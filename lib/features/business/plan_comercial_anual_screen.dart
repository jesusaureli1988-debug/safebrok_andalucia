import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'informes_programados_panel.dart';

class PlanComercialAnualScreen extends StatefulWidget {
  const PlanComercialAnualScreen({super.key});

  @override
  State<PlanComercialAnualScreen> createState() =>
      _PlanComercialAnualScreenState();
}

class _PlanComercialAnualScreenState extends State<PlanComercialAnualScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabs;

  static const _allowedRoles = {
    'jefe_equipo',
    'jefe_ventas',
    'director_zona',
    'director_nacional',
  };

  static const _definitions = <_MetricDefinition>[
    _MetricDefinition(
      keyName: 'incremento_prima_sin_vehiculos',
      title: 'Incremento de prima',
      subtitle: 'Crecimiento interanual excluyendo vehículos',
      unit: _MetricUnit.currency,
      icon: Icons.trending_up_rounded,
      color: Color(0xFF2563EB),
    ),
    _MetricDefinition(
      keyName: 'incremento_asegurados',
      title: 'Incremento de asegurados',
      subtitle: 'Variación anual del número de asegurados',
      unit: _MetricUnit.number,
      icon: Icons.groups_rounded,
      color: Color(0xFF7C3AED),
    ),
    _MetricDefinition(
      keyName: 'incremento_ventas_netas',
      title: 'Incremento de ventas netas',
      subtitle: 'Diferencia frente a las ventas netas del año anterior',
      unit: _MetricUnit.number,
      icon: Icons.stacked_line_chart_rounded,
      color: Color(0xFF0891B2),
    ),
    _MetricDefinition(
      keyName: 'porcentaje_pendiente',
      title: 'Pendiente de recibos',
      subtitle: 'Porcentaje máximo de recibos pendientes',
      unit: _MetricUnit.percentage,
      inverse: true,
      icon: Icons.pending_actions_rounded,
      color: Color(0xFFD97706),
    ),
    _MetricDefinition(
      keyName: 'anulaciones_decesos',
      title: 'Anulaciones decesos',
      subtitle: 'Límite anual de pólizas de decesos anuladas',
      unit: _MetricUnit.number,
      inverse: true,
      icon: Icons.policy_outlined,
      color: Color(0xFFDC2626),
    ),
    _MetricDefinition(
      keyName: 'anulaciones_resto',
      title: 'Anulaciones resto',
      subtitle: 'Límite anual para el resto de productos',
      unit: _MetricUnit.number,
      inverse: true,
      icon: Icons.remove_circle_outline_rounded,
      color: Color(0xFFE11D48),
    ),
    _MetricDefinition(
      keyName: 'ventas_netas',
      title: 'Ventas netas',
      subtitle: 'Altas menos anulaciones del año',
      unit: _MetricUnit.number,
      icon: Icons.shopping_bag_outlined,
      color: Color(0xFF059669),
    ),
    _MetricDefinition(
      keyName: 'facturacion',
      title: 'Facturación',
      subtitle: 'Prima anual neta generada',
      unit: _MetricUnit.currency,
      icon: Icons.euro_rounded,
      color: Color(0xFF0F766E),
    ),
    _MetricDefinition(
      keyName: 'captacion',
      title: 'Captación',
      subtitle: 'Candidatos incorporados al proceso',
      unit: _MetricUnit.number,
      icon: Icons.person_add_alt_1_rounded,
      color: Color(0xFF9333EA),
    ),
    _MetricDefinition(
      keyName: 'liquido_decesos',
      title: 'Líquido decesos',
      subtitle: 'Prima neta de decesos menos prima extornada',
      unit: _MetricUnit.currency,
      icon: Icons.waterfall_chart_rounded,
      color: Color(0xFF0369A1),
    ),
  ];

  bool _loading = true;
  bool _authorized = false;
  String? _error;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _selectedFigure;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _goals = [];
  Map<String, double> _actuals = {};
  Map<String, double> _monthlyActuals = {};
  Map<String, double> _cumulativeActuals = {};

  final _currency = NumberFormat.currency(locale: 'es_ES', symbol: '€');
  final _number = NumberFormat.decimalPattern('es_ES');

  bool get _isNationalDirector =>
      _text(_profile?['rol_usuario']) == 'director_nacional';

  bool get _canAnalyzeLeadershipStructure {
    final role = _text(_profile?['rol_usuario']);
    return role == 'director_nacional' ||
        role == 'director_zona' ||
        role == 'jefe_ventas';
  }

  List<_MetricDefinition> get _visibleDefinitions {
    final viewerRole = _text(_profile?['rol_usuario']);
    final figure = _selectedFigure ?? _profile;
    final figureRole = _text(figure?['rol_usuario']);
    final isOwnPlan = _text(figure?['auth_id']) == _text(_profile?['auth_id']);

    if (viewerRole == 'director_nacional') return _definitions;

    // El director de zona conserva una visión completa de las figuras
    // subordinadas, aunque esas figuras no vean todos esos indicadores.
    if (viewerRole == 'director_zona' && !isOwnPlan) return _definitions;

    final hiddenKeys = switch (figureRole) {
      'director_zona' => {'facturacion', 'anulaciones_resto'},
      'jefe_ventas' => {
        'facturacion',
        'anulaciones_resto',
        'ventas_netas',
        'incremento_ventas_netas',
      },
      'jefe_equipo' => {
        'facturacion',
        'anulaciones_resto',
        'ventas_netas',
        'incremento_ventas_netas',
        'liquido_decesos',
      },
      _ => <String>{},
    };

    return _definitions
        .where((definition) => !hiddenKeys.contains(definition.keyName))
        .toList();
  }

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

  String _text(dynamic value) => value?.toString().trim() ?? '';

  double _value(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  DateTime? _date(dynamic value) => DateTime.tryParse(value?.toString() ?? '');

  Future<void> _initialize() async {
    try {
      final authUser = _supabase.auth.currentUser;
      if (authUser == null) throw Exception('No existe una sesión activa.');
      final profile = await _supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, nombre, apellidos, rol_usuario')
          .eq('auth_id', authUser.id)
          .maybeSingle();
      if (profile == null) throw Exception('Perfil de usuario no encontrado.');
      final role = _text(profile['rol_usuario']);
      if (!_allowedRoles.contains(role)) {
        if (mounted) {
          setState(() {
            _authorized = false;
            _loading = false;
          });
        }
        return;
      }
      _profile = Map<String, dynamic>.from(profile);
      _selectedFigure = _profile;
      _authorized = true;
      await _loadBase();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadBase() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _supabase
            .from('usuarios')
            .select(
              'id, auth_id, parent_id, nombre, apellidos, rol_usuario, estado',
            ),
        _supabase
            .from('objetivos_comerciales_anuales')
            .select()
            .eq('anio', _year),
      ]);
      _users = List<Map<String, dynamic>>.from(results[0] as List);
      _goals = List<Map<String, dynamic>>.from(results[1] as List);
      if (_selectedFigure == null ||
          !_users.any(
            (user) =>
                _text(user['auth_id']) == _text(_selectedFigure?['auth_id']),
          )) {
        _selectedFigure = _profile;
      }
      await _calculateActuals();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _structureOf(Map<String, dynamic> root) {
    final rootId = _text(root['id']);
    if (rootId.isEmpty) return [root];
    final children = <String, List<Map<String, dynamic>>>{};
    for (final user in _users) {
      final parentId = _text(user['parent_id']);
      if (parentId.isNotEmpty) {
        children.putIfAbsent(parentId, () => []).add(user);
      }
    }
    final output = <Map<String, dynamic>>[root];
    final visited = <String>{rootId};
    final pending = <Map<String, dynamic>>[root];
    while (pending.isNotEmpty) {
      final parent = pending.removeAt(0);
      for (final child in children[_text(parent['id'])] ?? const []) {
        final id = _text(child['id']);
        if (id.isEmpty || visited.contains(id)) continue;
        visited.add(id);
        output.add(child);
        pending.add(child);
      }
    }
    return output;
  }

  Future<void> _calculateActuals() async {
    final figure = _selectedFigure;
    if (figure == null) return;
    final authIds = _structureOf(figure)
        .map((user) => _text(user['auth_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (authIds.isEmpty) {
      setState(() {
        _actuals = {};
        _loading = false;
      });
      return;
    }
    final from = DateTime(_year, 1, 1);
    final to = DateTime(_year + 1, 1, 1);
    final previousFrom = DateTime(_year - 1, 1, 1);
    final monthFrom = DateTime(_year, _month, 1);
    final monthTo = DateTime(_year, _month + 1, 1);
    final previousMonthFrom = DateTime(_year - 1, _month, 1);
    final previousMonthTo = DateTime(_year - 1, _month + 1, 1);

    try {
      final results = await Future.wait([
        _supabase
            .from('ventas')
            .select(
              'id, agente_auth_id, producto, fecha_efecto, prima_anual_neta, '
              'numero_asegurados, estado_poliza',
            )
            .inFilter('agente_auth_id', authIds),
        _supabase
            .from('anulaciones_polizas')
            .select('id, venta_id, fecha_anulacion, prima_extornada, estado')
            .eq('estado', 'ANULADA')
            .gte('fecha_anulacion', previousFrom.toIso8601String())
            .lt('fecha_anulacion', to.toIso8601String()),
        _supabase
            .from('recibos')
            .select('id, agente, estado, estado_recibo, fecha')
            .inFilter('agente', authIds)
            .gte('fecha', from.toIso8601String())
            .lt('fecha', to.toIso8601String()),
        _supabase
            .from('candidatos_captacion')
            .select('id, asignado_auth_id, fecha_asignacion')
            .inFilter('asignado_auth_id', authIds)
            .gte('fecha_asignacion', from.toIso8601String())
            .lt('fecha_asignacion', to.toIso8601String()),
      ]);
      final sales = List<Map<String, dynamic>>.from(results[0] as List);
      final allCancellations = List<Map<String, dynamic>>.from(
        results[1] as List,
      );
      final receipts = List<Map<String, dynamic>>.from(results[2] as List);
      final candidates = List<Map<String, dynamic>>.from(results[3] as List);
      final salesById = {for (final sale in sales) _text(sale['id']): sale};
      final currentSales = sales.where((sale) {
        final date = _date(sale['fecha_efecto']);
        return date != null && !date.isBefore(from) && date.isBefore(to);
      }).toList();
      final previousSales = sales.where((sale) {
        final date = _date(sale['fecha_efecto']);
        return date != null &&
            !date.isBefore(previousFrom) &&
            date.isBefore(from);
      }).toList();
      final structureCancellations = allCancellations.where((cancellation) {
        final sale = salesById[_text(cancellation['venta_id'])];
        return sale != null && authIds.contains(_text(sale['agente_auth_id']));
      }).toList();
      final validCancellations = structureCancellations.where((cancellation) {
        final date = _date(cancellation['fecha_anulacion']);
        return date != null && !date.isBefore(from) && date.isBefore(to);
      }).toList();
      final previousCancellations = structureCancellations.where((
        cancellation,
      ) {
        final date = _date(cancellation['fecha_anulacion']);
        return date != null &&
            !date.isBefore(previousFrom) &&
            date.isBefore(from);
      }).toList();
      final monthCancellations = validCancellations.where((cancellation) {
        final date = _date(cancellation['fecha_anulacion']);
        return date != null &&
            !date.isBefore(monthFrom) &&
            date.isBefore(monthTo);
      }).toList();
      final previousMonthCancellations = previousCancellations.where((
        cancellation,
      ) {
        final date = _date(cancellation['fecha_anulacion']);
        return date != null &&
            !date.isBefore(previousMonthFrom) &&
            date.isBefore(previousMonthTo);
      }).toList();

      bool vehicle(Map<String, dynamic> sale) {
        final product = _text(sale['producto']).toLowerCase();
        return product.contains('auto') ||
            product.contains('moto') ||
            product.contains('vehicul');
      }

      bool deaths(Map<String, dynamic> sale) =>
          _text(sale['producto']).toLowerCase().contains('deces');

      double premium(
        Iterable<Map<String, dynamic>> rows, {
        bool withoutVehicles = false,
        bool onlyDeaths = false,
      }) => rows
          .where((sale) {
            if (withoutVehicles && vehicle(sale)) return false;
            if (onlyDeaths && !deaths(sale)) return false;
            return true;
          })
          .fold(0, (sum, sale) => sum + _value(sale['prima_anual_neta']));

      double insured(Iterable<Map<String, dynamic>> rows) =>
          rows.fold(0, (sum, sale) => sum + _value(sale['numero_asegurados']));

      final currentCancellationIds = validCancellations
          .map((row) => _text(row['venta_id']))
          .toSet();
      final currentNet = currentSales.length - currentCancellationIds.length;
      final previousNet = previousSales.length - previousCancellations.length;
      final deathsCancellations = validCancellations.where((row) {
        final sale = salesById[_text(row['venta_id'])];
        return sale != null && deaths(sale);
      }).toList();
      final pendingReceipts = receipts.where((receipt) {
        final status =
            '${_text(receipt['estado_recibo'])} ${_text(receipt['estado'])}'
                .toLowerCase();
        return status.contains('pendiente');
      }).length;
      final deathReversals = deathsCancellations.fold(
        0.0,
        (sum, row) => sum + _value(row['prima_extornada']),
      );
      final currentMonthSales = currentSales.where((sale) {
        final date = _date(sale['fecha_efecto']);
        return date != null &&
            !date.isBefore(monthFrom) &&
            date.isBefore(monthTo);
      }).toList();
      final previousMonthSales = previousSales.where((sale) {
        final date = _date(sale['fecha_efecto']);
        return date != null &&
            !date.isBefore(previousMonthFrom) &&
            date.isBefore(previousMonthTo);
      }).toList();
      final monthCancellationIds = monthCancellations
          .map((row) => _text(row['venta_id']))
          .toSet();
      final monthNet = currentMonthSales.length - monthCancellationIds.length;
      final previousMonthNet =
          previousMonthSales.length - previousMonthCancellations.length;
      final monthDeathsCancellations = monthCancellations.where((row) {
        final sale = salesById[_text(row['venta_id'])];
        return sale != null && deaths(sale);
      }).toList();
      final monthReceipts = receipts.where((receipt) {
        final date = _date(receipt['fecha']);
        return date != null &&
            !date.isBefore(monthFrom) &&
            date.isBefore(monthTo);
      }).toList();
      final monthPendingReceipts = monthReceipts.where((receipt) {
        final status =
            '${_text(receipt['estado_recibo'])} ${_text(receipt['estado'])}'
                .toLowerCase();
        return status.contains('pendiente');
      }).length;
      final monthCandidates = candidates.where((candidate) {
        final date = _date(candidate['fecha_asignacion']);
        return date != null &&
            !date.isBefore(monthFrom) &&
            date.isBefore(monthTo);
      }).toList();
      final monthDeathReversals = monthDeathsCancellations.fold(
        0.0,
        (sum, row) => sum + _value(row['prima_extornada']),
      );
      final cumulativeSales = currentSales.where((sale) {
        final date = _date(sale['fecha_efecto']);
        return date != null && date.isBefore(monthTo);
      }).toList();
      final previousCumulativeSales = previousSales.where((sale) {
        final date = _date(sale['fecha_efecto']);
        return date != null && date.isBefore(previousMonthTo);
      }).toList();
      final cumulativeCancellations = validCancellations.where((cancellation) {
        final date = _date(cancellation['fecha_anulacion']);
        return date != null && date.isBefore(monthTo);
      }).toList();
      final previousCumulativeCancellations = previousCancellations.where((
        cancellation,
      ) {
        final date = _date(cancellation['fecha_anulacion']);
        return date != null && date.isBefore(previousMonthTo);
      }).toList();
      final cumulativeCancellationIds = cumulativeCancellations
          .map((row) => _text(row['venta_id']))
          .toSet();
      final cumulativeNet =
          cumulativeSales.length - cumulativeCancellationIds.length;
      final previousCumulativeNet =
          previousCumulativeSales.length -
          previousCumulativeCancellations.length;
      final cumulativeDeathsCancellations = cumulativeCancellations.where((
        row,
      ) {
        final sale = salesById[_text(row['venta_id'])];
        return sale != null && deaths(sale);
      }).toList();
      final cumulativeReceipts = receipts.where((receipt) {
        final date = _date(receipt['fecha']);
        return date != null && date.isBefore(monthTo);
      }).toList();
      final cumulativePendingReceipts = cumulativeReceipts.where((receipt) {
        final status =
            '${_text(receipt['estado_recibo'])} ${_text(receipt['estado'])}'
                .toLowerCase();
        return status.contains('pendiente');
      }).length;
      final cumulativeCandidates = candidates.where((candidate) {
        final date = _date(candidate['fecha_asignacion']);
        return date != null && date.isBefore(monthTo);
      }).toList();
      final cumulativeDeathReversals = cumulativeDeathsCancellations.fold(
        0.0,
        (sum, row) => sum + _value(row['prima_extornada']),
      );

      final actuals = <String, double>{
        'incremento_prima_sin_vehiculos':
            premium(currentSales, withoutVehicles: true) -
            premium(previousSales, withoutVehicles: true),
        'incremento_asegurados': insured(currentSales) - insured(previousSales),
        'incremento_ventas_netas': (currentNet - previousNet).toDouble(),
        'porcentaje_pendiente': receipts.isEmpty
            ? 0
            : pendingReceipts / receipts.length * 100,
        'anulaciones_decesos': deathsCancellations.length.toDouble(),
        'anulaciones_resto':
            (validCancellations.length - deathsCancellations.length).toDouble(),
        'ventas_netas': currentNet.toDouble(),
        'facturacion': premium(currentSales),
        'captacion': candidates.length.toDouble(),
        'liquido_decesos':
            premium(currentSales, onlyDeaths: true) - deathReversals,
      };
      final monthlyActuals = <String, double>{
        'incremento_prima_sin_vehiculos':
            premium(currentMonthSales, withoutVehicles: true) -
            premium(previousMonthSales, withoutVehicles: true),
        'incremento_asegurados':
            insured(currentMonthSales) - insured(previousMonthSales),
        'incremento_ventas_netas': (monthNet - previousMonthNet).toDouble(),
        'porcentaje_pendiente': monthReceipts.isEmpty
            ? 0
            : monthPendingReceipts / monthReceipts.length * 100,
        'anulaciones_decesos': monthDeathsCancellations.length.toDouble(),
        'anulaciones_resto':
            (monthCancellations.length - monthDeathsCancellations.length)
                .toDouble(),
        'ventas_netas': monthNet.toDouble(),
        'facturacion': premium(currentMonthSales),
        'captacion': monthCandidates.length.toDouble(),
        'liquido_decesos':
            premium(currentMonthSales, onlyDeaths: true) - monthDeathReversals,
      };
      final cumulativeActuals = <String, double>{
        'incremento_prima_sin_vehiculos':
            premium(cumulativeSales, withoutVehicles: true) -
            premium(previousCumulativeSales, withoutVehicles: true),
        'incremento_asegurados':
            insured(cumulativeSales) - insured(previousCumulativeSales),
        'incremento_ventas_netas': (cumulativeNet - previousCumulativeNet)
            .toDouble(),
        'porcentaje_pendiente': cumulativeReceipts.isEmpty
            ? 0
            : cumulativePendingReceipts / cumulativeReceipts.length * 100,
        'anulaciones_decesos': cumulativeDeathsCancellations.length.toDouble(),
        'anulaciones_resto':
            (cumulativeCancellations.length -
                    cumulativeDeathsCancellations.length)
                .toDouble(),
        'ventas_netas': cumulativeNet.toDouble(),
        'facturacion': premium(cumulativeSales),
        'captacion': cumulativeCandidates.length.toDouble(),
        'liquido_decesos':
            premium(cumulativeSales, onlyDeaths: true) -
            cumulativeDeathReversals,
      };
      if (!mounted) return;
      setState(() {
        _actuals = actuals;
        _monthlyActuals = monthlyActuals;
        _cumulativeActuals = cumulativeActuals;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _selectedGoal {
    final authId = _text(_selectedFigure?['auth_id']);
    for (final goal in _goals) {
      if (_text(goal['usuario_auth_id']) == authId) return goal;
    }
    return null;
  }

  Future<void> _changeYear(int delta) async {
    setState(() => _year += delta);
    await _loadBase();
  }

  Future<void> _changeMonth(int month) async {
    setState(() {
      _month = month;
      _loading = true;
    });
    await _calculateActuals();
  }

  Future<void> _selectFigure(Map<String, dynamic> figure) async {
    setState(() {
      _selectedFigure = figure;
      _loading = true;
    });
    await _calculateActuals();
  }

  Future<void> _editGoal(Map<String, dynamic> figure) async {
    final existing = _goals.cast<Map<String, dynamic>?>().firstWhere(
      (goal) => _text(goal?['usuario_auth_id']) == _text(figure['auth_id']),
      orElse: () => null,
    );
    final controllers = {
      for (final definition in _definitions)
        definition.keyName: TextEditingController(
          text: _value(
            existing?[definition.keyName],
          ).toStringAsFixed(definition.unit == _MetricUnit.currency ? 2 : 0),
        ),
    };
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Objetivos $_year · ${_fullName(figure)}'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _definitions.map((definition) {
                return SizedBox(
                  width: 310,
                  child: TextField(
                    controller: controllers[definition.keyName],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: definition.title,
                      helperText: definition.inverse
                          ? 'Objetivo máximo permitido'
                          : 'Objetivo mínimo a alcanzar',
                      suffixText: definition.unit == _MetricUnit.currency
                          ? '€'
                          : definition.unit == _MetricUnit.percentage
                          ? '%'
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.save_rounded),
            label: const Text('Guardar objetivos'),
          ),
        ],
      ),
    );
    if (save != true) return;
    final user = _supabase.auth.currentUser;
    await _supabase.from('objetivos_comerciales_anuales').upsert({
      'anio': _year,
      'usuario_auth_id': figure['auth_id'],
      'usuario_nombre': _fullName(figure),
      'usuario_rol': figure['rol_usuario'],
      for (final definition in _definitions)
        definition.keyName:
            double.tryParse(
              controllers[definition.keyName]!.text.replaceAll(',', '.'),
            ) ??
            0,
      'creado_por': user?.id,
      'actualizado_por': user?.id,
    }, onConflict: 'anio,usuario_auth_id');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan anual guardado correctamente.')),
      );
    }
    await _loadBase();
  }

  String _fullName(Map<String, dynamic> user) {
    final name = '${_text(user['nombre'])} ${_text(user['apellidos'])}'.trim();
    return name.isEmpty ? 'Usuario sin nombre' : name;
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'director_zona':
        return 'Director de zona';
      case 'director_nacional':
        return 'Director nacional';
      default:
        return role;
    }
  }

  String _formatValue(double value, _MetricUnit unit) {
    switch (unit) {
      case _MetricUnit.currency:
        return _currency.format(value);
      case _MetricUnit.percentage:
        return '${value.toStringAsFixed(2)} %';
      case _MetricUnit.number:
        return _number.format(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_authorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plan Comercial Anual')),
        body: const Center(
          child: Text('Esta pantalla está reservada a figuras de liderazgo.'),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF2F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071A2D),
        foregroundColor: Colors.white,
        title: const Text(
          'Plan Comercial Anual',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        bottom: _isNationalDirector
            ? TabBar(
                controller: _tabs,
                indicatorColor: const Color(0xFF35D0BA),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.dashboard_rounded),
                    text: 'Objetivos & Performance',
                  ),
                  Tab(icon: Icon(Icons.tune_rounded), text: 'Fijar objetivos'),
                ],
              )
            : null,
      ),
      body: _isNationalDirector
          ? TabBarView(
              controller: _tabs,
              children: [_performance(), _configuration()],
            )
          : _performance(),
    );
  }

  Widget _performance() {
    if (_error != null) return _errorView();
    final figure = _selectedFigure ?? _profile!;
    final goal = _selectedGoal;
    final visibleDefinitions = _visibleDefinitions;
    return RefreshIndicator(
      onRefresh: _loadBase,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _hero(figure),
          const SizedBox(height: 14),
          _yearAndFigureSelector(),
          if (_loading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          _executiveSummary(goal),
          const SizedBox(height: 16),
          if (goal == null)
            _withoutGoal(figure)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 1250
                    ? 3
                    : width >= 760
                    ? 2
                    : 1;
                final cardWidth = (width - ((columns - 1) * 14)) / columns;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: visibleDefinitions.map((definition) {
                    return SizedBox(
                      width: cardWidth,
                      child: _metricCard(
                        definition,
                        _cumulativeActuals[definition.keyName] ?? 0,
                        _cumulativeTarget(
                          definition,
                          _value(goal[definition.keyName]),
                        ),
                        _monthlyActuals[definition.keyName] ?? 0,
                        _monthlyTarget(
                          definition,
                          _value(goal[definition.keyName]),
                        ),
                        _actuals[definition.keyName] ?? 0,
                        _value(goal[definition.keyName]),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          const SizedBox(height: 18),
          const InformesProgramadosPanel(),
          const SizedBox(height: 18),
          _methodology(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _hero(Map<String, dynamic> figure) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF071A2D), Color(0xFF123E5A)],
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.track_changes_rounded,
            color: Color(0xFF5EEAD4),
            size: 34,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Objetivos & Performance $_year',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_fullName(figure)} · ${_roleLabel(_text(figure['rol_usuario']))}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                'Periodo corporativo: 1 de enero a 31 de diciembre',
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _yearAndFigureSelector() => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            onPressed: () => _changeYear(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text(
            'Ejercicio $_year',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          IconButton(
            onPressed: () => _changeYear(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          SizedBox(
            width: 175,
            child: DropdownButtonFormField<int>(
              initialValue: _month,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Mes analizado',
                border: OutlineInputBorder(),
              ),
              items: List.generate(12, (index) {
                final month = index + 1;
                return DropdownMenuItem(
                  value: month,
                  child: Text(
                    _monthName(month),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
              onChanged: (month) {
                if (month != null) _changeMonth(month);
              },
            ),
          ),
          if (_canAnalyzeLeadershipStructure)
            SizedBox(
              width: 310,
              child: DropdownButtonFormField<String>(
                initialValue: _text(_selectedFigure?['auth_id']),
                isExpanded: true,
                menuMaxHeight: 420,
                decoration: const InputDecoration(
                  labelText: 'Figura analizada',
                  border: OutlineInputBorder(),
                ),
                items: _selectableLeadershipFigures
                    .map(
                      (user) => DropdownMenuItem(
                        value: _text(user['auth_id']),
                        child: Text(
                          '${_fullName(user)} · ${_roleLabel(_text(user['rol_usuario']))}',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                selectedItemBuilder: (context) {
                  return _selectableLeadershipFigures.map((user) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_fullName(user)} · '
                        '${_roleLabel(_text(user['rol_usuario']))}',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList();
                },
                onChanged: (authId) {
                  if (authId == null) return;
                  final figure = _selectableLeadershipFigures.firstWhere(
                    (user) => _text(user['auth_id']) == authId,
                  );
                  _selectFigure(figure);
                },
              ),
            ),
        ],
      ),
    ),
  );

  List<Map<String, dynamic>> get _leadershipFigures {
    final figures =
        _users
            .where((user) => _allowedRoles.contains(_text(user['rol_usuario'])))
            .toList()
          ..sort((a, b) => _fullName(a).compareTo(_fullName(b)));
    return figures;
  }

  List<Map<String, dynamic>> get _selectableLeadershipFigures {
    if (_isNationalDirector) return _leadershipFigures;
    final profile = _profile;
    if (profile == null) return const [];
    final figures =
        _structureOf(profile)
            .where((user) => _allowedRoles.contains(_text(user['rol_usuario'])))
            .toList()
          ..sort((a, b) => _fullName(a).compareTo(_fullName(b)));
    return figures;
  }

  Widget _executiveSummary(Map<String, dynamic>? goal) {
    final visibleDefinitions = _visibleDefinitions;
    final configured = goal == null
        ? 0
        : visibleDefinitions
              .where((definition) => _value(goal[definition.keyName]) > 0)
              .length;
    final monthlyAchieved = goal == null
        ? 0
        : visibleDefinitions.where((definition) {
            final target = _monthlyTarget(
              definition,
              _value(goal[definition.keyName]),
            );
            final actual = _monthlyActuals[definition.keyName] ?? 0;
            if (target <= 0) return false;
            return definition.inverse ? actual <= target : actual >= target;
          }).length;
    final cumulativeAchieved = goal == null
        ? 0
        : visibleDefinitions.where((definition) {
            final target = _cumulativeTarget(
              definition,
              _value(goal[definition.keyName]),
            );
            final actual = _cumulativeActuals[definition.keyName] ?? 0;
            if (target <= 0) return false;
            return definition.inverse ? actual <= target : actual >= target;
          }).length;
    final elapsed = DateTime.now().year == _year
        ? DateTime.now().difference(DateTime(_year, 1, 1)).inDays /
              DateTime(_year + 1, 1, 1).difference(DateTime(_year, 1, 1)).inDays
        : DateTime.now().year > _year
        ? 1.0
        : 0.0;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _summaryCard(
          'Cumplidos acumulados',
          '$cumulativeAchieved / $configured',
          Icons.stacked_line_chart_rounded,
          const Color(0xFF0F766E),
        ),
        _summaryCard(
          'Cumplidos en ${_monthName(_month)}',
          '$monthlyAchieved / $configured',
          Icons.verified_rounded,
          const Color(0xFF059669),
        ),
        _summaryCard(
          'Avance del ejercicio',
          '${(elapsed * 100).clamp(0, 100).toStringAsFixed(1)} %',
          Icons.calendar_month_rounded,
          const Color(0xFF2563EB),
        ),
        _summaryCard(
          'Estructura incluida',
          '${_structureOf(_selectedFigure ?? _profile!).length} personas',
          Icons.account_tree_rounded,
          const Color(0xFF7C3AED),
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) =>
      SizedBox(
        width: 265,
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 19,
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

  String _monthName(int month) {
    const names = [
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
    return names[month.clamp(1, 12) - 1];
  }

  Widget _metricCard(
    _MetricDefinition definition,
    double cumulativeActual,
    double cumulativeTarget,
    double monthlyActual,
    double monthlyTarget,
    double annualActual,
    double annualTarget,
  ) {
    final rawProgress = cumulativeTarget <= 0
        ? 0.0
        : definition.inverse
        ? (cumulativeActual <= cumulativeTarget
              ? 1.0
              : cumulativeTarget / cumulativeActual)
        : cumulativeActual / cumulativeTarget;
    final progress = rawProgress.clamp(0.0, 1.0);
    final deviation = definition.inverse
        ? cumulativeTarget - cumulativeActual
        : cumulativeActual - cumulativeTarget;
    final remaining = (cumulativeTarget - cumulativeActual)
        .clamp(0, double.infinity)
        .toDouble();
    final achieved =
        cumulativeTarget > 0 &&
        (definition.inverse
            ? cumulativeActual <= cumulativeTarget
            : cumulativeActual >= cumulativeTarget);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: definition.color.withValues(alpha: .12),
                  foregroundColor: definition.color,
                  child: Icon(definition.icon),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        definition.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        definition.subtitle,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CustomPaint(
                    painter: _ProgressRingPainter(
                      progress: progress,
                      color: achieved
                          ? const Color(0xFF059669)
                          : definition.color,
                    ),
                    child: Center(
                      child: Text(
                        '${(rawProgress * 100).clamp(0, 999).toStringAsFixed(0)}%',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _smallValue(
                    'Acumulado a ${_monthName(_month)}',
                    _formatValue(cumulativeActual, definition.unit),
                  ),
                ),
                Expanded(
                  child: _smallValue(
                    'Objetivo acumulado',
                    _formatValue(cumulativeTarget, definition.unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(20),
              color: achieved ? const Color(0xFF059669) : definition.color,
              backgroundColor: definition.color.withValues(alpha: .10),
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: Text(
                    achieved
                        ? definition.inverse
                              ? 'Dentro del límite · margen: '
                                    '${_formatValue(remaining, definition.unit)}'
                              : 'Objetivo acumulado alcanzado'
                        : definition.inverse
                        ? 'Exceso: '
                              '${_formatValue(cumulativeActual - cumulativeTarget, definition.unit)}'
                        : 'Falta: ${_formatValue(remaining, definition.unit)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: achieved
                          ? const Color(0xFF047857)
                          : Colors.black87,
                    ),
                  ),
                ),
                Text(
                  'Desv. ${deviation >= 0 ? '+' : ''}'
                  '${_formatValue(deviation, definition.unit)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: deviation >= 0
                        ? const Color(0xFF047857)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_monthName(_month)}: '
                    '${_formatValue(monthlyActual, definition.unit)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Objetivo mensual: '
                    '${_formatValue(monthlyTarget, definition.unit)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Registrado en $_year: '
                    '${_formatValue(annualActual, definition.unit)}',
                    style: const TextStyle(color: Colors.black45, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Meta anual: ${_formatValue(annualTarget, definition.unit)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.black45, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _monthlyTarget(_MetricDefinition definition, double annualTarget) {
    if (definition.unit == _MetricUnit.percentage) return annualTarget;
    return annualTarget / 12;
  }

  double _cumulativeTarget(_MetricDefinition definition, double annualTarget) {
    if (definition.unit == _MetricUnit.percentage) return annualTarget;
    return annualTarget / 12 * _month;
  }

  Widget _smallValue(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.black45)),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
    ],
  );

  Widget _withoutGoal(Map<String, dynamic> figure) => Card(
    elevation: 0,
    color: const Color(0xFFFFF7E8),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.flag_outlined, size: 42, color: Color(0xFFD97706)),
          const SizedBox(height: 10),
          Text(
            'Todavía no existe un plan comercial para $_year.',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          if (_isNationalDirector) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _editGoal(figure),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Fijar objetivos ahora'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _configuration() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      _hero(_profile!),
      const SizedBox(height: 14),
      _yearAndFigureSelector(),
      const SizedBox(height: 14),
      Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Planes asignados a las figuras',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              const Text(
                'Los objetivos son individuales para cada figura, pero su '
                'resultado incluye toda la estructura que depende de ella.',
              ),
              const SizedBox(height: 14),
              ..._leadershipFigures.map((figure) {
                final configured = _goals.any(
                  (goal) =>
                      _text(goal['usuario_auth_id']) ==
                      _text(figure['auth_id']),
                );
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: configured
                        ? const Color(0xFFE8F7F0)
                        : const Color(0xFFFFF4E5),
                    foregroundColor: configured
                        ? const Color(0xFF059669)
                        : const Color(0xFFD97706),
                    child: Icon(
                      configured ? Icons.verified_rounded : Icons.flag_outlined,
                    ),
                  ),
                  title: Text(
                    _fullName(figure),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${_roleLabel(_text(figure['rol_usuario']))} · '
                    '${configured ? 'Plan configurado' : 'Pendiente'}',
                  ),
                  trailing: FilledButton.tonalIcon(
                    onPressed: () => _editGoal(figure),
                    icon: Icon(
                      configured ? Icons.edit_rounded : Icons.add_rounded,
                    ),
                    label: Text(configured ? 'Editar' : 'Configurar'),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _methodology() => ExpansionTile(
    title: const Text(
      'Criterios de cálculo',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
    children: const [
      Text(
        'Incrementos: comparan el ejercicio seleccionado con el ejercicio '
        'anterior. Ventas netas: ventas menos anulaciones. Facturación: '
        'suma de prima anual neta. Líquido decesos: prima neta de decesos '
        'menos prima extornada. Pendiente: recibos pendientes sobre el '
        'total acumulado. El objetivo anual se divide entre 12 meses y se '
        'acumula hasta el mes seleccionado; los objetivos porcentuales '
        'mantienen su porcentaje. También se muestra por separado el '
        'resultado exclusivo del mes. Las métricas de una figura incluyen '
        'sus subordinados.',
      ),
    ],
  );

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
          FilledButton(onPressed: _loadBase, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

enum _MetricUnit { currency, percentage, number }

class _MetricDefinition {
  final String keyName;
  final String title;
  final String subtitle;
  final _MetricUnit unit;
  final bool inverse;
  final IconData icon;
  final Color color;

  const _MetricDefinition({
    required this.keyName,
    required this.title,
    required this.subtitle,
    required this.unit,
    required this.icon,
    required this.color,
    this.inverse = false,
  });
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _ProgressRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 9) / 2;
    final background = Paint()
      ..color = color.withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    final foreground = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7;
    canvas.drawCircle(center, radius, background);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.2832 * progress.clamp(0, 1),
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
