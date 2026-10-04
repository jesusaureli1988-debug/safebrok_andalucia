import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detalle_tarea_jefe_screen.dart';

class MisContactosDiariosJefeScreen extends StatefulWidget {
  const MisContactosDiariosJefeScreen({super.key});

  @override
  State<MisContactosDiariosJefeScreen> createState() =>
      _MisContactosDiariosJefeScreenState();
}

class _MisContactosDiariosJefeScreenState
    extends State<MisContactosDiariosJefeScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  List<Map<String, dynamic>> tareas = [];

  @override
  void initState() {
    super.initState();
    cargarTareas();
  }

  String _formatearFecha(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  bool _esDiaLaborable(DateTime date) {
    return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
  }

  int get totalDias => tareas.length;

  int get diasRealizados => tareas.where((t) => t['realizada'] == true).length;

  int get diasPendientes => tareas.where((t) => t['realizada'] != true).length;

  int get contactosTotales => tareas.fold<int>(
    0,
    (sum, t) => sum + ((t['total_contactos'] ?? 0) as num).toInt(),
  );

  int get contactosEquipo => tareas.fold<int>(
    0,
    (sum, t) => sum + ((t['contactos_equipo'] ?? 0) as num).toInt(),
  );

  int get contactosPropios => tareas.fold<int>(
    0,
    (sum, t) => sum + ((t['contactos_propios'] ?? 0) as num).toInt(),
  );

  double get porcentajeCompletado {
    if (totalDias == 0) return 0;
    return diasRealizados / totalDias;
  }

  String _fechaBonita(dynamic value) {
    try {
      final fecha = DateTime.parse(value.toString());
      return "${fecha.day.toString().padLeft(2, '0')}/"
          "${fecha.month.toString().padLeft(2, '0')}/"
          "${fecha.year}";
    } catch (_) {
      return "Sin fecha";
    }
  }

  Future<void> cargarTareas() async {
    try {
      setState(() => loading = true);

      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() {
          tareas = [];
          loading = false;
        });
        return;
      }

      final hoy = DateTime.now();

      // 1. Cargamos primero las tareas existentes
      final tareasExistentes = await supabase
          .from('contactos_diarios_jefe_equipo')
          .select()
          .eq('auth_id', user.id)
          .order('fecha', ascending: true);

      final listaExistente = List<Map<String, dynamic>>.from(
        tareasExistentes as List,
      );

      // 2. Intentamos sacar la fecha de alta del usuario
      DateTime inicioDiario;

      try {
        final userData = await supabase
            .from('usuarios')
            .select('fecha_alta, created_at')
            .or(
              'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
            )
            .eq('auth_id', user.id)
            .maybeSingle();

        final fechaAltaRaw = userData?['fecha_alta'] ?? userData?['created_at'];

        inicioDiario = DateTime.parse(fechaAltaRaw.toString());
      } catch (_) {
        // Si falla, usamos la primera tarea existente
        if (listaExistente.isNotEmpty) {
          inicioDiario = DateTime.parse(
            listaExistente.first['fecha'].toString(),
          );
        } else {
          inicioDiario = DateTime(hoy.year, hoy.month, 1);
        }
      }

      final fechasExistentes = listaExistente
          .map((e) => e['fecha'].toString().substring(0, 10))
          .toSet();

      final List<Map<String, dynamic>> insertar = [];

      DateTime dia = DateTime(
        inicioDiario.year,
        inicioDiario.month,
        inicioDiario.day,
      );

      while (!dia.isAfter(hoy)) {
        if (_esDiaLaborable(dia)) {
          final fecha = _formatearFecha(dia);

          if (!fechasExistentes.contains(fecha)) {
            insertar.add({
              'auth_id': user.id,
              'fecha': fecha,
              'contactos_equipo': 0,
              'contactos_propios': 0,
              'total_contactos': 0,
              'realizada': false,
            });
          }
        }

        dia = dia.add(const Duration(days: 1));
      }

      if (insertar.isNotEmpty) {
        await supabase.from('contactos_diarios_jefe_equipo').insert(insertar);
      }

      // 3. Volvemos a cargar todo, ya con los días creados
      final data = await supabase
          .from('contactos_diarios_jefe_equipo')
          .select()
          .eq('auth_id', user.id)
          .order('fecha', ascending: false);

      setState(() {
        tareas = List<Map<String, dynamic>>.from(data as List);
        loading = false;
      });
    } catch (e) {
      setState(() {
        tareas = [];
        loading = false;
      });

      debugPrint("❌ ERROR CARGANDO CONTACTOS DIARIOS JEFE: $e");
    }
  }

  bool _esHoy(dynamic value) {
    try {
      final fecha = DateTime.parse(value.toString());
      final hoy = DateTime.now();
      return fecha.year == hoy.year &&
          fecha.month == hoy.month &&
          fecha.day == hoy.day;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Stack(
        children: [
          const _BackgroundGlow(),

          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2454D3)),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF2454D3),
                    backgroundColor: Colors.white,
                    onRefresh: cargarTareas,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _topBar(context),
                                const SizedBox(height: 22),
                                _heroPanel(),
                                const SizedBox(height: 18),
                                _statsGrid(),
                                const SizedBox(height: 24),
                                const Text(
                                  "Historial de actividad",
                                  style: TextStyle(
                                    color: const Color(0xFF071A3A),
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Control diario de contactos del jefe de equipo",
                                  style: TextStyle(
                                    color: const Color(0xFF53627A),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                            ),
                          ),
                        ),

                        if (tareas.isEmpty)
                          const SliverFillRemaining(
                            child: Center(
                              child: Text(
                                "No hay registros todavía",
                                style: TextStyle(
                                  color: const Color(0xFF53627A),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverList.builder(
                            itemCount: tareas.length,
                            itemBuilder: (context, index) {
                              return _tareaCard(tareas[index], index);
                            },
                          ),

                        const SliverToBoxAdapter(child: SizedBox(height: 30)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDCE5F2)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14071A3A),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF13244D),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contactos diarios',
                style: TextStyle(
                  color: Color(0xFF071A3A),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Panel de seguimiento del jefe',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: cargarTareas,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2454D3), Color(0xFF3B6AE8)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x332454D3),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _heroPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF13244D), Color(0xFF2454D3)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332454D3),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -8,
            top: -12,
            child: Icon(
              Icons.groups_rounded,
              color: Color(0x1FFFFFFF),
              size: 108,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 54,
                    width: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
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
                          'Ritmo comercial',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          contactosTotales.toString() + ' contactos acumulados',
                          style: const TextStyle(
                            color: Color(0xFFE1E9FC),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: LinearProgressIndicator(
                  value: porcentajeCompletado,
                  minHeight: 11,
                  backgroundColor: Colors.white24,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    (porcentajeCompletado * 100).toStringAsFixed(0) +
                        '% completado',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    diasRealizados.toString() +
                        ' de ' +
                        totalDias.toString() +
                        ' días',
                    style: const TextStyle(
                      color: Color(0xFFE1E9FC),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsGrid() {
    return Row(
      children: [
        Expanded(
          child: _miniStat(
            title: "Equipo",
            value: contactosEquipo.toString(),
            icon: Icons.groups_rounded,
            color: const Color(0xFF2454D3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(
            title: "Propios",
            value: contactosPropios.toString(),
            icon: Icons.person_pin_circle_rounded,
            color: const Color(0xFF2454D3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(
            title: "Pendientes",
            value: diasPendientes.toString(),
            icon: Icons.pending_actions_rounded,
            color: const Color(0xFF2454D3),
          ),
        ),
      ],
    );
  }

  Widget _miniStat({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE5F2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: const Color(0xFF071A3A),
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(color: const Color(0xFF53627A), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _tareaCard(Map<String, dynamic> tarea, int index) {
    final realizada = tarea['realizada'] == true;
    final fechaTexto = _fechaBonita(tarea['fecha']);
    final esHoy = _esHoy(tarea['fecha']);

    final equipo = tarea['contactos_equipo'] ?? 0;
    final propios = tarea['contactos_propios'] ?? 0;
    final total = tarea['total_contactos'] ?? 0;

    final Color estadoColor = realizada
        ? const Color(0xFF198754)
        : const Color(0xFF2454D3);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetalleTareaJefeScreen(tarea: tarea),
            ),
          ).then((_) => cargarTareas());
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 250 + (index * 20)),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: Colors.white,
            border: Border.all(
              color: esHoy ? const Color(0xFF2454D3) : const Color(0xFFDCE5F2),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0x14071A3A),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                height: 58,
                width: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: estadoColor.withOpacity(0.16),
                  border: Border.all(color: estadoColor.withOpacity(0.35)),
                ),
                child: Icon(
                  realizada
                      ? Icons.verified_rounded
                      : Icons.hourglass_top_rounded,
                  color: estadoColor,
                  size: 30,
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            esHoy ? "Tarea de hoy" : "Contactos diarios",
                            style: const TextStyle(
                              color: const Color(0xFF071A3A),
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (esHoy) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF0FF),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              "HOY",
                              style: TextStyle(
                                color: Color(0xFF2454D3),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 5),

                    Text(
                      fechaTexto,
                      style: TextStyle(
                        color: const Color(0xFF53627A),
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 13),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip("Equipo", equipo.toString()),
                        _chip("Propios", propios.toString()),
                        _chip("Total", total.toString()),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Column(
                children: [
                  Text(
                    realizada ? "OK" : "PEND.",
                    style: TextStyle(
                      color: estadoColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF64748B),
                    size: 17,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFDCE5F2)),
      ),
      child: Text(
        "$label $value",
        style: TextStyle(
          color: const Color(0xFF53627A),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4F6FB), Color(0xFFEAF1FF)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}
