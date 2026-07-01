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
          'Mis nóminas',
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
                            'Centro de nóminas',
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
    final total = _money(n['total_cobrar']);
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
                  builder: (_) => NominaDetailScreen(nomina: n),
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
                          'Nómina $mes $anio',
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

class NominaDetailScreen extends StatelessWidget {
  final Map<String, dynamic> nomina;

  const NominaDetailScreen({
    super.key,
    required this.nomina,
  });

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

final int mesNomina = nomina['mes'];
final int anioNomina = nomina['anio'];

DateTime inicioNomina = DateTime(anioNomina, mesNomina - 1, 24);
DateTime finNomina = DateTime(anioNomina, mesNomina, 24);

final bool isClosed = now.isAfter(finNomina);

final String estado = isClosed ? 'CERRADA' : 'ABIERTA';

final Color estadoColor =
    isClosed ? Colors.redAccent : Colors.greenAccent;

    final total = _money(nomina['total_cobrar']);
    final primasNetas = _money(nomina['prima_neta_total']);
    final primasBrutas = primasNetas * 1.13;
    final comisiones = _money(nomina['comisiones']);
    final rappel = _money(nomina['rappel']);
    final sueldoFijo = _money(nomina['sueldo_fijo']);

    return Scaffold(
      backgroundColor: const Color(0xFF061018),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Detalle nómina',
          style: TextStyle(
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroTotal(
                    total,
                    estado,
                    estadoColor,
                  ),
                  const SizedBox(height: 16),
                  _breakdownCard(
                    primasNetas: primasNetas,
                    primasBrutas: primasBrutas,
                    comisiones: comisiones,
                    rappel: rappel,
                    sueldoFijo: sueldoFijo,
                  ),
                  const SizedBox(height: 16),
                  _estadoCard(estado, estadoColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroTotal(
    double total,
    String estado,
    Color estadoColor,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.greenAccent.withOpacity(0.18),
                Colors.white.withOpacity(0.045),
              ],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 58,
                    width: 58,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.payments_rounded,
                      color: Colors.greenAccent,
                      size: 31,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: estadoColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      estado,
                      style: TextStyle(
                        color: estadoColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Total a cobrar',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.62),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${total.toStringAsFixed(2)} €',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Nómina ${nombreMes(nomina['mes'])} ${nomina['anio']}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.54),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _breakdownCard({
    required double primasNetas,
    required double primasBrutas,
    required double comisiones,
    required double rappel,
    required double sueldoFijo,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Desglose económico',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          _detailItem(
            'Primas netas',
            primasNetas,
            Icons.account_balance_wallet_rounded,
            Colors.cyanAccent,
          ),
          _detailItem(
            'Primas brutas',
            primasBrutas,
            Icons.trending_up_rounded,
            Colors.lightBlueAccent,
          ),
          _detailItem(
            'Comisiones',
            comisiones,
            Icons.payments_rounded,
            Colors.greenAccent,
          ),
          _detailItem(
            'Rappel',
            rappel,
            Icons.emoji_events_rounded,
            Colors.amberAccent,
          ),
          _detailItem(
            'Sueldo fijo',
            sueldoFijo,
            Icons.wallet_rounded,
            Colors.purpleAccent,
          ),
        ],
      ),
    );
  }

  Widget _detailItem(
    String title,
    double value,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} €',
            style: TextStyle(
              color: value > 0 ? Colors.white : Colors.white38,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoCard(String estado, Color estadoColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          Icon(
            estado == 'CERRADA'
                ? Icons.lock_rounded
                : Icons.lock_open_rounded,
            color: estadoColor,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Estado de la nómina',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            estado,
            style: TextStyle(
              color: estadoColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
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