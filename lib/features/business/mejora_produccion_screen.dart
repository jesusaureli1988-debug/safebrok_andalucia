import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MejoraProduccionScreen extends StatefulWidget {
  const MejoraProduccionScreen({super.key});

  @override
  State<MejoraProduccionScreen> createState() => _MejoraProduccionScreenState();
}

class _MejoraProduccionScreenState extends State<MejoraProduccionScreen> {
  final supabase = Supabase.instance.client;

  bool cargando = true;
  String? error;

  double produccionActual = 0;
  double objetivo = 12000;
  int referenciasActivas = 0;

  Map<String, int> ventasPorProducto = {
    'Decesos': 0,
    'Hogar': 0,
    'Vida': 0,
    'Salud': 0,
    'Auto': 0,
  };

  DateTime get inicioCiclo {
  final now = DateTime.now();

  if (now.day >= 24) {
    return DateTime(now.year, now.month, 24);
  }

  return DateTime(now.year, now.month - 1, 24);
}

  DateTime get finCiclo {
  return DateTime(inicioCiclo.year, inicioCiclo.month + 1, 24);
}

  double get porcentajeObjetivo {
    if (objetivo <= 0) return 0;
    return (produccionActual / objetivo).clamp(0.0, 1.0);
  }

  double get mixDecesosVida {
    final decesos = ventasPorProducto['Decesos'] ?? 0;
    final vida = ventasPorProducto['Vida'] ?? 0;
    final total = ventasPorProducto.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 0;
    return ((decesos + vida) / total) * 100;
  }

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
  }

  String _euros(double value) {
    final n = value.round().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < n.length; i++) {
      final pos = n.length - i;
      buffer.write(n[i]);
      if (pos > 1 && pos % 3 == 1) buffer.write('.');
    }
    return '${buffer.toString()}€';
  }

  Future<void> cargarDatos() async {
  try {
    setState(() {
      cargando = true;
      error = null;
    });

    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() {
        cargando = false;
        error = 'No hay usuario iniciado.';
      });
      return;
    }

    final perfil = await supabase
        .from('usuarios')
        .select('id, auth_id, rol_usuario, email')
        .eq('auth_id', user.id)
        .maybeSingle();

    if (perfil == null) {
      setState(() {
        cargando = false;
        error = 'Usuario no encontrado.';
      });
      return;
    }

    String limpiar(dynamic value) {
      return (value ?? '').toString().trim();
    }

    final userId = limpiar(perfil['id']);
    final userAuthId = limpiar(perfil['auth_id']);
    final role = limpiar(perfil['rol_usuario']);

    double produccion = 0;
    int referencias = 0;
    double objetivoLocal = 12000;
    List<Map<String, dynamic>> ventas = [];

    if (role == 'director_nacional') {
      setState(() {
        produccionActual = 0;
        objetivo = 0;
        referenciasActivas = 0;
        ventasPorProducto = {
          'Decesos': 0,
          'Hogar': 0,
          'Vida': 0,
          'Salud': 0,
          'Auto': 0,
        };
        cargando = false;
      });
      return;
    }

    if (role == 'jefe_equipo') {
      objetivoLocal = 10000;
    } else if (role == 'jefe_ventas') {
      objetivoLocal = 12000;
    } else if (role == 'director_zona') {
      objetivoLocal = 15000;
    } else {
      objetivoLocal = 12000;
    }

    final usuariosData = await supabase
        .from('usuarios')
        .select('id, auth_id, parent_id, rol_usuario');

    final usuariosTabla = List<Map<String, dynamic>>.from(usuariosData);

    final authIdsPermitidos = <String>{};

    if (role == 'agente') {
      authIdsPermitidos.add(userAuthId);
    } else {
      final idsVisitados = <String>{userId};

      void buscarDescendientes(String parentId) {
        for (final u in usuariosTabla) {
          final idUsuario = limpiar(u['id']);
          final parentUsuario = limpiar(u['parent_id']);
          final authUsuario = limpiar(u['auth_id']);

          if (parentUsuario == parentId &&
              idUsuario.isNotEmpty &&
              !idsVisitados.contains(idUsuario)) {
            idsVisitados.add(idUsuario);

            if (authUsuario.isNotEmpty && authUsuario != 'null') {
              authIdsPermitidos.add(authUsuario);
            }

            buscarDescendientes(idUsuario);
          }
        }
      }

      if (userAuthId.isNotEmpty && userAuthId != 'null') {
        authIdsPermitidos.add(userAuthId);
      }

      buscarDescendientes(userId);
    }

    if (authIdsPermitidos.isNotEmpty) {
      final ventasData = await supabase
    .from('ventas')
    .select('id, prima_anual_neta, producto, fecha_efecto, agente_auth_id')
    .inFilter('agente_auth_id', authIdsPermitidos.toList())
    .gte('fecha_efecto', inicioCiclo.toIso8601String())
    .lt('fecha_efecto', finCiclo.toIso8601String());

      ventas = List<Map<String, dynamic>>.from(ventasData);

for (final v in ventas) {
  produccion += _toDouble(v['prima_anual_neta']);
}

final extornosData = await supabase
    .from('anulaciones_polizas')
    .select('venta_id, prima_extornada, fecha_anulacion')
    .eq('estado', 'ANULADA')
    .gte('fecha_anulacion', inicioCiclo.toIso8601String())
    .lt('fecha_anulacion', finCiclo.toIso8601String());

final extornos = List<Map<String, dynamic>>.from(extornosData);

if (extornos.isNotEmpty) {
  final ventaIdsExtorno = extornos
      .map((e) => e['venta_id']?.toString())
      .where((id) => id != null && id.isNotEmpty && id != 'null')
      .cast<String>()
      .toSet()
      .toList();

  if (ventaIdsExtorno.isNotEmpty) {
    final ventasExtornadasData = await supabase
        .from('ventas')
        .select('id, agente_auth_id, producto')
        .inFilter('id', ventaIdsExtorno);

    final ventasExtornadasMap = {
      for (final v in List<Map<String, dynamic>>.from(ventasExtornadasData))
        v['id'].toString(): v,
    };

    for (final extorno in extornos) {
      final ventaId = extorno['venta_id']?.toString();
      final ventaOriginal = ventasExtornadasMap[ventaId];

      if (ventaOriginal == null) continue;

      final agenteAuthId = ventaOriginal['agente_auth_id']?.toString();

      if (agenteAuthId == null || !authIdsPermitidos.contains(agenteAuthId)) {
        continue;
      }

      final primaExtornada = _toDouble(extorno['prima_extornada']);

      produccion -= primaExtornada;

      ventas.add({
        'id': 'extorno_${extorno['venta_id']}',
        'producto': ventaOriginal['producto'],
        'prima_anual_neta': -primaExtornada,
        'fecha_efecto': extorno['fecha_anulacion'],
        'agente_auth_id': agenteAuthId,
        'tipo_movimiento': 'EXTORNO',
      });
    }
  }
}

if (produccion < 0) produccion = 0;

      final refs = await supabase
          .from('referencias_viables')
          .select('id')
          .inFilter('auth_id', authIdsPermitidos.toList());

      referencias = refs.length;
    }

    final map = {
      'Decesos': 0,
      'Hogar': 0,
      'Vida': 0,
      'Salud': 0,
      'Auto': 0,
    };

    for (final v in ventas) {
  final producto = v['producto']?.toString().trim();

  if (producto == null) continue;

  final esExtorno = v['tipo_movimiento'] == 'EXTORNO';
  final movimiento = esExtorno ? -1 : 1;

  final p = producto.toLowerCase();

  if (p.contains('decesos')) {
    map['Decesos'] = math.max(0, map['Decesos']! + movimiento);
  } else if (p.contains('hogar')) {
    map['Hogar'] = math.max(0, map['Hogar']! + movimiento);
  } else if (p.contains('vida')) {
    map['Vida'] = math.max(0, map['Vida']! + movimiento);
  } else if (p.contains('salud')) {
    map['Salud'] = math.max(0, map['Salud']! + movimiento);
  } else if (p.contains('auto') || p.contains('coche')) {
    map['Auto'] = math.max(0, map['Auto']! + movimiento);
  }
}

    setState(() {
      produccionActual = produccion;
      objetivo = objetivoLocal;
      referenciasActivas = referencias;
      ventasPorProducto = map;
      cargando = false;
    });
  } catch (e) {
    setState(() {
      cargando = false;
      error = e.toString();
    });
  }
}

  @override
  Widget build(BuildContext context) {
    final double faltante = math.max(0.0, objetivo - produccionActual);

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _BackgroundGlow(),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: cargarDatos,
              backgroundColor: const Color(0xFF0F172A),
              color: Colors.cyanAccent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
                children: [
                  _header(),

                  if (cargando) ...[
                    const SizedBox(height: 120),
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ] else if (error != null) ...[
                    const SizedBox(height: 40),
                    _glassCard(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Colors.orangeAccent,
                            size: 42,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No se pudieron cargar los datos',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: _bigMetricCard(
                            title: 'Producción actual',
                            value: _euros(produccionActual),
                            icon: Icons.trending_up_rounded,
                            accent: Colors.cyanAccent,
                            footer: produccionActual >= objetivo
                                ? 'Objetivo superado'
                                : 'Sigue avanzando',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _objectiveCard(faltante),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    _portfolioCard(),

                    const SizedBox(height: 18),

                    _needsCard(),

                    const SizedBox(height: 18),

                    _referencesCard(),

                    const SizedBox(height: 18),

                    _motivationCard(),
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
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.55)),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.18),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mejora tu producción',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.query_stats_rounded,
                    color: Colors.cyanAccent,
                    size: 28,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Ciclo del ${inicioCiclo.day}/${inicioCiclo.month}/${inicioCiclo.year} al ${finCiclo.day}/${finCiclo.month}/${finCiclo.year}',
                style: const TextStyle(
                  color: Colors.white60,
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

  Widget _bigMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    required String footer,
  }) {
    return _glassCard(
      borderColor: accent.withOpacity(0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _circleIcon(icon, accent),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                color: accent,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
            ),
            child: Text(
              footer,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _objectiveCard(double faltante) {
    return _glassCard(
      borderColor: Colors.purpleAccent.withOpacity(0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _circleIcon(Icons.track_changes_rounded, Colors.purpleAccent),
          const SizedBox(height: 14),
          const Text(
            'Objetivo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              _euros(objetivo),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: porcentajeObjetivo,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.12),
              valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(porcentajeObjetivo * 100).toStringAsFixed(1)}% completado',
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            faltante <= 0 ? 'Objetivo cumplido' : 'Te faltan ${_euros(faltante)}',
            style: TextStyle(
              color: faltante <= 0 ? Colors.greenAccent : Colors.orangeAccent,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _portfolioCard() {
    return _glassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.business_center_rounded,
            title: 'Tu cartera actual',
            subtitle: 'Ventas por producto en el ciclo actual',
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 620;

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _productsList()),
                    Container(
                      width: 1,
                      height: 250,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      color: Colors.white.withOpacity(0.12),
                    ),
                    SizedBox(width: 260, child: _mixCard()),
                  ],
                );
              }

              return Column(
                children: [
                  _productsList(),
                  const SizedBox(height: 16),
                  _mixCard(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _productsList() {
    return Column(
      children: [
        _productRow('Decesos', Icons.shield_rounded, Colors.purpleAccent, 10),
        _productRow('Hogar', Icons.home_rounded, Colors.greenAccent, 5),
        _productRow('Vida', Icons.favorite_rounded, Colors.pinkAccent, 3),
        _productRow('Salud', Icons.medical_services_rounded, Colors.blueAccent, 2),
        _productRow('Auto', Icons.directions_car_rounded, Colors.orangeAccent, 4),
      ],
    );
  }

  Widget _productRow(String producto, IconData icon, Color color, int maxObjetivo) {
    final cantidad = ventasPorProducto[producto] ?? 0;
    final progreso = maxObjetivo == 0 ? 0.0 : (cantidad / maxObjetivo).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          _smallIcon(icon, color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progreso,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.10),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$cantidad ventas',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mixCard() {
    final cumple = mixDecesosVida >= 30;
    final valor = (mixDecesosVida / 100).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cumple
              ? Colors.greenAccent.withOpacity(0.30)
              : Colors.orangeAccent.withOpacity(0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _circleIcon(Icons.pie_chart_rounded, Colors.purpleAccent, size: 44),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Mix Decesos + Vida',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 130,
            width: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 130,
                  width: 130,
                  child: CircularProgressIndicator(
                    value: valor,
                    strokeWidth: 13,
                    backgroundColor: Colors.white.withOpacity(0.13),
                    valueColor: AlwaysStoppedAnimation(
                      cumple ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${mixDecesosVida.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: cumple ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'mínimo 30%',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (cumple ? Colors.greenAccent : Colors.orangeAccent).withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (cumple ? Colors.greenAccent : Colors.orangeAccent).withOpacity(0.30),
              ),
            ),
            child: Text(
              cumple ? '✔ Mix correcto' : '⚠ Aumenta Decesos + Vida',
              style: TextStyle(
                color: cumple ? Colors.greenAccent : Colors.orangeAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _needsCard() {
    return _glassCard(
      padding: const EdgeInsets.all(20),
      borderColor: Colors.purpleAccent.withOpacity(0.30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.rocket_launch_rounded,
            title: 'Qué necesitas vender',
            subtitle: 'Basado en objetivos recomendados',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _needBox('Decesos', Icons.shield_rounded, Colors.purpleAccent, 10),
              _needBox('Hogar', Icons.home_rounded, Colors.greenAccent, 5),
              _needBox('Vida', Icons.favorite_rounded, Colors.pinkAccent, 3),
              _needBox('Salud', Icons.medical_services_rounded, Colors.blueAccent, 2),
              _needBox('Auto', Icons.directions_car_rounded, Colors.orangeAccent, 4),
            ],
          ),
        ],
      ),
    );
  }

  Widget _needBox(String producto, IconData icon, Color color, int objetivoProducto) {
    final actual = ventasPorProducto[producto] ?? 0;
    final faltan = math.max(0, objetivoProducto - actual);

    return Container(
      width: 142,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Column(
        children: [
          _smallIcon(icon, color),
          const SizedBox(height: 8),
          Text(
            producto,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Objetivo', style: TextStyle(color: Colors.white60, fontSize: 12)),
          Text(
            '$objetivoProducto',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text('Actual', style: TextStyle(color: Colors.white60, fontSize: 12)),
          Text(
            '$actual',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 8),
          Text(
            faltan == 0 ? '✔ OK' : 'Faltan $faltan',
            style: TextStyle(
              color: faltan == 0 ? Colors.greenAccent : Colors.orangeAccent,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _referencesCard() {
    return _glassCard(
      borderColor: Colors.cyanAccent.withOpacity(0.32),
      child: Row(
        children: [
          _circleIcon(Icons.groups_rounded, Colors.cyanAccent, size: 58),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Referencias activas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Oportunidades en curso',
                  style: TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
          Text(
            referenciasActivas.toString(),
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _motivationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            Colors.purpleAccent.withOpacity(0.24),
            Colors.cyanAccent.withOpacity(0.18),
          ],
        ),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.16),
            blurRadius: 28,
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.star_rounded, color: Colors.amberAccent, size: 34),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Cada acción te acerca a tu objetivo.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '¡Tú puedes! 💪',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        _circleIcon(icon, Colors.cyanAccent, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white60,
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

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
    Color? borderColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.075),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.12),
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
    );
  }

  Widget _circleIcon(IconData icon, Color color, {double size = 52}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.32),
            color.withOpacity(0.08),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }

  Widget _smallIcon(IconData icon, Color color) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.16),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow();

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
          top: -120,
          right: -90,
          child: _glow(260, Colors.cyanAccent),
        ),
        Positioned(
          bottom: 180,
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
        color: color.withOpacity(0.16),
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