import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';
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
  final double primasPropias;
  final double mixPropio;
  final List<_EstructuraNode> hijos;

  const _EstructuraNode({
    required this.usuario,
    required this.rol,
    required this.primasPropias,
    required this.mixPropio,
    required this.hijos,
  });

  int get totalPersonas {
    int total = 1;
    for (final hijo in hijos) {
      total += hijo.totalPersonas;
    }
    return total;
  }

  bool _incluyeCargo(String cargo) => cargo == 'todos' || rol == cargo;

  double primasEstructura(String cargo) {
    double total = _incluyeCargo(cargo) ? primasPropias : 0;
    for (final hijo in hijos) {
      total += hijo.primasEstructura(cargo);
    }
    return total;
  }

  double mixEstructura(String cargo) {
    double total = _incluyeCargo(cargo) ? mixPropio : 0;
    for (final hijo in hijos) {
      total += hijo.mixEstructura(cargo);
    }
    return total;
  }

  double porcentajeMix(String cargo) {
    final primas = primasEstructura(cargo);
    return primas <= 0 ? 0 : (mixEstructura(cargo) / primas) * 100;
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
  DateTime periodo = DateTime(DateTime.now().year, DateTime.now().month);
  String cargoSeleccionado = 'todos';

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
          .or(
            'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
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
          )
          .or(
            'estado.is.null,estado.not.in.(inactivo,Inactivo,INACTIVO,baja,Baja,BAJA,desactivado,Desactivado,DESACTIVADO,bloqueado,Bloqueado,BLOQUEADO,suspendido,Suspendido,SUSPENDIDO)',
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

      final primasPorAuth = <String, double>{};
      final mixPorAuth = <String, double>{};

      if (authIds.isNotEmpty) {
        final finPeriodo = DateTime(periodo.year, periodo.month + 1);
        final ventasData = await supabase
            .from('ventas')
            .select()
            .inFilter('agente_auth_id', authIds)
            .gte('fecha_efecto', periodo.toIso8601String())
            .lt('fecha_efecto', finPeriodo.toIso8601String());

        for (final raw in ventasData as List) {
          final venta = Map<String, dynamic>.from(raw as Map);
          if (!_ventaProductiva(venta)) continue;
          final authId = venta['agente_auth_id']?.toString();
          if (authId == null || authId.isEmpty) continue;
          final prima = PremiumWeighting.net(venta);
          primasPorAuth[authId] = (primasPorAuth[authId] ?? 0) + prima;
          if (_esMix(venta)) {
            mixPorAuth[authId] = (mixPorAuth[authId] ?? 0) + prima;
          }
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
            primasPropias: primasPorAuth[authId] ?? 0,
            mixPropio: mixPorAuth[authId] ?? 0,
            hijos: const [],
          );
        }

        final nuevosVisitados = {...visitados, id};

        final hijosDirectos = List<Map<String, dynamic>>.from(
          usuariosPorParentId[id] ?? <Map<String, dynamic>>[],
        );

        debugPrint(
          '➡️ ${_nombreCompleto(usuario)} '
          '| rol=$rol '
          '| hijos directos=${hijosDirectos.length}',
        );

        for (final hijo in hijosDirectos) {
          debugPrint(
            '   ✔ ${_nombreCompleto(hijo)} '
            '| rol=${hijo['rol_usuario']} '
            '| parent_id=${hijo['parent_id']}',
          );
        }

        final hijos = hijosDirectos
            .map((hijo) => construirNodo(hijo, nuevosVisitados))
            .toList();

        hijos.sort((a, b) {
          final ventas = b
              .primasEstructura(cargoSeleccionado)
              .compareTo(a.primasEstructura(cargoSeleccionado));
          if (ventas != 0) return ventas;

          return _nombreCompleto(
            a.usuario,
          ).toLowerCase().compareTo(_nombreCompleto(b.usuario).toLowerCase());
        });

        return _EstructuraNode(
          usuario: usuario,
          rol: rol,
          primasPropias: primasPorAuth[authId] ?? 0,
          mixPropio: mixPorAuth[authId] ?? 0,
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
      debugPrint(
        'PRIMAS ESTRUCTURA: ${arbol.primasEstructura(cargoSeleccionado)}',
      );
      debugPrint('MIX ESTRUCTURA: ${arbol.porcentajeMix(cargoSeleccionado)}%');

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
        return const Color(0xFF2563EB);
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

  bool _ventaProductiva(Map<String, dynamic> venta) {
    final estado = [
      venta['estado'],
      venta['estado_poliza'],
      venta['tipo_movimiento'],
      venta['situacion'],
    ].join(' ').toLowerCase();
    return !const [
      'baja',
      'extorno',
      'anulada',
      'anulado',
      'cancelada',
      'cancelado',
    ].any(estado.contains);
  }

  bool _esMix(Map<String, dynamic> venta) {
    final producto =
        (venta['producto'] ?? venta['ramo'] ?? venta['tipo_seguro'] ?? '')
            .toString()
            .trim()
            .toLowerCase()
            .replaceAll('á', 'a')
            .replaceAll('é', 'e')
            .replaceAll('í', 'i')
            .replaceAll('ó', 'o')
            .replaceAll('ú', 'u');
    return producto.contains('deceso') || producto.contains('vida');
  }

  double _rendimientoNodo(_EstructuraNode node) =>
      (node.porcentajeMix(cargoSeleccionado) / 100).clamp(0.0, 1.0);

  Color _rendimientoColor(double value) {
    if (value >= 0.40) return Colors.greenAccent;
    if (value >= 0.25) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _rendimientoTexto(_EstructuraNode node) =>
      'Mix ${node.porcentajeMix(cargoSeleccionado).toStringAsFixed(1)} %';

  int get totalDirectoresZona => raiz?.contarRol('director_zona') ?? 0;
  int get totalJefesVentas => raiz?.contarRol('jefe_ventas') ?? 0;
  int get totalJefesEquipo => raiz?.contarRol('jefe_equipo') ?? 0;
  int get totalAgentes => raiz?.contarRol('agente') ?? 0;
  double get totalPrimas => raiz?.primasEstructura(cargoSeleccionado) ?? 0;
  double get totalMix => raiz?.porcentajeMix(cargoSeleccionado) ?? 0;

  String _euros(double value) {
    final entero = value.round().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    return '$entero €';
  }

  String _mesTexto(DateTime fecha) {
    const meses = [
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
    return '${meses[fecha.month - 1]} ${fecha.year}';
  }

  void _cambiarMes(int delta) {
    setState(() => periodo = DateTime(periodo.year, periodo.month + delta));
    cargarEquipos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Stack(
        children: [
          const _EquiposBackground(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: const Color(0xFF2563EB),
                    ),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF2563EB),
                    backgroundColor: const Color(0xFFF1F5F9),
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
                          _filtrosComerciales(),
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
                color: Color(0xFF111827),
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
                'Rendimiento comercial',
                style: TextStyle(
                  color: const Color(0xFF111827),
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Primas y mix mensual de toda tu estructura',
                style: TextStyle(color: const Color(0xFF64748B), fontSize: 13),
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
              color: const Color(0xFF2563EB).withOpacity(0.12),
              border: Border.all(
                color: const Color(0xFF2563EB).withOpacity(0.38),
              ),
            ),
            child: const Icon(
              Icons.refresh_rounded,
              color: const Color(0xFF2563EB),
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
      hero: true,
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
                '${_euros(node.primasEstructura(cargoSeleccionado))} primas estructura',
                const Color(0xFF2563EB),
              ),
              _miniPill(
                Icons.trending_up_rounded,
                '${node.porcentajeMix(cargoSeleccionado).toStringAsFixed(1)} % mix estructura',
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
              color: Color(0xFFD8E2F2),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtrosComerciales() {
    const cargos = <String, String>{
      'todos': 'Todos los cargos',
      'director_zona': 'Directores de zona',
      'jefe_ventas': 'Jefes de ventas',
      'jefe_equipo': 'Jefes de equipo',
      'agente': 'Agentes',
    };
    return _glassCard(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF2563EB).withOpacity(0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Mes anterior',
                  onPressed: loading ? null : () => _cambiarMes(-1),
                  icon: const Icon(
                    Icons.chevron_left,
                    color: Color(0xFF111827),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: Text(
                    _mesTexto(periodo),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: const Color(0xFF111827),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Mes siguiente',
                  onPressed: loading ? null : () => _cambiarMes(1),
                  icon: const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              value: cargoSeleccionado,
              dropdownColor: const Color(0xFFF1F5F9),
              decoration: InputDecoration(
                labelText: 'Filtrar producción por cargo',
                labelStyle: const TextStyle(color: const Color(0xFF64748B)),
                prefixIcon: const Icon(
                  Icons.badge_outlined,
                  color: const Color(0xFF2563EB),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w800,
              ),
              items: cargos.entries
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.key,
                      child: Text(item.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => cargoSeleccionado = value);
              },
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
        color: const Color(0xFF2563EB),
      ),
      _kpiBox(
        title: 'Agentes',
        value: totalAgentes.toString(),
        icon: Icons.groups_rounded,
        color: Colors.greenAccent,
      ),
      _kpiBox(
        title: 'Primas',
        value: _euros(totalPrimas),
        icon: Icons.euro_rounded,
        color: Colors.lightBlueAccent,
      ),
      _kpiBox(
        title: 'Mix',
        value: '${totalMix.toStringAsFixed(1)} %',
        icon: Icons.donut_large_rounded,
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
        final itemWidth = (ancho - (separacion * (columnas - 1))) / columnas;

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
              color: const Color(0xFF64748B),
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
        const Icon(Icons.account_tree_rounded, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Árbol de estructura',
            style: TextStyle(
              color: const Color(0xFF111827),
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          '${(raiz?.totalPersonas ?? 1) - 1} personas',
          style: const TextStyle(
            color: const Color(0xFF64748B),
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
      margin: EdgeInsets.only(left: level == 0 ? 0 : 10, bottom: 14),
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
            collapsedIconColor: const Color(0xFF475569),
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
                          color: const Color(0xFF111827),
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
                        '${_euros(node.primasEstructura(cargoSeleccionado))} primas estructura',
                        const Color(0xFF2563EB),
                      ),
                      _miniPill(
                        Icons.trending_up_rounded,
                        '${node.porcentajeMix(cargoSeleccionado).toStringAsFixed(1)} % mix estructura',
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
                            backgroundColor: Colors.white,
                            valueColor: AlwaysStoppedAnimation(
                              rendimientoColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _rendimientoTexto(node),
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
                ...node.hijos.map((hijo) => _nodoTreeCard(hijo, level + 1)),
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
            'Primas propias',
            _euros(node.primasPropias),
            const Color(0xFF2563EB),
          ),
          _resumenDato(
            'Mix propio',
            node.primasPropias <= 0
                ? '0,0 %'
                : '${(node.mixPropio / node.primasPropias * 100).toStringAsFixed(1)} %',
            Colors.greenAccent,
          ),
          _resumenDato(
            'Primas estructura',
            _euros(node.primasEstructura(cargoSeleccionado)),
            Colors.lightBlueAccent,
          ),
          _resumenDato(
            'Mix estructura',
            '${node.porcentajeMix(cargoSeleccionado).toStringAsFixed(1)} %',
            Colors.amberAccent,
          ),
          _resumenDato('Personas', node.totalPersonas.toString(), color),
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
              color: const Color(0xFF64748B),
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
          Icon(_rolIcono(rol), color: color, size: compact ? 14 : 17),
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
        boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 16)],
      ),
      child: Center(
        child: Text(
          _iniciales(nombre),
          style: TextStyle(
            color: const Color(0xFF111827),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: const Color(0xFF64748B)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Este usuario no tiene personas asignadas directamente.',
              style: TextStyle(
                color: const Color(0xFF64748B),
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
            color: const Color(0xFF78909C),
            size: 64,
          ),
          SizedBox(height: 12),
          Text(
            'Sin estructura disponible',
            style: TextStyle(
              color: const Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'No se ha podido construir el árbol del usuario conectado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: const Color(0xFF64748B), height: 1.4),
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
              color: const Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: const Color(0xFF64748B), height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
    EdgeInsets? margin,
    bool hero = false,
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
              gradient: hero
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF111827), Color(0xFF1D4ED8)],
                    )
                  : null,
              color: hero ? null : Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: hero
                    ? Colors.white.withOpacity(0.14)
                    : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: (hero ? const Color(0xFF1D4ED8) : Colors.black)
                      .withOpacity(hero ? 0.20 : 0.08),
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
    return const Positioned.fill(child: ColoredBox(color: Color(0xFFF4F6FB)));
  }
}
