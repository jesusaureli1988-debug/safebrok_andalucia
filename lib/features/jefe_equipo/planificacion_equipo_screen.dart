import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlanificacionEquipoScreen extends StatefulWidget {
  const PlanificacionEquipoScreen({super.key});

  @override
  State<PlanificacionEquipoScreen> createState() =>
      _PlanificacionEquipoScreenState();
}

class _PlanificacionEquipoScreenState extends State<PlanificacionEquipoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;

  List<Map<String, dynamic>> agentes = [];
  List<Map<String, dynamic>> planificaciones = [];

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  Future<void> cargarDatos() async {
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
          .eq('auth_id', user.id)
          .single();

      final jefeId = jefe['id'];

      final agentesData = await supabase
          .from('usuarios')
          .select()
          .eq('parent_id', jefeId)
          .eq('rol_usuario', 'agente');

      final idsAgentes = agentesData.map((e) => e['id']).toList();

      final planData = idsAgentes.isEmpty
          ? []
          : await supabase
              .from('planificacion_equipo')
              .select()
              .inFilter('agente_id', idsAgentes);

      if (!mounted) return;

      setState(() {
        agentes = List<Map<String, dynamic>>.from(agentesData);
        planificaciones = List<Map<String, dynamic>>.from(planData);
        loading = false;
      });
    } catch (e) {
      debugPrint("ERROR PLANIFICACION: $e");

      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Map<String, dynamic>? getPlan(dynamic agenteId) {
    try {
      return planificaciones.firstWhere(
        (p) => p['agente_id'] == agenteId,
      );
    } catch (_) {
      return null;
    }
  }

  int objetivoAgente(Map<String, dynamic> agente) {
    final plan = getPlan(agente['id']);
    return plan?['objetivo_contactos'] ?? 0;
  }

  int realizadoAgente(Map<String, dynamic> agente) {
    final plan = getPlan(agente['id']);
    return plan?['contactos_realizados'] ?? 0;
  }

  double progresoAgente(Map<String, dynamic> agente) {
    final objetivo = objetivoAgente(agente);
    final realizado = realizadoAgente(agente);

    if (objetivo == 0) return 0;
    return realizado / objetivo;
  }

  int get totalObjetivos {
    return agentes.fold<int>(0, (sum, a) => sum + objetivoAgente(a));
  }

  int get totalRealizado {
    return agentes.fold<int>(0, (sum, a) => sum + realizadoAgente(a));
  }

  double get promedioCumplimiento {
    if (agentes.isEmpty) return 0;

    final total = agentes.fold<double>(
      0,
      (sum, a) => sum + progresoAgente(a),
    );

    return total / agentes.length;
  }

  int get objetivosActivos {
    return agentes.where((a) => objetivoAgente(a) > 0).length;
  }

  Color colorProgreso(double progreso) {
    if (progreso >= 1) return const Color(0xFF22C55E);
    if (progreso >= 0.75) return const Color(0xFF22D3EE);
    if (progreso >= 0.50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String estadoTexto(double progreso) {
    if (progreso >= 1) return "Objetivo superado";
    if (progreso >= 0.50) return "En progreso";
    return "Por debajo";
  }

  IconData estadoIcono(double progreso) {
    if (progreso >= 1) return Icons.check_circle_rounded;
    if (progreso >= 0.50) return Icons.hourglass_bottom_rounded;
    return Icons.schedule_rounded;
  }

  String iniciales(Map<String, dynamic> agente) {
    final nombre = (agente['nombre'] ?? '').toString().trim();
    final apellidos = (agente['apellidos'] ?? '').toString().trim();

    final n = nombre.isNotEmpty ? nombre[0] : '';
    final a = apellidos.isNotEmpty ? apellidos[0] : '';

    final result = "$n$a".toUpperCase();
    return result.isEmpty ? "AG" : result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020B1F),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF22D3EE),
              ),
            )
          : RefreshIndicator(
              onRefresh: cargarDatos,
              color: const Color(0xFF22D3EE),
              backgroundColor: const Color(0xFF071A3A),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header()),

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
                          Icon(
                            Icons.manage_accounts_rounded,
                            color: Color(0xFF22D3EE),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Agentes del equipo",
                            style: TextStyle(
                              color: Colors.white,
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
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                          child: _agenteCard(agente),
                        );
                      },
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 40),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 54, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF020B1F),
            Color(0xFF061A3D),
            Color(0xFF020B1F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: 10,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF22D3EE).withOpacity(0.30),
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
                      backgroundColor: Colors.white.withOpacity(0.08),
                      fixedSize: const Size(48, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: cargarDatos,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.08),
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
                          Color(0xFF22D3EE),
                          Color(0xFF2563EB),
                          Color(0xFF7C3AED),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22D3EE).withOpacity(0.35),
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
                            text: "Planificación\n",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: "del equipo",
                            style: TextStyle(
                              color: Color(0xFF22D3EE),
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

              const Text(
                "Revisa el progreso y objetivos semanales de cada agente",
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 16,
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
    final promedio = (promedioCumplimiento * 100).round();

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            icono: Icons.groups_rounded,
            valor: "${agentes.length}",
            titulo: "Agentes\nen equipo",
            color: const Color(0xFF2563EB),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            icono: Icons.track_changes_rounded,
            valor: "$promedio%",
            titulo: "Promedio\ncumplimiento",
            color: const Color(0xFF14B8A6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _kpiCard(
            icono: Icons.trending_up_rounded,
            valor: "$objetivosActivos",
            titulo: "Objetivos\nactivos",
            color: const Color(0xFF8B5CF6),
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
          colors: [
            color.withOpacity(0.32),
            const Color(0xFF061329),
          ],
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
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.24),
              border: Border.all(color: color.withOpacity(0.40)),
            ),
            child: Icon(icono, color: Colors.white),
          ),
          const Spacer(),
          Text(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            titulo,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _agenteCard(Map<String, dynamic> agente) {
    final nombre =
        "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}".trim();

    final objetivo = objetivoAgente(agente);
    final realizado = realizadoAgente(agente);
    final progreso = progresoAgente(agente);
    final porcentaje = (progreso * 100).round();

    final color = colorProgreso(progreso);
    final estado = estadoTexto(progreso);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          splashColor: color.withOpacity(0.14),
          highlightColor: color.withOpacity(0.07),
          onTap: () {},
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF071A3A),
                  Color(0xFF061329),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: color.withOpacity(0.34)),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 86,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),

                const SizedBox(width: 12),

                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF2563EB),
                            Color(0xFF7C3AED),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.20),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          iniciales(agente),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF061329),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 14),

                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progreso.clamp(0.0, 1.4),
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withOpacity(0.10),
                        color: color,
                      ),
                      Text(
                        "$porcentaje%",
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
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
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Objetivo: $objetivo contactos",
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progreso.clamp(0.0, 1.0),
                          minHeight: 7,
                          backgroundColor: Colors.white.withOpacity(0.10),
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 7),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: "$realizado",
                              style: TextStyle(
                                color: color,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            TextSpan(
                              text: " / $objetivo contactos",
                              style: const TextStyle(
                                color: Color(0xFFE2E8F0),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: color.withOpacity(0.55)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            estadoIcono(progreso),
                            color: color,
                            size: 15,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            estado,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.07),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF22D3EE).withOpacity(0.12),
                border: Border.all(
                  color: const Color(0xFF22D3EE).withOpacity(0.35),
                ),
              ),
              child: const Icon(
                Icons.groups_rounded,
                color: Color(0xFF22D3EE),
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "No hay agentes asignados",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Cuando tengas agentes en tu equipo, aparecerán aquí con su planificación y progreso semanal.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}