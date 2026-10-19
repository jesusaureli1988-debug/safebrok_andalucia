import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PolicyAgentsLoader = Future<List<Map<String, dynamic>>> Function();
typedef PolicyEditorSaver = Future<void> Function(Map<String, dynamic> data);

bool policyAgentActive(dynamic value) => !{
  'baja',
  'inactivo',
  'inactiva',
  'bloqueado',
  'bloqueada',
  'desactivado',
  'desactivada',
  'suspendido',
  'suspendida',
}.contains((value ?? 'activo').toString().trim().toLowerCase());
String policyAgentName(Map<String, dynamic> user) =>
    '${user['nombre'] ?? ''} ${user['apellidos'] ?? ''}'.trim();

class PolicyEditDialog extends StatefulWidget {
  const PolicyEditDialog({
    super.key,
    required this.policy,
    this.allowedAuthIds,
    this.agentsLoader,
    this.saver,
  });
  final Map<String, dynamic> policy;
  final Set<String>? allowedAuthIds;
  final PolicyAgentsLoader? agentsLoader;
  final PolicyEditorSaver? saver;
  @override
  State<PolicyEditDialog> createState() => _PolicyEditState();
}

class _PolicyEditState extends State<PolicyEditDialog> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  List<Map<String, dynamic>> users = [];
  bool loading = true, failed = false, saving = false;
  String? agent, error;
  static const labels = {
    'producto': 'Producto',
    'compania': 'Compañía',
    'categoria_producto': 'Categoría producto',
    'forma_pago': 'Forma de pago',
    'fecha_efecto': 'Fecha efecto',
    'precio': 'Precio',
    'numero_asegurados': 'Número de asegurados',
    'prima_anual': 'Prima anual',
    'prima_anual_neta': 'Prima anual neta',
    'prima_anual_bruta': 'Prima anual bruta',
    'comision': 'Comisión',
  };
  static const numeric = {
    'precio',
    'prima_anual',
    'prima_anual_neta',
    'prima_anual_bruta',
    'comision',
  };
  @override
  void initState() {
    super.initState();
    agent = widget.policy['agente_auth_id']?.toString();
    for (final field in labels.keys) {
      fields[field] = TextEditingController(
        text: widget.policy[field]?.toString() ?? '',
      );
    }
    load();
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final result = await (widget.agentsLoader?.call() ?? fetchAgents())
          .timeout(const Duration(seconds: 25));
      if (mounted) setState(() => users = result);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> fetchAgents() async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 1000) {
      final page = await Supabase.instance.client
          .from('usuarios')
          .select('id,auth_id,parent_id,nombre,apellidos,rol_usuario,estado')
          .order('nombre')
          .order('id')
          .range(offset, offset + 999);
      result.addAll(List<Map<String, dynamic>>.from(page));
      if (page.length < 1000) break;
    }
    return result;
  }

  List<Map<String, dynamic>> get candidates => users.where((u) {
    final id = u['auth_id']?.toString() ?? '';
    return id.isNotEmpty &&
        policyAgentActive(u['estado']) &&
        (widget.allowedAuthIds == null || widget.allowedAuthIds!.contains(id));
  }).toList();
  String nameFor(String? id) {
    final match = users
        .where((u) => u['auth_id']?.toString() == id)
        .firstOrNull;
    if (match != null) return policyAgentName(match);
    return id == widget.policy['agente_auth_id']?.toString()
        ? (widget.policy['agente_nombre']?.toString() ?? 'Agente actual')
        : 'Sin agente';
  }

  String dependency(Map<String, dynamic> user) {
    final parent = users.where((u) => u['id'] == user['parent_id']).firstOrNull;
    return parent == null
        ? 'Dependencia no informada'
        : 'Depende de: ${policyAgentName(parent)}';
  }

  Future<void> chooseAgent() async {
    var search = '';
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Seleccionar agente'),
          content: SizedBox(
            width: 550,
            height: 420,
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Buscar nombre o apellidos',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) =>
                      setLocal(() => search = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final result = candidates
                          .where(
                            (u) => policyAgentName(
                              u,
                            ).toLowerCase().contains(search),
                          )
                          .toList();
                      if (result.isEmpty) {
                        return const Center(
                          child: Text(
                            'No hay agentes activos con esos datos dentro de tus permisos.',
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: result.length,
                        itemBuilder: (context, index) {
                          final user = result[index];
                          return ListTile(
                            selected: user['auth_id'] == agent,
                            title: Text(policyAgentName(user)),
                            subtitle: Text(
                              '${user['rol_usuario'] ?? ''}\n${dependency(user)}',
                            ),
                            isThreeLine: true,
                            trailing: user['auth_id'] == agent
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(context, user),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => agent = selected['auth_id'].toString());
    }
  }

  double? number(String text) {
    var value = text.trim();
    if (value.contains(',')) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(value);
  }

  DateTime? checkedDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value);
    return parsed != null && parsed.toIso8601String().substring(0, 10) == value
        ? parsed
        : null;
  }

  Future<void> save() async {
    if (saving || !(form.currentState?.validate() ?? false)) return;
    if (agent == null) {
      setState(() => error = 'Selecciona el agente de la póliza.');
      return;
    }
    final changed = agent != widget.policy['agente_auth_id']?.toString();
    if (changed && !candidates.any((u) => u['auth_id']?.toString() == agent)) {
      setState(
        () => error =
            'El agente seleccionado ya no está disponible. Recarga el listado.',
      );
      return;
    }
    if (changed) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar cambio de agente'),
          content: Text(
            'Póliza: ${widget.policy['numero_poliza']}\n\nDe: ${nameFor(widget.policy['agente_auth_id']?.toString())}\nA: ${nameFor(agent)}\n\nLa producción pasará al agente nuevo y a su estructura según los criterios de cada pantalla. No se moverán las demás pólizas ni la ficha del cliente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    final data = <String, dynamic>{
      for (final entry in fields.entries)
        entry.key: numeric.contains(entry.key)
            ? (entry.value.text.trim().isEmpty
                  ? null
                  : number(entry.value.text))
            : entry.key == 'numero_asegurados'
            ? (entry.value.text.trim().isEmpty
                  ? null
                  : int.tryParse(entry.value.text.trim()))
            : entry.key == 'fecha_efecto'
            ? DateTime.parse(
                entry.value.text.trim(),
              ).toIso8601String().substring(0, 10)
            : entry.value.text.trim(),
      'agente_auth_id': agent,
    };
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.saver != null) {
        await widget.saver!(data).timeout(const Duration(seconds: 25));
      } else {
        var query = Supabase.instance.client
            .from('ventas')
            .update(data)
            .eq('id', widget.policy['id']);
        final previous = widget.policy['agente_auth_id'];
        query = previous == null
            ? query.isFilter('agente_auth_id', null)
            : query.eq('agente_auth_id', previous);
        final result = await query
            .select('id')
            .maybeSingle()
            .timeout(const Duration(seconds: 25));
        if (result == null) {
          throw StateError(
            'La póliza ha cambiado o no tienes permiso. Recarga antes de editar.',
          );
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'No se han podido confirmar los cambios: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Editar póliza',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Número de póliza: ${widget.policy['numero_poliza'] ?? 'Sin número'}',
                ),
                const SizedBox(height: 24),
                const Text(
                  'Agente y dependencia',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  nameFor(agent),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (users.any((u) => u['auth_id']?.toString() == agent))
                  Text(
                    dependency(
                      users.firstWhere(
                        (u) => u['auth_id']?.toString() == agent,
                      ),
                    ),
                  ),
                if (loading)
                  const LinearProgressIndicator()
                else if (failed)
                  Column(
                    children: [
                      const Text(
                        'No se ha podido cargar el listado de agentes.',
                      ),
                      TextButton(
                        onPressed: saving ? null : load,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: saving ? null : chooseAgent,
                    icon: const Icon(Icons.person_search_outlined),
                    label: const Text('Cambiar agente'),
                  ),
                const SizedBox(height: 20),
                for (final entry in fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextFormField(
                      key: ValueKey('policy-edit-${entry.key}'),
                      controller: entry.value,
                      enabled: !saving,
                      keyboardType:
                          numeric.contains(entry.key) ||
                              entry.key == 'numero_asegurados'
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: labels[entry.key],
                        border: const OutlineInputBorder(),
                      ),
                      validator: (text) {
                        final value = text?.trim() ?? '';
                        if ({
                              'producto',
                              'compania',
                              'fecha_efecto',
                              'prima_anual_neta',
                              'comision',
                            }.contains(entry.key) &&
                            value.isEmpty) {
                          return 'Este dato es obligatorio.';
                        }
                        if (numeric.contains(entry.key) &&
                            value.isNotEmpty &&
                            (number(value) == null ||
                                !number(value)!.isFinite ||
                                number(value)! < 0)) {
                          return 'Introduce un importe válido, mayor o igual que cero.';
                        }
                        if (entry.key == 'numero_asegurados' &&
                            value.isNotEmpty &&
                            (int.tryParse(value) == null ||
                                int.parse(value) < 0)) {
                          return 'Introduce un número entero válido.';
                        }
                        if (entry.key == 'fecha_efecto' &&
                            checkedDate(value) == null) {
                          return 'Usa una fecha válida: AAAA-MM-DD.';
                        }
                        return null;
                      },
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(saving ? 'Guardando…' : 'Guardar cambios'),
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
