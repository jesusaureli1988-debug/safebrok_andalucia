import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MisEquiposJefeVentasScreen extends StatefulWidget {
  const MisEquiposJefeVentasScreen({super.key});

  @override
  State<MisEquiposJefeVentasScreen> createState() =>
      _MisEquiposJefeVentasScreenState();
}

class _EstructuraNode {
  final Map<String, dynamic> usuario;
  final String rol;
  final int clientesPropios;
  final int ventasPropias;
  final List<_EstructuraNode> hijos;

  const _EstructuraNode({
    required this.usuario,
    required this.rol,
    required this.clientesPropios,
    required this.ventasPropias,
    required this.hijos,
  });

  int get totalPersonas {
    int total = 1;
    for (final hijo in hijos) {
      total += hijo.totalPersonas;
    }
    return total;
  }

  int get totalClientes {
    int total = clientesPropios;
    for (final hijo in hijos) {
      total += hijo.totalClientes;
    }
    return total;
  }

  int get totalVentas {
    int total = ventasPropias;
    for (final hijo in hijos) {
      total += hijo.totalVentas;
    }
    return total;
  }

  int contarRol(String rolBuscado) {
    int total = rol == rolBuscado ? 1 : 0;
    for (final hijo in hijos) {
      total += hijo.contarRol(rolBuscado);
    }
    return total;
  }
}

class _MisEquiposJefeVentasScreenState
    extends State<MisEquiposJefeVentasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String? error;

  Map<String, dynamic>? usuarioLogueado;
  _EstructuraNode? raiz;

  @override
  void initState() {
    super.initState();
    cargarEquipos();
  }

  String _normalizarRol(dynamic rol) {
    return (rol ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String? _rolHijoEsperado(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 'director_zona';
      case 'director_zona':
        return 'jefe_ventas';
      case 'jefe_ventas':
        return 'jefe_equipo';
      case 'jefe_equipo':
        return 'agente';
      default:
        return null;
    }
  }

  Future<void> cargarEquipos() async {
    try {
      if (mounted) {
        setState(() {
          loading = true;
          error = null;
        });
      }

      final authUser = supabase.auth.currentUser;

      if (authUser == null) {
        if (!mounted) return;
        setState(() {
          loading = false;
          error = 'No hay ningún usuario iniciado.';
        });
        return;
      }

      final perfilData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email, estado',
          )
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (perfilData == null) {
        if (!mounted) return;
        setState(() {
          loading = false;
          error = 'No se encontró el perfil del usuario conectado.';
        });
        return;
      }

      final perfil = Map<String, dynamic>.from(perfilData);

      final usuariosData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email, estado',
          );

      final usuarios = List<Map<String, dynamic>>.from(usuariosData);

      final authIds = usuarios
          .map((u) => u['auth_id']?.toString())
          .where(
            (id) =>
                id != null &&
                id.trim().isNotEmpty &&
                id.toLowerCase() != 'null',
          )
          .cast<String>()
          .toSet()
          .toList();

      final clientesPorAuth = <String, int>{};
      final ventasPorAuth = <String, int>{};

      if (authIds.isNotEmpty) {
        final clientesData = await supabase
            .from('clientes')
            .select('auth_id')
            .inFilter('auth_id', authIds);

        for (final item in clientesData as List) {
          final authId = item['auth_id']?.toString();
          if (authId == null || authId.isEmpty) continue;
          clientesPorAuth[authId] = (clientesPorAuth[authId] ?? 0) + 1;
        }

        final ventasData = await supabase
            .from('ventas')
            .select('agente_auth_id')
            .inFilter('agente_auth_id', authIds);

        for (final item in ventasData as List) {
          final authId = item['agente_auth_id']?.toString();
          if (authId == null || authId.isEmpty) continue;
          ventasPorAuth[authId] = (ventasPorAuth[authId] ?? 0) + 1;
        }
      }

      final usuariosPorParentId = <String, List<Map<String, dynamic>>>{};

      for (final usuario in usuarios) {
        final parentId = usuario['parent_id']?.toString().trim();

        if (parentId == null ||
            parentId.isEmpty ||
            parentId.toLowerCase() == 'null') {
          continue;
        }

        usuariosPorParentId
            .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
            .add(usuario);
      }

      _EstructuraNode construirNodo(
        Map<String, dynamic> usuario,
        Set<String> visitados,
      ) {
        final id = usuario['id']?.toString() ?? '';
        final authId = usuario['auth_id']?.toString() ?? '';
        final rol = _normalizarRol(usuario['rol_usuario']);

        if (id.isEmpty || visitados.contains(id)) {
          return _EstructuraNode(
            usuario: usuario,
            rol: rol,
            clientesPropios: clientesPorAuth[authId] ?? 0,
            ventasPropias: ventasPorAuth[authId] ?? 0,
            hijos: const [],
          );
        }

        final nuevosVisitados = {...visitados, id};
        final rolHijo = _rolHijoEsperado(rol);

        final hijosDirectos = rolHijo == null
            ? <Map<String, dynamic>>[]
            : (usuariosPorParentId[id] ?? <Map<String, dynamic>>[])
                .where(
                  (u) => _normalizarRol(u['rol_usuario']) == rolHijo,
                )
                .toList();

        final hijos = hijosDirectos
            .map((u) => construirNodo(u, nuevosVisitados))
            .toList();

        hijos.sort((a, b) {
          final ventas = b.totalVentas.compareTo(a.totalVentas);
          if (ventas != 0) return ventas;

          return _nombreCompleto(
            a.usuario,
          ).toLowerCase().compareTo(_nombreCompleto(b.usuario).toLowerCase());
        });

        return _EstructuraNode(
          usuario: usuario,
          rol: rol,
          clientesPropios: clientesPorAuth[authId] ?? 0,
          ventasPropias: ventasPorAuth[authId] ?? 0,
          hijos: hijos,
        );
      }

      final arbol = construirNodo(perfil, <String>{});

      debugPrint('----------------------------------------');
      debugPrint('MI ESTRUCTURA');
      debugPrint('USUARIO: ${_nombreCompleto(perfil)}');
      debugPrint('ROL: ${perfil['rol_usuario']}');
      debugPrint('ID: ${perfil['id']}');
      debugPrint('HIJOS DIRECTOS: ${arbol.hijos.length}');
      debugPrint('PERSONAS TOTALES: ${arbol.totalPersonas}');
      debugPrint('VENTAS TOTALES: ${arbol.totalVentas}');
      debugPrint('CLIENTES TOTALES: ${arbol.totalClientes}');

      if (!mounted) return;

      setState(() {
        usuarioLogueado = perfil;
        raiz = arbol;
        loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('ERROR CARGANDO ESTRUCTURA: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  String _nombreCompleto(Map<String, dynamic>? usuario) {
    if (usuario == null) return 'Sin nombre';

    final nombre = usuario['nombre']?.toString().trim() ?? '';
    final apellidos = usuario['apellidos']?.toString().trim() ?? '';
    final completo = '$nombre $apellidos'.trim();

    if (completo.isNotEmpty) return completo;

    return usuario['email']?.toString().trim().isNotEmpty == true
        ? usuario['email'].toString()
        : 'Sin nombre';
  }

  String _iniciales(String nombre) {
    final partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((parte) => parte.isNotEmpty)
        .toList();

    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();

    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }

  String _rolTexto(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return 'Director nacional';
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente';
      case 'administracion':
        return 'Administración';
      default:
        return rol.replaceAll('_', ' ');
    }
  }

  Color _rolColor(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return Colors.amberAccent;
      case 'director_zona':
        return Colors.deepPurpleAccent;
      case 'jefe_ventas':
        return Colors.purpleAccent;
      case 'jefe_equipo':
        return Colors.cyanAccent;
      case 'agente':
        return Colors.greenAccent;
      default:
        return Colors.blueAccent;
    }
  }

  IconData _rolIcono(String rol) {
    switch (_normalizarRol(rol)) {
      case 'director_nacional':
        return Icons.public_rounded;
      case 'director_zona':
        return Icons.map_rounded;
      case 'jefe_ventas':
        return Icons.workspace_premium_rounded;
      case 'jefe_equipo':
        return Icons.supervisor_account_rounded;
      case 'agente':
        return Icons.person_rounded;
      default:
        return Icons.badge_rounded;
    }
  }

  double _rendimientoNodo(_EstructuraNode node) {
    final agentes = node.contarRol('agente');

    final divisor = agentes > 0 ? agentes * 10 : 10;

    return (node.totalVentas / divisor).clamp(0.0, 1.0);
  }

  Color _rendimientoColor(double value) {
    if (value >= 0.75) return Colors.greenAccent;
    if (value >= 0.45) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _rendimientoTexto(double value) {
    if (value >= 0.75) return 'Estructura fuerte';
    if (value >= 0.45) return 'En crecimiento';
    return 'Necesita impulso';
  }

  int get totalDirectoresZona => raiz?.contarRol('director_zona') ?? 0;
  int get totalJefesVentas => raiz?.contarRol('jefe_ventas') ?? 0;
  int get totalJefesEquipo => raiz?.contarRol('jefe_equipo') ?? 0;
  int get totalAgentes => raiz?.contarRol('agente') ?? 0;
  int get totalClientes => raiz?.totalClientes ?? 0;
  int get totalVentas => raiz?.totalVentas ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _EquiposBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : RefreshIndicator(
                    color: Colors.cyanAccent,
                    backgroundColor: const Color(0xFF0F172A),
                    onRefresh: cargarEquipos,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
                      children: [
                        _header(),
                        const SizedBox(height: 20),
                        if (error != null)
                          _errorCard()
                        else if (raiz == null)
                          _emptyCard()
                        else ...[
                          _usuarioPrincipalCard(),
                          const SizedBox(height: 16),
                          _kpiResumen(),
                          const SizedBox(height: 20),
                          _sectionTitle(),
                          const SizedBox(height: 14),
                          if (raiz!.hijos.isEmpty)
                            _sinDependenciasCard(raiz!)
                          else
                            ...raiz!.hijos.map(
                              (nodo) => _nodoTreeCard(nodo, 0),
                            ),
                        ],
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
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 6,
          shadowColor: Colors.black45,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).maybePop(),
            child: const SizedBox(
              height: 54,
              width: 54,
              child: Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF020617),
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mi estructura',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Organigrama completo según el usuario conectado',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Actualizar estructura',
          onPressed: cargarEquipos,
          icon: Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.cyanAccent.withOpacity(0.12),
              border: Border.all(
                color: Colors.cyanAccent.withOpacity(0.38),
              ),
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: Colors.cyanAccent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _usuarioPrincipalCard() {
    final usuario = usuarioLogueado;
    final node = raiz!;
    final nombre = _nombreCompleto(usuario);
    final rol = _normalizarRol(usuario?['rol_usuario']);
    final color = _rolColor(rol);

    return _glassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          _avatar(nombre, color, size: 88),
          const SizedBox(height: 14),
          Text(
            nombre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          _rolPill(rol),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniPill(
                Icons.people_alt_rounded,
                '${node.clientesPropios} clientes propios',
                Colors.cyanAccent,
              ),
              _miniPill(
                Icons.trending_up_rounded,
                '${node.ventasPropias} ventas propias',
                Colors.greenAccent,
              ),
              _miniPill(
                Icons.account_tree_rounded,
                '${node.hijos.length} dependencias directas',
                color,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 40,
            width: 2,
            decoration: BoxDecoration(
              color: color.withOpacity(0.40),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Estructura comercial',
            style: TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiResumen() {
    final items = <Widget>[
      _kpiBox(
        title: 'Zonas',
        value: totalDirectoresZona.toString(),
        icon: Icons.map_rounded,
        color: Colors.deepPurpleAccent,
      ),
      _kpiBox(
        title: 'J. ventas',
        value: totalJefesVentas.toString(),
        icon: Icons.workspace_premium_rounded,
        color: Colors.purpleAccent,
      ),
      _kpiBox(
        title: 'J. equipo',
        value: totalJefesEquipo.toString(),
        icon: Icons.supervisor_account_rounded,
        color: Colors.cyanAccent,
      ),
      _kpiBox(
        title: 'Agentes',
        value: totalAgentes.toString(),
        icon: Icons.groups_rounded,
        color: Colors.greenAccent,
      ),
      _kpiBox(
        title: 'Clientes',
        value: totalClientes.toString(),
        icon: Icons.people_alt_rounded,
        color: Colors.lightBlueAccent,
      ),
      _kpiBox(
        title: 'Ventas',
        value: totalVentas.toString(),
        icon: Icons.trending_up_rounded,
        color: Colors.amberAccent,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final columnas = ancho >= 900
            ? 6
            : ancho >= 600
                ? 3
                : 3;

        final separacion = 10.0;
        final itemWidth =
            (ancho - (separacion * (columnas - 1))) / columnas;

        return Wrap(
          spacing: separacion,
          runSpacing: separacion,
          children: items
              .map((item) => SizedBox(width: itemWidth, child: item))
              .toList(),
        );
      },
    );
  }

  Widget _kpiBox({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.075),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle() {
    return Row(
      children: [
        const Icon(
          Icons.account_tree_rounded,
          color: Colors.cyanAccent,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Árbol de estructura',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          '${(raiz?.totalPersonas ?? 1) - 1} personas',
          style: const TextStyle(
            color: Colors.white54,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _nodoTreeCard(_EstructuraNode node, int level) {
    final nombre = _nombreCompleto(node.usuario);
    final color = _rolColor(node.rol);
    final rendimiento = _rendimientoNodo(node);
    final rendimientoColor = _rendimientoColor(rendimiento);

    return Container(
      margin: EdgeInsets.only(
        left: level == 0 ? 0 : 10,
        bottom: 14,
      ),
      child: _glassCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            key: PageStorageKey<String>(
              'estructura_${node.usuario['id']}_$level',
            ),
            initiallyExpanded: level == 0,
            tilePadding: const EdgeInsets.all(17),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 15),
            iconColor: color,
            collapsedIconColor: Colors.white70,
            title: Row(
              children: [
                _avatar(nombre, color, size: 54),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _rolPill(node.rol, compact: true),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 13),
              child: Column(
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _miniPill(
                        Icons.people_alt_rounded,
                        '${node.clientesPropios} clientes propios',
                        Colors.cyanAccent,
                      ),
                      _miniPill(
                        Icons.trending_up_rounded,
                        '${node.ventasPropias} ventas propias',
                        Colors.greenAccent,
                      ),
                      _miniPill(
                        Icons.account_tree_rounded,
                        '${node.hijos.length} directos',
                        color,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: rendimiento,
                            minHeight: 8,
                            backgroundColor: Colors.white.withOpacity(0.12),
                            valueColor: AlwaysStoppedAnimation(
                              rendimientoColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _rendimientoTexto(rendimiento),
                        style: TextStyle(
                          color: rendimientoColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            children: [
              _resumenNodo(node),
              if (node.hijos.isEmpty)
                _sinDependenciasCard(node)
              else ...[
                _treeConnector(color),
                ...node.hijos.map(
                  (hijo) => _nodoTreeCard(hijo, level + 1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _resumenNodo(_EstructuraNode node) {
    final color = _rolColor(node.rol);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        children: [
          _resumenDato(
            'Clientes propios',
            node.clientesPropios.toString(),
            Colors.cyanAccent,
          ),
          _resumenDato(
            'Ventas propias',
            node.ventasPropias.toString(),
            Colors.greenAccent,
          ),
          _resumenDato(
            'Clientes estructura',
            node.totalClientes.toString(),
            Colors.lightBlueAccent,
          ),
          _resumenDato(
            'Ventas estructura',
            node.totalVentas.toString(),
            Colors.amberAccent,
          ),
          _resumenDato(
            'Personas',
            node.totalPersonas.toString(),
            color,
          ),
        ],
      ),
    );
  }

  Widget _resumenDato(String label, String value, Color color) {
    return SizedBox(
      width: 118,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _treeConnector(Color color) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 26, bottom: 8),
        width: 2,
        height: 25,
        decoration: BoxDecoration(
          color: color.withOpacity(0.35),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _rolPill(String rol, {bool compact = false}) {
    final color = _rolColor(rol);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 14,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _rolIcono(rol),
            color: color,
            size: compact ? 14 : 17,
          ),
          SizedBox(width: compact ? 5 : 7),
          Flexible(
            child: Text(
              _rolTexto(rol),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 11 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String nombre, Color color, {double size = 50}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.34),
            Colors.blueAccent.withOpacity(0.16),
          ],
        ),
        border: Border.all(color: color.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 16,
          ),
        ],
      ),
      child: Center(
        child: Text(
          _iniciales(nombre),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _miniPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.27)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sinDependenciasCard(_EstructuraNode node) {
    final siguienteRol = _rolHijoEsperado(node.rol);
    final mensaje = siguienteRol == null
        ? 'Este usuario no tiene niveles inferiores en la jerarquía.'
        : 'No tiene ${_rolTexto(siguienteRol).toLowerCase()} asignados directamente.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Colors.white54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: Colors.white60,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return _glassCard(
      child: const Column(
        children: [
          Icon(
            Icons.account_tree_outlined,
            color: Colors.white38,
            size: 64,
          ),
          SizedBox(height: 12),
          Text(
            'Sin estructura disponible',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'No se ha podido construir el árbol del usuario conectado.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return _glassCard(
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.orangeAccent,
            size: 52,
          ),
          const SizedBox(height: 12),
          const Text(
            'No se pudo cargar la estructura',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white60,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
    EdgeInsets? margin,
  }) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.075),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _EquiposBackground extends StatelessWidget {
  const _EquiposBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF020617),
                Color(0xFF061A2D),
                Color(0xFF0B1026),
              ],
            ),
          ),
        ),
        Positioned(
          top: -110,
          right: -90,
          child: _glow(260, Colors.cyanAccent),
        ),
        Positioned(
          bottom: 160,
          left: -120,
          child: _glow(280, Colors.purpleAccent),
        ),
        Positioned(
          bottom: -120,
          right: -80,
          child: _glow(240, Colors.blueAccent),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.15),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.20),
            blurRadius: 120,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}