import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlanificacionSemanaDetalleScreen extends StatefulWidget {
  final Map semana;

  const PlanificacionSemanaDetalleScreen({super.key, required this.semana});

  @override
  State<PlanificacionSemanaDetalleScreen> createState() =>
      _PlanificacionSemanaDetalleScreenState();
}

class _PlanificacionSemanaDetalleScreenState
    extends State<PlanificacionSemanaDetalleScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;

  List<Map<String, dynamic>> agentes = [];
  List<Map<String, dynamic>> planificaciones = [];

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    try {
      setState(() => loading = true);

      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() => loading = false);
        return;
      }

      final jefe = await supabase
          .from('usuarios')
          .select('id')
          .or(
            'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
          )
          .eq('auth_id', user.id)
          .single();

      final agentesData = await supabase
          .from('usuarios')
          .select()
          .or(
            'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
          )
          .eq('parent_id', jefe['id'])
          .eq('rol_usuario', 'agente')
          .order('nombre', ascending: true);

      final planData = await supabase
          .from('planificacion_semanal_equipo')
          .select()
          .eq('jefe_id', jefe['id'])
          .eq('semana_inicio', widget.semana['semana_inicio']);

      if (!mounted) return;

      setState(() {
        agentes = List<Map<String, dynamic>>.from(agentesData);
        planificaciones = List<Map<String, dynamic>>.from(planData);
        loading = false;
      });
    } catch (e) {
      debugPrint("ERROR DETALLE SEMANA: $e");

      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Map<String, dynamic>? getPlan(dynamic agenteId) {
    try {
      return planificaciones.firstWhere((p) => p['agente_id'] == agenteId);
    } catch (_) {
      return null;
    }
  }

  String formatoFecha(DateTime fecha) {
    return "${fecha.day.toString().padLeft(2, '0')}/"
        "${fecha.month.toString().padLeft(2, '0')}/"
        "${fecha.year}";
  }

  int diasPlanificados(Map<String, dynamic>? plan) {
    if (plan == null) return 0;

    int total = 0;

    if ((plan['lunes'] ?? '').toString().trim().isNotEmpty) total++;
    if ((plan['martes'] ?? '').toString().trim().isNotEmpty) total++;
    if ((plan['miercoles'] ?? '').toString().trim().isNotEmpty) total++;
    if ((plan['jueves'] ?? '').toString().trim().isNotEmpty) total++;
    if ((plan['viernes'] ?? '').toString().trim().isNotEmpty) total++;

    return total;
  }

  int get agentesPlanificados {
    return agentes.where((a) => getPlan(a['id']) != null).length;
  }

  int get totalDiasPlanificados {
    int total = 0;

    for (final a in agentes) {
      total += diasPlanificados(getPlan(a['id']));
    }

    return total;
  }

  double get progresoSemana {
    if (agentes.isEmpty) return 0;
    return totalDiasPlanificados / (agentes.length * 5);
  }

  Color colorProgreso(int dias) {
    if (dias == 5) return const Color(0xFF0AAEAE);
    if (dias >= 3) return const Color(0xFF20C7C2);
    if (dias >= 1) return const Color(0xFF0A7F91);
    return const Color(0xFFE74646);
  }

  String estadoTexto(int dias) {
    if (dias == 5) return "Semana completa";
    if (dias >= 1) return "Parcial";
    return "Sin planificar";
  }

  @override
  Widget build(BuildContext context) {
    final inicio = DateTime.parse(widget.semana['semana_inicio']);
    final fin = DateTime.parse(widget.semana['semana_fin']);

    return Scaffold(
      backgroundColor: const Color(0xFFF2FCFD),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF20C7C2)),
            )
          : RefreshIndicator(
              onRefresh: cargar,
              color: const Color(0xFF20C7C2),
              backgroundColor: const Color(0xFFFFFFFF),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header(inicio, fin)),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                      child: _kpiPanel(),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Row(
                        children: const [
                          Icon(Icons.groups_rounded, color: Color(0xFF20C7C2)),
                          SizedBox(width: 10),
                          Text(
                            "Planificación por agente",
                            style: TextStyle(
                              color: const Color(0xFF071A3A),
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (agentes.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(),
                    )
                  else
                    SliverList.builder(
                      itemCount: agentes.length,
                      itemBuilder: (context, i) {
                        final agente = agentes[i];
                        final plan = getPlan(agente['id']);

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                          child: _agenteCard(agente: agente, plan: plan),
                        );
                      },
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
    );
  }

  Widget _header(DateTime inicio, DateTime fin) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 54, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF2FCFD), Color(0xFFFFFFFF), Color(0xFFF2FCFD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: 20,
            child: Container(
              width: 165,
              height: 165,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF20C7C2).withOpacity(0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      fixedSize: const Size(48, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: cargar,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      fixedSize: const Size(48, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF20C7C2),
                          Color(0xFF0A7F91),
                          Color(0xFF0A7F91),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF20C7C2).withOpacity(0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text: "Semana\n",
                            style: TextStyle(
                              color: const Color(0xFF071A3A),
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: "del equipo",
                            style: TextStyle(
                              color: Color(0xFF20C7C2),
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Text(
                "${formatoFecha(inicio)} - ${formatoFecha(fin)}",
                style: const TextStyle(
                  color: Color(0xFFC7ECEC),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                "Revisa la planificación diaria de cada agente durante la semana seleccionada.",
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiPanel() {
    final porcentaje = (progresoSemana * 100).round();

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            icono: Icons.groups_rounded,
            valor: "${agentes.length}",
            titulo: "Agentes\ndel equipo",
            color: const Color(0xFF0A7F91),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            icono: Icons.task_alt_rounded,
            valor: "$agentesPlanificados",
            titulo: "Agentes\nplanificados",
            color: const Color(0xFF0AAEAE),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            icono: Icons.track_changes_rounded,
            valor: "$porcentaje%",
            titulo: "Semana\ncubierta",
            color: const Color(0xFF0A7F91),
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required IconData icono,
    required String valor,
    required String titulo,
    required Color color,
  }) {
    return Container(
      height: 142,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.32), const Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.38)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: Colors.white, size: 28),
          const Spacer(),
          Text(
            valor,
            style: const TextStyle(
              color: const Color(0xFF071A3A),
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            titulo,
            style: const TextStyle(
              color: Color(0xFFC7ECEC),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _agenteCard({
    required Map<String, dynamic> agente,
    required Map<String, dynamic>? plan,
  }) {
    final nombre = "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}"
        .trim();

    final dias = diasPlanificados(plan);
    final progreso = dias / 5;
    final color = colorProgreso(dias);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withOpacity(0.34)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 5,
                  height: 58,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(width: 12),

                CircleAvatar(
                  radius: 27,
                  backgroundColor: color.withOpacity(0.18),
                  child: Text(
                    _iniciales(agente),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre.isEmpty ? "Agente sin nombre" : nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: const Color(0xFF071A3A),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$dias/5 días planificados",
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: color.withOpacity(0.55)),
                  ),
                  child: Text(
                    estadoTexto(dias),
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 7,
                backgroundColor: Colors.white,
                color: color,
              ),
            ),

            const SizedBox(height: 16),

            _dia("Lunes", plan?['lunes'], const Color(0xFF20C7C2)),
            _dia("Martes", plan?['martes'], const Color(0xFF0A7F91)),
            _dia("Miércoles", plan?['miercoles'], const Color(0xFF0A7F91)),
            _dia("Jueves", plan?['jueves'], const Color(0xFF0A7F91)),
            _dia("Viernes", plan?['viernes'], const Color(0xFF0AAEAE)),
          ],
        ),
      ),
    );
  }

  Widget _dia(String dia, dynamic valor, Color color) {
    final texto = (valor ?? '').toString().trim();
    final tienePlan = texto.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tienePlan ? color.withOpacity(0.34) : Colors.white,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              tienePlan ? Icons.check_rounded : Icons.remove_rounded,
              color: tienePlan ? color : const Color(0xFF64748B),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 82,
            child: Text(
              dia,
              style: TextStyle(
                color: tienePlan ? Colors.white : const Color(0xFF64748B),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              tienePlan ? texto : "Sin planificar",
              style: TextStyle(
                color: tienePlan
                    ? const Color(0xFFC7ECEC)
                    : const Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _iniciales(Map<String, dynamic> agente) {
    final nombre = (agente['nombre'] ?? '').toString().trim();
    final apellidos = (agente['apellidos'] ?? '').toString().trim();

    final n = nombre.isNotEmpty ? nombre[0] : '';
    final a = apellidos.isNotEmpty ? apellidos[0] : '';

    final result = "$n$a".toUpperCase();
    return result.isEmpty ? "AG" : result;
  }

  Widget _emptyState() {
    return const Center(
      child: Text(
        "No hay agentes asignados",
        style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
      ),
    );
  }
}
