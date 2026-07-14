import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class CargarGestionesScreen extends StatefulWidget {
  const CargarGestionesScreen({super.key});

  @override
  State<CargarGestionesScreen> createState() => _CargarGestionesScreenState();
}

class _CargarGestionesScreenState extends State<CargarGestionesScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool guardando = false;

  String role = '';
  String? myId;
  String? myAuthId;

  List<Map<String, dynamic>> usuarios = [];
  List<Map<String, dynamic>> usuariosPermitidos = [];
  List<Map<String, dynamic>> gestiones = [];

  String? filtroDirectorZonaId;
  String? filtroJefeVentasId;
  String? filtroJefeEquipoId;
  String? filtroUsuarioAuthId;
  String filtroEstado = 'Todos';
  String filtroPrioridad = 'Todas';
  String filtroTipo = 'Todos';
  String busqueda = '';

  final tituloCtrl = TextEditingController();
  final descripcionCtrl = TextEditingController();
  String? destinoAuthId;
  String tipoGestion = 'Seguimiento';
  String prioridadGestion = 'Media';
  DateTime? fechaLimite;
  PlatformFile? archivoGestion;

  final tipos = const [
    'Seguimiento',
    'Llamada',
    'Visita',
    'Documentación',
    'Recibo',
    'Referencia',
    'Incidencia',
    'Formación',
    'Solicitud de baja',
    'Otro',
  ];

  final prioridades = const ['Alta', 'Media', 'Baja'];
  final estados = const ['Pendiente', 'En gestión', 'Completada', 'Cancelada'];

  @override
  void initState() {
    super.initState();
    cargarDatos();
  }

  @override
  void dispose() {
    tituloCtrl.dispose();
    descripcionCtrl.dispose();
    super.dispose();
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

      await cargarGestiones();

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _snack('Error cargando gestiones: $e');
    }
  }

  Future<void> cargarGestiones() async {
    final authIdsPermitidos = usuariosPermitidos
        .map((u) => u['auth_id']?.toString() ?? '')
        .where((e) => e.isNotEmpty && e != 'null')
        .toList();

    dynamic query = supabase.from('gestiones_asignadas').select();

    if (!_veTodo()) {
      if (authIdsPermitidos.isEmpty) {
        gestiones = [];
        return;
      }
      query = query.inFilter('asignado_a_auth_id', authIdsPermitidos);
    }

    final data = await query.order('created_at', ascending: false);
    gestiones = List<Map<String, dynamic>>.from(data).map(_enriquecerGestion).toList();
  }

  bool _veTodo() => role == 'director_nacional' || role == 'administracion';

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

  Map<String, dynamic> _enriquecerGestion(Map<String, dynamic> g) {
    final destino = _usuarioPorAuth(g['asignado_a_auth_id']?.toString());
    final creador = _usuarioPorAuth(g['asignado_por_auth_id']?.toString());
    final estructura = _resolverEstructura(destino);

    return {
      ...g,
      'destino_nombre': destino == null ? 'Sin usuario' : _nombreCompleto(destino),
      'creador_nombre': creador == null ? 'Sistema' : _nombreCompleto(creador),
      'jefe_equipo_nombre': estructura['jefe_equipo_nombre'] ?? '',
      'jefe_equipo_id': estructura['jefe_equipo_id'],
      'jefe_ventas_nombre': estructura['jefe_ventas_nombre'] ?? '',
      'jefe_ventas_id': estructura['jefe_ventas_id'],
      'director_zona_nombre': estructura['director_zona_nombre'] ?? '',
      'director_zona_id': estructura['director_zona_id'],
    };
  }

  Map<String, dynamic> _resolverEstructura(Map<String, dynamic>? u) {
    Map<String, dynamic>? jefeEquipo;
    Map<String, dynamic>? jefeVentas;
    Map<String, dynamic>? directorZona;

    if (u == null) return {};

    final rol = u['rol_usuario']?.toString();

    if (rol == 'director_zona') {
      directorZona = u;
    } else if (rol == 'jefe_ventas') {
      jefeVentas = u;
      directorZona = _usuarioPorId(u['parent_id']?.toString());
    } else if (rol == 'jefe_equipo') {
      jefeEquipo = u;
      jefeVentas = _usuarioPorId(u['parent_id']?.toString());
      directorZona = _usuarioPorId(jefeVentas?['parent_id']?.toString());
    } else {
      jefeEquipo = _usuarioPorId(u['parent_id']?.toString());
      jefeVentas = _usuarioPorId(jefeEquipo?['parent_id']?.toString());
      directorZona = _usuarioPorId(jefeVentas?['parent_id']?.toString());
    }

    return {
      'jefe_equipo_id': jefeEquipo?['id']?.toString(),
      'jefe_equipo_nombre': jefeEquipo == null ? '' : _nombreCompleto(jefeEquipo),
      'jefe_ventas_id': jefeVentas?['id']?.toString(),
      'jefe_ventas_nombre': jefeVentas == null ? '' : _nombreCompleto(jefeVentas),
      'director_zona_id': directorZona?['id']?.toString(),
      'director_zona_nombre': directorZona == null ? '' : _nombreCompleto(directorZona),
    };
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

  String _nombreCompleto(Map<String, dynamic> u) {
    final nombre = u['nombre']?.toString() ?? '';
    final apellidos = u['apellidos']?.toString() ?? '';
    final completo = '$nombre $apellidos'.trim();
    return completo.isEmpty ? (u['email']?.toString() ?? 'Sin nombre') : completo;
  }

  List<Map<String, dynamic>> _usuariosPorRol(String rol) {
    return usuariosPermitidos.where((u) => u['rol_usuario']?.toString() == rol).toList();
  }

  bool _esUsuarioAsignable(Map<String, dynamic> u) {
    final auth = u['auth_id']?.toString() ?? '';
    final rol = u['rol_usuario']?.toString() ?? '';
    return auth.isNotEmpty && auth != 'null' && rol != 'director_nacional' && rol != 'administracion';
  }

  List<Map<String, dynamic>> get usuariosAsignables {
    var lista = usuariosPermitidos.where(_esUsuarioAsignable).toList();

    if (filtroDirectorZonaId != null) {
      lista = lista.where((u) => _resolverEstructura(u)['director_zona_id'] == filtroDirectorZonaId).toList();
    }
    if (filtroJefeVentasId != null) {
      lista = lista.where((u) => _resolverEstructura(u)['jefe_ventas_id'] == filtroJefeVentasId).toList();
    }
    if (filtroJefeEquipoId != null) {
      lista = lista.where((u) => _resolverEstructura(u)['jefe_equipo_id'] == filtroJefeEquipoId).toList();
    }

    return lista;
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

  List<Map<String, dynamic>> get gestionesFiltradas {
    var lista = [...gestiones];

    if (filtroDirectorZonaId != null) {
      lista = lista.where((g) => g['director_zona_id']?.toString() == filtroDirectorZonaId).toList();
    }
    if (filtroJefeVentasId != null) {
      lista = lista.where((g) => g['jefe_ventas_id']?.toString() == filtroJefeVentasId).toList();
    }
    if (filtroJefeEquipoId != null) {
      lista = lista.where((g) => g['jefe_equipo_id']?.toString() == filtroJefeEquipoId).toList();
    }
    if (filtroUsuarioAuthId != null) {
      lista = lista.where((g) => g['asignado_a_auth_id']?.toString() == filtroUsuarioAuthId).toList();
    }
    if (filtroEstado != 'Todos') {
      lista = lista.where((g) => g['estado']?.toString() == filtroEstado).toList();
    }
    if (filtroPrioridad != 'Todas') {
      lista = lista.where((g) => g['prioridad']?.toString() == filtroPrioridad).toList();
    }
    if (filtroTipo != 'Todos') {
      lista = lista.where((g) => g['tipo']?.toString() == filtroTipo).toList();
    }

    final q = busqueda.toLowerCase().trim();
    if (q.isNotEmpty) {
      lista = lista.where((g) {
        final text = '${g['titulo']} ${g['descripcion']} ${g['destino_nombre']} ${g['creador_nombre']} ${g['tipo']} ${g['estado']}'.toLowerCase();
        return text.contains(q);
      }).toList();
    }

    return lista;
  }


  Future<void> _seleccionarArchivoGestion() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      archivoGestion = result.files.first;
    });
  }

  void _quitarArchivoGestion() {
    setState(() {
      archivoGestion = null;
    });
  }

  String _limpiarNombreArchivo(String name) {
    return name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll('__', '_');
  }

  Future<Map<String, String?>> _subirArchivoGestion() async {
    if (archivoGestion == null) {
      return {
        'url': null,
        'nombre': null,
        'tipo': null,
      };
    }

    final bytes = archivoGestion!.bytes;
    if (bytes == null) {
      throw Exception('No se pudo leer el archivo seleccionado. Vuelve a seleccionarlo.');
    }

    final originalName = archivoGestion!.name;
    final cleanName = _limpiarNombreArchivo(originalName);
    final extension = archivoGestion!.extension ?? '';
    final owner = myAuthId ?? 'sin_usuario';
    final storagePath = '$owner/${DateTime.now().millisecondsSinceEpoch}_$cleanName';

    await supabase.storage.from('gestiones-archivos').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );

    final publicUrl = supabase.storage
        .from('gestiones-archivos')
        .getPublicUrl(storagePath);

    return {
      'url': publicUrl,
      'nombre': originalName,
      'tipo': extension,
    };
  }

  bool _tieneArchivo(Map<String, dynamic> g) {
    final url = g['archivo_url']?.toString().trim() ?? '';
    return url.isNotEmpty;
  }

  Future<void> _abrirArchivo(String? url) async {
    final cleanUrl = url?.trim() ?? '';
    if (cleanUrl.isEmpty) {
      _snack('Esta gestión no tiene archivo adjunto');
      return;
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null) {
      _snack('El enlace del archivo no es válido');
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _snack('No se pudo abrir el archivo');
    }
  }

  Future<void> _crearGestion() async {
    final titulo = tituloCtrl.text.trim();
    final descripcion = descripcionCtrl.text.trim();

    if (destinoAuthId == null || destinoAuthId!.isEmpty) {
      _snack('Selecciona un usuario destino');
      return;
    }
    if (titulo.isEmpty) {
      _snack('Escribe un título para la gestión');
      return;
    }
    if (myAuthId == null || myAuthId!.isEmpty) {
      _snack('No se ha podido identificar el usuario logueado');
      return;
    }

    try {
      setState(() => guardando = true);

      final archivoInfo = await _subirArchivoGestion();

      final insert = {
        'asignado_a_auth_id': destinoAuthId,
        'asignado_por_auth_id': myAuthId,
        'titulo': titulo,
        'descripcion': descripcion,
        'tipo': tipoGestion,
        'prioridad': prioridadGestion,
        'estado': 'Pendiente',
        'fecha_limite': fechaLimite?.toIso8601String(),
        'archivo_url': archivoInfo['url'],
        'archivo_nombre': archivoInfo['nombre'],
        'archivo_tipo': archivoInfo['tipo'],
      };

      final creada = await supabase
          .from('gestiones_asignadas')
          .insert(insert)
          .select()
          .single();

      await supabase.from('notificaciones').insert({
        'auth_id': destinoAuthId,
        'titulo': 'Nueva gestión asignada',
        'mensaje': titulo,
        'tipo': 'gestion',
        'leida': false,
        'referencia_id': creada['id'],
        'pantalla_destino': 'mis_gestiones',
        'archivo_url': archivoInfo['url'],
        'archivo_nombre': archivoInfo['nombre'],
      });

      tituloCtrl.clear();
      descripcionCtrl.clear();
      fechaLimite = null;
      destinoAuthId = null;
      tipoGestion = 'Seguimiento';
      prioridadGestion = 'Media';
      archivoGestion = null;

      await cargarGestiones();
      if (!mounted) return;
      setState(() {});
      _snack('Gestión asignada y notificación creada');
    } catch (e) {
      _snack('Error creando gestión: $e');
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> _actualizarGestion(Map<String, dynamic> g) async {
    String estado = g['estado']?.toString() ?? 'Pendiente';
    String prioridad = g['prioridad']?.toString() ?? 'Media';
    String descripcion = g['descripcion']?.toString() ?? '';
    String? nuevoDestino = g['asignado_a_auth_id']?.toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _modalShell(
              title: 'Gestionar gestión',
              subtitle: g['titulo']?.toString() ?? 'Sin título',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: estados.contains(estado) ? estado : 'Pendiente',
                    isExpanded: true,
                    decoration: _inputDecoration('Estado'),
                    items: estados.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => estado = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: prioridades.contains(prioridad) ? prioridad : 'Media',
                    isExpanded: true,
                    decoration: _inputDecoration('Prioridad'),
                    items: prioridades.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => prioridad = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: nuevoDestino,
                    isExpanded: true,
                    decoration: _inputDecoration('Reasignar a'),
                    items: usuariosAsignables
                        .map((u) => DropdownMenuItem<String>(
                              value: u['auth_id']?.toString(),
                              child: Text(_nombreCompleto(u)),
                            ))
                        .toList(),
                    onChanged: (v) => setModalState(() => nuevoDestino = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: descripcion,
                    maxLines: 4,
                    decoration: _inputDecoration('Descripción / actualización'),
                    onChanged: (v) => descripcion = v,
                  ),
                  if (_tieneArchivo(g)) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _abrirArchivo(g['archivo_url']?.toString()),
                        icon: const Icon(Icons.attach_file_rounded),
                        label: Text('Abrir archivo: ${g['archivo_nombre']?.toString() ?? 'Adjunto'}'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _guardarActualizacionGestion(g, estado, prioridad, descripcion, nuevoDestino);
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

  Future<void> _guardarActualizacionGestion(
    Map<String, dynamic> g,
    String estado,
    String prioridad,
    String descripcion,
    String? nuevoDestino,
  ) async {
    try {
      setState(() => guardando = true);
      final id = g['id']?.toString();
      if (id == null || id.isEmpty) return;

      final destinoAnterior = g['asignado_a_auth_id']?.toString();

      await supabase.from('gestiones_asignadas').update({
        'estado': estado,
        'prioridad': prioridad,
        'descripcion': descripcion,
        'asignado_a_auth_id': nuevoDestino,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      if (nuevoDestino != null && nuevoDestino != destinoAnterior) {
        await supabase.from('notificaciones').insert({
          'auth_id': nuevoDestino,
          'titulo': 'Gestión reasignada',
          'mensaje': g['titulo']?.toString() ?? 'Tienes una nueva gestión',
          'tipo': 'gestion',
          'leida': false,
          'referencia_id': id,
          'pantalla_destino': 'mis_gestiones',
          'archivo_url': g['archivo_url'],
          'archivo_nombre': g['archivo_nombre'],
        });
      }

      await cargarGestiones();
      if (!mounted) return;
      setState(() {});
      _snack('Gestión actualizada');
    } catch (e) {
      _snack('Error actualizando gestión: $e');
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> _pickFechaLimite() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (date == null) return;
    setState(() => fechaLimite = date);
  }

  String _formatDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '';
    final d = DateTime.tryParse(value.toString());
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  void limpiarFiltros() {
    setState(() {
      filtroDirectorZonaId = null;
      filtroJefeVentasId = null;
      filtroJefeEquipoId = null;
      filtroUsuarioAuthId = null;
      filtroEstado = 'Todos';
      filtroPrioridad = 'Todas';
      filtroTipo = 'Todos';
      busqueda = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoGestiones(),
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
                            Expanded(
                              child: isMobile
                                  ? ListView(
                                      children: [
                                        _formCrearGestion(),
                                        const SizedBox(height: 14),
                                        SizedBox(height: 620, child: _listadoGestiones()),
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(width: 420, child: _formCrearGestion()),
                                        const SizedBox(width: 16),
                                        Expanded(child: _listadoGestiones()),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      );

                      if (isMobile) {
                        return Column(
                          children: [
                            SizedBox(height: 300, child: _panelFiltros(compacto: true)),
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
    return Row(
      children: [
        InkWell(
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
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cargar gestiones',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xFF0F172A), fontSize: 25, fontWeight: FontWeight.w900),
              ),
              Text(
                '${gestionesFiltradas.length} gestiones visibles',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        _badgeRole(),
      ],
    );
  }

  Widget _badgeRole() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7DD3FC)),
      ),
      child: Text(
        role.replaceAll('_', ' ').toUpperCase(),
        style: const TextStyle(color: Color(0xFF075985), fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }

  Widget _panelFiltros({bool compacto = false}) {
    return Container(
      width: compacto ? double.infinity : 340,
      margin: EdgeInsets.all(compacto ? 10 : 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.10), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: ListView(
        children: [
          const Text('Filtros', style: TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          const Text('Filtra por estructura, usuario, tipo, prioridad y estado.', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          TextField(
            onChanged: (v) => setState(() => busqueda = v),
            decoration: _inputDecoration('Buscar gestión').copyWith(prefixIcon: const Icon(Icons.search_rounded)),
          ),
          const SizedBox(height: 14),
          if (directoresZona.isNotEmpty)
            _dropdownUsuarios(
              label: 'Director zona',
              value: filtroDirectorZonaId,
              usuarios: directoresZona,
              onChanged: (v) => setState(() {
                filtroDirectorZonaId = v;
                filtroJefeVentasId = null;
                filtroJefeEquipoId = null;
                filtroUsuarioAuthId = null;
              }),
            ),
          if (jefesVentas.isNotEmpty)
            _dropdownUsuarios(
              label: 'Jefe ventas',
              value: filtroJefeVentasId,
              usuarios: jefesVentas,
              onChanged: (v) => setState(() {
                filtroJefeVentasId = v;
                filtroJefeEquipoId = null;
                filtroUsuarioAuthId = null;
              }),
            ),
          if (jefesEquipo.isNotEmpty)
            _dropdownUsuarios(
              label: 'Jefe equipo',
              value: filtroJefeEquipoId,
              usuarios: jefesEquipo,
              onChanged: (v) => setState(() {
                filtroJefeEquipoId = v;
                filtroUsuarioAuthId = null;
              }),
            ),
          _dropdownAuthUsuarios(
            label: 'Usuario asignado',
            value: filtroUsuarioAuthId,
            usuarios: usuariosAsignables,
            onChanged: (v) => setState(() => filtroUsuarioAuthId = v),
          ),
          _dropdownSimple(label: 'Estado', value: filtroEstado, items: ['Todos', ...estados], onChanged: (v) => setState(() => filtroEstado = v!)),
          _dropdownSimple(label: 'Prioridad', value: filtroPrioridad, items: ['Todas', ...prioridades], onChanged: (v) => setState(() => filtroPrioridad = v!)),
          _dropdownSimple(label: 'Tipo', value: filtroTipo, items: ['Todos', ...tipos], onChanged: (v) => setState(() => filtroTipo = v!)),
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

  Widget _formCrearGestion() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text('Nueva gestión', style: TextStyle(color: Color(0xFF0F172A), fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Asigna una tarea a una persona de tu estructura y se le notificará al instante.', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          const SizedBox(height: 18),
          _dropdownAuthUsuarios(
            label: 'Asignar a',
            value: destinoAuthId,
            usuarios: usuariosAsignables,
            onChanged: (v) => setState(() => destinoAuthId = v),
          ),
          _dropdownSimple(label: 'Tipo de gestión', value: tipoGestion, items: tipos, onChanged: (v) => setState(() => tipoGestion = v!)),
          _dropdownSimple(label: 'Prioridad', value: prioridadGestion, items: prioridades, onChanged: (v) => setState(() => prioridadGestion = v!)),
          _dateButton(label: 'Fecha límite', value: fechaLimite, onTap: _pickFechaLimite),
          TextField(controller: tituloCtrl, decoration: _inputDecoration('Título')),
          const SizedBox(height: 12),
          TextField(controller: descripcionCtrl, maxLines: 5, decoration: _inputDecoration('Descripción')),
          const SizedBox(height: 12),
          _archivoAdjuntoBox(),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _crearGestion,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Asignar gestión'),
            style: _primaryButtonStyle(),
          ),
        ],
      ),
    );
  }


  Widget _archivoAdjuntoBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Archivo adjunto',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          if (archivoGestion == null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _seleccionarArchivoGestion,
                icon: const Icon(Icons.attach_file_rounded),
                label: const Text('Adjuntar PDF, foto, Excel u otro archivo'),
              ),
            )
          else
            Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.insert_drive_file_rounded,
                    color: Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        archivoGestion!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${(archivoGestion!.size / 1024).toStringAsFixed(1)} KB',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _quitarArchivoGestion,
                  icon: const Icon(Icons.close_rounded, color: Color(0xFFDC2626)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _listadoGestiones() {
    final lista = gestionesFiltradas.take(180).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: lista.isEmpty
            ? const Center(child: Text('No hay gestiones para estos filtros.', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800)))
            : Column(
                children: [
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    color: const Color(0xFFF1F5F9),
                    child: Row(
                      children: [
                        Text('Mostrando ${lista.length} de ${gestionesFiltradas.length}', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900)),
                        const Spacer(),
                        const Icon(Icons.notifications_active_rounded, color: Color(0xFF0284C7)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (context, index) {
                        final g = lista[index];
                        return _gestionCard(g);
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _gestionCard(Map<String, dynamic> g) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF0284C7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g['titulo']?.toString() ?? 'Sin título', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Asignado a: ${g['destino_nombre']} · Por: ${g['creador_nombre']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(g['tipo']?.toString() ?? 'Otro', const Color(0xFF7C3AED)),
                    _pill(g['prioridad']?.toString() ?? 'Media', _prioridadColor(g['prioridad'])),
                    _pill(g['estado']?.toString() ?? 'Pendiente', _estadoColor(g['estado'])),
                    if (_formatDate(g['fecha_limite']).isNotEmpty) _pill('Límite ${_formatDate(g['fecha_limite'])}', const Color(0xFF0891B2)),
                    if (_tieneArchivo(g))
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _abrirArchivo(g['archivo_url']?.toString()),
                        child: _pill(g['archivo_nombre']?.toString() ?? 'Archivo adjunto', const Color(0xFF0F766E)),
                      ),
                  ],
                ),
                if ((g['descripcion']?.toString().trim().isNotEmpty ?? false)) ...[
                  const SizedBox(height: 8),
                  Text(g['descripcion'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'gestionar') _actualizarGestion(g);
              if (value == 'archivo') _abrirArchivo(g['archivo_url']?.toString());
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'gestionar', child: Text('Gestionar / reasignar')),
              if (_tieneArchivo(g)) const PopupMenuItem(value: 'archivo', child: Text('Abrir archivo')),
            ],
          ),
        ],
      ),
    );
  }

  Color _prioridadColor(dynamic p) {
    final v = p?.toString() ?? '';
    if (v == 'Alta') return const Color(0xFFDC2626);
    if (v == 'Baja') return const Color(0xFF16A34A);
    return const Color(0xFFF97316);
  }

  Color _estadoColor(dynamic e) {
    final v = e?.toString() ?? '';
    if (v == 'Completada') return const Color(0xFF16A34A);
    if (v == 'Cancelada') return const Color(0xFFDC2626);
    if (v == 'En gestión') return const Color(0xFFF97316);
    return const Color(0xFF0284C7);
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
              Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 23, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
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

  Widget _dropdownAuthUsuarios({required String label, required String? value, required List<Map<String, dynamic>> usuarios, required void Function(String?) onChanged}) {
    final values = usuarios.map((u) => u['auth_id']?.toString()).whereType<String>().toSet();
    final safeValue = value != null && values.contains(value) ? value : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: DropdownButtonFormField<String>(
        value: safeValue,
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

class _FondoGestiones extends StatelessWidget {
  const _FondoGestiones();

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
