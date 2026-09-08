import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cambios_rol_panel.dart';

class UsuariosAccesosScreen extends StatefulWidget {
  const UsuariosAccesosScreen({super.key, required this.allowed});

  final bool allowed;
  @override
  State<UsuariosAccesosScreen> createState() => _State();
}

class _State extends State<UsuariosAccesosScreen>
    with SingleTickerProviderStateMixin {
  final db = Supabase.instance.client, search = TextEditingController();
  final activeScroll = ScrollController(), blockedScroll = ScrollController();
  late final TabController tabs;
  List<Map<String, dynamic>> activeUsers = [],
      blockedUsers = [],
      pending = [],
      audit = [];
  final Map<String, Map<String, dynamic>> parentCache = {};
  bool loading = true;
  bool loadingActiveMore = false, loadingBlockedMore = false;
  bool hasMoreActive = true, hasMoreBlocked = true;
  Timer? searchDebounce;
  String? error;
  static const labels = {
    'administracion': 'Administración',
    'director_nacional': 'Director nacional',
    'director_zona': 'Director de zona',
    'jefe_ventas': 'Jefe de ventas',
    'jefe_equipo': 'Jefe de equipo',
    'agente': 'Agente',
  };
  static const parents = <String, Set<String>>{
    'administracion': {},
    'director_nacional': {},
    'director_zona': {'director_nacional'},
    'jefe_ventas': {'director_zona', 'director_nacional'},
    'jefe_equipo': {'jefe_ventas', 'director_zona', 'director_nacional'},
    'agente': {
      'jefe_equipo',
      'jefe_ventas',
      'director_zona',
      'director_nacional',
    },
  };
  String norm(dynamic v) => (v ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  String name(Map u) => '${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}'.trim();
  bool active(Map u) => !{
    'bloqueado',
    'inactivo',
    'desactivado',
  }.contains(norm(u['estado'] ?? 'activo'));
  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 5, vsync: this);
    activeScroll.addListener(() => _handleScroll(true));
    blockedScroll.addListener(() => _handleScroll(false));
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    search.dispose();
    activeScroll.dispose();
    blockedScroll.dispose();
    searchDebounce?.cancel();
    super.dispose();
  }

  void _handleScroll(bool state) {
    final controller = state ? activeScroll : blockedScroll;
    if (controller.position.extentAfter < 240) loadUserPage(state);
  }

  void _searchChanged(String _) {
    searchDebounce?.cancel();
    searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      await Future.wait([
        loadUserPage(true, reset: true),
        loadUserPage(false, reset: true),
      ]);
    });
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await Future.wait([
        loadUserPage(true, reset: true, notify: false),
        loadUserPage(false, reset: true, notify: false),
      ]);
      final loadedPending = await db
          .from('incorporaciones')
          .select('id,nombre,apellidos,email,figura,responsable_id,updated_at')
          .eq('estado', 'ALTA_COMPLETADA')
          .isFilter('usuario_creado_id', null)
          .order('updated_at', ascending: false);
      pending = List<Map<String, dynamic>>.from(loadedPending);
      try {
        final loadedAudit = await db
            .from('usuarios_accesos_auditoria')
            .select('id,accion,objetivo_email,detalle,created_at')
            .order('created_at', ascending: false)
            .limit(200);
        audit = List<Map<String, dynamic>>.from(loadedAudit);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST205') rethrow;
        audit = [];
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadUserPage(
    bool state, {
    bool reset = false,
    bool notify = true,
  }) async {
    if (state ? loadingActiveMore : loadingBlockedMore) return;
    if (!reset && !(state ? hasMoreActive : hasMoreBlocked)) return;
    if (mounted && notify) {
      setState(() {
        if (state) {
          loadingActiveMore = true;
        } else {
          loadingBlockedMore = true;
        }
      });
    } else if (state) {
      loadingActiveMore = true;
    } else {
      loadingBlockedMore = true;
    }
    try {
      final current = state ? activeUsers : blockedUsers;
      final offset = reset ? 0 : current.length;
      dynamic query = db
          .from('usuarios')
          .select(
            'id,auth_id,nombre,apellidos,email,rol_usuario,parent_id,estado,created_at',
          );
      query = state
          ? query.or(
              'estado.is.null,estado.not.in.(bloqueado,inactivo,desactivado)',
            )
          : query.inFilter('estado', const [
              'bloqueado',
              'inactivo',
              'desactivado',
            ]);
      final q = search.text.trim();
      if (q.isNotEmpty) {
        final safe = q.replaceAll(RegExp(r'[,()%]'), ' ').trim();
        if (safe.isNotEmpty) {
          query = query.or(
            'nombre.ilike.%$safe%,apellidos.ilike.%$safe%,email.ilike.%$safe%',
          );
        }
      }
      final loaded = List<Map<String, dynamic>>.from(
        await query
            .order('nombre')
            .order('apellidos')
            .range(offset, offset + 9),
      );
      await _cacheParents(loaded);
      if (!mounted) return;
      if (q != search.text.trim()) return;
      setState(() {
        error = null;
        if (state) {
          activeUsers = reset ? loaded : [...activeUsers, ...loaded];
          hasMoreActive = loaded.length == 10;
        } else {
          blockedUsers = reset ? loaded : [...blockedUsers, ...loaded];
          hasMoreBlocked = loaded.length == 10;
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          if (state) {
            loadingActiveMore = false;
          } else {
            loadingBlockedMore = false;
          }
        });
      }
    }
  }

  Future<void> _cacheParents(List<Map<String, dynamic>> rows) async {
    final ids = rows
        .map((u) => u['parent_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty && !parentCache.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    final loaded = await db
        .from('usuarios')
        .select('id,nombre,apellidos')
        .inFilter('id', ids);
    for (final item in List<Map<String, dynamic>>.from(loaded)) {
      parentCache[item['id'].toString()] = item;
    }
  }

  Future<void> call(String action, Map<String, dynamic> body) async {
    FunctionResponse r;
    try {
      r = await db.functions.invoke(
        'gestionar-usuarios',
        body: {'action': action, ...body},
      );
    } on FunctionException catch (e) {
      final message = errorMessage(e.details);
      if (message.isNotEmpty) throw Exception(message);
      throw Exception(
        e.reasonPhrase ?? 'La función de usuarios rechazó la operación.',
      );
    }
    if (r.status < 200 || r.status >= 300) {
      throw Exception(r.data is Map ? r.data['error'] : r.data);
    }
  }

  String errorMessage(dynamic value) {
    if (value == null) return '';
    if (value is String) {
      final text = value.trim();
      return text == '[object Object]' ? '' : text;
    }
    if (value is Map) {
      for (final key in const [
        'message',
        'msg',
        'error_description',
        'error',
        'details',
        'hint',
      ]) {
        final text = errorMessage(value[key]);
        if (text.isNotEmpty) return text;
      }
    }
    final text = value.toString().trim();
    return text == '[object Object]' ? '' : text;
  }

  void msg(String s, [bool bad = false]) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s),
          backgroundColor: bad ? Colors.red : Colors.green,
        ),
      );
  Future<void> form({
    Map<String, dynamic>? user,
    Map<String, dynamic>? incorporation,
  }) async {
    final d = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _Form(
        labels: labels,
        parents: parents,
        user: user,
        incorporation: incorporation,
      ),
    );
    if (d == null) return;
    try {
      await call(user == null ? 'create' : 'update_assignment', {
        if (user != null) 'user_id': user['id'],
        ...d,
      });
      msg(
        user == null
            ? 'Usuario creado y acceso enviado.'
            : 'Cambio solicitado. Si cambia la figura, el rol actual seguirá activo hasta completar el nuevo contrato.',
      );
      await load();
    } catch (e) {
      msg(
        'No se pudo completar: ${e.toString().replaceFirst('Exception: ', '')}',
        true,
      );
    }
  }

  Future<void> action(String a, Map<String, dynamic> u) async {
    try {
      await call(a, {'user_id': u['id']});
      msg(
        a == 'resend_access'
            ? 'Acceso reenviado.'
            : a == 'deactivate'
            ? 'Usuario desactivado.'
            : 'Usuario reactivado.',
      );
      await load();
    } catch (e) {
      msg('No se pudo completar: $e', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.allowed) {
      return const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 52, color: Colors.red),
                SizedBox(height: 12),
                Text(
                  'Acceso restringido',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Solo Administración y Director nacional pueden gestionar usuarios y accesos.',
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      color: const Color(0xFFF3F6FA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usuarios y accesos',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Altas, permisos, responsables y seguridad de acceso.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: load,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => form(),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Crear usuario'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: TabBar(
              controller: tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF1565C0),
              tabs: [
                Tab(
                  text:
                      'Activos (${activeUsers.length}${hasMoreActive ? '+' : ''})',
                ),
                Tab(text: 'Pendientes (${pending.length})'),
                Tab(
                  text:
                      'Bloqueados (${blockedUsers.length}${hasMoreBlocked ? '+' : ''})',
                ),
                Tab(text: 'Historial (${audit.length})'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (error != null)
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: const Text('No se pudieron cargar los datos'),
                subtitle: Text(error!),
                trailing: TextButton(
                  onPressed: load,
                  child: const Text('Reintentar'),
                ),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: tabs,
                    children: [
                      userList(activeUsers, true),
                      pendingList(),
                      userList(blockedUsers, false),
                      const CambiosRolPanel(canManage: true),
                      auditList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget userList(List<Map<String, dynamic>> rows, bool state) => Column(
    children: [
      TextField(
        controller: search,
        onChanged: _searchChanged,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o email',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: rows.isEmpty && (state ? loadingActiveMore : loadingBlockedMore)
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
            ? const _Empty('No hay usuarios en esta sección.')
            : ListView.separated(
                controller: state ? activeScroll : blockedScroll,
                itemCount:
                    rows.length +
                    ((state ? loadingActiveMore : loadingBlockedMore) ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => i == rows.length
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : userCard(rows[i]),
              ),
      ),
    ],
  );
  Widget userCard(Map<String, dynamic> u) {
    final p = parentCache[u['parent_id']?.toString()];
    return Card(
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          child: Text(name(u).isEmpty ? '?' : name(u)[0].toUpperCase()),
        ),
        title: Text(
          name(u),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${u['email'] ?? ''}\n${labels[norm(u['rol_usuario'])] ?? u['rol_usuario']} · Responsable: ${p == null ? 'No aplica' : name(p)}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) => v == 'edit' ? form(user: u) : action(v, u),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: Text('Cambiar rol / responsable'),
            ),
            const PopupMenuItem(
              value: 'resend_access',
              child: Text('Reenviar acceso / restablecimiento'),
            ),
            PopupMenuItem(
              value: active(u) ? 'deactivate' : 'reactivate',
              child: Text(
                active(u) ? 'Desactivar usuario' : 'Reactivar usuario',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget pendingList() => pending.isEmpty
      ? const _Empty('No hay incorporaciones listas para alta.')
      : ListView.separated(
          itemCount: pending.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final e = pending[i];
            return Card(
              elevation: 0,
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
                title: Text(
                  '${e['nombre']} ${e['apellidos']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${e['email']} · ${labels[norm(e['figura'])] ?? e['figura']}',
                ),
                trailing: FilledButton.icon(
                  onPressed: () => form(incorporation: e),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Crear acceso'),
                ),
              ),
            );
          },
        );
  Widget auditList() => audit.isEmpty
      ? const _Empty('Todavía no hay movimientos registrados.')
      : ListView.separated(
          itemCount: audit.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final a = audit[i];
            return ListTile(
              tileColor: Colors.white,
              leading: const Icon(Icons.history),
              title: Text(a['accion'].toString().replaceAll('_', ' ')),
              subtitle: Text(
                '${a['objetivo_email'] ?? ''}\n${a['created_at'] ?? ''}',
              ),
            );
          },
        );
}

class _Form extends StatefulWidget {
  const _Form({
    required this.labels,
    required this.parents,
    this.user,
    this.incorporation,
  });
  final Map<String, String> labels;
  final Map<String, Set<String>> parents;
  final Map<String, dynamic>? user, incorporation;
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final db = Supabase.instance.client;
  late final TextEditingController first, last, email;
  late String role;
  String? parentId;
  List<Map<String, dynamic>> options = [];
  bool loadingParents = false;
  String? parentsError;
  bool get editing => widget.user != null;
  String norm(dynamic v) => v
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
  @override
  void initState() {
    super.initState();
    final s = widget.user ?? widget.incorporation ?? {};
    first = TextEditingController(text: '${s['nombre'] ?? ''}');
    last = TextEditingController(text: '${s['apellidos'] ?? ''}');
    email = TextEditingController(text: '${s['email'] ?? ''}');
    role = norm(s['rol_usuario'] ?? s['figura'] ?? 'agente');
    parentId = (s['parent_id'] ?? s['responsable_id'])?.toString();
    loadParents();
  }

  @override
  void dispose() {
    first.dispose();
    last.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> loadParents() async {
    final wanted = widget.parents[role] ?? const <String>{};
    if (wanted.isEmpty) {
      if (mounted) setState(() => options = []);
      return;
    }
    setState(() {
      loadingParents = true;
      parentsError = null;
    });
    try {
      final loaded = List<Map<String, dynamic>>.from(
        await db
            .from('usuarios')
            .select('id,nombre,apellidos,rol_usuario,estado')
            .inFilter('rol_usuario', wanted.toList())
            .or('estado.is.null,estado.not.in.(bloqueado,inactivo,desactivado)')
            .order('nombre')
            .order('apellidos')
            .limit(100),
      );
      if (parentId != null &&
          !loaded.any((u) => u['id'].toString() == parentId)) {
        final selected = await db
            .from('usuarios')
            .select('id,nombre,apellidos,rol_usuario,estado')
            .eq('id', parentId!)
            .maybeSingle();
        if (selected != null &&
            wanted.contains(norm(selected['rol_usuario']))) {
          loaded.add(Map<String, dynamic>.from(selected));
        } else {
          parentId = null;
        }
      }
      if (mounted) setState(() => options = loaded);
    } catch (e) {
      if (mounted) setState(() => parentsError = e.toString());
    } finally {
      if (mounted) setState(() => loadingParents = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(editing ? 'Editar asignación' : 'Crear acceso SafeBrok'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!editing) ...[
              field(first, 'Nombre'),
              field(last, 'Apellidos'),
              field(email, 'Email'),
            ],
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(
                labelText: 'Rol',
                border: OutlineInputBorder(),
              ),
              items: widget.labels.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() {
                  role = v!;
                  parentId = null;
                  options = [];
                });
                loadParents();
              },
            ),
            const SizedBox(height: 12),
            if ((widget.parents[role] ?? const <String>{}).isNotEmpty)
              if (loadingParents)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(),
                )
              else if (parentsError != null)
                ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: const Text('No se pudieron cargar los responsables'),
                  trailing: TextButton(
                    onPressed: loadParents,
                    child: const Text('Reintentar'),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: parentId,
                  decoration: const InputDecoration(
                    labelText: 'Responsable directo',
                    border: OutlineInputBorder(),
                  ),
                  items: options
                      .map(
                        (u) => DropdownMenuItem(
                          value: u['id'].toString(),
                          child: Text('${u['nombre']} ${u['apellidos']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => parentId = v),
                )
            else
              const ListTile(
                leading: Icon(Icons.account_tree_outlined),
                title: Text('Este rol inicia la jerarquía.'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          if (!editing &&
              (first.text.trim().isEmpty ||
                  last.text.trim().isEmpty ||
                  !email.text.contains('@'))) {
            return;
          }
          if ((widget.parents[role] ?? const <String>{}).isNotEmpty &&
              parentId == null) {
            return;
          }
          Navigator.pop(context, {
            'nombre': first.text.trim(),
            'apellidos': last.text.trim(),
            'email': email.text.trim().toLowerCase(),
            'rol_usuario': role,
            'parent_id': parentId,
            if (widget.incorporation != null)
              'incorporacion_id': widget.incorporation!['id'],
          });
        },
        child: Text(editing ? 'Guardar cambios' : 'Crear y enviar acceso'),
      ),
    ],
  );
  Widget field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.inbox_outlined, size: 52, color: Colors.blueGrey.shade300),
        const SizedBox(height: 12),
        Text(text, style: const TextStyle(color: Color(0xFF64748B))),
      ],
    ),
  );
}
