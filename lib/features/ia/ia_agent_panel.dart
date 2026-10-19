import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class IaAgentActions extends StatefulWidget {
  const IaAgentActions({
    super.key,
    required this.conversationId,
    required this.revision,
  });
  final String? conversationId;
  final int revision;
  @override
  State<IaAgentActions> createState() => _IaAgentActionsState();
}

class _IaAgentActionsState extends State<IaAgentActions> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> rows = [];
  String? busy, error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant IaAgentActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId ||
        oldWidget.revision != widget.revision) {
      rows = [];
      load();
    }
  }

  Future<void> load() async {
    final id = widget.conversationId;
    if (id == null) {
      if (mounted) setState(() => rows = []);
      return;
    }
    try {
      final data = await db
          .from('ia_agente_acciones')
          .select('id,titulo,tipo,datos,estado,created_at')
          .eq('conversacion_id', id)
          .eq('estado', 'pendiente')
          .order('created_at')
          .limit(20);
      if (!mounted || widget.conversationId != id) return;
      setState(() {
        rows = List<Map<String, dynamic>>.from(data);
        error = null;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'No se pudieron cargar las acciones. Pulsa para reintentar.',
        );
    }
  }

  Future<void> resolve(Map<String, dynamic> row, bool confirm) async {
    setState(() {
      busy = row['id'].toString();
      error = null;
    });
    try {
      final result = await db.rpc(
        'ia_ejecutar_accion',
        params: {'p_id': row['id'], 'p_confirmar': confirm},
      );
      if (!mounted) return;
      final state = result is Map ? result['estado'] : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state == 'ejecutada'
                ? 'Acción realizada y verificada en SafeBrok'
                : 'Propuesta cancelada',
          ),
        ),
      );
      await load();
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is PostgrestException
              ? e.message
              : 'No se pudo ejecutar. La propuesta sigue pendiente.',
        );
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && error == null) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 270),
      color: const Color(0xFFF0FDFA),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(12),
        children: [
          if (error != null)
            TextButton.icon(
              onPressed: load,
              icon: const Icon(Icons.refresh),
              label: Text(error!),
            ),
          if (rows.isNotEmpty)
            const Text(
              'Acciones preparadas · revisa los datos antes de confirmar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          for (final row in rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['titulo'].toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (final entry in Map<String, dynamic>.from(
                      row['datos'] as Map,
                    ).entries)
                      if (entry.value != null &&
                          entry.value.toString().isNotEmpty)
                        SelectableText('${_label(entry.key)}: ${entry.value}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: busy != null
                              ? null
                              : () => resolve(row, true),
                          icon: busy == row['id']
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: const Text('Confirmar y ejecutar'),
                        ),
                        TextButton(
                          onPressed: busy != null
                              ? null
                              : () => resolve(row, false),
                          child: const Text('Cancelar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _label(String key) =>
    const {
      'titulo': 'Título',
      'nombre': 'Nombre',
      'descripcion': 'Descripción',
      'inicio': 'Inicio',
      'fin': 'Fin',
      'parent_id': 'Carpeta destino',
      'destinatario_auth_id': 'Destinatario',
      'prioridad': 'Prioridad',
      'fecha_limite': 'Fecha límite',
      'tipo': 'Tipo de bot',
      'frecuencia': 'Frecuencia',
      'primera_ejecucion': 'Primera ejecución',
      'instrucciones': 'Instrucciones del bot',
      'configuracion': 'Periodo, usuarios, módulos y formato',
    }[key] ??
    key;

class IaBotsScreen extends StatefulWidget {
  const IaBotsScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<IaBotsScreen> createState() => _IaBotsScreenState();
}

class _IaBotsScreenState extends State<IaBotsScreen> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> bots = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await db
          .from('ia_bots')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        bots = List<Map<String, dynamic>>.from(data);
        loading = false;
        error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'No se pudieron cargar tus automatizaciones.';
        });
    }
  }

  Future<void> toggle(Map<String, dynamic> bot) async {
    try {
      await db
          .from('ia_bots')
          .update({'activa': bot['activa'] != true})
          .eq('id', bot['id']);
      await load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo cambiar el estado del bot.'),
          ),
        );
    }
  }

  Future<void> history(Map<String, dynamic> bot) async {
    try {
      final data = await db
          .from('ia_bot_ejecuciones')
          .select('created_at,resultado')
          .eq('bot_id', bot['id'])
          .order('created_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Historial · ${bot['nombre']}'),
          content: SizedBox(
            width: 600,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (data.isEmpty) const Text('Todavía no se ha ejecutado.'),
                for (final row in data)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(row['created_at'].toString()),
                        const SizedBox(height: 8),
                        SelectableText(
                          (row['resultado'] as Map)['mensaje']?.toString() ??
                              '',
                        ),
                        IaArtifactList(
                          files: List<Map<String, dynamic>>.from(
                            (row['resultado'] as Map)['archivos'] ?? [],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cargar el historial.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(
            title: const Text('Mis bots y automatizaciones'),
            actions: [
              IconButton(
                onPressed: load,
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'MIS AUTOMATIZACIONES',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: load,
                    tooltip: 'Actualizar bots',
                    icon: const Icon(Icons.refresh, size: 19),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Chip(
                    avatar: const Icon(
                      Icons.play_circle_outline,
                      size: 16,
                      color: Color(0xFF0F766E),
                    ),
                    label: Text(
                      '${bots.where((b) => b['activa'] == true).length} activos',
                    ),
                  ),
                  Chip(
                    avatar: const Icon(
                      Icons.pause_circle_outline,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    label: Text(
                      '${bots.where((b) => b['activa'] != true).length} en pausa o completados',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (error != null) Text(error!),
              if (bots.isEmpty && error == null)
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE4F4F0),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.smart_toy_outlined,
                          size: 27,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Tu primer bot empieza aquí',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF16324F),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Elige qué quieres seguir y cuándo. La IA preparará la automatización para que puedas revisarla antes de activarla.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text('Producción por cargo')),
                          Chip(label: Text('Incorporaciones')),
                          Chip(label: Text('Recordatorios')),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Se ejecutan con la app cerrada y dejan el resultado en tu campanita. Horario de Madrid, con un margen de cinco minutos.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              for (final bot in bots)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: Text(bot['nombre'].toString()),
                    subtitle: Text(
                      '${_botType(bot['tipo'])} · ${bot['frecuencia']}\nPróxima: ${bot['proxima_ejecucion']}\n${bot['ultimo_error'] ?? ''}',
                    ),
                    isThreeLine: true,
                    onTap: () => history(bot),
                    trailing: Switch(
                      value: bot['activa'] == true,
                      onChanged: (_) => toggle(bot),
                    ),
                  ),
                ),
            ],
          ),
  );
}

String _botType(dynamic type) =>
    const {
      'resumen_produccion': 'Resumen de producción',
      'pendientes_incorporaciones': 'Seguimiento de incorporaciones',
      'recordatorio': 'Recordatorio',
      'informe_personalizado': 'Informe personalizado de actividad',
    }[type] ??
    type.toString();

/// Los archivos privados renuevan su enlace al abrirlos desde el historial.
class IaArtifactList extends StatelessWidget {
  const IaArtifactList({super.key, required this.files});
  final List<Map<String, dynamic>> files;

  Future<void> open(BuildContext context, Map<String, dynamic> file) async {
    try {
      var url = file['url']?.toString();
      final path = file['storage_path']?.toString();
      if (path != null && path.isNotEmpty) {
        url = await Supabase.instance.client.storage
            .from('safecloud')
            .createSignedUrl(path, 3600);
      }
      final uri = Uri.tryParse(url ?? '');
      if (uri == null ||
          uri.scheme != 'https' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Enlace no disponible');
      }
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir. Comprueba tu sesión y el archivo en SafeCloud.',
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final file in files)
        Card(
          child: ListTile(
            leading: Icon(
              ['png', 'jpeg', 'webp'].contains(file['tipo'])
                  ? Icons.image_outlined
                  : Icons.insert_drive_file_outlined,
              color: const Color(0xFF0F766E),
            ),
            title: Text(
              file['nombre']?.toString() ?? 'Archivo',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: const Text(
              'Guardado en tu SafeCloud · pulsar para abrir',
            ),
            trailing: const Icon(Icons.download_outlined),
            onTap: () => open(context, file),
          ),
        ),
    ],
  );
}
