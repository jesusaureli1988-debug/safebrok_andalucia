import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ControlReferenciasScreen extends StatefulWidget {
  const ControlReferenciasScreen({super.key});

  @override
  State<ControlReferenciasScreen> createState() =>
      _ControlReferenciasScreenState();
}

class _ControlReferenciasScreenState extends State<ControlReferenciasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool guardando = false;

  String role = '';
  String? myId;
  String? myAuthId;

  List<Map<String, dynamic>> usuarios = [];
  List<Map<String, dynamic>> usuariosPermitidos = [];
  List<Map<String, dynamic>> referencias = [];
  List<Map<String, dynamic>> referenciasFiltradasCache = [];

  final Set<String> referenciasSeleccionadas = {};

  String busqueda = '';
  String? filtroDirectorZonaId;
  String? filtroJefeVentasId;
  String? filtroJefeEquipoId;
  String? filtroAgenteAuthId;
  String filtroTipoReferencia = 'Todos';
  String filtroEstado = 'Todos';
  String filtroPrioridad = 'Todas';
  String filtroRequiereVisita = 'Todos';
  DateTime? fechaDesde;
  DateTime? fechaHasta;

  String? sortKey;
  bool sortAsc = true;

  final List<_CampoTabla> camposDisponibles = const [
    _CampoTabla(key: 'agente_nombre', titulo: 'Agente', grupo: 'Estructura', ancho: 190),
    _CampoTabla(key: 'jefe_equipo_nombre', titulo: 'Jefe equipo', grupo: 'Estructura', ancho: 190),
    _CampoTabla(key: 'jefe_ventas_nombre', titulo: 'Jefe ventas', grupo: 'Estructura', ancho: 190),
    _CampoTabla(key: 'director_zona_nombre', titulo: 'Director zona', grupo: 'Estructura', ancho: 190),
    _CampoTabla(key: 'tipo_referencia', titulo: 'Tipo referencia', grupo: 'Referencia', ancho: 170),
    _CampoTabla(key: 'nombre', titulo: 'Nombre cliente', grupo: 'Referencia', ancho: 220),
    _CampoTabla(key: 'telefono', titulo: 'Teléfono', grupo: 'Referencia', ancho: 140),
    _CampoTabla(key: 'producto', titulo: 'Producto', grupo: 'Referencia', ancho: 160),
    _CampoTabla(key: 'prioridad', titulo: 'Prioridad', grupo: 'Gestión', ancho: 120),
    _CampoTabla(key: 'estado', titulo: 'Estado', grupo: 'Gestión', ancho: 160),
    _CampoTabla(key: 'resultados', titulo: 'Resultado', grupo: 'Gestión', ancho: 180),
    _CampoTabla(key: 'requiere_visita', titulo: 'Requiere visita', grupo: 'Gestión', ancho: 150),
    _CampoTabla(key: 'prima_potencial', titulo: 'Prima potencial', grupo: 'Negocio', ancho: 150),
    _CampoTabla(key: 'campania_actual', titulo: 'Campaña actual', grupo: 'Origen', ancho: 180),
    _CampoTabla(key: 'productos_actuales', titulo: 'Productos actuales', grupo: 'Origen', ancho: 220),
    _CampoTabla(key: 'fecha_vencimiento', titulo: 'Fecha vencimiento', grupo: 'Fechas', ancho: 170),
    _CampoTabla(key: 'fecha_seguimiento', titulo: 'Fecha seguimiento', grupo: 'Fechas', ancho: 170),
    _CampoTabla(key: 'fecha_rellamada', titulo: 'Fecha rellamada', grupo: 'Fechas', ancho: 170),
    _CampoTabla(key: 'fecha_llamada', titulo: 'Fecha llamada', grupo: 'Fechas', ancho: 170),
    _CampoTabla(key: 'created_at', titulo: 'Fecha creación', grupo: 'Fechas', ancho: 170),
    _CampoTabla(key: 'notas', titulo: 'Notas', grupo: 'Notas', ancho: 260),
    _CampoTabla(key: 'nota_seguimiento', titulo: 'Nota seguimiento', grupo: 'Notas', ancho: 260),
    _CampoTabla(key: 'id', titulo: 'ID', grupo: 'Sistema', ancho: 220),
    _CampoTabla(key: 'auth_id', titulo: 'Auth agente', grupo: 'Sistema', ancho: 220),
  ];

  late List<String> columnasActivas = [
    'agente_nombre',
    'jefe_equipo_nombre',
    'tipo_referencia',
    'nombre',
    'telefono',
    'producto',
    'prioridad',
    'estado',
    'resultados',
    'fecha_rellamada',
  ];

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
          .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos, email')
          .eq('auth_id', user.id)
          .maybeSingle();

      role = perfil?['rol_usuario']?.toString() ?? '';
      myId = perfil?['id']?.toString();
      myAuthId = perfil?['auth_id']?.toString();

      final usuariosData = await supabase
          .from('usuarios')
          .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos, email')
          .order('nombre', ascending: true);

      usuarios = List<Map<String, dynamic>>.from(usuariosData);
      usuariosPermitidos = _calcularUsuariosPermitidos();

      final authIdsPermitidos = usuariosPermitidos
          .map((u) => u['auth_id']?.toString() ?? '')
          .where((e) => e.isNotEmpty && e != 'null')
          .toList();

      dynamic query = supabase.from('referencias_viables').select();

      if (!_veTodo()) {
        if (authIdsPermitidos.isEmpty) {
          referencias = [];
          if (!mounted) return;
          setState(() => loading = false);
          return;
        }
        query = query.inFilter('auth_id', authIdsPermitidos);
      }

      final referenciasData = await query.order('created_at', ascending: false);

      referencias = List<Map<String, dynamic>>.from(referenciasData).map((r) {
        return _enriquecerReferencia(r);
      }).toList();
      _aplicarFiltros();

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _snack('Error cargando control de referencias: $e');
    }
  }

  Map<String, dynamic> _enriquecerReferencia(Map<String, dynamic> r) {
    final auth = r['auth_id']?.toString();
    final agente = _usuarioPorAuth(auth);
    final jefeEquipo = _usuarioPorId(agente?['parent_id']?.toString());
    final jefeVentas = _usuarioPorId(jefeEquipo?['parent_id']?.toString());
    final directorZona = _usuarioPorId(jefeVentas?['parent_id']?.toString());

    return {
      ...r,
      'agente_nombre': agente == null ? 'Sin agente' : _nombreCompleto(agente),
      'agente_id': agente?['id']?.toString(),
      'jefe_equipo_nombre': jefeEquipo == null ? '' : _nombreCompleto(jefeEquipo),
      'jefe_equipo_id': jefeEquipo?['id']?.toString(),
      'jefe_ventas_nombre': jefeVentas == null ? '' : _nombreCompleto(jefeVentas),
      'jefe_ventas_id': jefeVentas?['id']?.toString(),
      'director_zona_nombre': directorZona == null ? '' : _nombreCompleto(directorZona),
      'director_zona_id': directorZona?['id']?.toString(),
      'tipo_referencia': _tipoReferencia(r),
    };
  }

  bool _veTodo() => role == 'director_nacional' || role == 'administracion';

  Map<String, dynamic>? _usuarioPorAuth(String? authId) {
    if (authId == null || authId.isEmpty || authId == 'null') return null;
    for (final u in usuarios) {
      if (u['auth_id']?.toString() == authId) return u;
    }
    return null;
  }

  Map<String, dynamic>? _usuarioPorId(String? id) {
    if (id == null || id.isEmpty || id == 'null') return null;
    for (final u in usuarios) {
      if (u['id']?.toString() == id) return u;
    }
    return null;
  }

  List<Map<String, dynamic>> _calcularUsuariosPermitidos() {
    if (_veTodo()) return usuarios;
    if (myId == null || myId!.isEmpty) return [];

    final ids = <String>{myId!};
    bool cambios = true;

    while (cambios) {
      cambios = false;
      for (final u in usuarios) {
        final id = u['id']?.toString();
        final parentId = u['parent_id']?.toString();
        if (id == null || id.isEmpty) continue;
        if (parentId == null || parentId.isEmpty) continue;
        if (ids.contains(parentId) && !ids.contains(id)) {
          ids.add(id);
          cambios = true;
        }
      }
    }

    return usuarios.where((u) => ids.contains(u['id']?.toString())).toList();
  }

  String _nombreCompleto(Map<String, dynamic> u) {
    final nombre = u['nombre']?.toString() ?? '';
    final apellidos = u['apellidos']?.toString() ?? '';
    final completo = '$nombre $apellidos'.trim();
    return completo.isEmpty ? (u['email']?.toString() ?? 'Sin nombre') : completo;
  }

  String _tipoReferencia(Map<String, dynamic> r) {
    final campania = r['campania_actual']?.toString().trim() ?? '';
    final productosActuales = r['productos_actuales']?.toString().trim() ?? '';
    final notaSeguimiento = r['nota_seguimiento']?.toString().trim() ?? '';
    final fechaSeguimiento = r['fecha_seguimiento']?.toString().trim() ?? '';

    if (campania.isNotEmpty || productosActuales.isNotEmpty) {
      return 'Asignada compañía';
    }

    if (notaSeguimiento.isNotEmpty || fechaSeguimiento.isNotEmpty) {
      return 'Seguimiento';
    }

    return 'Propia agente';
  }

  List<Map<String, dynamic>> _usuariosPorRol(String rol) {
    return usuariosPermitidos
        .where((u) => u['rol_usuario']?.toString() == rol)
        .toList();
  }

  List<Map<String, dynamic>> get directoresZona =>
      _veTodo() ? _usuariosPorRol('director_zona') : [];

  List<Map<String, dynamic>> get jefesVentas {
    var lista = _usuariosPorRol('jefe_ventas');
    if (role == 'jefe_ventas') return [];

    if (filtroDirectorZonaId != null) {
      lista = lista
          .where((u) => u['parent_id']?.toString() == filtroDirectorZonaId)
          .toList();
    }
    return lista;
  }

  List<Map<String, dynamic>> get jefesEquipo {
    var lista = _usuariosPorRol('jefe_equipo');

    if (filtroJefeVentasId != null) {
      lista = lista
          .where((u) => u['parent_id']?.toString() == filtroJefeVentasId)
          .toList();
    }

    if (filtroDirectorZonaId != null && filtroJefeVentasId == null) {
      final idsVentas = usuariosPermitidos
          .where((u) =>
              u['rol_usuario']?.toString() == 'jefe_ventas' &&
              u['parent_id']?.toString() == filtroDirectorZonaId)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();

      lista = lista
          .where((u) => idsVentas.contains(u['parent_id']?.toString()))
          .toList();
    }

    return lista;
  }

  List<Map<String, dynamic>> get agentes {
    var lista = usuariosPermitidos.where((u) {
      final r = u['rol_usuario']?.toString();
      return r == 'agente' || r == 'mediador' || r == 'comercial';
    }).toList();

    if (filtroJefeEquipoId != null) {
      lista = lista
          .where((u) => u['parent_id']?.toString() == filtroJefeEquipoId)
          .toList();
    }

    if (filtroJefeVentasId != null && filtroJefeEquipoId == null) {
      final idsEquipo = usuariosPermitidos
          .where((u) =>
              u['rol_usuario']?.toString() == 'jefe_equipo' &&
              u['parent_id']?.toString() == filtroJefeVentasId)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();

      lista = lista
          .where((u) => idsEquipo.contains(u['parent_id']?.toString()))
          .toList();
    }

    if (filtroDirectorZonaId != null &&
        filtroJefeVentasId == null &&
        filtroJefeEquipoId == null) {
      final idsVentas = usuariosPermitidos
          .where((u) =>
              u['rol_usuario']?.toString() == 'jefe_ventas' &&
              u['parent_id']?.toString() == filtroDirectorZonaId)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();

      final idsEquipo = usuariosPermitidos
          .where((u) =>
              u['rol_usuario']?.toString() == 'jefe_equipo' &&
              idsVentas.contains(u['parent_id']?.toString()))
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();

      lista = lista
          .where((u) => idsEquipo.contains(u['parent_id']?.toString()))
          .toList();
    }

    return lista;
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

  String _valueToString(Map<String, dynamic> r, String key) {
    final value = r[key];
    if (value == null) return '';

    if (key.startsWith('fecha') || key == 'created_at') return _formatDate(value);
    if (key == 'requiere_visita') return value == true ? 'Sí' : 'No';
    if (key == 'prima_potencial') return _formatMoney(value);

    return value.toString();
  }

  String _formatMoney(dynamic value) {
    final n = double.tryParse(value?.toString() ?? '');
    if (n == null) return '';
    return '${n.toStringAsFixed(2)} €';
  }

  Set<String> _authIdsSegunFiltros() {
    if (filtroAgenteAuthId != null) return {filtroAgenteAuthId!};

    if (filtroJefeEquipoId != null) {
      return usuariosPermitidos
          .where((u) =>
              _esAgente(u) && u['parent_id']?.toString() == filtroJefeEquipoId)
          .map((u) => u['auth_id']?.toString())
          .whereType<String>()
          .where((e) => e.isNotEmpty && e != 'null')
          .toSet();
    }

    if (filtroJefeVentasId != null) {
      final idsEquipo = usuariosPermitidos
          .where((u) =>
              u['rol_usuario']?.toString() == 'jefe_equipo' &&
              u['parent_id']?.toString() == filtroJefeVentasId)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();

      return usuariosPermitidos
          .where((u) => _esAgente(u) && idsEquipo.contains(u['parent_id']?.toString()))
          .map((u) => u['auth_id']?.toString())
          .whereType<String>()
          .where((e) => e.isNotEmpty && e != 'null')
          .toSet();
    }

    if (filtroDirectorZonaId != null) {
      final idsVentas = usuariosPermitidos
          .where((u) =>
              u['rol_usuario']?.toString() == 'jefe_ventas' &&
              u['parent_id']?.toString() == filtroDirectorZonaId)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();

      final idsEquipo = usuariosPermitidos
          .where((u) =>
              u['rol_usuario']?.toString() == 'jefe_equipo' &&
              idsVentas.contains(u['parent_id']?.toString()))
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();

      return usuariosPermitidos
          .where((u) => _esAgente(u) && idsEquipo.contains(u['parent_id']?.toString()))
          .map((u) => u['auth_id']?.toString())
          .whereType<String>()
          .where((e) => e.isNotEmpty && e != 'null')
          .toSet();
    }

    return {};
  }

  bool _esAgente(Map<String, dynamic> u) {
    final r = u['rol_usuario']?.toString();
    return r == 'agente' || r == 'mediador' || r == 'comercial';
  }

  bool _estadoCoincide(Map<String, dynamic> r) {
    if (filtroEstado == 'Todos') return true;
    final e = r['estado']?.toString().toLowerCase().trim() ?? '';
    final res = r['resultados']?.toString().toLowerCase().trim() ?? '';

    if (filtroEstado == 'Abiertas') {
      return e != 'cerrada' &&
          e != 'cerrado' &&
          e != 'resuelto' &&
          e != 'contratado' &&
          e != 'desechado' &&
          e != 'sin exito' &&
          e != 'sin éxito';
    }
    if (filtroEstado == 'Pendientes') return e == 'pendiente' || e.isEmpty;
    if (filtroEstado == 'En gestión') {
      return e == 'en gestion' || e == 'en gestión' || e == 'gestion' || e == 'en curso';
    }
    if (filtroEstado == 'Cerradas') {
      return e == 'cerrada' || e == 'cerrado' || e == 'resuelto' || e == 'contratado';
    }
    if (filtroEstado == 'Cerradas con éxito') {
      return e == 'contratado' ||
          e == 'cerrada con exito' ||
          e == 'cerrada con éxito' ||
          res.contains('exito') ||
          res.contains('éxito') ||
          res.contains('contrat');
    }
    if (filtroEstado == 'Cerradas sin éxito') {
      return e == 'desechado' ||
          e == 'sin exito' ||
          e == 'sin éxito' ||
          res.contains('sin exito') ||
          res.contains('sin éxito') ||
          res.contains('rechaz') ||
          res.contains('no interesa');
    }

    return true;
  }

  List<Map<String, dynamic>> get referenciasFiltradas => referenciasFiltradasCache;

void _aplicarFiltros() {
  var lista = [...referencias];

  final authFiltro = _authIdsSegunFiltros();
  if (authFiltro.isNotEmpty) {
    lista = lista.where((r) => authFiltro.contains(r['auth_id']?.toString())).toList();
  }

  if (filtroTipoReferencia != 'Todos') {
    lista = lista.where((r) => r['tipo_referencia'] == filtroTipoReferencia).toList();
  }

  if (filtroPrioridad != 'Todas') {
    lista = lista.where((r) => r['prioridad']?.toString() == filtroPrioridad).toList();
  }

  if (filtroRequiereVisita != 'Todos') {
    final quiere = filtroRequiereVisita == 'Sí';
    lista = lista.where((r) => r['requiere_visita'] == quiere).toList();
  }

  lista = lista.where(_estadoCoincide).toList();

  if (fechaDesde != null) {
    final desde = DateTime(fechaDesde!.year, fechaDesde!.month, fechaDesde!.day);
    lista = lista.where((r) {
      final f = _parseDate(r['created_at']);
      if (f == null) return false;
      return !DateTime(f.year, f.month, f.day).isBefore(desde);
    }).toList();
  }

  if (fechaHasta != null) {
    final hasta = DateTime(fechaHasta!.year, fechaHasta!.month, fechaHasta!.day);
    lista = lista.where((r) {
      final f = _parseDate(r['created_at']);
      if (f == null) return false;
      return !DateTime(f.year, f.month, f.day).isAfter(hasta);
    }).toList();
  }

  final q = busqueda.toLowerCase().trim();
  if (q.isNotEmpty) {
    lista = lista.where((r) {
      return camposDisponibles.any(
        (c) => _valueToString(r, c.key).toLowerCase().contains(q),
      );
    }).toList();
  }

  if (sortKey != null) {
    lista.sort((a, b) {
      final av = _valueToString(a, sortKey!).toLowerCase();
      final bv = _valueToString(b, sortKey!).toLowerCase();
      return sortAsc ? av.compareTo(bv) : bv.compareTo(av);
    });
  }

  referenciasFiltradasCache = lista;
}

  void limpiarFiltros() {
    setState(() {
      busqueda = '';
      filtroDirectorZonaId = null;
      filtroJefeVentasId = null;
      filtroJefeEquipoId = null;
      filtroAgenteAuthId = null;
      filtroTipoReferencia = 'Todos';
      filtroEstado = 'Todos';
      filtroPrioridad = 'Todas';
      filtroRequiereVisita = 'Todos';
      fechaDesde = null;
      fechaHasta = null;
      referenciasSeleccionadas.clear();
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

  _CampoTabla _campo(String key) => camposDisponibles.firstWhere(
        (c) => c.key == key,
        orElse: () => _CampoTabla(key: key, titulo: key, grupo: 'Otros'),
      );

  void _toggleColumna(String key) {
    setState(() {
      if (columnasActivas.contains(key)) {
        if (columnasActivas.length > 1) columnasActivas.remove(key);
      } else {
        columnasActivas.add(key);
      }
    });
  }

  void _reordenarColumna(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = columnasActivas.removeAt(oldIndex);
      columnasActivas.insert(newIndex, item);
    });
  }

  void _ordenarPor(String key) {
    setState(() {
      if (sortKey == key) {
        sortAsc = !sortAsc;
      } else {
        sortKey = key;
        sortAsc = true;
      }
       _aplicarFiltros();
    });
  }

  Future<void> _reasignarReferencias(List<Map<String, dynamic>> refs) async {
    final agentesDestino = agentes;
    String? selectedAuthId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _modalShell(
              title: 'Reasignar referencias',
              subtitle: '${refs.length} referencia(s) seleccionada(s)',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedAuthId,
                    isExpanded: true,
                    decoration: _inputDecoration('Agente destino'),
                    items: agentesDestino.map((u) {
                      return DropdownMenuItem<String>(
                        value: u['auth_id']?.toString(),
                        child: Text(_nombreCompleto(u)),
                      );
                    }).toList(),
                    onChanged: (v) => setModalState(() => selectedAuthId = v),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: selectedAuthId == null
                          ? null
                          : () async {
                              Navigator.pop(context);
                              await _guardarReasignacion(refs, selectedAuthId!);
                            },
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Reasignar ahora'),
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

  Future<void> _guardarReasignacion(
    List<Map<String, dynamic>> refs,
    String nuevoAuthId,
  ) async {
    try {
      setState(() => guardando = true);

      final ids = refs.map((r) => r['id']?.toString()).whereType<String>().toList();

      await supabase
          .from('referencias_viables')
          .update({'auth_id': nuevoAuthId})
          .inFilter('id', ids);

      _snack('Referencias reasignadas correctamente');
      await cargarDatos();
      setState(() => referenciasSeleccionadas.clear());
    } catch (e) {
      _snack('Error reasignando referencias: $e');
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> _gestionarReferencias(List<Map<String, dynamic>> refs) async {
    String nuevoEstado = refs.length == 1
        ? (refs.first['estado']?.toString().isEmpty ?? true
            ? 'Pendiente'
            : refs.first['estado'].toString())
        : 'En gestión';
    String nuevoResultado = refs.length == 1 ? (refs.first['resultados']?.toString() ?? '') : '';
    String nuevaNota = refs.length == 1 ? (refs.first['nota_seguimiento']?.toString() ?? '') : '';
    bool? requiereVisita = refs.length == 1 ? refs.first['requiere_visita'] == true : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _modalShell(
              title: 'Gestionar referencias',
              subtitle: '${refs.length} referencia(s) seleccionada(s)',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: nuevoEstado,
                    isExpanded: true,
                    decoration: _inputDecoration('Estado'),
                    items: const [
                      'Pendiente',
                      'En gestión',
                      'Cerrada',
                      'Cerrada con éxito',
                      'Cerrada sin éxito',
                      'Desechado',
                    ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => nuevoEstado = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: nuevoResultado,
                    decoration: _inputDecoration('Resultado'),
                    onChanged: (v) => nuevoResultado = v,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: nuevaNota,
                    maxLines: 4,
                    decoration: _inputDecoration('Nota seguimiento'),
                    onChanged: (v) => nuevaNota = v,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<bool?>(
                    value: requiereVisita,
                    isExpanded: true,
                    decoration: _inputDecoration('Requiere visita'),
                    items: const [
                      DropdownMenuItem<bool?>(value: null, child: Text('No modificar')),
                      DropdownMenuItem<bool?>(value: true, child: Text('Sí')),
                      DropdownMenuItem<bool?>(value: false, child: Text('No')),
                    ],
                    onChanged: (v) => setModalState(() => requiereVisita = v),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _guardarGestion(
                          refs,
                          nuevoEstado,
                          nuevoResultado,
                          nuevaNota,
                          requiereVisita,
                        );
                      },
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Guardar cambios'),
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

  Future<void> _guardarGestion(
    List<Map<String, dynamic>> refs,
    String estado,
    String resultado,
    String nota,
    bool? requiereVisita,
  ) async {
    try {
      setState(() => guardando = true);

      final ids = refs.map((r) => r['id']?.toString()).whereType<String>().toList();
      final update = <String, dynamic>{
        'estado': estado,
        'resultados': resultado,
        'nota_seguimiento': nota,
        'fecha_seguimiento': DateTime.now().toIso8601String(),
      };

      if (requiereVisita != null) update['requiere_visita'] = requiereVisita;

      await supabase.from('referencias_viables').update(update).inFilter('id', ids);

      _snack('Referencias actualizadas correctamente');
      await cargarDatos();
      setState(() => referenciasSeleccionadas.clear());
    } catch (e) {
      _snack('Error guardando gestión: $e');
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  void _verDetalle(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _modalShell(
          title: 'Detalle de referencia',
          subtitle: r['nombre']?.toString() ?? 'Sin nombre',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: camposDisponibles.map((c) {
                  return _detailChip(c.titulo, _valueToString(r, c.key));
                }).toList(),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _reasignarReferencias([r]);
                      },
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Reasignar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _gestionarReferencias([r]);
                      },
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Gestionar'),
                      style: _primaryButtonStyle(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value.isEmpty ? '-' : value,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modalShell({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
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
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.hub_rounded, color: Color(0xFF0284C7)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF0F172A),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF0284C7),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoControlReferencias(),
          SafeArea(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0284C7)),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 980;

                      final contenido = Padding(
                        padding: EdgeInsets.fromLTRB(
                          isMobile ? 12 : 18,
                          18,
                          isMobile ? 12 : 22,
                          22,
                        ),
                        child: Column(
                          children: [
                            _header(),
                            const SizedBox(height: 14),
                            _barraAcciones(),
                            const SizedBox(height: 14),
                            Expanded(child: _tablaDinamica()),
                          ],
                        ),
                      );

                      if (isMobile) {
                        return Column(
                          children: [
                            SizedBox(
                              height: 330,
                              child: _panelCamposFiltros(compacto: true),
                            ),
                            Expanded(child: contenido),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          _panelCamposFiltros(),
                          Expanded(child: contenido),
                        ],
                      );
                    },
                  ),
          ),
          if (guardando)
            Container(
              color: Colors.black.withOpacity(0.18),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF0284C7)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelCamposFiltros({bool compacto = false}) {
    final grupos = <String, List<_CampoTabla>>{};
    for (final c in camposDisponibles) {
      grupos.putIfAbsent(c.grupo, () => []).add(c);
    }

    return Container(
      width: compacto ? double.infinity : 360,
      margin: EdgeInsets.all(compacto ? 10 : 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.blueGrey.withOpacity(0.14),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ListView(
        children: [
          const Text(
            'Control dinámico',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Activa columnas, filtra la estructura y gestiona referencias.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: (v) => setState(() {
  busqueda = v;
  _aplicarFiltros();
}),
            decoration: _inputDecoration('Buscar en toda la tabla').copyWith(
              prefixIcon: const Icon(Icons.search_rounded),
            ),
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
filtroAgenteAuthId = null;
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
filtroAgenteAuthId = null;
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
filtroAgenteAuthId = null;
_aplicarFiltros();
                });
              },
            ),
          if (agentes.isNotEmpty)
            _dropdownAgentes(
              label: 'Agente',
              value: filtroAgenteAuthId,
              usuarios: agentes,
              onChanged: (v) => setState(() {
  filtroAgenteAuthId = v;
  _aplicarFiltros();
}),
            ),
          _dropdownSimple(
            label: 'Tipo referencia',
            value: filtroTipoReferencia,
            items: const ['Todos', 'Propia agente', 'Seguimiento', 'Asignada compañía'],
            onChanged: (v) => setState(() {
  filtroTipoReferencia = v!;
  _aplicarFiltros();
}),
          ),
          _dropdownSimple(
            label: 'Estado',
            value: filtroEstado,
            items: const [
              'Todos',
              'Abiertas',
              'Pendientes',
              'En gestión',
              'Cerradas',
              'Cerradas con éxito',
              'Cerradas sin éxito',
            ],
            onChanged: (v) => setState(() {
  filtroEstado = v!;
  _aplicarFiltros();
}),
          ),
          _dropdownSimple(
            label: 'Prioridad',
            value: filtroPrioridad,
            items: const ['Todas', 'Alta', 'Media', 'Baja'],
           onChanged: (v) => setState(() {
  filtroPrioridad = v!;
  _aplicarFiltros();
}),
          ),
          _dropdownSimple(
            label: 'Requiere visita',
            value: filtroRequiereVisita,
            items: const ['Todos', 'Sí', 'No'],
           onChanged: (v) => setState(() {
  filtroRequiereVisita = v!;
  _aplicarFiltros();
}),
          ),
          _dateButton(label: 'Fecha desde', value: fechaDesde, onTap: () => _pickFecha(true)),
          _dateButton(label: 'Fecha hasta', value: fechaHasta, onTap: () => _pickFecha(false)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: limpiarFiltros,
            icon: const Icon(Icons.cleaning_services_rounded),
            label: const Text('Limpiar filtros'),
            style: _primaryButtonStyle(),
          ),
          const SizedBox(height: 22),
          const Text(
            'Columnas de la tabla',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...grupos.entries.map((entry) {
            return ExpansionTile(
              initiallyExpanded: entry.key == 'Estructura' || entry.key == 'Referencia',
              tilePadding: EdgeInsets.zero,
              title: Text(
                entry.key,
                style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
              children: entry.value.map((c) {
                final active = columnasActivas.contains(c.key);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  title: Text(c.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (_) => _toggleColumna(c.key),
                );
              }).toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _header() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final estrecho = constraints.maxWidth < 720;

        final botonVolver = InkWell(
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
              'Control de referencias',
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
              '${referenciasFiltradas.length} referencias visibles · ${referenciasSeleccionadas.length} seleccionadas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

        if (estrecho) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  botonVolver,
                  const SizedBox(width: 12),
                  Expanded(child: titulo),
                ],
              ),
              const SizedBox(height: 10),
              _badgeRole(),
            ],
          );
        }

        return Row(
          children: [
            botonVolver,
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

  Widget _barraAcciones() {
    final seleccionadas = referencias
        .where((r) => referenciasSeleccionadas.contains(r['id']?.toString()))
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.table_chart_rounded, color: Color(0xFF0284C7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Columnas activas: ${columnasActivas.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (seleccionadas.isNotEmpty)
                    Text(
                      '${seleccionadas.length} seleccionadas',
                      style: const TextStyle(
                        color: Color(0xFF0284C7),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: columnasActivas.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final key = columnasActivas[index];
                      final c = _campo(key);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.view_column_rounded, size: 17, color: Color(0xFF64748B)),
                            const SizedBox(width: 4),
                            Text(c.titulo, style: const TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _toggleColumna(key),
                              child: const Icon(Icons.close_rounded, size: 17, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (seleccionadas.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _reasignarReferencias(seleccionadas),
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: const Text('Reasignar selección'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _gestionarReferencias(seleccionadas),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Gestionar selección'),
                      style: _primaryButtonStyle(),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _tablaDinamica() {
  final todas = referenciasFiltradas;
  final lista = todas.take(150).toList();

  return Container(
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.94),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: lista.isEmpty
          ? const Center(
              child: Text(
                'No hay referencias para los filtros seleccionados.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Column(
              children: [
                Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  color: const Color(0xFFF1F5F9),
                  child: Row(
                    children: [
                      Text(
                        'Mostrando ${lista.length} de ${todas.length}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${referenciasSeleccionadas.length} seleccionadas',
                        style: const TextStyle(
                          color: Color(0xFF0284C7),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: lista.length,
                    itemBuilder: (context, index) {
                      final r = lista[index];
                      final id = r['id']?.toString() ?? '';
                      final selected = referenciasSeleccionadas.contains(id);

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFE0F2FE)
                              : const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF7DD3FC)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: selected,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    referenciasSeleccionadas.add(id);
                                  } else {
                                    referenciasSeleccionadas.remove(id);
                                  }
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: columnasActivas.map((key) {
                                  final c = _campo(key);
                                  return SizedBox(
                                    width: c.ancho,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.titulo,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        _cellValue(r, key),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded),
                              onSelected: (value) {
                                if (value == 'detalle') _verDetalle(r);
                                if (value == 'reasignar') {
                                  _reasignarReferencias([r]);
                                }
                                if (value == 'gestionar') {
                                  _gestionarReferencias([r]);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'detalle',
                                  child: Text('Ver detalles'),
                                ),
                                PopupMenuItem(
                                  value: 'reasignar',
                                  child: Text('Reasignar referencia'),
                                ),
                                PopupMenuItem(
                                  value: 'gestionar',
                                  child: Text('Gestionar referencia'),
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
    ),
  );
}

  Widget _cellValue(Map<String, dynamic> r, String key) {
    final text = _valueToString(r, key);

    if (key == 'estado') {
      return _pill(text.isEmpty ? 'Pendiente' : text, const Color(0xFF0284C7));
    }
    if (key == 'prioridad') {
      final color = text == 'Alta'
          ? const Color(0xFFDC2626)
          : text == 'Media'
              ? const Color(0xFFF97316)
              : const Color(0xFF16A34A);
      return _pill(text.isEmpty ? '-' : text, color);
    }
    if (key == 'tipo_referencia') {
      return _pill(text, const Color(0xFF7C3AED));
    }
    if (key == 'requiere_visita') {
      return _pill(text, text == 'Sí' ? const Color(0xFF16A34A) : const Color(0xFF64748B));
    }

    return Text(
      text.isEmpty ? '-' : text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontWeight: FontWeight.w700,
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
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }

  Widget _dropdownUsuarios({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> usuarios,
    required void Function(String?) onChanged,
  }) {
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

  Widget _dropdownAgentes({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> usuarios,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: _inputDecoration(label),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('Todos')),
          ...usuarios.map((u) => DropdownMenuItem<String>(value: u['auth_id']?.toString(), child: Text(_nombreCompleto(u)))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _dropdownSimple({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: _inputDecoration(label),
        items: items.map((e) => DropdownMenuItem<String>(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateButton({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    final text = value == null
        ? 'Sin seleccionar'
        : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF0284C7)),
      ),
    );
  }
}

class _CampoTabla {
  final String key;
  final String titulo;
  final String grupo;
  final double ancho;

  const _CampoTabla({
    required this.key,
    required this.titulo,
    required this.grupo,
    this.ancho = 160,
  });
}

class _FondoControlReferencias extends StatelessWidget {
  const _FondoControlReferencias();

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
