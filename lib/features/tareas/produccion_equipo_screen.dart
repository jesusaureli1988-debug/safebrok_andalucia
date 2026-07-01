import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProduccionEquipoScreen extends StatefulWidget {
  const ProduccionEquipoScreen({super.key});

  @override
  State<ProduccionEquipoScreen> createState() => _ProduccionEquipoScreenState();
}

class _ProduccionEquipoScreenState extends State<ProduccionEquipoScreen> {
  final supabase = Supabase.instance.client;

  double produccionEquipo = 0;
  int ventasHoy = 0;

  List<Map<String, dynamic>> ranking = [];

  bool loading = true;
  bool refreshing = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  Future<void> cargarDatos({bool isRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      if (isRefresh) {
        refreshing = true;
      } else {
        loading = true;
      }
      errorMessage = null;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() {
          loading = false;
          refreshing = false;
          errorMessage = "Usuario no autenticado";
        });
        return;
      }

      final jefe = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', user.id)
          .maybeSingle();

      if (jefe == null) {
        if (!mounted) return;
        setState(() {
          loading = false;
          refreshing = false;
          errorMessage = "No se encontró el jefe de equipo";
        });
        return;
      }

      final jefeId = jefe['id'];

      final agentes = await supabase
          .from('usuarios')
          .select('auth_id,nombre')
          .eq('parent_id', jefeId)
          .order('nombre', ascending: true);

      if (agentes.isEmpty) {
        if (!mounted) return;
        setState(() {
          produccionEquipo = 0;
          ventasHoy = 0;
          ranking = [];
          loading = false;
          refreshing = false;
        });
        return;
      }

      final agentesIds = agentes.map((a) => a['auth_id']).toList();

      final ventas = await supabase
          .from('ventas')
          .select('agente_auth_id, prima_anual_neta, fecha_efecto')
          .inFilter('agente_auth_id', agentesIds);

      double total = 0;
      int hoy = 0;

      final mapaProduccion = <String, double>{};
      final ahora = DateTime.now();

      for (final venta in ventas) {
        final primaRaw = venta['prima_anual_neta'];
        final prima = primaRaw is num
            ? primaRaw.toDouble()
            : double.tryParse(primaRaw?.toString() ?? '0') ?? 0;

        total += prima;

        final authId = venta['agente_auth_id'];

        mapaProduccion[authId] = (mapaProduccion[authId] ?? 0) + prima;

        final fechaRaw = venta['fecha_efecto'];

        if (fechaRaw != null) {
          final fecha = DateTime.tryParse(fechaRaw.toString());

          if (fecha != null &&
              fecha.year == ahora.year &&
              fecha.month == ahora.month &&
              fecha.day == ahora.day) {
            hoy++;
          }
        }
      }

      final rankingTemp = <Map<String, dynamic>>[];

      for (final agente in agentes) {
        final authId = agente['auth_id'];

        rankingTemp.add({
          "nombre": agente['nombre'] ?? "Sin nombre",
          "produccion": mapaProduccion[authId] ?? 0,
        });
      }

      rankingTemp.sort(
        (a, b) => b['produccion'].compareTo(a['produccion']),
      );

      if (!mounted) return;

      setState(() {
        produccionEquipo = total;
        ventasHoy = hoy;
        ranking = rankingTemp;
        loading = false;
        refreshing = false;
      });
    } catch (e) {
      debugPrint("ERROR PRODUCCION EQUIPO: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
        refreshing = false;
        errorMessage = "No se pudo cargar la producción del equipo";
      });
    }
  }

  double get mejorProduccion {
    if (ranking.isEmpty) return 0;
    return ranking.first['produccion'] ?? 0;
  }

  double get mediaProduccion {
    if (ranking.isEmpty) return 0;
    return produccionEquipo / ranking.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Producción equipo",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: "Actualizar",
            onPressed: refreshing ? null : () => cargarDatos(isRefresh: true),
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF38BDF8),
                    backgroundColor: const Color(0xFF0F172A),
                    onRefresh: () => cargarDatos(isRefresh: true),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: [
                        _HeaderCard(
                          produccionEquipo: produccionEquipo,
                          ventasHoy: ventasHoy,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBox(
                            message: errorMessage!,
                            onRetry: () => cargarDatos(),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _KpiGrid(
                          agentes: ranking.length,
                          ventasHoy: ventasHoy,
                          mediaProduccion: mediaProduccion,
                          mejorProduccion: mejorProduccion,
                        ),
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          title: "Ranking equipo",
                          subtitle: "Producción acumulada por agente",
                        ),
                        const SizedBox(height: 12),
                        if (ranking.isEmpty)
                          const _EmptyState()
                        else
                          ...ranking.asMap().entries.map(
                                (entry) => _RankingCard(
                                  position: entry.key + 1,
                                  nombre: entry.value['nombre'],
                                  produccion: entry.value['produccion'],
                                  maxProduccion: mejorProduccion,
                                ),
                              ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF07111B),
                Color(0xFF0B1F2E),
                Color(0xFF12384E),
              ],
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -80,
          child: _GlowCircle(
            size: 230,
            color: const Color(0xFF38BDF8).withOpacity(0.24),
          ),
        ),
        Positioned(
          bottom: -120,
          left: -90,
          child: _GlowCircle(
            size: 260,
            color: const Color(0xFF22C55E).withOpacity(0.16),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
          child: Container(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final double produccionEquipo;
  final int ventasHoy;

  const _HeaderCard({
    required this.produccionEquipo,
    required this.ventasHoy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF38BDF8),
                      Color(0xFF2563EB),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Producción total",
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Equipo comercial",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            "${produccionEquipo.toStringAsFixed(0)} €",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 10),
          _MiniChip(
            icon: Icons.today_rounded,
            text: "$ventasHoy ventas hoy",
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniChip({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF22C55E).withOpacity(0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: const Color(0xFF86EFAC),
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFBBF7D0),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final int agentes;
  final int ventasHoy;
  final double mediaProduccion;
  final double mejorProduccion;

  const _KpiGrid({
    required this.agentes,
    required this.ventasHoy,
    required this.mediaProduccion,
    required this.mejorProduccion,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            title: "Agentes",
            value: agentes.toString(),
            icon: Icons.groups_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            title: "Hoy",
            value: ventasHoy.toString(),
            icon: Icons.flash_on_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            title: "Media",
            value: "${mediaProduccion.toStringAsFixed(0)}€",
            icon: Icons.analytics_rounded,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: const Color(0xFF7DD3FC),
            size: 23,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.52),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.emoji_events_rounded,
          color: Color(0xFF7DD3FC),
          size: 23,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RankingCard extends StatelessWidget {
  final int position;
  final String nombre;
  final double produccion;
  final double maxProduccion;

  const _RankingCard({
    required this.position,
    required this.nombre,
    required this.produccion,
    required this.maxProduccion,
  });

  @override
  Widget build(BuildContext context) {
    final percent = maxProduccion <= 0 ? 0.0 : produccion / maxProduccion;

    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: position == 1
              ? const Color(0xFF38BDF8).withOpacity(0.28)
              : Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PositionBadge(position: position),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "${produccion.toStringAsFixed(0)} €",
                style: const TextStyle(
                  color: Color(0xFFBBF7D0),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: percent.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF38BDF8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionBadge extends StatelessWidget {
  final int position;

  const _PositionBadge({
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final bool isFirst = position == 1;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isFirst
            ? const LinearGradient(
                colors: [
                  Color(0xFF38BDF8),
                  Color(0xFF2563EB),
                ],
              )
            : null,
        color: isFirst ? null : Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Center(
        child: Text(
          "$position",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.groups_2_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.35),
          ),
          const SizedBox(height: 14),
          const Text(
            "Sin agentes o producción",
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            "Cuando tu equipo tenga agentes y ventas registradas aparecerá aquí el ranking de producción.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text("Reintentar"),
          ),
        ],
      ),
    );
  }
}