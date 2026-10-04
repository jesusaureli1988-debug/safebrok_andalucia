import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/payroll/role_compensation.dart';
import 'package:intl/intl.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommissionSimulatorScreen extends StatefulWidget {
  final String role;

  const CommissionSimulatorScreen({super.key, required this.role});

  @override
  State<CommissionSimulatorScreen> createState() =>
      _CommissionSimulatorScreenState();
}

class _CommissionSimulatorScreenState extends State<CommissionSimulatorScreen> {
  final _db = Supabase.instance.client;
  final _money = NumberFormat.currency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: 2,
  );
  final _ownPremium = TextEditingController(text: '4000');
  final _teamPremium = TextEditingController(text: '0');
  final _mix = TextEditingController(text: '30');
  final _quickCommissionRate = TextEditingController(text: '15');
  final _targetNet = TextEditingController(text: '2500');
  final _targetMix = TextEditingController(text: '30');

  bool _loading = true;
  String? _error;
  int _mode = 0;
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _companyRates = [];
  List<Map<String, dynamic>> _invoices = [];
  String? _selectedAuthId;
  double _irpf = 15;
  double _fixed = 0;
  final List<_SimulatedSale> _sales = [];

  static const _companies = [
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

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _ownPremium,
      _teamPremium,
      _mix,
      _quickCommissionRate,
      _targetNet,
      _targetMix,
    ]) {
      controller.addListener(_refresh);
    }
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _ownPremium,
      _teamPremium,
      _mix,
      _quickCommissionRate,
      _targetNet,
      _targetMix,
    ]) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';
  double _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(_text(value).replaceAll(',', '.')) ?? 0;
  String _role(dynamic value) => _text(value)
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  String _roleLabel(dynamic value) {
    switch (_role(value)) {
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

  String _name(Map<String, dynamic> user) {
    final name = '${_text(user['nombre'])} ${_text(user['apellidos'])}'.trim();
    return name.isEmpty ? _text(user['email']) : name;
  }

  Future<List<Map<String, dynamic>>> _safeRows(String table) async {
    try {
      final result = await _db.from(table).select();
      return (result as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (error) {
      debugPrint('SIMULADOR · $table: $error');
      return [];
    }
  }

  Future<void> _load() async {
    final auth = _db.auth.currentUser;
    if (auth == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait<dynamic>([
        _db
            .from('usuarios')
            .select(
              'id,auth_id,parent_id,nombre,apellidos,email,rol_usuario,estado',
            )
            .eq('auth_id', auth.id)
            .maybeSingle(),
        _db
            .from('usuarios')
            .select(
              'id,auth_id,parent_id,nombre,apellidos,email,rol_usuario,estado',
            ),
        _safeRows('comisiones_productos'),
        _safeRows('comisiones_producto_compania'),
        _safeRows('nominas_facturas'),
      ]);
      if (data[0] == null) throw Exception('No se ha encontrado tu perfil.');
      _me = Map<String, dynamic>.from(data[0] as Map);
      final allUsers = (data[1] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .where((user) {
            final state = _text(user['estado']).toLowerCase();
            return !{
              'inactivo',
              'baja',
              'desactivado',
              'bloqueado',
              'suspendido',
            }.contains(state);
          })
          .toList();
      _users = _selectableUsers(allUsers);
      _products = data[2] as List<Map<String, dynamic>>;
      _companyRates = data[3] as List<Map<String, dynamic>>;
      _invoices = data[4] as List<Map<String, dynamic>>;
      _selectedAuthId = auth.id;
      _applyEconomicSettings();
      if (_products.isNotEmpty && _sales.isEmpty) {
        _sales.add(
          _SimulatedSale(
            product: _text(_products.first['producto']),
            company: _companies.first,
            quantity: 1,
            grossPremium: 1000,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> _selectableUsers(List<Map<String, dynamic>> all) {
    final role = _role(_me?['rol_usuario'] ?? widget.role);
    if (role == 'administracion' || role == 'director_nacional') return all;
    return all
        .where((user) => _text(user['auth_id']) == _text(_me?['auth_id']))
        .toList();
  }

  Map<String, dynamic> get _selectedUser {
    for (final user in _users) {
      if (_text(user['auth_id']) == _selectedAuthId) return user;
    }
    return _me!;
  }

  String get _selectedRole => _role(_selectedUser['rol_usuario']);
  bool get _canSelectUser => {
    'administracion',
    'director_nacional',
  }.contains(_role(_me?['rol_usuario'] ?? widget.role));
  bool get _hasTeam => !{'agente', 'administracion'}.contains(_selectedRole);

  void _applyEconomicSettings() {
    final authId = _selectedAuthId;
    final mine = _invoices
        .where((invoice) => _text(invoice['usuario_auth_id']) == authId)
        .toList();
    mine.sort((a, b) {
      final aKey =
          (int.tryParse(_text(a['anio'])) ?? 0) * 100 +
          (int.tryParse(_text(a['mes'])) ?? 0);
      final bKey =
          (int.tryParse(_text(b['anio'])) ?? 0) * 100 +
          (int.tryParse(_text(b['mes'])) ?? 0);
      return bKey.compareTo(aKey);
    });
    _irpf = mine.isEmpty || _number(mine.first['irpf_porcentaje']) <= 0
        ? 15
        : _number(mine.first['irpf_porcentaje']).clamp(0, 100);
    _fixed = mine.isEmpty ? 0 : _number(mine.first['fijo']);
  }

  Map<String, dynamic>? _productConfig(String product) {
    for (final config in _products) {
      if (_text(config['producto']).toLowerCase() == product.toLowerCase())
        return config;
    }
    return null;
  }

  double _commissionRate(String product, String company) {
    for (final row in _companyRates) {
      if (_text(row['producto']).toLowerCase() == product.toLowerCase() &&
          _text(row['compania']).toLowerCase() == company.toLowerCase()) {
        return _number(row['porcentaje_comision']).clamp(0, 100);
      }
    }
    return _number(
      _productConfig(product)?['porcentaje_comision'],
    ).clamp(0, 100);
  }

  double _taxRate(String product) =>
      _number(_productConfig(product)?['porcentaje_impuestos']).clamp(0, 100);
  bool _isLife(String product) {
    final value = product.toLowerCase();
    return value.contains('vida') ||
        value.contains('decesos') ||
        value.contains('prima unica') ||
        value.contains('prima única');
  }

  double _computablePremium(String product, double netPremium) =>
      PremiumWeighting.net({
        'producto': product,
        'prima_anual_neta': netPremium,
        'fecha_efecto': DateTime.now().toIso8601String(),
      });
  _SimulationResult get _result {
    if (_mode == 0) {
      final own = math.max(0.0, _number(_ownPremium.text));
      final team = _hasTeam ? math.max(0.0, _number(_teamPremium.text)) : 0.0;
      final mix = _number(_mix.text).clamp(0.0, 100.0).toDouble();
      final commissions =
          own *
          (_number(_quickCommissionRate.text).clamp(0.0, 100.0).toDouble() /
              100);
      return _calculate(
        ownPremium: own,
        teamPremium: team,
        lifePremium: (own + team) * mix / 100,
        commissions: commissions,
      );
    }
    if (_mode == 1) {
      double own = 0;
      double life = 0;
      double commissions = 0;
      for (final sale in _sales) {
        final gross = sale.grossPremium * sale.quantity;
        final net = gross * (1 - _taxRate(sale.product) / 100);
        final computable = _computablePremium(sale.product, net);
        own += computable;
        if (_isLife(sale.product)) life += computable;
        commissions += net * _commissionRate(sale.product, sale.company) / 100;
      }
      final team = _hasTeam ? math.max(0.0, _number(_teamPremium.text)) : 0.0;
      return _calculate(
        ownPremium: own,
        teamPremium: team,
        lifePremium: life,
        commissions: commissions,
      );
    }
    return _targetResult;
  }

  _SimulationResult _calculate({
    required double ownPremium,
    required double teamPremium,
    required double lifePremium,
    required double commissions,
  }) {
    final structurePremium = ownPremium + teamPremium;
    final mix = structurePremium <= 0
        ? 0.0
        : lifePremium / structurePremium * 100;
    final compensation = RoleCompensationRules.calculate(
      role: _selectedRole,
      premiums: structurePremium,
      deathAndLifePremiums: lifePremium,
    );
    final rappel = compensation.total;
    final grossSalary = commissions + rappel + _fixed;
    final withholding = grossSalary * _irpf / 100;
    return _SimulationResult(
      ownPremium: ownPremium,
      teamPremium: teamPremium,
      lifePremium: lifePremium,
      mix: mix,
      commissions: commissions,
      rappel: rappel,
      baseRappel: compensation.rappel,
      variable: compensation.variable,
      fixed: _fixed,
      irpf: _irpf,
      withholding: withholding,
      grossSalary: grossSalary,
      netSalary: grossSalary - withholding,
      nextStep: _nextStep(_selectedRole, structurePremium, lifePremium),
    );
  }

  String _nextStep(String role, double premium, double lifePremium) {
    if (role == 'director_nacional' || role == 'director_regional')
      return 'Cada 1.000 € adicionales aportan aproximadamente 50 € más de variable.';
    if (role == 'director_zona' && premium >= 15500)
      return 'Cada 1.000 € adicionales aportan 100 € más de diferencial.';
    final thresholds = role == 'director_zona'
        ? [15500.0]
        : role == 'jefe_ventas'
        ? [6500.0]
        : role == 'jefe_equipo'
        ? [4000.0]
        : [1500.0, 2500, 4000, 6000, 9000, 12000];
    final next = thresholds
        .where((value) => value > premium)
        .cast<double?>()
        .firstOrNull;
    if (role == 'agente') {
      final mix = premium <= 0 ? 0 : lifePremium / premium * 100;
      if (mix < 30 && premium >= 4000)
        return 'El siguiente incentivo requiere alcanzar al menos un 30% de mix Decesos + Vida.';
      if (premium >= 1500 && premium < 4000 && mix < 99.999)
        return 'Los primeros tramos requieren producción íntegra en Decesos + Vida.';
    }
    if (next == null)
      return 'Ya estás en el tramo superior; sigue aumentando producción para mejorar el resultado.';
    return 'Te faltan ${_money.format(next - premium)} de producción para el siguiente tramo.';
  }

  _SimulationResult get _targetResult {
    final target = math.max(0.0, _number(_targetNet.text));
    final mix = _number(_targetMix.text).clamp(0.0, 100.0).toDouble();
    final averageRate = _products.isEmpty
        ? 15.0
        : _products.fold<double>(
                0,
                (sum, item) => sum + _number(item['porcentaje_comision']),
              ) /
              _products.length;
    double low = 0;
    double high = 1000000;
    _SimulationResult result = _calculate(
      ownPremium: 0,
      teamPremium: 0,
      lifePremium: 0,
      commissions: 0,
    );
    for (var i = 0; i < 60; i++) {
      final premium = (low + high) / 2;
      result = _calculate(
        ownPremium: premium,
        teamPremium: 0,
        lifePremium: premium * mix / 100,
        commissions: premium * averageRate / 100,
      );
      if (result.netSalary < target) {
        low = premium;
      } else {
        high = premium;
      }
    }
    return _calculate(
      ownPremium: high,
      teamPremium: 0,
      lifePremium: high * mix / 100,
      commissions: high * averageRate / 100,
    );
  }

  String get _conditionDescription =>
      RoleCompensationRules.conditionForRole(_selectedRole);

  BoxDecoration _card({bool strong = false}) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: const Color(0xFFE1E5EA)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF14213D).withValues(alpha: strong ? .13 : .07),
        blurRadius: strong ? 28 : 18,
        offset: Offset(0, strong ? 12 : 7),
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
            : LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  return ListView(
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
                      _userAndMode(),
                      const SizedBox(height: 18),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: _inputs()),
                            const SizedBox(width: 18),
                            Expanded(flex: 4, child: _results()),
                          ],
                        )
                      else ...[
                        _inputs(),
                        const SizedBox(height: 18),
                        _results(),
                      ],
                      const SizedBox(height: 18),
                      _disclaimer(),
                    ],
                  );
                },
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
          'Simulador de comisiones',
          style: TextStyle(
            color: Color(0xFF111C31),
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Reiniciar',
        onPressed: _reset,
        icon: const Icon(Icons.restart_alt_rounded, color: Color(0xFF111C31)),
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
        final compact = box.maxWidth < 650;
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
                'PROYECCIÓN ECONÓMICA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                ),
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Convierte producción\nen ingresos.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Simula ventas y descubre cuánto cobrarías antes de producirlas.',
              style: TextStyle(
                color: Color(0xFFDDE6FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
        final result = _result;
        final amount = Column(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            const Text(
              'NETO ESTIMADO',
              style: TextStyle(
                color: Color(0xFFDDE6FF),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: .7,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                _money.format(result.netSalary),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_roleLabel(_selectedRole)} · IRPF ${_irpf.toStringAsFixed(0)}%',
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
            children: [copy, const SizedBox(height: 24), amount],
          );
        return Row(
          children: [
            Expanded(child: copy),
            const SizedBox(width: 24),
            amount,
          ],
        );
      },
    ),
  );

  Widget _userAndMode() => Container(
    padding: const EdgeInsets.all(18),
    decoration: _card(),
    child: Column(
      children: [
        if (_canSelectUser) ...[
          DropdownButtonFormField<String>(
            initialValue: _selectedAuthId,
            isExpanded: true,
            decoration: _inputDecoration(
              'Simular condiciones de',
              Icons.person_search_rounded,
            ),
            items: _users
                .map(
                  (user) => DropdownMenuItem(
                    value: _text(user['auth_id']),
                    child: Text(
                      '${_name(user)} · ${_roleLabel(user['rol_usuario'])}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedAuthId = value;
                _applyEconomicSettings();
              });
            },
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(child: _modeButton(0, Icons.speed_rounded, 'Rápida')),
            const SizedBox(width: 8),
            Expanded(
              child: _modeButton(
                1,
                Icons.playlist_add_check_circle_rounded,
                'Detallada',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _modeButton(2, Icons.flag_rounded, 'Objetivo')),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDDE5F5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF2454D3),
                size: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _conditionDescription,
                  style: const TextStyle(
                    color: Color(0xFF43516A),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _modeButton(int value, IconData icon, String label) {
    final selected = _mode == value;
    return Material(
      color: selected ? const Color(0xFF14213D) : const Color(0xFFF3F5F8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _mode = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFF526078),
                size: 21,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF344158),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF2454D3)),
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE1E5EA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE1E5EA)),
        ),
      );

  Widget _inputs() {
    if (_mode == 1) return _detailedInputs();
    if (_mode == 2) return _targetInputs();
    return _quickInputs();
  }

  Widget _inputCard(
    String title,
    String subtitle,
    IconData icon,
    List<Widget> children,
  ) => Container(
    padding: const EdgeInsets.all(22),
    decoration: _card(strong: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(icon, title, subtitle),
        const SizedBox(height: 22),
        ...children,
      ],
    ),
  );

  Widget _numberField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? suffix,
  }) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: _inputDecoration(label, icon).copyWith(suffixText: suffix),
  );
  Widget _quickInputs() => _inputCard(
    'Simulación rápida',
    'Introduce cifras globales para obtener una estimación inmediata',
    Icons.speed_rounded,
    [
      _numberField(
        _ownPremium,
        'Primas propias computables',
        Icons.euro_rounded,
        suffix: '€',
      ),
      if (_hasTeam) ...[
        const SizedBox(height: 12),
        _numberField(
          _teamPremium,
          'Primas adicionales del equipo',
          Icons.groups_rounded,
          suffix: '€',
        ),
      ],
      const SizedBox(height: 12),
      _numberField(
        _mix,
        'Mix Decesos + Vida',
        Icons.pie_chart_rounded,
        suffix: '%',
      ),
      const SizedBox(height: 12),
      _numberField(
        _quickCommissionRate,
        'Comisión media estimada',
        Icons.percent_rounded,
        suffix: '%',
      ),
      const SizedBox(height: 14),
      const Text(
        'Para un cálculo exacto por producto y compañía utiliza el modo Detallada.',
        style: TextStyle(
          color: Color(0xFF778195),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _detailedInputs() => _inputCard(
    'Ventas simuladas',
    'Añade productos sin registrar ventas reales',
    Icons.playlist_add_check_circle_rounded,
    [
      if (_sales.isEmpty)
        const _SimulatorEmpty(
          message: 'Añade una venta para comenzar la simulación.',
        )
      else
        ..._sales.asMap().entries.map(
          (entry) => _saleTile(entry.key, entry.value),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => _editSale(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Añadir venta simulada'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF2454D3),
          minimumSize: const Size(double.infinity, 50),
          side: const BorderSide(color: Color(0xFFB9C9EE)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      if (_hasTeam) ...[
        const SizedBox(height: 14),
        _numberField(
          _teamPremium,
          'Producción adicional del equipo',
          Icons.groups_rounded,
          suffix: '€',
        ),
      ],
    ],
  );

  Widget _saleTile(int index, _SimulatedSale sale) {
    final gross = sale.grossPremium * sale.quantity;
    final net = gross * (1 - _taxRate(sale.product) / 100);
    final commission = net * _commissionRate(sale.product, sale.company) / 100;
    final computable = _computablePremium(sale.product, net);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E6EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF2454D3)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${sale.quantity} × ${sale.product}',
                  style: const TextStyle(
                    color: Color(0xFF111C31),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${sale.company} · Prima ${_money.format(computable)} · Comisión ${_money.format(commission)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF69758A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: () => _editSale(index: index),
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF526078)),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: () => setState(() => _sales.removeAt(index)),
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFC84040),
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetInputs() {
    final result = _targetResult;
    return _inputCard(
      'Objetivo de sueldo',
      'SafeBrok calcula la producción aproximada necesaria',
      Icons.flag_rounded,
      [
        _numberField(
          _targetNet,
          'Neto mensual que quieres alcanzar',
          Icons.savings_outlined,
          suffix: '€',
        ),
        const SizedBox(height: 12),
        _numberField(
          _targetMix,
          'Mix previsto de Decesos + Vida',
          Icons.pie_chart_rounded,
          suffix: '%',
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFEAF0FF), Color(0xFFF5F7FF)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD7E1F7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PRODUCCIÓN ORIENTATIVA NECESARIA',
                style: TextStyle(
                  color: Color(0xFF526078),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
              const SizedBox(height: 7),
              FittedBox(
                child: Text(
                  _money.format(result.ownPremium),
                  style: const TextStyle(
                    color: Color(0xFF2454D3),
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Con una comisión media basada en la configuración actual de productos.',
                style: const TextStyle(
                  color: Color(0xFF667187),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _editSale({int? index}) async {
    final existing = index == null ? null : _sales[index];
    String product =
        existing?.product ??
        (_products.isEmpty ? 'Decesos' : _text(_products.first['producto']));
    String company = existing?.company ?? _companies.first;
    final quantity = TextEditingController(text: '${existing?.quantity ?? 1}');
    final premium = TextEditingController(
      text: '${existing?.grossPremium ?? 1000}',
    );
    final saved = await showModalBottomSheet<_SimulatedSale>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD6DBE3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      index == null
                          ? 'Añadir venta simulada'
                          : 'Editar venta simulada',
                      style: const TextStyle(
                        color: Color(0xFF111C31),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: product,
                      isExpanded: true,
                      decoration: _inputDecoration(
                        'Producto',
                        Icons.inventory_2_outlined,
                      ),
                      items: _productNames
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(
                                item,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) modalSetState(() => product = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: company,
                      isExpanded: true,
                      decoration: _inputDecoration(
                        'Compañía',
                        Icons.business_outlined,
                      ),
                      items: _companies
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) modalSetState(() => company = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantity,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(
                        'Número de pólizas',
                        Icons.numbers_rounded,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: premium,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _inputDecoration(
                        'Prima anual bruta por póliza',
                        Icons.euro_rounded,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () {
                        final q = int.tryParse(quantity.text) ?? 0;
                        final p = _number(premium.text);
                        if (q <= 0 || p <= 0) return;
                        Navigator.pop(
                          context,
                          _SimulatedSale(
                            product: product,
                            company: company,
                            quantity: q,
                            grossPremium: p,
                          ),
                        );
                      },
                      icon: const Icon(Icons.calculate_rounded),
                      label: const Text('Aplicar a la simulación'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2454D3),
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    quantity.dispose();
    premium.dispose();
    if (saved == null) return;
    setState(() {
      if (index == null) {
        _sales.add(saved);
      } else {
        _sales[index] = saved;
      }
    });
  }

  List<String> get _productNames {
    final values =
        _products
            .map((item) => _text(item['producto']))
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values.isEmpty ? ['Decesos', 'Hogar', 'Vida', 'Auto'] : values;
  }

  Widget _results() {
    final result = _result;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _card(strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.account_balance_wallet_rounded,
            'Resultado estimado',
            'Desglose económico de la simulación',
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF14213D), Color(0xFF2454D3)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                const Text(
                  'SUELDO NETO ESTIMADO',
                  style: TextStyle(
                    color: Color(0xFFDDE6FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  child: Text(
                    _money.format(result.netSalary),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Bruto ${_money.format(result.grossSalary)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _resultLine(
            'Primas propias computables',
            result.ownPremium,
            const Color(0xFF2454D3),
          ),
          if (_hasTeam)
            _resultLine(
              'Producción adicional equipo',
              result.teamPremium,
              const Color(0xFF3E78C7),
            ),
          _resultLine(
            'Mix Decesos + Vida',
            result.mix,
            const Color(0xFF6F4BD8),
            percent: true,
          ),
          const Divider(height: 26, color: Color(0xFFE5E9EF)),
          _resultLine(
            'Comisiones propias',
            result.commissions,
            const Color(0xFF109A8D),
          ),
          _resultLine('Rappel', result.baseRappel, const Color(0xFFE88A17)),
          _resultLine(
            'Diferencial variable',
            result.variable,
            const Color(0xFF7A55D9),
          ),
          _resultLine('Parte fija', result.fixed, const Color(0xFF3E78C7)),
          _resultLine(
            'Base imponible',
            result.grossSalary,
            const Color(0xFF111C31),
          ),
          _resultLine(
            'Retención IRPF (${result.irpf.toStringAsFixed(0)}%)',
            -result.withholding,
            const Color(0xFFE05252),
          ),
          const Divider(height: 26, color: Color(0xFFE5E9EF)),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'TOTAL NETO',
                  style: TextStyle(
                    color: Color(0xFF111C31),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _money.format(result.netSalary),
                style: const TextStyle(
                  color: Color(0xFF16A36A),
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8EB),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFF3D9A5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFFE88A17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.nextStep,
                    style: const TextStyle(
                      color: Color(0xFF66502C),
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultLine(
    String label,
    double value,
    Color color, {
    bool percent = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
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
          percent ? '${value.toStringAsFixed(1)}%' : _money.format(value),
          style: TextStyle(
            color: value < 0
                ? const Color(0xFFC84040)
                : const Color(0xFF111C31),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(IconData icon, String title, String subtitle) => Row(
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
                fontSize: 19,
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

  Widget _disclaimer() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFEFF7F6),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFCFE7E3)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, color: Color(0xFF109A8D), size: 21),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Esta simulación es privada y orientativa. No crea ventas, no modifica nóminas ni genera facturas. El resultado definitivo depende de las operaciones validadas, extornos, ajustes y condiciones vigentes al tramitar la factura.',
            style: TextStyle(
              color: Color(0xFF41635E),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  void _reset() {
    setState(() {
      _mode = 0;
      _ownPremium.text = '4000';
      _teamPremium.text = '0';
      _mix.text = '30';
      _quickCommissionRate.text = '15';
      _targetNet.text = '2500';
      _targetMix.text = '30';
      _sales.clear();
      if (_products.isNotEmpty)
        _sales.add(
          _SimulatedSale(
            product: _text(_products.first['producto']),
            company: _companies.first,
            quantity: 1,
            grossPremium: 1000,
          ),
        );
    });
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(28),
        decoration: _card(strong: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calculate_outlined,
              color: Color(0xFF2454D3),
              size: 52,
            ),
            const SizedBox(height: 16),
            const Text(
              'No se pudo abrir el simulador',
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
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SimulatedSale {
  final String product;
  final String company;
  final int quantity;
  final double grossPremium;

  const _SimulatedSale({
    required this.product,
    required this.company,
    required this.quantity,
    required this.grossPremium,
  });
}

class _SimulationResult {
  final double ownPremium;
  final double teamPremium;
  final double lifePremium;
  final double mix;
  final double commissions;
  final double rappel;
  final double baseRappel;
  final double variable;
  final double fixed;
  final double irpf;
  final double withholding;
  final double grossSalary;
  final double netSalary;
  final String nextStep;

  const _SimulationResult({
    required this.ownPremium,
    required this.teamPremium,
    required this.lifePremium,
    required this.mix,
    required this.commissions,
    required this.rappel,
    required this.baseRappel,
    required this.variable,
    required this.fixed,
    required this.irpf,
    required this.withholding,
    required this.grossSalary,
    required this.netSalary,
    required this.nextStep,
  });
}

class _SimulatorEmpty extends StatelessWidget {
  final String message;
  const _SimulatorEmpty({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F7FA),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        const Icon(Icons.add_chart_rounded, color: Color(0xFF9BA5B5), size: 40),
        const SizedBox(height: 9),
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
