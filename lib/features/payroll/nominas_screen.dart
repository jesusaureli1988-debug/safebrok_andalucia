import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NominasScreen extends StatefulWidget {
  const NominasScreen({super.key});

  @override
  State<NominasScreen> createState() => _NominasScreenState();
}

class _NominasScreenState extends State<NominasScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> nominas = [];
  bool loading = true;
  String? role;

  @override
  void initState() {
    super.initState();
    loadNominas();
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

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _keyMes(DateTime fecha) {
  return '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';
}

DateTime? _fechaEfecto(Map<String, dynamic> venta) {
  final posibles = [
    venta['fecha_efecto'],
    venta['FECHA_EFECTO'],
    venta['fecha efecto'],
    venta['FECHA EFECTO'],
    venta['fecha'],
    venta['FECHA'],
    venta['created_at'],
  ];

  for (final value in posibles) {
    if (value == null) continue;

    final parsed = DateTime.tryParse(value.toString());

    if (parsed != null) {
      return parsed;
    }
  }

  return null;
}

List<Map<String, dynamic>> _ordenarNominas(
  Map<String, Map<String, dynamic>> grouped,
) {
  final list = grouped.values.toList();

  list.sort((a, b) {
    final anioA = int.tryParse(a['anio'].toString()) ?? 0;
    final mesA = int.tryParse(a['mes'].toString()) ?? 0;

    final anioB = int.tryParse(b['anio'].toString()) ?? 0;
    final mesB = int.tryParse(b['mes'].toString()) ?? 0;

    final fechaA = DateTime(anioA, mesA);
    final fechaB = DateTime(anioB, mesB);

    return fechaB.compareTo(fechaA);
  });

  return list;
}

void _sumarVentaEnNomina({
  required Map<String, Map<String, dynamic>> grouped,
  required Map<String, dynamic> venta,
  required String tipo,
  required bool sumaComision,
}) {
  final fecha = _fechaEfecto(venta);

  if (fecha == null) return;

  final key = _keyMes(fecha);

  grouped.putIfAbsent(key, () {
    return {
      'mes': fecha.month,
      'anio': fecha.year,
      'prima_neta_total': 0.0,
      'comisiones': 0.0,
      'rappel': 0.0,
      'sueldo_fijo': 0.0,
      'total_cobrar': 0.0,
      'tipo': tipo,
    };
  });

  final prima = _money(venta['prima_anual_neta']);
  final comision = _money(venta['comision']);

  grouped[key]!['prima_neta_total'] =
      _money(grouped[key]!['prima_neta_total']) + prima;

  if (sumaComision) {
    grouped[key]!['comisiones'] =
        _money(grouped[key]!['comisiones']) + comision;
  }
}

void _sumarBajaEnNomina({
  required Map<String, Map<String, dynamic>> grouped,
  required Map<String, dynamic> baja,
  required String tipo,
  required bool restaComision,
}) {
  final fecha = DateTime.tryParse(
    baja['fecha_anulacion']?.toString() ?? '',
  );

  if (fecha == null) return;

  final key = _keyMes(fecha);

  grouped.putIfAbsent(key, () {
    return {
      'mes': fecha.month,
      'anio': fecha.year,
      'prima_neta_total': 0.0,
      'comisiones': 0.0,
      'rappel': 0.0,
      'sueldo_fijo': 0.0,
      'total_cobrar': 0.0,
      'tipo': tipo,
      'bajas_primas': 0.0,
      'bajas_comisiones': 0.0,
    };
  });

  final primaExtornada = _money(baja['prima_extornada']);
  final comisionExtornada = _money(baja['comision_extornada']);

  grouped[key]!['prima_neta_total'] =
      _money(grouped[key]!['prima_neta_total']) - primaExtornada;

  grouped[key]!['bajas_primas'] =
      _money(grouped[key]!['bajas_primas']) + primaExtornada;

  if (restaComision) {
    grouped[key]!['comisiones'] =
        _money(grouped[key]!['comisiones']) - comisionExtornada;

    grouped[key]!['bajas_comisiones'] =
        _money(grouped[key]!['bajas_comisiones']) + comisionExtornada;
  }
}

Future<void> _aplicarBajasEnNominas({
  required Map<String, Map<String, dynamic>> grouped,
  required List<String> authIds,
  required String tipo,
  required String? authIdComision,
}) async {
  if (authIds.isEmpty) return;

  final anulacionesData = await supabase
      .from('anulaciones_polizas')
      .select()
      .eq('estado', 'ANULADA');

  final anulaciones = List<Map<String, dynamic>>.from(anulacionesData);

  if (anulaciones.isEmpty) return;

  final ventaIds = anulaciones
      .map((a) => a['venta_id']?.toString())
      .where((id) => id != null && id.isNotEmpty && id != 'null')
      .cast<String>()
      .toSet()
      .toList();

  if (ventaIds.isEmpty) return;

  final ventasData = await supabase
      .from('ventas')
      .select('id, agente_auth_id')
      .inFilter('id', ventaIds);

  final ventasMap = {
    for (final v in List<Map<String, dynamic>>.from(ventasData))
      v['id'].toString(): v,
  };

  for (final baja in anulaciones) {
    final ventaId = baja['venta_id']?.toString();
    final venta = ventasMap[ventaId];

    if (venta == null) continue;

    final agenteAuthId = venta['agente_auth_id']?.toString();

    if (agenteAuthId == null || !authIds.contains(agenteAuthId)) {
      continue;
    }

    _sumarBajaEnNomina(
      grouped: grouped,
      baja: baja,
      tipo: tipo,
      restaComision: authIdComision != null && agenteAuthId == authIdComision,
    );
  }
}

Future<void> loadNominas() async {
  final user = supabase.auth.currentUser;

  if (user == null) {
    setState(() => loading = false);
    return;
  }

  try {
    setState(() => loading = true);

    final profile = await supabase
        .from('usuarios')
        .select('rol_usuario, id')
        .eq('auth_id', user.id)
        .maybeSingle();

    role = profile?['rol_usuario'];
    final userId = profile?['id'];

    if (role == 'agente') {
      final ventas = await supabase
          .from('ventas')
          .select()
          .eq('agente_auth_id', user.id);

      final grouped = <String, Map<String, dynamic>>{};

      for (final venta in ventas) {
        _sumarVentaEnNomina(
          grouped: grouped,
          venta: Map<String, dynamic>.from(venta),
          tipo: 'Agente comercial',
          sumaComision: true,
        );
      }

      await _aplicarBajasEnNominas(
  grouped: grouped,
  authIds: [user.id],
  tipo: 'Agente comercial',
  authIdComision: user.id,
);

      for (final n in grouped.values) {
        n['total_cobrar'] = _money(n['comisiones']);
      }

      setState(() {
        nominas = _ordenarNominas(grouped);
        loading = false;
      });

      return;
    }

    if (role == 'jefe_equipo') {
      await _loadJefeEquipo(user.id, userId);
      return;
    }

    if (role == 'jefe_ventas') {
      await _loadJefeVentas(user.id, userId);
      return;
    }
    if (role == 'director_zona' || role == 'director_nacional') {
  await _loadDirector(user.id, userId);
  return;
}

    setState(() {
      nominas = [];
      loading = false;
    });
  } catch (e) {
    debugPrint('ERROR LOAD NOMINAS: $e');

    if (!mounted) return;

    setState(() {
      nominas = [];
      loading = false;
    });
  }
}

Future<void> _loadJefeEquipo(String authId, dynamic userId) async {
  try {
    final agentes = await supabase
        .from('usuarios')
        .select('auth_id')
        .eq('parent_id', userId)
        .eq('rol_usuario', 'agente');

    final agentesIds = (agentes as List)
        .map((a) => a['auth_id']?.toString())
        .where((id) => id != null && id.isNotEmpty && id != 'null')
        .cast<String>()
        .toList();

    final grouped = <String, Map<String, dynamic>>{};

    if (agentesIds.isNotEmpty) {
      final ventasEquipo = await supabase
          .from('ventas')
          .select()
          .inFilter('agente_auth_id', agentesIds);

      for (final venta in ventasEquipo) {
        _sumarVentaEnNomina(
          grouped: grouped,
          venta: Map<String, dynamic>.from(venta),
          tipo: 'Jefe de equipo',
          sumaComision: false,
        );
      }
    }

    final ventasPropias = await supabase
        .from('ventas')
        .select()
        .eq('agente_auth_id', authId);

    for (final venta in ventasPropias) {
      _sumarVentaEnNomina(
        grouped: grouped,
        venta: Map<String, dynamic>.from(venta),
        tipo: 'Jefe de equipo',
        sumaComision: true,
      );
    }

    await _aplicarBajasEnNominas(
  grouped: grouped,
  authIds: [...agentesIds, authId],
  tipo: 'Jefe de equipo',
  authIdComision: authId,
);

    for (final n in grouped.values) {
      final primasTotales = _money(n['prima_neta_total']);
      final comisiones = _money(n['comisiones']);
      final rappel = calcularRappelJefe(primasTotales);

      n['rappel'] = rappel;
      n['total_cobrar'] = comisiones + rappel;
    }

    setState(() {
      nominas = _ordenarNominas(grouped);
      loading = false;
    });
  } catch (e) {
    debugPrint('ERROR NOMINAS JEFE EQUIPO: $e');

    if (!mounted) return;

    setState(() {
      nominas = [];
      loading = false;
    });
  }
}

Future<void> _loadJefeVentas(String authId, dynamic userId) async {
  try {
    final jefesEquipo = await supabase
        .from('usuarios')
        .select('id, auth_id')
        .eq('parent_id', userId)
        .eq('rol_usuario', 'jefe_equipo');

    final jefesEquipoIds = (jefesEquipo as List)
        .map((e) => e['id']?.toString())
        .where((id) => id != null && id.isNotEmpty && id != 'null')
        .cast<String>()
        .toList();

    final estructuraAuthIds = <String>[];

    for (final jefe in jefesEquipo) {
      final jefeAuthId = jefe['auth_id']?.toString();

      if (jefeAuthId != null &&
          jefeAuthId.isNotEmpty &&
          jefeAuthId != 'null') {
        estructuraAuthIds.add(jefeAuthId);
      }
    }

    if (jefesEquipoIds.isNotEmpty) {
      final agentes = await supabase
          .from('usuarios')
          .select('auth_id')
          .inFilter('parent_id', jefesEquipoIds)
          .eq('rol_usuario', 'agente');

      for (final agente in agentes) {
        final agenteAuthId = agente['auth_id']?.toString();

        if (agenteAuthId != null &&
            agenteAuthId.isNotEmpty &&
            agenteAuthId != 'null') {
          estructuraAuthIds.add(agenteAuthId);
        }
      }
    }

    final grouped = <String, Map<String, dynamic>>{};

    if (estructuraAuthIds.isNotEmpty) {
      final ventasEquipo = await supabase
          .from('ventas')
          .select()
          .inFilter('agente_auth_id', estructuraAuthIds);

      for (final venta in ventasEquipo) {
        _sumarVentaEnNomina(
          grouped: grouped,
          venta: Map<String, dynamic>.from(venta),
          tipo: 'Jefe de ventas',
          sumaComision: false,
        );
      }
    }

    final ventasPropias = await supabase
        .from('ventas')
        .select()
        .eq('agente_auth_id', authId);

    for (final venta in ventasPropias) {
      _sumarVentaEnNomina(
        grouped: grouped,
        venta: Map<String, dynamic>.from(venta),
        tipo: 'Jefe de ventas',
        sumaComision: true,
      );
    }

    await _aplicarBajasEnNominas(
  grouped: grouped,
  authIds: [...estructuraAuthIds, authId],
  tipo: 'Jefe de ventas',
  authIdComision: authId,
);

    for (final n in grouped.values) {
      final primasTotales = _money(n['prima_neta_total']);
      final comisiones = _money(n['comisiones']);
      final rappel = calcularRappelJefeVentas(primasTotales);

      n['rappel'] = rappel;
      n['total_cobrar'] = comisiones + rappel;
    }

    setState(() {
      nominas = _ordenarNominas(grouped);
      loading = false;
    });
  } catch (e) {
    debugPrint('ERROR NOMINAS JEFE VENTAS: $e');

    if (!mounted) return;

    setState(() {
      nominas = [];
      loading = false;
    });
  }
}
Future<void> _loadDirector(String authId, dynamic userId) async {
  try {
    final usuarios = await supabase
        .from('usuarios')
        .select('auth_id')
        .neq('rol_usuario', 'director_nacional');

    final authIds = (usuarios as List)
        .map((u) => u['auth_id']?.toString())
        .where((id) => id != null && id.isNotEmpty && id != 'null')
        .cast<String>()
        .toList();

    final grouped = <String, Map<String, dynamic>>{};

    if (authIds.isNotEmpty) {
      final ventas = await supabase
          .from('ventas')
          .select()
          .inFilter('agente_auth_id', authIds);

      for (final venta in ventas) {
        _sumarVentaEnNomina(
          grouped: grouped,
          venta: Map<String, dynamic>.from(venta),
          tipo: 'Factura estructura',
          sumaComision: false,
        );
      }
    }

    await _aplicarBajasEnNominas(
  grouped: grouped,
  authIds: authIds,
  tipo: 'Factura estructura',
  authIdComision: null,
);

    for (final n in grouped.values) {
      final primasTotales = _money(n['prima_neta_total']);

      n['rappel'] = 0.0;
      n['comisiones'] = 0.0;
      n['total_cobrar'] = primasTotales;
      n['tipo'] = 'Factura estructura';
    }

    setState(() {
      nominas = _ordenarNominas(grouped);
      loading = false;
    });
  } catch (e) {
    debugPrint('ERROR NOMINAS DIRECTOR: $e');

    if (!mounted) return;

    setState(() {
      nominas = [];
      loading = false;
    });
  }
}

  String nombreMes(dynamic mes) {
    final m = mes is int ? mes : int.tryParse(mes.toString()) ?? 0;

    const meses = [
      '',
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];

    if (m < 1 || m > 12) return '';
    return meses[m];
  }

  double get totalAcumulado {
    return nominas.fold(0, (sum, n) => sum + _money(n['total_cobrar']));
  }

  double get primasAcumuladas {
    return nominas.fold(0, (sum, n) => sum + _money(n['prima_neta_total']));
  }

  double get rappelAcumulado {
    return nominas.fold(0, (sum, n) => sum + _money(n['rappel']));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Mis facturas',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: loadNominas,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
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
                : RefreshIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF102331),
                    onRefresh: loadNominas,
                    child: nominas.isEmpty
                        ? _emptyState()
                        : CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(child: _header()),
                              SliverToBoxAdapter(child: _kpiPanel()),
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  16,
                                  110,
                                ),
                                sliver: SliverList.builder(
                                  itemCount: nominas.length,
                                  itemBuilder: (context, index) {
                                    final n = nominas[index];
                                    return _nominaCard(n, index);
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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.14),
                  Colors.white.withOpacity(0.045),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 62,
                      width: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Colors.greenAccent,
                            Colors.cyanAccent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent.withOpacity(0.22),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.black,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Centro de facturas',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            role == null
                                ? 'Resumen económico personal'
                                : 'Resumen económico · $role',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.58),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  '${totalAcumulado.toStringAsFixed(2)} €',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total previsto a cobrar',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _kpiCard(
              'Primas netas',
              '${primasAcumuladas.toStringAsFixed(0)} €',
              Icons.trending_up_rounded,
              Colors.cyanAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              'Rappel',
              '${rappelAcumulado.toStringAsFixed(0)} €',
              Icons.emoji_events_rounded,
              Colors.amberAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 11),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontWeight: FontWeight.w600,
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

  Widget _nominaCard(Map<String, dynamic> n, int index) {
   final total = _money(n['comisiones']) +
    _money(n['rappel']) +
    _money(n['sueldo_fijo']);
    final mes = nombreMes(n['mes']);
    final anio = n['anio'] ?? '';
    final tipo = n['tipo'] ?? 'Nómina mensual';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + (index * 45)),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NominaDetailScreen(
  nomina: n,
  role: role,
),
                ),
              );
            },
            child: Ink(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.10),
                    Colors.white.withOpacity(0.035),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.24),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.cyanAccent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Factura $mes $anio',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tipo.toString(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.52),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _pill(
                              'Primas ${_money(n['prima_neta_total']).toStringAsFixed(0)} €',
                              Colors.cyanAccent,
                            ),
                            const SizedBox(width: 8),
                            _pill(
                              'Rappel ${_money(n['rappel']).toStringAsFixed(0)} €',
                              Colors.amberAccent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${total.toStringAsFixed(2)} €',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.11),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.20),
        Icon(
          Icons.receipt_long_outlined,
          size: 82,
          color: Colors.white.withOpacity(0.16),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'Sin nóminas disponibles',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Cuando tengas datos económicos aparecerán aquí.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.52),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FacturaNode {
  final Map<String, dynamic> usuario;
  final String rol;
  final List<_FacturaNode> hijos;
  final List<Map<String, dynamic>> polizas;

  _FacturaNode({
    required this.usuario,
    required this.rol,
    this.hijos = const [],
    this.polizas = const [],
  });
}

class NominaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> nomina;
  final String? role;

  const NominaDetailScreen({
    super.key,
    required this.nomina,
    required this.role,
  });

  @override
  State<NominaDetailScreen> createState() => _NominaDetailScreenState();
}

class _NominaDetailScreenState extends State<NominaDetailScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? currentRole;
  dynamic currentUserId;

  List<_FacturaNode> estructura = [];

  @override
  void initState() {
    super.initState();
    cargarEstructuraFactura();
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
  double _primaBrutaVenta(Map<String, dynamic> venta) {
  return _money(
    venta['prima_anual_bruta'] ??
    venta['prima_bruta'] ??
    venta['prima_total'] ??
    venta['precio_anual'] ??
    venta['prima_anual_neta']
  );
}

double _primaNetaVenta(Map<String, dynamic> venta) {
  return _money(venta['prima_anual_neta']);
}

double _comisionVenta(Map<String, dynamic> venta) {
  return _money(venta['comision']);
}

double _calcularRappelJefe(double primasTotales) {
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

double _calcularRappelJefeVentas(double primasTotales) {
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

double _primasBrutasNode(_FacturaNode node) {
  double total = 0;

  for (final p in node.polizas) {
    final r = p['revision_nomina'] ?? {};
    if (r['incluida'] == false) continue;
    total += _primaBrutaVenta(p);
  }

  for (final h in node.hijos) {
    total += _primasBrutasNode(h);
  }

  return total;
}

double _comisionesPropiasNode(_FacturaNode node) {
  double total = 0;

  for (final p in node.polizas) {
    final r = p['revision_nomina'] ?? {};
    if (r['incluida'] == false) continue;
    total += _comisionVenta(p);
  }

  return total;
}

double _rappelNode(_FacturaNode node) {
  final primas = _primasNode(node);

  if (node.rol == 'jefe_equipo') {
    return _calcularRappelJefe(primas);
  }

  if (node.rol == 'jefe_ventas') {
    return _calcularRappelJefeVentas(primas);
  }

  return 0;
}

double _fijoNode(_FacturaNode node) {
  return 0;
}

double _totalSueldoNode(_FacturaNode node) {
  return _comisionesPropiasNode(node) +
      _rappelNode(node) +
      _fijoNode(node);
}

  String nombreMes(dynamic mes) {
    final m = mes is int ? mes : int.tryParse(mes.toString()) ?? 0;
    const meses = [
      '',
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    if (m < 1 || m > 12) return '';
    return meses[m];
  }

  DateTime? _fechaEfecto(Map<String, dynamic> venta) {
    final posibles = [
      venta['fecha_efecto'],
      venta['FECHA_EFECTO'],
      venta['fecha efecto'],
      venta['FECHA EFECTO'],
      venta['fecha'],
      venta['FECHA'],
      venta['created_at'],
    ];

    for (final value in posibles) {
      if (value == null) continue;
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed;
    }

    return null;
  }

  String _nombreUsuario(Map<String, dynamic> u) {
  final nombre = u['nombre']?.toString().trim() ?? '';
  final apellidos = u['apellidos']?.toString().trim() ?? '';
  final completo = '$nombre $apellidos'.trim();

  if (completo.isNotEmpty) return completo;

  return (u['email'] ?? 'Usuario sin nombre').toString();
}

  String _nombreCliente(Map<String, dynamic> venta) {
  final cliente = venta['cliente_data'];

  if (cliente is Map) {
    final nombre = cliente['nombre']?.toString().trim() ?? '';
    final apellidos = cliente['apellidos']?.toString().trim() ?? '';

    final completo = '$nombre $apellidos'.trim();

    if (completo.isNotEmpty) return completo;
  }

  return (venta['nombre_cliente'] ??
          venta['cliente_nombre'] ??
          venta['nombre_completo'] ??
          venta['nombre'] ??
          venta['NOMBRE_CLIENTE'] ??
          venta['NOMBRE Y APELLIDOS DEL CLIENTE'] ??
          venta['cliente'] ??
          venta['titular'] ??
          'Cliente sin nombre')
      .toString();
}

  String _numeroPoliza(Map<String, dynamic> venta) {
    return (venta['numero_poliza'] ??
            venta['poliza'] ??
            venta['POLIZA'] ??
            venta['N_POLIZA'] ??
            venta['n_poliza'] ??
            venta['id'] ??
            'Sin número')
        .toString();
  }
  dynamic _clienteIdVenta(Map<String, dynamic> venta) {
  return venta['cliente_id'] ??
      venta['id_cliente'] ??
      venta['clienteId'] ??
      venta['CLIENTE_ID'];
}

  String _estadoRecibo(Map<String, dynamic> venta) {
  final calculado = venta['estado_recibo_calculado'];

  if (calculado != null && calculado.toString().trim().isNotEmpty) {
    return calculado.toString();
  }

  return (venta['estado_recibo'] ??
          venta['recibo_estado'] ??
          venta['gestion'] ??
          venta['GESTION'] ??
          venta['estado'] ??
          'COBRADO')
      .toString();
}

  String _estadoFirma(Map<String, dynamic> venta) {
    return (venta['estado_firma_ccpp'] ??
            venta['firma_ccpp'] ??
            venta['ccpp'] ??
            'No consultado')
        .toString();
  }

  bool get puedeVerPolizas {
    final rol = _rolCanonico(currentRole);
    return rol == 'director_nacional' ||
        rol == 'director_zona' ||
        rol == 'jefe_ventas' ||
        rol == 'jefe_equipo' ||
        rol == 'agente';
  }

  String _rolCanonico(dynamic value) {
    final raw = value
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if (raw.contains('director') && raw.contains('nacional')) {
      return 'director_nacional';
    }
    if (raw.contains('director') && raw.contains('zona')) {
      return 'director_zona';
    }
    if (raw.contains('jefe') && raw.contains('ventas')) {
      return 'jefe_ventas';
    }
    if (raw.contains('jefe') && raw.contains('equipo')) {
      return 'jefe_equipo';
    }
    if (raw == 'agente' || raw.contains('comercial')) {
      return 'agente';
    }

    return raw;
  }

  Future<void> cargarEstructuraFactura() async {
    try {
      setState(() => loading = true);

      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() => loading = false);
        return;
      }

      final profile = await supabase
          .from('usuarios')
          .select('id, auth_id, rol_usuario')
          .eq('auth_id', user.id)
          .maybeSingle();

      currentRole = profile?['rol_usuario'];
      currentUserId = profile?['id'];

      final usuarios = await supabase
    .from('usuarios')
    .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos, email');

      final listaUsuarios =
          (usuarios as List).map((e) => Map<String, dynamic>.from(e)).toList();

      final int mes = widget.nomina['mes'];
      final int anio = widget.nomina['anio'];

      final inicio = DateTime(anio, mes, 1);
      final fin = DateTime(anio, mes + 1, 1);

      final authIds = listaUsuarios
          .map((u) => u['auth_id']?.toString())
          .where((id) => id != null && id.isNotEmpty && id != 'null')
          .cast<String>()
          .toList();

      final ventas = authIds.isEmpty
          ? []
          : await supabase
              .from('ventas')
              .select()
              .inFilter('agente_auth_id', authIds);

      final ventasMes = <Map<String, dynamic>>[];

      for (final v in ventas as List) {
        final venta = Map<String, dynamic>.from(v);
        final fecha = _fechaEfecto(venta);
        if (fecha == null) continue;

        if (!fecha.isBefore(inicio) && fecha.isBefore(fin)) {
          ventasMes.add(venta);
        }
      }
      final anulacionesData = await supabase
    .from('anulaciones_polizas')
    .select()
    .eq('estado', 'ANULADA')
    .gte('fecha_anulacion', inicio.toIso8601String())
    .lt('fecha_anulacion', fin.toIso8601String());

final anulaciones = List<Map<String, dynamic>>.from(anulacionesData);

final ventaIdsBajas = anulaciones
    .map((a) => a['venta_id']?.toString())
    .where((id) => id != null && id.isNotEmpty && id != 'null')
    .cast<String>()
    .toSet()
    .toList();

if (ventaIdsBajas.isNotEmpty) {
  final ventasBajaData = await supabase
      .from('ventas')
      .select()
      .inFilter('id', ventaIdsBajas);

  final ventasBajaMap = {
    for (final v in List<Map<String, dynamic>>.from(ventasBajaData))
      v['id'].toString(): v,
  };

  for (final baja in anulaciones) {
    final ventaOriginal = ventasBajaMap[baja['venta_id']?.toString()];

    if (ventaOriginal == null) continue;

    final ventaBaja = Map<String, dynamic>.from(ventaOriginal);

    ventaBaja['id'] = 'baja_${baja['id']}';
    ventaBaja['tipo_movimiento'] = 'BAJA';
    ventaBaja['anulacion_id'] = baja['id'];
    ventaBaja['fecha_efecto'] = baja['fecha_anulacion'];
    ventaBaja['prima_anual_neta'] = -_money(baja['prima_extornada']);
    ventaBaja['comision'] = -_money(baja['comision_extornada']);
    ventaBaja['numero_poliza'] = baja['numero_poliza'];
    ventaBaja['nombre_cliente'] = baja['nombre_cliente'];
    ventaBaja['revision_nomina'] = {
      'incluida': true,
      'poliza_verificada': true,
      'verificada_zona': false,
      'verificada_nacional': false,
      'emitida': false,
    };

    ventasMes.add(ventaBaja);
  }
}

      final clienteIds = ventasMes
    .map((v) => _clienteIdVenta(v)?.toString())
    .where((id) => id != null && id.isNotEmpty && id != 'null')
    .cast<String>()
    .toSet()
    .toList();

final clientesMap = <String, Map<String, dynamic>>{};

if (clienteIds.isNotEmpty) {
  final clientes = await supabase
      .from('clientes')
      .select('id, nombre, apellidos')
      .inFilter('id', clienteIds);

  for (final c in clientes as List) {
    clientesMap[c['id'].toString()] = Map<String, dynamic>.from(c);
  }
}

for (final venta in ventasMes) {
  final clienteId = _clienteIdVenta(venta)?.toString();

  if (clienteId != null && clientesMap.containsKey(clienteId)) {
    venta['cliente_data'] = clientesMap[clienteId];
  }
}

final recibos = await supabase
    .from('recibos')
    .select();

for (final venta in ventasMes) {
  final numeroPoliza = _numeroPoliza(venta);
  final clienteId = _clienteIdVenta(venta)?.toString();

  Map<String, dynamic>? reciboEncontrado;

  for (final r in recibos as List) {
    final recibo = Map<String, dynamic>.from(r);

    final reciboPoliza = (recibo['numero_poliza'] ??
            recibo['poliza'] ??
            recibo['n_poliza'] ??
            recibo['N_POLIZA'])
        ?.toString();

    final reciboClienteId = (recibo['cliente_id'] ??
            recibo['id_cliente'] ??
            recibo['CLIENTE_ID'])
        ?.toString();

    if ((reciboPoliza != null && reciboPoliza == numeroPoliza) ||
        (clienteId != null && reciboClienteId == clienteId)) {
      reciboEncontrado = recibo;
      break;
    }
  }

  if (reciboEncontrado == null) {
    venta['estado_recibo_calculado'] = 'COBRADO';
  } else {
    venta['estado_recibo_calculado'] =
        (reciboEncontrado['estado'] ??
                reciboEncontrado['gestion'] ??
                reciboEncontrado['GESTION'] ??
                reciboEncontrado['estado_recibo'] ??
                'PENDIENTE')
            .toString();
  }
}

      await _asegurarRevisiones(ventasMes, listaUsuarios);

      final revisiones = await supabase
          .from('nominas_polizas_revision')
          .select()
          .eq('mes', mes)
          .eq('anio', anio);

      final revisionMap = <String, Map<String, dynamic>>{};

      for (final r in revisiones as List) {
        final key =
            '${r['venta_id']}_${r['nomina_auth_id']}_${r['mes']}_${r['anio']}';
        revisionMap[key] = Map<String, dynamic>.from(r);
      }

      for (final venta in ventasMes) {
        final agenteAuthId = venta['agente_auth_id']?.toString();
        final key =
            '${venta['id']}_${agenteAuthId}_${mes}_${anio}';
        venta['revision_nomina'] = revisionMap[key] ?? {};
      }
      debugPrint('--------------------------------');
debugPrint('ROL: $currentRole');
debugPrint('USER ID: $currentUserId');
debugPrint('USUARIOS: ${listaUsuarios.length}');
debugPrint('VENTAS MES: ${ventasMes.length}');

      final arbol = _crearArbol(listaUsuarios, ventasMes);

      debugPrint('NODOS ARBOL: ${arbol.length}');

      setState(() {
        estructura = arbol;
        loading = false;
      });
    } catch (e) {
      debugPrint('ERROR CARGAR ESTRUCTURA FACTURA: $e');
      if (!mounted) return;
      setState(() {
        estructura = [];
        loading = false;
      });
    }
  }

  Future<void> _asegurarRevisiones(
    List<Map<String, dynamic>> ventasMes,
    List<Map<String, dynamic>> usuarios,
  ) async {
    final int mes = widget.nomina['mes'];
    final int anio = widget.nomina['anio'];

    for (final venta in ventasMes) {
      final agenteAuthId = venta['agente_auth_id']?.toString();
      if (agenteAuthId == null || agenteAuthId.isEmpty) continue;

      final agente = usuarios.firstWhere(
        (u) => u['auth_id']?.toString() == agenteAuthId,
        orElse: () => {},
      );

      final existente = await supabase
          .from('nominas_polizas_revision')
          .select('id')
          .eq('venta_id', venta['id'].toString())
          .eq('nomina_auth_id', agenteAuthId)
          .eq('mes', mes)
          .eq('anio', anio)
          .maybeSingle();

      if (existente != null) continue;

      await supabase.from('nominas_polizas_revision').insert({
        'venta_id': venta['id'].toString(),
        'nomina_auth_id': agenteAuthId,
        'agente_auth_id': agenteAuthId,
        'agente_nombre': _nombreUsuario(agente),
        'mes': mes,
        'anio': anio,
        'rol_nomina': 'agente',
        'incluida': true,
        'poliza_verificada': false,
        'verificada_zona': false,
        'verificada_nacional': false,
        'emitida': false,
        'numero_poliza': _numeroPoliza(venta),
        'cliente_nombre': _nombreCliente(venta),
        'fecha_efecto': _fechaEfecto(venta)?.toIso8601String(),
        'estado_recibo': _estadoRecibo(venta),
        'estado_firma_ccpp': _estadoFirma(venta),
      });
    }
  }

  List<_FacturaNode> _crearArbol(
    List<Map<String, dynamic>> usuarios,
    List<Map<String, dynamic>> ventasMes,
  ) {
    String clean(dynamic value) => value?.toString().trim() ?? '';

    List<Map<String, dynamic>> ventasDe(dynamic authId) {
      final auth = clean(authId);
      if (auth.isEmpty || auth == 'null') return [];

      final result = ventasMes
          .where((v) => clean(v['agente_auth_id']) == auth)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();

      result.sort((a, b) {
        final fechaA = _fechaEfecto(a) ?? DateTime(1900);
        final fechaB = _fechaEfecto(b) ?? DateTime(1900);
        return fechaB.compareTo(fechaA);
      });

      return result;
    }

    Map<String, dynamic> buscarUsuarioConectado() {
      final authActual = clean(supabase.auth.currentUser?.id);

      for (final usuario in usuarios) {
        if (clean(usuario['auth_id']) == authActual) {
          return usuario;
        }
      }

      for (final usuario in usuarios) {
        if (clean(usuario['id']) == clean(currentUserId)) {
          return usuario;
        }
      }

      return <String, dynamic>{};
    }

    List<Map<String, dynamic>> hijosDirectos(
      Map<String, dynamic> padre,
      String rolEsperado,
    ) {
      final padreId = clean(padre['id']);
      if (padreId.isEmpty) return [];

      final hijos = usuarios.where((usuario) {
        return clean(usuario['parent_id']) == padreId &&
            _rolCanonico(usuario['rol_usuario']) == rolEsperado;
      }).map((u) => Map<String, dynamic>.from(u)).toList();

      hijos.sort((a, b) {
        return _nombreUsuario(a)
            .toLowerCase()
            .compareTo(_nombreUsuario(b).toLowerCase());
      });

      return hijos;
    }

    _FacturaNode construirNodo(Map<String, dynamic> usuario) {
      final rol = _rolCanonico(usuario['rol_usuario']);
      String? siguienteRol;

      switch (rol) {
        case 'director_nacional':
          siguienteRol = 'director_zona';
          break;
        case 'director_zona':
          siguienteRol = 'jefe_ventas';
          break;
        case 'jefe_ventas':
          siguienteRol = 'jefe_equipo';
          break;
        case 'jefe_equipo':
          siguienteRol = 'agente';
          break;
        case 'agente':
          siguienteRol = null;
          break;
        default:
          siguienteRol = null;
      }

      final hijos = siguienteRol == null
          ? <Map<String, dynamic>>[]
          : hijosDirectos(usuario, siguienteRol);

      return _FacturaNode(
        usuario: usuario,
        rol: rol,
        polizas: ventasDe(usuario['auth_id']),
        hijos: hijos.map(construirNodo).toList(),
      );
    }

    final miUsuario = buscarUsuarioConectado();

    if (miUsuario.isEmpty) {
      debugPrint(
        'NÓMINAS: no se encontró el usuario conectado en la tabla usuarios.',
      );
      return [];
    }

    final rolActual = _rolCanonico(miUsuario['rol_usuario']);

    debugPrint('--------------------------------');
    debugPrint('CREANDO ÁRBOL PARA: ${_nombreUsuario(miUsuario)}');
    debugPrint('ROL CONECTADO: $rolActual');
    debugPrint('ID CONECTADO: ${clean(miUsuario['id'])}');
    debugPrint('AUTH CONECTADO: ${clean(miUsuario['auth_id'])}');

    if (rolActual == 'director_nacional') {
      final directoresZona =
          hijosDirectos(miUsuario, 'director_zona');

      debugPrint(
        'DIRECTORES DE ZONA DIRECTOS ENCONTRADOS: ${directoresZona.length}',
      );

      for (final dz in directoresZona) {
        debugPrint(
          '  DZ: ${_nombreUsuario(dz)} | ID: ${clean(dz['id'])} '
          '| PARENT: ${clean(dz['parent_id'])}',
        );
      }

      return directoresZona.map(construirNodo).toList();
    }

    if (rolActual == 'director_zona' ||
        rolActual == 'jefe_ventas' ||
        rolActual == 'jefe_equipo' ||
        rolActual == 'agente') {
      return [construirNodo(miUsuario)];
    }

    debugPrint('NÓMINAS: rol no admitido para el árbol: $rolActual');
    return [];
  }

  double _primasNode(_FacturaNode node) {
    double total = 0;

    for (final p in node.polizas) {
      final r = p['revision_nomina'] ?? {};
      if (r['incluida'] == false) continue;
      total += _money(p['prima_anual_neta']);
    }

    for (final h in node.hijos) {
      total += _primasNode(h);
    }

    return total;
  }

  double _comisionesNode(_FacturaNode node) {
    double total = 0;

    if (node.rol == 'agente') {
      for (final p in node.polizas) {
        final r = p['revision_nomina'] ?? {};
        if (r['incluida'] == false) continue;
        total += _money(p['comision']);
      }
    }

    for (final h in node.hijos) {
      total += _comisionesNode(h);
    }

    return total;
  }

  String _estadoNode(_FacturaNode node) {
    final polizas = _todasPolizas(node);

    if (polizas.isEmpty) return 'SIN PÓLIZAS';

    final emitidas = polizas.every((p) {
      final r = p['revision_nomina'] ?? {};
      return r['emitida'] == true;
    });

    final nacional = polizas.every((p) {
      final r = p['revision_nomina'] ?? {};
      return r['verificada_nacional'] == true || r['incluida'] == false;
    });

    final zona = polizas.every((p) {
      final r = p['revision_nomina'] ?? {};
      return r['verificada_zona'] == true || r['incluida'] == false;
    });

    if (emitidas) return 'EMITIDA';
    if (nacional) return 'VERIFICADA · PENDIENTE DE EMISIÓN';
    if (zona) return 'PENDIENTE DIRECTOR NACIONAL';

    return 'PENDIENTE REVISIÓN ZONA';
  }

  List<Map<String, dynamic>> _todasPolizas(_FacturaNode node) {
    final result = <Map<String, dynamic>>[];
    result.addAll(node.polizas);

    for (final h in node.hijos) {
      result.addAll(_todasPolizas(h));
    }

    return result;
  }

  Color _estadoColor(String estado) {
    if (estado == 'EMITIDA') return Colors.greenAccent;
    if (estado.contains('EMISIÓN')) return Colors.lightBlueAccent;
    if (estado.contains('NACIONAL')) return Colors.amberAccent;
    if (estado.contains('SIN')) return Colors.white38;
    return Colors.orangeAccent;
  }

  Future<void> actualizarPoliza(
    Map<String, dynamic> venta, {
    bool? incluida,
    bool? polizaVerificada,
    bool? verificadaZona,
    bool? verificadaNacional,
    bool? emitida,
  }) async {
    final agenteAuthId = venta['agente_auth_id']?.toString();
    if (agenteAuthId == null) return;

    final revision = venta['revision_nomina'] ?? {};

    await supabase
        .from('nominas_polizas_revision')
        .update({
          'incluida': incluida ?? revision['incluida'] ?? true,
          'poliza_verificada':
              polizaVerificada ?? revision['poliza_verificada'] ?? false,
          'verificada_zona':
              verificadaZona ?? revision['verificada_zona'] ?? false,
          'verificada_nacional':
              verificadaNacional ?? revision['verificada_nacional'] ?? false,
          'emitida': emitida ?? revision['emitida'] ?? false,
          'actualizado_en': DateTime.now().toIso8601String(),
        })
        .eq('venta_id', venta['id'].toString())
        .eq('nomina_auth_id', agenteAuthId)
        .eq('mes', widget.nomina['mes'])
        .eq('anio', widget.nomina['anio']);

    await cargarEstructuraFactura();
  }

  Future<void> verificarTodasZona(_FacturaNode node) async {
    final polizas = _todasPolizas(node);

    for (final p in polizas) {
      final agenteAuthId = p['agente_auth_id']?.toString();
      if (agenteAuthId == null) continue;

      await supabase
          .from('nominas_polizas_revision')
          .update({
            'verificada_zona': true,
            'actualizado_en': DateTime.now().toIso8601String(),
          })
          .eq('venta_id', p['id'].toString())
          .eq('nomina_auth_id', agenteAuthId)
          .eq('mes', widget.nomina['mes'])
          .eq('anio', widget.nomina['anio']);
    }

    await cargarEstructuraFactura();
  }

  Future<void> verificarTodasNacional(_FacturaNode node) async {
    final polizas = _todasPolizas(node);

    for (final p in polizas) {
      final agenteAuthId = p['agente_auth_id']?.toString();
      if (agenteAuthId == null) continue;

      await supabase
          .from('nominas_polizas_revision')
          .update({
            'verificada_nacional': true,
            'actualizado_en': DateTime.now().toIso8601String(),
          })
          .eq('venta_id', p['id'].toString())
          .eq('nomina_auth_id', agenteAuthId)
          .eq('mes', widget.nomina['mes'])
          .eq('anio', widget.nomina['anio']);
    }

    await cargarEstructuraFactura();
  }

  Future<void> marcarEmitida(_FacturaNode node) async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final polizas = _todasPolizas(node);

  for (final p in polizas) {
    final agenteAuthId = p['agente_auth_id']?.toString();
    if (agenteAuthId == null) continue;

    await supabase
        .from('nominas_polizas_revision')
        .update({
          'emitida': true,
          'actualizado_en': DateTime.now().toIso8601String(),
        })
        .eq('venta_id', p['id'].toString())
        .eq('nomina_auth_id', agenteAuthId)
        .eq('mes', widget.nomina['mes'])
        .eq('anio', widget.nomina['anio']);
  }

  await _crearFacturaPendiente(node);

  await cargarEstructuraFactura();
}

Future<void> _crearFacturaPendiente(_FacturaNode node) async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final usuarioAuthId = node.usuario['auth_id']?.toString();
  final usuarioNombre = _nombreUsuario(node.usuario);
  final usuarioEmail = node.usuario['email']?.toString() ?? '';
  final usuarioRol = node.rol;

  if (usuarioAuthId == null ||
      usuarioAuthId.isEmpty ||
      usuarioAuthId == 'null') {
    return;
  }

  final mes = widget.nomina['mes'];
  final anio = widget.nomina['anio'];

  final existente = await supabase
      .from('nominas_facturas')
      .select('id')
      .eq('usuario_auth_id', usuarioAuthId)
      .eq('mes', mes)
      .eq('anio', anio)
      .maybeSingle();

  if (existente != null) {
    return;
  }

  final comisionesPropias = _comisionesPropiasNode(node);
  final rappel = _rappelNode(node);
  final fijo = _fijoNode(node);

  final base = comisionesPropias + rappel + fijo;
  final irpf = 15.0;
  final importeIrpf = base * irpf / 100;
  final total = base - importeIrpf;

  final facturaCreada = await supabase
      .from('nominas_facturas')
      .insert({
        'usuario_auth_id': usuarioAuthId,
        'usuario_nombre': usuarioNombre,
        'usuario_email': usuarioEmail,
        'usuario_rol': usuarioRol,
        'mes': mes,
        'anio': anio,
       'comisiones': comisionesPropias,
'rappel': rappel,
'fijo': fijo,
'base_imponible': base,
'irpf_porcentaje': irpf,
        'importe_irpf': importeIrpf,
        'total_factura': total,
        'estado': 'pendiente_tramitar',
        'aprobada_por': user.id,
        'fecha_aprobacion': DateTime.now().toIso8601String(),
      })
      .select()
      .single();

  final facturaId = facturaCreada['id'];
  final polizas = _todasPolizas(node);

  final lineas = polizas.map((p) {
  final esBaja = p['tipo_movimiento'] == 'BAJA';

  return {
    'factura_id': facturaId,
    'venta_id': p['id'].toString().replaceFirst('baja_', ''),
    'numero_poliza': _numeroPoliza(p),
    'cliente_nombre': _nombreCliente(p),
    'prima_neta': _primaNetaVenta(p),
    'comision': _comisionVenta(p),
    'tipo_movimiento': esBaja ? 'EXTORNO' : 'VENTA',
    'anulacion_id': esBaja ? p['anulacion_id'] : null,
    'prima_extornada': esBaja ? _primaNetaVenta(p).abs() : 0,
    'comision_extornada': esBaja ? _comisionVenta(p).abs() : 0,
  };
}).toList();

  if (lineas.isNotEmpty) {
    await supabase.from('nominas_facturas_lineas').insert(lineas);
  }
}

  @override
  Widget build(BuildContext context) {
    final mes = nombreMes(widget.nomina['mes']);
    final anio = widget.nomina['anio'];

    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 66,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF061018),
                size: 30,
              ),
            ),
          ),
        ),
        title: Text(
          'Factura $mes $anio',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                : RefreshIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF102331),
                    onRefresh: cargarEstructuraFactura,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                      children: [
                        _heroFactura(),
                        const SizedBox(height: 16),
                        if (estructura.isEmpty)
                          _emptyEstructura()
                        else
                          ...estructura.map((n) => _nodeCard(n, 0)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _heroFactura() {
    double primas = 0;
    double comisiones = 0;

    for (final n in estructura) {
      primas += _primasNode(n);
      comisiones += _comisionesNode(n);
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.greenAccent.withOpacity(0.18),
            Colors.white.withOpacity(0.045),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Control de facturas',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Estructura jerárquica · ${nombreMes(widget.nomina['mes'])} ${widget.nomina['anio']}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${(comisiones).toStringAsFixed(2)} €',
            style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'Comisiones agentes · Primas ${primas.toStringAsFixed(2)} €',
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nodeCard(_FacturaNode node, int level) {
    final nombre = _nombreUsuario(node.usuario);
    final estado = _estadoNode(node);
    final color = _estadoColor(estado);
    final primasTotales = _primasNode(node);
    final polizasTotales = _todasPolizas(node);
    final polizasPropias = node.polizas;
    final hijos = node.hijos;

    return Container(
      margin: EdgeInsets.only(
        left: level == 0 ? 0 : 8,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(level == 0 ? 0.065 : 0.045),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: level == 0
              ? Colors.cyanAccent.withOpacity(0.22)
              : Colors.white.withOpacity(0.09),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          popupMenuTheme: const PopupMenuThemeData(
            color: Color(0xFF102331),
            textStyle: TextStyle(color: Colors.white),
          ),
        ),
        child: ExpansionTile(
          initiallyExpanded: level == 0,
          maintainState: true,
          collapsedIconColor: Colors.white70,
          iconColor: Colors.cyanAccent,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _colorRol(node.rol).withOpacity(0.15),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              _iconoRol(node.rol),
              color: _colorRol(node.rol),
            ),
          ),
          title: Text(
            nombre,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _miniPill(_rolTexto(node.rol), _colorRol(node.rol)),
                _miniPill(estado, color),
                _miniPill(
                  '${polizasPropias.length} propias',
                  Colors.lightBlueAccent,
                ),
                _miniPill(
                  '${polizasTotales.length} estructura',
                  Colors.white70,
                ),
                _miniPill(
                  '${primasTotales.toStringAsFixed(0)} € primas',
                  Colors.greenAccent,
                ),
              ],
            ),
          ),
          children: [
            _resumenNode(node, estado, color),

            _tituloSeccionArbol(
              icon: Icons.receipt_long_rounded,
              title: 'Pólizas propias',
              subtitle: polizasPropias.isEmpty
                  ? 'Esta persona no tiene pólizas en el periodo'
                  : '${polizasPropias.length} movimientos encontrados',
              color: Colors.lightBlueAccent,
            ),

            if (polizasPropias.isEmpty)
              _sinPolizasPropias()
            else if (!puedeVerPolizas)
              _bloqueSinPermiso()
            else
              ...polizasPropias.map(_polizaItem),

            if (hijos.isNotEmpty) ...[
              const SizedBox(height: 6),
              _tituloSeccionArbol(
                icon: Icons.account_tree_rounded,
                title: _tituloDependencias(node.rol),
                subtitle: '${hijos.length} personas asignadas directamente',
                color: Colors.cyanAccent,
              ),
              ...hijos.map((h) => _nodeCard(h, level + 1)),
            ] else if (node.rol != 'agente') ...[
              const SizedBox(height: 6),
              _tituloSeccionArbol(
                icon: Icons.account_tree_outlined,
                title: _tituloDependencias(node.rol),
                subtitle: 'No hay personas asignadas directamente',
                color: Colors.white54,
              ),
            ],

            if (currentRole == 'director_zona')
              _botonAccionGrande(
                'Verificar esta persona y su estructura',
                Icons.verified_rounded,
                Colors.orangeAccent,
                () => verificarTodasZona(node),
              ),

            if (currentRole == 'director_nacional') ...[
              _botonAccionGrande(
                'Verificar esta persona y su estructura',
                Icons.workspace_premium_rounded,
                Colors.lightBlueAccent,
                () => verificarTodasNacional(node),
              ),
              const SizedBox(height: 8),
              _botonAccionGrande(
                'Marcar esta persona y su estructura como emitida',
                Icons.payments_rounded,
                Colors.greenAccent,
                () => marcarEmitida(node),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconoRol(String rol) {
    switch (rol) {
      case 'director_zona':
        return Icons.map_rounded;
      case 'jefe_ventas':
        return Icons.business_center_rounded;
      case 'jefe_equipo':
        return Icons.groups_rounded;
      case 'agente':
        return Icons.person_rounded;
      default:
        return Icons.account_tree_rounded;
    }
  }

  Color _colorRol(String rol) {
    switch (rol) {
      case 'director_zona':
        return Colors.purpleAccent;
      case 'jefe_ventas':
        return Colors.amberAccent;
      case 'jefe_equipo':
        return Colors.cyanAccent;
      case 'agente':
        return Colors.greenAccent;
      default:
        return Colors.white70;
    }
  }

  String _tituloDependencias(String rol) {
    switch (rol) {
      case 'director_nacional':
        return 'Directores de zona';
      case 'director_zona':
        return 'Jefes de ventas';
      case 'jefe_ventas':
        return 'Jefes de equipo';
      case 'jefe_equipo':
        return 'Agentes';
      default:
        return 'Personas asignadas';
    }
  }

  Widget _tituloSeccionArbol({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.50),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sinPolizasPropias() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.025),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        'Sin pólizas propias en este periodo.',
        style: TextStyle(
          color: Colors.white.withOpacity(0.48),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _rolTexto(String rol) {
    switch (rol) {
      case 'director_nacional':
        return 'Director nacional';
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente';
      default:
        return rol;
    }
  }

  Widget _resumenNode(
  _FacturaNode node,
  String estado,
  Color color,
) {
  final primasBrutas = _primasBrutasNode(node);
  final primasNetas = _primasNode(node);
  final rappel = _rappelNode(node);
  final comisionesPropias = _comisionesPropiasNode(node);
  final comisiones = _comisionesNode(node);
  final fijo = _fijoNode(node);
  final total = _totalSueldoNode(node);

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.18),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        _lineaResumen('Primas brutas', primasBrutas, Colors.white70),
        _lineaResumen('Primas netas', primasNetas, Colors.cyanAccent),
        _lineaResumen('Rappel', rappel, Colors.amberAccent),
        _lineaResumen('Comisiones propias', comisionesPropias, Colors.greenAccent),
        _lineaResumen('Comisiones', comisiones, Colors.lightGreenAccent),
        _lineaResumen('Fijo', fijo, Colors.lightBlueAccent),
        _lineaResumen('Total', total, Colors.greenAccent),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                'Estado factura',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              estado,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

  Widget _lineaResumen(String title, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.60),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} €',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _polizaItem(Map<String, dynamic> venta) {
    final revision = venta['revision_nomina'] ?? {};
    final incluida = revision['incluida'] == true;
    final polizaVerificada = revision['poliza_verificada'] == true;
    final zona = revision['verificada_zona'] == true;
    final nacional = revision['verificada_nacional'] == true;
    final emitida = revision['emitida'] == true;

    final cliente = _nombreCliente(venta);
    final numeroPoliza = _numeroPoliza(venta);
    final fechaEfecto = _fechaEfecto(venta)?.toString().split(' ').first ?? 'Sin fecha';
    final estadoRecibo = _estadoRecibo(venta);
    final estadoFirma = _estadoFirma(venta);

    final prima = _money(venta['prima_anual_neta']);
    final comision = _money(venta['comision']);
    final esBaja = venta['tipo_movimiento'] == 'BAJA';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: incluida
            ? Colors.white.withOpacity(0.055)
            : Colors.redAccent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: incluida
              ? Colors.white.withOpacity(0.09)
              : Colors.redAccent.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cliente,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white70,
                ),
                color: const Color(0xFF102331),
                onSelected: (value) {
                  _mostrarConsultaPoliza(
                    context,
                    value,
                    venta,
                    cliente,
                    numeroPoliza,
                    fechaEfecto,
                    estadoRecibo,
                    estadoFirma,
                  );
                },
                itemBuilder: (_) => [
                  _menuItem('recibo', 'Consultar recibo'),
                  _menuItem('fecha', 'Consultar fecha efecto'),
                  _menuItem('firma', 'Estado firma CCPP'),
                  _menuItem('datos', 'Ver datos completos'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            esBaja ? 'BAJA / EXTORNO · Póliza: $numeroPoliza' : 'Póliza: $numeroPoliza',
            style: TextStyle(
              color: Colors.cyanAccent.withOpacity(0.9),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Prima neta: ${prima.toStringAsFixed(2)} € · Comisión: ${comision.toStringAsFixed(2)} €',
            style: TextStyle(
              color: Colors.white.withOpacity(0.58),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fecha efecto: $fechaEfecto · Recibo: $estadoRecibo · Firma CCPP: $estadoFirma',
            style: TextStyle(
              color: Colors.white.withOpacity(0.48),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _accionPoliza(
                  polizaVerificada ? 'Verificada' : 'Verificar póliza',
                  Icons.fact_check_rounded,
                  polizaVerificada ? Colors.greenAccent : Colors.orangeAccent,
                  () => actualizarPoliza(
                    venta,
                    polizaVerificada: !polizaVerificada,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _accionPoliza(
                  incluida ? 'Excluir cálculo' : 'Incluir cálculo',
                  incluida ? Icons.block_rounded : Icons.add_circle_rounded,
                  incluida ? Colors.redAccent : Colors.greenAccent,
                  () => actualizarPoliza(
                    venta,
                    incluida: !incluida,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (currentRole == 'director_zona')
  Expanded(
    child: _accionPoliza(
      zona ? 'Póliza verificada' : 'Verificar póliza',
      Icons.verified_rounded,
      zona ? Colors.greenAccent : Colors.orangeAccent,
      () => actualizarPoliza(
        venta,
        verificadaZona: !zona,
      ),
    ),
  ),
              if (currentRole == 'director_nacional')
                Expanded(
                  child: _accionPoliza(
                    nacional ? 'Nacional OK' : 'Nacional verifica',
                    Icons.workspace_premium_rounded,
                    nacional ? Colors.greenAccent : Colors.lightBlueAccent,
                    () => actualizarPoliza(
                      venta,
                      verificadaNacional: !nacional,
                    ),
                  ),
                ),
            ],
          ),
          if (currentRole == 'director_nacional') ...[
            const SizedBox(height: 8),
            _accionPoliza(
              emitida ? 'Emitida' : 'Marcar emitida',
              Icons.payments_rounded,
              emitida ? Colors.greenAccent : Colors.amberAccent,
              () => actualizarPoliza(
                venta,
                emitida: !emitida,
              ),
            ),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, String text) {
    return PopupMenuItem(
      value: value,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _accionPoliza(
    String text,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: color.withOpacity(0.11),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 17),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botonAccionGrande(
    String text,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      child: _accionPoliza(text, icon, color, onTap),
    );
  }

  Widget _miniPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _bloqueSinPermiso() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'El detalle de pólizas solo puede verlo Director Zona o Director Nacional.',
        style: TextStyle(
          color: Colors.orangeAccent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _emptyEstructura() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Text(
        'No hay estructura ni facturas disponibles para este mes.',
        style: TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  void _mostrarConsultaPoliza(
    BuildContext context,
    String tipo,
    Map<String, dynamic> venta,
    String cliente,
    String numeroPoliza,
    String fechaEfecto,
    String estadoRecibo,
    String estadoFirma,
  ) {
    String titulo = 'Datos de póliza';
    String contenido = '';

    if (tipo == 'recibo') {
      titulo = 'Estado del recibo';
      contenido =
          'Cliente: $cliente\nPóliza: $numeroPoliza\nEstado recibo: $estadoRecibo';
    }

    if (tipo == 'fecha') {
      titulo = 'Fecha efecto';
      contenido =
          'Cliente: $cliente\nPóliza: $numeroPoliza\nFecha efecto: $fechaEfecto';
    }

    if (tipo == 'firma') {
      titulo = 'Firma CCPP';
      contenido =
          'Cliente: $cliente\nPóliza: $numeroPoliza\nEstado firma CCPP: $estadoFirma';
    }

    if (tipo == 'datos') {
      titulo = 'Datos completos';
      contenido = venta.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF102331),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  contenido,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PremiumBackground extends StatelessWidget {
  const _PremiumBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFF061018)),
        Positioned(
          top: -120,
          right: -90,
          child: _blurCircle(
            color: Colors.greenAccent.withOpacity(0.18),
            size: 270,
          ),
        ),
        Positioned(
          top: 260,
          left: -130,
          child: _blurCircle(
            color: Colors.cyanAccent.withOpacity(0.16),
            size: 290,
          ),
        ),
        Positioned(
          bottom: -130,
          right: -100,
          child: _blurCircle(
            color: const Color(0xFF2D7DFF).withOpacity(0.14),
            size: 320,
          ),
        ),
      ],
    );
  }

  Widget _blurCircle({
    required Color color,
    required double size,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 95,
            spreadRadius: 38,
          ),
        ],
      ),
    );
  }
}