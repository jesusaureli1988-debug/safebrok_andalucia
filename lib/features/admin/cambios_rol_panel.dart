import 'package:safebrok_andalucia/core/widgets/progressive_records.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class CambiosRolPanel extends StatefulWidget {
  const CambiosRolPanel({
    super.key,
    required this.canManage,
    this.embedded = true,
  });
  final bool canManage;
  final bool embedded;
  @override
  State<CambiosRolPanel> createState() => _CambiosRolPanelState();
}

class _CambiosRolPanelState extends State<CambiosRolPanel> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? error;
  String? busyId;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await db
          .from('cambios_rol')
          .select(
            '*,usuario:usuarios!cambios_rol_usuario_id_fkey(nombre,apellidos,email)',
          )
          .order('updated_at', ascending: false);
      rows = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  String role(dynamic value) => (value ?? '').toString().replaceAll('_', ' ');
  String status(dynamic value) {
    switch ((value ?? '').toString()) {
      case 'PENDIENTE_CONTRATO':
        return 'Pendiente de contrato';
      case 'PENDIENTE_FIRMA':
        return 'Pendiente de firma';
      case 'FIRMADO_PENDIENTE_VALIDACION':
        return 'Firma pendiente de validar';
      case 'CORRECCION_REQUERIDA':
        return 'Corrección requerida';
      case 'APROBADO':
        return 'Aprobado';
      case 'RECHAZADO':
        return 'Rechazado';
      case 'CANCELADO':
        return 'Cancelado';
      default:
        return value?.toString() ?? '';
    }
  }

  void message(String text, {bool bad = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: bad ? Colors.red : Colors.green,
        ),
      );

  Future<void> upload(Map<String, dynamic> row, {required bool signed}) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null) return;
    final file = picked.files.single;
    if (file.bytes == null) {
      message('No se pudo leer el archivo.', bad: true);
      return;
    }
    final id = row['id'].toString();
    setState(() => busyId = id);
    try {
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path =
          '$id/${signed ? 'firmado' : 'contrato'}_${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await db.storage
          .from('cambios-rol')
          .uploadBinary(
            path,
            file.bytes!,
            fileOptions: const FileOptions(upsert: false),
          );
      await db.rpc(
        signed ? 'cambio_rol_enviar_firmado' : 'cambio_rol_publicar_contrato',
        params: {'p_id': id, 'p_path': path, 'p_nombre': file.name},
      );
      message(
        signed
            ? 'Contrato firmado enviado para validación.'
            : 'Contrato enviado al usuario para su firma.',
      );
      await load();
    } catch (e) {
      message('No se pudo enviar el documento: $e', bad: true);
    }
    if (mounted) setState(() => busyId = null);
  }

  Future<void> openDocument(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final url = await db.storage
          .from('cambios-rol')
          .createSignedUrl(path, 900);
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      ))
        throw Exception('No se pudo abrir el documento');
    } catch (e) {
      message('No se pudo abrir el documento: $e', bad: true);
    }
  }

  Future<void> resolve(Map<String, dynamic> row, bool approve) async {
    String? notes;
    if (!approve) {
      final controller = TextEditingController();
      notes = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Solicitar corrección'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Motivo obligatorio',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty)
                  Navigator.pop(context, controller.text.trim());
              },
              child: const Text('Enviar corrección'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (notes == null) return;
    }
    final id = row['id'].toString();
    setState(() => busyId = id);
    try {
      await db.rpc(
        'cambio_rol_resolver',
        params: {'p_id': id, 'p_aprobar': approve, 'p_observaciones': notes},
      );
      message(
        approve
            ? 'Cambio aprobado. El nuevo rol ya está activo.'
            : 'Corrección enviada al usuario.',
      );
      await load();
    } catch (e) {
      message('No se pudo completar la revisión: $e', bad: true);
    }
    if (mounted) setState(() => busyId = null);
  }

  Widget content() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 44),
            const SizedBox(height: 8),
            Text(error!, textAlign: TextAlign.center),
            TextButton(onPressed: load, child: const Text('Reintentar')),
          ],
        ),
      );
    if (rows.isEmpty)
      return const Center(child: Text('No hay cambios de figura en curso.'));
    return RefreshIndicator(
      onRefresh: load,
      child: ProgressiveListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, index) {
          final row = rows[index];
          final user = row['usuario'] is Map
              ? Map<String, dynamic>.from(row['usuario'])
              : <String, dynamic>{};
          final state = row['estado'].toString();
          final busy = busyId == row['id'].toString();
          return Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        child: Icon(
                          state == 'APROBADO'
                              ? Icons.verified
                              : Icons.description_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${user['nombre'] ?? ''} ${user['apellidos'] ?? ''}'
                                  .trim(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            Text(user['email']?.toString() ?? ''),
                          ],
                        ),
                      ),
                      Chip(label: Text(status(state))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${role(row['rol_anterior'])}  →  ${role(row['rol_nuevo'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if ((row['observaciones'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Observaciones: ${row['observaciones']}',
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (busy)
                    const LinearProgressIndicator()
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (row['contrato_path'] != null)
                          OutlinedButton.icon(
                            onPressed: () =>
                                openDocument(row['contrato_path']?.toString()),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Ver contrato'),
                          ),
                        if (row['contrato_firmado_path'] != null)
                          OutlinedButton.icon(
                            onPressed: () => openDocument(
                              row['contrato_firmado_path']?.toString(),
                            ),
                            icon: const Icon(Icons.draw_outlined),
                            label: const Text('Ver firmado'),
                          ),
                        if (widget.canManage &&
                            (state == 'PENDIENTE_CONTRATO' ||
                                state == 'CORRECCION_REQUERIDA'))
                          FilledButton.icon(
                            onPressed: () => upload(row, signed: false),
                            icon: const Icon(Icons.upload_file),
                            label: Text(
                              row['contrato_path'] == null
                                  ? 'Adjuntar y enviar contrato'
                                  : 'Enviar contrato corregido',
                            ),
                          ),
                        if (!widget.canManage &&
                            (state == 'PENDIENTE_FIRMA' ||
                                state == 'CORRECCION_REQUERIDA'))
                          FilledButton.icon(
                            onPressed: () => upload(row, signed: true),
                            icon: const Icon(Icons.draw),
                            label: const Text('Adjuntar contrato firmado'),
                          ),
                        if (widget.canManage &&
                            state == 'FIRMADO_PENDIENTE_VALIDACION') ...[
                          FilledButton.icon(
                            onPressed: () => resolve(row, true),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Dar visto bueno'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => resolve(row, false),
                            icon: const Icon(Icons.replay),
                            label: const Text('Solicitar corrección'),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? content()
      : Scaffold(
          appBar: AppBar(title: const Text('Mi cambio de figura')),
          body: SafeArea(child: content()),
        );
}
