import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';

class NominasScreen extends StatefulWidget {
  const NominasScreen({super.key});

  @override
  State<NominasScreen> createState() => _NominasScreenState();
}

class _NominasScreenState extends State<NominasScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> nominas = [];
  List<Map<String, dynamic>> _configuredClosures = [];
  bool loading = true;
  String? role;

  @override
  void initState() {
    super.initState();
    loadNominas();
  }

  String _clean(dynamic value) {
    final s = (value ?? '').toString().trim();
    return s.toLowerCase() == 'null' ? '' : s;
  }

  String _rol(dynamic value) =>
      _clean(value).toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final s = value.toString().trim();
    final n = s.contains(',') && s.contains('.')
        ? s.replaceAll('.', '').replaceAll(',', '.')
        : s.replaceAll(',', '.');
    return double.tryParse(n) ?? 0;
  }

  int _nivel(dynamic value) {
    switch (_rol(value)) {
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

  bool _esDV(dynamic producto) {
    final p = _clean(producto).toLowerCase();
    return p.contains('decesos') ||
        p.contains('vida') ||
        p.contains('prima unica') ||
        p.contains('prima única');
  }

  DateTime? _fechaEfecto(Map<String, dynamic> venta) {
    for (final v in [
      venta['fecha_efecto'],
      venta['fecha'],
      venta['created_at'],
    ]) {
      final f = DateTime.tryParse((v ?? '').toString());
      if (f != null) return f;
    }
    return null;
  }

  Map<String, DateTime> _periodoDeFecha(DateTime fecha) {
    final date = DateTime(fecha.year, fecha.month, fecha.day);

    for (final closure in _configuredClosures) {
      final from = DateTime.tryParse(closure['fecha_desde'].toString());
      final to = DateTime.tryParse(closure['fecha_hasta'].toString());
      if (from == null || to == null) continue;

      final start = DateTime(from.year, from.month, from.day);
      final lastDay = DateTime(to.year, to.month, to.day);
      if (!date.isBefore(start) && !date.isAfter(lastDay)) {
        return {'inicio': start, 'fin': lastDay.add(const Duration(days: 1))};
      }
    }

    final inicio = fecha.day >= 24
        ? DateTime(fecha.year, fecha.month, 24)
        : DateTime(fecha.year, fecha.month - 1, 24);
    return {
      'inicio': inicio,
      'fin': DateTime(inicio.year, inicio.month + 1, 24),
    };
  }

  String _keyPeriodo(DateTime fecha) {
    final p = _periodoDeFecha(fecha);
    final fin = p['fin']!;
    return '${fin.year}-${fin.month.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _estructuraValida(
    Map<String, dynamic> perfil,
    List<Map<String, dynamic>> usuarios,
  ) {
    if (_rol(perfil['rol_usuario']) == 'administracion') {
      return usuarios.where((u) => _clean(u['auth_id']).isNotEmpty).toList();
    }

    final raiz = _clean(perfil['id']);
    final resultado = <Map<String, dynamic>>[perfil];
    final visitados = <String>{raiz};
    final cola = <Map<String, dynamic>>[perfil];

    while (cola.isNotEmpty) {
      final padre = cola.removeAt(0);
      final padreId = _clean(padre['id']);
      final nivelPadre = _nivel(padre['rol_usuario']);

      for (final original in usuarios) {
        if (_clean(original['parent_id']) != padreId) continue;
        final hijo = Map<String, dynamic>.from(original);
        final id = _clean(hijo['id']);
        if (id.isEmpty || visitados.contains(id)) continue;
        if (_nivel(hijo['rol_usuario']) <= 0 ||
            _nivel(hijo['rol_usuario']) >= nivelPadre) {
          continue;
        }
        visitados.add(id);
        resultado.add(hijo);
        cola.add(hijo);
      }
    }
    return resultado;
  }

  double calcularRappelAgente(double primas, double primasDV) {
    if (primas <= 0) return 0;
    final porcentaje = primasDV / primas * 100;
    if (primas >= 12000 && porcentaje >= 30) return 1500;
    if (primas >= 9000 && porcentaje >= 30) return 1200;
    if (primas >= 6000 && porcentaje >= 30) return 800;
    if (primas >= 4000 && porcentaje >= 30) return 600;
    if (primas >= 2500 && porcentaje >= 99.999) return 400;
    if (primas >= 1500 && porcentaje >= 99.999) return 200;
    return 0;
  }

  double calcularRappelJefe(double primas) {
    if (primas >= 10000) return 2000 + ((primas - 10000) ~/ 1000) * 100;
    if (primas >= 9000) return 1800;
    if (primas >= 8000) return 1600;
    if (primas >= 7000) return 1400;
    if (primas >= 6000) return 1200;
    if (primas >= 5000) return 1000;
    if (primas >= 4000) return 800;
    return 0;
  }

  double calcularRappelJefeVentas(double primas) {
    if (primas >= 11500) return 2500 + ((primas - 11500) ~/ 1000) * 100;
    if (primas >= 10500) return 2300;
    if (primas >= 9500) return 2100;
    if (primas >= 8500) return 1900;
    if (primas >= 7500) return 1700;
    if (primas >= 6500) return 1500;
    return 0;
  }

  void _recalcularNomina(Map<String, dynamic> n, String rolActual) {
    final primas = _money(n['prima_neta_total']).clamp(0, double.infinity);
    final primasDV = _money(n['primas_dv']).clamp(0, double.infinity);
    final comisiones = _money(n['comisiones']);
    double concepto = 0;
    String conceptoNombre = 'Rappel';

    switch (rolActual) {
      case 'agente':
        concepto = calcularRappelAgente(primas.toDouble(), primasDV.toDouble());
        break;
      case 'jefe_equipo':
        concepto = calcularRappelJefe(primas.toDouble());
        break;
      case 'jefe_ventas':
        concepto = calcularRappelJefeVentas(primas.toDouble());
        break;
      case 'director_zona':
        concepto = primas * 0.10;
        conceptoNombre = '10% estructura';
        break;
      case 'director_nacional':
        concepto = primas * 0.05;
        conceptoNombre = '5% estructura';
        break;
    }

    n['rappel'] = concepto;
    n['concepto_variable'] = conceptoNombre;
    n['sueldo_fijo'] = 0.0;
    n['total_cobrar'] = comisiones + concepto;
  }

  Future<void> loadNominas() async {
    final auth = supabase.auth.currentUser;
    if (auth == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      if (mounted) setState(() => loading = true);

      final perfilData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          )
          .eq('auth_id', auth.id)
          .maybeSingle();

      if (perfilData == null) throw Exception('Usuario no encontrado');

      final perfil = Map<String, dynamic>.from(perfilData);
      role = _rol(perfil['rol_usuario']);

      final usuariosData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          );

      final usuarios = List<Map<String, dynamic>>.from(usuariosData);
      final estructura = _estructuraValida(perfil, usuarios);
      final authIds = estructura
          .map((u) => _clean(u['auth_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final closuresData = await supabase
          .from('cierres_produccion')
          .select('anio, mes, fecha_desde, fecha_hasta, estado')
          .order('fecha_desde');
      _configuredClosures = List<Map<String, dynamic>>.from(closuresData);

      final grouped = <String, Map<String, dynamic>>{};

      if (authIds.isNotEmpty) {
        final ventasData = await supabase
            .from('ventas')
            .select(
              'id, agente_auth_id, fecha_efecto, created_at, prima_anual_neta, comision, producto',
            )
            .inFilter('agente_auth_id', authIds);

        for (final raw in List<Map<String, dynamic>>.from(ventasData)) {
          final fecha = _fechaEfecto(raw);
          if (fecha == null) continue;
          final periodo = _periodoDeFecha(fecha);
          final fin = periodo['fin']!;
          final key = _keyPeriodo(fecha);

          grouped.putIfAbsent(
            key,
            () => {
              'mes': fin.month,
              'anio': fin.year,
              'inicio_periodo': periodo['inicio']!.toIso8601String(),
              'fin_periodo': fin.toIso8601String(),
              'prima_neta_total': 0.0,
              'primas_dv': 0.0,
              'comisiones': 0.0,
              'rappel': 0.0,
              'sueldo_fijo': 0.0,
              'total_cobrar': 0.0,
              'tipo': 'Nómina ${role ?? ''}',
            },
          );

          final prima = _money(raw['prima_anual_neta']);
          grouped[key]!['prima_neta_total'] =
              _money(grouped[key]!['prima_neta_total']) + prima;

          if (_esDV(raw['producto'])) {
            grouped[key]!['primas_dv'] =
                _money(grouped[key]!['primas_dv']) + prima;
          }

          if (_clean(raw['agente_auth_id']) == auth.id) {
            grouped[key]!['comisiones'] =
                _money(grouped[key]!['comisiones']) + _money(raw['comision']);
          }
        }

        final bajasData = await supabase
            .from('anulaciones_polizas')
            .select(
              'id, venta_id, fecha_anulacion, prima_extornada, comision_extornada',
            )
            .eq('estado', 'ANULADA');

        final bajas = List<Map<String, dynamic>>.from(bajasData);
        final ventaIds = bajas
            .map((b) => _clean(b['venta_id']))
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        if (ventaIds.isNotEmpty) {
          final originalesData = await supabase
              .from('ventas')
              .select('id, agente_auth_id, producto')
              .inFilter('id', ventaIds);
          final originales = {
            for (final v in List<Map<String, dynamic>>.from(originalesData))
              _clean(v['id']): v,
          };

          for (final baja in bajas) {
            final fecha = DateTime.tryParse(_clean(baja['fecha_anulacion']));
            final venta = originales[_clean(baja['venta_id'])];
            if (fecha == null || venta == null) continue;
            final agente = _clean(venta['agente_auth_id']);
            if (!authIds.contains(agente)) continue;

            final periodo = _periodoDeFecha(fecha);
            final fin = periodo['fin']!;
            final key = _keyPeriodo(fecha);
            grouped.putIfAbsent(
              key,
              () => {
                'mes': fin.month,
                'anio': fin.year,
                'inicio_periodo': periodo['inicio']!.toIso8601String(),
                'fin_periodo': fin.toIso8601String(),
                'prima_neta_total': 0.0,
                'primas_dv': 0.0,
                'comisiones': 0.0,
                'rappel': 0.0,
                'sueldo_fijo': 0.0,
                'total_cobrar': 0.0,
                'tipo': 'Nómina ${role ?? ''}',
              },
            );

            final prima = _money(baja['prima_extornada']);
            grouped[key]!['prima_neta_total'] =
                _money(grouped[key]!['prima_neta_total']) - prima;
            if (_esDV(venta['producto'])) {
              grouped[key]!['primas_dv'] =
                  _money(grouped[key]!['primas_dv']) - prima;
            }
            if (agente == auth.id) {
              grouped[key]!['comisiones'] =
                  _money(grouped[key]!['comisiones']) -
                  _money(baja['comision_extornada']);
            }
          }
        }
      }

      for (final n in grouped.values) {
        _recalcularNomina(n, role ?? '');
      }

      final lista = grouped.values.toList()
        ..sort(
          (a, b) =>
              DateTime(
                int.parse(b['anio'].toString()),
                int.parse(b['mes'].toString()),
              ).compareTo(
                DateTime(
                  int.parse(a['anio'].toString()),
                  int.parse(a['mes'].toString()),
                ),
              ),
        );

      if (!mounted) return;
      setState(() {
        nominas = lista;
        loading = false;
      });
    } catch (e, s) {
      debugPrint('ERROR LOAD NOMINAS: $e');
      debugPrint('$s');
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

  Map<String, dynamic>? get nominaActual {
    final p = _periodoDeFecha(DateTime.now());
    final fin = p['fin']!;
    for (final n in nominas) {
      if (_money(n['mes']).toInt() == fin.month &&
          _money(n['anio']).toInt() == fin.year) {
        return n;
      }
    }
    return null;
  }

  double get totalAcumulado => _money(nominaActual?['total_cobrar']);
  double get primasAcumuladas => _money(nominaActual?['prima_neta_total']);
  double get rappelAcumulado => _money(nominaActual?['rappel']);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 66,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Material(
            color: const Color(0xFFE2E8F0),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: const Center(
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: const Color(0xFF0F172A),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Facturas y liquidaciones',
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: loadNominas,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF2563EB)),
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
                      color: const Color(0xFF2563EB),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF2563EB),
                    backgroundColor: const Color(0xFFFFFFFF),
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
                colors: [const Color(0xFFEFF6FF), const Color(0xFFF8FAFC)],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: const Color(0xFFE2E8F0)),
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
                            const Color(0xFF059669),
                            const Color(0xFF2563EB),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF059669).withOpacity(0.22),
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
                              color: const Color(0xFF0F172A),
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
                              color: const Color(0xFF64748B),
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
                    color: const Color(0xFF059669),
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sueldo previsto del periodo actual',
                  style: TextStyle(
                    color: const Color(0xFF64748B),
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
              const Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              'Rappel',
              '${rappelAcumulado.toStringAsFixed(0)} €',
              Icons.emoji_events_rounded,
              const Color(0xFFD97706),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                    color: const Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    color: const Color(0xFF64748B),
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
                  builder: (_) => NominaDetailScreen(nomina: n, role: role),
                ),
              );
            },
            child: Ink(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFFF8FAFC), Colors.white],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFF059669).withOpacity(0.16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x140F172A),
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
                      color: const Color(0xFF2563EB).withOpacity(0.13),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: const Color(0xFF2563EB),
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
                            color: const Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tipo.toString(),
                          style: TextStyle(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _pill(
                              'Primas ${_money(n['prima_neta_total']).toStringAsFixed(0)} €',
                              const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 8),
                            _pill(
                              '${n['concepto_variable'] ?? 'Rappel'} ${_money(n['rappel']).toStringAsFixed(0)} €',
                              const Color(0xFFD97706),
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
                          color: const Color(0xFF059669),
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: const Color(0xFF64748B),
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
          color: const Color(0xFFCBD5E1),
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'Sin nóminas disponibles',
            style: TextStyle(
              color: const Color(0xFF0F172A),
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
              color: const Color(0xFF64748B),
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
          venta['prima_anual_neta'],
    );
  }

  double _primaNetaVenta(Map<String, dynamic> venta) {
    return _money(venta['prima_anual_neta']);
  }

  double _comisionVenta(Map<String, dynamic> venta) {
    return _money(venta['comision']);
  }

  bool _esProductoDV(dynamic producto) {
    final p = (producto ?? '').toString().trim().toLowerCase();
    return p.contains('decesos') ||
        p.contains('vida') ||
        p.contains('prima unica') ||
        p.contains('prima única');
  }

  double _primasDVNode(_FacturaNode node) {
    double total = 0;
    for (final p in node.polizas) {
      final r = p['revision_nomina'] ?? {};
      if (r['incluida'] == false) continue;
      if (_esProductoDV(p['producto'])) {
        total += _primaNetaVenta(p);
      }
    }
    for (final h in node.hijos) {
      total += _primasDVNode(h);
    }
    return total;
  }

  double _calcularRappelAgente(double primas, double primasDV) {
    if (primas <= 0) return 0;
    final porcentaje = primasDV / primas * 100;
    if (primas >= 12000 && porcentaje >= 30) return 1500;
    if (primas >= 9000 && porcentaje >= 30) return 1200;
    if (primas >= 6000 && porcentaje >= 30) return 800;
    if (primas >= 4000 && porcentaje >= 30) return 600;
    if (primas >= 2500 && porcentaje >= 99.999) return 400;
    if (primas >= 1500 && porcentaje >= 99.999) return 200;
    return 0;
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

    if (node.rol == 'agente') {
      return _calcularRappelAgente(primas, _primasDVNode(node));
    }

    if (node.rol == 'jefe_equipo') {
      return _calcularRappelJefe(primas);
    }

    if (node.rol == 'jefe_ventas') {
      return _calcularRappelJefeVentas(primas);
    }

    if (node.rol == 'director_zona') {
      return primas * 0.10;
    }

    if (node.rol == 'director_nacional') {
      return primas * 0.05;
    }

    return 0;
  }

  double _fijoNode(_FacturaNode node) {
    return 0;
  }

  double _totalSueldoNode(_FacturaNode node) {
    return _comisionesPropiasNode(node) + _rappelNode(node) + _fijoNode(node);
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

  int _nivelRolDetalle(dynamic value) {
    switch (_rolCanonico(value)) {
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
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          );

      final listaUsuarios = (usuarios as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final int mes = widget.nomina['mes'];
      final int anio = widget.nomina['anio'];

      final productionPeriod = await ProductionPeriodService.instance.forMonth(
        year: anio,
        month: mes,
      );
      final inicio = productionPeriod.start;
      final fin = productionPeriod.endExclusive;

      final miUsuario = listaUsuarios.firstWhere(
        (u) => u['auth_id']?.toString() == user.id,
        orElse: () => <String, dynamic>{},
      );

      final estructuraPermitida = <Map<String, dynamic>>[];
      if (miUsuario.isNotEmpty) {
        final visitados = <String>{miUsuario['id'].toString()};
        final cola = <Map<String, dynamic>>[miUsuario];
        estructuraPermitida.add(miUsuario);

        while (cola.isNotEmpty) {
          final padre = cola.removeAt(0);
          final padreId = padre['id']?.toString() ?? '';
          final nivelPadre = _nivelRolDetalle(padre['rol_usuario']);

          for (final u in listaUsuarios) {
            final id = u['id']?.toString() ?? '';
            if (u['parent_id']?.toString() != padreId ||
                id.isEmpty ||
                visitados.contains(id)) {
              continue;
            }

            final nivelHijo = _nivelRolDetalle(u['rol_usuario']);
            if (nivelHijo <= 0 || nivelHijo >= nivelPadre) continue;

            visitados.add(id);
            estructuraPermitida.add(u);
            cola.add(u);
          }
        }
      }

      final authIds = estructuraPermitida
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

          // Conservamos por separado el ID real de la póliza y el ID de la baja.
          // El ID sintético solo se usa en pantalla/revisión para no mezclar la venta
          // original con el movimiento de extorno.
          ventaBaja['venta_original_id'] = ventaOriginal['id'];
          ventaBaja['id'] = 'baja_${baja['id']}';
          ventaBaja['tipo_movimiento'] = 'BAJA';
          ventaBaja['anulacion_id'] = baja['id'];
          ventaBaja['fecha_efecto'] = baja['fecha_anulacion'];

          final primaExtornada = _money(baja['prima_extornada']);
          final comisionExtornada = _money(baja['comision_extornada']);

          // Valores negativos para que resten en nómina.
          ventaBaja['prima_anual_neta'] = -primaExtornada;
          ventaBaja['comision'] = -comisionExtornada;

          // Valores positivos específicos para mostrarlos claramente
          // en Tramitar facturas y en el detalle/PDF.
          ventaBaja['prima_extornada'] = primaExtornada;
          ventaBaja['comision_extornada'] = comisionExtornada;

          ventaBaja['numero_poliza'] =
              baja['numero_poliza'] ?? ventaOriginal['numero_poliza'];
          ventaBaja['nombre_cliente'] =
              baja['nombre_cliente'] ?? ventaOriginal['nombre_cliente'];
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

      final recibos = await supabase.from('recibos').select();

      for (final venta in ventasMes) {
        final numeroPoliza = _numeroPoliza(venta);
        final clienteId = _clienteIdVenta(venta)?.toString();

        Map<String, dynamic>? reciboEncontrado;

        for (final r in recibos as List) {
          final recibo = Map<String, dynamic>.from(r);

          final reciboPoliza =
              (recibo['numero_poliza'] ??
                      recibo['poliza'] ??
                      recibo['n_poliza'] ??
                      recibo['N_POLIZA'])
                  ?.toString();

          final reciboClienteId =
              (recibo['cliente_id'] ??
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
        final key = '${venta['id']}_${agenteAuthId}_${mes}_${anio}';
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
      final result = ventasMes
          .where((v) => clean(v['agente_auth_id']) == auth)
          .map((v) => Map<String, dynamic>.from(v))
          .toList();
      result.sort((a, b) {
        final fa = _fechaEfecto(a) ?? DateTime(1900);
        final fb = _fechaEfecto(b) ?? DateTime(1900);
        return fb.compareTo(fa);
      });
      return result;
    }

    final authActual = clean(supabase.auth.currentUser?.id);
    final raiz = usuarios.firstWhere(
      (u) => clean(u['auth_id']) == authActual,
      orElse: () => <String, dynamic>{},
    );

    if (raiz.isEmpty) return [];

    _FacturaNode construir(
      Map<String, dynamic> usuario,
      Set<String> visitados,
    ) {
      final id = clean(usuario['id']);
      final nivelPadre = _nivelRolDetalle(usuario['rol_usuario']);
      final nuevosVisitados = <String>{...visitados, id};

      final hijosUsuarios =
          usuarios
              .where((u) {
                final hijoId = clean(u['id']);
                final nivelHijo = _nivelRolDetalle(u['rol_usuario']);
                return clean(u['parent_id']) == id &&
                    hijoId.isNotEmpty &&
                    !nuevosVisitados.contains(hijoId) &&
                    nivelHijo > 0 &&
                    nivelHijo < nivelPadre;
              })
              .map((u) => Map<String, dynamic>.from(u))
              .toList()
            ..sort(
              (a, b) => _nombreUsuario(
                a,
              ).toLowerCase().compareTo(_nombreUsuario(b).toLowerCase()),
            );

      return _FacturaNode(
        usuario: usuario,
        rol: _rolCanonico(usuario['rol_usuario']),
        polizas: ventasDe(usuario['auth_id']),
        hijos: hijosUsuarios.map((h) => construir(h, nuevosVisitados)).toList(),
      );
    }

    return [construir(raiz, <String>{})];
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

  double _porcentajeMixNode(_FacturaNode node) {
    final primasTotales = _primasNode(node);
    if (primasTotales <= 0) return 0;

    final primasDV = _primasDVNode(node);
    return (primasDV / primasTotales * 100).clamp(0, 100).toDouble();
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
    if (estado == 'EMITIDA') return const Color(0xFF059669);
    if (estado.contains('EMISIÓN')) return const Color(0xFF0284C7);
    if (estado.contains('NACIONAL')) return const Color(0xFFD97706);
    if (estado.contains('SIN')) return const Color(0xFF94A3B8);
    return const Color(0xFFEA580C);
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

    // Solo enviamos a la factura los movimientos incluidos en el cálculo.
    // Cada baja viaja como una línea EXTORNO independiente, vinculada a la
    // venta/póliza original y a su registro de anulación.
    final movimientosIncluidos = _todasPolizas(node).where((p) {
      final revision = p['revision_nomina'];
      if (revision is Map && revision['incluida'] == false) return false;
      return true;
    }).toList();

    final lineas = <Map<String, dynamic>>[];

    for (final p in movimientosIncluidos) {
      final esExtorno = p['tipo_movimiento'] == 'BAJA';

      if (esExtorno) {
        final ventaOriginalId = p['venta_original_id']?.toString().trim() ?? '';

        final primaExtornada = _money(
          p['prima_extornada'] ?? _primaNetaVenta(p).abs(),
        );
        final comisionExtornada = _money(
          p['comision_extornada'] ?? _comisionVenta(p).abs(),
        );

        lineas.add({
          'factura_id': facturaId,

          // ID real de la póliza/venta que se está extornando.
          'venta_id': ventaOriginalId.isNotEmpty
              ? ventaOriginalId
              : p['id'].toString().replaceFirst('baja_', ''),

          'numero_poliza': _numeroPoliza(p),
          'cliente_nombre': _nombreCliente(p),

          // Se guardan negativos para que el detalle económico muestre
          // claramente que es una resta.
          'prima_neta': -primaExtornada,
          'comision': -comisionExtornada,

          'tipo_movimiento': 'EXTORNO',
          'anulacion_id': p['anulacion_id'],

          // También se conservan los importes positivos en sus columnas
          // específicas para el detalle y el PDF.
          'prima_extornada': primaExtornada,
          'comision_extornada': comisionExtornada,
        });
      } else {
        lineas.add({
          'factura_id': facturaId,
          'venta_id': p['id'].toString(),
          'numero_poliza': _numeroPoliza(p),
          'cliente_nombre': _nombreCliente(p),
          'prima_neta': _primaNetaVenta(p),
          'comision': _comisionVenta(p),
          'tipo_movimiento': 'VENTA',
          'anulacion_id': null,
          'prima_extornada': 0.0,
          'comision_extornada': 0.0,
        });
      }
    }

    if (lineas.isNotEmpty) {
      await supabase.from('nominas_facturas_lineas').insert(lineas);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mes = nombreMes(widget.nomina['mes']);
    final anio = widget.nomina['anio'];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 66,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            elevation: 1,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF0F172A),
                size: 24,
              ),
            ),
          ),
        ),
        title: Text(
          'Factura $mes $anio',
          style: const TextStyle(
            color: const Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          const _PremiumBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: const Color(0xFF2563EB),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF2563EB),
                    backgroundColor: const Color(0xFFFFFFFF),
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
            const Color(0xFF059669).withOpacity(0.18),
            const Color(0xFFF8FAFC),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Control y verificación',
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Estructura jerárquica · ${nombreMes(widget.nomina['mes'])} ${widget.nomina['anio']}',
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${(comisiones).toStringAsFixed(2)} €',
            style: const TextStyle(
              color: const Color(0xFF059669),
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'Comisiones agentes · Primas ${primas.toStringAsFixed(2)} €',
            style: TextStyle(
              color: const Color(0xFF64748B),
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
      margin: EdgeInsets.only(left: level == 0 ? 0 : 8, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: level == 0
              ? const Color(0xFF2563EB).withOpacity(0.22)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          popupMenuTheme: const PopupMenuThemeData(
            color: Colors.white,
            textStyle: TextStyle(color: Color(0xFF0F172A)),
          ),
        ),
        child: ExpansionTile(
          initiallyExpanded: level == 0,
          maintainState: true,
          collapsedIconColor: const Color(0xFF475569),
          iconColor: const Color(0xFF2563EB),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _colorRol(node.rol).withOpacity(0.15),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(_iconoRol(node.rol), color: _colorRol(node.rol)),
          ),
          title: Text(
            nombre,
            style: const TextStyle(
              color: const Color(0xFF0F172A),
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
                  const Color(0xFF0284C7),
                ),
                _miniPill(
                  '${polizasTotales.length} estructura',
                  const Color(0xFF475569),
                ),
                _miniPill(
                  '${primasTotales.toStringAsFixed(0)} € primas',
                  const Color(0xFF059669),
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
              color: const Color(0xFF0284C7),
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
                color: const Color(0xFF2563EB),
              ),
              ...hijos.map((h) => _nodeCard(h, level + 1)),
            ] else if (node.rol != 'agente') ...[
              const SizedBox(height: 6),
              _tituloSeccionArbol(
                icon: Icons.account_tree_outlined,
                title: _tituloDependencias(node.rol),
                subtitle: 'No hay personas asignadas directamente',
                color: const Color(0xFF64748B),
              ),
            ],

            if (currentRole == 'director_zona')
              _botonAccionGrande(
                'Verificar esta persona y su estructura',
                Icons.verified_rounded,
                const Color(0xFFEA580C),
                () => verificarTodasZona(node),
              ),

            if (currentRole == 'director_nacional') ...[
              _botonAccionGrande(
                'Verificar esta persona y su estructura',
                Icons.workspace_premium_rounded,
                const Color(0xFF0284C7),
                () => verificarTodasNacional(node),
              ),
              const SizedBox(height: 8),
              _botonAccionGrande(
                'Marcar esta persona y su estructura como emitida',
                Icons.payments_rounded,
                const Color(0xFF059669),
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
        return const Color(0xFF7C3AED);
      case 'jefe_ventas':
        return const Color(0xFFD97706);
      case 'jefe_equipo':
        return const Color(0xFF2563EB);
      case 'agente':
        return const Color(0xFF059669);
      default:
        return const Color(0xFF475569);
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
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: const Color(0xFF64748B),
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
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        'Sin pólizas propias en este periodo.',
        style: TextStyle(
          color: const Color(0xFF64748B),
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

  Widget _resumenNode(_FacturaNode node, String estado, Color color) {
    final primasBrutas = _primasBrutasNode(node);
    final primasNetas = _primasNode(node);
    final rappel = _rappelNode(node);
    final porcentajeMix = _porcentajeMixNode(node);
    final comisionesPropias = _comisionesPropiasNode(node);
    final comisiones = _comisionesNode(node);
    final fijo = _fijoNode(node);
    final total = _totalSueldoNode(node);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _lineaResumen('Primas brutas', primasBrutas, const Color(0xFF475569)),
          _lineaResumen('Primas netas', primasNetas, const Color(0xFF2563EB)),
          _lineaDato(
            'Mix Decesos / Vida',
            '${porcentajeMix.toStringAsFixed(1)} %',
            porcentajeMix >= 30
                ? const Color(0xFF059669)
                : const Color(0xFFEA580C),
          ),
          _lineaResumen('Rappel', rappel, const Color(0xFFD97706)),
          _lineaResumen(
            'Comisiones propias',
            comisionesPropias,
            const Color(0xFF059669),
          ),
          _lineaResumen(
            'Comisiones equipo',
            comisiones,
            const Color(0xFF16A34A),
          ),
          _lineaResumen('Fijo', fijo, const Color(0xFF0284C7)),
          _lineaResumen('Total', total, const Color(0xFF059669)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Estado factura',
                  style: TextStyle(
                    color: const Color(0xFF64748B),
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

  Widget _lineaDato(String title, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
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
                color: const Color(0xFF475569),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} €',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
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
    final fechaEfecto =
        _fechaEfecto(venta)?.toString().split(' ').first ?? 'Sin fecha';
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
            ? Colors.white
            : const Color(0xFFDC2626).withOpacity(0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: incluida
              ? const Color(0xFFE2E8F0)
              : const Color(0xFFDC2626).withOpacity(0.25),
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
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: const Color(0xFF475569),
                ),
                color: const Color(0xFFFFFFFF),
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
            esBaja
                ? 'BAJA / EXTORNO · Póliza: $numeroPoliza'
                : 'Póliza: $numeroPoliza',
            style: TextStyle(
              color: const Color(0xFF2563EB).withOpacity(0.9),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Prima neta: ${prima.toStringAsFixed(2)} € · Comisión: ${comision.toStringAsFixed(2)} €',
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fecha efecto: $fechaEfecto · Recibo: $estadoRecibo · Firma CCPP: $estadoFirma',
            style: TextStyle(
              color: const Color(0xFF64748B),
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
                  polizaVerificada
                      ? const Color(0xFF059669)
                      : const Color(0xFFEA580C),
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
                  incluida ? const Color(0xFFDC2626) : const Color(0xFF059669),
                  () => actualizarPoliza(venta, incluida: !incluida),
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
                    zona ? const Color(0xFF059669) : const Color(0xFFEA580C),
                    () => actualizarPoliza(venta, verificadaZona: !zona),
                  ),
                ),
              if (currentRole == 'director_nacional')
                Expanded(
                  child: _accionPoliza(
                    nacional ? 'Nacional OK' : 'Nacional verifica',
                    Icons.workspace_premium_rounded,
                    nacional
                        ? const Color(0xFF059669)
                        : const Color(0xFF0284C7),
                    () =>
                        actualizarPoliza(venta, verificadaNacional: !nacional),
                  ),
                ),
            ],
          ),
          if (currentRole == 'director_nacional') ...[
            const SizedBox(height: 8),
            _accionPoliza(
              emitida ? 'Emitida' : 'Marcar emitida',
              Icons.payments_rounded,
              emitida ? const Color(0xFF059669) : const Color(0xFFD97706),
              () => actualizarPoliza(venta, emitida: !emitida),
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
          color: const Color(0xFF0F172A),
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
        color: const Color(0xFFEA580C).withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'El detalle de pólizas solo puede verlo Director Zona o Director Nacional.',
        style: TextStyle(
          color: const Color(0xFFEA580C),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _emptyEstructura() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Text(
        'No hay estructura ni facturas disponibles para este mes.',
        style: TextStyle(
          color: const Color(0xFF475569),
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
      backgroundColor: const Color(0xFFFFFFFF),
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
                    color: const Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  contenido,
                  style: TextStyle(
                    color: const Color(0xFF334155),
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
        Container(color: const Color(0xFFF3F6FA)),
        Positioned(
          top: -120,
          right: -90,
          child: _blurCircle(
            color: const Color(0xFF059669).withOpacity(0.18),
            size: 270,
          ),
        ),
        Positioned(
          top: 260,
          left: -130,
          child: _blurCircle(
            color: const Color(0xFF2563EB).withOpacity(0.16),
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

  Widget _blurCircle({required Color color, required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color, blurRadius: 95, spreadRadius: 38)],
      ),
    );
  }
}
