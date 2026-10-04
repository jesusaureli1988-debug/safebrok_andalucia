import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/utils/referencias_filter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safebrok_andalucia/features/business/referencia_diaria_screen.dart';
import 'package:safebrok_andalucia/features/business/referencias_screen.dart';
import 'package:safebrok_andalucia/features/business/seguimiento_clientes_screen.dart';
import 'package:safebrok_andalucia/features/business/visitas_hoy_screen.dart';
import 'package:safebrok_andalucia/features/recibos/recibos_agente_screen.dart';
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
  int recibosPendientes = 0;

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
      "detalle": "Cargando recibos...",
      "completada": false,
      "icono": Icons.receipt_long,
      "color": Colors.amberAccent,
      "actual": 0,
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
    cargarRecibosPendientes();
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

    final filtradas = List<Map<String, dynamic>>.from(
      data,
    ).where((r) => esReferenciaActiva(r, now)).toList();

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

    final hoy = DateTime(now.year, now.month, now.day);

    final data = await supabase
        .from('seguimiento_clientes')
        .select()
        .eq('auth_id', user.id);

    int pendientesHoy = 0;
    int realizadasHoy = 0;

    for (final item in data) {
      if (item['proxima_llamada'] == null) continue;

      final fecha = DateTime.parse(item['proxima_llamada']);

      final fechaLlamada = DateTime(fecha.year, fecha.month, fecha.day);

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

  bool _esReciboSinGestionar(dynamic value) {
    final estado = (value ?? '').toString().trim().toLowerCase();

    return estado.isEmpty ||
        estado == 'pendiente' ||
        estado == 'devuelto' ||
        estado == 'impagado';
  }

  Future<void> cargarRecibosPendientes() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final data = await supabase
          .from('recibos')
          .select('id, estado')
          .eq('agente', user.id);

      final pendientes = List<Map<String, dynamic>>.from(
        data,
      ).where((recibo) => _esReciboSinGestionar(recibo['estado'])).length;

      if (!mounted) return;

      recibosPendientes = pendientes;
      _actualizarTarea(
        "Recibos pendientes",
        detalle: pendientes == 0
            ? "Sin recibos por gestionar"
            : pendientes == 1
            ? "1 recibo por gestionar"
            : "$pendientes recibos por gestionar",
        completada: pendientes == 0,
        actual: pendientes,
        objetivo: 0,
      );
    } catch (error) {
      debugPrint('ERROR CARGANDO RECIBOS PENDIENTES: $error');
      if (!mounted) return;

      _actualizarTarea(
        "Recibos pendientes",
        detalle: "No se pudieron cargar los recibos",
        completada: false,
        actual: 0,
        objetivo: 0,
      );
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      cargarReferenciasHoy(),
      cargarLlamadasPendientes(),
      cargarDatosSeguimiento(),
      cargarDatosVisitas(),
      cargarContactosDiarios(),
      cargarRecibosPendientes(),
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

    if (titulo == "Recibos pendientes") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RecibosAgenteScreen()),
      ).then((_) => cargarRecibosPendientes());
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          const _PremiumBackground(),
          SafeArea(
            child: RefreshIndicator(
              color: Colors.cyanAccent,
              backgroundColor: const Color(0xFFEAF8F8),
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
          IconButton.filledTonal(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF13244D),
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Mis tareas",
              style: TextStyle(
                color: Color(0xFF13244D),
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar tareas',
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF13244D),
              backgroundColor: Colors.white,
            ),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF172B58), Color(0xFF2454D3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF13244D).withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TAREAS DEL DÍA",
                  style: TextStyle(
                    color: Color(0xFFCBD9FA),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  "$completadas / ${tareas.length}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  "completadas",
                  style: TextStyle(color: Color(0xFFE1E9FC), fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 92,
            width: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 82,
                  width: 82,
                  child: CircularProgressIndicator(
                    value: progreso,
                    strokeWidth: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
                Text(
                  "$percent%",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> tarea) {
    final bool completada = tarea["completada"] == true;
    const Color color = Color(0xFF2454D3);
    final int actual = tarea["actual"] ?? 0;
    final int objetivo = tarea["objetivo"] ?? 0;
    final bool hasProgress = objetivo > 0;
    final double value = hasProgress ? (actual / objetivo).clamp(0.0, 1.0) : 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _abrirTarea(tarea),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDCE5F2)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF0FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(tarea["icono"], color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tarea["titulo"],
                      style: const TextStyle(
                        color: Color(0xFF13244D),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tarea["detalle"],
                      style: const TextStyle(
                        color: Color(0xFF53627A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasProgress) ...[
                      const SizedBox(height: 11),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE5EBF5),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _rightBadge(
                completada: completada,
                color: color,
                actual: actual,
                objetivo: objetivo,
                hasProgress: hasProgress,
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B)),
            ],
          ),
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
          color: const Color(0xFFE7F7EF),
          border: Border.all(color: const Color(0xFF88D5AC)),
        ),
        child: const Icon(
          Icons.check_rounded,
          color: const Color(0xFF198754),
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
              backgroundColor: const Color(0xFFE5EBF5),
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
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFF5F7FC), Color(0xFFEAF1FF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
    ),
  );
}
