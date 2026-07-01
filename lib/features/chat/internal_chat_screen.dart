import 'dart:async';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InternalChatScreen extends StatefulWidget {
  const InternalChatScreen({super.key});

  @override
  State<InternalChatScreen> createState() => _InternalChatScreenState();
}

class _InternalChatScreenState extends State<InternalChatScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController searchCtrl = TextEditingController();

  

  bool loading = true;
  String search = '';

  List<Map<String, dynamic>> usuarios = [];
  Map<String, Map<String, dynamic>> lastMessages = {};
  Map<String, int> unreadCount = {};

  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    loadUsers();

    refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => loadUsers(silent: true),
    );

    searchCtrl.addListener(() {
      setState(() {
        search = searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    searchCtrl.dispose();
    super.dispose();
  }

  

  Future<void> loadUsers({bool silent = false}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      if (!silent) {
        setState(() => loading = true);
      }

      final usersRes = await supabase
          .from('usuarios')
          .select('id, nombre, apellidos, auth_id, rol_usuario')
          .neq('auth_id', user.id)
          .order('nombre', ascending: true);

      final messagesRes = await supabase
          .from('chat_mensajes')
          .select()
          .or(
            'sender_auth_id.eq.${user.id},receiver_auth_id.eq.${user.id}',
          )
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> users =
          List<Map<String, dynamic>>.from(usersRes);

      final List<Map<String, dynamic>> messages =
          List<Map<String, dynamic>>.from(messagesRes);

      final Map<String, Map<String, dynamic>> latest = {};
      final Map<String, int> unread = {};

      for (final msg in messages) {
        final sender = msg['sender_auth_id']?.toString();
        final receiver = msg['receiver_auth_id']?.toString();

        final otherAuthId = sender == user.id ? receiver : sender;

        if (otherAuthId == null) continue;

        latest.putIfAbsent(otherAuthId, () => msg);

        final isIncoming = receiver == user.id;
        final isUnread = msg['leido'] != true;

        if (isIncoming && isUnread) {
          unread[otherAuthId] = (unread[otherAuthId] ?? 0) + 1;
        }
      }

      if (!mounted) return;

      users.sort((a, b) {
  final authA = a['auth_id']?.toString() ?? '';
  final authB = b['auth_id']?.toString() ?? '';

  final msgA = latest[authA];
  final msgB = latest[authB];

  final dateA = DateTime.tryParse(msgA?['created_at']?.toString() ?? '');
  final dateB = DateTime.tryParse(msgB?['created_at']?.toString() ?? '');

  if (dateA == null && dateB == null) return 0;
  if (dateA == null) return 1;
  if (dateB == null) return -1;

  return dateB.compareTo(dateA);
});

setState(() {
  usuarios = users;
  lastMessages = latest;
  unreadCount = unread;
  loading = false;
});
    } catch (e) {
      debugPrint('ERROR CHAT USERS: $e');

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredUsers {
    if (search.isEmpty) return usuarios;

    return usuarios.where((u) {
      final nombre =
          '${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}'.toLowerCase();
      final rol = (u['rol_usuario'] ?? '').toString().toLowerCase();

      return nombre.contains(search) || rol.contains(search);
    }).toList();
  }

  String _nombreUsuario(Map<String, dynamic> u) {
    final nombre = '${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}'.trim();
    return nombre.isEmpty ? 'Usuario sin nombre' : nombre;
  }

  String _rolText(String? rol) {
    switch (rol) {
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente comercial';
      default:
        return 'Usuario';
    }
  }

  String _lastMessageText(String authId) {
    final msg = lastMessages[authId];

    if (msg == null) return 'Sin mensajes todavía';

    final text = msg['mensaje']?.toString() ?? '';

    if (text.length <= 42) return text;

    return '${text.substring(0, 42)}...';
  }

  String _timeText(String authId) {
    final msg = lastMessages[authId];

    if (msg == null) return '';

    final created = DateTime.tryParse(msg['created_at']?.toString() ?? '');

    if (created == null) return '';

    final now = DateTime.now();
    final local = created.toLocal();

    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    return '${local.day}/${local.month}';
  }

  @override
  Widget build(BuildContext context) {
    final users = filteredUsers;

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _ChatBackground(),
          SafeArea(
            child: Column(
              children: [
                _header(),
                _searchBox(),
                const SizedBox(height: 8),
                Expanded(
                  child: loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF22D3EE),
                          ),
                        )
                      : users.isEmpty
                          ? _emptyState()
                          : RefreshIndicator(
                              color: const Color(0xFF22D3EE),
                              backgroundColor: const Color(0xFF061329),
                              onRefresh: () => loadUsers(),
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  24,
                                ),
                                itemCount: users.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final u = users[index];
                                  final authId = u['auth_id']?.toString() ?? '';
                                  final unread = unreadCount[authId] ?? 0;

                                  return _userTile(
                                    userData: u,
                                    unread: unread,
                                  );
                                },
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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF22D3EE),
                  Color(0xFF2563EB),
                  Color(0xFF7C3AED),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22D3EE).withOpacity(0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.forum_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat interno',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Comunicación directa con todo el equipo',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => loadUsers(),
            icon: const Icon(Icons.refresh_rounded),
            color: Colors.white,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.08),
              fixedSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      child: TextField(
        controller: searchCtrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Buscar usuario, rol o equipo...',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF22D3EE),
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.07),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: const Color(0xFF22D3EE).withOpacity(0.65),
            ),
          ),
        ),
      ),
    );
  }

  Widget _userTile({
    required Map<String, dynamic> userData,
    required int unread,
  }) {
    final authId = userData['auth_id']?.toString() ?? '';
    final nombre = _nombreUsuario(userData);
    final rol = _rolText(userData['rol_usuario']?.toString());
    final initial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        splashColor: const Color(0xFF22D3EE).withOpacity(0.10),
        highlightColor: const Color(0xFF22D3EE).withOpacity(0.06),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatConversationScreen(
                otherUser: userData,
              ),
            ),
          );

          loadUsers(silent: true);
        },
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.10),
                const Color(0xFF061329).withOpacity(0.96),
                const Color(0xFF020617).withOpacity(0.92),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: unread > 0
                  ? const Color(0xFF22D3EE).withOpacity(0.45)
                  : Colors.white.withOpacity(0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: unread > 0
                    ? const Color(0xFF22D3EE).withOpacity(0.12)
                    : Colors.black.withOpacity(0.18),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF22D3EE),
                          Color(0xFF2563EB),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF020617),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
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
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rol,
                      style: const TextStyle(
                        color: Color(0xFF67E8F9),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _lastMessageText(authId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unread > 0 ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight:
                            unread > 0 ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _timeText(authId),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  unread > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22D3EE),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unread.toString(),
                            style: const TextStyle(
                              color: Color(0xFF020617),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white38,
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Text(
        'No hay usuarios disponibles',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
class ChatConversationScreen extends StatefulWidget {
  final Map<String, dynamic> otherUser;

  const ChatConversationScreen({
    super.key,
    required this.otherUser,
  });

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController messageCtrl = TextEditingController();
  final ScrollController scrollController = ScrollController();

  bool loading = true;
  bool sending = false;

  bool showEmojiPicker = false;

  List<Map<String, dynamic>> messages = [];
  Timer? refreshTimer;

  String get otherAuthId => widget.otherUser['auth_id']?.toString() ?? '';

  String get otherName {
    final nombre =
        '${widget.otherUser['nombre'] ?? ''} ${widget.otherUser['apellidos'] ?? ''}'
            .trim();

    return nombre.isEmpty ? 'Usuario' : nombre;
  }

  @override
  void initState() {
    super.initState();
    loadMessages();

    refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => loadMessages(silent: true),
    );
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    messageCtrl.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> loadMessages({bool silent = false}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      if (!silent) {
        setState(() => loading = true);
      }

      final res = await supabase
          .from('chat_mensajes')
          .select()
          .or(
            'and(sender_auth_id.eq.${user.id},receiver_auth_id.eq.$otherAuthId),and(sender_auth_id.eq.$otherAuthId,receiver_auth_id.eq.${user.id})',
          )
          .order('created_at', ascending: true);

      final data = List<Map<String, dynamic>>.from(res);

      await supabase
          .from('chat_mensajes')
          .update({'leido': true})
          .eq('sender_auth_id', otherAuthId)
          .eq('receiver_auth_id', user.id)
          .eq('leido', false);

      if (!mounted) return;

      final oldLength = messages.length;

      setState(() {
        messages = data;
        loading = false;
      });

      if (messages.length != oldLength) {
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('ERROR CHAT MESSAGES: $e');

      if (!mounted) return;

      setState(() => loading = false);
    }
  }

  Future<void> sendMessage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final text = messageCtrl.text.trim();

    if (text.isEmpty || sending) return;

    setState(() => sending = true);

    try {
      await supabase.from('chat_mensajes').insert({
        'sender_auth_id': user.id,
        'receiver_auth_id': otherAuthId,
        'mensaje': text,
        'leido': false,
      });

      messageCtrl.clear();

      await loadMessages(silent: true);

      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar mensaje: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => sending = false);
      }
    }
  }
  Future<void> sendAttachment({
  required Uint8List bytes,
  required String fileName,
  required String tipo,
}) async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  try {
    final path =
        '${user.id}/$otherAuthId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    await supabase.storage.from('chat-archivos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final publicUrl =
        supabase.storage.from('chat-archivos').getPublicUrl(path);

    await supabase.from('chat_mensajes').insert({
      'sender_auth_id': user.id,
      'receiver_auth_id': otherAuthId,
      'mensaje': tipo == 'imagen' ? 'Imagen adjunta' : 'Archivo adjunto',
      'tipo': tipo,
      'archivo_url': publicUrl,
      'archivo_nombre': fileName,
      'leido': false,
    });

    await loadMessages(silent: true);
    _scrollToBottom();
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error al adjuntar archivo: $e')),
    );
  }
}


  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  bool _isMine(Map<String, dynamic> msg) {
    final user = supabase.auth.currentUser;
    return msg['sender_auth_id']?.toString() == user?.id;
  }

  String _timeText(String? raw) {
    final date = DateTime.tryParse(raw ?? '');

    if (date == null) return '';

    final local = date.toLocal();

    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');

    return '$h:$m';
  }

  String _roleText(String? rol) {
    switch (rol) {
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente comercial';
      default:
        return 'Usuario';
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = otherName.isNotEmpty ? otherName[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          const _ChatBackground(),
          SafeArea(
            child: Column(
              children: [
                _conversationHeader(initial),
                Expanded(
                  child: loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF22D3EE),
                          ),
                        )
                      : messages.isEmpty
                          ? _emptyConversation()
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                18,
                              ),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                return _messageBubble(messages[index]);
                              },
                            ),
                ),
                _composer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _conversationHeader(String initial) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF020617).withOpacity(0.80),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: Colors.white,
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF22D3EE),
                  Color(0xFF2563EB),
                ],
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otherName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _roleText(widget.otherUser['rol_usuario']?.toString()),
                      style: const TextStyle(
                        color: Color(0xFF67E8F9),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => loadMessages(),
            icon: const Icon(Icons.refresh_rounded),
            color: Colors.white70,
          ),
        ],
      ),
    );
  }

  Widget _emptyConversation() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.075),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
          ),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              color: Color(0xFF22D3EE),
              size: 54,
            ),
            SizedBox(height: 14),
            Text(
              'Todavía no hay mensajes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Escribe el primer mensaje para iniciar la conversación.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

 Widget _messageBubble(Map<String, dynamic> msg) {
  final mine = _isMine(msg);
  final text = msg['mensaje']?.toString() ?? '';
  final time = _timeText(msg['created_at']?.toString());
  final read = msg['leido'] == true;

  final tipo = msg['tipo']?.toString() ?? 'texto';
  final archivoUrl = msg['archivo_url']?.toString();
  final archivoNombre = msg['archivo_nombre']?.toString();

  return Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 310),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 8),
      decoration: BoxDecoration(
        gradient: mine
            ? const LinearGradient(
                colors: [
                  Color(0xFF22D3EE),
                  Color(0xFF2563EB),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: mine ? null : Colors.white.withOpacity(0.085),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(mine ? 20 : 5),
          bottomRight: Radius.circular(mine ? 5 : 20),
        ),
        border: Border.all(
          color: mine
              ? Colors.white.withOpacity(0.12)
              : Colors.white.withOpacity(0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (tipo == 'imagen' && archivoUrl != null && archivoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                archivoUrl,
                width: 220,
                fit: BoxFit.cover,
              ),
            )
          else if (tipo == 'archivo' &&
              archivoUrl != null &&
              archivoUrl.isNotEmpty)
            InkWell(
              onTap: () async {
                final url = Uri.parse(archivoUrl);
                await launchUrl(url, mode: LaunchMode.externalApplication);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.insert_drive_file_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      archivoNombre ?? 'Archivo adjunto',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              text,
              style: TextStyle(
                color: mine ? Colors.white : Colors.white,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                time,
                style: TextStyle(
                  color: mine ? Colors.white70 : Colors.white38,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 5),
                Icon(
                  read ? Icons.done_all_rounded : Icons.done_rounded,
                  size: 15,
                  color: read ? Colors.white : Colors.white70,
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

 Widget _composer() {
  return ClipRRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF020617).withOpacity(0.88),
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _openAttachmentMenu,
                    icon: const Icon(
                      Icons.add_circle_rounded,
                      color: Color(0xFF22D3EE),
                      size: 31,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: messageCtrl,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.075),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: const Color(0xFF22D3EE).withOpacity(0.60),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        showEmojiPicker = !showEmojiPicker;
                      });
                    },
                    icon: const Icon(
                      Icons.emoji_emotions_rounded,
                      color: Colors.amberAccent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: sending ? null : sendMessage,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF22D3EE),
                            Color(0xFF2563EB),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: sending
                          ? const Padding(
                              padding: EdgeInsets.all(15),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 25,
                            ),
                    ),
                  ),
                ],
              ),
              if (showEmojiPicker)
                SizedBox(
                  height: 260,
                  child: EmojiPicker(
                    onEmojiSelected: (category, emoji) {
                      messageCtrl.text += emoji.emoji;
                      messageCtrl.selection = TextSelection.fromPosition(
                        TextPosition(offset: messageCtrl.text.length),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  }
  Future<void> _openAttachmentMenu() async {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF061329),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.image_rounded,
                  color: Color(0xFF22D3EE),
                ),
                title: const Text(
                  'Enviar foto',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);

                  final picker = ImagePicker();
                  final image = await picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 80,
                  );

                  if (image == null) return;

                  final bytes = await image.readAsBytes();

                  await sendAttachment(
                    bytes: bytes,
                    fileName: image.name,
                    tipo: 'imagen',
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.attach_file_rounded,
                  color: Colors.orangeAccent,
                ),
                title: const Text(
                  'Enviar archivo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);

                  final result = await FilePicker.platform.pickFiles(
                    withData: true,
                  );

                  if (result == null) return;

                  final file = result.files.single;

                  if (file.bytes == null) return;

                  await sendAttachment(
                    bytes: file.bytes!,
                    fileName: file.name,
                    tipo: 'archivo',
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}
}

class _ChatBackground extends StatelessWidget {
  const _ChatBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF020617),
                Color(0xFF061B3A),
                Color(0xFF020617),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -110,
          right: -90,
          child: _glow(const Color(0xFF22D3EE), 270),
        ),
        Positioned(
          top: 280,
          left: -130,
          child: _glow(const Color(0xFF7C3AED), 290),
        ),
        Positioned(
          bottom: -110,
          right: -90,
          child: _glow(const Color(0xFF2563EB), 250),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.13),
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