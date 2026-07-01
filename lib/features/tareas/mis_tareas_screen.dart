import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/utils/referencias_filter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safebrok_andalucia/features/business/referencia_diaria_screen.dart';
import 'package:safebrok_andalucia/features/business/referencias_screen.dart';
import 'package:safebrok_andalucia/features/business/seguimiento_clientes_screen.dart';
import 'package:safebrok_andalucia/features/business/visitas_hoy_screen.dart';
import '../business/contactos_diarios_screen.dart';

class MisTareasScreen extends StatefulWidget {
  const MisTareasScreen({super.key});

  @override
  State<MisTareasScreen> createState() => _MisTareasScreenState();
}

class _MisTareasScreenState extends State<MisTareasScreen> {
  final supabase = Supabase.instance.client;

  int referenciasHoy = 0;
  int llamadasPendientes = 0;
  int seguimientosPendientes = 0;
  int seguimientosTotales = 0;
  int visitasHoy = 0;
  int contactosHoy = 0;

  final List<Map<String, dynamic>> tareas = [
    {
      "titulo": "Incluir 3 referencias diarias",
      "detalle": "0 / 3 completadas",
      "completada": false,
      "icono": Icons.person_add_alt_1,
      "color": Colors.greenAccent,
      "actual": 0,
      "objetivo": 3,
    },
    {
      "titulo": "Contactos diarios",
      "detalle": "0 / 6 completados",
      "completada": false,
      "icono": Icons.group_add,
      "color": Colors.blueAccent,
      "actual": 0,
      "objetivo": 6,
    },
    {
      "titulo": "Llamadas a referencias viables",
      "detalle": "0 pendientes",
      "completada": false,
      "icono": Icons.phone,
      "color": Colors.orangeAccent,
      "actual": 0,
      "objetivo": 0,
    },
    {
      "titulo": "Seguimiento de clientes",
      "detalle": "0 / 0 completadas",
      "completada": false,
      "icono": Icons.support_agent,
      "color": Colors.purpleAccent,
      "actual": 0,
      "objetivo": 0,
    },
    {
      "titulo": "Visitas programadas",
      "detalle": "0 visitas pendientes",
      "completada": false,
      "icono": Icons.location_on,
      "color": Colors.cyanAccent,
      "actual": 0,
      "objetivo": 0,
    },
    {
      "titulo": "Recibos pendientes",
      "detalle": "3 recibos por gestionar",
      "completada": false,
      "icono": Icons.receipt_long,
      "color": Colors.amberAccent,
      "actual": 3,
      "objetivo": 0,
    },
  ];

  int get completadas => tareas.where((e) => e["completada"] == true).length;

  double get progreso => tareas.isEmpty ? 0 : completadas / tareas.length;

  @override
  void initState() {
    super.initState();
    registrarAcceso();
    cargarReferenciasHoy();
    cargarLlamadasPendientes();
    cargarDatosSeguimiento();
    cargarDatosVisitas();
    cargarContactosDiarios();
  }

  void _actualizarTarea(
    String titulo, {
    required String detalle,
    required bool completada,
    int? actual,
    int? objetivo,
  }) {
    final index = tareas.indexWhere((t) => t["titulo"] == titulo);

    if (index == -1) return;

    setState(() {
      tareas[index]["detalle"] = detalle;
      tareas[index]["completada"] = completada;

      if (actual != null) tareas[index]["actual"] = actual;
      if (objetivo != null) tareas[index]["objetivo"] = objetivo;
    });
  }

  Future<void> registrarAcceso() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('actividad_agentes').insert({
      'auth_id': user.id,
      'pantalla': 'mis_tareas',
    });
  }

  Future<void> cargarReferenciasHoy() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final inicioDia = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final data = await supabase
        .from('referencias_viables')
        .select('id')
        .eq('auth_id', user.id)
        .gte('created_at', inicioDia.toIso8601String());

    referenciasHoy = data.length;

    _actualizarTarea(
      "Incluir 3 referencias diarias",
      detalle: "${referenciasHoy > 3 ? 3 : referenciasHoy} / 3 completadas",
      completada: referenciasHoy >= 3,
      actual: referenciasHoy > 3 ? 3 : referenciasHoy,
      objetivo: 3,
    );
  }

  Future<void> cargarContactosDiarios() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final inicioDia = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final data = await supabase
        .from('contactos_diarios')
        .select('contactos_positivos, created_at')
        .eq('auth_id', user.id)
        .gte('created_at', inicioDia.toIso8601String());

    int totalPositivos = 0;

    for (final item in data) {
      totalPositivos += (item['contactos_positivos'] ?? 0) as int;
    }

    contactosHoy = totalPositivos;

    _actualizarTarea(
      "Contactos diarios",
      detalle: "${totalPositivos > 6 ? 6 : totalPositivos} / 6 completados",
      completada: totalPositivos >= 6,
      actual: totalPositivos > 6 ? 6 : totalPositivos,
      objetivo: 6,
    );
  }

  Future<void> cargarLlamadasPendientes() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final data = await supabase
        .from('referencias_viables')
        .select()
        .eq('auth_id', user.id);

    final now = DateTime.now();

    final filtradas = List<Map<String, dynamic>>.from(data)
        .where((r) => esReferenciaActiva(r, now))
        .toList();

    llamadasPendientes = filtradas.length;

    _actualizarTarea(
      "Llamadas a referencias viables",
      detalle: "$llamadasPendientes pendientes",
      completada: llamadasPendientes == 0,
      actual: llamadasPendientes,
      objetivo: 0,
    );
  }

  Future<int> getSeguimientosPendientes() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 0;

    final data = await supabase
        .from('seguimiento_clientes')
        .select()
        .eq('auth_id', user.id)
        .eq('estado', 'Pendiente');

    final now = DateTime.now();

    final pendientes = data.where((s) {
      final fecha = DateTime.parse(s['proxima_llamada']);
      return fecha.isBefore(now.add(const Duration(days: 1)));
    }).toList();

    return pendientes.length;
  }

  Future<int> getSeguimientosTotales() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 0;

    final data = await supabase
        .from('seguimiento_clientes')
        .select('id')
        .eq('auth_id', user.id);

    return data.length;
  }

 Future<void> cargarDatosSeguimiento() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final now = DateTime.now();

  final hoy = DateTime(
    now.year,
    now.month,
    now.day,
  );

  final data = await supabase
      .from('seguimiento_clientes')
      .select()
      .eq('auth_id', user.id);

  int pendientesHoy = 0;
  int realizadasHoy = 0;

  for (final item in data) {
    if (item['proxima_llamada'] == null) continue;

    final fecha = DateTime.parse(item['proxima_llamada']);

    final fechaLlamada = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
    );

    final esDeHoyOVencida = !fechaLlamada.isAfter(hoy);

    if (!esDeHoyOVencida) continue;

    if (item['estado'] == 'Pendiente') {
      pendientesHoy++;
    }

    if (item['estado'] == 'Realizada') {
      realizadasHoy++;
    }
  }

  final totalTareaHoy = pendientesHoy + realizadasHoy;

  _actualizarTarea(
    "Seguimiento de clientes",
    detalle: totalTareaHoy == 0
        ? "Sin seguimientos para hoy"
        : "$realizadasHoy / $totalTareaHoy realizadas",
    completada: pendientesHoy == 0,
    actual: realizadasHoy,
    objetivo: totalTareaHoy,
  );
}

  Future<void> cargarDatosVisitas() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final today = DateTime.now();

    final todayString =
        "${today.year.toString().padLeft(4, '0')}-"
        "${today.month.toString().padLeft(2, '0')}-"
        "${today.day.toString().padLeft(2, '0')}";

    final data = await supabase
        .from('visitas')
        .select('id')
        .eq('auth_id', user.id)
        .eq('estado', 'Pendiente')
        .eq('fecha_visita', todayString);

    visitasHoy = data.length;

    _actualizarTarea(
      "Visitas programadas",
      detalle: "$visitasHoy visitas pendientes",
      completada: visitasHoy == 0,
      actual: visitasHoy,
      objetivo: 0,
    );
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      cargarReferenciasHoy(),
      cargarLlamadasPendientes(),
      cargarDatosSeguimiento(),
      cargarDatosVisitas(),
      cargarContactosDiarios(),
    ]);
  }

  void _abrirTarea(Map<String, dynamic> tarea) {
    final titulo = tarea["titulo"];

    if (titulo == "Incluir 3 referencias diarias") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReferenciaDiariaScreen()),
      ).then((_) {
        cargarReferenciasHoy();
        cargarLlamadasPendientes();
      });
      return;
    }

    if (titulo == "Contactos diarios") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ContactosDiariosScreen()),
      ).then((_) => cargarContactosDiarios());
      return;
    }

    if (titulo == "Llamadas a referencias viables") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReferenciasScreen()),
      ).then((_) => cargarLlamadasPendientes());
      return;
    }

    if (titulo == "Seguimiento de clientes") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SeguimientoClientesScreen()),
      ).then((_) => cargarDatosSeguimiento());
      return;
    }

    if (titulo == "Visitas programadas") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VisitasHoyScreen()),
      ).then((_) => cargarDatosVisitas());
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      body: Stack(
        children: [
          const _PremiumBackground(),
          SafeArea(
            child: RefreshIndicator(
              color: Colors.cyanAccent,
              backgroundColor: const Color(0xFF0B1D2A),
              onRefresh: _refreshAll,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _topBar()),
                  SliverToBoxAdapter(child: _heroCard()),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                    sliver: SliverList.separated(
                      itemCount: tareas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        return _taskCard(tareas[index]);
                      },
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

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: const Icon(
              Icons.menu_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              "Mis tareas",
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),
          Stack(
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              Positioned(
                top: 8,
                right: 9,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.cyanAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    final percent = (progreso * 100).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            Colors.cyanAccent.withOpacity(0.16),
            const Color(0xFF081A2A).withOpacity(0.92),
            const Color(0xFF061018).withOpacity(0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.cyanAccent.withOpacity(0.32),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.12),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "TAREAS DEL DÍA",
                      style: TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "$completadas",
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 62,
                            fontWeight: FontWeight.w900,
                            height: 0.9,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "/ ${tareas.length}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 46,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "completadas",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.cyanAccent.withOpacity(0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.star_rounded,
                            color: Colors.cyanAccent,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Sigue así. Vas por buen camino",
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                height: 130,
                width: 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 120,
                      width: 120,
                      child: CircularProgressIndicator(
                        value: progreso,
                        strokeWidth: 11,
                        backgroundColor: Colors.white.withOpacity(0.10),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.cyanAccent,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "$percent%",
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 31,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "PROGRESO",
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> tarea) {
    final bool completada = tarea["completada"] == true;
    final Color color = tarea["color"] as Color;
    final int actual = tarea["actual"] ?? 0;
    final int objetivo = tarea["objetivo"] ?? 0;

    final bool hasProgress = objetivo > 0;
    final double value = hasProgress ? (actual / objetivo).clamp(0.0, 1.0) : 0;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _abrirTarea(tarea),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.12),
              Colors.white.withOpacity(0.055),
              Colors.white.withOpacity(0.035),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border.all(
            color: completada
                ? Colors.greenAccent.withOpacity(0.38)
                : color.withOpacity(0.26),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.09),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withOpacity(0.34),
                    color.withOpacity(0.10),
                    Colors.black.withOpacity(0.15),
                  ],
                ),
                border: Border.all(color: color.withOpacity(0.55)),
              ),
              child: Icon(
                tarea["icono"],
                color: color,
                size: 34,
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 58,
              color: Colors.white.withOpacity(0.10),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tarea["titulo"],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    tarea["detalle"],
                    style: TextStyle(
                      color: color,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (hasProgress) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 7,
                        backgroundColor: Colors.white.withOpacity(0.10),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            _rightBadge(
              completada: completada,
              color: color,
              actual: actual,
              objetivo: objetivo,
              hasProgress: hasProgress,
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withOpacity(0.52),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rightBadge({
    required bool completada,
    required Color color,
    required int actual,
    required int objetivo,
    required bool hasProgress,
  }) {
    if (completada) {
      return Container(
        height: 54,
        width: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.greenAccent.withOpacity(0.12),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
        ),
        child: const Icon(
          Icons.check_rounded,
          color: Colors.greenAccent,
          size: 32,
        ),
      );
    }

    if (hasProgress) {
      final percent = ((actual / objetivo).clamp(0.0, 1.0) * 100).round();

      return SizedBox(
        height: 58,
        width: 58,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: actual / objetivo,
              strokeWidth: 5,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
            Text(
              "$percent%",
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 54,
      width: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.10),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        "$actual",
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
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
              colors: [
                Color(0xFF02060A),
                Color(0xFF061018),
                Color(0xFF071827),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -80,
          child: _blurCircle(220, Colors.cyanAccent.withOpacity(0.18)),
        ),
        Positioned(
          top: 260,
          left: -130,
          child: _blurCircle(240, Colors.blueAccent.withOpacity(0.10)),
        ),
        Positioned(
          bottom: -100,
          right: -100,
          child: _blurCircle(260, Colors.cyanAccent.withOpacity(0.10)),
        ),
      ],
    );
  }

  static Widget _blurCircle(double size, Color color) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 80,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}