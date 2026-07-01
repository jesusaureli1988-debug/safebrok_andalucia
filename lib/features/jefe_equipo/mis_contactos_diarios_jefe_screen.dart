import 'dart:ui';
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
  return date.weekday >= DateTime.monday &&
      date.weekday <= DateTime.friday;
}

int get totalDias => tareas.length;

int get diasRealizados =>
    tareas.where((t) => t['realizada'] == true).length;

int get diasPendientes =>
    tareas.where((t) => t['realizada'] != true).length;

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

    final listaExistente =
        List<Map<String, dynamic>>.from(tareasExistentes as List);

    // 2. Intentamos sacar la fecha de alta del usuario
    DateTime inicioDiario;

    try {
      final userData = await supabase
          .from('usuarios')
          .select('fecha_alta, created_at')
          .eq('auth_id', user.id)
          .maybeSingle();

      final fechaAltaRaw =
          userData?['fecha_alta'] ?? userData?['created_at'];

      inicioDiario = DateTime.parse(fechaAltaRaw.toString());
    } catch (_) {
      // Si falla, usamos la primera tarea existente
      if (listaExistente.isNotEmpty) {
        inicioDiario =
            DateTime.parse(listaExistente.first['fecha'].toString());
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
      await supabase
          .from('contactos_diarios_jefe_equipo')
          .insert(insertar);
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
      backgroundColor: const Color(0xFF050816),
      body: Stack(
        children: [
          const _BackgroundGlow(),

          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF38BDF8),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF38BDF8),
                    backgroundColor: const Color(0xFF0F172A),
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
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "Control diario de contactos del jefe de equipo",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
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
                                style: TextStyle(color: Colors.white70),
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

                        const SliverToBoxAdapter(
                          child: SizedBox(height: 30),
                        ),
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
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
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
                "Contactos diarios",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                "Panel de seguimiento del jefe",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: cargarTareas,
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF38BDF8),
                  Color(0xFF6366F1),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38BDF8).withOpacity(0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.16),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 54,
                    width: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF22C55E),
                          Color(0xFF38BDF8),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22C55E).withOpacity(0.35),
                          blurRadius: 24,
                        ),
                      ],
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
                          "Ritmo comercial",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "$contactosTotales contactos acumulados",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
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
                  backgroundColor: Colors.white.withOpacity(0.10),
                  color: const Color(0xFF22C55E),
                ),
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${(porcentajeCompletado * 100).toStringAsFixed(0)}% completado",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    "$diasRealizados de $totalDias días",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
            color: const Color(0xFF38BDF8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(
            title: "Propios",
            value: contactosPropios.toString(),
            icon: Icons.person_pin_circle_rounded,
            color: const Color(0xFFA78BFA),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(
            title: "Pendientes",
            value: diasPendientes.toString(),
            icon: Icons.pending_actions_rounded,
            color: const Color(0xFFF59E0B),
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
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
            ),
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

    final Color estadoColor =
        realizada ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);

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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                estadoColor.withOpacity(0.18),
                Colors.white.withOpacity(0.055),
              ],
            ),
            border: Border.all(
              color: esHoy
                  ? const Color(0xFF38BDF8).withOpacity(0.65)
                  : Colors.white.withOpacity(0.09),
            ),
            boxShadow: [
              BoxShadow(
                color: estadoColor.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
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
                              color: Colors.white,
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
                              color: const Color(0xFF38BDF8).withOpacity(0.18),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              "HOY",
                              style: TextStyle(
                                color: Color(0xFF7DD3FC),
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
                        color: Colors.white.withOpacity(0.58),
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
                    color: Colors.white.withOpacity(0.35),
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
        color: Colors.black.withOpacity(0.20),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(
        "$label $value",
        style: TextStyle(
          color: Colors.white.withOpacity(0.78),
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
    return Stack(
      children: [
        Positioned(
          top: -90,
          left: -80,
          child: _glow(const Color(0xFF38BDF8), 230),
        ),
        Positioned(
          top: 130,
          right: -100,
          child: _glow(const Color(0xFF6366F1), 260),
        ),
        Positioned(
          bottom: -120,
          left: 40,
          child: _glow(const Color(0xFF22C55E), 230),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: const SizedBox(),
      ),
    );
  }
}