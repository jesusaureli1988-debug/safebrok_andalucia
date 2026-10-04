import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompleteHistoryScreen extends StatefulWidget {
  final String role;

  const CompleteHistoryScreen({super.key, required this.role});

  @override
  State<CompleteHistoryScreen> createState() => _CompleteHistoryScreenState();
}

class _CompleteHistoryScreenState extends State<CompleteHistoryScreen> {
  final _db = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: 0,
  );

  bool _loading = true;
  String? _error;
  int _tab = 0;
  String _type = 'todos';
  String _query = '';
  DateTimeRange? _range;
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _cancellations = [];
  List<Map<String, dynamic>> _receipts = [];
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _incorporations = [];
  List<Map<String, dynamic>> _roleChanges = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year - 1, now.month, 1),
      end: now,
    );
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
  DateTime? _date(dynamic value) => value == null
      ? null
      : value is DateTime
      ? value
      : DateTime.tryParse(value.toString());

  Future<List<Map<String, dynamic>>> _safeRows(String table) async {
    try {
      final result = await _db.from(table).select();
      return (result as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (error) {
      debugPrint('HISTÓRICO · $table no disponible: $error');
      return [];
    }
  }

  Future<void> _load({bool loader = true}) async {
    final auth = _db.auth.currentUser;
    if (auth == null) return;
    if (loader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final base = await Future.wait<dynamic>([
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
      ]);
      if (base[0] == null) throw Exception('No se ha encontrado tu perfil.');
      _me = Map<String, dynamic>.from(base[0] as Map);
      final allUsers = (base[1] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      _users = _visibleUsers(allUsers);
      final rows = await Future.wait([
        _safeRows('ventas'),
        _safeRows('anulaciones_polizas'),
        _safeRows('recibos'),
        _safeRows('nominas_facturas'),
        _safeRows('incorporaciones'),
        _safeRows('cambios_rol'),
      ]);
      _sales = _scopeRows(rows[0], const [
        'agente_auth_id',
        'auth_id',
        'usuario_auth_id',
      ]);
      final saleIds = _sales.map((sale) => _text(sale['id'])).toSet();
      _cancellations = rows[1]
          .where((item) => saleIds.contains(_text(item['venta_id'])))
          .toList();
      _receipts = _scopeRows(rows[2], const [
        'agente',
        'agente_auth_id',
        'usuario_auth_id',
        'auth_id',
      ]);
      _invoices = _scopeRows(rows[3], const ['usuario_auth_id', 'auth_id']);
      _incorporations = _scopeIncorporations(rows[4]);
      _roleChanges = _scopeRoleChanges(rows[5]);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> _visibleUsers(List<Map<String, dynamic>> all) {
    final role = _role(_me?['rol_usuario'] ?? widget.role);
    if (role == 'administracion' || role == 'director_nacional') return all;
    final myId = _text(_me?['id']);
    final result = <Map<String, dynamic>>[];
    final pending = <String>{myId};
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final id = pending.first;
      pending.remove(id);
      if (!visited.add(id)) continue;
      for (final user in all) {
        final userId = _text(user['id']);
        if (userId == id || _text(user['parent_id']) == id) {
          if (!result.any((item) => _text(item['id']) == userId))
            result.add(user);
          if (userId != id) pending.add(userId);
        }
      }
    }
    return result;
  }

  Set<String> get _visibleAuthIds => _users
      .map((user) => _text(user['auth_id']))
      .where((id) => id.isNotEmpty)
      .toSet();
  Set<String> get _visibleUserIds => _users
      .map((user) => _text(user['id']))
      .where((id) => id.isNotEmpty)
      .toSet();
  bool get _global => {
    'administracion',
    'director_nacional',
  }.contains(_role(_me?['rol_usuario'] ?? widget.role));

  List<Map<String, dynamic>> _scopeRows(
    List<Map<String, dynamic>> rows,
    List<String> authKeys,
  ) {
    if (_global && _visibleAuthIds.isEmpty) return rows;
    return rows.where((row) {
      for (final key in authKeys) {
        final value = _text(row[key]);
        if (value.isNotEmpty && _visibleAuthIds.contains(value)) return true;
      }
      return false;
    }).toList();
  }

  List<Map<String, dynamic>> _scopeIncorporations(
    List<Map<String, dynamic>> rows,
  ) {
    if (_global) return rows;
    return rows.where((row) {
      final authCandidates = [
        row['solicitante_auth_id'],
        row['usuario_auth_id'],
        row['auth_id'],
      ];
      final idCandidates = [row['responsable_id'], row['usuario_id']];
      return authCandidates.any(
            (value) => _visibleAuthIds.contains(_text(value)),
          ) ||
          idCandidates.any((value) => _visibleUserIds.contains(_text(value)));
    }).toList();
  }

  List<Map<String, dynamic>> _scopeRoleChanges(
    List<Map<String, dynamic>> rows,
  ) {
    if (_global) return rows;
    return rows
        .where(
          (row) =>
              _visibleUserIds.contains(_text(row['usuario_id'])) ||
              _visibleAuthIds.contains(_text(row['usuario_auth_id'])),
        )
        .toList();
  }

  Map<String, dynamic>? _userByAuth(dynamic authId) {
    final id = _text(authId);
    for (final user in _users) {
      if (_text(user['auth_id']) == id) return user;
    }
    return null;
  }

  Map<String, dynamic>? _userById(dynamic userId) {
    final id = _text(userId);
    for (final user in _users) {
      if (_text(user['id']) == id) return user;
    }
    return null;
  }

  String _userName(Map<String, dynamic>? user) {
    if (user == null) return 'Sin asignar';
    final value = '${_text(user['nombre'])} ${_text(user['apellidos'])}'.trim();
    return value.isEmpty ? _text(user['email']) : value;
  }

  List<_HistoryEvent> get _allEvents {
    final events = <_HistoryEvent>[];
    for (final sale in _sales) {
      final date = _date(sale['fecha_efecto'] ?? sale['created_at']);
      if (date == null) continue;
      final user = _userByAuth(sale['agente_auth_id']);
      events.add(
        _HistoryEvent(
          type: 'ventas',
          date: date,
          title: _text(sale['producto']).isEmpty
              ? 'Nueva póliza'
              : _text(sale['producto']),
          subtitle:
              '${_userName(user)} · ${_text(sale['compania']).isEmpty ? 'Venta registrada' : _text(sale['compania'])}',
          amount: PremiumWeighting.net(sale),
          status: 'Emitida',
          icon: Icons.receipt_long_rounded,
          color: const Color(0xFF2454D3),
          raw: sale,
        ),
      );
    }
    for (final item in _cancellations) {
      final date = _date(item['fecha_anulacion'] ?? item['created_at']);
      if (date == null) continue;
      final sale = _sales.cast<Map<String, dynamic>?>().firstWhere(
        (row) => _text(row?['id']) == _text(item['venta_id']),
        orElse: () => null,
      );
      final user = sale == null ? null : _userByAuth(sale['agente_auth_id']);
      events.add(
        _HistoryEvent(
          type: 'anulaciones',
          date: date,
          title: 'Anulación de póliza',
          subtitle:
              '${_userName(user)} · ${_text(item['motivo']).isEmpty ? 'Producción anulada' : _text(item['motivo'])}',
          amount: -_number(item['prima_extornada']),
          status: _text(item['estado']).isEmpty
              ? 'Anulada'
              : _text(item['estado']),
          icon: Icons.cancel_outlined,
          color: const Color(0xFFE05252),
          raw: item,
        ),
      );
    }
    for (final item in _receipts) {
      final date = _date(item['fecha'] ?? item['created_at']);
      if (date == null) continue;
      final user = _userByAuth(
        item['agente'] ?? item['agente_auth_id'] ?? item['usuario_auth_id'],
      );
      final client = _text(item['cliente']).isEmpty
          ? 'Recibo ${_text(item['numero_recibo'])}'
          : _text(item['cliente']);
      events.add(
        _HistoryEvent(
          type: 'recibos',
          date: date,
          title: client,
          subtitle:
              '${_userName(user)} · ${_text(item['compania']).isEmpty ? 'Recibo' : _text(item['compania'])}',
          amount: _number(item['importe']),
          status: _text(item['estado']).isEmpty
              ? 'Registrado'
              : _text(item['estado']),
          icon: Icons.payments_outlined,
          color: const Color(0xFFE88A17),
          raw: item,
        ),
      );
    }
    for (final item in _invoices) {
      final year = int.tryParse(_text(item['anio']));
      final month = int.tryParse(_text(item['mes']));
      final date = year != null && month != null
          ? DateTime(year, month)
          : _date(item['created_at']);
      if (date == null) continue;
      final user = _userByAuth(item['usuario_auth_id']);
      events.add(
        _HistoryEvent(
          type: 'facturas',
          date: date,
          title: 'Factura ${DateFormat('MMMM yyyy', 'es_ES').format(date)}',
          subtitle: _userName(user),
          amount: _number(item['total_factura']),
          status: _text(item['estado']).isEmpty
              ? 'En preparación'
              : _text(item['estado']),
          icon: Icons.description_outlined,
          color: const Color(0xFF6F4BD8),
          raw: item,
        ),
      );
    }
    for (final item in _incorporations) {
      final date = _date(
        item['updated_at'] ?? item['created_at'] ?? item['fecha_prevista'],
      );
      if (date == null) continue;
      final name = '${_text(item['nombre'])} ${_text(item['apellidos'])}'
          .trim();
      events.add(
        _HistoryEvent(
          type: 'incorporaciones',
          date: date,
          title: name.isEmpty ? 'Proceso de incorporación' : name,
          subtitle: _text(item['figura']).isEmpty
              ? 'Incorporación comercial'
              : _text(item['figura']),
          amount: null,
          status: _text(item['estado']).isEmpty
              ? 'En proceso'
              : _text(item['estado']),
          icon: Icons.person_add_alt_1_rounded,
          color: const Color(0xFF109A8D),
          raw: item,
        ),
      );
    }
    for (final item in _roleChanges) {
      final date = _date(item['updated_at'] ?? item['created_at']);
      if (date == null) continue;
      final user =
          _userById(item['usuario_id']) ?? _userByAuth(item['usuario_auth_id']);
      events.add(
        _HistoryEvent(
          type: 'estructura',
          date: date,
          title: 'Cambio de figura · ${_userName(user)}',
          subtitle:
              '${_text(item['rol_anterior']).replaceAll('_', ' ')} → ${_text(item['rol_nuevo']).replaceAll('_', ' ')}',
          amount: null,
          status: _text(item['estado']).isEmpty
              ? 'Registrado'
              : _text(item['estado']),
          icon: Icons.account_tree_rounded,
          color: const Color(0xFF3E78C7),
          raw: item,
        ),
      );
    }
    events.sort((a, b) => b.date.compareTo(a.date));
    return events;
  }

  bool _inRange(DateTime date) {
    final range = _range;
    if (range == null) return true;
    final end = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
      23,
      59,
      59,
      999,
    );
    return !date.isBefore(range.start) && !date.isAfter(end);
  }

  List<_HistoryEvent> get _events {
    final query = _query.toLowerCase();
    return _allEvents.where((event) {
      final matchesType = _type == 'todos' || event.type == _type;
      final matchesRange = _inRange(event.date);
      final matchesQuery =
          query.isEmpty ||
          '${event.title} ${event.subtitle} ${event.status}'
              .toLowerCase()
              .contains(query);
      return matchesType && matchesRange && matchesQuery;
    }).toList();
  }

  List<Map<String, dynamic>> get _salesInRange => _sales.where((sale) {
    final date = _date(sale['fecha_efecto'] ?? sale['created_at']);
    return date != null && _inRange(date);
  }).toList();

  double get _premium =>
      _salesInRange.fold(0, (sum, sale) => sum + PremiumWeighting.net(sale));
  double get _commissions =>
      _salesInRange.fold(0, (sum, sale) => sum + _number(sale['comision']));
  double get _lifePremium => _salesInRange
      .where((sale) {
        final product = _text(sale['producto']).toLowerCase();
        return product.contains('vida') ||
            product.contains('decesos') ||
            product.contains('prima unica') ||
            product.contains('prima única');
      })
      .fold(0, (sum, sale) => sum + PremiumWeighting.net(sale));
  double get _mix => _premium <= 0 ? 0 : _lifePremium / _premium * 100;

  double get _previousPremium {
    final range = _range;
    if (range == null) return 0;
    final days = range.end.difference(range.start).inDays + 1;
    final previousEnd = range.start.subtract(const Duration(days: 1));
    final previousStart = previousEnd.subtract(Duration(days: days - 1));
    return _sales
        .where((sale) {
          final date = _date(sale['fecha_efecto'] ?? sale['created_at']);
          return date != null &&
              !date.isBefore(previousStart) &&
              !date.isAfter(
                DateTime(
                  previousEnd.year,
                  previousEnd.month,
                  previousEnd.day,
                  23,
                  59,
                  59,
                ),
              );
        })
        .fold(0, (sum, sale) => sum + PremiumWeighting.net(sale));
  }

  double get _variation {
    if (_previousPremium <= 0) return _premium > 0 ? 100 : 0;
    return (_premium - _previousPremium) / _previousPremium * 100;
  }

  List<_MonthValue> get _monthly {
    final range = _range;
    if (range == null) return const [];
    final months = <_MonthValue>[];
    var cursor = DateTime(range.start.year, range.start.month);
    final last = DateTime(range.end.year, range.end.month);
    var guard = 0;
    while (!cursor.isAfter(last) && guard < 36) {
      final end = DateTime(cursor.year, cursor.month + 1);
      final value = _sales
          .where((sale) {
            final date = _date(sale['fecha_efecto'] ?? sale['created_at']);
            return date != null && !date.isBefore(cursor) && date.isBefore(end);
          })
          .fold(0.0, (sum, sale) => sum + PremiumWeighting.net(sale));
      months.add(_MonthValue(DateFormat.MMM('es_ES').format(cursor), value));
      cursor = end;
      guard++;
    }
    return months;
  }

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
            : RefreshIndicator(
                color: const Color(0xFF2454D3),
                onRefresh: () => _load(loader: false),
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
                        _controls(),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          child: _tab == 0 ? _summary(wide) : _activity(),
                        ),
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
          'Histórico completo',
          style: TextStyle(
            color: Color(0xFF111C31),
            fontSize: 26,
            fontWeight: FontWeight.w900,
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
        final compact = box.maxWidth < 650;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'MEMORIA COMERCIAL',
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
              'Todo lo ocurrido.\nSiempre localizable.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                height: 1.08,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Producción, economía, recibos y evolución de la organización.',
              style: TextStyle(
                color: Color(0xFFDDE6FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
        final metrics = Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            _heroMetric(
              '${_allEvents.length}',
              'movimientos',
              Icons.history_rounded,
            ),
            _heroMetric('${_users.length}', 'personas', Icons.groups_rounded),
            _heroMetric(
              '${_sales.length}',
              'pólizas',
              Icons.receipt_long_rounded,
            ),
          ],
        );
        if (compact)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 24), metrics],
          );
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 20),
            Flexible(child: metrics),
          ],
        );
      },
    ),
  );

  Widget _heroMetric(String value, String label, IconData icon) => Container(
    constraints: const BoxConstraints(minWidth: 130),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFDDE6FF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _controls() => Container(
    padding: const EdgeInsets.all(18),
    decoration: _card(),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _tabButton(
                0,
                Icons.insights_rounded,
                'Resumen y evolución',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tabButton(
                1,
                Icons.view_timeline_rounded,
                'Registro de actividad',
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _historySearchField(),
                  const SizedBox(height: 10),
                  _rangeButton(),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: _historySearchField()),
                const SizedBox(width: 10),
                _rangeButton(),
              ],
            );
          },
        ),
        const SizedBox(height: 13),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _typeChip('todos', 'Todo'),
              _typeChip('ventas', 'Ventas'),
              _typeChip('anulaciones', 'Anulaciones'),
              _typeChip('recibos', 'Recibos'),
              _typeChip('facturas', 'Facturas'),
              _typeChip('incorporaciones', 'Incorporaciones'),
              _typeChip('estructura', 'Estructura'),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _historySearchField() => TextField(
    controller: _searchController,
    onChanged: (value) => setState(() => _query = value.trim()),
    decoration: InputDecoration(
      hintText: 'Buscar persona, cliente, póliza, compañía...',
      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2454D3)),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              icon: const Icon(Icons.close_rounded),
            ),
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
    ),
  );

  Widget _rangeButton() => OutlinedButton.icon(
    onPressed: _pickRange,
    icon: const Icon(Icons.date_range_rounded),
    label: Text(_rangeLabel),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF111C31),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
      side: const BorderSide(color: Color(0xFFD8DEE8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
  String get _rangeLabel {
    final range = _range;
    if (range == null) return 'Todo el histórico';
    return '${DateFormat('dd/MM/yy').format(range.start)} – ${DateFormat('dd/MM/yy').format(range.end)}';
  }

  Future<void> _pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'ES'),
      helpText: 'Selecciona el periodo histórico',
      saveText: 'Aplicar',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF2454D3),
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF111C31),
          ),
        ),
        child: child!,
      ),
    );
    if (selected != null) setState(() => _range = selected);
  }

  Widget _tabButton(int value, IconData icon, String label) {
    final selected = _tab == value;
    return Material(
      color: selected ? const Color(0xFF14213D) : const Color(0xFFF3F5F8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _tab = value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFF526078),
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF344158),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeChip(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _type == value,
      onSelected: (_) => setState(() => _type = value),
      showCheckmark: false,
      selectedColor: const Color(0xFF2454D3),
      backgroundColor: const Color(0xFFF3F5F8),
      side: BorderSide(
        color: _type == value
            ? const Color(0xFF2454D3)
            : const Color(0xFFE1E5EA),
      ),
      labelStyle: TextStyle(
        color: _type == value ? Colors.white : const Color(0xFF526078),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
  Widget _summary(bool wide) => Column(
    key: const ValueKey('summary'),
    children: [
      GridView.count(
        crossAxisCount: wide ? 4 : 2,
        childAspectRatio: wide ? 1.75 : 1.18,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _kpi(
            Icons.euro_rounded,
            'Primas',
            _money.format(_premium),
            '${_salesInRange.length} pólizas',
            const Color(0xFF2454D3),
            _variation,
          ),
          _kpi(
            Icons.pie_chart_rounded,
            'Mix D + V',
            '${_mix.toStringAsFixed(1)}%',
            _money.format(_lifePremium),
            const Color(0xFF6F4BD8),
            null,
          ),
          _kpi(
            Icons.account_balance_wallet_outlined,
            'Comisiones',
            _money.format(_commissions),
            'Generadas en el periodo',
            const Color(0xFF109A8D),
            null,
          ),
          _kpi(
            Icons.timeline_rounded,
            'Actividad',
            '${_events.length}',
            'Movimientos localizados',
            const Color(0xFFE88A17),
            null,
          ),
        ],
      ),
      const SizedBox(height: 18),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: _chart()),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: _breakdown()),
          ],
        )
      else ...[
        _chart(),
        const SizedBox(height: 18),
        _breakdown(),
      ],
      const SizedBox(height: 18),
      _recentActivity(),
    ],
  );

  Widget _kpi(
    IconData icon,
    String title,
    String value,
    String subtitle,
    Color color,
    double? variation,
  ) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _card(strong: true),
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
                              : const Color(0xFFE05252))
                          .withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${variation >= 0 ? '+' : ''}${variation.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: variation >= 0
                        ? const Color(0xFF168259)
                        : const Color(0xFFC84040),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF526078),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
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
            color: Color(0xFF7B8597),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _chart() {
    final points = _monthly;
    final maxValue = points.fold<double>(
      0,
      (value, point) => math.max(value, point.value),
    );
    return Container(
      height: 390,
      padding: const EdgeInsets.all(22),
      decoration: _card(strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.show_chart_rounded,
            'Evolución histórica',
            'Producción computable por mes',
          ),
          const SizedBox(height: 24),
          Expanded(
            child: points.isEmpty
                ? const _HistoryEmpty(
                    message:
                        'Selecciona un periodo para visualizar la evolución.',
                  )
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxValue <= 0 ? 100 : maxValue * 1.22,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxValue <= 0 ? 25 : maxValue / 4,
                        getDrawingHorizontalLine: (_) => const FlLine(
                          color: Color(0xFFE8EBF0),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => const Color(0xFF14213D),
                          getTooltipItems: (spots) => spots
                              .map(
                                (spot) => LineTooltipItem(
                                  _money.format(spot.y),
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
                            interval: math.max(
                              1,
                              (points.length / 6).ceilToDouble(),
                            ),
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= points.length)
                                return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 9),
                                child: Text(
                                  points[index].label.toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF778195),
                                    fontSize: 10,
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
                          dotData: FlDotData(show: points.length <= 14),
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

  Widget _breakdown() {
    final counts = <String, int>{};
    for (final event in _events) {
      counts[event.type] = (counts[event.type] ?? 0) + 1;
    }
    const types = [
      'ventas',
      'recibos',
      'facturas',
      'incorporaciones',
      'anulaciones',
      'estructura',
    ];
    final maxCount = counts.values.fold<int>(1, math.max);
    return Container(
      constraints: const BoxConstraints(minHeight: 390),
      padding: const EdgeInsets.all(22),
      decoration: _card(strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.donut_large_rounded,
            'Composición del histórico',
            'Movimientos por categoría',
          ),
          const SizedBox(height: 24),
          ...types.map((type) {
            final count = counts[type] ?? 0;
            final data = _typeVisual(type);
            return Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(data.$2, color: data.$3, size: 19),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          data.$1,
                          style: const TextStyle(
                            color: Color(0xFF344158),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '$count',
                        style: const TextStyle(
                          color: Color(0xFF111C31),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: count / maxCount,
                      minHeight: 7,
                      backgroundColor: const Color(0xFFE9EDF4),
                      color: data.$3,
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

  (String, IconData, Color) _typeVisual(String type) {
    switch (type) {
      case 'ventas':
        return ('Ventas', Icons.receipt_long_rounded, const Color(0xFF2454D3));
      case 'recibos':
        return ('Recibos', Icons.payments_outlined, const Color(0xFFE88A17));
      case 'facturas':
        return (
          'Facturas',
          Icons.description_outlined,
          const Color(0xFF6F4BD8),
        );
      case 'incorporaciones':
        return (
          'Incorporaciones',
          Icons.person_add_alt_1_rounded,
          const Color(0xFF109A8D),
        );
      case 'anulaciones':
        return ('Anulaciones', Icons.cancel_outlined, const Color(0xFFE05252));
      default:
        return (
          'Estructura',
          Icons.account_tree_rounded,
          const Color(0xFF3E78C7),
        );
    }
  }

  Widget _recentActivity() => Container(
    padding: const EdgeInsets.all(22),
    decoration: _card(strong: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          Icons.update_rounded,
          'Últimos movimientos',
          'Actividad más reciente dentro del periodo',
        ),
        const SizedBox(height: 18),
        if (_events.isEmpty)
          const _HistoryEmpty(
            message: 'No hay movimientos con los filtros seleccionados.',
          )
        else
          ..._events.take(6).map(_eventTile),
        if (_events.length > 6) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _tab = 1),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text('Ver los ${_events.length} movimientos'),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _activity() => Container(
    key: const ValueKey('activity'),
    padding: const EdgeInsets.all(22),
    decoration: _card(strong: true),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          Icons.view_timeline_rounded,
          'Registro de actividad',
          '${_events.length} movimientos encontrados',
        ),
        const SizedBox(height: 20),
        if (_events.isEmpty)
          const _HistoryEmpty(
            message: 'No hay movimientos con los filtros seleccionados.',
          )
        else
          ..._groupedEvents.entries.map(
            (entry) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                  child: Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF69758A),
                      fontSize: 12,
                      letterSpacing: .7,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                ...entry.value.map(_eventTile),
              ],
            ),
          ),
      ],
    ),
  );

  Map<String, List<_HistoryEvent>> get _groupedEvents {
    final result = <String, List<_HistoryEvent>>{};
    for (final event in _events) {
      final key = DateFormat('MMMM yyyy', 'es_ES').format(event.date);
      result.putIfAbsent(key, () => []).add(event);
    }
    return result;
  }

  Widget _eventTile(_HistoryEvent event) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF9FAFC),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: const Color(0xFFE4E8EF)),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: () => _showEvent(event),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(event.icon, color: event.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111C31),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      event.subtitle,
                      maxLines: 1,
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
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (event.amount != null)
                    Text(
                      _money.format(event.amount),
                      style: TextStyle(
                        color: event.amount! < 0
                            ? const Color(0xFFC84040)
                            : const Color(0xFF111C31),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('dd/MM/yyyy').format(event.date),
                    style: const TextStyle(
                      color: Color(0xFF7B8597),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA4B4)),
            ],
          ),
        ),
      ),
    ),
  );

  void _showEvent(_HistoryEvent event) {
    final visibleEntries = event.raw.entries
        .where(
          (entry) =>
              entry.value != null &&
              _text(entry.value).isNotEmpty &&
              !entry.key.toLowerCase().contains('url'),
        )
        .take(8)
        .toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
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
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: event.color.withValues(alpha: .11),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(event.icon, color: event.color),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: const TextStyle(
                              color: Color(0xFF111C31),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            DateFormat(
                              "dd 'de' MMMM 'de' yyyy",
                              'es_ES',
                            ).format(event.date),
                            style: const TextStyle(
                              color: Color(0xFF69758A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.subtitle,
                        style: const TextStyle(
                          color: Color(0xFF344158),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.status,
                              style: TextStyle(
                                color: event.color,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (event.amount != null)
                            Text(
                              _money.format(event.amount),
                              style: const TextStyle(
                                color: Color(0xFF111C31),
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Información registrada',
                  style: TextStyle(
                    color: Color(0xFF111C31),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ...visibleEntries.map(
                  (entry) =>
                      _detailRow(_fieldLabel(entry.key), _text(entry.value)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fieldLabel(String key) => key
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF69758A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF111C31),
              fontWeight: FontWeight.w800,
            ),
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
              Icons.history_rounded,
              color: Color(0xFF2454D3),
              size: 52,
            ),
            const SizedBox(height: 16),
            const Text(
              'No se pudo cargar el histórico',
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

class _HistoryEvent {
  final String type;
  final DateTime date;
  final String title;
  final String subtitle;
  final double? amount;
  final String status;
  final IconData icon;
  final Color color;
  final Map<String, dynamic> raw;

  const _HistoryEvent({
    required this.type,
    required this.date,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    required this.icon,
    required this.color,
    required this.raw,
  });
}

class _MonthValue {
  final String label;
  final double value;
  const _MonthValue(this.label, this.value);
}

class _HistoryEmpty extends StatelessWidget {
  final String message;
  const _HistoryEmpty({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 36),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F7FA),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.manage_search_rounded,
          color: Color(0xFF9BA5B5),
          size: 42,
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
