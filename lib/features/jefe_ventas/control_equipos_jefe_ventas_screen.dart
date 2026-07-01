import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ControlEquiposJefeVentasScreen extends StatefulWidget {
  const ControlEquiposJefeVentasScreen({super.key});

  @override
  State<ControlEquiposJefeVentasScreen> createState() =>
      _ControlEquiposJefeVentasScreenState();
}

class _ControlEquiposJefeVentasScreenState
    extends State<ControlEquiposJefeVentasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  List<Map<String, dynamic>> equipos = [];

  final DateTime inicioSistema = DateTime(2026, 6, 1);

  @override
  void initState() {
    super.initState();
    cargarEstado();
  }

  Future<void> cargarEstado() async {
    try {
      setState(() {
        loading = true;
        error = null;
      });

      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() {
          loading = false;
          error = "No hay usuario iniciado.";
        });
        return;
      }

      final jefeVentas = await supabase
          .from('usuarios')
          .select()
          .eq('auth_id', user.id)
          .single();

      final jefesEquipo = await supabase
          .from('usuarios')
          .select()
          .eq('parent_id', jefeVentas['id'])
          .eq('rol_usuario', 'jefe_equipo');

      final List<Map<String, dynamic>> resultado = [];

      for (final jefe in jefesEquipo) {
        final agentes = await supabase
            .from('usuarios')
            .select()
            .eq('parent_id', jefe['id'])
            .eq('rol_usuario', 'agente');

        final List<Map<String, dynamic>> agentesProcesados = [];

        int incidenciasEquipo = 0;

        for (final agente in agentes) {
          final tareas = await _analizarTareas(agente['auth_id']);

          final incidencias = tareas.where((t) => t['ok'] == false).length;

          if (incidencias > 0) {
            incidenciasEquipo++;
          }

          agentesProcesados.add({
            "agente": Map<String, dynamic>.from(agente),
            "tareas": tareas,
            "incidencias": incidencias,
          });
        }

        agentesProcesados.sort((a, b) {
          final incA = a['incidencias'] ?? 0;
          final incB = b['incidencias'] ?? 0;
          return incB.compareTo(incA);
        });

        resultado.add({
          "jefe": Map<String, dynamic>.from(jefe),
          "agentes": agentesProcesados,
          "totalAgentes": agentes.length,
          "incidenciasEquipo": incidenciasEquipo,
        });
      }

      resultado.sort((a, b) {
        final incA = a['incidenciasEquipo'] ?? 0;
        final incB = b['incidenciasEquipo'] ?? 0;
        return incB.compareTo(incA);
      });

      setState(() {
        equipos = resultado;
        loading = false;
      });
    } catch (e) {
      debugPrint("ERROR EQUIPOS: $e");

      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _analizarTareas(String authId) async {
    final now = DateTime.now();

    final inicioMes = DateTime(
      now.year,
      now.month,
      1,
    );

    final referencias = await supabase
        .from('referencias_viables')
        .select('created_at')
        .eq('auth_id', authId)
        .gte('created_at', inicioMes.toIso8601String());

    Map<String, int> refsPorDia = {};

    for (final r in referencias) {
      final fecha = DateTime.parse(r['created_at']);
      final key = DateTime(fecha.year, fecha.month, fecha.day).toString();

      refsPorDia[key] = (refsPorDia[key] ?? 0) + 1;
    }

    int diasMalReferencias = 0;

    for (int d = 1; d <= now.day; d++) {
      final dia = DateTime(now.year, now.month, d).toString();

      final count = refsPorDia[dia] ?? 0;

      if (count < 3) {
        diasMalReferencias++;
      }
    }

    final contactos = await supabase
        .from('contactos_diarios')
        .select('created_at, contactos_positivos')
        .eq('auth_id', authId)
        .gte('created_at', inicioMes.toIso8601String());

    Map<String, int> contactosPorDia = {};

    for (final c in contactos) {
      final fecha = DateTime.parse(c['created_at']);
      final key = DateTime(fecha.year, fecha.month, fecha.day).toString();

      contactosPorDia[key] =
          (contactosPorDia[key] ?? 0) +
          ((c['contactos_positivos'] ?? 0) as int);
    }

    int diasMalContactos = 0;

    for (int d = 1; d <= now.day; d++) {
      final dia = DateTime(now.year, now.month, d).toString();

      final total = contactosPorDia[dia] ?? 0;

      if (total < 6) {
        diasMalContactos++;
      }
    }

    final seguimientos = await supabase
        .from('seguimiento_clientes')
        .select('proxima_llamada, estado')
        .eq('auth_id', authId)
        .eq('estado', 'Pendiente');

    int seguimientosVencidos = 0;

    for (final s in seguimientos) {
      if (s['proxima_llamada'] == null) continue;

      final fecha = DateTime.parse(s['proxima_llamada']);

      if (fecha.isBefore(now)) {
        seguimientosVencidos++;
      }
    }

    final actividad = await supabase
        .from('actividad_agentes')
        .select('created_at')
        .eq('auth_id', authId)
        .eq('pantalla', 'mis_tareas')
        .order('created_at', ascending: false)
        .limit(1);

    DateTime fechaBase;

    if (actividad.isNotEmpty) {
      fechaBase = DateTime.parse(actividad.first['created_at']);
    } else {
      fechaBase = inicioSistema;
    }

    final diasSinEntrar = DateTime.now().difference(fechaBase).inDays;

    return [
      {
        "titulo": "Referencias diarias",
        "ok": diasMalReferencias == 0,
        "detalle": "$diasMalReferencias días por debajo de 3 referencias",
        "icon": Icons.people_alt_rounded,
      },
      {
        "titulo": "Contactos diarios",
        "ok": diasMalContactos == 0,
        "detalle": "$diasMalContactos días por debajo de 6 contactos",
        "icon": Icons.phone_in_talk_rounded,
      },
      {
        "titulo": "Seguimientos vencidos",
        "ok": seguimientosVencidos == 0,
        "detalle": "$seguimientosVencidos pendientes",
        "icon": Icons.notification_important_rounded,
      },
      {
        "titulo": "Entrada en tareas",
        "ok": diasSinEntrar < 3,
        "detalle": "$diasSinEntrar días sin entrar a tareas",
        "icon": Icons.task_alt_rounded,
      },
    ];
  }

  int get totalEquipos => equipos.length;

  int get totalAgentes {
    return equipos.fold<int>(
      0,
      (total, e) => total + ((e['totalAgentes'] ?? 0) as int),
    );
  }

  int get totalAgentesConIncidencias {
    return equipos.fold<int>(
      0,
      (total, e) => total + ((e['incidenciasEquipo'] ?? 0) as int),
    );
  }

  int get totalIncidencias {
    int total = 0;

    for (final equipo in equipos) {
      final agentes = List<Map<String, dynamic>>.from(equipo['agentes']);

      for (final item in agentes) {
        total += (item['incidencias'] ?? 0) as int;
      }
    }

    return total;
  }

  double get cumplimientoGlobal {
    if (totalAgentes == 0) return 1;

    final totalTareas = totalAgentes * 4;

    if (totalTareas == 0) return 1;

    return ((totalTareas - totalIncidencias) / totalTareas).clamp(0.0, 1.0);
  }

  Color _estadoColorPorIncidencias(int incidencias) {
    if (incidencias == 0) return Colors.greenAccent;
    if (incidencias <= 2) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _estadoTextoPorIncidencias(int incidencias) {
    if (incidencias == 0) return "Todo correcto";
    if (incidencias <= 2) return "Revisar";
    return "Crítico";
  }

  double _cumplimientoAgente(List tareas) {
    if (tareas.isEmpty) return 1;

    final ok = tareas.where((t) => t['ok'] == true).length;

    return (ok / tareas.length).clamp(0.0, 1.0);
  }

  double _cumplimientoEquipo(Map<String, dynamic> equipo) {
    final agentes = List<Map<String, dynamic>>.from(equipo['agentes']);

    if (agentes.isEmpty) return 1;

    int totalTareas = 0;
    int tareasOk = 0;

    for (final item in agentes) {
      final tareas = List<Map<String, dynamic>>.from(item['tareas']);

      totalTareas += tareas.length;
      tareasOk += tareas.where((t) => t['ok'] == true).length;
    }

    if (totalTareas == 0) return 1;

    return (tareasOk / totalTareas).clamp(0.0, 1.0);
  }

  String _nombreCompleto(Map<String, dynamic>? u) {
    if (u == null) return "Sin nombre";

    final nombre = u['nombre']?.toString() ?? '';
    final apellidos = u['apellidos']?.toString() ?? '';

    final completo = '$nombre $apellidos'.trim();

    if (completo.isEmpty) {
      return u['email']?.toString() ?? 'Sin nombre';
    }

    return completo;
  }

  String _iniciales(String nombre) {
    final partes = nombre.trim().split(' ').where((e) => e.isNotEmpty).toList();

    if (partes.isEmpty) return "?";
    if (partes.length == 1) return partes.first[0].toUpperCase();

    return "${partes[0][0]}${partes[1][0]}".toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _ControlBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: cargarEstado,
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF0F172A),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                      children: [
                        _header(),
                        const SizedBox(height: 18),

                        if (error != null)
                          _errorCard()
                        else ...[
                          _controlHero(),
                          const SizedBox(height: 16),
                          _kpiResumen(),
                          const SizedBox(height: 20),
                          _sectionTitle(),
                          const SizedBox(height: 14),

                          if (equipos.isEmpty)
                            _emptyCard()
                          else
                            ...equipos.map(_equipoControlCard),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.45),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.16),
                  blurRadius: 22,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Control de equipos",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 3),
              Text(
                "Auditoría comercial y tareas críticas",
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.cyanAccent.withOpacity(0.12),
            border: Border.all(
              color: Colors.cyanAccent.withOpacity(0.38),
            ),
          ),
          child: const Icon(
            Icons.health_and_safety_rounded,
            color: Colors.cyanAccent,
          ),
        ),
      ],
    );
  }

  Widget _controlHero() {
    final porcentaje = cumplimientoGlobal;
    final color = porcentaje >= 0.80
        ? Colors.greenAccent
        : porcentaje >= 0.55
            ? Colors.orangeAccent
            : Colors.redAccent;

    final texto = porcentaje >= 0.80
        ? "Estructura controlada"
        : porcentaje >= 0.55
            ? "Necesita seguimiento"
            : "Riesgo alto";

    return _glassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.15),
                  border: Border.all(
                    color: color.withOpacity(0.38),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.16),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Icon(
                  porcentaje >= 0.80
                      ? Icons.verified_rounded
                      : porcentaje >= 0.55
                          ? Icons.manage_search_rounded
                          : Icons.warning_rounded,
                  color: color,
                  size: 36,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      texto,
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      "Resumen global del cumplimiento de actividad",
                      style: TextStyle(
                        color: Colors.white60,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: porcentaje,
                    minHeight: 13,
                    backgroundColor: Colors.white.withOpacity(0.12),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "${(porcentaje * 100).toStringAsFixed(0)}%",
                style: TextStyle(
                  color: color,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiResumen() {
    return Row(
      children: [
        Expanded(
          child: _kpiBox(
            title: "Equipos",
            value: totalEquipos.toString(),
            icon: Icons.account_tree_rounded,
            color: Colors.purpleAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiBox(
            title: "Agentes",
            value: totalAgentes.toString(),
            icon: Icons.groups_rounded,
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _kpiBox(
            title: "Alertas",
            value: totalAgentesConIncidencias.toString(),
            icon: Icons.warning_rounded,
            color: totalAgentesConIncidencias == 0
                ? Colors.greenAccent
                : Colors.redAccent,
          ),
        ),
      ],
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle() {
    return Row(
      children: [
        const Icon(
          Icons.fact_check_rounded,
          color: Colors.cyanAccent,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            "Panel de incidencias",
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          "$totalIncidencias incidencias",
          style: TextStyle(
            color: totalIncidencias == 0 ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _equipoControlCard(Map<String, dynamic> equipo) {
    final jefe = Map<String, dynamic>.from(equipo['jefe']);
    final agentes = List<Map<String, dynamic>>.from(equipo['agentes']);

    final nombreJefe = _nombreCompleto(jefe);

    final incidenciasEquipo = (equipo['incidenciasEquipo'] ?? 0) as int;
    final totalAgentesEquipo = (equipo['totalAgentes'] ?? 0) as int;

    final cumplimiento = _cumplimientoEquipo(equipo);
    final color = _estadoColorPorIncidencias(incidenciasEquipo);

    return _glassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          iconColor: Colors.cyanAccent,
          collapsedIconColor: Colors.white70,
          tilePadding: const EdgeInsets.all(18),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          title: Row(
            children: [
              _avatar(nombreJefe, Colors.purpleAccent, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreJefe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "$incidenciasEquipo agentes con incidencias de $totalAgentesEquipo",
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(
                _estadoTextoPorIncidencias(incidenciasEquipo),
                color,
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: cumplimiento,
                      minHeight: 9,
                      backgroundColor: Colors.white.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation(
                        cumplimiento >= 0.80
                            ? Colors.greenAccent
                            : cumplimiento >= 0.55
                                ? Colors.orangeAccent
                                : Colors.redAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "${(cumplimiento * 100).toStringAsFixed(0)}%",
                  style: TextStyle(
                    color: cumplimiento >= 0.80
                        ? Colors.greenAccent
                        : cumplimiento >= 0.55
                            ? Colors.orangeAccent
                            : Colors.redAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          children: [
            if (agentes.isEmpty)
              _emptyAgents()
            else
              ...agentes.map(_agenteControlNode),
          ],
        ),
      ),
    );
  }

  Widget _agenteControlNode(Map<String, dynamic> item) {
    final agente = Map<String, dynamic>.from(item['agente']);
    final tareas = List<Map<String, dynamic>>.from(item['tareas']);
    final incidencias = (item['incidencias'] ?? 0) as int;

    final nombreAgente = _nombreCompleto(agente);
    final cumplimiento = _cumplimientoAgente(tareas);
    final color = _estadoColorPorIncidencias(incidencias);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          iconColor: Colors.cyanAccent,
          collapsedIconColor: Colors.white70,
          tilePadding: const EdgeInsets.all(14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              _avatar(nombreAgente, Colors.cyanAccent, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreAgente,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      incidencias == 0
                          ? "Sin incidencias"
                          : "$incidencias incidencias detectadas",
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                incidencias == 0
                    ? Icons.verified_rounded
                    : incidencias <= 2
                        ? Icons.manage_search_rounded
                        : Icons.warning_rounded,
                color: color,
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: cumplimiento,
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  "${(cumplimiento * 100).toStringAsFixed(0)}%",
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          children: tareas.map(_taskTile).toList(),
        ),
      ),
    );
  }

  Widget _taskTile(Map<String, dynamic> t) {
    final ok = t['ok'] == true;
    final color = ok ? Colors.greenAccent : Colors.redAccent;
    final icon = t['icon'] is IconData ? t['icon'] as IconData : Icons.task_alt_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.22),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.13),
              border: Border.all(
                color: color.withOpacity(0.30),
              ),
            ),
            child: Icon(
              ok ? Icons.check_circle_rounded : Icons.warning_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            icon,
            color: Colors.white54,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t['titulo']?.toString() ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t['detalle']?.toString() ?? '',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.30),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _avatar(String nombre, Color color, {double size = 50}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.34),
            Colors.blueAccent.withOpacity(0.16),
          ],
        ),
        border: Border.all(
          color: color.withOpacity(0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 16,
          ),
        ],
      ),
      child: Center(
        child: Text(
          _iniciales(nombre),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _emptyAgents() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.white54),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Este jefe de equipo todavía no tiene agentes asignados.",
              style: TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return _glassCard(
      child: const Column(
        children: [
          Icon(
            Icons.fact_check_outlined,
            color: Colors.white38,
            size: 64,
          ),
          SizedBox(height: 12),
          Text(
            "Sin equipos asignados",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            "Cuando tengas jefes de equipo y agentes aparecerá aquí el control de actividad.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return _glassCard(
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.orangeAccent,
            size: 52,
          ),
          const SizedBox(height: 12),
          const Text(
            "No se pudo cargar el control",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
    EdgeInsets? margin,
  }) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.075),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ControlBackground extends StatelessWidget {
  const _ControlBackground();

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
                Color(0xFF020617),
                Color(0xFF061A2D),
                Color(0xFF0B1026),
              ],
            ),
          ),
        ),
        Positioned(
          top: -110,
          right: -90,
          child: _glow(260, Colors.cyanAccent),
        ),
        Positioned(
          bottom: 160,
          left: -120,
          child: _glow(280, Colors.purpleAccent),
        ),
        Positioned(
          bottom: -120,
          right: -80,
          child: _glow(240, Colors.blueAccent),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.20),
            blurRadius: 120,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}