import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReasignarMediadorScreen extends StatefulWidget {
  const ReasignarMediadorScreen({super.key});

  @override
  State<ReasignarMediadorScreen> createState() =>
      _ReasignarMediadorScreenState();
}

class _ReasignarMediadorScreenState extends State<ReasignarMediadorScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool guardando = false;

  String role = '';
  String? myId;
  String? myAuthId;

  List<Map<String, dynamic>> usuarios = [];
  List<Map<String, dynamic>> mediadores = [];
  List<Map<String, dynamic>> jefesEquipo = [];

  Map<String, dynamic>? mediadorSeleccionado;
  Map<String, dynamic>? jefeSeleccionado;

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

    print('ROLE ACTUAL: $role');
    print('MI ID: $myId');

    final data = await supabase
        .from('usuarios')
        .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos, email')
        .order('nombre', ascending: true);

    usuarios = List<Map<String, dynamic>>.from(data);

    print('TOTAL USUARIOS: ${usuarios.length}');

    List<Map<String, dynamic>> listaPermitida = [];

    if (role == 'director_nacional' || role == 'administracion') {
      listaPermitida = usuarios;
      print('VE TODA LA RED');
    } else {
      final idsPermitidos = _idsEstructuraPermitida();

      print('IDS PERMITIDOS: $idsPermitidos');

      listaPermitida = usuarios.where((u) {
        final id = u['id']?.toString();
        return id != null && idsPermitidos.contains(id);
      }).toList();
    }

    mediadores = listaPermitida.where((u) {
      final r = u['rol_usuario']?.toString().trim();

      return r == 'agente' ||
          r == 'mediador' ||
          r == 'comercial';
    }).toList();

    jefesEquipo = listaPermitida.where((u) {
      final r = u['rol_usuario']?.toString().trim();

      return r == 'jefe_equipo';
    }).toList();

    print('MEDIADORES CARGADOS: ${mediadores.length}');
    print('JEFES EQUIPO CARGADOS: ${jefesEquipo.length}');

    if (!mounted) return;

    setState(() => loading = false);
  } catch (e) {
    print('ERROR CARGAR REASIGNAR MEDIADOR: $e');

    if (!mounted) return;

    setState(() => loading = false);
    _snack('Error cargando datos: $e');
  }
}

  bool _veTodaLaRed() {
    return role == 'director_nacional' || role == 'administracion';
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

  List<Map<String, dynamic>> get mediadoresFiltrados {
  final text = busqueda.toLowerCase().trim();

  if (text.isEmpty) return mediadores;

  return mediadores.where((u) {
    final nombre = u['nombre']?.toString().toLowerCase() ?? '';
    final email = u['email']?.toString().toLowerCase() ?? '';

    return nombre.contains(text) || email.contains(text);
  }).toList();
}

  String _nombreJefeActual(Map<String, dynamic> mediador) {
    final parentId = mediador['parent_id']?.toString();

    if (parentId == null || parentId.isEmpty) return 'Sin jefe asignado';

    final jefe = usuarios.firstWhere(
      (u) => u['id']?.toString() == parentId,
      orElse: () => {},
    );

    return jefe['nombre']?.toString() ?? 'Sin jefe asignado';
  }

  Future<void> reasignar() async {
    if (mediadorSeleccionado == null || jefeSeleccionado == null) {
      _snack('Selecciona un mediador y un jefe de equipo');
      return;
    }

    final mediadorId = mediadorSeleccionado!['id']?.toString();
    final jefeId = jefeSeleccionado!['id']?.toString();

    if (mediadorId == null || jefeId == null) {
      _snack('Faltan datos para reasignar');
      return;
    }

    if (mediadorSeleccionado!['parent_id']?.toString() == jefeId) {
      _snack('Ese mediador ya pertenece a ese jefe de equipo');
      return;
    }

    setState(() => guardando = true);

    try {
      await supabase.from('usuarios').update({
        'parent_id': jefeId,
      }).eq('id', mediadorId);

      await supabase.from('historial_reasignaciones').insert({
        'tipo': 'reasignar_mediador',
        'usuario_id': mediadorId,
        'usuario_nombre': mediadorSeleccionado!['nombre']?.toString(),
        'jefe_anterior_id': mediadorSeleccionado!['parent_id']?.toString(),
        'jefe_nuevo_id': jefeId,
        'jefe_nuevo_nombre': jefeSeleccionado!['nombre']?.toString(),
        'realizado_por_auth_id': myAuthId,
        'realizado_por_rol': role,
        'created_at': DateTime.now().toIso8601String(),
      });

      _snack('Mediador reasignado correctamente');

      mediadorSeleccionado = null;
      jefeSeleccionado = null;

      await cargarDatos();
    } catch (e) {
      _snack('Error reasignando mediador: $e');
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoReasignar(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0284C7),
                    ),
                  )
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
                                child: _panelMediadores(),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 4,
                                child: _panelJefes(),
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
                'Reasignar mediador',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Mueve mediadores entre jefes de equipo respetando la estructura comercial.',
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

  Widget _panelMediadores() {
    return _glassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.person_search_rounded,
            title: 'Mediadores',
            subtitle: '${mediadores.length} disponibles',
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => busqueda = v),
            decoration: InputDecoration(
              hintText: 'Buscar mediador...',
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
            child: mediadoresFiltrados.isEmpty
                ? _empty('No hay mediadores en tu estructura')
                : ListView.builder(
                    itemCount: mediadoresFiltrados.length,
                    itemBuilder: (context, index) {
                      final m = mediadoresFiltrados[index];
                      final selected =
                          mediadorSeleccionado?['id']?.toString() ==
                              m['id']?.toString();

                      return _userCard(
                        user: m,
                        selected: selected,
                        subtitle: 'Jefe actual: ${_nombreJefeActual(m)}',
                        icon: Icons.person_rounded,
                        color: const Color(0xFF0284C7),
                        onTap: () {
                          setState(() => mediadorSeleccionado = m);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _panelJefes() {
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
          Expanded(
            child: jefesEquipo.isEmpty
                ? _empty('No hay jefes de equipo disponibles')
                : ListView.builder(
                    itemCount: jefesEquipo.length,
                    itemBuilder: (context, index) {
                      final j = jefesEquipo[index];
                      final selected =
                          jefeSeleccionado?['id']?.toString() ==
                              j['id']?.toString();

                      return _userCard(
                        user: j,
                        selected: selected,
                        subtitle: 'Jefe de equipo',
                        icon: Icons.supervisor_account_rounded,
                        color: const Color(0xFF16A34A),
                        onTap: () {
                          setState(() => jefeSeleccionado = j);
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
    final mediador = mediadorSeleccionado;
    final jefe = jefeSeleccionado;

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
            title: 'Mediador seleccionado',
            value: mediador?['nombre']?.toString() ?? 'Sin seleccionar',
            icon: Icons.person_rounded,
            color: const Color(0xFF0284C7),
          ),
          const SizedBox(height: 14),
          _resumenBox(
            title: 'Jefe actual',
            value: mediador == null
                ? 'Sin seleccionar'
                : _nombreJefeActual(mediador),
            icon: Icons.account_tree_rounded,
            color: const Color(0xFFF97316),
          ),
          const SizedBox(height: 14),
          _resumenBox(
            title: 'Nuevo jefe de equipo',
            value: jefe?['nombre']?.toString() ?? 'Sin seleccionar',
            icon: Icons.supervisor_account_rounded,
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
                    'Esta acción cambiará la dependencia del mediador dentro de la estructura.',
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
    final nombre = user['nombre']?.toString() ?? '';
final apellidos = user['apellidos']?.toString() ?? '';
final nombreCompleto = '$nombre $apellidos'.trim();

final nombreMostrar =
    nombreCompleto.isEmpty ? 'Sin nombre' : nombreCompleto;
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

class _FondoReasignar extends StatelessWidget {
  const _FondoReasignar();

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