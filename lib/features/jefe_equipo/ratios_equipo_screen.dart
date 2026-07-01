import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RatiosEquipoScreen extends StatefulWidget {
  const RatiosEquipoScreen({super.key});

  @override
  State<RatiosEquipoScreen> createState() => _RatiosEquipoScreenState();
}

class _RatiosEquipoScreenState extends State<RatiosEquipoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool refreshing = false;
  String? errorMessage;

  List<Map<String, dynamic>> agentesRatios = [];

  double ratioEquipo = 0;

  int contactosEquipo = 0;
  int positivosEquipo = 0;

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
          .select()
          .eq('auth_id', user.id)
          .single();

      final jefeId = jefe['id'];

      final agentes = await supabase
          .from('usuarios')
          .select()
          .eq('parent_id', jefeId)
          .eq('rol_usuario', 'agente')
          .order('nombre', ascending: true);

      final List<Map<String, dynamic>> resultado = [];

      int totalContactosEquipo = 0;
      int totalPositivosEquipo = 0;

      for (final agente in agentes) {
        final authId = agente['auth_id'];

        final contactos = await supabase
            .from('contactos_diarios')
            .select()
            .eq('auth_id', authId);

        int frios = 0;
        int telefonicos = 0;
        int positivos = 0;

        for (final c in contactos) {
          frios += ((c['contactos_frios'] ?? 0) as num).toInt();
          telefonicos += ((c['contactos_telefonicos'] ?? 0) as num).toInt();
          positivos += ((c['contactos_positivos'] ?? 0) as num).toInt();
        }

        final totalContactos = frios + telefonicos;

        final ratio = totalContactos == 0
            ? 0.0
            : (positivos / totalContactos) * 100;

        totalContactosEquipo += totalContactos;
        totalPositivosEquipo += positivos;

        resultado.add({
          'nombre': "${agente['nombre']} ${agente['apellidos'] ?? ''}".trim(),
          'contactos': totalContactos,
          'positivos': positivos,
          'ratio': ratio,
        });
      }

      resultado.sort(
        (a, b) => (b['ratio'] as double).compareTo(a['ratio'] as double),
      );

      final ratioMedioEquipo = totalContactosEquipo == 0
          ? 0.0
          : (totalPositivosEquipo / totalContactosEquipo) * 100;

      if (!mounted) return;

      setState(() {
        agentesRatios = resultado;
        contactosEquipo = totalContactosEquipo;
        positivosEquipo = totalPositivosEquipo;
        ratioEquipo = ratioMedioEquipo;
        loading = false;
        refreshing = false;
      });
    } catch (e) {
      debugPrint("ERROR RATIOS: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
        refreshing = false;
        errorMessage = "No se pudieron cargar los ratios del equipo";
      });
    }
  }

  Color colorRatio(double ratio) {
    if (ratio >= 20) return const Color(0xFF86EFAC);
    if (ratio >= 10) return const Color(0xFFFBBF24);
    return Colors.redAccent;
  }

  String estadoRatio(double ratio) {
    if (ratio >= 20) return "Excelente";
    if (ratio >= 10) return "Mejorable";
    return "Bajo";
  }

  String medalla(int index) {
    if (index == 0) return "🥇";
    if (index == 1) return "🥈";
    if (index == 2) return "🥉";
    return "🏅";
  }

  double get mejorRatio {
    if (agentesRatios.isEmpty) return 0;
    return agentesRatios.first['ratio'] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Ratios del equipo",
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
                        _HeaderPanel(
                          ratioEquipo: ratioEquipo,
                          contactosEquipo: contactosEquipo,
                          positivosEquipo: positivosEquipo,
                          agentes: agentesRatios.length,
                          color: colorRatio(ratioEquipo),
                          estado: estadoRatio(ratioEquipo),
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
                          contactosEquipo: contactosEquipo,
                          positivosEquipo: positivosEquipo,
                          agentes: agentesRatios.length,
                          mejorRatio: mejorRatio,
                        ),
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          title: "Ranking de agentes",
                          subtitle: "Conversión de contactos en positivos",
                        ),
                        const SizedBox(height: 12),
                        if (agentesRatios.isEmpty)
                          const _EmptyState()
                        else
                          ...List.generate(
                            agentesRatios.length,
                            (index) {
                              final a = agentesRatios[index];
                              final ratio = a['ratio'] as double;

                              return _AgentRatioCard(
                                position: index + 1,
                                medal: medalla(index),
                                nombre: a['nombre'],
                                contactos: a['contactos'],
                                positivos: a['positivos'],
                                ratio: ratio,
                                color: colorRatio(ratio),
                                estado: estadoRatio(ratio),
                              );
                            },
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

class _HeaderPanel extends StatelessWidget {
  final double ratioEquipo;
  final int contactosEquipo;
  final int positivosEquipo;
  final int agentes;
  final Color color;
  final String estado;

  const _HeaderPanel({
    required this.ratioEquipo,
    required this.contactosEquipo,
    required this.positivosEquipo,
    required this.agentes,
    required this.color,
    required this.estado,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (ratioEquipo / 25).clamp(0.0, 1.0);

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
                  Icons.analytics_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Ratio medio equipo",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Contactos positivos sobre contactos totales",
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${ratioEquipo.toStringAsFixed(1)}%",
                style: TextStyle(
                  color: color,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _StatusChip(
                  text: estado,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeaderMiniMetric(
                  title: "Contactos",
                  value: contactosEquipo.toString(),
                  icon: Icons.call_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderMiniMetric(
                  title: "Positivos",
                  value: positivosEquipo.toString(),
                  icon: Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderMiniMetric(
                  title: "Agentes",
                  value: agentes.toString(),
                  icon: Icons.groups_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusChip({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.28),
        ),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _HeaderMiniMetric extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _HeaderMiniMetric({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: const Color(0xFF7DD3FC),
            size: 20,
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.48),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final int contactosEquipo;
  final int positivosEquipo;
  final int agentes;
  final double mejorRatio;

  const _KpiGrid({
    required this.contactosEquipo,
    required this.positivosEquipo,
    required this.agentes,
    required this.mejorRatio,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            title: "Contactos",
            value: contactosEquipo.toString(),
            icon: Icons.phone_in_talk_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            title: "Positivos",
            value: positivosEquipo.toString(),
            icon: Icons.verified_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _KpiCard(
            title: "Mejor ratio",
            value: "${mejorRatio.toStringAsFixed(1)}%",
            icon: Icons.emoji_events_rounded,
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
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.52),
              fontSize: 10.5,
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
          Icons.leaderboard_rounded,
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

class _AgentRatioCard extends StatelessWidget {
  final int position;
  final String medal;
  final String nombre;
  final int contactos;
  final int positivos;
  final double ratio;
  final Color color;
  final String estado;

  const _AgentRatioCard({
    required this.position,
    required this.medal,
    required this.nombre,
    required this.contactos,
    required this.positivos,
    required this.ratio,
    required this.color,
    required this.estado,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (ratio / 25).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: color.withOpacity(position <= 3 ? 0.32 : 0.18),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                medal,
                style: const TextStyle(fontSize: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "$positivos positivos · $contactos contactos",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${ratio.toStringAsFixed(1)}%",
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    estado,
                    style: TextStyle(
                      color: color.withOpacity(0.85),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
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
            Icons.analytics_outlined,
            size: 48,
            color: Colors.white.withOpacity(0.35),
          ),
          const SizedBox(height: 14),
          const Text(
            "Sin ratios disponibles",
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            "Cuando los agentes registren contactos diarios aparecerá aquí el ranking de conversión.",
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