import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/production/production_period_service.dart';

class BiRentabilidadScreen extends StatefulWidget {
  const BiRentabilidadScreen({super.key});

  @override
  State<BiRentabilidadScreen> createState() => _BiRentabilidadScreenState();
}

class _BiRentabilidadScreenState extends State<BiRentabilidadScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabs;

  static const _primary = Color(0xFF0284C7);
  static const _primaryDark = Color(0xFF075985);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _border = Color(0xFFE2E8F0);
  static const _background = Color(0xFFF6F9FC);

  static const _companies = <String>[
    'Ocaso',
    'Santalucía',
    'DKV',
    'Adeslas',
    'Mapfre',
    'Generali',
    'Helvetia',
    'Axa',
    'Allianz',
    'Zurich',
    'Active',
    'Aura',
    'Occident',
    'Fiact',
    'Asisa',
    'Pelayo',
    'Reale Seguros',
    'Sanitas',
  ];

  bool _loading = true;
  bool _authorized = false;
  DateTime? _from;
  DateTime? _to;
  String _company = 'Todas';
  String _product = 'Todos';
  String _role = 'Todas';
  List<String> _products = [];
  List<Map<String, dynamic>> _rates = [];
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _invoiceLines = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _closures = [];
  String? _error;

  final _money = NumberFormat.currency(locale: 'es_ES', symbol: '€');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _initialize();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(
          value?.toString().trim().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _normalize(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  String _rateKey(String company, String product) =>
      '${_normalize(company)}|${_normalize(product)}';

  Future<void> _initialize() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Sesión no disponible.');

      final profile = await _supabase
          .from('usuarios')
          .select('rol_usuario')
          .or(
            'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
          )
          .eq('auth_id', user.id)
          .maybeSingle();
      final role = _normalize(
        _text(profile?['rol_usuario']),
      ).replaceAll('-', '_').replaceAll(' ', '_');
      if (role != 'director_nacional') {
        if (mounted) {
          setState(() {
            _authorized = false;
            _loading = false;
          });
        }
        return;
      }

      final period = await ProductionPeriodService.instance.current();
      _from = period.start;
      _to = DateTime(period.to.year, period.to.month, period.to.day);
      _authorized = true;
      await _loadEverything();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadEverything() async {
    if (!_authorized) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _supabase.from('comisiones_productos').select().order('orden'),
        _supabase.from('comisiones_aseguradoras').select().order('compania'),
        _supabase
            .from('usuarios')
            .select('id, auth_id, nombre, apellidos, rol_usuario, parent_id')
            .or(
              'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
            ),
        _supabase
            .from('cierres_produccion')
            .select('anio, mes, fecha_desde, fecha_hasta')
            .order('fecha_desde'),
      ]);
      final productRows = List<Map<String, dynamic>>.from(results[0] as List);
      _products = productRows
          .map((row) => _text(row['producto']))
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      _rates = List<Map<String, dynamic>>.from(results[1] as List);
      _users = List<Map<String, dynamic>>.from(results[2] as List);
      _closures = List<Map<String, dynamic>>.from(results[3] as List);
      await _loadAnalysis();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadAnalysis() async {
    if (_from == null || _to == null) return;
    try {
      final endExclusive = _to!.add(const Duration(days: 1));
      dynamic salesQuery = _supabase
          .from('ventas')
          .select(
            'id, agente_auth_id, producto, compania, numero_poliza, '
            'fecha_efecto, prima_anual_neta, prima_anual_bruta, comision',
          )
          .gte('fecha_efecto', _from!.toIso8601String())
          .lt('fecha_efecto', endExclusive.toIso8601String());
      if (_company != 'Todas') {
        salesQuery = salesQuery.eq('compania', _company);
      }
      if (_product != 'Todos') {
        salesQuery = salesQuery.eq('producto', _product);
      }

      final salesData = <Map<String, dynamic>>[];
      for (var offset = 0; ; offset += 1000) {
        final page = List<Map<String, dynamic>>.from(
          await salesQuery.order('id').range(offset, offset + 999) as List,
        );
        salesData.addAll(page);
        if (page.length < 1000) break;
      }
      final results = await Future.wait<dynamic>([
        _supabase.from('nominas_facturas').select(),
        _supabase.from('nominas_facturas_lineas').select(),
      ]);
      var sales = List<Map<String, dynamic>>.from(salesData);
      var invoices = List<Map<String, dynamic>>.from(results[0] as List);
      final allLines = List<Map<String, dynamic>>.from(results[1] as List);

      final usersByAuth = {
        for (final user in _users) _text(user['auth_id']): user,
      };
      if (_role != 'Todas') {
        sales = sales.where((sale) {
          return _text(
                usersByAuth[_text(sale['agente_auth_id'])]?['rol_usuario'],
              ) ==
              _role;
        }).toList();
        invoices = invoices
            .where((invoice) => _text(invoice['usuario_rol']) == _role)
            .toList();
      }

      invoices = invoices.where(_invoiceInsideFilter).toList();
      final invoiceIds = invoices.map((e) => _text(e['id'])).toSet();
      final lines = allLines
          .where((line) => invoiceIds.contains(_text(line['factura_id'])))
          .toList();

      if (!mounted) return;
      setState(() {
        _sales = sales;
        _invoices = invoices;
        _invoiceLines = lines;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  bool _invoiceInsideFilter(Map<String, dynamic> invoice) {
    final year = int.tryParse(_text(invoice['anio']));
    final month = int.tryParse(_text(invoice['mes']));
    if (year == null || month == null || _from == null || _to == null) {
      return false;
    }
    final closure = _closures.cast<Map<String, dynamic>?>().firstWhere(
      (row) =>
          int.tryParse(_text(row?['anio'])) == year &&
          int.tryParse(_text(row?['mes'])) == month,
      orElse: () => null,
    );
    final start = closure == null
        ? DateTime(year, month - 1, 24)
        : DateTime.parse(_text(closure['fecha_desde']));
    final end = closure == null
        ? DateTime(year, month, 23)
        : DateTime.parse(_text(closure['fecha_hasta']));
    return !end.isBefore(_from!) && !start.isAfter(_to!);
  }

  Map<String, Map<String, dynamic>> get _ratesByKey => {
    for (final rate in _rates)
      _rateKey(_text(rate['compania']), _text(rate['producto'])): rate,
  };

  double _incomeForSale(Map<String, dynamic> sale) {
    final rate =
        _ratesByKey[_rateKey(_text(sale['compania']), _text(sale['producto']))];
    if (rate == null || rate['activo'] == false) return 0;
    final base = _text(rate['base_calculo']) == 'prima_bruta'
        ? _number(sale['prima_anual_bruta'])
        : _number(sale['prima_anual_neta']);
    return base * _number(rate['porcentaje_comision']) / 100;
  }

  double get _income =>
      _sales.fold(0, (sum, sale) => sum + _incomeForSale(sale));

  double get _cost =>
      _invoices.fold(0, (sum, invoice) => sum + _invoiceCost(invoice));

  double get _result => _income - _cost;
  double get _margin => _income == 0 ? 0 : _result / _income * 100;

  int get _salesWithoutRate => _sales.where((sale) {
    return !_ratesByKey.containsKey(
      _rateKey(_text(sale['compania']), _text(sale['producto'])),
    );
  }).length;

  List<_ProfitRow> _rankingBy(String dimension) {
    final buckets = <String, _ProfitRow>{};
    final usersByAuth = {
      for (final user in _users) _text(user['auth_id']): user,
    };
    for (final sale in _sales) {
      final label = switch (dimension) {
        'company' => _text(sale['compania']),
        'product' => _text(sale['producto']),
        'role' => _text(
          usersByAuth[_text(sale['agente_auth_id'])]?['rol_usuario'],
        ),
        'month' => _monthLabel(DateTime.parse(_text(sale['fecha_efecto']))),
        _ => 'Sin clasificar',
      };
      final safeLabel = label.isEmpty ? 'Sin clasificar' : label;
      final row = buckets.putIfAbsent(safeLabel, () => _ProfitRow(safeLabel));
      row.income += _incomeForSale(sale);
      row.sales++;
    }

    if (dimension == 'role') {
      for (final invoice in _invoices) {
        final label = _text(invoice['usuario_rol']).isEmpty
            ? 'Sin clasificar'
            : _text(invoice['usuario_rol']);
        final row = buckets.putIfAbsent(label, () => _ProfitRow(label));
        row.cost += _invoiceCost(invoice);
      }
      final rows = buckets.values.toList()
        ..sort((a, b) => b.result.compareTo(a.result));
      return rows;
    }

    if (dimension == 'month') {
      for (final invoice in _invoices) {
        final year = int.tryParse(_text(invoice['anio']));
        final month = int.tryParse(_text(invoice['mes']));
        final label = year == null || month == null
            ? 'Sin clasificar'
            : _monthLabel(DateTime(year, month));
        final row = buckets.putIfAbsent(label, () => _ProfitRow(label));
        row.cost += _invoiceCost(invoice);
      }
      final rows = buckets.values.toList()
        ..sort((a, b) => b.result.compareTo(a.result));
      return rows;
    }

    final directCostsBySale = <String, double>{};
    for (final line in _invoiceLines) {
      final saleId = _text(line['venta_id']);
      if (saleId.isEmpty) continue;
      directCostsBySale[saleId] =
          (directCostsBySale[saleId] ?? 0) + _number(line['comision']);
    }
    var assignedDirectCost = 0.0;
    for (final sale in _sales) {
      final cost = directCostsBySale[_text(sale['id'])] ?? 0;
      assignedDirectCost += cost;
      final label = switch (dimension) {
        'company' => _text(sale['compania']),
        'product' => _text(sale['producto']),
        'role' => _text(
          usersByAuth[_text(sale['agente_auth_id'])]?['rol_usuario'],
        ),
        'month' => _monthLabel(DateTime.parse(_text(sale['fecha_efecto']))),
        _ => 'Sin clasificar',
      };
      buckets[label.isEmpty ? 'Sin clasificar' : label]?.cost += cost;
    }

    // Rappels, fijos y ajustes no vinculados se reparten proporcionalmente al
    // ingreso para que el total de cada ranking cuadre con la cuenta de resultados.
    final unassigned = _cost - assignedDirectCost;
    if (_income != 0) {
      for (final row in buckets.values) {
        row.cost += unassigned * row.income / _income;
      }
    }
    final rows = buckets.values.toList()
      ..sort((a, b) => b.result.compareTo(a.result));
    return rows;
  }

  double _invoiceCost(Map<String, dynamic> invoice) {
    final storedBase = invoice['base_imponible'];
    if (storedBase != null) return _number(storedBase);
    return _number(invoice['comisiones']) +
        _number(invoice['rappel']) +
        _number(invoice['fijo']);
  }

  String _monthLabel(DateTime value) =>
      DateFormat('MMM yyyy', 'es_ES').format(value);

  Future<void> _pickDate({required bool from}) async {
    final initial = from ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'ES'),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = picked;
      } else {
        _to = picked;
        if (_from != null && _from!.isAfter(picked)) _from = picked;
      }
    });
    await _loadAnalysis();
  }

  Future<void> _editRate(String company, String product) async {
    final existing = _ratesByKey[_rateKey(company, product)];
    final controller = TextEditingController(
      text: _number(existing?['porcentaje_comision']).toStringAsFixed(2),
    );
    var base = _text(existing?['base_calculo']);
    if (base.isEmpty) base = 'prima_neta';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$company · $product'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Comisión de la aseguradora',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: base,
                  decoration: const InputDecoration(
                    labelText: 'Base del cálculo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'prima_neta',
                      child: Text('Prima anual neta'),
                    ),
                    DropdownMenuItem(
                      value: 'prima_bruta',
                      child: Text('Prima anual bruta'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => base = value ?? 'prima_neta'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final percentage = double.tryParse(controller.text.replaceAll(',', '.'));
    if (percentage == null || percentage < 0 || percentage > 100) {
      _message('Introduce un porcentaje entre 0 y 100.', error: true);
      return;
    }
    final user = _supabase.auth.currentUser;
    await _supabase.from('comisiones_aseguradoras').upsert({
      'compania': company,
      'producto': product,
      'porcentaje_comision': percentage,
      'base_calculo': base,
      'activo': true,
      'creado_por': user?.id,
      'actualizado_por': user?.id,
    }, onConflict: 'compania,producto');
    _message('Comisión de aseguradora actualizada.');
    await _loadEverything();
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_authorized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_authorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('BI de Rentabilidad')),
        body: const Center(
          child: Text('Acceso exclusivo para Dirección Nacional.'),
        ),
      );
    }
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'BI de Rentabilidad',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _primary,
          indicatorWeight: 3,
          labelColor: _primaryDark,
          unselectedLabelColor: _muted,
          tabs: const [
            Tab(
              icon: Icon(Icons.analytics_rounded),
              text: 'Cuenta de resultados',
            ),
            Tab(icon: Icon(Icons.tune_rounded), text: 'Ingresos aseguradoras'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_dashboard(), _configuration()],
      ),
    );
  }

  Widget _dashboard() {
    if (_error != null) return _errorView();
    return RefreshIndicator(
      onRefresh: _loadEverything,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _executiveHeader(),
          const SizedBox(height: 16),
          _filters(),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpi(
                'Ingresos aseguradoras',
                _money.format(_income),
                Icons.account_balance_rounded,
                const Color(0xFF087E8B),
              ),
              _kpi(
                'Coste comercial',
                _money.format(_cost),
                Icons.payments_rounded,
                const Color(0xFF0A7F91),
              ),
              _kpi(
                'Resultado',
                _money.format(_result),
                _result >= 0 ? Icons.trending_up : Icons.trending_down,
                _result >= 0
                    ? const Color(0xFF0AAEAE)
                    : const Color(0xFFE74646),
              ),
              _kpi(
                'Margen de beneficio',
                '${_margin.toStringAsFixed(2)} %',
                Icons.percent_rounded,
                _margin >= 0
                    ? const Color(0xFF0A7F91)
                    : const Color(0xFFE74646),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_salesWithoutRate > 0) _missingRatesWarning(),
          _profitAndLoss(),
          const SizedBox(height: 16),
          _rankingSection('Rentabilidad por compañía', _rankingBy('company')),
          const SizedBox(height: 16),
          _rankingSection('Rentabilidad por producto', _rankingBy('product')),
          const SizedBox(height: 16),
          _rankingSection('Rentabilidad por figura', _rankingBy('role')),
          const SizedBox(height: 16),
          _rankingSection('Evolución mensual', _rankingBy('month')),
        ],
      ),
    );
  }

  Widget _executiveHeader() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE0F2FE), Color(0xFFF0FDFA)],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFFBAE6FD)),
    ),
    child: Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330284C7),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.query_stats_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inteligencia financiera de SafeBrok',
                style: TextStyle(
                  color: _ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Ingresos, costes comerciales y margen operativo en una única visión ejecutiva.',
                style: TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filters() => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: _border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _dateButton('Desde', _from, () => _pickDate(from: true)),
          _dateButton('Hasta', _to, () => _pickDate(from: false)),
          _filterDropdown('Compañía', _company, [
            'Todas',
            ..._companies,
          ], (value) => _changeFilter(() => _company = value)),
          _filterDropdown('Producto', _product, [
            'Todos',
            ..._products,
          ], (value) => _changeFilter(() => _product = value)),
          _filterDropdown('Figura', _role, const [
            'Todas',
            'agente',
            'jefe_equipo',
            'jefe_ventas',
            'director_zona',
            'director_nacional',
          ], (value) => _changeFilter(() => _role = value)),
          FilledButton.icon(
            onPressed: _loadAnalysis,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Actualizar'),
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
        ],
      ),
    ),
  );

  void _changeFilter(VoidCallback change) {
    setState(change);
    _loadAnalysis();
  }

  Widget _dateButton(
    String label,
    DateTime? value,
    VoidCallback onPressed,
  ) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.calendar_month_rounded),
    label: Text(
      '$label: ${value == null ? '-' : DateFormat('dd/MM/yyyy').format(value)}',
    ),
  );

  Widget _filterDropdown(
    String label,
    String value,
    List<String> items,
    ValueChanged<String> onChanged,
  ) => SizedBox(
    width: 205,
    child: DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : items.first,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
      ),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: (item) {
        if (item != null) onChanged(item);
      },
    ),
  );

  Widget _kpi(String title, String value, IconData icon, Color color) =>
      SizedBox(
        width: 265,
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: _border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: .12),
                  foregroundColor: color,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _missingRatesWarning() => Card(
    color: const Color(0xFFFFF4E5),
    elevation: 0,
    child: ListTile(
      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
      title: Text(
        '$_salesWithoutRate ventas sin comisión de aseguradora configurada',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: const Text(
        'Estas ventas cuentan como ingreso cero. Configúralas para que el '
        'resultado no quede infravalorado.',
      ),
      trailing: TextButton(
        onPressed: () => _tabs.animateTo(1),
        child: const Text('Configurar'),
      ),
    ),
  );

  Widget _profitAndLoss() => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: _border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cuenta de resultados',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _accountLine('Ingresos por producción', _income, positive: true),
          _accountLine(
            'Comisiones comerciales',
            _invoices.fold(0, (sum, row) => sum + _number(row['comisiones'])),
          ),
          _accountLine(
            'Rappels',
            _invoices.fold(0, (sum, row) => sum + _number(row['rappel'])),
          ),
          _accountLine(
            'Fijos y pagos comerciales',
            _invoices.fold(0, (sum, row) => sum + _number(row['fijo'])),
          ),
          const Divider(height: 28),
          _accountLine(
            'Resultado operativo',
            _result,
            total: true,
            positive: _result >= 0,
          ),
        ],
      ),
    ),
  );

  Widget _accountLine(
    String label,
    double amount, {
    bool positive = false,
    bool total = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: total ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          '${positive ? '' : '- '}${_money.format(amount.abs())}',
          style: TextStyle(
            fontSize: total ? 20 : 15,
            fontWeight: total ? FontWeight.w900 : FontWeight.w700,
            color: positive
                ? const Color(0xFF0AAEAE)
                : total && amount < 0
                ? const Color(0xFFE74646)
                : null,
          ),
        ),
      ],
    ),
  );

  Widget _rankingSection(String title, List<_ProfitRow> rows) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: _border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Text('No hay información para los filtros seleccionados.')
          else
            ...rows.take(12).toList().asMap().entries.map((entry) {
              final row = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${entry.key + 1}',
                        style: const TextStyle(color: Colors.black45),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        row.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${row.sales} ventas',
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _money.format(row.income),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _money.format(row.cost),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _money.format(row.result),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: row.result >= 0
                              ? const Color(0xFF0AAEAE)
                              : const Color(0xFFE74646),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    ),
  );

  Widget _configuration() {
    final selectedCompany = _company == 'Todas' ? _companies.first : _company;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _executiveHeader(),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: _border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comisiones recibidas de aseguradoras',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Son ingresos de SafeBrok y no modifican las comisiones que se pagan a los comerciales.',
                  style: TextStyle(color: _muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedCompany,
                    decoration: InputDecoration(
                      labelText: 'Aseguradora',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items: _companies
                        .map(
                          (company) => DropdownMenuItem(
                            value: company,
                            child: Text(company),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _company = value);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ..._products.map((product) {
          final rate = _ratesByKey[_rateKey(selectedCompany, product)];
          final percentage = _number(rate?['porcentaje_comision']);
          final base = _text(rate?['base_calculo']) == 'prima_bruta'
              ? 'Prima bruta'
              : 'Prima neta';
          return Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: _border),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE0F2FE),
                foregroundColor: _primary,
                child: const Icon(Icons.shield_outlined),
              ),
              title: Text(
                product,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(rate == null ? 'Pendiente de configurar' : base),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rate == null ? '—' : '${percentage.toStringAsFixed(2)} %',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: rate == null
                          ? Colors.orange.shade700
                          : const Color(0xFF087E8B),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed: () => _editRate(selectedCompany, product),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadEverything,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}

class _ProfitRow {
  final String label;
  double income = 0;
  double cost = 0;
  int sales = 0;

  _ProfitRow(this.label);

  double get result => income - cost;
}
