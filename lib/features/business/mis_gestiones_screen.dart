import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MisGestionesScreen extends StatefulWidget {
  const MisGestionesScreen({super.key});

  @override
  State<MisGestionesScreen> createState() => _MisGestionesScreenState();
}

class _MisGestionesScreenState extends State<MisGestionesScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool guardando = false;

  String? myAuthId;
  String myName = 'Usuario';

  List<Map<String, dynamic>> gestiones = [];
  List<Map<String, dynamic>> usuarios = [];

  String filtroEstado = 'Todas';
  String filtroPrioridad = 'Todas';
  String filtroTipo = 'Todos';
  String busqueda = '';

  final estados = const [
    'Todas',
    'Pendiente',
    'En gestión',
    'Completada',
    'Realizada',
    'Cancelada',
  ];

  final prioridades = const [
    'Todas',
    'Alta',
    'Media',
    'Baja',
  ];

  final tipos = const [
    'Todos',
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

  @override
  void initState() {
    super.initState();
    cargarGestiones();
  }

  Future<void> cargarGestiones() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      myAuthId = user.id;

      final perfil = await supabase
          .from('usuarios')
          .select('auth_id, nombre, apellidos, email')
          .eq('auth_id', user.id)
          .maybeSingle();

      if (perfil != null) {
        myName = _nombreCompleto(perfil);
      }

      final usuariosData = await supabase
          .from('usuarios')
          .select('auth_id, nombre, apellidos, email');

      usuarios = List<Map<String, dynamic>>.from(usuariosData);

      final data = await supabase
          .from('gestiones_asignadas')
          .select()
          .eq('asignado_a_auth_id', user.id)
          .order('created_at', ascending: false);

      final lista = List<Map<String, dynamic>>.from(data).map((g) {
        final creador = _usuarioPorAuth(g['asignado_por_auth_id']?.toString());
        return {
          ...g,
          'creador_nombre': creador == null ? 'Responsable' : _nombreCompleto(creador),
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        gestiones = lista;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _snack('Error cargando tus gestiones: $e');
    }
  }

  Map<String, dynamic>? _usuarioPorAuth(String? authId) {
    if (authId == null || authId.isEmpty || authId == 'null') return null;
    for (final u in usuarios) {
      if (u['auth_id']?.toString() == authId) return u;
    }
    return null;
  }

  String _nombreCompleto(Map<String, dynamic> u) {
    final nombre = u['nombre']?.toString() ?? '';
    final apellidos = u['apellidos']?.toString() ?? '';
    final completo = '$nombre $apellidos'.trim();
    return completo.isEmpty ? (u['email']?.toString() ?? 'Usuario') : completo;
  }

  List<Map<String, dynamic>> get gestionesFiltradas {
    var lista = [...gestiones];

    if (filtroEstado != 'Todas') {
      lista = lista.where((g) {
        final estado = g['estado']?.toString() ?? 'Pendiente';
        if (filtroEstado == 'Realizada') {
          return estado == 'Realizada' || estado == 'Completada';
        }
        return estado == filtroEstado;
      }).toList();
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
        final text = '${g['titulo']} ${g['descripcion']} ${g['tipo']} ${g['prioridad']} ${g['estado']} ${g['comentario_realizacion']} ${g['creador_nombre']}'
            .toLowerCase();
        return text.contains(q);
      }).toList();
    }

    return lista;
  }

  int get pendientes => gestiones.where((g) {
        final e = g['estado']?.toString() ?? 'Pendiente';
        return e == 'Pendiente' || e == 'En gestión';
      }).length;

  int get completadas => gestiones.where((g) {
        final e = g['estado']?.toString() ?? '';
        return e == 'Completada' || e == 'Realizada';
      }).length;

  int get vencidas {
    final hoy = DateTime.now();
    final today = DateTime(hoy.year, hoy.month, hoy.day);

    return gestiones.where((g) {
      final e = g['estado']?.toString() ?? 'Pendiente';
      if (e == 'Completada' || e == 'Realizada' || e == 'Cancelada') return false;
      final f = DateTime.tryParse(g['fecha_limite']?.toString() ?? '');
      if (f == null) return false;
      final limpia = DateTime(f.year, f.month, f.day);
      return limpia.isBefore(today);
    }).length;
  }

  Future<void> _marcarEnGestion(Map<String, dynamic> g) async {
    final id = g['id']?.toString();
    if (id == null || id.isEmpty) return;

    try {
      setState(() => guardando = true);

      final update = <String, dynamic>{
        'estado': 'En gestión',
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (g['fecha_lectura'] == null || g['fecha_lectura'].toString().isEmpty) {
        update['fecha_lectura'] = DateTime.now().toIso8601String();
      }

      await supabase.from('gestiones_asignadas').update(update).eq('id', id);

      await cargarGestiones();
      _snack('Gestión marcada como en gestión');
    } catch (e) {
      _snack('Error actualizando gestión: $e');
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> _reportarRealizada(Map<String, dynamic> g) async {
    String comentario = g['comentario_realizacion']?.toString() ?? '';
    PlatformFile? archivoRespuesta;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return _modalShell(
              title: 'Reportar gestión realizada',
              subtitle: g['titulo']?.toString() ?? 'Sin título',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: comentario,
                    maxLines: 6,
                    decoration: _inputDecoration('Comentario de realización'),
                    onChanged: (v) => comentario = v,
                  ),
                  const SizedBox(height: 14),
                  _archivoRespuestaBox(
                    archivoRespuesta,
                    onPick: () async {
                      final picked = await _pickArchivo();
                      if (picked == null) return;
                      setModalState(() => archivoRespuesta = picked);
                    },
                    onRemove: () => setModalState(() => archivoRespuesta = null),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _guardarRealizada(g, comentario, archivoRespuesta);
                      },
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Enviar reporte y marcar realizada'),
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

  Widget _archivoRespuestaBox(
    PlatformFile? archivo, {
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
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
            'Archivo de respuesta',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Puedes adjuntar PDF, foto, Word, Excel, ZIP o cualquier documento.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          if (archivo == null)
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.attach_file_rounded),
              label: const Text('Adjuntar archivo'),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_rounded, color: Color(0xFF0284C7)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          archivo.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _formatBytes(archivo.size),
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
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded, color: Color(0xFFDC2626)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<PlatformFile?> _pickArchivo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: kIsWeb,
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) return null;
      return result.files.first;
    } catch (e) {
      _snack('Error seleccionando archivo: $e');
      return null;
    }
  }

  Future<Map<String, String>?> _subirArchivoRespuesta(
    PlatformFile archivo,
    String gestionId,
  ) async {
    try {
      final extension = archivo.extension?.trim().isNotEmpty == true
          ? archivo.extension!.trim()
          : archivo.name.split('.').length > 1
              ? archivo.name.split('.').last
              : 'file';

      final cleanName = archivo.name
          .replaceAll(RegExp(r'[^A-Za-z0-9_\.\-]'), '_')
          .replaceAll('__', '_');

      final path = 'respuestas/$gestionId/${DateTime.now().millisecondsSinceEpoch}_$cleanName';

      if (kIsWeb) {
        final bytes = archivo.bytes;
        if (bytes == null) throw Exception('No se pudo leer el archivo');
        await supabase.storage.from('gestiones-archivos').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                upsert: true,
                contentType: _contentType(extension),
              ),
            );
      } else {
        final filePath = archivo.path;
        if (filePath == null || filePath.isEmpty) throw Exception('No se pudo leer el archivo');
        await supabase.storage.from('gestiones-archivos').upload(
              path,
              File(filePath),
              fileOptions: FileOptions(
                upsert: true,
                contentType: _contentType(extension),
              ),
            );
      }

      final publicUrl = supabase.storage.from('gestiones-archivos').getPublicUrl(path);

      return {
        'url': publicUrl,
        'nombre': archivo.name,
        'tipo': extension,
      };
    } catch (e) {
      _snack('Error subiendo archivo de respuesta: $e');
      return null;
    }
  }

  String _contentType(String ext) {
    final e = ext.toLowerCase();
    if (e == 'pdf') return 'application/pdf';
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'png') return 'image/png';
    if (e == 'gif') return 'image/gif';
    if (e == 'webp') return 'image/webp';
    if (e == 'xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (e == 'xls') return 'application/vnd.ms-excel';
    if (e == 'docx') return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (e == 'doc') return 'application/msword';
    if (e == 'zip') return 'application/zip';
    if (e == 'txt') return 'text/plain';
    return 'application/octet-stream';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _guardarRealizada(
    Map<String, dynamic> g,
    String comentario,
    PlatformFile? archivoRespuesta,
  ) async {
    final id = g['id']?.toString();
    if (id == null || id.isEmpty) return;

    try {
      setState(() => guardando = true);

      Map<String, String>? archivoSubido;

      if (archivoRespuesta != null) {
        archivoSubido = await _subirArchivoRespuesta(archivoRespuesta, id);
        if (archivoSubido == null) {
          setState(() => guardando = false);
          return;
        }
      }

      final now = DateTime.now().toIso8601String();

      final update = <String, dynamic>{
        'estado': 'Completada',
        'comentario_realizacion': comentario.trim(),
        'fecha_realizada': now,
        'updated_at': now,
        'reportada_por_auth_id': myAuthId,
      };

      if (archivoSubido != null) {
        update['archivo_respuesta_url'] = archivoSubido['url'];
        update['archivo_respuesta_nombre'] = archivoSubido['nombre'];
        update['archivo_respuesta_tipo'] = archivoSubido['tipo'];
      }

      await supabase.from('gestiones_asignadas').update(update).eq('id', id);

      await supabase.from('notificaciones').update({'leida': true}).eq('referencia_id', id);

      final responsableAuth = g['asignado_por_auth_id']?.toString();
      if (responsableAuth != null && responsableAuth.isNotEmpty && responsableAuth != 'null') {
        await supabase.from('notificaciones').insert({
          'auth_id': responsableAuth,
          'titulo': 'Gestión completada',
          'mensaje': '$myName ha completado la gestión: ${g['titulo'] ?? 'Sin título'}',
          'tipo': 'gestion_realizada',
          'leida': false,
          'referencia_id': id,
          'pantalla_destino': 'cargar_gestiones',
          'archivo_url': archivoSubido?['url'],
          'archivo_nombre': archivoSubido?['nombre'],
        });
      }

      await cargarGestiones();
      _snack('Gestión reportada y responsable notificado');
    } catch (e) {
      _snack('Error reportando gestión: $e');
    } finally {
      if (mounted) setState(() => guardando = false);
    }
  }

  Future<void> _abrirArchivo(String? url) async {
    if (url == null || url.trim().isEmpty) {
      _snack('Esta gestión no tiene archivo adjunto');
      return;
    }

    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      _snack('Archivo no válido');
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _snack('No se ha podido abrir el archivo');
  }

  void _verDetalle(Map<String, dynamic> g) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _modalShell(
          title: 'Detalle de gestión',
          subtitle: g['titulo']?.toString() ?? 'Sin título',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailBox('Asignada por', g['creador_nombre']?.toString() ?? 'Responsable'),
              _detailBox('Tipo', g['tipo']?.toString() ?? 'Otro'),
              _detailBox('Prioridad', g['prioridad']?.toString() ?? 'Media'),
              _detailBox('Estado', g['estado']?.toString() ?? 'Pendiente'),
              _detailBox('Fecha límite', _formatDate(g['fecha_limite']).isEmpty ? '-' : _formatDate(g['fecha_limite'])),
              _detailBox('Descripción', g['descripcion']?.toString() ?? '-'),
              if ((g['archivo_url']?.toString().isNotEmpty ?? false))
                _detailBox('Archivo recibido', g['archivo_nombre']?.toString() ?? 'Archivo adjunto'),
              if ((g['comentario_realizacion']?.toString().isNotEmpty ?? false))
                _detailBox('Comentario realizado', g['comentario_realizacion'].toString()),
              if ((g['archivo_respuesta_url']?.toString().isNotEmpty ?? false))
                _detailBox('Archivo enviado', g['archivo_respuesta_nombre']?.toString() ?? 'Archivo respuesta'),
              const SizedBox(height: 18),
              if ((g['archivo_url']?.toString().isNotEmpty ?? false)) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _abrirArchivo(g['archivo_url']?.toString()),
                    icon: const Icon(Icons.attach_file_rounded),
                    label: const Text('Abrir archivo recibido'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if ((g['archivo_respuesta_url']?.toString().isNotEmpty ?? false)) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _abrirArchivo(g['archivo_respuesta_url']?.toString()),
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Abrir archivo enviado'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if ((g['estado']?.toString() ?? '') != 'Completada')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _marcarEnGestion(g);
                        },
                        icon: const Icon(Icons.pending_actions_rounded),
                        label: const Text('En gestión'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _reportarRealizada(g);
                        },
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Realizada'),
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

  String _formatDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return '';
    final d = DateTime.tryParse(value.toString());
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Color _prioridadColor(dynamic p) {
    final v = p?.toString() ?? '';
    if (v == 'Alta') return const Color(0xFFDC2626);
    if (v == 'Baja') return const Color(0xFF16A34A);
    return const Color(0xFFF97316);
  }

  Color _estadoColor(dynamic e) {
    final v = e?.toString() ?? '';
    if (v == 'Completada' || v == 'Realizada') return const Color(0xFF16A34A);
    if (v == 'Cancelada') return const Color(0xFFDC2626);
    if (v == 'En gestión') return const Color(0xFFF97316);
    return const Color(0xFF0284C7);
  }

  bool _estaCompletada(Map<String, dynamic> g) {
    final estado = g['estado']?.toString() ?? '';
    return estado == 'Completada' || estado == 'Realizada';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: Stack(
        children: [
          const _FondoMisGestiones(),
          SafeArea(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
                : Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                    child: Column(
                      children: [
                        _header(),
                        const SizedBox(height: 14),
                        _resumen(),
                        const SizedBox(height: 14),
                        _filtros(),
                        const SizedBox(height: 14),
                        Expanded(child: _listado()),
                      ],
                    ),
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
        final narrow = constraints.maxWidth < 560;
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

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mis gestiones asignadas',
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
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [volver, const SizedBox(width: 12), Expanded(child: title)]),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: _refreshButton()),
            ],
          );
        }

        return Row(
          children: [
            volver,
            const SizedBox(width: 14),
            Expanded(child: title),
            _refreshButton(),
          ],
        );
      },
    );
  }

  Widget _refreshButton() {
    return IconButton(
      onPressed: cargarGestiones,
      icon: const Icon(Icons.refresh_rounded),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0284C7),
        fixedSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Widget _resumen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final cards = [
          _summaryCard('Pendientes', pendientes.toString(), Icons.pending_actions_rounded, const Color(0xFFF97316)),
          _summaryCard('Realizadas', completadas.toString(), Icons.check_circle_rounded, const Color(0xFF16A34A)),
          _summaryCard('Vencidas', vencidas.toString(), Icons.warning_rounded, const Color(0xFFDC2626)),
        ];

        if (narrow) {
          return Column(
            children: [
              cards[0],
              const SizedBox(height: 10),
              cards[1],
              const SizedBox(height: 10),
              cards[2],
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
            const SizedBox(width: 10),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800)),
                Text(value, style: TextStyle(color: color, fontSize: 25, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 720;
          final children = [
            SizedBox(
              width: narrow ? double.infinity : 260,
              child: TextField(
                onChanged: (v) => setState(() => busqueda = v),
                decoration: _inputDecoration('Buscar').copyWith(prefixIcon: const Icon(Icons.search_rounded)),
              ),
            ),
            SizedBox(
              width: narrow ? double.infinity : 180,
              child: _dropdownSimple('Estado', filtroEstado, estados, (v) => setState(() => filtroEstado = v!)),
            ),
            SizedBox(
              width: narrow ? double.infinity : 180,
              child: _dropdownSimple('Prioridad', filtroPrioridad, prioridades, (v) => setState(() => filtroPrioridad = v!)),
            ),
            SizedBox(
              width: narrow ? double.infinity : 220,
              child: _dropdownSimple('Tipo', filtroTipo, tipos, (v) => setState(() => filtroTipo = v!)),
            ),
          ];

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: children,
          );
        },
      ),
    );
  }

  Widget _listado() {
    final lista = gestionesFiltradas;

    if (lista.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.94),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white),
        ),
        child: const Center(
          child: Text(
            'No tienes gestiones con estos filtros.',
            style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: ListView.builder(
          itemCount: lista.length,
          itemBuilder: (context, index) => _gestionCard(lista[index]),
        ),
      ),
    );
  }

  Widget _gestionCard(Map<String, dynamic> g) {
    final tieneArchivo = g['archivo_url']?.toString().trim().isNotEmpty ?? false;
    final tieneRespuesta = g['archivo_respuesta_url']?.toString().trim().isNotEmpty ?? false;
    final estado = g['estado']?.toString() ?? 'Pendiente';
    final completada = _estaCompletada(g);

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
            decoration: BoxDecoration(
              color: _estadoColor(estado).withOpacity(0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(Icons.assignment_rounded, color: _estadoColor(estado)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g['titulo']?.toString() ?? 'Sin título', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Asignada por: ${g['creador_nombre'] ?? 'Responsable'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(g['descripcion']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill(g['tipo']?.toString() ?? 'Otro', const Color(0xFF7C3AED)),
                    _pill(g['prioridad']?.toString() ?? 'Media', _prioridadColor(g['prioridad'])),
                    _pill(estado, _estadoColor(estado)),
                    if (_formatDate(g['fecha_limite']).isNotEmpty) _pill('Límite ${_formatDate(g['fecha_limite'])}', const Color(0xFF0891B2)),
                    if (tieneArchivo) _pill('Archivo recibido', const Color(0xFF0EA5E9)),
                    if (tieneRespuesta) _pill('Archivo enviado', const Color(0xFF16A34A)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _verDetalle(g),
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('Ver detalle'),
                    ),
                    if (tieneArchivo)
                      OutlinedButton.icon(
                        onPressed: () => _abrirArchivo(g['archivo_url']?.toString()),
                        icon: const Icon(Icons.attach_file_rounded),
                        label: const Text('Abrir archivo'),
                      ),
                    if (!completada)
                      ElevatedButton.icon(
                        onPressed: () => _reportarRealizada(g),
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('Reportar'),
                        style: _primaryButtonStyle(compact: true),
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

  Widget _detailBox(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(value.isEmpty ? '-' : value, style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800)),
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

  Widget _dropdownSimple(String label, String value, List<String> items, void Function(String?) onChanged) {
    final safeItems = items.toSet().toList();
    final safeValue = safeItems.contains(value) ? value : safeItems.first;
    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      decoration: _inputDecoration(label),
      items: safeItems.map((e) => DropdownMenuItem<String>(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
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

  ButtonStyle _primaryButtonStyle({bool compact = false}) {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF0284C7),
      foregroundColor: Colors.white,
      padding: EdgeInsets.symmetric(vertical: compact ? 10 : 15, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: const Color(0xFF0F172A)));
  }
}

class _FondoMisGestiones extends StatelessWidget {
  const _FondoMisGestiones();

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
