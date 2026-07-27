import 'dart:convert';
import 'dart:ui';

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
  static const _bg = Color(0xFF07111B);
  static const _panel = Color(0xFF0D1924);
  static const _panelSoft = Color(0xFF122331);
  static const _cyan = Color(0xFF67E8F9);

  final _supabase = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<Map<String, dynamic>> _conversaciones = [];
  final List<Map<String, dynamic>> _mensajes = [];

  String? _conversacionActualId;
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

    if (_conversaciones.isNotEmpty) {
      await _abrirConversacion(
        _conversaciones.first['id'].toString(),
        cerrarDrawer: false,
      );
    } else {
      _nuevaConversacion();
    }
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

  void _nuevaConversacion() {
    if (!mounted) return;

    setState(() {
      _conversacionActualId = null;
      _mensajes
        ..clear()
        ..add({
          'role': 'assistant',
          'text':
              'Hola, soy Safebrok IA. Pregúntame sobre ventas, clientes, pólizas, recibos, objetivos o cualquier proceso de Safebrok.',
          'local': true,
        });
    });

    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    _scrollDown();
  }

  Future<void> _abrirConversacion(
    String id, {
    bool cerrarDrawer = true,
  }) async {
    if (id.isEmpty || _cargandoMensajes) return;

    if (cerrarDrawer &&
        (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
      Navigator.of(context).pop();
    }

    setState(() {
      _conversacionActualId = id;
      _cargandoMensajes = true;
      _mensajes.clear();
    });

    try {
      final data = await _supabase
          .from('ia_mensajes')
          .select('id, role, contenido, created_at')
          .eq('conversacion_id', id)
          .order('created_at', ascending: true);

      if (!mounted || _conversacionActualId != id) return;

      setState(() {
        _mensajes
          ..clear()
          ..addAll(
            (data as List).map(
              (e) => {
                'id': e['id'],
                'role': e['role'],
                'text': e['contenido'],
                'created_at': e['created_at'],
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

  Future<void> enviarPregunta() async {
    final pregunta = _controller.text.trim();
    if (pregunta.isEmpty || _enviando || _cargandoMensajes) return;

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

      await _supabase.from('ia_mensajes').insert({
        'conversacion_id': conversacionId,
        'auth_id': userId,
        'role': 'user',
        'contenido': pregunta,
      });

      final session = _supabase.auth.currentSession;
      final inicio = historial.length > 12 ? historial.length - 12 : 0;

      final response = await http.post(
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
          'historial': historial.skip(inicio).toList(),
          'conversacion_id': conversacionId,
        }),
      );

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

      final pdfUrl = (
        documento['url'] ??
        accion['url'] ??
        data['pdf_url']
      )?.toString().trim();

      final pdfNombre = (
        documento['nombre'] ??
        accion['archivo'] ??
        data['nombre_pdf'] ??
        'informe_safebrok.pdf'
      ).toString().trim();

      final tienePdf = pdfUrl != null && pdfUrl.isNotEmpty;

      final mensajeIa = await _supabase
          .from('ia_mensajes')
          .insert({
            'conversacion_id': conversacionId,
            'auth_id': userId,
            'role': 'assistant',
            'contenido': respuesta,
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
        backgroundColor: _panel,
        title: const Text(
          'Renombrar conversación',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Título',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withOpacity(.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
        backgroundColor: _panel,
        title: const Text(
          'Eliminar conversación',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Se eliminarán todos sus mensajes.',
          style: TextStyle(color: Colors.white70),
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
        final escritorio = constraints.maxWidth >= 900;

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
  backgroundColor: _bg.withOpacity(.96),
  elevation: 0,
  iconTheme: const IconThemeData(
    color: Colors.white,
  ),
  leading: escritorio
      ? null
      : IconButton(
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: _cyan, size: 20),
                SizedBox(width: 9),
                Text(
                  'Safebrok IA',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Nueva conversación',
                onPressed: _nuevaConversacion,
                icon: const Icon(Icons.edit_square, color: Colors.white),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: Row(
            children: [
              if (escritorio) SizedBox(width: 300, child: _sidebar()),
              if (escritorio)
                VerticalDivider(
                  width: 1,
                  color: Colors.white.withOpacity(.08),
                ),
              Expanded(child: _chat()),
            ],
          ),
        );
      },
    );
  }

  Widget _sidebar() {
    return Container(
      color: _panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: InkWell(
              onTap: _nuevaConversacion,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(.16)),
                  color: Colors.white.withOpacity(.04),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Nueva conversación',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 8, 17, 8),
            child: Row(
              children: [
                Text(
                  'CONVERSACIONES',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.42),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _cargandoConversaciones
                ? const Center(
                    child: CircularProgressIndicator(color: _cyan),
                  )
                : _conversaciones.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Todavía no hay conversaciones guardadas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                        itemCount: _conversaciones.length,
                        itemBuilder: (context, index) {
                          final c = _conversaciones[index];
                          final id = c['id'].toString();
                          final seleccionada = id == _conversacionActualId;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 3),
                            decoration: BoxDecoration(
                              color: seleccionada
                                  ? Colors.white.withOpacity(.09)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.only(left: 12, right: 4),
                              onTap: () => _abrirConversacion(id),
                              leading: Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: seleccionada ? _cyan : Colors.white54,
                                size: 19,
                              ),
                              title: Text(
                                c['titulo']?.toString() ??
                                    'Nueva conversación',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: seleccionada
                                      ? Colors.white
                                      : Colors.white70,
                                  fontWeight: seleccionada
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                color: _panelSoft,
                                icon: const Icon(
                                  Icons.more_horiz_rounded,
                                  color: Colors.white54,
                                  size: 19,
                                ),
                                onSelected: (value) {
                                  if (value == 'rename') _renombrar(c);
                                  if (value == 'delete') _eliminar(c);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text(
                                      'Renombrar',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Eliminar',
                                      style: TextStyle(
                                        color: Color(0xFFF87171),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Divider(height: 1, color: Colors.white.withOpacity(.08)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: _cyan.withOpacity(.14),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: _cyan,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _supabase.auth.currentUser?.email ?? 'Usuario Safebrok',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
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

  Widget _chat() {
    return Stack(
      children: [
        const _AiBackground(),
        Column(
          children: [
            if (_mensajes.length <= 1 && !_cargandoMensajes) _welcome(),
            Expanded(
              child: _cargandoMensajes
                  ? const Center(
                      child: CircularProgressIndicator(color: _cyan),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                      itemCount: _mensajes.length + (_enviando ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_enviando && index == _mensajes.length) {
                          return const _TypingBubble();
                        }
                        final m = _mensajes[index];
                        return _MessageBubble(
                          isUser: m['role'] == 'user',
                          text: m['text']?.toString() ?? '',
                          pdfUrl: m['pdf_url']?.toString(),
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
            _inputBar(),
          ],
        ),
      ],
    );
  }

  Widget _welcome() {
    final acciones = [
      ('Resumen de ventas', 'Hazme un resumen de las ventas de mi estructura'),
      ('Ranking del equipo', 'Hazme un ranking de mi equipo por prima neta'),
      ('Objetivo actual', '¿Cómo vamos respecto al objetivo actual?'),
      ('Recibos pendientes', '¿Qué recibos pendientes tiene mi estructura?'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_cyan, Colors.blueAccent],
              ),
              boxShadow: [
                BoxShadow(color: _cyan.withOpacity(.24), blurRadius: 30),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: _bg,
              size: 29,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '¿En qué puedo ayudarte?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Consulta información de Safebrok o pide ayuda con cualquier proceso.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.4),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: acciones.map((a) {
              return InkWell(
                onTap: () => enviarSugerencia(a.$2),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 220,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.055),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(.10)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_outward_rounded,
                        color: _cyan,
                        size: 18,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          a.$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        decoration: BoxDecoration(
          color: _bg.withOpacity(.94),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(.06)),
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 7, 7, 7),
              decoration: BoxDecoration(
                color: _panelSoft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(.12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.35,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => enviarPregunta(),
                      decoration: const InputDecoration(
                        hintText: 'Pregunta a Safebrok IA',
                        hintStyle: TextStyle(color: Colors.white38),
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
                                colors: [_cyan, Colors.blueAccent],
                              ),
                        color: _enviando ? Colors.white12 : null,
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
                              color: _bg,
                            ),
                    ),
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
  final String? pdfUrl;
  final String? pdfNombre;
  final Map<String, dynamic>? visualizacion;

  const _MessageBubble({
    required this.isUser,
    required this.text,
    this.pdfUrl,
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
    const cyan = Color(0xFF67E8F9);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: Container(
          margin: const EdgeInsets.only(bottom: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 31,
                  height: 31,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [cyan, Colors.blueAccent],
                    ),
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
                  padding: EdgeInsets.symmetric(
                    horizontal: isUser ? 16 : 2,
                    vertical: isUser ? 12 : 3,
                  ),
                  decoration: isUser
                      ? BoxDecoration(
                          color: const Color(0xFF1C3445),
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(
                            color: Colors.white.withOpacity(.08),
                          ),
                        )
                      : null,
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
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                                h2: const TextStyle(
                                  color: cyan,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                                h3: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                ),
                                p: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  height: 1.55,
                                  fontWeight: FontWeight.w500,
                                ),
                                listBullet: const TextStyle(
                                  color: cyan,
                                  fontSize: 15,
                                ),
                                strong: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                                code: TextStyle(
                                  color: cyan,
                                  backgroundColor:
                                      Colors.white.withOpacity(.08),
                                ),
                                tableHead: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                                tableBody:
                                    const TextStyle(color: Colors.white),
                                tableBorder: TableBorder.all(
                                  color: Colors.white24,
                                ),
                              ),
                            ),
                            if (visualizacion != null) ...[
                              const SizedBox(height: 16),
                              _DashboardVisual(
                                data: visualizacion!,
                              ),
                            ],
                            if ((pdfUrl ?? '').trim().isNotEmpty) ...[
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
                                      ? 'Descargar informe PDF'
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
                                  color: Colors.white38,
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
        color: const Color(0xFF0D1924),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['titulo']?.toString() ?? 'Resumen visual',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          if ((data['subtitulo']?.toString() ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              data['subtitulo'].toString(),
              style: const TextStyle(
                color: Colors.white54,
                height: 1.35,
              ),
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
        color: Colors.white.withOpacity(.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.08)),
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
                    color: Colors.white60,
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
                color: Colors.white,
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
              color: Colors.white54,
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
            (data['valores'] as List)
                .map((e) => double.tryParse(e.toString()) ?? 0),
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
            color: Colors.white,
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

  final _cyan = const Color(0xFF67E8F9);
  final _blue = const Color(0xFF3B82F6);
  final _grid = Colors.white.withOpacity(.12);
  final _text = Colors.white70;

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
      canvas.drawLine(
        Offset(left, y),
        Offset(left + chartWidth, y),
        gridPaint,
      );
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
        final x = left +
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
        _drawAxisLabel(canvas, etiquetas[i], x, top + chartHeight + 10, chartWidth);
      }
      canvas.drawPath(path, linePaint);
    } else {
      final slot = chartWidth / valores.length;
      final barWidth = (slot * .58).clamp(12.0, 44.0);
      final barPaint = Paint()
        ..shader =  LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_blue, _cyan],
        ).createShader(
          Rect.fromLTWH(left, top, chartWidth, chartHeight),
        );

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
        Colors.white54,
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
      const Color(0xFF67E8F9),
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
      const Color(0xFF22C55E),
      const Color(0xFFF59E0B),
      const Color(0xFFEC4899),
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
      Colors.white,
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
        Colors.white54,
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
              backgroundColor: Color(0xFF67E8F9),
              child: Icon(
                Icons.auto_awesome,
                color: Color(0xFF07111B),
                size: 17,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Safebrok IA está pensando…',
              style: TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiBackground extends StatelessWidget {
  const _AiBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -140,
            right: -100,
            child: _Glow(
              color: const Color(0xFF67E8F9).withOpacity(.15),
              size: 300,
            ),
          ),
          Positioned(
            bottom: -130,
            left: -100,
            child: _Glow(
              color: Colors.blueAccent.withOpacity(.11),
              size: 280,
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
