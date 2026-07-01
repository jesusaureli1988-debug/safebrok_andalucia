import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ContactosDiariosEquipoScreen extends StatefulWidget {
  const ContactosDiariosEquipoScreen({super.key});

  @override
  State<ContactosDiariosEquipoScreen> createState() =>
      _ContactosDiariosEquipoScreenState();
}

class _ContactosDiariosEquipoScreenState
    extends State<ContactosDiariosEquipoScreen> {
  final supabase = Supabase.instance.client;

  String? filtroAgente;
  int? filtroMes;
  int? filtroAnio = DateTime.now().year;

  List<Map<String, dynamic>> agentesList = [];
  List<Map<String, dynamic>> agentes = [];

  int contactosPositivosHoy = 0;

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
          .single();

      final jefeId = jefe['id'];

      final usuarios = await supabase
          .from('usuarios')
          .select('id, auth_id, nombre, apellidos')
          .eq('parent_id', jefeId)
          .order('nombre', ascending: true);

      agentesList = List<Map<String, dynamic>>.from(usuarios);

      final agentesAuthIds = agentesList.map((e) => e['auth_id']).toList();

      if (agentesAuthIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          agentes = [];
          contactosPositivosHoy = 0;
          loading = false;
          refreshing = false;
        });
        return;
      }

      final data = await supabase
          .from('contactos_diarios')
          .select('auth_id, contactos_positivos, created_at')
          .inFilter('auth_id', agentesAuthIds);

      int totalGlobal = 0;
      final Map<String, Map<String, dynamic>> porDia = {};

      for (final r in data) {
        final fechaRaw = r['created_at'];
        if (fechaRaw == null) continue;

        final fecha = DateTime.tryParse(fechaRaw.toString());
        if (fecha == null) continue;

        if (filtroAnio != null && fecha.year != filtroAnio) continue;
        if (filtroMes != null && fecha.month != filtroMes) continue;
        if (filtroAgente != null && r['auth_id'] != filtroAgente) continue;

        final dia =
            "${fecha.day.toString().padLeft(2, '0')}/"
            "${fecha.month.toString().padLeft(2, '0')}/"
            "${fecha.year}";

        final agente = agentesList.firstWhere(
          (a) => a['auth_id'] == r['auth_id'],
          orElse: () => {
            'nombre': 'Agente',
            'apellidos': 'no encontrado',
          },
        );

        final positivosRaw = r['contactos_positivos'];
        final positivos = positivosRaw is int
            ? positivosRaw
            : int.tryParse(positivosRaw?.toString() ?? '0') ?? 0;

        totalGlobal += positivos;

        porDia.putIfAbsent(
          dia,
          () => {
            "fecha": dia,
            "fechaOrden": fecha,
            "detalles": <Map<String, dynamic>>[],
            "total": 0,
          },
        );

        porDia[dia]!["detalles"].add({
          "nombre": "${agente['nombre']} ${agente['apellidos']}".trim(),
          "positivos": positivos,
        });

        porDia[dia]!["total"] += positivos;
      }

      final resultado = porDia.values.toList();

      resultado.sort((a, b) {
        final fa = a['fechaOrden'] as DateTime;
        final fb = b['fechaOrden'] as DateTime;
        return fb.compareTo(fa);
      });

      if (!mounted) return;

      setState(() {
        contactosPositivosHoy = totalGlobal;
        agentes = resultado;
        loading = false;
        refreshing = false;
      });
    } catch (e) {
      debugPrint("❌ ERROR CONTACTOS EQUIPO: $e");

      if (!mounted) return;

      setState(() {
        loading = false;
        refreshing = false;
        errorMessage = "No se pudieron cargar los contactos del equipo";
      });
    }
  }

  int get objetivoEquipo => agentesList.length * 18;

  double get cumplimiento {
    if (objetivoEquipo == 0) return 0;
    return contactosPositivosHoy / objetivoEquipo;
  }

  String get filtroTexto {
    final partes = <String>[];

    if (filtroAgente != null) {
      final agente = agentesList.firstWhere(
        (a) => a['auth_id'] == filtroAgente,
        orElse: () => {},
      );

      if (agente.isNotEmpty) {
        partes.add("${agente['nombre']} ${agente['apellidos']}".trim());
      }
    } else {
      partes.add("Todo el equipo");
    }

    if (filtroMes != null) partes.add("Mes $filtroMes");
    if (filtroAnio != null) partes.add("$filtroAnio");

    return partes.join(" · ");
  }

  void limpiarFiltros() {
    setState(() {
      filtroAgente = null;
      filtroMes = null;
      filtroAnio = DateTime.now().year;
    });

    cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Contactos diarios equipo",
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
                          totalContactos: contactosPositivosHoy,
                          objetivoEquipo: objetivoEquipo,
                          agentes: agentesList.length,
                          cumplimiento: cumplimiento,
                          filtroTexto: filtroTexto,
                        ),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBox(
                            message: errorMessage!,
                            onRetry: () => cargarDatos(),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _FiltersPanel(
                          agentesList: agentesList,
                          filtroAgente: filtroAgente,
                          filtroMes: filtroMes,
                          filtroAnio: filtroAnio,
                          onAgenteChanged: (value) {
                            setState(() => filtroAgente = value);
                            cargarDatos();
                          },
                          onMesChanged: (value) {
                            setState(() => filtroMes = value);
                            cargarDatos();
                          },
                          onAnioChanged: (value) {
                            setState(() => filtroAnio = value);
                            cargarDatos();
                          },
                          onClear: limpiarFiltros,
                        ),
                        const SizedBox(height: 24),
                        const _SectionTitle(
                          title: "Detalle diario",
                          subtitle: "Contactos positivos agrupados por día",
                        ),
                        const SizedBox(height: 12),
                        if (agentes.isEmpty)
                          const _EmptyState()
                        else
                          ...agentes.map(
                            (dia) => _DayCard(dia: dia),
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
  final int totalContactos;
  final int objetivoEquipo;
  final int agentes;
  final double cumplimiento;
  final String filtroTexto;

  const _HeaderPanel({
    required this.totalContactos,
    required this.objetivoEquipo,
    required this.agentes,
    required this.cumplimiento,
    required this.filtroTexto,
  });

  @override
  Widget build(BuildContext context) {
    final progress = cumplimiento.clamp(0.0, 1.0);

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
                  Icons.call_made_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Contactos positivos",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      filtroTexto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            "$totalContactos",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Objetivo equipo diario: $objetivoEquipo contactos",
            style: const TextStyle(
              color: Color(0xFFBAE6FD),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF38BDF8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  title: "Agentes",
                  value: agentes.toString(),
                  icon: Icons.groups_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniMetric(
                  title: "Cumplimiento",
                  value: "${(cumplimiento * 100).toStringAsFixed(0)}%",
                  icon: Icons.verified_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MiniMetric({
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
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF7DD3FC),
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  final List<Map<String, dynamic>> agentesList;
  final String? filtroAgente;
  final int? filtroMes;
  final int? filtroAnio;
  final ValueChanged<String?> onAgenteChanged;
  final ValueChanged<int?> onMesChanged;
  final ValueChanged<int?> onAnioChanged;
  final VoidCallback onClear;

  const _FiltersPanel({
    required this.agentesList,
    required this.filtroAgente,
    required this.filtroMes,
    required this.filtroAnio,
    required this.onAgenteChanged,
    required this.onMesChanged,
    required this.onAnioChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        filtroAgente != null || filtroMes != null || filtroAnio != DateTime.now().year;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Filtros",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (hasFilters)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: const Text("Limpiar"),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DropContainer(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filtroAgente,
                isExpanded: true,
                dropdownColor: const Color(0xFF102331),
                iconEnabledColor: Colors.white70,
                hint: const Text(
                  "Todo el equipo",
                  style: TextStyle(color: Colors.white),
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text("Todo el equipo"),
                  ),
                  ...agentesList.map(
                    (a) => DropdownMenuItem<String?>(
                      value: a['auth_id'],
                      child: Text(
                        "${a['nombre']} ${a['apellidos']}".trim(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: onAgenteChanged,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DropContainer(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: filtroMes,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF102331),
                      iconEnabledColor: Colors.white70,
                      hint: const Text(
                        "Mes",
                        style: TextStyle(color: Colors.white),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text("Todos"),
                        ),
                        ...List.generate(
                          12,
                          (i) => DropdownMenuItem<int?>(
                            value: i + 1,
                            child: Text("Mes ${i + 1}"),
                          ),
                        ),
                      ],
                      onChanged: onMesChanged,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DropContainer(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: filtroAnio,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF102331),
                      iconEnabledColor: Colors.white70,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      items: [2025, 2026, 2027].map(
                        (y) {
                          return DropdownMenuItem<int?>(
                            value: y,
                            child: Text("$y"),
                          );
                        },
                      ).toList(),
                      onChanged: onAnioChanged,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DropContainer extends StatelessWidget {
  final Widget child;

  const _DropContainer({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: child,
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
          Icons.view_day_rounded,
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

class _DayCard extends StatelessWidget {
  final Map<String, dynamic> dia;

  const _DayCard({
    required this.dia,
  });

  @override
  Widget build(BuildContext context) {
    final List detalles = (dia['detalles'] as List?) ?? [];
    final total = dia['total'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF2563EB),
                      Color(0xFF38BDF8),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dia['fecha'] ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "Total del día: $total contactos",
                      style: const TextStyle(
                        color: Color(0xFFBAE6FD),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...detalles.map(
            (a) => _AgentContactRow(
              nombre: a['nombre'] ?? 'Agente',
              positivos: a['positivos'] ?? 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentContactRow extends StatelessWidget {
  final String nombre;
  final int positivos;

  const _AgentContactRow({
    required this.nombre,
    required this.positivos,
  });

  @override
  Widget build(BuildContext context) {
    final cumplido = positivos >= 6;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cumplido
              ? const Color(0xFF22C55E).withOpacity(0.20)
              : Colors.redAccent.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            cumplido ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: cumplido ? const Color(0xFF86EFAC) : Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.78),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "$positivos",
            style: TextStyle(
              color: cumplido ? const Color(0xFFBBF7D0) : Colors.redAccent,
              fontSize: 15,
              fontWeight: FontWeight.w900,
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
            Icons.call_missed_outgoing_rounded,
            size: 48,
            color: Colors.white.withOpacity(0.35),
          ),
          const SizedBox(height: 14),
          const Text(
            "Sin contactos en este filtro",
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            "Cuando el equipo registre contactos diarios aparecerán agrupados por fecha.",
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
