import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ControlAltasScreen extends StatefulWidget {
  const ControlAltasScreen({super.key});

  @override
  State<ControlAltasScreen> createState() => _ControlAltasScreenState();
}

class _ControlAltasScreenState extends State<ControlAltasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool guardando = false;

  String role = '';
  String? myId;
  String? myAuthId;

  int vista = 0; // 0 candidatos, 1 gestion jefes equipo

  List<Map<String, dynamic>> usuarios = [];
  List<Map<String, dynamic>> usuariosPermitidos = [];
  List<Map<String, dynamic>> candidatos = [];
  List<Map<String, dynamic>> candidatosFiltradosCache = [];

  final Set<String> candidatosSeleccionados = {};

  String busqueda = '';
  String? filtroDirectorZonaId;
  String? filtroJefeVentasId;
  String? filtroJefeEquipoId;
  String? filtroAgenteAuthId;
  String filtroEstado = 'Todos';
  String filtroOrigen = 'Todos';
  String filtroPrioridad = 'Todas';
  String filtroCiudad = 'Todas';
  String ratioSeleccionado = 'Incorporados / Incluidos';
  DateTime? fechaDesde;
  DateTime? fechaHasta;

  String? sortKey;
  bool sortAsc = true;

  final List<_CampoTabla> camposDisponibles = const [
    _CampoTabla(key: 'jefe_equipo_nombre', titulo: 'Jefe equipo', grupo: 'Estructura', ancho: 190),
    _CampoTabla(key: 'jefe_ventas_nombre', titulo: 'Jefe ventas', grupo: 'Estructura', ancho: 190),
    _CampoTabla(key: 'director_zona_nombre', titulo: 'Director zona', grupo: 'Estructura', ancho: 190),
    _CampoTabla(key: 'comercial_nombre', titulo: 'Comercial / usuario', grupo: 'Estructura', ancho: 190),
    _CampoTabla(key: 'nombre', titulo: 'Nombre candidato', grupo: 'Candidato', ancho: 220),
    _CampoTabla(key: 'telefono', titulo: 'Teléfono', grupo: 'Candidato', ancho: 140),
    _CampoTabla(key: 'email', titulo: 'Email', grupo: 'Candidato', ancho: 220),
    _CampoTabla(key: 'ciudad', titulo: 'Ciudad', grupo: 'Candidato', ancho: 140),
    _CampoTabla(key: 'estado', titulo: 'Estado', grupo: 'Gestión', ancho: 170),
    _CampoTabla(key: 'origen', titulo: 'Origen', grupo: 'Gestión', ancho: 160),
    _CampoTabla(key: 'prioridad', titulo: 'Prioridad', grupo: 'Gestión', ancho: 120),
    _CampoTabla(key: 'observaciones', titulo: 'Observaciones', grupo: 'Notas', ancho: 260),
    _CampoTabla(key: 'notas', titulo: 'Notas', grupo: 'Notas', ancho: 260),
    _CampoTabla(key: 'proxima_accion', titulo: 'Próxima acción', grupo: 'Seguimiento', ancho: 220),
    _CampoTabla(key: 'motivo_descarte', titulo: 'Motivo descarte', grupo: 'Seguimiento', ancho: 220),
    _CampoTabla(key: 'fecha_contacto', titulo: 'Fecha contacto', grupo: 'Fechas', ancho: 160),
    _CampoTabla(key: 'fecha_entrevista', titulo: 'Fecha entrevista', grupo: 'Fechas', ancho: 160),
    _CampoTabla(key: 'fecha_entrevista_programada', titulo: 'Entrevista programada', grupo: 'Fechas', ancho: 190),
    _CampoTabla(key: 'fecha_seleccion', titulo: 'Fecha selección', grupo: 'Fechas', ancho: 160),
    _CampoTabla(key: 'fecha_incorporacion', titulo: 'Fecha incorporación', grupo: 'Fechas', ancho: 180),
    _CampoTabla(key: 'fecha_proxima_accion', titulo: 'Fecha próxima acción', grupo: 'Fechas', ancho: 190),
    _CampoTabla(key: 'created_at', titulo: 'Fecha alta sistema', grupo: 'Fechas', ancho: 180),
    _CampoTabla(key: 'update_at', titulo: 'Última actualización', grupo: 'Fechas', ancho: 180),
    _CampoTabla(key: 'cv_url', titulo: 'CV', grupo: 'Sistema', ancho: 220),
    _CampoTabla(key: 'id', titulo: 'ID', grupo: 'Sistema', ancho: 220),
    _CampoTabla(key: 'auth_id', titulo: 'Auth ID', grupo: 'Sistema', ancho: 220),
    _CampoTabla(key: 'asignado_por', titulo: 'Asignado por', grupo: 'Sistema', ancho: 220),
  ];

  late List<String> columnasActivas = [
    'jefe_equipo_nombre',
    'nombre',
    'telefono',
    'email',
    'ciudad',
    'estado',
    'origen',
    'prioridad',
    'fecha_entrevista_programada',
    'proxima_accion',
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

      dynamic query = supabase.from('candidatos_captacion').select();

      if (!_veTodo()) {
        if (authIdsPermitidos.isEmpty) {
          candidatos = [];
          candidatosFiltradosCache = [];
          if (!mounted) return;
          setState(() => loading = false);
          return;
        }
        query = query.inFilter('auth_id', authIdsPermitidos);
      }

      final candidatosData = await query.order('created_at', ascending: false);

      candidatos = List<Map<String, dynamic>>.from(candidatosData).map((c) {
        return _enriquecerCandidato(c);
      }).toList();

      _aplicarFiltros();

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _snack('Error cargando control de altas: $e');
    }
  }

  bool _veTodo() => role == 'director_nacional' || role == 'administracion';

  Map<String, dynamic> _enriquecerCandidato(Map<String, dynamic> c) {
    final auth = c['auth_id']?.toString();
    final comercial = _usuarioPorAuth(auth);
    final jefeEquipo = _resolverJefeEquipo(comercial);
    final jefeVentas = _usuarioPorId(jefeEquipo?['parent_id']?.toString());
    final directorZona = _usuarioPorId(jefeVentas?['parent_id']?.toString());

    return {
      ...c,
      'comercial_nombre': comercial == null ? 'Sin usuario' : _nombreCompleto(comercial),
      'comercial_id': comercial?['id']?.toString(),
      'jefe_equipo_nombre': jefeEquipo == null ? '' : _nombreCompleto(jefeEquipo),
      'jefe_equipo_id': jefeEquipo?['id']?.toString(),
      'jefe_ventas_nombre': jefeVentas == null ? '' : _nombreCompleto(jefeVentas),
      'jefe_ventas_id': jefeVentas?['id']?.toString(),
      'director_zona_nombre': directorZona == null ? '' : _nombreCompleto(directorZona),
      'director_zona_id': directorZona?['id']?.toString(),
    };
  }

  Map<String, dynamic>? _resolverJefeEquipo(Map<String, dynamic>? usuario) {
    if (usuario == null) return null;
    final rol = usuario['rol_usuario']?.toString();
    if (rol == 'jefe_equipo') return usuario;
    return _usuarioPorId(usuario['parent_id']?.toString());
  }

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

  bool _esAgente(Map<String, dynamic> u) {
    final r = u['rol_usuario']?.toString();
    return r == 'agente' || r == 'mediador' || r == 'comercial';
  }

  List<Map<String, dynamic>> _usuariosPorRol(String rol) {
    return usuariosPermitidos.where((u) => u['rol_usuario']?.toString() == rol).toList();
  }

  List<Map<String, dynamic>> get directoresZona => _veTodo() ? _usuariosPorRol('director_zona') : [];

  List<Map<String, dynamic>> get jefesVentas {
    var lista = _usuariosPorRol('jefe_ventas');
    if (role == 'jefe_ventas') return [];
    if (filtroDirectorZonaId != null) {
      lista = lista.where((u) => u['parent_id']?.toString() == filtroDirectorZonaId).toList();
    }
    return lista;
  }

  List<Map<String, dynamic>> get jefesEquipo {
    var lista = _usuariosPorRol('jefe_equipo');

    if (filtroJefeVentasId != null) {
      lista = lista.where((u) => u['parent_id']?.toString() == filtroJefeVentasId).toList();
    }

    if (filtroDirectorZonaId != null && filtroJefeVentasId == null) {
      final idsVentas = usuariosPermitidos
          .where((u) => u['rol_usuario']?.toString() == 'jefe_ventas' && u['parent_id']?.toString() == filtroDirectorZonaId)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();
      lista = lista.where((u) => idsVentas.contains(u['parent_id']?.toString())).toList();
    }

    return lista;
  }

  List<Map<String, dynamic>> get agentes {
    var lista = usuariosPermitidos.where(_esAgente).toList();

    if (filtroJefeEquipoId != null) {
      lista = lista.where((u) => u['parent_id']?.toString() == filtroJefeEquipoId).toList();
    }

    if (filtroJefeVentasId != null && filtroJefeEquipoId == null) {
      final idsEquipo = usuariosPermitidos
          .where((u) => u['rol_usuario']?.toString() == 'jefe_equipo' && u['parent_id']?.toString() == filtroJefeVentasId)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();
      lista = lista.where((u) => idsEquipo.contains(u['parent_id']?.toString())).toList();
    }

    if (filtroDirectorZonaId != null && filtroJefeVentasId == null && filtroJefeEquipoId == null) {
      final idsVentas = usuariosPermitidos
          .where((u) => u['rol_usuario']?.toString() == 'jefe_ventas' && u['parent_id']?.toString() == filtroDirectorZonaId)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();
      final idsEquipo = usuariosPermitidos
          .where((u) => u['rol_usuario']?.toString() == 'jefe_equipo' && idsVentas.contains(u['parent_id']?.toString()))
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();
      lista = lista.where((u) => idsEquipo.contains(u['parent_id']?.toString())).toList();
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
    if (key.startsWith('fecha') || key == 'created_at' || key == 'update_at') return _formatDate(value);
    return value.toString();
  }

  _CampoTabla _campo(String key) => camposDisponibles.firstWhere(
        (c) => c.key == key,
        orElse: () => _CampoTabla(key: key, titulo: key, grupo: 'Otros'),
      );

  List<Map<String, dynamic>> get candidatosFiltrados => candidatosFiltradosCache;

  void _aplicarFiltros() {
    var lista = [...candidatos];

    if (filtroDirectorZonaId != null) {
      lista = lista.where((c) => c['director_zona_id']?.toString() == filtroDirectorZonaId).toList();
    }

    if (filtroJefeVentasId != null) {
      lista = lista.where((c) => c['jefe_ventas_id']?.toString() == filtroJefeVentasId).toList();
    }

    if (filtroJefeEquipoId != null) {
      lista = lista.where((c) => c['jefe_equipo_id']?.toString() == filtroJefeEquipoId).toList();
    }

    if (filtroAgenteAuthId != null) {
      lista = lista.where((c) => c['auth_id']?.toString() == filtroAgenteAuthId).toList();
    }

    if (filtroEstado != 'Todos') {
      lista = lista.where((c) => _normalizarEstado(c['estado']) == _normalizarEstado(filtroEstado)).toList();
    }

    if (filtroOrigen != 'Todos') {
      lista = lista.where((c) => c['origen']?.toString() == filtroOrigen).toList();
    }

    if (filtroPrioridad != 'Todas') {
      lista = lista.where((c) => c['prioridad']?.toString() == filtroPrioridad).toList();
    }

    if (filtroCiudad != 'Todas') {
      lista = lista.where((c) => c['ciudad']?.toString() == filtroCiudad).toList();
    }

    if (fechaDesde != null) {
      final desde = DateTime(fechaDesde!.year, fechaDesde!.month, fechaDesde!.day);
      lista = lista.where((c) {
        final f = _parseDate(c['created_at']);
        if (f == null) return false;
        return !DateTime(f.year, f.month, f.day).isBefore(desde);
      }).toList();
    }

    if (fechaHasta != null) {
      final hasta = DateTime(fechaHasta!.year, fechaHasta!.month, fechaHasta!.day);
      lista = lista.where((c) {
        final f = _parseDate(c['created_at']);
        if (f == null) return false;
        return !DateTime(f.year, f.month, f.day).isAfter(hasta);
      }).toList();
    }

    final q = busqueda.toLowerCase().trim();
    if (q.isNotEmpty) {
      lista = lista.where((c) {
        return camposDisponibles.any((campo) => _valueToString(c, campo.key).toLowerCase().contains(q));
      }).toList();
    }

    if (sortKey != null) {
      lista.sort((a, b) {
        final av = _valueToString(a, sortKey!).toLowerCase();
        final bv = _valueToString(b, sortKey!).toLowerCase();
        return sortAsc ? av.compareTo(bv) : bv.compareTo(av);
      });
    }

    candidatosFiltradosCache = lista;
  }

  String _normalizarEstado(dynamic value) {
    final e = value?.toString().toLowerCase().trim() ?? '';
    return e
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  List<String> get estadosDisponibles {
    final set = candidatos
        .map((c) => c['estado']?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Todos', ...set];
  }

  List<String> get origenesDisponibles {
    final set = candidatos
        .map((c) => c['origen']?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Todos', ...set];
  }

  List<String> get ciudadesDisponibles {
    final set = candidatos
        .map((c) => c['ciudad']?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Todas', ...set];
  }

  void limpiarFiltros() {
    setState(() {
      busqueda = '';
      filtroDirectorZonaId = null;
      filtroJefeVentasId = null;
      filtroJefeEquipoId = null;
      filtroAgenteAuthId = null;
      filtroEstado = 'Todos';
      filtroOrigen = 'Todos';
      filtroPrioridad = 'Todas';
      filtroCiudad = 'Todas';
      fechaDesde = null;
      fechaHasta = null;
      candidatosSeleccionados.clear();
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

  void _toggleColumna(String key) {
    setState(() {
      if (columnasActivas.contains(key)) {
        if (columnasActivas.length > 1) columnasActivas.remove(key);
      } else {
        columnasActivas.add(key);
      }
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

  Future<void> _gestionarCandidatos(List<Map<String, dynamic>> refs) async {
    String nuevoEstado = _estadoParaDropdown(
  refs.length == 1 ? refs.first['estado']?.toString() : null,
);
    String nuevaPrioridad = refs.length == 1 ? (refs.first['prioridad']?.toString() ?? 'Media') : 'Media';
    String observaciones = refs.length == 1 ? (refs.first['observaciones']?.toString() ?? '') : '';
    String notas = refs.length == 1 ? (refs.first['notas']?.toString() ?? '') : '';
    String proximaAccion = refs.length == 1 ? (refs.first['proxima_accion']?.toString() ?? '') : '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _modalShell(
              title: 'Gestionar candidatos',
              subtitle: '${refs.length} candidato(s) seleccionado(s)',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: nuevoEstado,
                    isExpanded: true,
                    decoration: _inputDecoration('Estado'),
                    items: const [
                      'Nuevo',
                      'Contactado',
                      'Entrevista programada',
                      'Entrevistado',
                      'Seleccionado',
                      'Descartado',
                      'Incorporado',
                    ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => nuevoEstado = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: nuevaPrioridad,
                    isExpanded: true,
                    decoration: _inputDecoration('Prioridad'),
                    items: const ['Alta', 'Media', 'Baja']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setModalState(() => nuevaPrioridad = v!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: proximaAccion,
                    decoration: _inputDecoration('Próxima acción'),
                    onChanged: (v) => proximaAccion = v,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: observaciones,
                    maxLines: 3,
                    decoration: _inputDecoration('Observaciones'),
                    onChanged: (v) => observaciones = v,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: notas,
                    maxLines: 3,
                    decoration: _inputDecoration('Notas'),
                    onChanged: (v) => notas = v,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _guardarGestion(refs, nuevoEstado, nuevaPrioridad, observaciones, notas, proximaAccion);
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
  String _estadoParaDropdown(dynamic value) {
  final e = _normalizarEstado(value);

  if (e == 'nuevo') return 'Nuevo';
  if (e == 'contactado') return 'Contactado';
  if (e == 'entrevista programada') return 'Entrevista programada';
  if (e == 'entrevistado' || e == 'entrevistada') return 'Entrevistado';
  if (e == 'seleccionado' || e == 'seleccionada') return 'Seleccionado';
  if (e == 'descartado' || e == 'descartada') return 'Descartado';
  if (e == 'incorporado' || e == 'incorporada') return 'Incorporado';

  return 'Contactado';
}

  Future<void> _guardarGestion(
    List<Map<String, dynamic>> refs,
    String estado,
    String prioridad,
    String observaciones,
    String notas,
    String proximaAccion,
  ) async {
    try {
      setState(() => guardando = true);
      final ids = refs.map((r) => r['id']?.toString()).whereType<String>().toList();
      final now = DateTime.now().toIso8601String();
      final update = <String, dynamic>{
        'estado': estado,
        'prioridad': prioridad,
        'observaciones': observaciones,
        'notas': notas,
        'proxima_accion': proximaAccion,
        'update_at': now,
      };

      final normal = _normalizarEstado(estado);
      if (normal.contains('entrevista')) update['fecha_entrevista_programada'] = now;
      if (normal == 'entrevistado') update['fecha_entrevista'] = now;
      if (normal == 'seleccionado') update['fecha_seleccion'] = now;
      if (normal == 'incorporado') update['fecha_incorporacion'] = now;
      if (normal == 'contactado') update['fecha_contacto'] = now;

      await supabase.from('candidatos_captacion').update(update).inFilter('id', ids);

      _snack('Candidatos actualizados correctamente');
      await cargarDatos();
      setState(() => candidatosSeleccionados.clear());
    } catch (e) {
      _snack('Error guardando candidatos: $e');
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  void _verDetalle(Map<String, dynamic> c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _modalShell(
          title: 'Detalle de candidato',
          subtitle: c['nombre']?.toString() ?? 'Sin nombre',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: camposDisponibles.map((campo) {
                  return _detailChip(campo.titulo, _valueToString(c, campo.key));
                }).toList(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _gestionarCandidatos([c]);
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Gestionar candidato'),
                  style: _primaryButtonStyle(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

 List<Map<String, dynamic>> get _resumenJefesEquipo {
  final map = <String, Map<String, dynamic>>{};

  List<Map<String, dynamic>> base;

  if (filtroJefeEquipoId != null) {
    base = usuariosPermitidos
        .where((u) => u['id']?.toString() == filtroJefeEquipoId)
        .toList();
  } else if (filtroJefeVentasId != null) {
    base = usuariosPermitidos
        .where((u) =>
            u['rol_usuario']?.toString() == 'jefe_equipo' &&
            u['parent_id']?.toString() == filtroJefeVentasId)
        .toList();
  } else if (filtroDirectorZonaId != null) {
    final idsJefesVentas = usuariosPermitidos
        .where((u) =>
            u['rol_usuario']?.toString() == 'jefe_ventas' &&
            u['parent_id']?.toString() == filtroDirectorZonaId)
        .map((u) => u['id']?.toString())
        .whereType<String>()
        .toSet();

    base = usuariosPermitidos
        .where((u) =>
            u['rol_usuario']?.toString() == 'jefe_equipo' &&
            idsJefesVentas.contains(u['parent_id']?.toString()))
        .toList();
  } else if (role == 'jefe_ventas' && myId != null) {
    base = usuariosPermitidos
        .where((u) =>
            u['rol_usuario']?.toString() == 'jefe_equipo' &&
            u['parent_id']?.toString() == myId)
        .toList();
  } else {
    base = usuariosPermitidos
        .where((u) => u['rol_usuario']?.toString() == 'jefe_equipo')
        .toList();
  }

  for (final jefe in base) {
    final jefeId = jefe['id']?.toString() ?? '';
    if (jefeId.isEmpty) continue;

    final jefeVentas = _usuarioPorId(jefe['parent_id']?.toString());
    final directorZona = _usuarioPorId(jefeVentas?['parent_id']?.toString());

    map[jefeId] = {
      'jefe_id': jefeId,
      'jefe_equipo': _nombreCompleto(jefe),
      'jefe_ventas': jefeVentas == null ? '' : _nombreCompleto(jefeVentas),
      'director_zona': directorZona == null ? '' : _nombreCompleto(directorZona),
      'incluidos': 0,
      'contactados': 0,
      'entrevista_programada': 0,
      'entrevistados': 0,
      'seleccionados': 0,
      'descartados': 0,
      'incorporados': 0,
    };
  }

  for (final c in candidatosFiltrados) {
    final jefeId = c['jefe_equipo_id']?.toString() ?? '';
    if (jefeId.isEmpty || !map.containsKey(jefeId)) continue;

    final row = map[jefeId]!;
    row['incluidos'] = (row['incluidos'] as int) + 1;

    final e = _normalizarEstado(c['estado']);

    if (e.contains('contact')) {
      row['contactados'] = (row['contactados'] as int) + 1;
    }

    if (e.contains('program')) {
      row['entrevista_programada'] =
          (row['entrevista_programada'] as int) + 1;
    }

    if (e == 'entrevistado' || e == 'entrevistada' || e.contains('entrevist')) {
      row['entrevistados'] = (row['entrevistados'] as int) + 1;
    }

    if (e.contains('seleccion')) {
      row['seleccionados'] = (row['seleccionados'] as int) + 1;
    }

    if (e.contains('descart')) {
      row['descartados'] = (row['descartados'] as int) + 1;
    }

    if (e.contains('incorpor')) {
      row['incorporados'] = (row['incorporados'] as int) + 1;
    }
  }

  final list = map.values.toList();
  list.sort((a, b) => (b['incluidos'] as int).compareTo(a['incluidos'] as int));
  return list;
}

List<Map<String, dynamic>> get _resumenOrigenes {
  final map = <String, Map<String, dynamic>>{};

  for (final c in candidatosFiltrados) {
    final origen = (c['origen']?.toString().trim().isNotEmpty ?? false)
        ? c['origen'].toString().trim()
        : 'Sin origen';

    map.putIfAbsent(origen, () {
      return {
        'origen': origen,
        'incluidos': 0,
        'contactados': 0,
        'entrevista_programada': 0,
        'entrevistados': 0,
        'seleccionados': 0,
        'descartados': 0,
        'incorporados': 0,
      };
    });

    final row = map[origen]!;
    row['incluidos'] = (row['incluidos'] as int) + 1;

    final e = _normalizarEstado(c['estado']);

    if (e.contains('contact')) row['contactados'] = (row['contactados'] as int) + 1;
    if (e.contains('program')) row['entrevista_programada'] = (row['entrevista_programada'] as int) + 1;
    if (e.contains('entrevist')) row['entrevistados'] = (row['entrevistados'] as int) + 1;
    if (e.contains('seleccion')) row['seleccionados'] = (row['seleccionados'] as int) + 1;
    if (e.contains('descart')) row['descartados'] = (row['descartados'] as int) + 1;
    if (e.contains('incorpor')) row['incorporados'] = (row['incorporados'] as int) + 1;
  }

  final list = map.values.toList();
  list.sort((a, b) => (b['incluidos'] as int).compareTo(a['incluidos'] as int));
  return list;
}

  double _ratio(Map<String, dynamic> row) {
    final incluidos = (row['incluidos'] as int).toDouble();
    final entrevistados = (row['entrevistados'] as int).toDouble();
    final seleccionados = (row['seleccionados'] as int).toDouble();
    final descartados = (row['descartados'] as int).toDouble();
    final incorporados = (row['incorporados'] as int).toDouble();

    double div(double a, double b) => b <= 0 ? 0 : (a / b) * 100;

    if (ratioSeleccionado == 'Entrevistados / Incluidos') return div(entrevistados, incluidos);
    if (ratioSeleccionado == 'Seleccionados / Entrevistados') return div(seleccionados, entrevistados);
    if (ratioSeleccionado == 'Incorporados / Entrevistados') return div(incorporados, entrevistados);
    if (ratioSeleccionado == 'Incorporados / Seleccionados') return div(incorporados, seleccionados);
    if (ratioSeleccionado == 'Descartados / Incluidos') return div(descartados, incluidos);
    return div(incorporados, incluidos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoControlAltas(),
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
                            if (vista == 0) _barraAcciones(),
                            if (vista == 0) const SizedBox(height: 14),
                            Expanded(child: vista == 0 ? _tablaCandidatos() : _tablaGestionJefes()),
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
              'Control de altas',
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
              '${candidatosFiltrados.length} candidatos visibles · ${candidatosSeleccionados.length} seleccionados',
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
          Expanded(child: _tabButton('Candidatos', 0, Icons.person_search_rounded)),
         Expanded(child: _tabButton('Gestión estructura', 1, Icons.leaderboard_rounded)),
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
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF64748B),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelFiltros({bool compacto = false}) {
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
          BoxShadow(color: Colors.blueGrey.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 8)),
        ],
      ),
      child: ListView(
        children: [
          const Text(
            'Filtros de altas',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            'Analiza candidatos y altas por estructura.',
            style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, height: 1.3),
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: (v) => setState(() {
              busqueda = v;
              _aplicarFiltros();
            }),
            decoration: _inputDecoration('Buscar candidato').copyWith(prefixIcon: const Icon(Icons.search_rounded)),
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
              label: 'Comercial / usuario',
              value: filtroAgenteAuthId,
              usuarios: agentes,
              onChanged: (v) => setState(() {
                filtroAgenteAuthId = v;
                _aplicarFiltros();
              }),
            ),
          _dropdownSimple(
            label: 'Estado',
            value: filtroEstado,
            items: estadosDisponibles,
            onChanged: (v) => setState(() {
              filtroEstado = v!;
              _aplicarFiltros();
            }),
          ),
          _dropdownSimple(
            label: 'Origen',
            value: filtroOrigen,
            items: origenesDisponibles,
            onChanged: (v) => setState(() {
              filtroOrigen = v!;
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
            label: 'Ciudad',
            value: filtroCiudad,
            items: ciudadesDisponibles,
            onChanged: (v) => setState(() {
              filtroCiudad = v!;
              _aplicarFiltros();
            }),
          ),
          _dateButton(label: 'Fecha desde', value: fechaDesde, onTap: () => _pickFecha(true)),
          _dateButton(label: 'Fecha hasta', value: fechaHasta, onTap: () => _pickFecha(false)),
          _dropdownSimple(
            label: 'Ratio gestión jefes',
            value: ratioSeleccionado,
            items: const [
              'Incorporados / Incluidos',
              'Entrevistados / Incluidos',
              'Seleccionados / Entrevistados',
              'Incorporados / Entrevistados',
              'Incorporados / Seleccionados',
              'Descartados / Incluidos',
            ],
            onChanged: (v) => setState(() => ratioSeleccionado = v!),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: limpiarFiltros,
            icon: const Icon(Icons.cleaning_services_rounded),
            label: const Text('Limpiar filtros'),
            style: _primaryButtonStyle(),
          ),
          const SizedBox(height: 22),
          const Text(
            'Columnas candidatos',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...grupos.entries.map((entry) {
            return ExpansionTile(
              initiallyExpanded: entry.key == 'Estructura' || entry.key == 'Candidato',
              tilePadding: EdgeInsets.zero,
              title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
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

  Widget _barraAcciones() {
    final seleccionadas = candidatos.where((c) => candidatosSeleccionados.contains(c['id']?.toString())).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
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
                  '${seleccionadas.length} seleccionados',
                  style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w900),
                ),
            ],
          ),
          if (seleccionadas.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _gestionarCandidatos(seleccionadas),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Gestionar selección'),
                  style: _primaryButtonStyle(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _tablaCandidatos() {
    final todas = candidatosFiltrados;
    final lista = todas.take(160).toList();

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
                  'No hay candidatos para los filtros seleccionados.',
                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
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
                          style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        Text(
                          '${candidatosSeleccionados.length} seleccionados',
                          style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (context, index) {
                        final c = lista[index];
                        final id = c['id']?.toString() ?? '';
                        final selected = candidatosSeleccionados.contains(id);

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFE0F2FE) : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: selected ? const Color(0xFF7DD3FC) : const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: selected,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      candidatosSeleccionados.add(id);
                                    } else {
                                      candidatosSeleccionados.remove(id);
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
                                    final campo = _campo(key);
                                    return SizedBox(
                                      width: campo.ancho,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            campo.titulo,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w900),
                                          ),
                                          const SizedBox(height: 3),
                                          _cellValue(c, key),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded),
                                onSelected: (value) {
                                  if (value == 'detalle') _verDetalle(c);
                                  if (value == 'gestionar') _gestionarCandidatos([c]);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'detalle', child: Text('Ver detalles')),
                                  PopupMenuItem(value: 'gestionar', child: Text('Gestionar candidato')),
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

  Widget _tablaGestionJefes() {
  final rows = _resumenJefesEquipo;
  final origenes = _resumenOrigenes;

  final totalIncluidos =
      rows.fold<int>(0, (s, r) => s + ((r['incluidos'] ?? 0) as int));
  final totalContactados =
      rows.fold<int>(0, (s, r) => s + ((r['contactados'] ?? 0) as int));
  final totalProgramadas =
      rows.fold<int>(0, (s, r) => s + ((r['entrevista_programada'] ?? 0) as int));
  final totalEntrevistados =
      rows.fold<int>(0, (s, r) => s + ((r['entrevistados'] ?? 0) as int));
  final totalSeleccionados =
      rows.fold<int>(0, (s, r) => s + ((r['seleccionados'] ?? 0) as int));
  final totalDescartados =
      rows.fold<int>(0, (s, r) => s + ((r['descartados'] ?? 0) as int));
  final totalIncorporados =
      rows.fold<int>(0, (s, r) => s + ((r['incorporados'] ?? 0) as int));

  final totalRow = {
    'incluidos': totalIncluidos,
    'contactados': totalContactados,
    'entrevista_programada': totalProgramadas,
    'entrevistados': totalEntrevistados,
    'seleccionados': totalSeleccionados,
    'descartados': totalDescartados,
    'incorporados': totalIncorporados,
  };

  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.94),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: rows.isEmpty
          ? const Center(
              child: Text(
                'No hay datos de gestión para estos filtros.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  color: const Color(0xFFF1F5F9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resumen por estructura',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _miniTotal('Incluidos', totalIncluidos),
                          _miniTotal('Contactados', totalContactados),
                          _miniTotal('Ent. program.', totalProgramadas),
                          _miniTotal('Entrevistados', totalEntrevistados),
                          _miniTotal('Seleccionados', totalSeleccionados),
                          _miniTotal('Descartados', totalDescartados),
                          _miniTotal('Incorporados', totalIncorporados),
                          _miniTotal(
                            'Ratio',
                            _ratio(totalRow).round(),
                            suffix: '%',
                            color: const Color(0xFF0284C7),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ratio seleccionado: $ratioSeleccionado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0284C7),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
  child: ListView(
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Text(
          'Resumen por origen de captación',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      ...origenes.map((r) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                r['origen'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _miniTotal('Incluidos', r['incluidos']),
                  _miniTotal('Contactados', r['contactados']),
                  _miniTotal('Ent. program.', r['entrevista_programada']),
                  _miniTotal('Entrevistados', r['entrevistados']),
                  _miniTotal('Seleccionados', r['seleccionados']),
                  _miniTotal('Descartados', r['descartados']),
                  _miniTotal('Incorporados', r['incorporados']),
                  _miniTotal(
                    'Ratio',
                    _ratio(r).toStringAsFixed(1),
                    suffix: '%',
                    color: const Color(0xFF0284C7),
                  ),
                ],
              ),
            ],
          ),
        );
      }),

      const Padding(
        padding: EdgeInsets.fromLTRB(14, 18, 14, 6),
        child: Text(
          'Resumen por jefe de equipo',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      ...rows.map<Widget>((r) {
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
          r['jefe_equipo'].toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${r['jefe_ventas']} · ${r['director_zona']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _miniTotal('Incluidos', r['incluidos']),
            _miniTotal('Contactados', r['contactados']),
            _miniTotal('Ent. program.', r['entrevista_programada']),
            _miniTotal('Entrevistados', r['entrevistados']),
            _miniTotal('Seleccionados', r['seleccionados']),
            _miniTotal('Descartados', r['descartados']),
            _miniTotal('Incorporados', r['incorporados']),
            _miniTotal(
              'Ratio',
              _ratio(r).toStringAsFixed(1),
              suffix: '%',
              color: const Color(0xFF0284C7),
            ),
          ],
        ),
      ],
    ),
  );
}).toList(),
    ],
  ),
),
              ],
            ),
    ),
  );
}

Widget _miniTotal(
  String label,
  dynamic value, {
  String suffix = '',
  Color color = const Color(0xFF0F172A),
}) {
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
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$value$suffix',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

  Widget _resText(String label, String value, {bool big = false, Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color ?? const Color(0xFF0F172A), fontSize: big ? 15 : 20, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _cellValue(Map<String, dynamic> r, String key) {
    final text = _valueToString(r, key);
    if (key == 'estado') return _pill(text.isEmpty ? 'Nuevo' : text, const Color(0xFF0284C7));
    if (key == 'prioridad') {
      final color = text == 'Alta'
          ? const Color(0xFFDC2626)
          : text == 'Media'
              ? const Color(0xFFF97316)
              : const Color(0xFF16A34A);
      return _pill(text.isEmpty ? '-' : text, color);
    }
    if (key == 'origen') return _pill(text.isEmpty ? '-' : text, const Color(0xFF7C3AED));

    return Text(
      text.isEmpty ? '-' : text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700),
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
                    child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF0284C7)),
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

  Widget _dropdownAgentes({required String label, required String? value, required List<Map<String, dynamic>> usuarios, required void Function(String?) onChanged}) {
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

class _CampoTabla {
  final String key;
  final String titulo;
  final String grupo;
  final double ancho;

  const _CampoTabla({required this.key, required this.titulo, required this.grupo, this.ancho = 160});
}

class _FondoControlAltas extends StatelessWidget {
  const _FondoControlAltas();

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
