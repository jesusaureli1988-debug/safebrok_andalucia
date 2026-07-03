import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safebrok_andalucia/features/payroll/nominas_screen.dart';
import 'objetivo_screen.dart';
import 'package:safebrok_andalucia/features/sales/create_sale_wizard.dart';
import 'package:safebrok_andalucia/features/sales/my_sales_screen.dart';
import 'package:safebrok_andalucia/features/referrals/referral_screen.dart';
import 'referencias_screen.dart';
import 'package:safebrok_andalucia/features/business/mejora_produccion_screen.dart';
import 'package:safebrok_andalucia/features/business/ranking_comercial_screen.dart';
import 'package:safebrok_andalucia/features/team/team_dashboard_screen.dart';

class BusinessScreen extends StatefulWidget {
  final String role;

  const BusinessScreen({
    super.key,
    required this.role,
  });

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool _objetivoCumplido = false;

  double saldoTotal = 0;
  double esteMes = 0;
  double objetivo = 0;

  double variacionMesAnterior = 0;
bool variacionPositiva = true;

  double primasPropiasJefe = 0;
  double comisionesPropiasJefe = 0;
  double primasTotalesJefe = 0;
  double rappelJefeVentas = 0;

  List<Map<String, dynamic>> ventas = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() => loading = false);
      }
      return;
    }

    try {
      final now = DateTime.now();

      final start = now.day >= 24
          ? DateTime(now.year, now.month, 24)
          : DateTime(now.year, now.month - 1, 24);

      final end = now.day >= 24
          ? DateTime(now.year, now.month + 1, 24)
          : DateTime(now.year, now.month, 24);

          final previousStart = DateTime(start.year, start.month - 1, start.day);
final previousEnd = start;

      primasPropiasJefe = 0;
      comisionesPropiasJefe = 0;
      primasTotalesJefe = 0;
      rappelJefeVentas = 0;

      double primasDV = 0;
      double primasTotales = 0;
      double porcentajeDV = 0;

      final ventasPropias = await supabase
          .from('ventas')
          .select('prima_anual_neta, comision, producto')
          .eq('agente_auth_id', user.id)
          .gte('fecha_efecto', start.toIso8601String())
          .lt('fecha_efecto', end.toIso8601String());

      for (final v in ventasPropias) {
        final prima = (v['prima_anual_neta'] ?? 0).toDouble();

        primasPropiasJefe += prima;
        comisionesPropiasJefe += (v['comision'] ?? 0).toDouble();

        final producto = (v['producto'] ?? '').toString().toLowerCase();

        if (producto.contains('vida') || producto.contains('decesos')) {
          primasDV += prima;
        }
      }

      final userProfile = await supabase
          .from('usuarios')
          .select('rol_usuario, id')
          .eq('auth_id', user.id)
          .maybeSingle();

      final role = userProfile?['rol_usuario'];
      final userId = userProfile?['id'];

      

      List<Map<String, dynamic>> ultimasVentasRaw = [];

      if (role == 'jefe_equipo') {
        final agentes = await supabase
            .from('usuarios')
            .select('auth_id')
            .eq('parent_id', userId);

        final ids = (agentes as List)
            .map((e) => e['auth_id'] as String)
            .toList();

        if (ids.isNotEmpty) {
          ultimasVentasRaw = await supabase
              .from('ventas')
              .select('producto, precio, cliente_id')
              .inFilter('agente_auth_id', ids)
              .order('fecha_efecto', ascending: false)
              .limit(2);
        }
      } else if (role == 'jefe_ventas') {
        final jefesEquipo = await supabase
            .from('usuarios')
            .select('id')
            .eq('parent_id', userId);

        final jefesEquipoIds = (jefesEquipo as List)
            .map((e) => e['id'] as String)
            .toList();

        if (jefesEquipoIds.isNotEmpty) {
          final agentes = await supabase
              .from('usuarios')
              .select('auth_id')
              .inFilter('parent_id', jefesEquipoIds);

          final agentesIds = (agentes as List)
              .map((e) => e['auth_id'] as String)
              .toList();

          if (agentesIds.isNotEmpty) {
            ultimasVentasRaw = await supabase
                .from('ventas')
                .select('producto, precio, cliente_id')
                .inFilter('agente_auth_id', agentesIds)
                .order('fecha_efecto', ascending: false)
                .limit(2);
          }
        }
      } else if (role == 'director_zona') {
  final usuariosData = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id');

  final usuariosTabla = List<Map<String, dynamic>>.from(usuariosData);

  String limpiar(dynamic value) {
    return (value ?? '').toString().trim();
  }

  final idsPermitidos = <String>{userId.toString()};
  final authIdsPermitidos = <String>{user.id};

  void buscarDescendientes(String parentId) {
    for (final u in usuariosTabla) {
      final idUsuario = limpiar(u['id']);
      final parentUsuario = limpiar(u['parent_id']);
      final authIdUsuario = limpiar(u['auth_id']);

      if (parentUsuario == parentId &&
          idUsuario.isNotEmpty &&
          !idsPermitidos.contains(idUsuario)) {
        idsPermitidos.add(idUsuario);

        if (authIdUsuario.isNotEmpty) {
          authIdsPermitidos.add(authIdUsuario);
        }

        buscarDescendientes(idUsuario);
      }
    }
  }

  buscarDescendientes(userId.toString());

  ultimasVentasRaw = await supabase
      .from('ventas')
      .select('producto, precio, cliente_id')
      .inFilter('agente_auth_id', authIdsPermitidos.toList())
      .order('fecha_efecto', ascending: false)
      .limit(2);
} else if (role == 'director_nacional') {
  ultimasVentasRaw = await supabase
      .from('ventas')
      .select('producto, precio, cliente_id')
      .order('fecha_efecto', ascending: false)
      .limit(2);
} else {
  ultimasVentasRaw = await supabase
      .from('ventas')
      .select('producto, precio, cliente_id')
      .eq('agente_auth_id', user.id)
      .order('fecha_efecto', ascending: false)
      .limit(2);
}

      final clientes = await supabase.from('clientes').select('id, nombre');

      final clientesMap = {
        for (final c in clientes) c['id']: c['nombre'],
      };

     double primasEquipo = 0;

if (role == 'jefe_equipo' ||
    role == 'jefe_ventas' ||
    role == 'director_zona') {
  primasEquipo = await getPrimasEquipo(userId.toString(), role, start, end);

        if (role == 'jefe_equipo') {
          final agentes = await supabase
              .from('usuarios')
              .select('auth_id')
              .eq('parent_id', userId);

          final ids = (agentes as List)
              .map((e) => e['auth_id'] as String)
              .toList();

          if (ids.isNotEmpty) {
            final ventasDVEquipo = await supabase
                .from('ventas')
                .select('prima_anual_neta, producto')
                .inFilter('agente_auth_id', ids)
                .gte('fecha_efecto', start.toIso8601String())
                .lt('fecha_efecto', end.toIso8601String());

            for (final v in ventasDVEquipo) {
              final producto =
                  (v['producto'] ?? '').toString().toLowerCase();

              if (producto.contains('vida') || producto.contains('decesos')) {
                primasDV += (v['prima_anual_neta'] ?? 0).toDouble();
              }
            }
          }
        }

        if (role == 'jefe_ventas') {
          final jefes = await supabase
              .from('usuarios')
              .select('id')
              .eq('parent_id', userId);

          final jefesIds =
              (jefes as List).map((e) => e['id'] as String).toList();

          if (jefesIds.isNotEmpty) {
            final agentes = await supabase
                .from('usuarios')
                .select('auth_id')
                .inFilter('parent_id', jefesIds);

            final agentesIds = (agentes as List)
                .map((e) => e['auth_id'] as String)
                .toList();

            if (agentesIds.isNotEmpty) {
              final ventasDV = await supabase
                  .from('ventas')
                  .select('prima_anual_neta, producto')
                  .inFilter('agente_auth_id', agentesIds)
                  .gte('fecha_efecto', start.toIso8601String())
                  .lt('fecha_efecto', end.toIso8601String());

              for (final v in ventasDV) {
                final producto =
                    (v['producto'] ?? '').toString().toLowerCase();

                if (producto.contains('vida') || producto.contains('decesos')) {
                  primasDV += (v['prima_anual_neta'] ?? 0).toDouble();
                }
              }
            }
          }
        }
      }

      if (role == 'agente') {
        primasTotales = primasPropiasJefe;
      } else {
        primasTotales = primasPropiasJefe + primasEquipo;
      }

      double primasPeriodoAnterior = 0;

if (role == 'agente') {
  final ventasAnterior = await supabase
      .from('ventas')
      .select('prima_anual_neta')
      .eq('agente_auth_id', user.id)
      .gte('fecha_efecto', previousStart.toIso8601String())
      .lt('fecha_efecto', previousEnd.toIso8601String());

  for (final v in ventasAnterior) {
    primasPeriodoAnterior += (v['prima_anual_neta'] ?? 0).toDouble();
  }
} else if (role == 'jefe_equipo' || role == 'jefe_ventas') {
  primasPeriodoAnterior = await getPrimasEquipo(
    userId,
    role,
    previousStart,
    previousEnd,
  );

  final ventasPropiasAnterior = await supabase
      .from('ventas')
      .select('prima_anual_neta')
      .eq('agente_auth_id', user.id)
      .gte('fecha_efecto', previousStart.toIso8601String())
      .lt('fecha_efecto', previousEnd.toIso8601String());

  for (final v in ventasPropiasAnterior) {
    primasPeriodoAnterior += (v['prima_anual_neta'] ?? 0).toDouble();
  }
}

final variacion = primasPeriodoAnterior > 0
    ? ((primasTotales - primasPeriodoAnterior) / primasPeriodoAnterior) * 100
    : primasTotales > 0
        ? 100.0
        : 0.0;

      double rappelJefe = 0;

      if (role == 'jefe_equipo') {
        rappelJefe = calcularRappelJefe(primasTotales);
      }

      if (role == 'jefe_ventas') {
        rappelJefeVentas = calcularRappelJefeVentas(primasTotales);
      }

      double objetivoPrimas = 12000;

      if (role == 'jefe_equipo') {
        objetivoPrimas = 10000;
      }

      if (role == 'jefe_ventas') {
        objetivoPrimas = 11500;
      }

      porcentajeDV = primasTotales > 0 ? (primasDV / primasTotales) * 100 : 0;

      final objetivoCumplido =
          primasTotales >= objetivoPrimas && porcentajeDV >= 30;

      final progreso = (primasTotales / objetivoPrimas).clamp(0.0, 1.0);

      final ultimasVentasConNombre = ultimasVentasRaw.map((v) {
        final clienteId = v['cliente_id'];

        return {
          ...v,
          'cliente_nombre': clientesMap[clienteId] ?? 'Sin cliente',
        };
      }).toList();

      if (!mounted) return;

    setState(() {
  if (role == 'jefe_equipo') {
    saldoTotal = comisionesPropiasJefe + rappelJefe;
  } else if (role == 'jefe_ventas') {
    saldoTotal = comisionesPropiasJefe + rappelJefeVentas;
  } else if (role == 'director_zona') {
    saldoTotal = calcularRappelDirectorZona(primasTotales);
  } else if (role == 'director_nacional') {
    saldoTotal = 0;
  } else {
    saldoTotal = comisionesPropiasJefe;
  }

  esteMes = saldoTotal;
  objetivo = progreso * 100;
  ventas = ultimasVentasConNombre;
  _objetivoCumplido = objetivoCumplido;

  variacionMesAnterior = variacion;
  variacionPositiva = variacion >= 0;

  loading = false;
});
    } catch (e) {
      debugPrint('ERROR BUSINESS SCREEN: $e');

      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  double calcularRappelJefe(double primasTotales) {
    if (primasTotales < 4000) return 0;

    if (primasTotales >= 10000) {
      return 2000 + ((primasTotales - 10000) ~/ 1000) * 100;
    }

    if (primasTotales >= 9000) return 1800;
    if (primasTotales >= 8000) return 1600;
    if (primasTotales >= 7000) return 1400;
    if (primasTotales >= 6000) return 1200;
    if (primasTotales >= 5000) return 1000;
    if (primasTotales >= 4000) return 800;

    return 0;
  }

  double calcularRappelJefeVentas(double primasTotales) {
    if (primasTotales >= 11500) {
      return 2500 + ((primasTotales - 11500) ~/ 1000) * 100;
    }

    if (primasTotales >= 10500) return 2300;
    if (primasTotales >= 9500) return 2100;
    if (primasTotales >= 8500) return 1900;
    if (primasTotales >= 7500) return 1700;
    if (primasTotales >= 6500) return 1500;

    return 0;
  }

  double calcularRappelDirectorZona(double primasTotales) {
  if (primasTotales < 15000) return 0;

  double sueldo = 2500;

  if (primasTotales <= 20000) {
    sueldo += (primasTotales - 15000) * 0.04;
  } else {
    sueldo += 200; // 4% de los 5.000 € entre 15.000 y 20.000
    sueldo += (primasTotales - 20000) * 0.05;
  }

  return sueldo;
}

  Future<double> getPrimasEquipo(
  String jefeId,
  String role,
  DateTime start,
  DateTime end,
) async {
  final usuariosData = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, rol_usuario');

  final usuariosTabla = List<Map<String, dynamic>>.from(usuariosData);

  String limpiar(dynamic value) {
    return (value ?? '').toString().trim();
  }

  final idsPermitidos = <String>{};

  void buscarDescendientes(String parentId) {
    for (final u in usuariosTabla) {
      final idUsuario = limpiar(u['id']);
      final parentUsuario = limpiar(u['parent_id']);

      if (parentUsuario == parentId &&
          idUsuario.isNotEmpty &&
          !idsPermitidos.contains(idUsuario)) {
        idsPermitidos.add(idUsuario);
        buscarDescendientes(idUsuario);
      }
    }
  }

  buscarDescendientes(jefeId);

  final agentesAuthIds = usuariosTabla.where((u) {
    final idUsuario = limpiar(u['id']);
    final authId = limpiar(u['auth_id']);

    return idsPermitidos.contains(idUsuario) && authId.isNotEmpty;
  }).map((u) {
    return limpiar(u['auth_id']);
  }).toList();

  if (agentesAuthIds.isEmpty) return 0;

  final ventasEquipo = await supabase
      .from('ventas')
      .select('prima_anual_neta')
      .inFilter('agente_auth_id', agentesAuthIds)
      .gte('fecha_efecto', start.toIso8601String())
      .lt('fecha_efecto', end.toIso8601String());

  double total = 0;

  for (final v in ventasEquipo) {
    final primaRaw = v['prima_anual_neta'];

    final prima = primaRaw is num
        ? primaRaw.toDouble()
        : double.tryParse(primaRaw?.toString() ?? '0') ?? 0;

    total += prima;
  }

  return total;
}
    @override
  Widget build(BuildContext context) {
    final progresoObjetivo = (objetivo / 100).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.transparent,
        elevation: 0,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CreateSaleWizard(),
            ),
          );
        },
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [
                Color(0xFF20E070),
                Color(0xFF1D7CFF),
                Color(0xFF7A3CFF),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.45),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.add_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),

          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
                    children: [
                      _header(),

                      const SizedBox(height: 22),

                      _saldoPrincipal(),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child: _metricCard(
                              title: "Este mes",
                              value: "${esteMes.toStringAsFixed(0)} €",
                              subtitle: "Importe generado",
                              icon: Icons.trending_up_rounded,
                              color: Colors.cyanAccent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _metricCard(
                              title: "Objetivo",
                              value: "${objetivo.toStringAsFixed(1)}%",
                              subtitle: _objetivoCumplido
                                  ? "Objetivo cumplido"
                                  : "En progreso",
                              icon: Icons.track_changes_rounded,
                              color: _objetivoCumplido
                                  ? Colors.greenAccent
                                  : Colors.purpleAccent,
                              circularValue: progresoObjetivo,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      _objetivoCard(progresoObjetivo),

                      const SizedBox(height: 24),

                      _quickActions(),

                      const SizedBox(height: 24),

                      _businessSection(
                        title: "Últimas ventas",
                        icon: Icons.receipt_long_outlined,
                        trailing: TextButton(
                          onPressed: () {
                            if (widget.role == 'jefe_equipo') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeamDashboardScreen(),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MySalesScreen(),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            "Ver todas",
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        child: ventas.isEmpty
                            ? _emptySales()
                            : Column(
                                children: ventas
                                    .map(
                                      (v) => _saleRow(
                                        producto: v['producto']?.toString() ??
                                            'Venta',
                                        cliente:
                                            v['cliente_nombre']?.toString() ??
                                                'Sin cliente',
                                        importe: "${v['precio']}€",
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),

                      const SizedBox(height: 20),

                      _businessSection(
                        title: "Descubre más",
                        icon: Icons.explore_outlined,
                        child: Column(
                          children: [
                            _discoverRow(
                              icon: Icons.card_giftcard_rounded,
                              title: "Trae a un amigo",
                              color: Colors.orangeAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ReferralScreen(),
                                  ),
                                );
                              },
                            ),
                            _discoverRow(
                              icon: Icons.people_alt_rounded,
                              title: "Referencias viables",
                              color: Colors.purpleAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ReferenciasScreen(),
                                  ),
                                );
                              },
                            ),
                            _discoverRow(
                              icon: Icons.rocket_launch_rounded,
                              title: "Mejora tu producción",
                              color: Colors.greenAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const MejoraProduccionScreen(),
                                  ),
                                );
                              },
                            ),
                            _discoverRow(
                              icon: Icons.emoji_events_rounded,
                              title: "Ranking comercial",
                              color: Colors.amberAccent,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RankingComercialScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.18),
                Colors.white.withOpacity(0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.18),
            ),
          ),
          child: const Icon(
            Icons.account_circle_rounded,
            color: Colors.white,
            size: 38,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Negocio",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              Text(
                "Panel económico y producción comercial",
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
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          child: Icon(
            _objetivoCumplido
                ? Icons.verified_rounded
                : Icons.trending_up_rounded,
            color: _objetivoCumplido ? Colors.greenAccent : Colors.orangeAccent,
            size: 25,
          ),
        ),
      ],
    );
  }

 Widget _saldoPrincipal() {
  return Container(
    width: double.infinity,
    height: 238,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(34),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF062C68),
          Color(0xFF071B3E),
          Color(0xFF050B12),
        ],
      ),
      border: Border.all(
        color: Colors.cyanAccent.withOpacity(0.28),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.blueAccent.withOpacity(0.22),
          blurRadius: 35,
          offset: const Offset(0, 18),
        ),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 4,
          right: -8,
          top: 86,
          child: CustomPaint(
            size: const Size(double.infinity, 90),
            painter: _MiniChartPainter(
              positive: variacionPositiva,
            ),
          ),
        ),

        Positioned(
          right: -18,
          top: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: (variacionPositiva ? Colors.greenAccent : Colors.redAccent)
                  .withOpacity(0.15),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color:
                    (variacionPositiva ? Colors.greenAccent : Colors.redAccent)
                        .withOpacity(0.34),
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (variacionPositiva ? Colors.greenAccent : Colors.redAccent)
                          .withOpacity(0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  variacionPositiva
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color:
                      variacionPositiva ? Colors.greenAccent : Colors.redAccent,
                  size: 17,
                ),
                const SizedBox(width: 5),
                Text(
                  "${variacionMesAnterior.abs().toStringAsFixed(1)}%",
                  style: TextStyle(
                    color:
                        variacionPositiva ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),

        Positioned(
          right: -30,
          bottom: -34,
          child: Icon(
            variacionPositiva
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 155,
            color: (variacionPositiva ? Colors.greenAccent : Colors.redAccent)
                .withOpacity(0.055),
          ),
        ),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "SALDO GENERADO",
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              "${saldoTotal.toStringAsFixed(0)} €",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 50,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
              ),
            ),

            const Spacer(),

            Row(
              children: [
                Text(
                  "vs mes anterior",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  "Periodo actual",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.42),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    double? circularValue,
  }) {
    return Container(
  constraints: const BoxConstraints(
    minHeight: 142,
  ),
  padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.18),
            Colors.white.withOpacity(0.045),
          ],
        ),
        border: Border.all(
          color: color.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _hexIcon(icon, color, 42),
              const Spacer(),
              if (circularValue != null)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: circularValue,
                    strokeWidth: 7,
                    backgroundColor: Colors.white.withOpacity(0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.64),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _objetivoCard(double progresoObjetivo) {
  final bool objetivoOk = _objetivoCumplido || progresoObjetivo >= 1;

  final Color colorBase = objetivoOk
      ? Colors.amberAccent
      : progresoObjetivo >= 0.80
          ? Colors.purpleAccent
          : Colors.cyanAccent;

  final IconData iconoCentro = objetivoOk
      ? Icons.workspace_premium_rounded
      : progresoObjetivo >= 0.80
          ? Icons.emoji_events_rounded
          : Icons.shield_rounded;

  return Container(
    height: 250,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(34),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF061B36),
          colorBase.withOpacity(0.15),
          const Color(0xFF080A18),
        ],
      ),
      border: Border.all(
        color: colorBase.withOpacity(0.34),
      ),
      boxShadow: [
        BoxShadow(
          color: colorBase.withOpacity(0.18),
          blurRadius: 32,
          offset: const Offset(0, 18),
        ),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -8,
          top: 10,
          bottom: 8,
          child: _objetivoEscudoPremium(
            color: colorBase,
            icon: iconoCentro,
          ),
        ),

        Positioned(
          right: 8,
          bottom: 10,
          child: Container(
            width: 130,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(100),
              color: colorBase.withOpacity(0.12),
              boxShadow: [
                BoxShadow(
                  color: colorBase.withOpacity(0.26),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),

        SizedBox(
          width: MediaQuery.of(context).size.width * 0.48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "OBJETIVO DEL MES",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                "Tu progreso actual",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.58),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 22),

              ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: [
                      Colors.white,
                      colorBase,
                    ],
                  ).createShader(bounds);
                },
                child: Text(
                  "${objetivo.toStringAsFixed(1)}%",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 47,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                  ),
                ),
              ),

              Text(
                "del objetivo",
                style: TextStyle(
                  color: colorBase,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 18),

              ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: LinearProgressIndicator(
                  value: progresoObjetivo,
                  minHeight: 10,
                  backgroundColor: Colors.white.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(colorBase),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
Widget _objetivoEscudoPremium({
  required Color color,
  required IconData icon,
}) {
  return SizedBox(
    width: 155,
    height: 190,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.22),
                blurRadius: 34,
                spreadRadius: 5,
              ),
            ],
          ),
        ),

        CustomPaint(
          size: const Size(132, 155),
          painter: _ShieldPainter(color),
        ),

        Positioned(
          top: 47,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.22),
                  color.withOpacity(0.42),
                  color.withOpacity(0.10),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.30),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 42,
            ),
          ),
        ),

        Positioned(
          left: 2,
          bottom: 28,
          child: Icon(
            Icons.spa_rounded,
            color: color.withOpacity(0.60),
            size: 44,
          ),
        ),

        Positioned(
          right: 2,
          bottom: 28,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(3.1416),
            child: Icon(
              Icons.spa_rounded,
              color: color.withOpacity(0.60),
              size: 44,
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(
          child: _premiumAction(
            icon: Icons.calendar_month_rounded,
            title: "Mes",
            color: Colors.cyanAccent,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NominasScreen(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _premiumAction(
            icon: Icons.track_changes_rounded,
            title: "Objetivo",
            color: Colors.purpleAccent,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ObjetivoScreen(role: widget.role),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _premiumAction(
            icon: Icons.more_horiz_rounded,
            title: "Más",
            color: Colors.orangeAccent,
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const MoreMenuSheet(),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _premiumAction({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        splashColor: color.withOpacity(0.10),
        highlightColor: color.withOpacity(0.06),
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                color.withOpacity(0.18),
                Colors.white.withOpacity(0.045),
              ],
            ),
            border: Border.all(
              color: color.withOpacity(0.28),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _hexIcon(icon, color, 45),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _businessSection({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.065),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.09),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _hexIcon(icon, Colors.cyanAccent, 42),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _emptySales() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Text(
        "Sin ventas registradas todavía",
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withOpacity(0.58),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _saleRow({
    required String producto,
    required String cliente,
    required String importe,
  }) {
    final color = producto.toLowerCase().contains('vida')
        ? Colors.purpleAccent
        : Colors.greenAccent;

    final icon = producto.toLowerCase().contains('vida')
        ? Icons.favorite_rounded
        : Icons.home_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          _hexIcon(icon, color, 48),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  cliente,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            importe,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _discoverRow({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: color.withOpacity(0.10),
        highlightColor: color.withOpacity(0.06),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
            ),
          ),
          child: Row(
            children: [
              _hexIcon(icon, color, 46),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withOpacity(0.35),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hexIcon(IconData icon, Color color, double size) {
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
        border: Border.all(
          color: color.withOpacity(0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: color,
        size: size * 0.48,
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
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF050B12),
                Color(0xFF071A2E),
                Color(0xFF050B12),
              ],
            ),
          ),
        ),
        Positioned(
          top: -150,
          right: -100,
          child: _glow(Colors.cyanAccent, 330, 0.16),
        ),
        Positioned(
          bottom: -170,
          left: -110,
          child: _glow(Colors.blueAccent, 370, 0.15),
        ),
        Positioned(
          top: 330,
          left: -120,
          child: _glow(Colors.purpleAccent, 240, 0.08),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            color: Colors.black.withOpacity(0.05),
          ),
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

class MoreMenuSheet extends StatelessWidget {
  const MoreMenuSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF071421),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(32),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Más opciones",
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          _item(Icons.bar_chart_rounded, "Estadísticas avanzadas"),
          _item(Icons.people_alt_rounded, "Equipo y jerarquía"),
          _item(Icons.history_rounded, "Histórico completo"),
          _item(Icons.calculate_outlined, "Simulador de comisiones"),
          _item(Icons.settings_rounded, "Configuración"),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: Colors.cyanAccent,
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: Colors.white38,
        ),
        onTap: () {},
      ),
    );
  }
}
class _MiniChartPainter extends CustomPainter {
  final bool positive;

  _MiniChartPainter({
    required this.positive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = positive ? Colors.greenAccent : Colors.redAccent;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.055)
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final linePaint = Paint()
      ..color = color.withOpacity(0.98)
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final shadowPaint = Paint()
      ..color = color.withOpacity(0.20)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        8,
      );

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.23),
          color.withOpacity(0.08),
          color.withOpacity(0.00),
        ],
      ).createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

    final path = Path();

    if (positive) {
      path.moveTo(0, size.height * 0.72);
      path.cubicTo(
        size.width * 0.10,
        size.height * 0.67,
        size.width * 0.16,
        size.height * 0.36,
        size.width * 0.28,
        size.height * 0.44,
      );
      path.cubicTo(
        size.width * 0.40,
        size.height * 0.52,
        size.width * 0.44,
        size.height * 0.78,
        size.width * 0.56,
        size.height * 0.58,
      );
      path.cubicTo(
        size.width * 0.68,
        size.height * 0.34,
        size.width * 0.76,
        size.height * 0.22,
        size.width * 0.88,
        size.height * 0.30,
      );
      path.cubicTo(
        size.width * 0.94,
        size.height * 0.34,
        size.width * 0.97,
        size.height * 0.16,
        size.width,
        size.height * 0.18,
      );
    } else {
      path.moveTo(0, size.height * 0.26);
      path.cubicTo(
        size.width * 0.10,
        size.height * 0.31,
        size.width * 0.16,
        size.height * 0.58,
        size.width * 0.28,
        size.height * 0.48,
      );
      path.cubicTo(
        size.width * 0.40,
        size.height * 0.38,
        size.width * 0.44,
        size.height * 0.20,
        size.width * 0.56,
        size.height * 0.42,
      );
      path.cubicTo(
        size.width * 0.68,
        size.height * 0.66,
        size.width * 0.76,
        size.height * 0.76,
        size.width * 0.88,
        size.height * 0.68,
      );
      path.cubicTo(
        size.width * 0.94,
        size.height * 0.64,
        size.width * 0.97,
        size.height * 0.84,
        size.width,
        size.height * 0.82,
      );
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, linePaint);

    final dot = positive
        ? Offset(size.width, size.height * 0.18)
        : Offset(size.width, size.height * 0.82);

    final glowPaint = Paint()
      ..color = color.withOpacity(0.24)
      ..style = PaintingStyle.fill;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dotBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.90)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(dot, 11, glowPaint);
    canvas.drawCircle(dot, 5, dotPaint);
    canvas.drawCircle(dot, 6.5, dotBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) {
    return oldDelegate.positive != positive;
  }
}
class _ShieldPainter extends CustomPainter {
  final Color color;

  _ShieldPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.50, 0)
      ..lineTo(size.width * 0.88, size.height * 0.18)
      ..lineTo(size.width * 0.82, size.height * 0.70)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height,
        size.width * 0.18,
        size.height * 0.70,
      )
      ..lineTo(size.width * 0.12, size.height * 0.18)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.28),
          color.withOpacity(0.45),
          color.withOpacity(0.12),
        ],
      ).createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.75)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.35)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        8,
      );

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}