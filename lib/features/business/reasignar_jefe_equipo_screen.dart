import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReasignarJefeEquipoScreen extends StatefulWidget {
  const ReasignarJefeEquipoScreen({super.key});

  @override
  State<ReasignarJefeEquipoScreen> createState() =>
      _ReasignarJefeEquipoScreenState();
}

class _ReasignarJefeEquipoScreenState
    extends State<ReasignarJefeEquipoScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool guardando = false;

  String role = '';
  String? myId;
  String? myAuthId;

  List<Map<String, dynamic>> usuarios = [];
  List<Map<String, dynamic>> jefesEquipo = [];
  List<Map<String, dynamic>> jefesVentas = [];

  Map<String, dynamic>? jefeEquipoSeleccionado;
  Map<String, dynamic>? jefeVentasSeleccionado;

  String busqueda = '';

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  Future<void> cargarDatos() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      final perfil = await supabase
          .from('usuarios')
          .select('id, auth_id, rol_usuario, parent_id, nombre, apellidos, email')
          .eq('auth_id', user.id)
          .maybeSingle();

      role = perfil?['rol_usuario']?.toString() ?? '';
      myId = perfil?['id']?.toString();
      myAuthId = perfil?['auth_id']?.toString();

      final data = await supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos, email')
          .order('nombre', ascending: true);

      usuarios = List<Map<String, dynamic>>.from(data);

      List<Map<String, dynamic>> listaPermitida = [];

      if (role == 'director_nacional' || role == 'administracion') {
        listaPermitida = usuarios;
      } else {
        final idsPermitidos = _idsEstructuraPermitida();

        listaPermitida = usuarios.where((u) {
          final id = u['id']?.toString();
          return id != null && idsPermitidos.contains(id);
        }).toList();
      }

      jefesEquipo = listaPermitida.where((u) {
        final r = u['rol_usuario']?.toString().trim();
        return r == 'jefe_equipo';
      }).toList();

      jefesVentas = listaPermitida.where((u) {
        final r = u['rol_usuario']?.toString().trim();
        return r == 'jefe_ventas';
      }).toList();

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _snack('Error cargando datos: $e');
    }
  }

  Set<String> _idsEstructuraPermitida() {
    final Set<String> ids = {};

    if (myId == null || myId!.isEmpty) return ids;

    ids.add(myId!);

    bool hayCambios = true;

    while (hayCambios) {
      hayCambios = false;

      for (final u in usuarios) {
        final id = u['id']?.toString();
        final parentId = u['parent_id']?.toString();

        if (id == null || id.isEmpty) continue;
        if (parentId == null || parentId.isEmpty) continue;

        if (ids.contains(parentId) && !ids.contains(id)) {
          ids.add(id);
          hayCambios = true;
        }
      }
    }

    return ids;
  }

  List<Map<String, dynamic>> get jefesEquipoFiltrados {
    final text = busqueda.toLowerCase().trim();

    if (text.isEmpty) return jefesEquipo;

    return jefesEquipo.where((u) {
      final nombre = u['nombre']?.toString().toLowerCase() ?? '';
      final apellidos = u['apellidos']?.toString().toLowerCase() ?? '';
      final email = u['email']?.toString().toLowerCase() ?? '';

      return nombre.contains(text) ||
          apellidos.contains(text) ||
          email.contains(text);
    }).toList();
  }

  String _nombreCompleto(Map<String, dynamic> user) {
    final nombre = user['nombre']?.toString() ?? '';
    final apellidos = user['apellidos']?.toString() ?? '';
    final completo = '$nombre $apellidos'.trim();

    return completo.isEmpty ? 'Sin nombre' : completo;
  }

  String _nombreJefeVentasActual(Map<String, dynamic> jefeEquipo) {
    final parentId = jefeEquipo['parent_id']?.toString();

    if (parentId == null || parentId.isEmpty) return 'Sin jefe de ventas';

    final jefe = usuarios.firstWhere(
      (u) => u['id']?.toString() == parentId,
      orElse: () => {},
    );

    if (jefe.isEmpty) return 'Sin jefe de ventas';

    return _nombreCompleto(jefe);
  }

  Future<void> reasignar() async {
    if (jefeEquipoSeleccionado == null || jefeVentasSeleccionado == null) {
      _snack('Selecciona un jefe de equipo y un jefe de ventas');
      return;
    }

    final jefeEquipoId = jefeEquipoSeleccionado!['id']?.toString();
    final jefeVentasId = jefeVentasSeleccionado!['id']?.toString();

    if (jefeEquipoId == null || jefeVentasId == null) {
      _snack('Faltan datos para reasignar');
      return;
    }

    if (jefeEquipoSeleccionado!['parent_id']?.toString() == jefeVentasId) {
      _snack('Ese jefe de equipo ya pertenece a ese jefe de ventas');
      return;
    }

    setState(() => guardando = true);

    try {
      await supabase.from('usuarios').update({
        'parent_id': jefeVentasId,
      }).eq('id', jefeEquipoId);

      await supabase.from('historial_reasignaciones').insert({
        'tipo': 'reasignar_jefe_equipo',
        'usuario_id': jefeEquipoId,
        'usuario_nombre': _nombreCompleto(jefeEquipoSeleccionado!),
        'jefe_anterior_id': jefeEquipoSeleccionado!['parent_id']?.toString(),
        'jefe_nuevo_id': jefeVentasId,
        'jefe_nuevo_nombre': _nombreCompleto(jefeVentasSeleccionado!),
        'realizado_por_auth_id': myAuthId,
        'realizado_por_rol': role,
        'created_at': DateTime.now().toIso8601String(),
      });

      _snack('Jefe de equipo reasignado correctamente');

      jefeEquipoSeleccionado = null;
      jefeVentasSeleccionado = null;

      await cargarDatos();
    } catch (e) {
      _snack('Error reasignando jefe de equipo: $e');
    }

    if (mounted) {
      setState(() => guardando = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = role == 'jefe_ventas';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoReasignarJefe(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0284C7),
                    ),
                  )
                : bloqueado
                    ? _pantallaBloqueada()
                    : Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            _header(),
                            const SizedBox(height: 18),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _panelJefesEquipo(),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    flex: 4,
                                    child: _panelJefesVentas(),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    flex: 4,
                                    child: _panelResumen(),
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
  }

  Widget _pantallaBloqueada() {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _header(),
          const SizedBox(height: 18),
          Expanded(
            child: _glassPanel(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        color: Color(0xFFDC2626),
                        size: 52,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Módulo restringido',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'El jefe de ventas puede ver el acceso, pero no puede reasignar jefes de equipo a otros jefes de ventas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueGrey.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reasignar jefe de equipo',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Mueve jefes de equipo entre jefes de ventas respetando la estructura.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        _roleBadge(),
      ],
    );
  }

  Widget _roleBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7DD3FC)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF0284C7),
          ),
          const SizedBox(width: 8),
          Text(
            role.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF075985),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelJefesEquipo() {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.groups_rounded,
            title: 'Jefes de equipo',
            subtitle: '${jefesEquipo.length} disponibles',
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => busqueda = v),
            decoration: InputDecoration(
              hintText: 'Buscar jefe de equipo...',
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF0284C7),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: jefesEquipoFiltrados.isEmpty
                ? _empty('No hay jefes de equipo en tu estructura')
                : ListView.builder(
                    itemCount: jefesEquipoFiltrados.length,
                    itemBuilder: (context, index) {
                      final j = jefesEquipoFiltrados[index];
                      final selected =
                          jefeEquipoSeleccionado?['id']?.toString() ==
                              j['id']?.toString();

                      return _userCard(
                        user: j,
                        selected: selected,
                        subtitle:
                            'Jefe ventas actual: ${_nombreJefeVentasActual(j)}',
                        icon: Icons.supervisor_account_rounded,
                        color: const Color(0xFF0284C7),
                        onTap: () {
                          setState(() => jefeEquipoSeleccionado = j);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _panelJefesVentas() {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.manage_accounts_rounded,
            title: 'Jefes de ventas',
            subtitle: '${jefesVentas.length} disponibles',
          ),
          const SizedBox(height: 14),
          Expanded(
            child: jefesVentas.isEmpty
                ? _empty('No hay jefes de ventas disponibles')
                : ListView.builder(
                    itemCount: jefesVentas.length,
                    itemBuilder: (context, index) {
                      final j = jefesVentas[index];
                      final selected =
                          jefeVentasSeleccionado?['id']?.toString() ==
                              j['id']?.toString();

                      return _userCard(
                        user: j,
                        selected: selected,
                        subtitle: 'Jefe de ventas',
                        icon: Icons.manage_accounts_rounded,
                        color: const Color(0xFF16A34A),
                        onTap: () {
                          setState(() => jefeVentasSeleccionado = j);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _panelResumen() {
    final jefeEquipo = jefeEquipoSeleccionado;
    final jefeVentas = jefeVentasSeleccionado;

    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.swap_horiz_rounded,
            title: 'Resumen',
            subtitle: 'Confirma la reasignación',
          ),
          const SizedBox(height: 22),
          _resumenBox(
            title: 'Jefe de equipo',
            value: jefeEquipo == null
                ? 'Sin seleccionar'
                : _nombreCompleto(jefeEquipo),
            icon: Icons.supervisor_account_rounded,
            color: const Color(0xFF0284C7),
          ),
          const SizedBox(height: 14),
          _resumenBox(
            title: 'Jefe de ventas actual',
            value: jefeEquipo == null
                ? 'Sin seleccionar'
                : _nombreJefeVentasActual(jefeEquipo),
            icon: Icons.account_tree_rounded,
            color: const Color(0xFFF97316),
          ),
          const SizedBox(height: 14),
          _resumenBox(
            title: 'Nuevo jefe de ventas',
            value: jefeVentas == null
                ? 'Sin seleccionar'
                : _nombreCompleto(jefeVentas),
            icon: Icons.manage_accounts_rounded,
            color: const Color(0xFF16A34A),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_rounded,
                  color: Color(0xFFD97706),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Esta acción cambiará el parent_id del jefe de equipo al nuevo jefe de ventas.',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: guardando ? null : reasignar,
              icon: guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(
                guardando ? 'Guardando...' : 'Confirmar reasignación',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 17),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userCard({
    required Map<String, dynamic> user,
    required bool selected,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final nombreMostrar = _nombreCompleto(user);
    final email = user['email']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : const Color(0xFFE2E8F0),
              width: selected ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blueGrey.withOpacity(0.07),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withOpacity(0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombreMostrar,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: color,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resumenBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0284C7)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty(String text) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _glassPanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.11),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FondoReasignarJefe extends StatelessWidget {
  const _FondoReasignarJefe();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFFF4F7FB)),
        Positioned(
          top: -120,
          right: -100,
          child: _orb(310, const Color(0xFF7DD3FC)),
        ),
        Positioned(
          bottom: -140,
          left: -130,
          child: _orb(350, const Color(0xFFC4B5FD)),
        ),
      ],
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.42),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 120,
            spreadRadius: 35,
          ),
        ],
      ),
    );
  }
}