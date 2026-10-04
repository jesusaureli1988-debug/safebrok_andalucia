import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamHierarchyScreen extends StatefulWidget {
  final String role;

  const TeamHierarchyScreen({super.key, required this.role});

  @override
  State<TeamHierarchyScreen> createState() => _TeamHierarchyScreenState();
}

class _TeamHierarchyScreenState extends State<TeamHierarchyScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _money = NumberFormat.currency(
    locale: 'es_ES',
    symbol: '€',
    decimalDigits: 0,
  );

  bool _loading = true;
  String? _error;
  int _tab = 0;
  String _period = 'mes';
  String _roleFilter = 'todos';
  String _query = '';
  Map<String, dynamic>? _me;
  ProductionPeriod? _productionPeriod;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _sales = [];

  static const _inactive = {
    'inactivo',
    'baja',
    'desactivado',
    'bloqueado',
    'suspendido',
  };

  static const _roleOrder = {
    'administracion': 0,
    'director_nacional': 1,
    'director_regional': 2,
    'director_zona': 3,
    'jefe_ventas': 4,
    'jefe_equipo': 5,
    'agente': 6,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _role(dynamic value) => _text(value)
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
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
    final value = '${_text(user['nombre'])} ${_text(user['apellidos'])}'.trim();
    return value.isEmpty ? 'Usuario sin nombre' : value;
  }

  bool _isActive(Map<String, dynamic> user) =>
      !_inactive.contains(_text(user['estado']).toLowerCase());

  Future<void> _load({bool loader = true}) async {
    final auth = _supabase.auth.currentUser;
    if (auth == null) return;
    if (loader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final base = await Future.wait<dynamic>([
        _supabase
            .from('usuarios')
            .select(
              'id,auth_id,parent_id,nombre,apellidos,email,rol_usuario,estado',
            )
            .eq('auth_id', auth.id)
            .maybeSingle(),
        _supabase
            .from('usuarios')
            .select(
              'id,auth_id,parent_id,nombre,apellidos,email,rol_usuario,estado',
            ),
        ProductionPeriodService.instance.current(),
      ]);
      if (base[0] == null) throw Exception('No se ha encontrado tu perfil.');
      _me = Map<String, dynamic>.from(base[0] as Map);
      final all = (base[1] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .where(_isActive)
          .toList();
      _productionPeriod = base[2] as ProductionPeriod;
      _users = _visibleUsers(all);
      final ids = _users
          .map((user) => _text(user['auth_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      _sales = ids.isEmpty
          ? []
          : (await _supabase
                        .from('ventas')
                        .select(
                          'id,agente_auth_id,producto,fecha_efecto,created_at,prima_anual_neta,comision',
                        )
                        .inFilter('agente_auth_id', ids)
                        .order('fecha_efecto', ascending: true)
                    as List)
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
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
    final myRole = _role(_me?['rol_usuario'] ?? widget.role);
    if (myRole == 'administracion' || myRole == 'director_nacional') {
      return all;
    }
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
          if (!result.any((item) => _text(item['id']) == userId)) {
            result.add(user);
          }
          if (userId != id) pending.add(userId);
        }
      }
    }
    return result;
  }

  DateTime? _date(dynamic value) => value == null
      ? null
      : value is DateTime
      ? value
      : DateTime.tryParse(value.toString());

  DateTime get _start {
    final now = DateTime.now();
    switch (_period) {
      case 'trimestre':
        return DateTime(now.year, now.month - 2, 1);
      case 'anio':
        return DateTime(now.year, 1, 1);
      default:
        return _productionPeriod?.start ?? DateTime(now.year, now.month, 1);
    }
  }

  DateTime get _end {
    final now = DateTime.now();
    if (_period == 'mes') {
      return _productionPeriod?.endExclusive ??
          DateTime(now.year, now.month + 1, 1);
    }
    return DateTime(now.year, now.month + 1, 1);
  }

  List<Map<String, dynamic>> get _periodSales => _sales.where((sale) {
    final date = _date(sale['fecha_efecto'] ?? sale['created_at']);
    return date != null && !date.isBefore(_start) && date.isBefore(_end);
  }).toList();

  List<Map<String, dynamic>> _children(Map<String, dynamic> user) {
    final id = _text(user['id']);
    final result = _users
        .where((item) => _text(item['parent_id']) == id)
        .toList();
    result.sort((a, b) {
      final role = (_roleOrder[_role(a['rol_usuario'])] ?? 99).compareTo(
        _roleOrder[_role(b['rol_usuario'])] ?? 99,
      );
      return role != 0 ? role : _name(a).compareTo(_name(b));
    });
    return result;
  }

  List<Map<String, dynamic>> get _roots {
    final ids = _users.map((user) => _text(user['id'])).toSet();
    final myRole = _role(_me?['rol_usuario'] ?? widget.role);
    if (myRole != 'administracion' && myRole != 'director_nacional') {
      final mine = _users.where(
        (user) => _text(user['id']) == _text(_me?['id']),
      );
      if (mine.isNotEmpty) return mine.toList();
    }
    final roots = _users
        .where(
          (user) =>
              _text(user['parent_id']).isEmpty ||
              !ids.contains(_text(user['parent_id'])),
        )
        .toList();
    roots.sort((a, b) => _name(a).compareTo(_name(b)));
    return roots;
  }

  Set<String> _descendantAuthIds(Map<String, dynamic> root) {
    final result = <String>{};
    void walk(Map<String, dynamic> user) {
      final auth = _text(user['auth_id']);
      if (auth.isNotEmpty) result.add(auth);
      for (final child in _children(user)) {
        walk(child);
      }
    }

    walk(root);
    return result;
  }

  _TeamStats _stats(Map<String, dynamic> root) {
    final ids = _descendantAuthIds(root);
    final sales = _periodSales
        .where((sale) => ids.contains(_text(sale['agente_auth_id'])))
        .toList();
    final premium = sales.fold<double>(
      0,
      (sum, sale) => sum + PremiumWeighting.net(sale),
    );
    final life = sales
        .where((sale) {
          final product = _text(sale['producto']).toLowerCase();
          return product.contains('vida') ||
              product.contains('decesos') ||
              product.contains('prima unica') ||
              product.contains('prima única');
        })
        .fold<double>(0, (sum, sale) => sum + PremiumWeighting.net(sale));
    return _TeamStats(
      premium: premium,
      mix: premium <= 0 ? 0 : life / premium * 100,
      sales: sales.length,
      members: math.max(0, ids.length - 1),
    );
  }

  bool _matches(Map<String, dynamic> user) {
    final matchesRole =
        _roleFilter == 'todos' || _role(user['rol_usuario']) == _roleFilter;
    final value =
        '${_name(user)} ${_text(user['email'])} ${_roleLabel(user['rol_usuario'])}'
            .toLowerCase();
    final matchesText = _query.isEmpty || value.contains(_query.toLowerCase());
    if (matchesRole && matchesText) return true;
    return _children(user).any(_matches);
  }

  List<Map<String, dynamic>> get _filteredRoots =>
      _roots.where(_matches).toList();
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
                        _hero(wide),
                        const SizedBox(height: 18),
                        _controls(),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          child: _tab == 0
                              ? _treeView()
                              : _performanceView(wide),
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
          'Equipo y jerarquía',
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

  Widget _hero(bool wide) {
    final total = _users.length;
    final managers = _users
        .where((user) => _role(user['rol_usuario']) != 'agente')
        .length;
    final agents = total - managers;
    final orphans = _users.where((user) {
      final role = _role(user['rol_usuario']);
      return role != 'administracion' &&
          role != 'director_nacional' &&
          _text(user['parent_id']).isEmpty;
    }).length;
    final hero = Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'ORGANIZACIÓN COMERCIAL',
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
            'Toda la estructura.\nUna sola visión.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              height: 1.08,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Consulta dependencias, composición y rendimiento comercial.',
            style: TextStyle(
              color: Color(0xFFDDE6FF),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _heroMetric('$total', 'personas', Icons.groups_rounded),
              _heroMetric(
                '$managers',
                'responsables',
                Icons.account_tree_rounded,
              ),
              _heroMetric('$agents', 'agentes', Icons.person_rounded),
              _heroMetric(
                '$orphans',
                'sin dependencia',
                Icons.warning_amber_rounded,
              ),
            ],
          ),
        ],
      ),
    );
    return hero;
  }

  Widget _heroMetric(String value, String label, IconData icon) => Container(
    constraints: const BoxConstraints(minWidth: 135),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 21),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
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
                Icons.account_tree_rounded,
                'Árbol jerárquico',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tabButton(
                1,
                Icons.bar_chart_rounded,
                'Rendimiento de equipos',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre, correo o figura...',
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF2454D3),
            ),
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
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('todos', 'Todas las figuras'),
              _filterChip('director_regional', 'Regional'),
              _filterChip('director_zona', 'Zona'),
              _filterChip('jefe_ventas', 'J. ventas'),
              _filterChip('jefe_equipo', 'J. equipo'),
              _filterChip('agente', 'Agentes'),
              if (_tab == 1) ...[
                const SizedBox(width: 12),
                _periodChip('mes', 'Mes'),
                _periodChip('trimestre', '3 meses'),
                _periodChip('anio', 'Año'),
              ],
            ],
          ),
        ),
      ],
    ),
  );

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
                size: 20,
                color: selected ? Colors.white : const Color(0xFF526078),
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

  Widget _filterChip(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _roleFilter == value,
      onSelected: (_) => setState(() => _roleFilter = value),
      selectedColor: const Color(0xFF2454D3),
      backgroundColor: const Color(0xFFF3F5F8),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: _roleFilter == value ? Colors.white : const Color(0xFF526078),
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: _roleFilter == value
            ? const Color(0xFF2454D3)
            : const Color(0xFFE1E5EA),
      ),
    ),
  );

  Widget _periodChip(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _period == value,
      onSelected: (_) => setState(() => _period = value),
      selectedColor: const Color(0xFF109A8D),
      backgroundColor: const Color(0xFFF3F5F8),
      showCheckmark: false,
      labelStyle: TextStyle(
        color: _period == value ? Colors.white : const Color(0xFF526078),
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(
        color: _period == value
            ? const Color(0xFF109A8D)
            : const Color(0xFFE1E5EA),
      ),
    ),
  );
  Widget _treeView() {
    final roots = _filteredRoots;
    if (roots.isEmpty)
      return const _EmptyState(
        message: 'No hay personas que coincidan con los filtros.',
      );
    return Container(
      key: const ValueKey('tree'),
      padding: const EdgeInsets.all(20),
      decoration: _card(strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.account_tree_rounded,
            'Mapa de la organización',
            '${_users.length} personas activas dentro de tu ámbito',
          ),
          const SizedBox(height: 18),
          ...roots.map((root) => _personNode(root, 0)),
        ],
      ),
    );
  }

  Widget _personNode(Map<String, dynamic> user, int depth) {
    final children = _children(user).where(_matches).toList();
    final stats = _stats(user);
    final matchesSelf =
        (_roleFilter == 'todos' || _role(user['rol_usuario']) == _roleFilter) &&
        (_query.isEmpty ||
            '${_name(user)} ${_text(user['email'])} ${_roleLabel(user['rol_usuario'])}'
                .toLowerCase()
                .contains(_query.toLowerCase()));
    if (!matchesSelf && children.isEmpty) return const SizedBox.shrink();
    final color = _roleColor(user['rol_usuario']);
    final content = InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showPerson(user, stats),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: color.withValues(alpha: .11),
              child: Text(
                _name(user).substring(0, 1).toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name(user),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111C31),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 5,
                    children: [
                      _tag(_roleLabel(user['rol_usuario']), color),
                      if (children.isNotEmpty)
                        _tag(
                          '${children.length} directos',
                          const Color(0xFF526078),
                        ),
                      _tag(
                        _money.format(stats.premium),
                        const Color(0xFF109A8D),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8B95A6)),
          ],
        ),
      ),
    );
    return Container(
      margin: EdgeInsets.only(left: math.min(depth * 18.0, 54), bottom: 10),
      decoration: BoxDecoration(
        color: depth == 0 ? const Color(0xFFF8FAFD) : Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: depth == 0 ? const Color(0xFFD7E1F7) : const Color(0xFFE5E9EF),
        ),
      ),
      child: children.isEmpty
          ? content
          : Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: depth == 0,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                trailing: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: Color(0xFF526078),
                  ),
                ),
                title: content,
                children: children
                    .map((child) => _personNode(child, depth + 1))
                    .toList(),
              ),
            ),
    );
  }

  Widget _performanceView(bool wide) {
    var branches = <Map<String, dynamic>>[];
    final myRole = _role(_me?['rol_usuario'] ?? widget.role);
    if (myRole == 'administracion') {
      branches = _roots;
    } else {
      final mine = _users.where(
        (user) => _text(user['id']) == _text(_me?['id']),
      );
      branches = mine.isEmpty ? [] : _children(mine.first);
      if (branches.isEmpty && mine.isNotEmpty) branches = [mine.first];
    }
    branches = branches.where(_matches).toList();
    branches.sort((a, b) => _stats(b).premium.compareTo(_stats(a).premium));
    if (branches.isEmpty)
      return const _EmptyState(
        message: 'No hay equipos que coincidan con los filtros.',
      );
    final maxPremium = branches.fold<double>(
      0,
      (value, user) => math.max(value, _stats(user).premium),
    );
    return Container(
      key: const ValueKey('performance'),
      padding: const EdgeInsets.all(20),
      decoration: _card(strong: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            Icons.bar_chart_rounded,
            'Rendimiento por estructura',
            'Producción computable, mix y composición del periodo seleccionado',
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: branches.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 2 : 1,
              childAspectRatio: wide ? 2.05 : 1.55,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (context, index) {
              final user = branches[index];
              return _teamCard(user, _stats(user), index + 1, maxPremium);
            },
          ),
        ],
      ),
    );
  }

  Widget _teamCard(
    Map<String, dynamic> user,
    _TeamStats stats,
    int position,
    double maximum,
  ) {
    final color = _roleColor(user['rol_usuario']);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showPerson(user, stats),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE1E5EA)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF14213D).withValues(alpha: .055),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      '#$position',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name(user),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF111C31),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _roleLabel(user['rol_usuario']),
                          style: const TextStyle(
                            color: Color(0xFF69758A),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.open_in_new_rounded,
                    color: Color(0xFF8B95A6),
                    size: 19,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: _miniMetric('Primas', _money.format(stats.premium)),
                  ),
                  Expanded(
                    child: _miniMetric(
                      'Mix',
                      '${stats.mix.toStringAsFixed(1)}%',
                    ),
                  ),
                  Expanded(child: _miniMetric('Pólizas', '${stats.sales}')),
                  Expanded(child: _miniMetric('Equipo', '${stats.members}')),
                ],
              ),
              const SizedBox(height: 15),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: maximum <= 0
                      ? 0
                      : (stats.premium / maximum).clamp(0, 1),
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE9EDF4),
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF111C31),
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF7B8597),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
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

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );

  Color _roleColor(dynamic value) {
    switch (_role(value)) {
      case 'administracion':
        return const Color(0xFF14213D);
      case 'director_nacional':
        return const Color(0xFF2454D3);
      case 'director_regional':
        return const Color(0xFF6F4BD8);
      case 'director_zona':
        return const Color(0xFF3E78C7);
      case 'jefe_ventas':
        return const Color(0xFFE88A17);
      case 'jefe_equipo':
        return const Color(0xFF109A8D);
      default:
        return const Color(0xFF16A36A);
    }
  }

  void _showPerson(Map<String, dynamic> user, _TeamStats stats) {
    final children = _children(user);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
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
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _roleColor(
                      user['rol_usuario'],
                    ).withValues(alpha: .12),
                    child: Text(
                      _name(user).substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: _roleColor(user['rol_usuario']),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name(user),
                          style: const TextStyle(
                            color: Color(0xFF111C31),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _roleLabel(user['rol_usuario']),
                          style: const TextStyle(
                            color: Color(0xFF667187),
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
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _modalMetric(
                        'Producción',
                        _money.format(stats.premium),
                        Icons.euro_rounded,
                      ),
                    ),
                    Expanded(
                      child: _modalMetric(
                        'Mix',
                        '${stats.mix.toStringAsFixed(1)}%',
                        Icons.pie_chart_rounded,
                      ),
                    ),
                    Expanded(
                      child: _modalMetric(
                        'Pólizas',
                        '${stats.sales}',
                        Icons.receipt_long_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _detailRow(
                Icons.email_outlined,
                'Correo',
                _text(user['email']).isEmpty
                    ? 'No disponible'
                    : _text(user['email']),
              ),
              _detailRow(
                Icons.account_tree_outlined,
                'Dependientes directos',
                '${children.length}',
              ),
              _detailRow(
                Icons.groups_outlined,
                'Personas en la estructura',
                '${stats.members}',
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modalMetric(String label, String value, IconData icon) => Column(
    children: [
      Icon(icon, color: const Color(0xFF2454D3), size: 21),
      const SizedBox(height: 7),
      FittedBox(
        child: Text(
          value,
          style: const TextStyle(
            color: Color(0xFF111C31),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF778195),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _detailRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF69758A)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF667187),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
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
              Icons.account_tree_outlined,
              color: Color(0xFF2454D3),
              size: 52,
            ),
            const SizedBox(height: 16),
            const Text(
              'No se pudo cargar la estructura',
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

class _TeamStats {
  final double premium;
  final double mix;
  final int sales;
  final int members;

  const _TeamStats({
    required this.premium,
    required this.mix,
    required this.sales,
    required this.members,
  });
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 58),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFE1E5EA)),
    ),
    child: Column(
      children: [
        const Icon(
          Icons.account_tree_rounded,
          color: Color(0xFF9BA5B5),
          size: 48,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF667187),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
