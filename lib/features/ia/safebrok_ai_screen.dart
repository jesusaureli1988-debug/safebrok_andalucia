import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'ia_agent_panel.dart';
import 'ia_workspaces.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SafebrokAiScreen extends StatefulWidget {
  const SafebrokAiScreen({super.key});

  @override
  State<SafebrokAiScreen> createState() => _SafebrokAiScreenState();
}

class _SafebrokAiScreenState extends State<SafebrokAiScreen> {
  static const _bg = Color(0xFFF4F6FB);
  static const _panel = Color(0xFF0D1924);
  static const _cyan = Color(0xFF14B8A6);

  final _supabase = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<Map<String, dynamic>> _conversaciones = [];
  final List<Map<String, dynamic>> _mensajes = [];

  final List<PlatformFile> _adjuntos = [];
  String? _conversacionActualId;
  String _espacio = 'general';
  String _historyQuery = '';
  bool _showBots = false;
  bool _enviando = false;
  bool _cargandoConversaciones = true;
  bool _cargandoMensajes = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await _cargarConversaciones();
    if (!mounted) return;

    _nuevaConversacion();
  }

  Future<void> _cargarConversaciones() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _cargandoConversaciones = false);
      return;
    }

    try {
      final data = await _supabase
          .from('ia_conversaciones')
          .select('id, titulo, created_at, updated_at')
          .eq('auth_id', user.id)
          .order('updated_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _conversaciones
          ..clear()
          ..addAll(
            (data as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          );
        _cargandoConversaciones = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoConversaciones = false);
      _error('No se pudieron cargar las conversaciones: $e');
    }
  }

  void _nuevaConversacion({String espacio = 'general'}) {
    if (!mounted || _enviando || _cargandoMensajes) return;

    setState(() {
      _espacio = espacio;
      _showBots = false;
      _conversacionActualId = null;
      _mensajes
        ..clear()
        ..add({
          'role': 'assistant',
          'text':
              'Trabajaremos en ${iaWorkspace(_espacio).title.toLowerCase()}, con los datos y permisos de tu perfil. ¿Qué necesitas hacer?',
          'local': true,
        });
    });

    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    _scrollDown();
  }

  Future<void> _abrirConversacion(String id, {bool cerrarDrawer = true}) async {
    if (id.isEmpty || _cargandoMensajes || _enviando) return;

    if (cerrarDrawer && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
      Navigator.of(context).pop();
    }

    setState(() {
      _conversacionActualId = id;
      _showBots = false;
      _cargandoMensajes = true;
      _mensajes.clear();
    });

    try {
      final data = await _supabase
          .from('ia_mensajes')
          .select('id, role, contenido, created_at, metadata')
          .eq('conversacion_id', id)
          .order('created_at', ascending: true);

      if (!mounted || _conversacionActualId != id) return;

      setState(() {
        final espacios = data.where(
          (m) =>
              m['role'] == 'user' &&
              m['metadata'] is Map &&
              (m['metadata'] as Map)['espacio_ia'] != null,
        );
        _espacio = espacios.isEmpty
            ? 'general'
            : iaWorkspace(
                (espacios.first['metadata'] as Map)['espacio_ia'].toString(),
              ).id;
        _mensajes
          ..clear()
          ..addAll(
            (data as List).map(
              (e) => {
                'id': e['id'],
                'role': e['role'],
                'text': e['contenido'],
                'created_at': e['created_at'],
                'pasos': (e['metadata'] as Map?)?['pasos'],
                'archivos':
                    (e['metadata'] as Map?)?['archivos'] ??
                    (e['metadata'] as Map?)?['adjuntos'],
                'pdf_url':
                    ((e['metadata'] as Map?)?['documento'] as Map?)?['url'],
                'pdf_nombre':
                    ((e['metadata'] as Map?)?['documento'] as Map?)?['nombre'],
              },
            ),
          );
        _cargandoMensajes = false;
      });
      _scrollDown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoMensajes = false);
      _error('No se pudo abrir la conversación: $e');
    }
  }

  Future<String> _crearConversacion(String pregunta) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('No hay una sesión iniciada.');

    final limpio = pregunta.replaceAll(RegExp(r'\s+'), ' ').trim();
    final titulo = limpio.length <= 42
        ? limpio
        : '${limpio.substring(0, 42).trim()}…';

    final data = await _supabase
        .from('ia_conversaciones')
        .insert({'auth_id': user.id, 'titulo': titulo})
        .select('id, titulo, created_at, updated_at')
        .single();

    final conversacion = Map<String, dynamic>.from(data);
    if (mounted) {
      setState(() {
        _conversacionActualId = conversacion['id'].toString();
        _conversaciones.insert(0, conversacion);
      });
    }

    return conversacion['id'].toString();
  }

  Future<void> _seleccionarAdjuntos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'docx',
        'xlsx',
        'pptx',
        'csv',
        'txt',
        'md',
        'json',
        'html',
        'png',
        'jpg',
        'jpeg',
        'webp',
        'xml',
        'dart',
        'js',
        'ts',
        'py',
        'sql',
        'css',
        'yaml',
        'yml',
      ],
    );
    if (result == null || !mounted) return;
    final files = [..._adjuntos, ...result.files];
    if (files.length > 3 ||
        files.any((f) => f.size > 8000000 || f.bytes == null) ||
        files.fold<int>(0, (s, f) => s + f.size) > 16000000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Máximo 3 archivos, 8 MB por archivo y 16 MB en total.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _adjuntos.clear();
      _adjuntos.addAll(files);
    });
  }

  Future<List<Map<String, dynamic>>> _subirAdjuntos(
    List<PlatformFile> files,
    String userId,
  ) async {
    final uploaded = <Map<String, dynamic>>[];
    const mimes = {
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'webp': 'image/webp',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'md': 'text/markdown',
      'json': 'application/json',
      'html': 'text/html',
    };
    try {
      for (final file in files) {
        final rng = Random.secure();
        final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
        bytes[6] = (bytes[6] & 15) | 64;
        bytes[8] = (bytes[8] & 63) | 128;
        final hex = bytes
            .map((v) => v.toRadixString(16).padLeft(2, '0'))
            .join();
        final id =
            '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
        final name = file.name.replaceAll(RegExp(r'[/\\]'), '_');
        final path = '$userId/ia_adjuntos/$id/$name';
        final type = name.split('.').last.toLowerCase();
        final mime = mimes[type] ?? 'text/plain';
        await _supabase.storage
            .from('safecloud')
            .uploadBinary(
              path,
              file.bytes!,
              fileOptions: FileOptions(contentType: mime),
            );
        try {
          await _supabase.from('safecloud_items').insert({
            'id': id,
            'owner_auth_id': userId,
            'parent_id': null,
            'nombre': name,
            'tipo': 'archivo',
            'storage_path': path,
            'mime_type': mime,
            'size_bytes': file.size,
          });
        } catch (_) {
          await _supabase.storage.from('safecloud').remove([path]);
          rethrow;
        }
        uploaded.add({
          'id': id,
          'nombre': name,
          'tipo': type,
          'storage_path': path,
          'size_bytes': file.size,
        });
      }
      return uploaded;
    } catch (_) {
      for (final f in uploaded) {
        await _supabase.from('safecloud_items').delete().eq('id', f['id']);
        await _supabase.storage.from('safecloud').remove([
          f['storage_path'] as String,
        ]);
      }
      rethrow;
    }
  }

  Future<void> enviarPregunta() async {
    final pregunta = _controller.text.trim().isEmpty && _adjuntos.isNotEmpty
        ? 'Analiza los archivos adjuntos.'
        : _controller.text.trim();
    if (pregunta.isEmpty || _enviando || _cargandoMensajes) return;

    final adjuntos = List<PlatformFile>.from(_adjuntos);
    FocusScope.of(context).unfocus();

    final historial = _mensajes
        .where((m) => m['local'] != true)
        .map(
          (m) => {
            'role': m['role']?.toString() ?? '',
            'text': m['text']?.toString() ?? '',
          },
        )
        .toList();

    setState(() {
      _mensajes.add({'role': 'user', 'text': pregunta, 'pending': true});
      _enviando = true;
      _controller.clear();
    });
    _scrollDown();

    try {
      var conversacionId = _conversacionActualId;

      if (conversacionId == null) {
        conversacionId = await _crearConversacion(pregunta);
        if (!mounted) return;
        setState(() => _mensajes.removeWhere((m) => m['local'] == true));
      }

      final userId = _supabase.auth.currentUser!.id;

      final archivosAdjuntos = await _subirAdjuntos(adjuntos, userId);
      if (mounted)
        setState(() {
          _adjuntos.clear();
          _mensajes.lastWhere((m) => m['role'] == 'user')['archivos'] =
              archivosAdjuntos;
        });
      await _supabase.from('ia_mensajes').insert({
        'conversacion_id': conversacionId,
        'auth_id': userId,
        'role': 'user',
        'contenido': pregunta,
        'metadata': {'espacio_ia': _espacio, 'adjuntos': archivosAdjuntos},
      });

      final session = _supabase.auth.currentSession;
      final inicio = historial.length > 12 ? historial.length - 12 : 0;

      final response = await http
          .post(
            Uri.parse(
              'https://ytmxjavihwylrswphczc.supabase.co/functions/v1/safebrok-ia',
            ),
            headers: {
              'Content-Type': 'application/json',
              if (session != null)
                'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'pregunta': pregunta,
              'modo_agente': true,
              'espacio_ia': _espacio,
              'historial': historial.skip(inicio).toList(),
              'conversacion_id': conversacionId,
            }),
          )
          .timeout(const Duration(seconds: 120));

      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      final respuesta = response.statusCode == 200
          ? (data['respuesta']?.toString() ?? 'No he podido responder.')
          : 'Ha ocurrido un error al conectar con Safebrok IA. ${data['error'] ?? ''}';

      final visualizacion = data['visualizacion'] is Map
          ? Map<String, dynamic>.from(data['visualizacion'] as Map)
          : null;

      final accion = data['accion'] is Map
          ? Map<String, dynamic>.from(data['accion'] as Map)
          : <String, dynamic>{};

      final documento = data['documento'] is Map
          ? Map<String, dynamic>.from(data['documento'] as Map)
          : <String, dynamic>{};

      final pdfUrl = (documento['url'] ?? accion['url'] ?? data['pdf_url'])
          ?.toString()
          .trim();

      final pdfNombre =
          (documento['nombre'] ??
                  accion['archivo'] ??
                  data['nombre_pdf'] ??
                  'informe_safebrok.pdf')
              .toString()
              .trim();

      final tienePdf = pdfUrl != null && pdfUrl.isNotEmpty;

      final mensajeIa = await _supabase
          .from('ia_mensajes')
          .insert({
            'conversacion_id': conversacionId,
            'auth_id': userId,
            'role': 'assistant',
            'contenido': respuesta,
            'metadata': {
              'pasos': data['pasos'] ?? [],
              'documento': documento,
              'archivos': data['archivos'] ?? [],
            },
          })
          .select('id, created_at')
          .single();

      await _supabase
          .from('ia_conversaciones')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', conversacionId);

      if (!mounted) return;
      setState(() {
        final pendiente = _mensajes.lastIndexWhere(
          (m) => m['role'] == 'user' && m['pending'] == true,
        );
        if (pendiente >= 0) _mensajes[pendiente]['pending'] = false;

        _mensajes.add({
          'id': mensajeIa['id'],
          'role': 'assistant',
          'text': respuesta,
          'pasos': data['pasos'],
          'archivos': data['archivos'],
          'created_at': mensajeIa['created_at'],
          if (tienePdf) 'pdf_url': pdfUrl,
          if (tienePdf) 'pdf_nombre': pdfNombre,
          if (visualizacion != null) 'visualizacion': visualizacion,
        });

        final index = _conversaciones.indexWhere(
          (c) => c['id'].toString() == conversacionId,
        );
        if (index >= 0) {
          final actualizada = Map<String, dynamic>.from(
            _conversaciones.removeAt(index),
          );
          actualizada['updated_at'] = DateTime.now().toIso8601String();
          _conversaciones.insert(0, actualizada);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensajes.add({
          'role': 'assistant',
          'text': 'No he podido completar la consulta. Error: $e',
        });
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
      _scrollDown();
    }
  }

  Future<void> _renombrar(Map<String, dynamic> conversacion) async {
    final controller = TextEditingController(
      text: conversacion['titulo']?.toString() ?? '',
    );

    final nuevoTitulo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Renombrar conversación',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: Color(0xFF111827)),
          decoration: InputDecoration(
            hintText: 'Título',
            hintStyle: const TextStyle(color: Color(0xFF738198)),
            filled: true,
            fillColor: const Color(0xFFF7FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (nuevoTitulo == null || nuevoTitulo.isEmpty) return;

    try {
      await _supabase
          .from('ia_conversaciones')
          .update({'titulo': nuevoTitulo})
          .eq('id', conversacion['id']);
      if (mounted) setState(() => conversacion['titulo'] = nuevoTitulo);
    } catch (e) {
      _error('No se pudo renombrar: $e');
    }
  }

  Future<void> _eliminar(Map<String, dynamic> conversacion) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Eliminar conversación',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Se eliminarán todos sus mensajes.',
          style: TextStyle(color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    final id = conversacion['id'].toString();

    try {
      await _supabase.from('ia_conversaciones').delete().eq('id', id);
      if (!mounted) return;

      setState(() {
        _conversaciones.removeWhere((c) => c['id'].toString() == id);
      });

      if (_conversacionActualId == id) {
        if (_conversaciones.isNotEmpty) {
          await _abrirConversacion(
            _conversaciones.first['id'].toString(),
            cerrarDrawer: false,
          );
        } else {
          _nuevaConversacion();
        }
      }
    } catch (e) {
      _error('No se pudo eliminar: $e');
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!_scrollController.hasClients) return;
      if (_isWelcome) {
        _scrollController.jumpTo(0);
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  void enviarSugerencia(String texto) {
    _controller.text = texto;
    enviarPregunta();
  }

  void _error(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: const Color(0xFFB91C1C),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final escritorio = constraints.maxWidth >= 780;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _bg,
          drawer: escritorio
              ? null
              : Drawer(
                  backgroundColor: _panel,
                  child: SafeArea(child: _sidebar()),
                ),
          appBar: AppBar(
            backgroundColor: Colors.white.withOpacity(.97),
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            iconTheme: const IconThemeData(color: Color(0xFF0F2747)),
            leading: escritorio
                ? null
                : IconButton(
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.menu_rounded),
                  ),
            title: Row(
              children: [
                const Icon(Icons.auto_awesome, color: _cyan, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    iaWorkspace(_espacio).title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F2747),
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              if (escritorio)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Acceso según tu perfil',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              IconButton(
                tooltip: 'Nueva conversación',
                onPressed: _enviando ? null : _nuevaConversacion,
                icon: const Icon(Icons.edit_square, color: Color(0xFF0F2747)),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Row(
            children: [
              if (escritorio) SizedBox(width: 272, child: _sidebar()),
              if (escritorio)
                VerticalDivider(width: 1, color: Color(0xFFDCE6F2)),
              Expanded(child: _showBots ? _botsWorkspace() : _chat()),
            ],
          ),
        );
      },
    );
  }

  void _selectWorkspace(String id) {
    if (_enviando || _cargandoMensajes) return;
    if (id == 'bots') {
      setState(() {
        _espacio = id;
        _showBots = true;
      });
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false)
        Navigator.pop(context);
    } else {
      _nuevaConversacion(espacio: id);
    }
  }

  Widget _sidebar() {
    final history = _conversaciones
        .where(
          (c) => (c['titulo'] ?? '').toString().toLowerCase().contains(
            _historyQuery.toLowerCase(),
          ),
        )
        .take(40)
        .toList();
    return Material(
      color: _panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 18, 18),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Image.asset(
                    'assets/images/safebrok_mark.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SafeBrok IA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'Tu espacio de trabajo',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: _enviando ? null : _nuevaConversacion,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFCCFBF1),
                  foregroundColor: const Color(0xFF115E59),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.centerLeft,
                ),
                icon: const Icon(Icons.add, size: 19),
                label: const Text(
                  'Nueva conversación',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 9),
                  child: Text(
                    'ESPACIOS DE TRABAJO',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.3,
                      color: Color(0xFF8090A5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final workspace in iaWorkspaces)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: ListTile(
                      key: ValueKey('ia-space-${workspace.id}'),
                      dense: true,
                      minVerticalPadding: 1,
                      selected: workspace.id == _espacio,
                      selectedTileColor: const Color(0xFF183F40),
                      selectedColor: const Color(0xFF99F6E4),
                      iconColor: const Color(0xFF94A3B8),
                      textColor: const Color(0xFFCBD5E1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(workspace.icon, size: 19),
                      title: Text(
                        workspace.title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: _enviando
                          ? null
                          : () => _selectWorkspace(workspace.id),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 22, 12, 10),
                  child: Text(
                    'CONVERSACIONES',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.3,
                      color: Color(0xFF8090A5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TextField(
                    onChanged: (value) => setState(() => _historyQuery = value),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Buscar conversación',
                      hintStyle: const TextStyle(
                        color: Color(0xFF8090A5),
                        fontSize: 12,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 17,
                        color: Color(0xFF8090A5),
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF142332),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_cargandoConversaciones)
                  const LinearProgressIndicator(color: _cyan),
                if (!_cargandoConversaciones && history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Tus conversaciones aparecerán aquí.',
                      style: TextStyle(color: Color(0xFF8090A5), fontSize: 12),
                    ),
                  ),
                for (final c in history)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 12, right: 0),
                    selected:
                        c['id'].toString() == _conversacionActualId &&
                        !_showBots,
                    selectedTileColor: const Color(0xFF1B3041),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: const Icon(
                      Icons.chat_bubble_outline,
                      size: 16,
                      color: Color(0xFF8090A5),
                    ),
                    title: Text(
                      c['titulo']?.toString() ?? 'Conversación',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 12,
                      ),
                    ),
                    onTap: _enviando
                        ? null
                        : () => _abrirConversacion(c['id'].toString()),
                    trailing: PopupMenuButton<String>(
                      enabled: !_enviando,
                      icon: const Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: Color(0xFF8090A5),
                      ),
                      onSelected: (value) {
                        if (value == 'rename') _renombrar(c);
                        if (value == 'delete') _eliminar(c);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Renombrar'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF243544)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 15,
                  backgroundColor: Color(0xFF183F40),
                  child: Icon(
                    Icons.person_outline,
                    size: 17,
                    color: Color(0xFF99F6E4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _supabase.auth.currentUser?.email ?? 'Mi cuenta',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
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

  Widget _botsWorkspace() => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(22),
        color: Colors.white,
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tu trabajo, en automático',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F2747),
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Crea, pausa y revisa tus bots desde un mismo lugar.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _nuevaConversacion(espacio: 'bots'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Crear con IA'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
              ),
            ),
          ],
        ),
      ),
      const Expanded(child: IaBotsScreen(embedded: true)),
    ],
  );

  bool get _isWelcome =>
      _mensajes.isEmpty ||
      (_mensajes.length == 1 && _mensajes.first['local'] == true);

  Widget _chat() {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFFF7F9FC))),
        Column(
          children: [
            Expanded(
              child: _cargandoMensajes
                  ? const Center(child: CircularProgressIndicator(color: _cyan))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                      itemCount: _isWelcome && !_enviando
                          ? 1
                          : _mensajes.length + (_enviando ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_isWelcome && !_enviando) return _welcome();
                        if (_enviando && index == _mensajes.length) {
                          return const _TypingBubble();
                        }
                        final m = _mensajes[index];
                        return _MessageBubble(
                          isUser: m['role'] == 'user',
                          text: m['text']?.toString() ?? '',
                          pasos: m['pasos'] is List
                              ? List<dynamic>.from(m['pasos'])
                              : const [],
                          pdfUrl: m['pdf_url']?.toString(),
                          archivos: List<Map<String, dynamic>>.from(
                            m['archivos'] ?? [],
                          ),
                          pdfNombre: m['pdf_nombre']?.toString(),
                          visualizacion: m['visualizacion'] is Map
                              ? Map<String, dynamic>.from(
                                  m['visualizacion'] as Map,
                                )
                              : null,
                        );
                      },
                    ),
            ),
            IaAgentActions(
              conversationId: _conversacionActualId,
              revision: _mensajes.length + (_enviando ? 1 : 0),
            ),
            _inputBar(),
          ],
        ),
      ],
    );
  }

  Widget _welcome() {
    final workspace = iaWorkspace(_espacio);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4F4F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  workspace.icon,
                  color: const Color(0xFF0F766E),
                  size: 27,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _espacio == 'general' ? '¿Qué hacemos hoy?' : workspace.title,
                style: const TextStyle(
                  fontSize: 34,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF102A43),
                  letterSpacing: -1.1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                workspace.subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Datos de tu ámbito · acciones revisables · resultados verificables',
                style: TextStyle(fontSize: 12, color: Color(0xFF7B8A9B)),
              ),
              const SizedBox(height: 30),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 440;
                  final width = twoColumns
                      ? (constraints.maxWidth - 14) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (var i = 0; i < workspace.prompts.length; i++)
                        SizedBox(
                          width: width,
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            child: InkWell(
                              onTap: () {
                                _controller.text = workspace.prompts[i].$2;
                              },
                              borderRadius: BorderRadius.circular(15),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 126,
                                ),
                                padding: const EdgeInsets.all(19),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '0${i + 1}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                        const Spacer(),
                                        const Icon(
                                          Icons.north_east,
                                          size: 16,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      workspace.prompts[i].$1,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF16324F),
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      workspace.prompts[i].$2,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.97),
          border: const Border(top: BorderSide(color: Color(0xFFDCE6F2))),
          boxShadow: [
            BoxShadow(
              color: Color(0x120F2747),
              blurRadius: 24,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 7, 7, 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFD6E2EE)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D0F2747),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_adjuntos.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      children: _adjuntos
                          .map(
                            (f) => InputChip(
                              label: Text(
                                f.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onDeleted: _enviando
                                  ? null
                                  : () => setState(() => _adjuntos.remove(f)),
                            ),
                          )
                          .toList(),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Adjuntar PDF, documento o imagen',
                        onPressed: _enviando ? null : _seleccionarAdjuntos,
                        icon: const Icon(
                          Icons.attach_file_rounded,
                          color: _cyan,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 5,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 15,
                            height: 1.35,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => enviarPregunta(),
                          decoration: InputDecoration(
                            hintText: _espacio == 'general'
                                ? 'Describe qué quieres consultar o hacer…'
                                : 'Trabajar en ${iaWorkspace(_espacio).title.toLowerCase()}…',
                            hintStyle: TextStyle(color: Color(0xFF738198)),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _enviando ? null : enviarPregunta,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: _enviando
                                ? null
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFF0F2747),
                                      Color(0xFF1D4ED8),
                                      _cyan,
                                    ],
                                  ),
                            color: _enviando ? const Color(0xFFCBD5E1) : null,
                          ),
                          child: _enviando
                              ? const Padding(
                                  padding: EdgeInsets.all(11),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isUser;
  final String text;
  final List<dynamic> pasos;
  final List<Map<String, dynamic>> archivos;
  final String? pdfUrl;
  final String? pdfNombre;
  final Map<String, dynamic>? visualizacion;

  const _MessageBubble({
    required this.isUser,
    required this.text,
    this.pasos = const [],
    this.pdfUrl,
    this.archivos = const [],
    this.pdfNombre,
    this.visualizacion,
  });

  Future<void> _abrirEnlace(BuildContext context, String? href) async {
    final valor = href?.trim() ?? '';
    if (valor.isEmpty) return;

    final uri = Uri.tryParse(valor);
    if (uri == null) {
      _mostrarError(context, 'El enlace del archivo no es válido.');
      return;
    }

    final abierto = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );

    if (!abierto && context.mounted) {
      _mostrarError(
        context,
        'No se pudo abrir el archivo. Comprueba tu conexión e inténtalo de nuevo.',
      );
    }
  }

  void _mostrarError(BuildContext context, String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: const Color(0xFFB91C1C),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF14B8A6);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: Container(
          margin: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 31,
                  height: 31,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [cyan, Colors.blueAccent]),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF07111B),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0F2747), Color(0xFF1D4ED8)],
                          )
                        : null,
                    color: isUser ? null : Colors.white,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(
                      color: isUser
                          ? const Color(0xFF315EBD)
                          : const Color(0xFFDCE6F2),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x100F2747),
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: isUser
                      ? Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MarkdownBody(
                              data: text,
                              selectable: true,
                              onTapLink: (texto, href, titulo) {
                                _abrirEnlace(context, href);
                              },
                              styleSheet: MarkdownStyleSheet(
                                h1: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                                h2: const TextStyle(
                                  color: Color(0xFF0F766E),
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                                h3: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                ),
                                p: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  height: 1.55,
                                  fontWeight: FontWeight.w500,
                                ),
                                listBullet: const TextStyle(
                                  color: Color(0xFF0F766E),
                                  fontSize: 15,
                                ),
                                strong: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w900,
                                ),
                                code: TextStyle(
                                  color: cyan,
                                  backgroundColor: const Color(0xFFE8F8F6),
                                ),
                                tableHead: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w900,
                                ),
                                tableBody: const TextStyle(
                                  color: Color(0xFF334155),
                                ),
                                tableBorder: TableBorder.all(
                                  color: Color(0xFFD8E3EF),
                                ),
                              ),
                            ),
                            if (pasos.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final paso in pasos)
                                    Chip(
                                      avatar: Icon(
                                        paso['estado'] == 'correcto'
                                            ? Icons.check_circle_outline
                                            : Icons.error_outline,
                                        size: 16,
                                      ),
                                      label: Text(
                                        (paso['modulo'] ?? paso['herramienta'])
                                            .toString(),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (visualizacion != null) ...[
                              const SizedBox(height: 16),
                              _DashboardVisual(data: visualizacion!),
                            ],
                            if (archivos.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              IaArtifactList(files: archivos),
                            ],
                            if (archivos.isEmpty &&
                                (pdfUrl ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: () => _abrirEnlace(context, pdfUrl),
                                style: FilledButton.styleFrom(
                                  backgroundColor: cyan,
                                  foregroundColor: const Color(0xFF07111B),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.download_rounded,
                                  size: 20,
                                ),
                                label: Text(
                                  (pdfNombre ?? '').trim().isEmpty
                                      ? 'Descargar archivo'
                                      : 'Descargar ${pdfNombre!.trim()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: text),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Respuesta copiada'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.copy_rounded,
                                  color: Color(0xFF64748B),
                                  size: 17,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardVisual extends StatelessWidget {
  final Map<String, dynamic> data;

  const _DashboardVisual({required this.data});

  @override
  Widget build(BuildContext context) {
    final tarjetasRaw = data['tarjetas'];
    final tarjetas = tarjetasRaw is List
        ? tarjetasRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .take(4)
              .toList()
        : <Map<String, dynamic>>[];

    final grafico = data['grafico'] is Map
        ? Map<String, dynamic>.from(data['grafico'] as Map)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE6F2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F2747),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['titulo']?.toString() ?? 'Resumen visual',
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if ((data['subtitulo']?.toString() ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              data['subtitulo'].toString(),
              style: const TextStyle(color: Color(0xFF64748B), height: 1.35),
            ),
          ],
          if (tarjetas.isNotEmpty) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth;
                final columnas = ancho >= 700
                    ? 4
                    : ancho >= 440
                    ? 2
                    : 1;
                final separacion = 10.0;
                final anchoTarjeta =
                    (ancho - (separacion * (columnas - 1))) / columnas;

                return Wrap(
                  spacing: separacion,
                  runSpacing: separacion,
                  children: tarjetas
                      .map(
                        (tarjeta) => SizedBox(
                          width: anchoTarjeta,
                          child: _KpiCard(data: tarjeta),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
          if (grafico != null) ...[
            const SizedBox(height: 20),
            _AutomaticChart(data: grafico),
          ],
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final tendencia = data['tendencia']?.toString() ?? 'neutral';
    final icono = tendencia == 'positiva'
        ? Icons.trending_up_rounded
        : tendencia == 'negativa'
        ? Icons.trending_down_rounded
        : Icons.horizontal_rule_rounded;

    final color = tendencia == 'positiva'
        ? const Color(0xFF4ADE80)
        : tendencia == 'negativa'
        ? const Color(0xFFF87171)
        : const Color(0xFF67E8F9);

    return Container(
      constraints: const BoxConstraints(minHeight: 122),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE6F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data['etiqueta']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(icono, color: color, size: 19),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data['valor']?.toString() ?? '-',
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            data['detalle']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomaticChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AutomaticChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final etiquetas = (data['etiquetas'] is List)
        ? List<String>.from(
            (data['etiquetas'] as List).map((e) => e.toString()),
          )
        : <String>[];
    final valores = (data['valores'] is List)
        ? List<double>.from(
            (data['valores'] as List).map(
              (e) => double.tryParse(e.toString()) ?? 0,
            ),
          )
        : <double>[];

    if (etiquetas.length < 2 || etiquetas.length != valores.length) {
      return const SizedBox.shrink();
    }

    final tipo = data['tipo']?.toString() ?? 'barras';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          data['titulo']?.toString() ?? 'Gráfico',
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: tipo == 'circular' ? 270 : 250,
          width: double.infinity,
          child: CustomPaint(
            painter: _SafeChartPainter(
              tipo: tipo,
              etiquetas: etiquetas,
              valores: valores,
              unidad: data['unidad']?.toString() ?? '',
            ),
          ),
        ),
      ],
    );
  }
}

class _SafeChartPainter extends CustomPainter {
  final String tipo;
  final List<String> etiquetas;
  final List<double> valores;
  final String unidad;

  _SafeChartPainter({
    required this.tipo,
    required this.etiquetas,
    required this.valores,
    required this.unidad,
  });

  final _cyan = const Color(0xFF14B8A6);
  final _blue = const Color(0xFF3B82F6);
  final _grid = const Color(0xFFDCE6F2);
  final _text = const Color(0xFF64748B);

  @override
  void paint(Canvas canvas, Size size) {
    if (tipo == 'circular') {
      _paintCircular(canvas, size);
    } else {
      _paintCartesian(canvas, size);
    }
  }

  void _paintCartesian(Canvas canvas, Size size) {
    const left = 46.0;
    const right = 12.0;
    const top = 12.0;
    const bottom = 52.0;

    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final maxValue = valores.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    final safeMax = maxValue <= 0 ? 1.0 : maxValue * 1.12;

    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = top + chartHeight - (chartHeight * i / 4);
      canvas.drawLine(Offset(left, y), Offset(left + chartWidth, y), gridPaint);
      _drawText(
        canvas,
        _formatNumber(safeMax * i / 4),
        Offset(0, y - 7),
        10,
        _text,
        maxWidth: 42,
        align: TextAlign.right,
      );
    }

    if (tipo == 'linea') {
      final path = Path();
      final pointPaint = Paint()..color = _cyan;
      final linePaint = Paint()
        ..color = _cyan
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      for (var i = 0; i < valores.length; i++) {
        final x =
            left +
            (valores.length == 1
                ? chartWidth / 2
                : chartWidth * i / (valores.length - 1));
        final y = top + chartHeight - (valores[i] / safeMax * chartHeight);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        canvas.drawCircle(Offset(x, y), 4, pointPaint);
        _drawAxisLabel(
          canvas,
          etiquetas[i],
          x,
          top + chartHeight + 10,
          chartWidth,
        );
      }
      canvas.drawPath(path, linePaint);
    } else {
      final slot = chartWidth / valores.length;
      final barWidth = (slot * .58).clamp(12.0, 44.0);
      final barPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_blue, _cyan],
        ).createShader(Rect.fromLTWH(left, top, chartWidth, chartHeight));

      for (var i = 0; i < valores.length; i++) {
        final height = valores[i] / safeMax * chartHeight;
        final x = left + slot * i + (slot - barWidth) / 2;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top + chartHeight - height, barWidth, height),
          const Radius.circular(6),
        );
        canvas.drawRRect(rect, barPaint);
        _drawAxisLabel(
          canvas,
          etiquetas[i],
          x + barWidth / 2,
          top + chartHeight + 10,
          slot,
        );
      }
    }

    if (unidad.trim().isNotEmpty) {
      _drawText(
        canvas,
        unidad,
        Offset(left, 0),
        9.5,
        const Color(0xFF64748B),
        maxWidth: chartWidth,
      );
    }
  }

  void _paintCircular(Canvas canvas, Size size) {
    final total = valores.fold<double>(0, (sum, value) => sum + value.abs());
    if (total <= 0) return;

    final radius = (size.width < size.height ? size.width : size.height) * .27;
    final center = Offset(size.width * .34, size.height * .48);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final colors = [
      const Color(0xFF14B8A6),
      const Color(0xFF2563EB),
      const Color(0xFF0F2747),
      const Color(0xFF0891B2),
      const Color(0xFF64748B),
      const Color(0xFF4F46E5),
    ];

    var start = -1.5708;
    for (var i = 0; i < valores.length; i++) {
      final sweep = valores[i].abs() / total * 6.283185307;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .48
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }

    _drawText(
      canvas,
      _formatNumber(total),
      Offset(center.dx - radius * .55, center.dy - 14),
      19,
      const Color(0xFF0F172A),
      maxWidth: radius * 1.1,
      align: TextAlign.center,
      fontWeight: FontWeight.w900,
    );
    if (unidad.trim().isNotEmpty) {
      _drawText(
        canvas,
        unidad,
        Offset(center.dx - radius * .55, center.dy + 10),
        10,
        const Color(0xFF64748B),
        maxWidth: radius * 1.1,
        align: TextAlign.center,
      );
    }

    final legendX = size.width * .63;
    var legendY = 22.0;
    for (var i = 0; i < etiquetas.length; i++) {
      final color = colors[i % colors.length];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legendX, legendY + 3, 10, 10),
          const Radius.circular(3),
        ),
        Paint()..color = color,
      );
      final porcentaje = valores[i].abs() / total * 100;
      _drawText(
        canvas,
        '${_shortLabel(etiquetas[i], 18)}  ${porcentaje.toStringAsFixed(1)}%',
        Offset(legendX + 16, legendY),
        10.5,
        _text,
        maxWidth: size.width - legendX - 18,
      );
      legendY += 27;
      if (legendY > size.height - 22) break;
    }
  }

  void _drawAxisLabel(
    Canvas canvas,
    String label,
    double centerX,
    double y,
    double availableWidth,
  ) {
    _drawText(
      canvas,
      _shortLabel(label, 12),
      Offset(centerX - availableWidth / 2, y),
      9,
      _text,
      maxWidth: availableWidth,
      align: TextAlign.center,
    );
  }

  String _shortLabel(String text, int max) {
    final clean = text.trim();
    return clean.length <= max ? clean : '${clean.substring(0, max - 1)}…';
  }

  String _formatNumber(double value) {
    if (value.abs() >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
    Color color, {
    required double maxWidth,
    TextAlign align = TextAlign.left,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SafeChartPainter oldDelegate) {
    return oldDelegate.tipo != tipo ||
        oldDelegate.unidad != unidad ||
        oldDelegate.etiquetas.toString() != etiquetas.toString() ||
        oldDelegate.valores.toString() != valores.toString();
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 15.5,
              backgroundColor: Color(0xFF14B8A6),
              child: Icon(
                Icons.auto_awesome,
                color: Color(0xFF07111B),
                size: 17,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'SafeBrok IA está pensando…',
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
