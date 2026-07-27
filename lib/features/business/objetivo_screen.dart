import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';

class ObjetivoScreen extends StatefulWidget {
  final String role;

  const ObjetivoScreen({super.key, required this.role});

  @override
  State<ObjetivoScreen> createState() => _ObjetivoScreenState();
}

class _ObjetivoScreenState extends State<ObjetivoScreen> {
  final supabase = Supabase.instance.client;

  double primasTotales = 0;
  double primasEquipo = 0;
  double primasPropias = 0;

  double primaNeta = 0;
  double porcentajeDV = 0;

  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  String _limpiarId(dynamic value) {
    if (value == null) return '';

    final texto = value.toString().trim();

    if (texto.isEmpty || texto.toLowerCase() == 'null') {
      return '';
    }

    return texto;
  }

  String _normalizarRol(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _normalizarTexto(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  double _numero(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    final texto = value.toString().trim();

    if (texto.isEmpty) return 0;

    final normalizado = texto.contains(',') && texto.contains('.')
        ? texto.replaceAll('.', '').replaceAll(',', '.')
        : texto.replaceAll(',', '.');

    return double.tryParse(normalizado) ?? 0;
  }

  int _nivelRol(dynamic rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 5;
      case 'director_zona':
        return 4;
      case 'jefe_ventas':
        return 3;
      case 'jefe_equipo':
        return 2;
      case 'agente':
        return 1;
      default:
        return 0;
    }
  }

  Future<Map<String, double>> _getExtornosPeriodo({
    required DateTime start,
    required DateTime end,
    required List<String> authIds,
    required String myAuthId,
  }) async {
    if (authIds.isEmpty) {
      return {
        'prima_total': 0,
        'prima_propia': 0,
        'prima_equipo': 0,
        'prima_mix': 0,
      };
    }

    final anulacionesData = await supabase
        .from('anulaciones_polizas')
        .select('venta_id, prima_extornada, fecha_anulacion')
        .gte('fecha_anulacion', start.toIso8601String())
        .lt('fecha_anulacion', end.toIso8601String());

    final anulaciones = List<Map<String, dynamic>>.from(anulacionesData);

    if (anulaciones.isEmpty) {
      return {
        'prima_total': 0,
        'prima_propia': 0,
        'prima_equipo': 0,
        'prima_mix': 0,
      };
    }

    final ventaIds = anulaciones
        .map((a) => _limpiarId(a['venta_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ventaIds.isEmpty) {
      return {
        'prima_total': 0,
        'prima_propia': 0,
        'prima_equipo': 0,
        'prima_mix': 0,
      };
    }

    final ventasData = await supabase
        .from('ventas')
        .select('id, agente_auth_id, producto')
        .inFilter('id', ventaIds);

    final ventasMap = <String, Map<String, dynamic>>{};

    for (final venta in List<Map<String, dynamic>>.from(ventasData)) {
      final id = _limpiarId(venta['id']);

      if (id.isNotEmpty) {
        ventasMap[id] = venta;
      }
    }

    final autorizados = authIds.toSet();

    double primaTotal = 0;
    double primaPropia = 0;
    double primaEquipo = 0;
    double primaMix = 0;

    for (final anulacion in anulaciones) {
      final ventaId = _limpiarId(anulacion['venta_id']);

      final venta = ventasMap[ventaId];

      if (venta == null) continue;

      final agenteAuthId = _limpiarId(venta['agente_auth_id']);

      if (!autorizados.contains(agenteAuthId)) {
        continue;
      }

      final primaExtornada = _numero(anulacion['prima_extornada']);

      primaTotal += primaExtornada;

      if (agenteAuthId == myAuthId) {
        primaPropia += primaExtornada;
      } else {
        primaEquipo += primaExtornada;
      }

      final producto = _normalizarTexto(venta['producto']);

      if (_esProductoMixDV(producto)) {
        primaMix += primaExtornada;
      }
    }

    return {
      'prima_total': primaTotal,
      'prima_propia': primaPropia,
      'prima_equipo': primaEquipo,
      'prima_mix': primaMix,
    };
  }

  bool _esProductoMixDV(String producto) {
    final normalized = producto.toLowerCase().trim();
    return normalized.contains('decesos') ||
        normalized.contains('vida') ||
        normalized.contains('prima unica') ||
        normalized.contains('prima única');
  }

  List<Map<String, dynamic>> _construirEstructuraValida({
    required Map<String, dynamic> perfil,
    required List<Map<String, dynamic>> todosUsuarios,
  }) {
    final rolRaiz = _normalizarRol(perfil['rol_usuario']);
    final idRaiz = _limpiarId(perfil['id']);
    if (idRaiz.isEmpty) {
      throw Exception(
        'El usuario conectado no tiene un id válido en usuarios.',
      );
    }
    if (rolRaiz == 'administracion' || rolRaiz == 'director_nacional') {
      return todosUsuarios.where((usuario) {
        return _limpiarId(usuario['id']).isNotEmpty &&
            _limpiarId(usuario['auth_id']).isNotEmpty;
      }).toList();
    }
    final hijosPorParent = <String, List<Map<String, dynamic>>>{};
    for (final fila in todosUsuarios) {
      final usuario = Map<String, dynamic>.from(fila);
      final parentId = _limpiarId(usuario['parent_id']);
      if (parentId.isEmpty) continue;
      hijosPorParent
          .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
          .add(usuario);
    }
    final resultado = <Map<String, dynamic>>[Map<String, dynamic>.from(perfil)];
    final visitados = <String>{idRaiz};
    final pendientes = <Map<String, dynamic>>[
      Map<String, dynamic>.from(perfil),
    ];
    while (pendientes.isNotEmpty) {
      final padre = pendientes.removeAt(0);
      final padreId = _limpiarId(padre['id']);
      final nivelPadre = _nivelRol(padre['rol_usuario']);
      final hijos = hijosPorParent[padreId] ?? <Map<String, dynamic>>[];
      for (final hijoOriginal in hijos) {
        final hijo = Map<String, dynamic>.from(hijoOriginal);
        final hijoId = _limpiarId(hijo['id']);
        final nivelHijo = _nivelRol(hijo['rol_usuario']);
        if (hijoId.isEmpty || visitados.contains(hijoId)) continue;
        if (nivelPadre <= 0 || nivelHijo <= 0 || nivelHijo >= nivelPadre)
          continue;
        visitados.add(hijoId);
        resultado.add(hijo);
        pendientes.add(hijo);
      }
    }
    return resultado;
  }

  Future<void> loadData() async {
    try {
      final authUser = supabase.auth.currentUser;

      if (authUser == null) {
        if (mounted) {
          setState(() {
            loading = false;
          });
        }
        return;
      }

      final perfilData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          )
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (perfilData == null) {
        throw Exception(
          'No se encontró el usuario logueado en la tabla usuarios.',
        );
      }

      final perfil = Map<String, dynamic>.from(perfilData);

      final usuariosData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          );

      final todosUsuarios = List<Map<String, dynamic>>.from(usuariosData);

      final estructura = _construirEstructuraValida(
        perfil: perfil,
        todosUsuarios: todosUsuarios,
      );

      final authIdsEstructura = estructura
          .map((u) => _limpiarId(u['auth_id']))
          .where((authId) => authId.isNotEmpty)
          .toSet()
          .toList();

      if (authIdsEstructura.isEmpty) {
        throw Exception(
          'La estructura del usuario no contiene auth_id válidos.',
        );
      }

      final productionPeriod = await ProductionPeriodService.instance.current();
      final start = productionPeriod.start;
      final end = productionPeriod.endExclusive;

      final ventasData = await supabase
          .from('ventas')
          .select(
            'id, prima_anual_neta, producto, agente_auth_id, fecha_efecto',
          )
          .inFilter('agente_auth_id', authIdsEstructura)
          .gte('fecha_efecto', start.toIso8601String())
          .lt('fecha_efecto', end.toIso8601String());

      final ventas = List<Map<String, dynamic>>.from(ventasData).where((venta) {
        return authIdsEstructura.contains(_limpiarId(venta['agente_auth_id']));
      }).toList();

      double totalPrimas = 0;
      double totalMixDV = 0;
      double totalPropias = 0;
      double totalEquipo = 0;

      for (final venta in ventas) {
        final prima = _numero(venta['prima_anual_neta']);

        final agenteAuthId = _limpiarId(venta['agente_auth_id']);

        totalPrimas += prima;

        if (agenteAuthId == authUser.id) {
          totalPropias += prima;
        } else {
          totalEquipo += prima;
        }

        final producto = _normalizarTexto(venta['producto']);

        if (_esProductoMixDV(producto)) {
          totalMixDV += prima;
        }
      }

      final extornos = await _getExtornosPeriodo(
        start: start,
        end: end,
        authIds: authIdsEstructura,
        myAuthId: authUser.id,
      );

      totalPrimas -= extornos['prima_total'] ?? 0;
      totalPropias -= extornos['prima_propia'] ?? 0;
      totalEquipo -= extornos['prima_equipo'] ?? 0;
      totalMixDV -= extornos['prima_mix'] ?? 0;

      if (totalPrimas < 0) totalPrimas = 0;
      if (totalPropias < 0) totalPropias = 0;
      if (totalEquipo < 0) totalEquipo = 0;
      if (totalMixDV < 0) totalMixDV = 0;

      final porcentaje = totalPrimas > 0
          ? (totalMixDV / totalPrimas) * 100
          : 0.0;

      debugPrint('=========================================');
      debugPrint('OBJETIVO SCREEN');
      debugPrint('ROL REAL: ${perfil['rol_usuario']}');
      debugPrint('PERSONAS EN ESTRUCTURA: ${estructura.length}');
      debugPrint('AUTH IDS AUTORIZADOS: ${authIdsEstructura.length}');
      debugPrint('PRIMAS PROPIAS: $totalPropias');
      debugPrint('PRIMAS EQUIPO: $totalEquipo');
      debugPrint('PRIMAS TOTALES: $totalPrimas');
      debugPrint('MIX VIDA + DECESOS + PRIMA ÚNICA: $totalMixDV');
      debugPrint('PORCENTAJE MIX: $porcentaje');
      debugPrint('=========================================');

      if (!mounted) return;

      setState(() {
        primaNeta = totalPrimas;
        porcentajeDV = porcentaje;
        primasPropias = totalPropias;
        primasEquipo = totalEquipo;
        primasTotales = totalPrimas;
        loading = false;
      });
    } catch (e, s) {
      debugPrint('ERROR OBJETIVOS: $e');
      debugPrint('$s');

      if (!mounted) return;

      setState(() {
        primaNeta = 0;
        porcentajeDV = 0;
        primasPropias = 0;
        primasEquipo = 0;
        primasTotales = 0;
        loading = false;
      });
    }
  }

  double get objetivoPrimas {
    final role = widget.role.toLowerCase().trim();

    if (role == 'jefe_equipo') return 10000;
    if (role == 'jefe_ventas') return 11500;
    if (role == 'director_zona') return 15000;
    if (role == 'director_nacional') return 25000;

    return 12000;
  }

  String get roleLabel {
    final role = widget.role.toLowerCase().trim();

    if (role == 'director_nacional') return "Director Nacional";
    if (role == 'director_zona') return "Director de Zona";
    if (role == 'jefe_ventas') return "Jefe de Ventas";
    if (role == 'jefe_equipo') return "Jefe de Equipo";

    return "Agente";
  }

  @override
  Widget build(BuildContext context) {
    final bool objetivoPrimasOk = primaNeta >= objetivoPrimas;
    final bool objetivoDVOk = porcentajeDV >= 30;
    final bool objetivoGeneralOk = objetivoPrimasOk && objetivoDVOk;

    final double progresoPrimas = (primaNeta / objetivoPrimas).clamp(0.0, 1.0);
    final double progresoDV = (porcentajeDV / 30).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      body: Stack(
        children: [
          const _ObjetivoBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
                    children: [
                      _header(objetivoGeneralOk),
                      const SizedBox(height: 24),
                      _heroCard(
                        objetivoGeneralOk: objetivoGeneralOk,
                        progresoPrimas: progresoPrimas,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _miniResumeCard(
                              title: "Propias",
                              value: "${primasPropias.toStringAsFixed(0)} €",
                              icon: Icons.person_rounded,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _miniResumeCard(
                              title: "Equipo",
                              value: "${primasEquipo.toStringAsFixed(0)} €",
                              icon: Icons.groups_rounded,
                              color: Colors.purpleAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _objectiveCard(
                        title: "Objetivo primas",
                        current: "${primaNeta.toStringAsFixed(2)} €",
                        target: "${objetivoPrimas.toStringAsFixed(0)} €",
                        progress: progresoPrimas,
                        ok: objetivoPrimasOk,
                        icon: Icons.trending_up_rounded,
                        color: Colors.cyanAccent,
                        description:
                            "Tienes que alcanzar el volumen de primas marcado para tu perfil.",
                      ),
                      const SizedBox(height: 14),
                      _objectiveCard(
                        title: "Objetivo Decesos + Vida",
                        current: "${porcentajeDV.toStringAsFixed(2)}%",
                        target: "30%",
                        progress: progresoDV,
                        ok: objetivoDVOk,
                        icon: Icons.shield_rounded,
                        color: Colors.greenAccent,
                        description:
                            "Mínimo requerido de producción en Decesos y Vida.",
                      ),
                      const SizedBox(height: 20),
                      _statusPanel(
                        objetivoPrimasOk: objetivoPrimasOk,
                        objetivoDVOk: objetivoDVOk,
                        objetivoGeneralOk: objetivoGeneralOk,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(bool objetivoGeneralOk) {
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Objetivos",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                "Control de primas y Decesos + Vida",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: objetivoGeneralOk
                ? Colors.greenAccent.withOpacity(0.13)
                : Colors.orangeAccent.withOpacity(0.13),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: objetivoGeneralOk
                  ? Colors.greenAccent.withOpacity(0.30)
                  : Colors.orangeAccent.withOpacity(0.30),
            ),
          ),
          child: Icon(
            objetivoGeneralOk
                ? Icons.verified_rounded
                : Icons.rocket_launch_rounded,
            color: objetivoGeneralOk ? Colors.greenAccent : Colors.orangeAccent,
            size: 25,
          ),
        ),
      ],
    );
  }

  Widget _heroCard({
    required bool objetivoGeneralOk,
    required double progresoPrimas,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF062C68), Color(0xFF10114A), Color(0xFF050B12)],
        ),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.24)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.24),
            blurRadius: 35,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -20,
            child: Icon(
              objetivoGeneralOk
                  ? Icons.emoji_events_rounded
                  : Icons.track_changes_rounded,
              color: objetivoGeneralOk
                  ? Colors.amberAccent.withOpacity(0.16)
                  : Colors.cyanAccent.withOpacity(0.12),
              size: 145,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                roleLabel.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.66),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "${primaNeta.toStringAsFixed(0)} €",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 50,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "de ${objetivoPrimas.toStringAsFixed(0)} € en primas",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: LinearProgressIndicator(
                  value: progresoPrimas,
                  minHeight: 9,
                  backgroundColor: Colors.white.withOpacity(0.10),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    objetivoGeneralOk ? Colors.greenAccent : Colors.cyanAccent,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _statusChip(
                    objetivoGeneralOk ? "Objetivo OK" : "En progreso",
                    objetivoGeneralOk
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    objetivoGeneralOk
                        ? Icons.check_circle_rounded
                        : Icons.auto_graph_rounded,
                  ),
                  const Spacer(),
                  Text(
                    "${(progresoPrimas * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
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

  Widget _miniResumeCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.16), Colors.white.withOpacity(0.045)],
        ),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          _premiumIcon(icon, color, 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _objectiveCard({
    required String title,
    required String current,
    required String target,
    required double progress,
    required bool ok,
    required IconData icon,
    required Color color,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: ok
              ? Colors.greenAccent.withOpacity(0.24)
              : Colors.white.withOpacity(0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _premiumIcon(icon, ok ? Colors.greenAccent : color, 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _statusChip(
                ok ? "OK" : "FALTA",
                ok ? Colors.greenAccent : Colors.redAccent,
                ok ? Icons.check_rounded : Icons.close_rounded,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                current,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              Text(
                target,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(
                ok ? Colors.greenAccent : color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPanel({
    required bool objetivoPrimasOk,
    required bool objetivoDVOk,
    required bool objetivoGeneralOk,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            objetivoGeneralOk
                ? Colors.greenAccent.withOpacity(0.14)
                : Colors.orangeAccent.withOpacity(0.12),
            Colors.white.withOpacity(0.045),
          ],
        ),
        border: Border.all(
          color: objetivoGeneralOk
              ? Colors.greenAccent.withOpacity(0.28)
              : Colors.orangeAccent.withOpacity(0.24),
        ),
      ),
      child: Row(
        children: [
          _premiumIcon(
            objetivoGeneralOk
                ? Icons.emoji_events_rounded
                : Icons.rocket_launch_rounded,
            objetivoGeneralOk ? Colors.amberAccent : Colors.orangeAccent,
            58,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              objetivoGeneralOk
                  ? "Perfecto. Cumples primas y el mínimo de Decesos + Vida."
                  : _mensajePendiente(objetivoPrimasOk, objetivoDVOk),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _mensajePendiente(bool primasOk, bool dvOk) {
    if (!primasOk && !dvOk) {
      return "Todavía faltan primas y también subir el porcentaje de Decesos + Vida.";
    }

    if (!primasOk) {
      return "El porcentaje de Decesos + Vida está bien. Ahora falta alcanzar primas.";
    }

    return "Las primas están conseguidas. Falta llegar al 30% en Decesos + Vida.";
  }

  Widget _statusChip(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumIcon(IconData icon, Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.34),
            color.withOpacity(0.10),
            Colors.white.withOpacity(0.025),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

class _ObjetivoBackground extends StatelessWidget {
  const _ObjetivoBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF050B12), Color(0xFF071A2E), Color(0xFF050B12)],
            ),
          ),
        ),
        Positioned(
          top: -150,
          right: -100,
          child: _glow(Colors.cyanAccent, 330, 0.15),
        ),
        Positioned(
          bottom: -170,
          left: -110,
          child: _glow(Colors.blueAccent, 370, 0.14),
        ),
        Positioned(
          top: 310,
          left: -130,
          child: _glow(Colors.purpleAccent, 250, 0.08),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(color: Colors.black.withOpacity(0.05)),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
      ),
    );
  }
}
