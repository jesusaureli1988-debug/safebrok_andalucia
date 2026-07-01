import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DirectorNacionalUsuariosScreen extends StatefulWidget {
  const DirectorNacionalUsuariosScreen({super.key});

  @override
  State<DirectorNacionalUsuariosScreen> createState() =>
      _DirectorNacionalUsuariosScreenState();
}

class _DirectorNacionalUsuariosScreenState
    extends State<DirectorNacionalUsuariosScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;

  List<Map<String, dynamic>> usuarios = [];

  String searchText = '';
  String selectedRole = 'Todos';

  final roles = const [
  'Todos',
  'director_nacional',
  'director_zona',
  'jefe_ventas',
  'jefe_equipo',
  'agente',
  'administracion',
];

  @override
  void initState() {
    super.initState();
    cargarUsuarios();
  }

  Future<void> cargarUsuarios() async {
    try {
      setState(() => loading = true);

      final data = await supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos, email, telefono')
          .order('rol_usuario', ascending: true);

      usuarios = List<Map<String, dynamic>>.from(data);

      debugPrint('USUARIOS CARGADOS: ${usuarios.length}');
for (final u in usuarios) {
  debugPrint('ROL USUARIO: ${u['rol_usuario']}');
}

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      debugPrint('ERROR USUARIOS DIRECTOR NACIONAL: $e');

      if (!mounted) return;
      setState(() {
        usuarios = [];
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get usuariosFiltrados {
  return usuarios.where((u) {
    final role = (u['rol_usuario'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    final selected = selectedRole
        .toLowerCase()
        .trim();

    final nombre =
        "${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}".toLowerCase().trim();

    final email = (u['email'] ?? '').toString().toLowerCase().trim();
    final telefono = (u['telefono'] ?? '').toString().toLowerCase().trim();

    final query = searchText.toLowerCase().trim();

    final matchRole = selected == 'todos' || role == selected;

    final matchSearch = query.isEmpty ||
        nombre.contains(query) ||
        email.contains(query) ||
        telefono.contains(query) ||
        role.contains(query) ||
        _roleName(role).toLowerCase().contains(query);

    return matchRole && matchSearch;
  }).toList();
}

  Map<String, dynamic>? _parentOf(Map<String, dynamic> user) {
    final parentId = user['parent_id']?.toString();

    if (parentId == null || parentId.isEmpty || parentId == 'null') {
      return null;
    }

    try {
      return usuarios.firstWhere(
        (u) => u['id']?.toString() == parentId,
      );
    } catch (_) {
      return null;
    }
  }

  int _countRole(String role) {
    return usuarios.where((u) => u['rol_usuario'] == role).length;
  }

  int _childrenCount(String id) {
    return usuarios.where((u) => u['parent_id']?.toString() == id).length;
  }

  String _fullName(Map<String, dynamic> u) {
    final name = "${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}".trim();
    return name.isEmpty ? 'Usuario sin nombre' : name;
  }

  String _roleName(String role) {
    switch (role) {
      case 'director_nacional':
        return 'Director nacional';
      case 'director_zona':
        return 'Director zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente comercial';
      case 'administracion':
        return 'Administración';
      default:
        return 'Usuario';
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'director_nacional':
        return Colors.cyanAccent;
      case 'director_zona':
        return Colors.blueAccent;
      case 'jefe_ventas':
        return Colors.purpleAccent;
      case 'jefe_equipo':
        return Colors.greenAccent;
      case 'agente':
        return Colors.amberAccent;
      case 'administracion':
        return Colors.orangeAccent;
      default:
        return Colors.white70;
    }
  }

  int _roleLevel(String role) {
    switch (role) {
      case 'director_nacional':
        return 0;
      case 'director_zona':
        return 1;
      case 'jefe_ventas':
        return 2;
      case 'jefe_equipo':
        return 3;
      case 'agente':
        return 4;
      case 'administracion':
        return 1;
      default:
        return 5;
    }
  }

  List<Map<String, dynamic>> get usuariosOrdenados {
    final list = [...usuariosFiltrados];

    list.sort((a, b) {
      final roleA = _roleLevel(a['rol_usuario']?.toString() ?? '');
      final roleB = _roleLevel(b['rol_usuario']?.toString() ?? '');

      final compareRole = roleA.compareTo(roleB);
      if (compareRole != 0) return compareRole;

      return _fullName(a).compareTo(_fullName(b));
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _UsuariosBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : RefreshIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF071A3A),
                    onRefresh: cargarUsuarios,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _topBar()),
                        SliverToBoxAdapter(child: _hero()),
                        SliverToBoxAdapter(child: _summaryGrid()),
                        SliverToBoxAdapter(child: _filters()),
                        usuariosOrdenados.isEmpty
                            ? SliverFillRemaining(
                                hasScrollBody: false,
                                child: _emptyState(),
                              )
                            : SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(18, 8, 18, 40),
                                sliver: SliverList.builder(
                                  itemCount: usuariosOrdenados.length,
                                  itemBuilder: (context, index) {
                                    return _userCard(
                                      usuariosOrdenados[index],
                                      index,
                                    );
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

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.08),
              fixedSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Estructura nacional',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF22D3EE),
                  Color(0xFF2563EB),
                  Color(0xFF7C3AED),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.account_tree_rounded,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.cyanAccent.withOpacity(0.20),
                  const Color(0xFF071A3A).withOpacity(0.94),
                  const Color(0xFF020617).withOpacity(0.96),
                ],
              ),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.25),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -18,
                  bottom: -25,
                  child: Icon(
                    Icons.hub_rounded,
                    size: 145,
                    color: Colors.cyanAccent.withOpacity(0.08),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mapa completo de la red',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Control visual de directores, jefes de ventas, jefes de equipo, agentes y administración.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        _heroChip(
                          Icons.people_alt_rounded,
                          '${usuarios.length} usuarios',
                          Colors.cyanAccent,
                        ),
                        const SizedBox(width: 10),
                        _heroChip(
                          Icons.account_tree_rounded,
                          '${_countRole('agente')} agentes',
                          Colors.greenAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroChip(IconData icon, String text, Color color) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.13),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: color.withOpacity(0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: GridView.count(
        crossAxisCount: 2,
        childAspectRatio: 1.35,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        children: [
          _summaryCard(
            'Directores zona',
            _countRole('director_zona').toString(),
            Icons.map_rounded,
            Colors.blueAccent,
          ),
          _summaryCard(
            'Jefes ventas',
            _countRole('jefe_ventas').toString(),
            Icons.business_center_rounded,
            Colors.purpleAccent,
          ),
          _summaryCard(
            'Jefes equipo',
            _countRole('jefe_equipo').toString(),
            Icons.groups_2_rounded,
            Colors.greenAccent,
          ),
          _summaryCard(
            'Agentes',
            _countRole('agente').toString(),
            Icons.person_rounded,
            Colors.amberAccent,
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color),
      child: Row(
        children: [
          _bubble(icon, color),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => searchText = v),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            cursorColor: Colors.cyanAccent,
            decoration: InputDecoration(
              hintText: 'Buscar usuario, email, teléfono o rol...',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.42),
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.cyanAccent,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.07),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide(
                  color: Colors.cyanAccent.withOpacity(0.45),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.075),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.18),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_alt_rounded,
                  color: Colors.cyanAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedRole,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF071A3A),
                      iconEnabledColor: Colors.cyanAccent,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                      items: roles
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                e == 'Todos' ? 'Todos los roles' : _roleName(e),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => selectedRole = v);
                      },
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

  Widget _userCard(Map<String, dynamic> u, int index) {
    final role = u['rol_usuario']?.toString() ?? '';
    final color = _roleColor(role);
    final parent = _parentOf(u);
    final id = u['id']?.toString() ?? '';
    final children = _childrenCount(id);

    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: EdgeInsets.fromLTRB(
        16 + (_roleLevel(role).clamp(0, 4) * 7),
        16,
        16,
        16,
      ),
      decoration: _cardDecoration(color),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withOpacity(0.30),
              ),
            ),
            child: Center(
              child: Text(
                _fullName(u)[0].toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName(u),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _tag(Icons.badge_rounded, _roleName(role), color),
                    if (parent != null)
                      _tag(
                        Icons.account_tree_rounded,
                        'Depende de ${_fullName(parent)}',
                        Colors.cyanAccent,
                      ),
                    if (children > 0)
                      _tag(
                        Icons.groups_rounded,
                        '$children debajo',
                        Colors.greenAccent,
                      ),
                    if ((u['email'] ?? '').toString().isNotEmpty)
                      _tag(
                        Icons.mail_rounded,
                        u['email'].toString(),
                        Colors.white70,
                      ),
                    if ((u['telefono'] ?? '').toString().isNotEmpty)
                      _tag(
                        Icons.phone_rounded,
                        u['telefono'].toString(),
                        Colors.white70,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: color.withOpacity(0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          'No hay usuarios con estos filtros.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.65),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _bubble(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.28),
        ),
      ),
      child: Icon(icon, color: color),
    );
  }

  BoxDecoration _cardDecoration(Color color) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          color.withOpacity(0.18),
          const Color(0xFF071A3A).withOpacity(0.92),
          const Color(0xFF020617).withOpacity(0.96),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(
        color: color.withOpacity(0.28),
      ),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.08),
          blurRadius: 22,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }
}

class _UsuariosBackground extends StatelessWidget {
  const _UsuariosBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFF020617)),
        Positioned(
          top: -120,
          right: -90,
          child: _glow(const Color(0xFF22D3EE), 300),
        ),
        Positioned(
          top: 300,
          left: -140,
          child: _glow(const Color(0xFF7C3AED), 320),
        ),
        Positioned(
          bottom: -140,
          right: -110,
          child: _glow(const Color(0xFF22C55E), 300),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
          child: Container(
            color: Colors.black.withOpacity(0.08),
          ),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        shape: BoxShape.circle,
      ),
    );
  }
}