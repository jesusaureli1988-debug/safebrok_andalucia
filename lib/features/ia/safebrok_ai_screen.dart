import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class SafebrokAiScreen extends StatefulWidget {
  const SafebrokAiScreen({super.key});

  @override
  State<SafebrokAiScreen> createState() => _SafebrokAiScreenState();
}

class _SafebrokAiScreenState extends State<SafebrokAiScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool loading = false;

  final List<Map<String, String>> mensajes = [
    {
      'role': 'assistant',
      'text':
          'Hola, soy Safebrok IA. Puedo ayudarte a usar la app, resolver dudas comerciales y explicarte cualquier pantalla.'
    },
  ];

  Future<void> enviarPregunta() async {
    final pregunta = _controller.text.trim();

    if (pregunta.isEmpty || loading) return;

    setState(() {
      mensajes.add({
        'role': 'user',
        'text': pregunta,
      });
      loading = true;
      _controller.clear();
    });

    _scrollDown();

    try {
      final session = Supabase.instance.client.auth.currentSession;

final response = await http.post(
  Uri.parse(
    'https://ytmxjavihwylrswphczc.supabase.co/functions/v1/safebrok-ia',
  ),
  headers: {
    'Content-Type': 'application/json',
    if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
  },
  body: jsonEncode({
    'pregunta': pregunta,
  }),
);

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        setState(() {
          mensajes.add({
            'role': 'assistant',
            'text': data['respuesta'] ?? 'No he podido responder.',
          });
        });
      } else {
        setState(() {
          mensajes.add({
            'role': 'assistant',
            'text':
                'Ha ocurrido un error al conectar con Safebrok IA. ${data['error'] ?? ''}',
          });
        });
      }
    } catch (e) {
      setState(() {
        mensajes.add({
          'role': 'assistant',
          'text': 'No he podido conectar con Safebrok IA. Error: $e',
        });
      });
    } finally {
      setState(() => loading = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void enviarSugerencia(String texto) {
    _controller.text = texto;
    enviarPregunta();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Safebrok IA',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: .3,
          ),
        ),
      ),
      body: Stack(
        children: [
          const _AiBackground(),
          Column(
            children: [
              _header(),
              _quickActions(),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: mensajes.length + (loading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (loading && index == mensajes.length) {
                      return const _TypingBubble();
                    }

                    final msg = mensajes[index];
                    return _MessageBubble(
                      isUser: msg['role'] == 'user',
                      text: msg['text'] ?? '',
                    );
                  },
                ),
              ),
              _inputBar(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.07),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withOpacity(.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyanAccent.withOpacity(.95),
                        Colors.blueAccent.withOpacity(.75),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withOpacity(.25),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF07111B),
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asistente inteligente',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Pregunta sobre la app, ventas, clientes o procesos comerciales.',
                        style: TextStyle(
                          color: Colors.white70,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActions() {
    final acciones = [
      '¿Cómo añado una venta?',
      'Explícame cómo usar Safebrok',
      '¿Dónde veo mis clientes?',
      'Dame ideas para vender más',
    ];

    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: acciones.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: () => enviarSugerencia(acciones[index]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.07),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withOpacity(.12)),
              ),
              child: Center(
                child: Text(
                  acciones[index],
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF07111B).withOpacity(.92),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(.08)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.08),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(.12)),
                ),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => enviarPregunta(),
                  decoration: const InputDecoration(
                    hintText: 'Pregunta a Safebrok IA...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: enviarPregunta,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: loading
                        ? [
                            Colors.white24,
                            Colors.white10,
                          ]
                        : [
                            Colors.cyanAccent,
                            Colors.blueAccent,
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(.25),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Color(0xFF07111B),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final bool isUser;
  final String text;

  const _MessageBubble({
    required this.isUser,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 10,
          bottom: 2,
          left: isUser ? 42 : 0,
          right: isUser ? 0 : 42,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [
                    Colors.cyanAccent,
                    Colors.blueAccent,
                  ],
                )
              : null,
          color: isUser ? null : Colors.white.withOpacity(.08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 5),
            bottomRight: Radius.circular(isUser ? 5 : 20),
          ),
          border: Border.all(
            color: isUser ? Colors.transparent : Colors.white.withOpacity(.12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUser)
              Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF07111B),
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              )
            else
              MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  h1: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                  h2: const TextStyle(
                    color: Color(0xFF67E8F9),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                  h3: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                  p: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                  listBullet: const TextStyle(
                    color: Color(0xFF67E8F9),
                  ),
                  strong: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                  code: TextStyle(
                    color: Colors.cyanAccent,
                    backgroundColor: Colors.white.withOpacity(.08),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

            if (!isUser) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  borderRadius: BorderRadius.circular(100),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: text));

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Respuesta copiada',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          backgroundColor: const Color(0xFF16A34A),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.08),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: Colors.white.withOpacity(.12),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          color: Colors.white70,
                          size: 15,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Copiar',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 10, right: 80),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(.12)),
        ),
        child: const Text(
          'Safebrok IA está pensando...',
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AiBackground extends StatelessWidget {
  const _AiBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          right: -90,
          child: _Glow(
            color: Colors.cyanAccent.withOpacity(.28),
            size: 260,
          ),
        ),
        Positioned(
          bottom: -100,
          left: -80,
          child: _Glow(
            color: Colors.blueAccent.withOpacity(.22),
            size: 240,
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;

  const _Glow({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: const SizedBox(),
      ),
    );
  }
}