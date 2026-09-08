import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/auth/app_role.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrevisionesScreen extends StatefulWidget {
  const PrevisionesScreen({super.key, required this.role});
  final String role;
  @override
  State<PrevisionesScreen> createState() => _PrevisionesScreenState();
}

class _PrevisionesScreenState extends State<PrevisionesScreen>
    with SingleTickerProviderStateMixin {
  final db = Supabase.instance.client;
  late final TabController tabs;
  late String role;
  DateTime period = DateTime(DateTime.now().year, DateTime.now().month);
  bool loading = true, saving = false;
  String? error;
  final forecasts = <String, _Forecast>{};
  final actuals = <String, _Actual>{};
  List<_MemberProgress> members = const [];
  String? currentUserId;
  bool get isAgent => role == AppRole.agente.value;

  @override
  void initState() {
    super.initState();
    role = AppRole.normalize(widget.role);
    tabs = TabController(length: isAgent ? 1 : 2, vsync: this);
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final auth = db.auth.currentUser;
    if (auth == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final me = Map<String, dynamic>.from(
        await db
            .from('usuarios')
            .select('id,auth_id,parent_id,rol_usuario,nombre,apellidos,estado')
            .or(
              'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
            )
            .eq('auth_id', auth.id)
            .single(),
      );
      final users = List<Map<String, dynamic>>.from(
        await db
            .from('usuarios')
            .select('id,auth_id,parent_id,rol_usuario,nombre,apellidos,estado')
            .or(
              'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
            ),
      );
      role = AppRole.normalize(me['rol_usuario']);
      final rows = List<Map<String, dynamic>>.from(
        await db
            .from('previsiones_mensuales')
            .select()
            .eq('periodo', dbDate(period)),
      );
      final nextForecasts = <String, _Forecast>{
        for (final row in rows.where(
          (row) => row['usuario_auth_id']?.toString() == auth.id,
        ))
          row['ambito'].toString(): _Forecast.fromRow(row),
      };
      final nextActuals = <String, _Actual>{
        'propias': await calculate({auth.id}),
        if (!isAgent) 'equipo': await calculate(teamIds(me, users)),
      };
      final nextMembers = isAgent
          ? const <_MemberProgress>[]
          : await buildMembers(me, users, rows);
      if (!mounted) return;
      setState(() {
        forecasts
          ..clear()
          ..addAll(nextForecasts);
        actuals
          ..clear()
          ..addAll(nextActuals);
        members = nextMembers;
        currentUserId = me['id']?.toString();
        loading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          error = friendlyError(e);
          loading = false;
        });
    }
  }

  Set<String> teamIds(
    Map<String, dynamic> me,
    List<Map<String, dynamic>> users,
  ) {
    final myAuth = me['auth_id']?.toString();
    if (role == AppRole.administracion.value) {
      return users
          .map((u) => u['auth_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty && id != myAuth)
          .toSet();
    }
    final children = <String, List<Map<String, dynamic>>>{};
    for (final user in users) {
      final parent = user['parent_id']?.toString();
      if (parent != null && parent.isNotEmpty) {
        children.putIfAbsent(parent, () => []).add(user);
      }
    }
    final result = <String>{}, seen = <String>{};
    void walk(String id) {
      if (!seen.add(id)) return;
      for (final child in children[id] ?? const <Map<String, dynamic>>[]) {
        final auth = child['auth_id']?.toString();
        final childId = child['id']?.toString();
        if (auth != null && auth.isNotEmpty) result.add(auth);
        if (childId != null && childId.isNotEmpty) walk(childId);
      }
    }

    final myId = me['id']?.toString();
    if (myId != null) walk(myId);
    return result;
  }

  Future<List<_MemberProgress>> buildMembers(
    Map<String, dynamic> me,
    List<Map<String, dynamic>> users,
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = teamIds(me, users);
    if (ids.isEmpty) return const [];
    final end = DateTime(period.year, period.month + 1);
    final sales = (await paged(
      'ventas',
      'agente_auth_id',
      ids,
      'created_at',
      end,
    )).where(productiveSale);
    final hires = await paged(
      'incorporaciones',
      'solicitante_auth_id',
      ids,
      'completado_at',
      end,
      completed: true,
    );

    final ownActual = <String, _Actual>{};
    for (final sale in sales) {
      final auth = sale['agente_auth_id']?.toString();
      if (auth == null) continue;
      final old = ownActual[auth] ?? const _Actual();
      final amount = PremiumWeighting.net(sale);
      ownActual[auth] = _Actual(
        old.premiums + amount,
        old.mix + (isLifeMix(sale) ? amount : 0),
        old.hires,
      );
    }
    for (final hire in hires) {
      final auth = hire['solicitante_auth_id']?.toString();
      if (auth == null) continue;
      final old = ownActual[auth] ?? const _Actual();
      ownActual[auth] = _Actual(old.premiums, old.mix, old.hires + 1);
    }

    final goals = <String, _Forecast>{};
    for (final row in rows) {
      final auth = row['usuario_auth_id']?.toString();
      final scope = row['ambito']?.toString();
      if (auth != null && scope != null) {
        goals[auth + '|' + scope] = _Forecast.fromRow(row);
      }
    }

    final visibleUsers = users
        .where((user) => ids.contains(user['auth_id']?.toString()))
        .toList();

    final children = <String, List<Map<String, dynamic>>>{};
    for (final user in visibleUsers) {
      final parent = user['parent_id']?.toString();
      if (parent != null) children.putIfAbsent(parent, () => []).add(user);
    }

    _Actual aggregateBelow(String userId, Set<String> seen) {
      if (!seen.add(userId)) return const _Actual();
      var total = const _Actual();
      for (final child in children[userId] ?? const <Map<String, dynamic>>[]) {
        final auth = child['auth_id']?.toString();
        final childId = child['id']?.toString();
        if (auth != null)
          total = total.plus(ownActual[auth] ?? const _Actual());
        if (childId != null) total = total.plus(aggregateBelow(childId, seen));
      }
      return total;
    }

    final result = <_MemberProgress>[];
    for (final user in visibleUsers) {
      final auth = user['auth_id']?.toString();
      final id = user['id']?.toString();
      if (auth == null || id == null) continue;
      final memberRole = AppRole.normalize(user['rol_usuario']);
      final agent = memberRole == AppRole.agente.value;
      result.add(
        _MemberProgress(
          user: user,
          forecast: goals[auth + '|' + (agent ? 'propias' : 'equipo')],
          actual: agent
              ? (ownActual[auth] ?? const _Actual())
              : aggregateBelow(id, <String>{}),
        ),
      );
    }
    result.sort((a, b) {
      final roleOrder = roleLevel(b.role).compareTo(roleLevel(a.role));
      if (roleOrder != 0) return roleOrder;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  int roleLevel(String value) =>
      const {
        'agente': 1,
        'jefe_equipo': 2,
        'jefe_ventas': 3,
        'director_zona': 4,
        'director_nacional': 5,
        'administracion': 6,
      }[value] ??
      0;

  String roleLabel(String value) =>
      const {
        'agente': 'Agente',
        'jefe_equipo': 'Jefe de equipo',
        'jefe_ventas': 'Jefe de ventas',
        'director_zona': 'Director de zona',
        'director_nacional': 'Director nacional',
        'administracion': 'Administración',
      }[value] ??
      'Usuario';
  Future<_Actual> calculate(Set<String> ids) async {
    if (ids.isEmpty) return const _Actual();
    final end = DateTime(period.year, period.month + 1);
    final sales = await paged(
      'ventas',
      'agente_auth_id',
      ids,
      'created_at',
      end,
    );
    final productive = sales.where(productiveSale).toList();
    final premiums = productive.fold<double>(
      0,
      (sum, sale) => sum + PremiumWeighting.net(sale),
    );
    final mix = productive
        .where(isLifeMix)
        .fold<double>(0, (sum, sale) => sum + PremiumWeighting.net(sale));
    final hires = await paged(
      'incorporaciones',
      'solicitante_auth_id',
      ids,
      'completado_at',
      end,
      completed: true,
    );
    return _Actual(premiums, mix, hires.length);
  }

  Future<List<Map<String, dynamic>>> paged(
    String table,
    String column,
    Set<String> ids,
    String dateColumn,
    DateTime end, {
    bool completed = false,
  }) async {
    final result = <Map<String, dynamic>>[], all = ids.toList();
    for (var i = 0; i < all.length; i += 80) {
      final block = all.sublist(i, math.min(i + 80, all.length));
      var from = 0;
      while (true) {
        var query = db
            .from(table)
            .select()
            .inFilter(column, block)
            .gte(dateColumn, period.toUtc().toIso8601String())
            .lt(dateColumn, end.toUtc().toIso8601String());
        if (completed) query = query.eq('estado', 'ALTA_COMPLETADA');
        final page = List<Map<String, dynamic>>.from(
          await query.range(from, from + 999),
        );
        result.addAll(page);
        if (page.length < 1000) break;
        from += 1000;
      }
    }
    return result;
  }

  bool productiveSale(Map<String, dynamic> sale) {
    final text = [
      sale['estado'],
      sale['estado_poliza'],
      sale['tipo_movimiento'],
      sale['situacion'],
    ].join(' ').toLowerCase();
    return ![
      'baja',
      'extorno',
      'anulada',
      'anulado',
      'cancelada',
      'cancelado',
    ].any(text.contains);
  }

  bool isLifeMix(Map<String, dynamic> sale) {
    final product = normalize(
      sale['producto'] ?? sale['ramo'] ?? sale['tipo_seguro'],
    );
    return product.contains('deceso') || product.contains('vida');
  }

  String normalize(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  Future<void> edit(String scope) async {
    final old = forecasts[scope] ?? const _Forecast();
    final premium = TextEditingController(text: editable(old.premiums));
    final mix = TextEditingController(text: editable(old.mix));
    final hires = TextEditingController(
      text: old.hires == 0 ? '' : old.hires.toString(),
    );
    final key = GlobalKey<FormState>();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          22,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 22,
        ),
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scope == 'propias' ? 'Previsión propia' : 'Previsión de equipo',
                style: const TextStyle(
                  color: const Color(0xFF071A3A),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                monthText(period),
                style: const TextStyle(color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              field(premium, 'Primas previstas (€)', Icons.euro_rounded),
              const SizedBox(height: 12),
              field(
                mix,
                'Decesos + Vida previstos (€)',
                Icons.health_and_safety_rounded,
              ),
              const SizedBox(height: 12),
              field(
                hires,
                'Incorporaciones previstas',
                Icons.person_add_alt_1_rounded,
                integer: true,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () {
                    if (key.currentState!.validate())
                      Navigator.pop(context, true);
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Guardar previsión'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted != true) return;
    final data = _Forecast(
      parse(premium.text),
      parse(mix.text),
      int.tryParse(hires.text) ?? 0,
    );
    if (data.mix > data.premiums) {
      notice('Decesos + Vida no puede superar las primas totales.');
      return;
    }
    await save(scope, data);
  }

  Widget field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool integer = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    style: const TextStyle(color: const Color(0xFF071A3A)),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: const Color(0xFF64748B)),
      prefixIcon: Icon(icon, color: const Color(0xFF20C7C2)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
    ),
    validator: (value) {
      final number = integer
          ? int.tryParse(value?.trim() ?? '')?.toDouble()
          : parseNullable(value);
      return number == null || number < 0
          ? 'Introduce una cantidad válida'
          : null;
    },
  );

  Future<void> save(String scope, _Forecast data) async {
    final auth = db.auth.currentUser;
    if (auth == null) return;
    setState(() => saving = true);
    try {
      await db.from('previsiones_mensuales').upsert({
        'usuario_auth_id': auth.id,
        'periodo': dbDate(period),
        'ambito': scope,
        'primas_objetivo': data.premiums,
        'decesos_vida_objetivo': data.mix,
        'incorporaciones_objetivo': data.hires,
      }, onConflict: 'usuario_auth_id,periodo,ambito');
      if (mounted) setState(() => forecasts[scope] = data);
      notice('Previsión guardada correctamente.');
    } catch (e) {
      notice(friendlyError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF2FCFD),
    appBar: AppBar(
      backgroundColor: const Color(0xFFFFFFFF),
      foregroundColor: const Color(0xFF071A3A),
      title: const Text(
        'Previsiones',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded)),
      ],
      bottom: TabBar(
        controller: tabs,
        indicatorColor: const Color(0xFF20C7C2),
        labelColor: const Color(0xFF071A3A),
        unselectedLabelColor: const Color(0xFF64748B),
        tabs: [
          const Tab(text: 'Propias', icon: Icon(Icons.person_rounded)),
          if (!isAgent)
            const Tab(text: 'Equipo', icon: Icon(Icons.groups_rounded)),
        ],
      ),
    ),
    body: Column(
      children: [
        monthPicker(),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? errorView()
              : TabBarView(
                  controller: tabs,
                  children: [content('propias'), if (!isAgent) teamContent()],
                ),
        ),
      ],
    ),
  );

  Widget monthPicker() => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFF20C7C2).withValues(alpha: .3)),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: () => changeMonth(-1),
          icon: const Icon(Icons.chevron_left, color: Color(0xFF071A3A)),
        ),
        Expanded(
          child: Column(
            children: [
              const Text(
                'PERIODO MENSUAL',
                style: TextStyle(
                  color: Color(0xFF20C7C2),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                monthText(period),
                style: const TextStyle(
                  color: const Color(0xFF071A3A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => changeMonth(1),
          icon: const Icon(Icons.chevron_right, color: Color(0xFF071A3A)),
        ),
      ],
    ),
  );

  List<_MemberProgress> childrenOf(_MemberProgress member) =>
      members.where((item) => item.parentId == member.id).toList();

  List<_MemberProgress> rootMembers() {
    final ids = members.map((member) => member.id).toSet();
    return members.where((member) {
      if (member.parentId == currentUserId) return true;
      if (role == AppRole.administracion.value) {
        return member.parentId == null || !ids.contains(member.parentId);
      }
      return false;
    }).toList();
  }

  Widget teamContent() {
    final goal = forecasts['equipo'];
    final actual = actuals['equipo'] ?? const _Actual();
    double ratio(double real, double target) => target <= 0 ? 0 : real / target;
    final roots = rootMembers();
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFE1F8F8)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.account_tree_rounded,
                      color: Color(0xFF20C7C2),
                      size: 38,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Compromiso de mi estructura',
                        style: TextStyle(
                          color: const Color(0xFF071A3A),
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (goal == null)
                  const Text(
                    'Todavía no has registrado la previsión de tu equipo.',
                    style: TextStyle(color: const Color(0xFF53627A)),
                  )
                else
                  Row(
                    children: [
                      miniProgress(
                        'Primas',
                        ratio(actual.premiums, goal.premiums),
                        const Color(0xFF60A5FA),
                      ),
                      const SizedBox(width: 8),
                      miniProgress(
                        'D + V',
                        ratio(actual.mix, goal.mix),
                        const Color(0xFF2DD4BF),
                      ),
                      const SizedBox(width: 8),
                      miniProgress(
                        'Altas',
                        ratio(actual.hires.toDouble(), goal.hires.toDouble()),
                        const Color(0xFFFFA726),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: saving ? null : () => edit('equipo'),
                    icon: Icon(goal == null ? Icons.add : Icons.edit),
                    label: Text(
                      goal == null
                          ? 'Crear mi previsión de equipo'
                          : 'Modificar mi previsión de equipo',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF071A3A),
                      side: const BorderSide(color: Color(0xFF20C7C2)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'ESTRUCTURA DESPLEGABLE',
            style: TextStyle(
              color: Color(0xFF20C7C2),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          if (roots.isEmpty)
            const _EmptyTeam()
          else
            ...roots.map((member) => memberCard(member, 0)),
        ],
      ),
    );
  }

  Widget memberCard(_MemberProgress member, int depth) {
    final children = childrenOf(member);
    final body = memberBody(member);
    if (children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: () => showMember(member),
          borderRadius: BorderRadius.circular(20),
          child: body,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF20C7C2).withValues(alpha: .25),
            ),
          ),
          child: ExpansionTile(
            initiallyExpanded: depth == 0,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
            iconColor: const Color(0xFF20C7C2),
            collapsedIconColor: const Color(0xFF20C7C2),
            title: body,
            children: children
                .map((child) => memberCard(child, depth + 1))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget memberBody(_MemberProgress member) {
    final goal = member.forecast;
    final actual = member.actual;
    double ratio(double real, double target) => target <= 0 ? 0 : real / target;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: goal == null
              ? Colors.orange.withValues(alpha: .3)
              : const Color(0xFF20C7C2).withValues(alpha: .22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF0A7F91).withValues(alpha: .22),
                child: Icon(
                  member.role == AppRole.agente.value
                      ? Icons.person
                      : Icons.groups,
                  color: const Color(0xFF20C7C2),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: const TextStyle(
                        color: const Color(0xFF071A3A),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      roleLabel(member.role) +
                          (member.role == AppRole.agente.value
                              ? ' · Compromiso propio'
                              : ' · Compromiso de estructura'),
                      style: const TextStyle(
                        color: const Color(0xFF64748B),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ver detalle',
                onPressed: () => showMember(member),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: const Color(0xFF78909C),
                  size: 19,
                ),
              ),
              if (goal == null) const _PendingBadge(),
            ],
          ),
          if (goal != null) ...[
            const SizedBox(height: 13),
            Row(
              children: [
                miniProgress(
                  'Primas',
                  ratio(actual.premiums, goal.premiums),
                  const Color(0xFF0A7F91),
                ),
                const SizedBox(width: 7),
                miniProgress(
                  'D + V',
                  ratio(actual.mix, goal.mix),
                  const Color(0xFF0AAEAE),
                ),
                const SizedBox(width: 7),
                miniProgress(
                  'Altas',
                  ratio(actual.hires.toDouble(), goal.hires.toDouble()),
                  const Color(0xFF10AAA6),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              member.role == AppRole.agente.value
                  ? 'Pendiente de registrar su previsión propia.'
                  : 'Pendiente de registrar su previsión de equipo.',
              style: const TextStyle(
                color: const Color(0xFF64748B),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget miniProgress(String label, double ratio, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            (ratio * 100).toStringAsFixed(0) + '%',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: const Color(0xFF64748B),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> showMember(_MemberProgress member) async {
    final goal = member.forecast;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF2FCFD),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        maxChildSize: .94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              member.name,
              style: const TextStyle(
                color: const Color(0xFF071A3A),
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              roleLabel(member.role) + ' · ' + monthText(period),
              style: const TextStyle(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 18),
            if (goal == null)
              const _EmptyCommitment()
            else ...[
              progress(
                'Primas',
                'Compromiso individual',
                Icons.euro,
                const Color(0xFF0A7F91),
                member.actual.premiums,
                goal.premiums,
                money: true,
              ),
              const SizedBox(height: 12),
              progress(
                'Decesos + Vida',
                'Compromiso individual',
                Icons.health_and_safety,
                const Color(0xFF0AAEAE),
                member.actual.mix,
                goal.mix,
                money: true,
              ),
              const SizedBox(height: 12),
              progress(
                'Incorporaciones',
                'Compromiso individual',
                Icons.person_add_alt_1,
                const Color(0xFF10AAA6),
                member.actual.hires.toDouble(),
                goal.hires.toDouble(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget content(String scope) {
    final goal = forecasts[scope] ?? const _Forecast();
    final actual = actuals[scope] ?? const _Actual();
    final missing = !forecasts.containsKey(scope);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          hero(scope, missing),
          const SizedBox(height: 14),
          progress(
            'Primas',
            'Producción neta ponderada',
            Icons.euro,
            const Color(0xFF0A7F91),
            actual.premiums,
            goal.premiums,
            money: true,
          ),
          const SizedBox(height: 12),
          progress(
            'Decesos + Vida',
            'Mix dentro del total',
            Icons.health_and_safety,
            const Color(0xFF0AAEAE),
            actual.mix,
            goal.mix,
            money: true,
          ),
          const SizedBox(height: 12),
          progress(
            'Incorporaciones',
            'Altas completadas',
            Icons.person_add_alt_1,
            const Color(0xFF10AAA6),
            actual.hires.toDouble(),
            goal.hires.toDouble(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: saving ? null : () => edit(scope),
              icon: Icon(missing ? Icons.add : Icons.edit),
              label: Text(
                missing ? 'Crear previsión del mes' : 'Modificar previsión',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget hero(String scope, bool missing) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(23),
      gradient: const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFE1F8F8)],
      ),
    ),
    child: Row(
      children: [
        Icon(
          scope == 'propias' ? Icons.person : Icons.groups,
          color: const Color(0xFF20C7C2),
          size: 36,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scope == 'propias'
                    ? 'Mi compromiso mensual'
                    : 'Compromiso de mi equipo',
                style: const TextStyle(
                  color: const Color(0xFF071A3A),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                missing
                    ? 'Aún no has registrado este mes.'
                    : 'El avance se actualiza con la actividad real.',
                style: const TextStyle(color: const Color(0xFF53627A)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget progress(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    double real,
    double goal, {
    bool money = false,
  }) {
    final ratio = goal <= 0 ? 0.0 : real / goal;
    final bar = ratio.clamp(0.0, 1.0);
    String show(double n) => money ? euros(n) : n.toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 29),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: const Color(0xFF071A3A),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: const Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                (ratio * 100).toStringAsFixed(1) + '%',
                style: TextStyle(
                  color: color,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              datum('REAL', show(real)),
              datum('PREVISIÓN', show(goal)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: bar,
              minHeight: 9,
              backgroundColor: const Color(0xFFD9E9EC),
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget datum(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: const Color(0xFF78909C),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: const Color(0xFF071A3A),
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.orange, size: 46),
          const SizedBox(height: 10),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: const Color(0xFF53627A)),
          ),
          FilledButton(onPressed: load, child: const Text('Reintentar')),
        ],
      ),
    ),
  );

  void changeMonth(int delta) {
    setState(() => period = DateTime(period.year, period.month + delta));
    load();
  }

  void notice(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String friendlyError(Object e) =>
      e.toString().contains('previsiones_mensuales')
      ? 'El módulo de previsiones aún no está disponible en el servidor.'
      : 'No se pudieron cargar las previsiones. Vuelve a intentarlo.';
  String dbDate(DateTime d) =>
      d.year.toString().padLeft(4, '0') +
      '-' +
      d.month.toString().padLeft(2, '0') +
      '-01';
  String monthText(DateTime d) {
    const m = [
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
    return m[d.month - 1] + ' ' + d.year.toString();
  }

  String euros(double n) {
    final t = n.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return t + ' €';
  }

  double? parseNullable(String? v) {
    final raw = (v ?? '').trim();
    if (raw.isEmpty) return null;
    return double.tryParse(
      raw.contains(',') ? raw.replaceAll('.', '').replaceAll(',', '.') : raw,
    );
  }

  double parse(String v) => parseNullable(v) ?? 0;
  String editable(double v) => v == 0 ? '' : v.toStringAsFixed(2);
}

class _Forecast {
  const _Forecast([this.premiums = 0, this.mix = 0, this.hires = 0]);
  factory _Forecast.fromRow(Map<String, dynamic> row) => _Forecast(
    PremiumWeighting.number(row['primas_objetivo']),
    PremiumWeighting.number(row['decesos_vida_objetivo']),
    (row['incorporaciones_objetivo'] as num?)?.toInt() ?? 0,
  );
  final double premiums, mix;
  final int hires;
}

class _Actual {
  const _Actual([this.premiums = 0, this.mix = 0, this.hires = 0]);
  final double premiums, mix;
  final int hires;

  _Actual plus(_Actual other) =>
      _Actual(premiums + other.premiums, mix + other.mix, hires + other.hires);
}

class _MemberProgress {
  const _MemberProgress({
    required this.user,
    required this.forecast,
    required this.actual,
  });
  final Map<String, dynamic> user;
  final _Forecast? forecast;
  final _Actual actual;
  String get id => user['id']?.toString() ?? '';
  String? get parentId => user['parent_id']?.toString();
  String get name {
    final value =
        ((user['nombre'] ?? '').toString() +
                ' ' +
                (user['apellidos'] ?? '').toString())
            .trim();
    return value.isEmpty ? 'Usuario' : value;
  }

  String get role => AppRole.normalize(user['rol_usuario']);
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'PENDIENTE',
      style: TextStyle(
        color: Colors.orange,
        fontSize: 9,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _EmptyTeam extends StatelessWidget {
  const _EmptyTeam();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(28),
    child: Column(
      children: [
        Icon(
          Icons.account_tree_outlined,
          color: const Color(0xFF78909C),
          size: 48,
        ),
        SizedBox(height: 12),
        Text(
          'No hay miembros por debajo de tu figura.',
          textAlign: TextAlign.center,
          style: TextStyle(color: const Color(0xFF64748B)),
        ),
      ],
    ),
  );
}

class _EmptyCommitment extends StatelessWidget {
  const _EmptyCommitment();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 30),
    child: Column(
      children: [
        Icon(Icons.pending_actions_rounded, color: Colors.orange, size: 50),
        SizedBox(height: 12),
        Text(
          'Este usuario aún no ha registrado sus compromisos del mes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: const Color(0xFF53627A)),
        ),
      ],
    ),
  );
}
