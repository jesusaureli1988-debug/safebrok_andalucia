import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ControlBajasScreen extends StatefulWidget {
  const ControlBajasScreen({super.key});

  @override
  State<ControlBajasScreen> createState() => _ControlBajasScreenState();
}

class _ControlBajasScreenState extends State<ControlBajasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool guardando = false;

  String role = '';
  String? myId;
  String? myAuthId;

  int vista = 0; // 0 estructura, 1 motivos, 2 usuarios

  List<Map<String, dynamic>> usuarios = [];
  List<Map<String, dynamic>> usuariosPermitidos = [];
  List<Map<String, dynamic>> usuariosEnriquecidos = [];

  final Map<String, Map<String, dynamic>> usuariosPorId = {};
  final Map<String, Map<String, dynamic>> usuariosPorAuth = {};
  List<Map<String, dynamic>> usuariosFiltradosCache = [];

  String busqueda = '';
  String? filtroDirectorZonaId;
  String? filtroJefeVentasId;
  String? filtroJefeEquipoId;
  String filtroRol = 'Todos';
  String filtroEstado = 'Todos';
  String filtroMotivoBaja = 'Todos';
  String agrupacion = 'Jefe equipo';
  String ratioSeleccionado = 'Bajas / Total';
  DateTime? fechaDesde;
  DateTime? fechaHasta;

  final List<String> motivosBaja = const [
    'No supera formación',
    'No inicia actividad',
    'Baja voluntaria',
    'Motivos personales',
    'Motivos laborales',
    'No alcanza objetivos',
    'Falta de actividad',
    'Ausencias reiteradas',
    'Cambio de empresa',
    'Jubilación',
    'Fallecimiento',
    'Otro',
  ];

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  String _normalizarRol(dynamic rol) {
    return (rol ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _idTexto(dynamic value) {
    final id = (value ?? '').toString().trim();

    if (id.isEmpty || id.toLowerCase() == 'null') {
      return '';
    }

    return id;
  }

  bool _esRolAgente(String rol) {
    final normalizado = _normalizarRol(rol);

    return normalizado == 'agente' ||
        normalizado == 'mediador' ||
        normalizado == 'comercial';
  }

  bool _relacionPermitida({
    required String rolPadre,
    required String rolHijo,
  }) {
    final padre = _normalizarRol(rolPadre);
    final hijo = _normalizarRol(rolHijo);

    switch (padre) {
      case 'director_nacional':
        return hijo == 'director_zona' ||
            hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            _esRolAgente(hijo);

      case 'director_zona':
        return hijo == 'jefe_ventas' ||
            hijo == 'jefe_equipo' ||
            _esRolAgente(hijo);

      case 'jefe_ventas':
        return hijo == 'jefe_equipo' ||
            _esRolAgente(hijo);

      case 'jefe_equipo':
        return _esRolAgente(hijo);

      default:
        return false;
    }
  }

  void _crearIndicesUsuarios() {
    usuariosPorId.clear();
    usuariosPorAuth.clear();

    for (final usuario in usuarios) {
      final id = _idTexto(usuario['id']);
      final authId = _idTexto(usuario['auth_id']);

      if (id.isNotEmpty) {
        usuariosPorId[id] = usuario;
      }

      if (authId.isNotEmpty) {
        usuariosPorAuth[authId] = usuario;
      }
    }
  }

  bool _veTodo() {
    final normalizado = _normalizarRol(role);

    return normalizado == 'director_nacional' ||
        normalizado == 'administracion' ||
        normalizado == 'administrador' ||
        normalizado == 'admin';
  }

  List<Map<String, dynamic>> _construirEstructura({
    required Map<String, dynamic> perfil,
  }) {
    if (_veTodo()) {
      return usuarios.where((usuario) {
        return _idTexto(usuario['id']).isNotEmpty;
      }).toList();
    }

    final hijosPorParentId =
        <String, List<Map<String, dynamic>>>{};

    for (final usuario in usuarios) {
      final parentId = _idTexto(usuario['parent_id']);

      if (parentId.isEmpty) continue;

      hijosPorParentId
          .putIfAbsent(
            parentId,
            () => <Map<String, dynamic>>[],
          )
          .add(usuario);
    }

    final resultado = <Map<String, dynamic>>[];
    final visitados = <String>{};

    void recorrer(Map<String, dynamic> actual) {
      final idActual = _idTexto(actual['id']);

      if (idActual.isEmpty || visitados.contains(idActual)) {
        return;
      }

      visitados.add(idActual);
      resultado.add(actual);

      final rolActual =
          _normalizarRol(actual['rol_usuario']);

      final hijos = hijosPorParentId[idActual] ??
          const <Map<String, dynamic>>[];

      for (final hijo in hijos) {
        final rolHijo =
            _normalizarRol(hijo['rol_usuario']);

        if (!_relacionPermitida(
          rolPadre: rolActual,
          rolHijo: rolHijo,
        )) {
          debugPrint(
            'CONTROL BAJAS: usuario bloqueado '
            '${_nombreCompleto(hijo)} '
            '| rol=$rolHijo '
            '| parent=${hijo['parent_id']} '
            '| padre=$rolActual',
          );

          continue;
        }

        recorrer(hijo);
      }
    }

    recorrer(perfil);

    return resultado;
  }

  Future<void> cargarDatos() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        loading = false;
        usuariosPermitidos = [];
        usuariosEnriquecidos = [];
        usuariosFiltradosCache = [];
      });

      return;
    }

    try {
      if (mounted) {
        setState(() {
          loading = true;
        });
      }

      final perfilData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, '
            'nombre, apellidos, email, estado, '
            'motivo_baja, comentario_baja, fecha_baja, '
            'baja_tramitada_por',
          )
          .eq('auth_id', user.id)
          .maybeSingle();

      if (perfilData == null) {
        throw Exception(
          'No se encontró el perfil del usuario conectado.',
        );
      }

      final perfil =
          Map<String, dynamic>.from(perfilData);

      role = _normalizarRol(perfil['rol_usuario']);
      myId = _idTexto(perfil['id']);
      myAuthId = _idTexto(perfil['auth_id']);

      final usuariosData = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, '
            'nombre, apellidos, email, estado, '
            'motivo_baja, comentario_baja, fecha_baja, '
            'baja_tramitada_por',
          )
          .order('nombre', ascending: true);

      usuarios =
          List<Map<String, dynamic>>.from(
        usuariosData,
      );

      _crearIndicesUsuarios();

      usuariosPermitidos = _construirEstructura(
        perfil: perfil,
      );

      usuariosEnriquecidos = usuariosPermitidos
          .map(_enriquecerUsuario)
          .toList();

      _aplicarFiltros();

      debugPrint(
        '======= CONTROL BAJAS ESTRUCTURA REAL =======',
      );
      debugPrint(
        'USUARIO: ${_nombreCompleto(perfil)}',
      );
      debugPrint('ROL: $role');
      debugPrint(
        'PERSONAS EN ESTRUCTURA: '
        '${usuariosPermitidos.length}',
      );
      debugPrint(
        '============================================',
      );

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    } catch (e, stackTrace) {
      debugPrint(
        'ERROR CARGANDO CONTROL DE BAJAS: $e',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        loading = false;
        usuariosPermitidos = [];
        usuariosEnriquecidos = [];
        usuariosFiltradosCache = [];
      });

      _snack(
        'Error cargando control de bajas: $e',
      );
    }
  }

  Map<String, dynamic>? _usuarioPorId(
    String? id,
  ) {
    final valor = _idTexto(id);

    if (valor.isEmpty) return null;

    return usuariosPorId[valor];
  }

  Map<String, dynamic>? _usuarioPorAuth(
    String? authId,
  ) {
    final valor = _idTexto(authId);

    if (valor.isEmpty) return null;

    return usuariosPorAuth[valor];
  }

  List<Map<String, dynamic>> _cadenaAntecesores(
    Map<String, dynamic>? usuario,
  ) {
    if (usuario == null) return [];

    final resultado = <Map<String, dynamic>>[];
    final visitados = <String>{};

    var parentId = _idTexto(usuario['parent_id']);

    while (parentId.isNotEmpty &&
        !visitados.contains(parentId)) {
      visitados.add(parentId);

      final padre = usuariosPorId[parentId];

      if (padre == null) break;

      resultado.add(padre);
      parentId = _idTexto(padre['parent_id']);
    }

    return resultado;
  }

  Map<String, dynamic>? _buscarAntecesorPorRol(
    Map<String, dynamic>? usuario,
    String rolBuscado,
  ) {
    final buscado = _normalizarRol(rolBuscado);

    if (usuario != null &&
        _normalizarRol(usuario['rol_usuario']) ==
            buscado) {
      return usuario;
    }

    for (final antecesor in _cadenaAntecesores(usuario)) {
      if (_normalizarRol(
            antecesor['rol_usuario'],
          ) ==
          buscado) {
        return antecesor;
      }
    }

    return null;
  }

  Map<String, dynamic>? _responsableInmediato(
    Map<String, dynamic>? usuario,
  ) {
    if (usuario == null) return null;

    return _usuarioPorId(
      _idTexto(usuario['parent_id']),
    );
  }

  Map<String, dynamic> _enriquecerUsuario(
    Map<String, dynamic> usuario,
  ) {
    final directorZona = _buscarAntecesorPorRol(
      usuario,
      'director_zona',
    );

    final jefeVentas = _buscarAntecesorPorRol(
      usuario,
      'jefe_ventas',
    );

    final jefeEquipo = _buscarAntecesorPorRol(
      usuario,
      'jefe_equipo',
    );

    final responsable =
        _responsableInmediato(usuario);

    return {
      ...usuario,
      'nombre_completo':
          _nombreCompleto(usuario),
      'responsable_id':
          _idTexto(responsable?['id']),
      'responsable_nombre': responsable == null
          ? ''
          : _nombreCompleto(responsable),
      'responsable_rol':
          _normalizarRol(
        responsable?['rol_usuario'],
      ),
      'director_zona_id':
          _idTexto(directorZona?['id']),
      'director_zona_nombre':
          directorZona == null
              ? ''
              : _nombreCompleto(directorZona),
      'jefe_ventas_id':
          _idTexto(jefeVentas?['id']),
      'jefe_ventas_nombre':
          jefeVentas == null
              ? ''
              : _nombreCompleto(jefeVentas),
      'jefe_equipo_id':
          _idTexto(jefeEquipo?['id']),
      'jefe_equipo_nombre':
          jefeEquipo == null
              ? ''
              : _nombreCompleto(jefeEquipo),
    };
  }

  String _nombreCompleto(
    Map<String, dynamic> usuario,
  ) {
    final nombre =
        usuario['nombre']?.toString() ?? '';

    final apellidos =
        usuario['apellidos']?.toString() ?? '';

    final completo =
        '$nombre $apellidos'.trim();

    return completo.isEmpty
        ? (usuario['email']?.toString() ??
            'Sin nombre')
        : completo;
  }

  bool _esAgente(Map<String, dynamic> usuario) {
    return _esRolAgente(
      usuario['rol_usuario']?.toString() ?? '',
    );
  }

  bool _esDescendienteDe(
    Map<String, dynamic> usuario,
    String ancestroId,
  ) {
    final objetivo = _idTexto(ancestroId);

    if (objetivo.isEmpty) return false;

    if (_idTexto(usuario['id']) == objetivo) {
      return true;
    }

    final visitados = <String>{};
    var parentId =
        _idTexto(usuario['parent_id']);

    while (parentId.isNotEmpty &&
        !visitados.contains(parentId)) {
      if (parentId == objetivo) {
        return true;
      }

      visitados.add(parentId);

      final padre = usuariosPorId[parentId];

      if (padre == null) break;

      parentId =
          _idTexto(padre['parent_id']);
    }

    return false;
  }

  bool _estaInactivo(Map<String, dynamic> u) {
    final e = _normalizar(u['estado']);
    return e == 'inactivo' || e == 'baja' || e == 'dado de baja';
  }

  String _normalizar(dynamic value) {
    return value
            ?.toString()
            .toLowerCase()
            .trim()
            .replaceAll('á', 'a')
            .replaceAll('é', 'e')
            .replaceAll('í', 'i')
            .replaceAll('ó', 'o')
            .replaceAll('ú', 'u') ??
        '';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatDate(dynamic value) {
    final d = _parseDate(value);
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  List<Map<String, dynamic>> _usuariosPorRol(
    String rol,
  ) {
    final normalizado =
        _normalizarRol(rol);

    return usuariosPermitidos.where((usuario) {
      return _normalizarRol(
            usuario['rol_usuario'],
          ) ==
          normalizado;
    }).toList();
  }

  List<Map<String, dynamic>> get directoresZona {
    return _veTodo()
        ? _usuariosPorRol('director_zona')
        : const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> get jefesVentas {
    var lista =
        _usuariosPorRol('jefe_ventas');

    if (role == 'jefe_ventas') {
      return const <Map<String, dynamic>>[];
    }

    if (filtroDirectorZonaId != null) {
      lista = lista.where((usuario) {
        return _esDescendienteDe(
          usuario,
          filtroDirectorZonaId!,
        );
      }).toList();
    }

    return lista;
  }

  List<Map<String, dynamic>> get jefesEquipo {
    var lista =
        _usuariosPorRol('jefe_equipo');

    final responsableSeleccionado =
        filtroJefeVentasId ??
        filtroDirectorZonaId;

    if (responsableSeleccionado != null) {
      lista = lista.where((usuario) {
        return _esDescendienteDe(
          usuario,
          responsableSeleccionado,
        );
      }).toList();
    }

    return lista;
  }

  List<Map<String, dynamic>> get usuariosFiltrados => usuariosFiltradosCache;

  void _aplicarFiltros() {
    var lista = [...usuariosEnriquecidos];

    if (filtroDirectorZonaId != null) {
      lista = lista.where((u) => u['director_zona_id']?.toString() == filtroDirectorZonaId).toList();
    }

    if (filtroJefeVentasId != null) {
      lista = lista.where((u) => u['jefe_ventas_id']?.toString() == filtroJefeVentasId).toList();
    }

    if (filtroJefeEquipoId != null) {
      lista = lista.where((u) => u['jefe_equipo_id']?.toString() == filtroJefeEquipoId).toList();
    }

    if (filtroRol != 'Todos') {
      lista = lista.where((u) => u['rol_usuario']?.toString() == filtroRol).toList();
    }

    if (filtroEstado == 'Activos') {
      lista = lista.where((u) => !_estaInactivo(u)).toList();
    }

    if (filtroEstado == 'Bajas') {
      lista = lista.where(_estaInactivo).toList();
    }

    if (filtroMotivoBaja != 'Todos') {
      lista = lista.where((u) => u['motivo_baja']?.toString() == filtroMotivoBaja).toList();
    }

    if (fechaDesde != null) {
      final desde = DateTime(fechaDesde!.year, fechaDesde!.month, fechaDesde!.day);
      lista = lista.where((u) {
        final f = _parseDate(u['fecha_baja']);
        if (f == null) return false;
        return !DateTime(f.year, f.month, f.day).isBefore(desde);
      }).toList();
    }

    if (fechaHasta != null) {
      final hasta = DateTime(fechaHasta!.year, fechaHasta!.month, fechaHasta!.day);
      lista = lista.where((u) {
        final f = _parseDate(u['fecha_baja']);
        if (f == null) return false;
        return !DateTime(f.year, f.month, f.day).isAfter(hasta);
      }).toList();
    }

    final q = busqueda.toLowerCase().trim();
    if (q.isNotEmpty) {
      lista = lista.where((u) {
        final text = [
          u['nombre_completo'],
          u['email'],
          u['rol_usuario'],
          u['estado'],
          u['motivo_baja'],
          u['comentario_baja'],
          u['director_zona_nombre'],
          u['jefe_ventas_nombre'],
          u['jefe_equipo_nombre'],
        ].join(' ').toLowerCase();
        return text.contains(q);
      }).toList();
    }

    usuariosFiltradosCache = lista;
  }

  List<String> get rolesDisponibles {
    final set = usuariosEnriquecidos
        .map((u) => u['rol_usuario']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Todos', ...set];
  }

  List<String> get motivosDisponibles {
    final set = usuariosEnriquecidos
        .map((u) => u['motivo_baja']?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Todos', ...set];
  }

  int get totalUsuarios => usuariosFiltrados.length;
  int get totalBajas => usuariosFiltrados.where(_estaInactivo).length;
  int get totalActivos => totalUsuarios - totalBajas;

  double get porcentajeBajas => totalUsuarios == 0 ? 0 : (totalBajas / totalUsuarios) * 100;

  List<Map<String, dynamic>> get resumenAgrupado {
    final map = <String, Map<String, dynamic>>{};

    for (final u in usuariosFiltrados) {
      final keyData = _resolverAgrupacion(u);
      final key = keyData['key'] ?? 'sin_datos';
      final nombre = keyData['nombre'] ?? 'Sin datos';
      final subtitulo = keyData['subtitulo'] ?? '';

      map.putIfAbsent(key, () {
        return {
          'key': key,
          'nombre': nombre,
          'subtitulo': subtitulo,
          'total': 0,
          'activos': 0,
          'bajas': 0,
        };
      });

      final row = map[key]!;
      row['total'] = (row['total'] as int) + 1;

      if (_estaInactivo(u)) {
        row['bajas'] = (row['bajas'] as int) + 1;
      } else {
        row['activos'] = (row['activos'] as int) + 1;
      }
    }

    final list = map.values.toList();
    list.sort((a, b) => (b['bajas'] as int).compareTo(a['bajas'] as int));
    return list;
  }

  Map<String, String> _resolverAgrupacion(Map<String, dynamic> u) {
    if (agrupacion == 'Director zona') {
      return {
        'key': u['director_zona_id']?.toString() ?? 'sin_director_zona',
        'nombre': (u['director_zona_nombre']?.toString().isNotEmpty ?? false) ? u['director_zona_nombre'].toString() : 'Sin director zona',
        'subtitulo': 'Director zona',
      };
    }

    if (agrupacion == 'Jefe ventas') {
      return {
        'key': u['jefe_ventas_id']?.toString() ?? 'sin_jefe_ventas',
        'nombre': (u['jefe_ventas_nombre']?.toString().isNotEmpty ?? false) ? u['jefe_ventas_nombre'].toString() : 'Sin jefe ventas',
        'subtitulo': u['director_zona_nombre']?.toString() ?? '',
      };
    }

    if (agrupacion == 'Rol') {
      return {
        'key': u['rol_usuario']?.toString() ?? 'sin_rol',
        'nombre': (u['rol_usuario']?.toString().isNotEmpty ?? false) ? u['rol_usuario'].toString().replaceAll('_', ' ').toUpperCase() : 'Sin rol',
        'subtitulo': 'Rol usuario',
      };
    }

    return {
      'key': u['jefe_equipo_id']?.toString() ?? 'sin_jefe_equipo',
      'nombre': (u['jefe_equipo_nombre']?.toString().isNotEmpty ?? false) ? u['jefe_equipo_nombre'].toString() : 'Sin jefe equipo',
      'subtitulo': '${u['jefe_ventas_nombre'] ?? ''} · ${u['director_zona_nombre'] ?? ''}',
    };
  }

  List<Map<String, dynamic>> get resumenMotivos {
    final map = <String, Map<String, dynamic>>{};
    final bajas = usuariosFiltrados.where(_estaInactivo).toList();

    for (final u in bajas) {
      final motivo = (u['motivo_baja']?.toString().trim().isNotEmpty ?? false) ? u['motivo_baja'].toString().trim() : 'Sin motivo';
      map.putIfAbsent(motivo, () => {'motivo': motivo, 'total': 0});
      map[motivo]!['total'] = (map[motivo]!['total'] as int) + 1;
    }

    final list = map.values.toList();
    list.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
    return list;
  }

  List<Map<String, dynamic>> get resumenMeses {
    final map = <String, Map<String, dynamic>>{};
    final bajas = usuariosFiltrados.where(_estaInactivo).toList();

    for (final u in bajas) {
      final f = _parseDate(u['fecha_baja']);
      final key = f == null ? 'Sin fecha' : '${f.year}-${f.month.toString().padLeft(2, '0')}';
      final label = f == null ? 'Sin fecha' : '${f.month.toString().padLeft(2, '0')}/${f.year}';
      map.putIfAbsent(key, () => {'key': key, 'label': label, 'total': 0});
      map[key]!['total'] = (map[key]!['total'] as int) + 1;
    }

    final list = map.values.toList();
    list.sort((a, b) => b['key'].toString().compareTo(a['key'].toString()));
    return list;
  }

  double _ratio(Map<String, dynamic> row) {
    final total = (row['total'] as int?)?.toDouble() ?? 0;
    final bajas = (row['bajas'] as int?)?.toDouble() ?? 0;
    final activos = (row['activos'] as int?)?.toDouble() ?? 0;

    double div(double a, double b) => b <= 0 ? 0 : (a / b) * 100;

    if (ratioSeleccionado == 'Activos / Total') return div(activos, total);
    return div(bajas, total);
  }

  void limpiarFiltros() {
    setState(() {
      busqueda = '';
      filtroDirectorZonaId = null;
      filtroJefeVentasId = null;
      filtroJefeEquipoId = null;
      filtroRol = 'Todos';
      filtroEstado = 'Todos';
      filtroMotivoBaja = 'Todos';
      fechaDesde = null;
      fechaHasta = null;
      _aplicarFiltros();
    });
  }

  Future<void> _pickFecha(bool desde) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (date == null) return;

    setState(() {
      if (desde) {
        fechaDesde = date;
      } else {
        fechaHasta = date;
      }
      _aplicarFiltros();
    });
  }


  String _rolVisible(dynamic rol) {
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
      case 'mediador':
        return 'Mediador';
      case 'comercial':
        return 'Comercial';
      case 'administracion':
      case 'administrador':
      case 'admin':
        return 'Administración';
      default:
        final texto = (rol ?? '').toString().trim();
        return texto.isEmpty
            ? 'Sin rol'
            : texto.replaceAll('_', ' ');
    }
  }

  bool _creariaCiclo({
    required Map<String, dynamic> usuario,
    required Map<String, dynamic> nuevoResponsable,
  }) {
    final usuarioId = _idTexto(usuario['id']);
    final responsableId =
        _idTexto(nuevoResponsable['id']);

    if (usuarioId.isEmpty || responsableId.isEmpty) {
      return true;
    }

    if (usuarioId == responsableId) {
      return true;
    }

    return _esDescendienteDe(
      nuevoResponsable,
      usuarioId,
    );
  }

  List<Map<String, dynamic>> _responsablesPermitidosPara(
    Map<String, dynamic> usuario,
  ) {
    final rolUsuario =
        _normalizarRol(usuario['rol_usuario']);

    final lista = usuariosPermitidos.where((posible) {
      final idPosible = _idTexto(posible['id']);
      final authPosible = _idTexto(posible['auth_id']);

      if (idPosible.isEmpty || authPosible.isEmpty) {
        return false;
      }

      if (_creariaCiclo(
        usuario: usuario,
        nuevoResponsable: posible,
      )) {
        return false;
      }

      return _relacionPermitida(
        rolPadre:
            _normalizarRol(posible['rol_usuario']),
        rolHijo: rolUsuario,
      );
    }).toList();

    lista.sort((a, b) {
      final rolA =
          _rolVisible(a['rol_usuario']).toLowerCase();

      final rolB =
          _rolVisible(b['rol_usuario']).toLowerCase();

      final comparacionRol =
          rolA.compareTo(rolB);

      if (comparacionRol != 0) {
        return comparacionRol;
      }

      return _nombreCompleto(a)
          .toLowerCase()
          .compareTo(
            _nombreCompleto(b).toLowerCase(),
          );
    });

    return lista;
  }

  Future<bool> _usuarioSiguePermitido(
    String usuarioId,
  ) async {
    final authUser = supabase.auth.currentUser;

    if (authUser == null) return false;

    final perfilData = await supabase
        .from('usuarios')
        .select(
          'id, auth_id, parent_id, rol_usuario, '
          'nombre, apellidos, email, estado, '
          'motivo_baja, comentario_baja, fecha_baja, '
          'baja_tramitada_por',
        )
        .eq('auth_id', authUser.id)
        .maybeSingle();

    if (perfilData == null) return false;

    if (_veTodo()) return true;

    final usuariosData = await supabase
        .from('usuarios')
        .select(
          'id, auth_id, parent_id, rol_usuario, '
          'nombre, apellidos, email, estado, '
          'motivo_baja, comentario_baja, fecha_baja, '
          'baja_tramitada_por',
        );

    final anteriores = usuarios;

    usuarios =
        List<Map<String, dynamic>>.from(
      usuariosData,
    );

    _crearIndicesUsuarios();

    final estructura = _construirEstructura(
      perfil: Map<String, dynamic>.from(
        perfilData,
      ),
    );

    final permitido = estructura.any((usuario) {
      return _idTexto(usuario['id']) == usuarioId;
    });

    usuarios = anteriores;
    _crearIndicesUsuarios();

    return permitido;
  }

  Future<void> _gestionarBaja(
    Map<String, dynamic> usuario,
  ) async {
    String estado = _estaInactivo(usuario)
        ? 'Inactivo'
        : 'Activo';

    String motivo =
        (usuario['motivo_baja']
                    ?.toString()
                    .isNotEmpty ??
                false)
            ? usuario['motivo_baja'].toString()
            : motivosBaja.first;

    String comentario =
        usuario['comentario_baja']?.toString() ?? '';

    DateTime fechaBaja =
        _parseDate(usuario['fecha_baja']) ??
            DateTime.now();

    String? nuevoParentId =
        _idTexto(usuario['parent_id']).isEmpty
            ? null
            : _idTexto(usuario['parent_id']);

    final teniaResponsable =
        nuevoParentId != null;

    final responsables =
        _responsablesPermitidosPara(usuario);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final responsableActual =
                _usuarioPorId(nuevoParentId);

            return _modalShell(
              title: 'Gestionar usuario',
              subtitle:
                  usuario['nombre_completo']?.toString() ??
                      'Usuario',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius:
                          BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFBFDBFE),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB)
                                    .withOpacity(0.11),
                                borderRadius:
                                    BorderRadius.circular(14),
                              ),
                              child: Icon(
                                teniaResponsable
                                    ? Icons.swap_horiz_rounded
                                    : Icons.person_add_alt_1_rounded,
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    teniaResponsable
                                        ? 'Reasignar responsable'
                                        : 'Asignar responsable',
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontSize: 16,
                                      fontWeight:
                                          FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    responsableActual == null
                                        ? 'Sin responsable seleccionado'
                                        : '${_nombreCompleto(responsableActual)} · ${_rolVisible(responsableActual['rol_usuario'])}',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: responsables.any(
                            (responsable) =>
                                _idTexto(responsable['id']) ==
                                nuevoParentId,
                          )
                              ? nuevoParentId
                              : null,
                          isExpanded: true,
                          decoration: _inputDecoration(
                            teniaResponsable
                                ? 'Nuevo responsable'
                                : 'Asignar a',
                          ),
                          items: responsables.map((responsable) {
                            return DropdownMenuItem<String>(
                              value:
                                  _idTexto(responsable['id']),
                              child: Text(
                                '${_nombreCompleto(responsable)} · ${_rolVisible(responsable['rol_usuario'])}',
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setModalState(() {
                              nuevoParentId = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: estado,
                    isExpanded: true,
                    decoration:
                        _inputDecoration('Estado'),
                    items: const [
                      'Activo',
                      'Inactivo',
                    ]
                        .map(
                          (valor) =>
                              DropdownMenuItem<String>(
                            value: valor,
                            child: Text(valor),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;

                      setModalState(() {
                        estado = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (estado == 'Inactivo') ...[
                    DropdownButtonFormField<String>(
                      value: motivosBaja.contains(motivo)
                          ? motivo
                          : 'Otro',
                      isExpanded: true,
                      decoration:
                          _inputDecoration('Motivo baja'),
                      items: motivosBaja
                          .map(
                            (valor) =>
                                DropdownMenuItem<String>(
                              value: valor,
                              child: Text(valor),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        setModalState(() {
                          motivo = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius:
                          BorderRadius.circular(18),
                      onTap: () async {
                        final fecha =
                            await showDatePicker(
                          context: context,
                          initialDate: fechaBaja,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );

                        if (fecha != null) {
                          setModalState(() {
                            fechaBaja = fecha;
                          });
                        }
                      },
                      child: InputDecorator(
                        decoration: _inputDecoration(
                          'Fecha baja',
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.date_range_rounded,
                              color: Color(0xFF0284C7),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(
                                fechaBaja
                                    .toIso8601String(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: comentario,
                      maxLines: 4,
                      decoration: _inputDecoration(
                        'Comentario baja',
                      ),
                      onChanged: (value) {
                        comentario = value;
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: nuevoParentId == null
                          ? null
                          : () async {
                              Navigator.pop(context);

                              await _guardarBaja(
                                usuario,
                                estado,
                                motivo,
                                comentario,
                                fechaBaja,
                                nuevoParentId:
                                    nuevoParentId,
                              );
                            },
                      icon: Icon(
                        teniaResponsable
                            ? Icons.swap_horiz_rounded
                            : Icons.person_add_alt_1_rounded,
                      ),
                      label: Text(
                        teniaResponsable
                            ? 'Reasignar y guardar'
                            : 'Asignar y guardar',
                      ),
                      style: _primaryButtonStyle(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _guardarBaja(
    Map<String, dynamic> usuario,
    String estado,
    String motivo,
    String comentario,
    DateTime fechaBaja, {
    required String? nuevoParentId,
  }) async {
    try {
      if (mounted) {
        setState(() {
          guardando = true;
        });
      }

      final id = _idTexto(usuario['id']);
      final parentId = _idTexto(nuevoParentId);

      if (id.isEmpty) {
        throw Exception('Usuario sin id válido.');
      }

      if (parentId.isEmpty) {
        throw Exception(
          'Debes seleccionar un responsable.',
        );
      }

      final siguePermitido =
          await _usuarioSiguePermitido(id);

      if (!siguePermitido) {
        throw Exception(
          'El usuario ya no pertenece a tu estructura.',
        );
      }

      final usuarioActual = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, '
            'nombre, apellidos, email',
          )
          .eq('id', id)
          .maybeSingle();

      final responsableActual = await supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, '
            'nombre, apellidos, email',
          )
          .eq('id', parentId)
          .maybeSingle();

      if (usuarioActual == null ||
          responsableActual == null) {
        throw Exception(
          'No se pudo validar la asignación.',
        );
      }

      final usuarioMap =
          Map<String, dynamic>.from(usuarioActual);

      final responsableMap =
          Map<String, dynamic>.from(
        responsableActual,
      );

      final responsablePermitido =
          usuariosPermitidos.any((permitido) {
        return _idTexto(permitido['id']) == parentId;
      });

      if (!responsablePermitido) {
        throw Exception(
          'El responsable seleccionado no pertenece '
          'a tu estructura.',
        );
      }

      if (!_relacionPermitida(
        rolPadre: _normalizarRol(
          responsableMap['rol_usuario'],
        ),
        rolHijo: _normalizarRol(
          usuarioMap['rol_usuario'],
        ),
      )) {
        throw Exception(
          'La dependencia seleccionada no es válida '
          'para el rol del usuario.',
        );
      }

      if (_creariaCiclo(
        usuario: usuarioMap,
        nuevoResponsable: responsableMap,
      )) {
        throw Exception(
          'La asignación produciría un ciclo '
          'en la estructura.',
        );
      }

      final update = <String, dynamic>{
        'parent_id': parentId,
        'estado': estado,
        'motivo_baja':
            estado == 'Inactivo' ? motivo : null,
        'comentario_baja':
            estado == 'Inactivo' ? comentario : null,
        'fecha_baja': estado == 'Inactivo'
            ? fechaBaja.toIso8601String()
            : null,
        'baja_tramitada_por':
            estado == 'Inactivo'
                ? myAuthId
                : null,
      };

      await supabase
          .from('usuarios')
          .update(update)
          .eq('id', id);

      _snack(
        'Usuario actualizado y asignado a '
        '${_nombreCompleto(responsableMap)}',
      );

      await cargarDatos();
    } catch (e) {
      _snack(
        'Error guardando usuario: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          guardando = false;
        });
      }
    }
  }

  void _verDetalle(Map<String, dynamic> u) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _modalShell(
          title: 'Detalle usuario',
          subtitle: u['nombre_completo']?.toString() ?? 'Usuario',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _detailChip('Nombre', u['nombre_completo']?.toString() ?? ''),
                  _detailChip('Email', u['email']?.toString() ?? ''),
                  _detailChip('Rol', u['rol_usuario']?.toString() ?? ''),
                  _detailChip('Estado', u['estado']?.toString() ?? ''),
                  _detailChip('Responsable directo', u['responsable_nombre']?.toString() ?? ''),
                  _detailChip('Rol responsable', _rolVisible(u['responsable_rol'])),
                  _detailChip('Director zona', u['director_zona_nombre']?.toString() ?? ''),
                  _detailChip('Jefe ventas', u['jefe_ventas_nombre']?.toString() ?? ''),
                  _detailChip('Jefe equipo', u['jefe_equipo_nombre']?.toString() ?? ''),
                  _detailChip('Motivo baja', u['motivo_baja']?.toString() ?? ''),
                  _detailChip('Comentario baja', u['comentario_baja']?.toString() ?? ''),
                  _detailChip('Fecha baja', _formatDate(u['fecha_baja'])),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _gestionarBaja(u);
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(
                    _idTexto(u['parent_id']).isEmpty
                        ? 'Gestionar / Asignar'
                        : 'Gestionar / Reasignar',
                  ),
                  style: _primaryButtonStyle(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoControlBajas(),
          SafeArea(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 980;

                      final contenido = Padding(
                        padding: EdgeInsets.fromLTRB(isMobile ? 12 : 18, 18, isMobile ? 12 : 22, 22),
                        child: Column(
                          children: [
                            _header(),
                            const SizedBox(height: 14),
                            _selectorVista(),
                            const SizedBox(height: 14),
                            _totalesCabecera(),
                            const SizedBox(height: 14),
                            Expanded(
                              child: vista == 0
                                  ? _vistaEstructura()
                                  : vista == 1
                                      ? _vistaMotivos()
                                      : _vistaUsuarios(),
                            ),
                          ],
                        ),
                      );

                      if (isMobile) {
                        return Column(
                          children: [
                            SizedBox(height: 330, child: _panelFiltros(compacto: true)),
                            Expanded(child: contenido),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          _panelFiltros(),
                          Expanded(child: contenido),
                        ],
                      );
                    },
                  ),
          ),
          if (guardando)
            Container(
              color: Colors.black.withOpacity(0.18),
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7))),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final estrecho = constraints.maxWidth < 720;
        final volver = InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          ),
        );

        final titulo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Control de bajas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$totalUsuarios usuarios visibles · $totalBajas bajas · ${porcentajeBajas.toStringAsFixed(1)} % bajas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ],
        );

        if (estrecho) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [volver, const SizedBox(width: 12), Expanded(child: titulo)]),
              const SizedBox(height: 10),
              _badgeRole(),
            ],
          );
        }

        return Row(
          children: [
            volver,
            const SizedBox(width: 14),
            Expanded(child: titulo),
            const SizedBox(width: 12),
            _badgeRole(),
          ],
        );
      },
    );
  }

  Widget _badgeRole() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7DD3FC)),
      ),
      child: Text(
        role.replaceAll('_', ' ').toUpperCase(),
        style: const TextStyle(color: Color(0xFF075985), fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }

  Widget _selectorVista() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          Expanded(child: _tabButton('Estructura', 0, Icons.account_tree_rounded)),
          Expanded(child: _tabButton('Motivos', 1, Icons.rule_rounded)),
          Expanded(child: _tabButton('Usuarios', 2, Icons.people_alt_rounded)),
        ],
      ),
    );
  }

  Widget _tabButton(String text, int index, IconData icon) {
    final active = vista == index;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => vista = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0284C7) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? Colors.white : const Color(0xFF64748B), size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: active ? Colors.white : const Color(0xFF64748B), fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalesCabecera() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _miniTotal('Usuarios', totalUsuarios),
          _miniTotal('Activos', totalActivos, color: const Color(0xFF16A34A)),
          _miniTotal('Bajas', totalBajas, color: const Color(0xFFDC2626)),
          _miniTotal('% bajas', porcentajeBajas.toStringAsFixed(1), suffix: '%', color: const Color(0xFFF97316)),
        ],
      ),
    );
  }

  Widget _panelFiltros({bool compacto = false}) {
    return Container(
      width: compacto ? double.infinity : 360,
      margin: EdgeInsets.all(compacto ? 10 : 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 8))],
      ),
      child: ListView(
        children: [
          const Text('Filtros de bajas', style: TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          const Text(
            'Analiza bajas por estructura, rol, motivo y fechas.',
            style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, height: 1.3),
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: (v) => setState(() {
              busqueda = v;
              _aplicarFiltros();
            }),
            decoration: _inputDecoration('Buscar usuario').copyWith(prefixIcon: const Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 14),
          if (directoresZona.isNotEmpty)
            _dropdownUsuarios(
              label: 'Director de zona',
              value: filtroDirectorZonaId,
              usuarios: directoresZona,
              onChanged: (v) {
                setState(() {
                  filtroDirectorZonaId = v;
                  filtroJefeVentasId = null;
                  filtroJefeEquipoId = null;
                  _aplicarFiltros();
                });
              },
            ),
          if (jefesVentas.isNotEmpty)
            _dropdownUsuarios(
              label: 'Jefe de ventas',
              value: filtroJefeVentasId,
              usuarios: jefesVentas,
              onChanged: (v) {
                setState(() {
                  filtroJefeVentasId = v;
                  filtroJefeEquipoId = null;
                  _aplicarFiltros();
                });
              },
            ),
          if (jefesEquipo.isNotEmpty)
            _dropdownUsuarios(
              label: 'Jefe de equipo',
              value: filtroJefeEquipoId,
              usuarios: jefesEquipo,
              onChanged: (v) {
                setState(() {
                  filtroJefeEquipoId = v;
                  _aplicarFiltros();
                });
              },
            ),
          _dropdownSimple(
            label: 'Estado',
            value: filtroEstado,
            items: const ['Todos', 'Activos', 'Bajas'],
            onChanged: (v) => setState(() {
              filtroEstado = v!;
              _aplicarFiltros();
            }),
          ),
          _dropdownSimple(
            label: 'Rol',
            value: filtroRol,
            items: rolesDisponibles,
            onChanged: (v) => setState(() {
              filtroRol = v!;
              _aplicarFiltros();
            }),
          ),
          _dropdownSimple(
            label: 'Motivo baja',
            value: filtroMotivoBaja,
            items: motivosDisponibles,
            onChanged: (v) => setState(() {
              filtroMotivoBaja = v!;
              _aplicarFiltros();
            }),
          ),
          _dateButton(label: 'Fecha baja desde', value: fechaDesde, onTap: () => _pickFecha(true)),
          _dateButton(label: 'Fecha baja hasta', value: fechaHasta, onTap: () => _pickFecha(false)),
          _dropdownSimple(
            label: 'Agrupar estructura por',
            value: agrupacion,
            items: const ['Jefe equipo', 'Jefe ventas', 'Director zona', 'Rol'],
            onChanged: (v) => setState(() => agrupacion = v!),
          ),
          _dropdownSimple(
            label: 'Ratio',
            value: ratioSeleccionado,
            items: const ['Bajas / Total', 'Activos / Total'],
            onChanged: (v) => setState(() => ratioSeleccionado = v!),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: limpiarFiltros,
            icon: const Icon(Icons.cleaning_services_rounded),
            label: const Text('Limpiar filtros'),
            style: _primaryButtonStyle(),
          ),
        ],
      ),
    );
  }

  Widget _vistaEstructura() {
    final rows = resumenAgrupado;

    return _panelTabla(
      emptyText: 'No hay datos para estos filtros.',
      child: rows.isEmpty
          ? null
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final r = rows[index];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r['nombre'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      if (r['subtitulo']?.toString().isNotEmpty ?? false) ...[
                        const SizedBox(height: 3),
                        Text(
                          r['subtitulo'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _miniTotal('Total', r['total']),
                          _miniTotal('Activos', r['activos'], color: const Color(0xFF16A34A)),
                          _miniTotal('Bajas', r['bajas'], color: const Color(0xFFDC2626)),
                          _miniTotal('Ratio', _ratio(r).toStringAsFixed(1), suffix: '%', color: const Color(0xFF0284C7)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _vistaMotivos() {
    final rows = resumenMotivos;
    final total = rows.fold<int>(0, (s, r) => s + ((r['total'] ?? 0) as int));

    return _panelTabla(
      emptyText: 'No hay motivos de baja para estos filtros.',
      child: rows.isEmpty
          ? null
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final r = rows[index];
                final n = (r['total'] ?? 0) as int;
                final pct = total == 0 ? 0.0 : (n / total) * 100;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r['motivo'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      _miniTotal('Bajas', n, color: const Color(0xFFDC2626)),
                      const SizedBox(width: 10),
                      _miniTotal('%', pct.toStringAsFixed(1), suffix: '%', color: const Color(0xFF0284C7)),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _vistaUsuarios() {
    final rows = usuariosFiltrados.take(200).toList();

    return _panelTabla(
      emptyText: 'No hay usuarios para estos filtros.',
      child: rows.isEmpty
          ? null
          : Column(
              children: [
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  color: const Color(0xFFF1F5F9),
                  child: Row(
                    children: [
                      Text('Mostrando ${rows.length} de ${usuariosFiltrados.length}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900)),
                      const Spacer(),
                      const Text('Acciones', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final u = rows[index];
                      final baja = _estaInactivo(u);

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u['nombre_completo']?.toString() ?? 'Sin nombre',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_rolVisible(u['rol_usuario'])} · Responsable: ${u['responsable_nombre']?.toString().isEmpty ?? true ? 'Sin asignar' : u['responsable_nombre']} · ${u['jefe_equipo_nombre'] ?? ''} · ${u['jefe_ventas_nombre'] ?? ''} · ${u['director_zona_nombre'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                                  ),
                                  if (baja) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _pill(u['motivo_baja']?.toString().isEmpty ?? true ? 'Sin motivo' : u['motivo_baja'].toString(), const Color(0xFFDC2626)),
                                        _pill(_formatDate(u['fecha_baja']).isEmpty ? 'Sin fecha' : _formatDate(u['fecha_baja']), const Color(0xFFF97316)),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _pill(baja ? 'Inactivo' : 'Activo', baja ? const Color(0xFFDC2626) : const Color(0xFF16A34A)),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              onSelected: (value) {
                                if (value == 'detalle') _verDetalle(u);
                                if (value == 'gestionar') _gestionarBaja(u);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'detalle',
                                  child: Text('Ver detalles'),
                                ),
                                PopupMenuItem(
                                  value: 'gestionar',
                                  child: Text(
                                    _idTexto(u['parent_id']).isEmpty
                                        ? 'Gestionar / Asignar'
                                        : 'Gestionar / Reasignar',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _panelTabla({required String emptyText, required Widget? child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: child ??
            Center(
              child: Text(
                emptyText,
                style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
              ),
            ),
      ),
    );
  }

  Widget _miniTotal(String label, dynamic value, {String suffix = '', Color color = const Color(0xFF0F172A)}) {
    return Container(
      width: 135,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text('$value$suffix', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }

  Widget _detailChip(String label, String value) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(value.isEmpty ? '-' : value, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _modalShell({required String title, required String subtitle, required Widget child}) {
    return Padding(
      padding: EdgeInsets.only(left: 18, right: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 28, offset: const Offset(0, 14))],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.person_remove_alt_1_rounded, color: Color(0xFF0284C7)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 23, fontWeight: FontWeight.w900)),
                        Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdownUsuarios({required String label, required String? value, required List<Map<String, dynamic>> usuarios, required void Function(String?) onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: _inputDecoration(label),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('Todos')),
          ...usuarios.map((u) => DropdownMenuItem<String>(value: u['id']?.toString(), child: Text(_nombreCompleto(u)))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _dropdownSimple({required String label, required String value, required List<String> items, required void Function(String?) onChanged}) {
    final safeItems = items.toSet().toList();
    final safeValue = safeItems.contains(value) ? value : safeItems.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: DropdownButtonFormField<String>(
        value: safeValue,
        isExpanded: true,
        decoration: _inputDecoration(label),
        items: safeItems.map((e) => DropdownMenuItem<String>(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateButton({required String label, required DateTime? value, required VoidCallback onTap}) {
    final text = value == null ? 'Sin seleccionar' : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: InputDecorator(
          decoration: _inputDecoration(label),
          child: Row(
            children: [
              const Icon(Icons.date_range_rounded, color: Color(0xFF0284C7)),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF0284C7))),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF0284C7),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: const Color(0xFF0F172A)));
  }
}

class _FondoControlBajas extends StatelessWidget {
  const _FondoControlBajas();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: const Color(0xFFF4F7FB)),
        Positioned(top: -130, right: -120, child: _orb(330, const Color(0xFF7DD3FC))),
        Positioned(bottom: -150, left: -130, child: _orb(360, const Color(0xFFC4B5FD))),
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
        boxShadow: [BoxShadow(color: color.withOpacity(0.28), blurRadius: 70, spreadRadius: 20)],
      ),
    );
  }
}