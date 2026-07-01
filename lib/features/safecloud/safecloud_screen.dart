// VERSIÓN SAFECLOUD PRO
// Incluye: Mi unidad, Compartido conmigo, compartir con compañeros,
// carpetas dentro de carpetas, mover, renombrar, borrar, subir varios archivos.

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SafeCloudScreen extends StatefulWidget {
  const SafeCloudScreen({super.key});

  @override
  State<SafeCloudScreen> createState() => _SafeCloudScreenState();
}

class _SafeCloudScreenState extends State<SafeCloudScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool uploading = false;
  bool gridView = true;
  bool sharedMode = false;

  String? currentFolderId;
  String search = '';

  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> path = [];
  List<Map<String, dynamic>> allFolders = [];
  List<Map<String, dynamic>> usuarios = [];

  static const bg = Color(0xFF07111D);
  static const card = Color(0xFF101C2B);
  static const card2 = Color(0xFF132437);
  static const blue = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    await loadUsuarios();
    await loadItems();
  }

  Future<void> loadUsuarios() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final res = await supabase
        .from('usuarios')
        .select('id, nombre, auth_id, rol_usuario')
        .neq('auth_id', user.id)
        .order('nombre');

    usuarios = List<Map<String, dynamic>>.from(res);
  }

  Future<void> loadItems() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => loading = true);

    try {
      final foldersRes = await supabase
          .from('safecloud_items')
          .select()
          .eq('owner_auth_id', user.id)
          .eq('tipo', 'carpeta')
          .order('nombre');

      allFolders = List<Map<String, dynamic>>.from(foldersRes);

      if (!sharedMode) {
        if (currentFolderId == null) {
          final res = await supabase
              .from('safecloud_items')
              .select()
              .eq('owner_auth_id', user.id)
              .isFilter('parent_id', null)
              .order('tipo')
              .order('nombre');

          items = List<Map<String, dynamic>>.from(res);
        } else {
          final res = await supabase
              .from('safecloud_items')
              .select()
              .eq('owner_auth_id', user.id)
              .eq('parent_id', currentFolderId!)
              .order('tipo')
              .order('nombre');

          items = List<Map<String, dynamic>>.from(res);
        }
      } else {
        if (currentFolderId == null) {
          final shares = await supabase
              .from('safecloud_shares')
              .select('item_id')
              .eq('shared_with_auth_id', user.id);

          final ids = List<Map<String, dynamic>>.from(shares)
              .map((e) => e['item_id'].toString())
              .toList();

          if (ids.isEmpty) {
            items = [];
          } else {
            final res = await supabase
                .from('safecloud_items')
                .select()
                .inFilter('id', ids)
                .order('tipo')
                .order('nombre');

            items = List<Map<String, dynamic>>.from(res);
          }
        } else {
          final res = await supabase
              .from('safecloud_items')
              .select()
              .eq('parent_id', currentFolderId!)
              .order('tipo')
              .order('nombre');

          items = List<Map<String, dynamic>>.from(res);
        }
      }
    } catch (e) {
      debugPrint("ERROR SAFECLOUD: $e");
    }

    setState(() => loading = false);
  }

  List<Map<String, dynamic>> get filteredItems {
    if (search.trim().isEmpty) return items;

    final q = search.trim().toLowerCase();

    return items.where((e) {
      return (e['nombre'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  bool isMine(Map<String, dynamic> item) {
    final user = supabase.auth.currentUser;
    return user != null && item['owner_auth_id'] == user.id;
  }

  Future<void> crearCarpeta() async {
    final nombre = await _inputDialog(
      title: "Nueva carpeta",
      label: "Nombre de la carpeta",
    );

    if (nombre == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('safecloud_items').insert({
      'owner_auth_id': user.id,
      'parent_id': currentFolderId,
      'nombre': nombre,
      'tipo': 'carpeta',
    });

    loadItems();
  }

  Future<void> crearNota() async {
    final nombre = await _inputDialog(
      title: "Nuevo archivo de texto",
      label: "Nombre del archivo",
      hint: "Ejemplo: notas cliente",
    );

    if (nombre == null) return;

    final contenido = await _textAreaDialog();

    if (contenido == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final fileName = nombre.endsWith('.txt') ? nombre : '$nombre.txt';

    final storagePath =
        "${user.id}/${DateTime.now().millisecondsSinceEpoch}_$fileName";

    final bytes = Uint8List.fromList(utf8.encode(contenido));

    await supabase.storage.from('safecloud').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            upsert: false,
            contentType: 'text/plain',
          ),
        );

    await supabase.from('safecloud_items').insert({
      'owner_auth_id': user.id,
      'parent_id': currentFolderId,
      'nombre': fileName,
      'tipo': 'archivo',
      'storage_path': storagePath,
      'mime_type': 'txt',
      'size_bytes': bytes.length,
    });

    loadItems();
  }

  Future<void> subirArchivos() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
    );

    if (result == null) return;

    setState(() => uploading = true);

    try {
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;

        final fileName = file.name;
        final storagePath =
            "${user.id}/${DateTime.now().millisecondsSinceEpoch}_$fileName";

        await supabase.storage.from('safecloud').uploadBinary(
              storagePath,
              bytes,
              fileOptions: const FileOptions(upsert: false),
            );

        await supabase.from('safecloud_items').insert({
          'owner_auth_id': user.id,
          'parent_id': currentFolderId,
          'nombre': fileName,
          'tipo': 'archivo',
          'storage_path': storagePath,
          'mime_type': file.extension,
          'size_bytes': file.size,
        });
      }
    } catch (e) {
      debugPrint("ERROR SUBIENDO ARCHIVOS: $e");
    }

    setState(() => uploading = false);
    loadItems();
  }

  Future<void> abrirArchivo(Map<String, dynamic> item) async {
    final storagePath = item['storage_path'];
    if (storagePath == null) return;

    final signedUrl = await supabase.storage
        .from('safecloud')
        .createSignedUrl(storagePath, 60 * 10);

    await launchUrl(
      Uri.parse(signedUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void abrirCarpeta(Map<String, dynamic> item) {
    setState(() {
      path.add(item);
      currentFolderId = item['id'];
      search = '';
    });

    loadItems();
  }

  void volverAtras() {
    if (path.isEmpty) return;

    setState(() {
      path.removeLast();
      currentFolderId = path.isEmpty ? null : path.last['id'];
      search = '';
    });

    loadItems();
  }

  void cambiarModo(bool shared) {
    setState(() {
      sharedMode = shared;
      currentFolderId = null;
      path.clear();
      search = '';
    });

    loadItems();
  }

  Future<void> compartir(Map<String, dynamic> item) async {
    if (!isMine(item)) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final selectedAuthId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Compartir con compañero",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: usuarios.length,
                    itemBuilder: (_, index) {
                      final u = usuarios[index];

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: blue.withOpacity(0.20),
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(
                          u['nombre'] ?? 'Sin nombre',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          u['rol_usuario'] ?? '',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context, u['auth_id'].toString());
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedAuthId == null) return;

    await supabase.from('safecloud_shares').insert({
      'item_id': item['id'],
      'shared_by_auth_id': user.id,
      'shared_with_auth_id': selectedAuthId,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Archivo/carpeta compartido correctamente"),
      ),
    );
  }

  Future<void> renombrar(Map<String, dynamic> item) async {
    if (!isMine(item)) return;

    final nuevoNombre = await _inputDialog(
      title: "Renombrar",
      label: "Nuevo nombre",
      initialValue: item['nombre'],
    );

    if (nuevoNombre == null) return;

    await supabase
        .from('safecloud_items')
        .update({'nombre': nuevoNombre})
        .eq('id', item['id']);

    loadItems();
  }

  Future<void> eliminar(Map<String, dynamic> item) async {
    if (!isMine(item)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar"),
        content: Text(
          item['tipo'] == 'carpeta'
              ? "Se eliminará la carpeta '${item['nombre']}' y todo su contenido."
              : "Se eliminará '${item['nombre']}'.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    if (item['tipo'] == 'archivo' && item['storage_path'] != null) {
      await supabase.storage.from('safecloud').remove([
        item['storage_path'],
      ]);
    }

    await supabase.from('safecloud_items').delete().eq('id', item['id']);

    loadItems();
  }

  Future<void> moverItem(Map<String, dynamic> item) async {
    if (!isMine(item)) return;

    final destinoId = await _selectFolderDialog(item);

    if (destinoId == 'cancel') return;

    await supabase.from('safecloud_items').update({
      'parent_id': destinoId == 'root' ? null : destinoId,
    }).eq('id', item['id']);

    loadItems();
  }

  Future<String?> _selectFolderDialog(Map<String, dynamic> movingItem) async {
    final movingId = movingItem['id']?.toString();

    final folders = allFolders.where((f) {
      return f['id'].toString() != movingId;
    }).toList();

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: card,
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
                const Text(
                  "Mover a...",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  onTap: () => Navigator.pop(context, 'root'),
                  leading: const Icon(Icons.home_rounded, color: Colors.white),
                  title: const Text(
                    "Inicio",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                ...folders.map((f) {
                  return ListTile(
                    onTap: () => Navigator.pop(context, f['id'].toString()),
                    leading: const Icon(
                      Icons.folder_rounded,
                      color: Colors.amberAccent,
                    ),
                    title: Text(
                      f['nombre'] ?? '',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  child: const Text("Cancelar"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _inputDialog({
    required String title,
    required String label,
    String? hint,
    String? initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);

    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  Future<String?> _textAreaDialog() async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Contenido del archivo"),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: "Escribe aquí el contenido...",
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text("Crear archivo"),
          ),
        ],
      ),
    );
  }

  String formatSize(dynamic size) {
    final bytes = int.tryParse((size ?? 0).toString()) ?? 0;

    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / 1024 / 1024).toStringAsFixed(1)} MB";
  }

  IconData iconFor(Map<String, dynamic> item) {
    if (item['tipo'] == 'carpeta') return Icons.folder_rounded;

    final name = (item['nombre'] ?? '').toString().toLowerCase();

    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png')) {
      return Icons.image_rounded;
    }
    if (name.endsWith('.xlsx') || name.endsWith('.xls')) {
      return Icons.table_chart_rounded;
    }
    if (name.endsWith('.doc') || name.endsWith('.docx')) {
      return Icons.description_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  Color colorFor(Map<String, dynamic> item) {
    if (item['tipo'] == 'carpeta') return Colors.amberAccent;

    final name = (item['nombre'] ?? '').toString().toLowerCase();

    if (name.endsWith('.pdf')) return Colors.redAccent;
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png')) {
      return Colors.lightBlueAccent;
    }
    if (name.endsWith('.xlsx') || name.endsWith('.xls')) {
      return Colors.greenAccent;
    }

    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final data = filteredItems;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: sharedMode
          ? null
          : FloatingActionButton.extended(
              backgroundColor: blue,
              foregroundColor: Colors.white,
              onPressed: _showCreateOptions,
              icon: const Icon(Icons.add_rounded),
              label: const Text("Nuevo"),
            ),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            _modeSelector(),
            _searchAndTools(),
            _breadcrumb(),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(color: blue),
                    )
                  : data.isEmpty
                      ? _emptyState()
                      : gridView
                          ? _grid(data)
                          : _list(data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF102A43),
            Color(0xFF0B1624),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 38),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "SafeCloud",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Tu nube interna de documentos",
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          if (uploading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _modeButton(
                title: "Mi unidad",
                icon: Icons.folder_copy_rounded,
                active: !sharedMode,
                onTap: () => cambiarModo(false),
              ),
            ),
            Expanded(
              child: _modeButton(
                title: "Compartido",
                icon: Icons.group_rounded,
                active: sharedMode,
                onTap: () => cambiarModo(true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton({
    required String title,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? blue : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchAndTools() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: TextField(
                onChanged: (v) => setState(() => search = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  icon: Icon(
                    Icons.search_rounded,
                    color: Colors.white.withOpacity(0.55),
                  ),
                  hintText: "Buscar en esta carpeta",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () => setState(() => gridView = !gridView),
            icon: Icon(
              gridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              color: Colors.white,
            ),
          ),
          IconButton(
            onPressed: loadItems,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumb() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: path.isEmpty ? null : volverAtras,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: path.isEmpty ? Colors.white24 : Colors.white,
            ),
          ),
          Expanded(
            child: Text(
              path.isEmpty
                  ? sharedMode
                      ? "Compartido conmigo"
                      : "Mi unidad"
                  : "${sharedMode ? 'Compartido' : 'Mi unidad'} / ${path.map((e) => e['nombre']).join(' / ')}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(List<Map<String, dynamic>> data) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: data.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (_, index) => _gridCard(data[index]),
    );
  }

  Widget _list(List<Map<String, dynamic>> data) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      itemCount: data.length,
      itemBuilder: (_, index) => _listTile(data[index]),
    );
  }

  Widget _gridCard(Map<String, dynamic> item) {
    final isFolder = item['tipo'] == 'carpeta';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => isFolder ? abrirCarpeta(item) : abrirArchivo(item),
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(iconFor(item), color: colorFor(item), size: 44),
                  const Spacer(),
                  _menu(item),
                ],
              ),
              const Spacer(),
              Text(
                item['nombre'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isFolder ? "Carpeta" : formatSize(item['size_bytes']),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.50),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (!isMine(item))
                    Icon(
                      Icons.group_rounded,
                      color: Colors.white.withOpacity(0.55),
                      size: 16,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listTile(Map<String, dynamic> item) {
    final isFolder = item['tipo'] == 'carpeta';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ListTile(
        onTap: () => isFolder ? abrirCarpeta(item) : abrirArchivo(item),
        leading: Icon(iconFor(item), color: colorFor(item), size: 34),
        title: Text(
          item['nombre'] ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          isFolder ? "Carpeta" : formatSize(item['size_bytes']),
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
        trailing: _menu(item),
      ),
    );
  }

  Widget _menu(Map<String, dynamic> item) {
    final mine = isMine(item);

    return PopupMenuButton<String>(
      color: card2,
      iconColor: Colors.white70,
      onSelected: (value) {
        if (value == 'open') {
          item['tipo'] == 'carpeta' ? abrirCarpeta(item) : abrirArchivo(item);
        }
        if (value == 'share') compartir(item);
        if (value == 'rename') renombrar(item);
        if (value == 'move') moverItem(item);
        if (value == 'delete') eliminar(item);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'open',
          child: Text("Abrir", style: TextStyle(color: Colors.white)),
        ),
        if (mine)
          const PopupMenuItem(
            value: 'share',
            child: Text("Compartir", style: TextStyle(color: Colors.white)),
          ),
        if (mine)
          const PopupMenuItem(
            value: 'rename',
            child: Text("Renombrar", style: TextStyle(color: Colors.white)),
          ),
        if (mine)
          const PopupMenuItem(
            value: 'move',
            child: Text("Mover a carpeta", style: TextStyle(color: Colors.white)),
          ),
        if (mine)
          const PopupMenuItem(
            value: 'delete',
            child: Text("Eliminar", style: TextStyle(color: Colors.white)),
          ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              sharedMode ? Icons.group_off_rounded : Icons.folder_open_rounded,
              color: Colors.white.withOpacity(0.30),
              size: 86,
            ),
            const SizedBox(height: 18),
            Text(
              sharedMode
                  ? "No tienes archivos compartidos"
                  : "Esta carpeta está vacía",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sharedMode
                  ? "Cuando un compañero comparta algo contigo aparecerá aquí."
                  : "Crea una carpeta, sube archivos o crea una nota interna.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.55)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _optionTile(
                  icon: Icons.create_new_folder_rounded,
                  title: "Crear carpeta",
                  subtitle: "Puedes crear carpetas dentro de carpetas",
                  onTap: () {
                    Navigator.pop(context);
                    crearCarpeta();
                  },
                ),
                _optionTile(
                  icon: Icons.upload_file_rounded,
                  title: "Subir archivos o fotos",
                  subtitle: "Puedes subir varios archivos a la vez",
                  onTap: () {
                    Navigator.pop(context);
                    subirArchivos();
                  },
                ),
                _optionTile(
                  icon: Icons.note_add_rounded,
                  title: "Crear archivo de texto",
                  subtitle: "Notas internas, instrucciones o recordatorios",
                  onTap: () {
                    Navigator.pop(context);
                    crearNota();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _optionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: blue.withOpacity(0.18),
        child: Icon(icon, color: Colors.white),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withOpacity(0.55)),
      ),
    );
  }
}