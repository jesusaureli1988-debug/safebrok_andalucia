import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'planificacion_semana_detalle_screen.dart';
import 'planificacion_semanal_equipo_screen.dart';

class PlanificacionEquipoListScreen extends StatefulWidget {
  const PlanificacionEquipoListScreen({super.key});

  @override
  State<PlanificacionEquipoListScreen> createState() =>
      _PlanificacionEquipoListScreenState();
}

class _PlanificacionEquipoListScreenState
    extends State<PlanificacionEquipoListScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
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
          .eq('auth_id', user.id)
          .single();

      final data = await supabase
          .from('planificacion_semanal_equipo')
          .select()
          .eq('jefe_id', jefe['id'])
          .order('semana_inicio', ascending: false);

      final Map<String, Map<String, dynamic>> agrupado = {};

      for (final item in data) {
        final key = item['semana_inicio'];

        if (!agrupado.containsKey(key)) {
          agrupado[key] = {
            'semana_inicio': item['semana_inicio'],
            'semana_fin': item['semana_fin'],
            'agentes': <dynamic>[],
          };
        }

        agrupado[key]!['agentes'].add(item);
      }

      if (!mounted) return;

      setState(() {
        planificaciones = agrupado.values.toList();
        loading = false;
      });
    } catch (e) {
      debugPrint("ERROR CARGA PLANIFICACION: $e");

      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  String formatoFecha(DateTime fecha) {
    return "${fecha.day.toString().padLeft(2, '0')}/"
        "${fecha.month.toString().padLeft(2, '0')}/"
        "${fecha.year}";
  }

  String formatoSemana(DateTime inicio, DateTime fin) {
    return "${formatoFecha(inicio)} - ${formatoFecha(fin)}";
  }

  String mesCorto(DateTime fecha) {
    const meses = [
      'ENE',
      'FEB',
      'MAR',
      'ABR',
      'MAY',
      'JUN',
      'JUL',
      'AGO',
      'SEP',
      'OCT',
      'NOV',
      'DIC',
    ];

    return meses[fecha.month - 1];
  }

  bool esSemanaActual(DateTime inicio, DateTime fin) {
    final hoy = DateTime.now();
    final actual = DateTime(hoy.year, hoy.month, hoy.day);
    final i = DateTime(inicio.year, inicio.month, inicio.day);
    final f = DateTime(fin.year, fin.month, fin.day);

    return actual.isAtSameMomentAs(i) ||
        actual.isAtSameMomentAs(f) ||
        (actual.isAfter(i) && actual.isBefore(f));
  }

  int get totalSemanas => planificaciones.length;

  int get totalAgentesPlanificados {
    int total = 0;

    for (final p in planificaciones) {
      final agentes = p['agentes'] as List? ?? [];
      total += agentes.length;
    }

    return total;
  }

  int get semanasCompletadas {
    final hoy = DateTime.now();

    return planificaciones.where((p) {
      final fin = DateTime.parse(p['semana_fin']);
      return fin.isBefore(DateTime(hoy.year, hoy.month, hoy.day));
    }).length;
  }

  int get semanasActivas {
    return planificaciones.where((p) {
      final inicio = DateTime.parse(p['semana_inicio']);
      final fin = DateTime.parse(p['semana_fin']);
      return esSemanaActual(inicio, fin);
    }).length;
  }

  Future<void> nuevaPlanificacion() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PlanificacionSemanalEquipoScreen(),
      ),
    );

    if (res == true) {
      await cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020B1F),
      floatingActionButton: Container(
        width: 72,
        height: 72,
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
              color: const Color(0xFF22D3EE).withOpacity(0.45),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: FloatingActionButton(
          elevation: 0,
          backgroundColor: Colors.transparent,
          onPressed: nuevaPlanificacion,
          child: const Icon(
            Icons.add_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF22D3EE),
              ),
            )
          : RefreshIndicator(
              onRefresh: cargar,
              color: const Color(0xFF22D3EE),
              backgroundColor: const Color(0xFF061329),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _header(),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                      child: _kpiPanel(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.calendar_month_rounded,
                            color: Color(0xFF22D3EE),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Semanas planificadas",
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

                  if (planificaciones.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _emptyState(),
                    )
                  else
                    SliverList.builder(
                      itemCount: planificaciones.length,
                      itemBuilder: (context, i) {
                        final p = planificaciones[i];

                        final inicio = DateTime.parse(p['semana_inicio']);
                        final fin = DateTime.parse(p['semana_fin']);
                        final agentes = p['agentes'] as List? ?? [];

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                          child: _semanaCard(
                            semana: p,
                            inicio: inicio,
                            fin: fin,
                            agentes: agentes,
                            index: i,
                          ),
                        );
                      },
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 90),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 54, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF020B1F),
            Color(0xFF041635),
            Color(0xFF020B1F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: "Planificación del ",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  TextSpan(
                    text: "equipo",
                    style: TextStyle(
                      color: Color(0xFF22D3EE),
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  TextSpan(
                    text: "\nOrganiza, planifica y alcanza objetivos",
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: cargar,
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
    );
  }

  Widget _kpiPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _kpiItem(
              icono: Icons.calendar_month_rounded,
              valor: "$totalSemanas",
              titulo: "Semanas",
              color: const Color(0xFF8B5CF6),
            ),
          ),
          Expanded(
            child: _kpiItem(
              icono: Icons.groups_rounded,
              valor: "$totalAgentesPlanificados",
              titulo: "Agentes",
              color: const Color(0xFF22D3EE),
            ),
          ),
          Expanded(
            child: _kpiItem(
              icono: Icons.verified_rounded,
              valor: "$semanasCompletadas",
              titulo: "Cerradas",
              color: const Color(0xFF22C55E),
            ),
          ),
          Expanded(
            child: _kpiItem(
              icono: Icons.flash_on_rounded,
              valor: "$semanasActivas",
              titulo: "Activas",
              color: const Color(0xFFF59E0B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiItem({
    required IconData icono,
    required String valor,
    required String titulo,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withOpacity(0.14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Icon(icono, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          valor,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          titulo,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _semanaCard({
    required Map<String, dynamic> semana,
    required DateTime inicio,
    required DateTime fin,
    required List agentes,
    required int index,
  }) {
    final actual = esSemanaActual(inicio, fin);
    final completada = fin.isBefore(DateTime.now()) && !actual;

    final Color accent = actual
        ? const Color(0xFF22D3EE)
        : completada
            ? const Color(0xFF22C55E)
            : const Color(0xFF8B5CF6);

    final estado = actual
        ? "ACTUAL"
        : completada
            ? "COMPLETADA"
            : "PRÓXIMA";

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        splashColor: accent.withOpacity(0.16),
        highlightColor: accent.withOpacity(0.08),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlanificacionSemanaDetalleScreen(
                semana: semana,
              ),
            ),
          );
        },
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF071A3A),
                actual
                    ? const Color(0xFF24105A)
                    : const Color(0xFF071226),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: accent.withOpacity(actual ? 0.75 : 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(actual ? 0.22 : 0.08),
                blurRadius: actual ? 24 : 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _dateBox(inicio, accent),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (actual)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: accent.withOpacity(0.6)),
                        ),
                        child: Text(
                          estado,
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),

                    Text(
                      formatoSemana(inicio, fin),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      actual
                          ? "Semana actual"
                          : completada
                              ? "Semana completada"
                              : "Semana planificada",
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          color: accent,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${agentes.length} agentes",
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.06),
                  border: Border.all(color: accent.withOpacity(0.55)),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateBox(DateTime fecha, Color accent) {
    return Container(
      width: 76,
      height: 92,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.95),
            const Color(0xFF1E3A8A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            mesCorto(fecha),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            fecha.day.toString().padLeft(2, '0'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 33,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          Text(
            "${fecha.year}",
            style: const TextStyle(
              color: Color(0xFFE0F2FE),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
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
                Icons.calendar_month_rounded,
                color: Color(0xFF22D3EE),
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "No hay planificaciones creadas",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Crea la primera planificación semanal para organizar objetivos y actividad del equipo.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: nuevaPlanificacion,
              icon: const Icon(Icons.add_rounded),
              label: const Text("Crear planificación"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22D3EE),
                foregroundColor: const Color(0xFF020B1F),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}