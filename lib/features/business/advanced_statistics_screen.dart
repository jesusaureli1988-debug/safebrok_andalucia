import 'dart:math' as math;
import 'package:safebrok_andalucia/core/production/policy_effect_date.dart';
import 'package:safebrok_andalucia/core/production/policy_sales_query.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdvancedStatisticsScreen extends StatefulWidget {
  final String role;

  const AdvancedStatisticsScreen({super.key, required this.role});

  @override
  State<AdvancedStatisticsScreen> createState() =>
      _AdvancedStatisticsScreenState();
}

class _AdvancedStatisticsScreenState extends State<AdvancedStatisticsScreen> {
  final _supabase = Supabase.instance.client;
  final _currency = NumberFormat.currency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: 0,
  );

  bool _loading = true;
  String? _error;
  String _period = 'mes';
  bool _teamScope = true;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _cancellations = [];
  Map<String, dynamic>? _goal;
  ProductionPeriod? _currentPeriod;

  static const _periods = <String, String>{
    'mes': 'Mes',
    'trimestre': '3 meses',
    'anio': 'Año',
    'todo': 'Histórico',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(_text(value)) ?? 0;

  String _role(dynamic value) =>
      _text(value).toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

  DateTime? _date(dynamic value) {
    if (value == null) return null;
    return value is DateTime ? value : DateTime.tryParse(value.toString());
  }

  bool get _hasTeam {
    final role = _role(_profile?['rol_usuario'] ?? widget.role);
    return role != 'agente' && role.isNotEmpty;
  }

  String get _roleLabel {
    switch (_role(_profile?['rol_usuario'] ?? widget.role)) {
      case 'administracion':
        return 'Administración';
      case 'director_nacional':
        return 'Director nacional';
      case 'director_regional':
        return 'Director regional';
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      default:
        return 'Agente';
    }
  }

  Future<void> _load({bool showLoader = true}) async {
    final auth = _supabase.auth.currentUser;
    if (auth == null) return;
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final base = await Future.wait<dynamic>([
        _supabase
            .from('usuarios')
            .select('id,auth_id,parent_id,nombre,apellidos,rol_usuario,estado')
            .eq('auth_id', auth.id)
            .maybeSingle(),
        _supabase
            .from('usuarios')
            .select('id,auth_id,parent_id,nombre,apellidos,rol_usuario,estado'),
        _supabase
            .from('objetivos_comerciales_anuales')
            .select()
            .eq('usuario_auth_id', auth.id)
            .eq('anio', DateTime.now().year)
            .maybeSingle(),
        ProductionPeriodService.instance.current(),
      ]);

      if (base[0] == null) throw Exception('Perfil no encontrado.');
      _profile = Map<String, dynamic>.from(base[0] as Map);
      _users = (base[1] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .where(_isActive)
          .toList();
      _goal = base[2] == null
          ? null
          : Map<String, dynamic>.from(base[2] as Map);
      _currentPeriod = base[3] as ProductionPeriod;

      if (!_hasTeam) _teamScope = false;
      final ids = _scopeAuthIds();
      if (ids.isEmpty) throw Exception('No hay usuarios en el ámbito actual.');

      final commercial = await Future.wait<dynamic>([
        PolicySalesQuery.load(_supabase, authIds: ids),
        _supabase
            .from('anulaciones_polizas')
            .select('id,venta_id,fecha_anulacion,prima_extornada,estado')
            .eq('estado', 'ANULADA'),
      ]);

      if (!mounted) return;
      setState(() {
        _sales = (commercial[0] as List)
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _cancellations = (commercial[1] as List)
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      debugPrint('ERROR ESTADISTICAS AVANZADAS: $error');
      debugPrint('$stack');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No hemos podido calcular las estadísticas.';
      });
    }
  }

  bool _isActive(Map<String, dynamic> user) {
    final status = _text(user['estado']).toLowerCase();
    return !{
      'inactivo',
      'baja',
      'desactivado',
      'bloqueado',
      'suspendido',
    }.contains(status);
  }

  List<Map<String, dynamic>> _structure() {
    final root = _profile;
    if (root == null) return [];
    if (!_teamScope) return [root];

    final role = _role(root['rol_usuario']);
    if (role == 'administracion' || role == 'director_nacional') {
      return _users;
    }

    final result = <Map<String, dynamic>>[root];
    final visited = <String>{_text(root['id'])};
    final pending = <Map<String, dynamic>>[root];
    while (pending.isNotEmpty) {
      final parentId = _text(pending.removeAt(0)['id']);
      for (final user in _users) {
        if (_text(user['parent_id']) != parentId) continue;
        final id = _text(user['id']);
        if (id.isEmpty || visited.contains(id)) continue;
        visited.add(id);
        result.add(user);
        pending.add(user);
      }
    }
    return result;
  }

  List<String> _scopeAuthIds() => _structure()
      .map((user) => _text(user['auth_id']))
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();

  DateTime get _rangeStart {
    final now = DateTime.now();
    switch (_period) {
      case 'trimestre':
        return DateTime(now.year, now.month - 2, 1);
      case 'anio':
        return DateTime(now.year, 1, 1);
      case 'todo':
        return DateTime(2000);
      default:
        return _currentPeriod?.start ?? DateTime(now.year, now.month, 1);
    }
  }

  DateTime get _rangeEnd {
    final now = DateTime.now();
    if (_period == 'mes' && _currentPeriod != null) {
      return _currentPeriod!.endExclusive;
    }
    return DateTime(now.year, now.month + 1, 1);
  }

  List<Map<String, dynamic>> get _periodSales {
    final ids = _scopeAuthIds().toSet();
    return _sales.where((sale) {
      final date = PolicyEffectDate.read(sale);
      return date != null &&
          ids.contains(_text(sale['agente_auth_id'])) &&
          !date.isBefore(_rangeStart) &&
          date.isBefore(_rangeEnd);
    }).toList();
  }

  List<Map<String, dynamic>> get _previousSales {
    if (_period == 'todo') return const [];
    final duration = _rangeEnd.difference(_rangeStart);
    final previousStart = _rangeStart.subtract(duration);
    final ids = _scopeAuthIds().toSet();
    return _sales.where((sale) {
      final date = PolicyEffectDate.read(sale);
      return date != null &&
          ids.contains(_text(sale['agente_auth_id'])) &&
          !date.isBefore(previousStart) &&
          date.isBefore(_rangeStart);
    }).toList();
  }

  double _premiumOf(Iterable<Map<String, dynamic>> sales) =>
      sales.fold(0, (sum, sale) => sum + PremiumWeighting.net(sale));

  double _commissionsOf(Iterable<Map<String, dynamic>> sales) =>
      sales.fold(0, (sum, sale) => sum + _number(sale['comision']));

  double get _premium => _premiumOf(_periodSales);
  double get _commissions => _commissionsOf(_periodSales);
  double get _average =>
      _periodSales.isEmpty ? 0 : _premium / _periodSales.length;

  double get _lifePremium => _periodSales
      .where((sale) {
        final product = _text(sale['producto']).toLowerCase();
        return product.contains('vida') ||
            product.contains('decesos') ||
            product.contains('prima única') ||
            product.contains('prima unica');
      })
      .fold(0, (sum, sale) => sum + PremiumWeighting.net(sale));

  double get _mix => _premium <= 0 ? 0 : _lifePremium / _premium * 100;

  double get _variation {
    final previous = _premiumOf(_previousSales);
    if (previous <= 0) return _premium > 0 ? 100 : 0;
    return (_premium - previous) / previous * 100;
  }

  double get _annualGoal => _number(_goal?['incremento_primas']);

  double get _weightedGoal {
    if (_annualGoal <= 0) return 0;
    final now = DateTime.now();
    if (_period == 'mes') return _annualGoal / 12;
    if (_period == 'trimestre') return _annualGoal / 4;
    if (_period == 'anio') return _annualGoal * now.month / 12;
    return _annualGoal;
  }

  double get _goalProgress =>
      _weightedGoal <= 0 ? 0 : (_premium / _weightedGoal * 100);

  Set<String> get _cancelledSaleIds => _cancellations
      .map((item) => _text(item['venta_id']))
      .where((id) => id.isNotEmpty)
      .toSet();

  int get _cancellationsInPeriod => _periodSales
      .where((sale) => _cancelledSaleIds.contains(_text(sale['id'])))
      .length;

  Map<String, double> get _products {
    final result = <String, double>{};
    for (final sale in _periodSales) {
      final name = _text(sale['producto']).isEmpty
          ? 'Sin clasificar'
          : _text(sale['producto']);
      result[name] = (result[name] ?? 0) + PremiumWeighting.net(sale);
    }
    final sorted = result.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map<String, double>.fromEntries(sorted);
  }

  List<_TrendPoint> get _trend {
    final now = DateTime.now();
    final months = _period == 'anio' || _period == 'todo' ? 12 : 6;
    final ids = _scopeAuthIds().toSet();
    return List.generate(months, (index) {
      final date = DateTime(now.year, now.month - (months - 1 - index), 1);
      final end = DateTime(date.year, date.month + 1, 1);
      final value = _sales
          .where((sale) {
            final saleDate = PolicyEffectDate.read(sale);
            return saleDate != null &&
                ids.contains(_text(sale['agente_auth_id'])) &&
                !saleDate.isBefore(date) &&
                saleDate.isBefore(end);
          })
          .fold<double>(0, (sum, sale) => sum + PremiumWeighting.net(sale));
      return _TrendPoint(DateFormat.MMM('es_ES').format(date), value);
    });
  }

  List<_Insight> get _insights {
    final result = <_Insight>[];
    if (_weightedGoal > 0) {
      final remaining = math.max(0, _weightedGoal - _premium);
      result.add(
        _Insight(
          icon: _goalProgress >= 100
              ? Icons.verified_rounded
              : Icons.track_changes_rounded,
          color: _goalProgress >= 100
              ? const Color(0xFF16A36A)
              : const Color(0xFF2454D3),
          title: _goalProgress >= 100
              ? 'Objetivo del periodo alcanzado'
              : 'Faltan ${_currency.format(remaining)} para el objetivo',
          body: _goalProgress >= 100
              ? 'La producción ya supera el objetivo ponderado del periodo.'
              : 'El cumplimiento actual es del ${_goalProgress.toStringAsFixed(1)}%.',
        ),
      );
    }
    result.add(
      _Insight(
        icon: Icons.balance_rounded,
        color: _mix >= 30 ? const Color(0xFF16A36A) : const Color(0xFFE88A17),
        title: _mix >= 30
            ? 'Mix comercial equilibrado'
            : 'Oportunidad de mejorar el mix',
        body:
            'Decesos y Vida representan el ${_mix.toStringAsFixed(1)}% de la producción.',
      ),
    );
    if (_variation != 0 && _period != 'todo') {
      result.add(
        _Insight(
          icon: _variation >= 0
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          color: _variation >= 0
              ? const Color(0xFF16A36A)
              : const Color(0xFFE45252),
          title:
              '${_variation >= 0 ? '+' : ''}${_variation.toStringAsFixed(1)}% frente al periodo anterior',
          body: _variation >= 0
              ? 'La producción evoluciona por encima del periodo comparable.'
              : 'Conviene revisar actividad, conversión y oportunidades abiertas.',
        ),
      );
    }
    if (_products.isNotEmpty) {
      final best = _products.entries.first;
      result.add(
        _Insight(
          icon: Icons.auto_graph_rounded,
          color: const Color(0xFF6F4BD8),
          title: '${best.key} lidera la producción',
          body:
              'Aporta ${_currency.format(best.value)} en el periodo seleccionado.',
        ),
      );
    }
    return result;
  }

  BoxDecoration _cardDecoration({bool elevated = false}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: const Color(0xFFE1E5EA)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF13284C).withValues(alpha: elevated ? .13 : .07),
        blurRadius: elevated ? 28 : 18,
        offset: Offset(0, elevated ? 12 : 7),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2454D3)),
              )
            : _error != null
            ? _errorView()
            : RefreshIndicator(
                onRefresh: () => _load(showLoader: false),
                color: const Color(0xFF2454D3),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        wide ? 28 : 16,
                        12,
                        wide ? 28 : 16,
                        36,
                      ),
                      children: [
                        _topBar(),
                        const SizedBox(height: 18),
                        _hero(),
                        const SizedBox(height: 18),
                        _filters(),
                        const SizedBox(height: 18),
                        _kpiGrid(wide),
                        const SizedBox(height: 18),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 6, child: _trendCard()),
                              const SizedBox(width: 18),
                              Expanded(flex: 4, child: _performanceCard()),
                            ],
                          )
                        else ...[
                          _trendCard(),
                          const SizedBox(height: 18),
                          _performanceCard(),
                        ],
                        const SizedBox(height: 18),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _productsCard()),
                              const SizedBox(width: 18),
                              Expanded(child: _insightsCard()),
                            ],
                          )
                        else ...[
                          _productsCard(),
                          const SizedBox(height: 18),
                          _insightsCard(),
                        ],
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _topBar() => Row(
    children: [
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.pop(context),
          child: const Padding(
            padding: EdgeInsets.all(13),
            child: Icon(Icons.arrow_back_rounded, color: Color(0xFF111C31)),
          ),
        ),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Text(
          'Estadísticas avanzadas',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111C31),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Actualizar',
        onPressed: () => _load(),
        icon: const Icon(Icons.refresh_rounded, color: Color(0xFF111C31)),
      ),
    ],
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF14213D), Color(0xFF2454D3)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF2454D3).withValues(alpha: .22),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 620;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'INTELIGENCIA COMERCIAL',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: .7,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Decisiones claras,\nresultados medibles.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_roleLabel} · ${_teamScope && _hasTeam ? 'visión de estructura' : 'visión propia'}',
              style: const TextStyle(
                color: Color(0xFFDDE6FF),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
        final metric = Column(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            const Text(
              'Producción analizada',
              style: TextStyle(
                color: Color(0xFFDDE6FF),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              child: Text(
                _currency.format(_premium),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_periodSales.length} pólizas · Mix ${_mix.toStringAsFixed(1)}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
        if (compact)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [copy, const SizedBox(height: 24), metric],
          );
        return Row(
          children: [
            Expanded(child: copy),
            const SizedBox(width: 30),
            metric,
          ],
        );
      },
    ),
  );
  Widget _filters() => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(),
    child: Wrap(
      spacing: 10,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 6),
          child: Text(
            'Periodo',
            style: TextStyle(
              color: Color(0xFF111C31),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ..._periods.entries.map(
          (entry) => ChoiceChip(
            label: Text(entry.value),
            selected: _period == entry.key,
            onSelected: (_) => setState(() => _period = entry.key),
            selectedColor: const Color(0xFF2454D3),
            backgroundColor: const Color(0xFFF3F5F8),
            side: BorderSide(
              color: _period == entry.key
                  ? const Color(0xFF2454D3)
                  : const Color(0xFFE1E5EA),
            ),
            labelStyle: TextStyle(
              color: _period == entry.key
                  ? Colors.white
                  : const Color(0xFF46536A),
              fontWeight: FontWeight.w700,
            ),
            showCheckmark: false,
          ),
        ),
        if (_hasTeam) ...[
          const SizedBox(width: 8),
          Container(width: 1, height: 32, color: const Color(0xFFE1E5EA)),
          ChoiceChip(
            avatar: Icon(
              Icons.person_rounded,
              size: 18,
              color: !_teamScope ? Colors.white : const Color(0xFF46536A),
            ),
            label: const Text('Propio'),
            selected: !_teamScope,
            onSelected: (_) => setState(() => _teamScope = false),
            selectedColor: const Color(0xFF14213D),
            backgroundColor: const Color(0xFFF3F5F8),
            labelStyle: TextStyle(
              color: !_teamScope ? Colors.white : const Color(0xFF46536A),
              fontWeight: FontWeight.w700,
            ),
            showCheckmark: false,
          ),
          ChoiceChip(
            avatar: Icon(
              Icons.account_tree_rounded,
              size: 18,
              color: _teamScope ? Colors.white : const Color(0xFF46536A),
            ),
            label: const Text('Estructura'),
            selected: _teamScope,
            onSelected: (_) => setState(() => _teamScope = true),
            selectedColor: const Color(0xFF14213D),
            backgroundColor: const Color(0xFFF3F5F8),
            labelStyle: TextStyle(
              color: _teamScope ? Colors.white : const Color(0xFF46536A),
              fontWeight: FontWeight.w700,
            ),
            showCheckmark: false,
          ),
        ],
      ],
    ),
  );

  Widget _kpiGrid(bool wide) {
    final cards = [
      _kpiCard(
        Icons.euro_rounded,
        'Primas',
        _currency.format(_premium),
        'Prima computable',
        const Color(0xFF2454D3),
        _variation,
      ),
      _kpiCard(
        Icons.pie_chart_rounded,
        'Mix Decesos + Vida',
        '${_mix.toStringAsFixed(1)}%',
        _currency.format(_lifePremium),
        const Color(0xFF6F4BD8),
        null,
      ),
      _kpiCard(
        Icons.receipt_long_rounded,
        'Comisiones',
        _currency.format(_commissions),
        'Generadas en el periodo',
        const Color(0xFF109A8D),
        null,
      ),
      _kpiCard(
        Icons.stacked_bar_chart_rounded,
        'Prima media',
        _currency.format(_average),
        '${_periodSales.length} pólizas',
        const Color(0xFFE88A17),
        null,
      ),
    ];
    return GridView.count(
      crossAxisCount: wide ? 4 : 2,
      childAspectRatio: wide ? 1.7 : 1.2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  Widget _kpiCard(
    IconData icon,
    String title,
    String value,
    String subtitle,
    Color color,
    double? variation,
  ) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(elevated: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const Spacer(),
            if (variation != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color:
                      (variation >= 0
                              ? const Color(0xFF16A36A)
                              : const Color(0xFFE45252))
                          .withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${variation >= 0 ? '+' : ''}${variation.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: variation >= 0
                        ? const Color(0xFF168259)
                        : const Color(0xFFC84040),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF4E5A70),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111C31),
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF778195),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _sectionHeader(IconData icon, String title, String subtitle) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF0FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: const Color(0xFF2454D3)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF111C31),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF778195),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _trendCard() {
    final points = _trend;
    final maxValue = points.fold<double>(
      0,
      (max, item) => math.max(max, item.value),
    );
    return Container(
      height: 390,
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.show_chart_rounded,
            'Evolución de producción',
            'Primas computables de los últimos ${points.length} meses',
          ),
          const SizedBox(height: 26),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxValue <= 0 ? 100 : maxValue * 1.22,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxValue <= 0 ? 25 : maxValue / 4,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Color(0xFFE8EBF0), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF14213D),
                    getTooltipItems: (spots) => spots
                        .map(
                          (spot) => LineTooltipItem(
                            _currency.format(spot.y),
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length)
                          return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            points[index].label.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF778195),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < points.length; i++)
                        FlSpot(i.toDouble(), points[i].value),
                    ],
                    isCurved: true,
                    curveSmoothness: .28,
                    color: const Color(0xFF2454D3),
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 4,
                        color: Colors.white,
                        strokeWidth: 3,
                        strokeColor: const Color(0xFF2454D3),
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF2454D3).withValues(alpha: .22),
                          const Color(0xFF2454D3).withValues(alpha: .01),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
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

  Widget _performanceCard() {
    final progress = (_goalProgress / 100).clamp(0.0, 1.0);
    return Container(
      constraints: const BoxConstraints(minHeight: 390),
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.track_changes_rounded,
            'Cumplimiento',
            'Objetivo ponderado del periodo',
          ),
          const SizedBox(height: 26),
          Center(
            child: SizedBox(
              width: 158,
              height: 158,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 14,
                      backgroundColor: const Color(0xFFE9EDF4),
                      color: _goalProgress >= 100
                          ? const Color(0xFF16A36A)
                          : const Color(0xFF2454D3),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_goalProgress.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Color(0xFF111C31),
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'alcanzado',
                        style: TextStyle(
                          color: Color(0xFF778195),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _metricRow(
            'Objetivo del periodo',
            _weightedGoal > 0 ? _currency.format(_weightedGoal) : 'Sin definir',
          ),
          _metricRow('Producción actual', _currency.format(_premium)),
          _metricRow(
            'Anulaciones',
            '$_cancellationsInPeriod',
            warning: _cancellationsInPeriod > 0,
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, String value, {bool warning = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF667187),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: warning
                    ? const Color(0xFFC84040)
                    : const Color(0xFF111C31),
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );

  Widget _productsCard() {
    final products = _products.entries.take(7).toList();
    final maximum = products.isEmpty
        ? 1.0
        : math.max(1.0, products.first.value);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _cardDecoration(elevated: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.donut_large_rounded,
            'Distribución por productos',
            'Qué está generando la producción',
          ),
          const SizedBox(height: 22),
          if (products.isEmpty)
            const _EmptyBlock(
              message: 'Todavía no hay producción en este periodo.',
            )
          else
            ...products.asMap().entries.map((indexed) {
              final entry = indexed.value;
              const palette = [
                Color(0xFF2454D3),
                Color(0xFF109A8D),
                Color(0xFF6F4BD8),
                Color(0xFFE88A17),
                Color(0xFF3E78C7),
                Color(0xFF16A36A),
                Color(0xFF8A5B35),
              ];
              final color = palette[indexed.key % palette.length];
              final share = _premium <= 0 ? 0.0 : entry.value / _premium * 100;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            entry.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF27344C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${share.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Color(0xFF778195),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _currency.format(entry.value),
                          style: const TextStyle(
                            color: Color(0xFF111C31),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: (entry.value / maximum).clamp(0, 1),
                        minHeight: 7,
                        backgroundColor: const Color(0xFFE9EDF4),
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _insightsCard() => Container(
    padding: const EdgeInsets.all(22),
    decoration: _cardDecoration(elevated: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          Icons.lightbulb_rounded,
          'Lectura comercial',
          'Alertas y oportunidades detectadas',
        ),
        const SizedBox(height: 18),
        ..._insights.map(
          (insight) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: insight.color.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: insight.color.withValues(alpha: .18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(insight.icon, color: insight.color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        style: const TextStyle(
                          color: Color(0xFF111C31),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        insight.body,
                        style: const TextStyle(
                          color: Color(0xFF667187),
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(28),
        decoration: _cardDecoration(elevated: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.analytics_outlined,
              color: Color(0xFF2454D3),
              size: 52,
            ),
            const SizedBox(height: 16),
            const Text(
              'No se pudieron cargar las estadísticas',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF111C31),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF667187)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TrendPoint {
  final String label;
  final double value;
  const _TrendPoint(this.label, this.value);
}

class _Insight {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  const _Insight({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
}

class _EmptyBlock extends StatelessWidget {
  final String message;
  const _EmptyBlock({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F7FA),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.query_stats_rounded,
          color: Color(0xFF9AA4B5),
          size: 38,
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF667187),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
