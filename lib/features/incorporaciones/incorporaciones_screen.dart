import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'incorporacion_repository.dart';

const _labels = {
  'agente': 'Agente',
  'jefe_equipo': 'Jefe de equipo',
  'jefe_ventas': 'Jefe de ventas',
  'director_zona': 'Director de zona',
  'director_nacional': 'Director nacional',
  'administracion': 'Administración',
  'DNI_ANVERSO': 'DNI anverso',
  'DNI_REVERSO': 'DNI reverso',
  'FOTO_CORPORATIVA': 'Foto corporativa/carnet',
  'CERTIFICADO_TITULARIDAD': 'Certificado de titularidad bancaria',
  'CV': 'CV',
  'CONTRATO': 'Contrato',
  'CONTRATO_FIRMADO': 'Contrato firmado',
};
String _label(dynamic v) => _labels[v] ?? v.toString().replaceAll('_', ' ');

bool _requiredComplete(Map<String, dynamic> expediente) {
  final types = List<Map<String, dynamic>>.from(
    expediente['documentos'] ?? [],
  ).map((document) => document['tipo']?.toString()).whereType<String>().toSet();
  return IncorporacionRepository.requiredTypes.every(types.contains);
}

String _visibleState(Map<String, dynamic> expediente) {
  if (expediente['estado'] == 'BORRADOR' && _requiredComplete(expediente)) {
    return 'LISTO PARA REVISIÓN';
  }
  return _label(expediente['estado']);
}

class IncorporacionesScreen extends StatefulWidget {
  const IncorporacionesScreen({super.key});
  @override
  State<IncorporacionesScreen> createState() => _IncorporacionesScreenState();
}

class _IncorporacionesScreenState extends State<IncorporacionesScreen> {
  final repo = IncorporacionRepository();
  bool loading = true;
  bool admin = false;
  String filter = 'TRABAJO';
  List<Map<String, dynamic>> rows = [];

  static const states = <String>[
    'BORRADOR',
    'ENVIADO',
    'EN_REVISION',
    'CORRECCION_REQUERIDA',
    'DOCUMENTACION_VALIDADA',
    'CONTRATO_DISPONIBLE',
    'PENDIENTE_FIRMA',
    'CONTRATO_FIRMADO',
    'ALTA_COMPLETADA',
  ];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final role = repo.normalRole((await repo.myProfile())['rol_usuario']);
      admin = role == 'administracion' || role == 'director_nacional';
      rows = await repo.list();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _hasSigned(Map<String, dynamic> e, {String? status}) {
    final documents = List<Map<String, dynamic>>.from(e['documentos'] ?? []);
    return documents.any(
      (d) =>
          d['tipo'] == 'CONTRATO_FIRMADO' &&
          (status == null || d['estado'] == status),
    );
  }

  bool _requiredDocumentsComplete(Map<String, dynamic> e) {
    final types = List<Map<String, dynamic>>.from(
      e['documentos'] ?? [],
    ).map((d) => d['tipo']?.toString()).whereType<String>().toSet();
    return IncorporacionRepository.requiredTypes.every(types.contains);
  }

  bool _needsWork(Map<String, dynamic> e) {
    final state = e['estado']?.toString();
    if (admin) {
      if (state == 'BORRADOR' && _requiredDocumentsComplete(e)) return true;
      if (<String>{
        'ENVIADO',
        'EN_REVISION',
        'DOCUMENTACION_VALIDADA',
        'CONTRATO_DISPONIBLE',
        'CONTRATO_FIRMADO',
      }.contains(state))
        return true;
      return state == 'PENDIENTE_FIRMA' && _hasSigned(e, status: 'SUBIDO');
    }
    if (state == 'BORRADOR') return !_requiredDocumentsComplete(e);
    if (<String>{'CORRECCION_REQUERIDA', 'CONTRATO_DISPONIBLE'}.contains(state))
      return true;
    if (state == 'PENDIENTE_FIRMA') {
      return !_hasSigned(e) || _hasSigned(e, status: 'CORRECCION_REQUERIDA');
    }
    return false;
  }

  List<Map<String, dynamic>> get filteredRows {
    if (filter == 'TODOS') return rows;
    if (filter == 'TRABAJO') return rows.where(_needsWork).toList();
    return rows.where((e) => e['estado'] == filter).toList();
  }

  int _count(String value) {
    if (value == 'TODOS') return rows.length;
    if (value == 'TRABAJO') return rows.where(_needsWork).length;
    return rows.where((e) => e['estado'] == value).length;
  }

  Widget _filters() {
    final values = <String>['TRABAJO', 'TODOS', ...states];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final value = values[index];
          final label = value == 'TRABAJO'
              ? 'Mi trabajo pendiente'
              : value == 'TODOS'
              ? 'Todos'
              : _label(value);
          return FilterChip(
            selected: filter == value,
            label: Text('$label (${_count(value)})'),
            onSelected: (_) => setState(() => filter = value),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff4f6fb),
    appBar: AppBar(
      title: Text(
        admin ? 'Administración · Incorporaciones' : 'Incorporaciones',
      ),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton: admin
        ? null
        : FloatingActionButton.extended(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IncorporacionWizard()),
              );
              load();
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Nueva incorporación'),
          ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              _filters(),
              Expanded(
                child: filteredRows.isEmpty
                    ? Center(
                        child: Text(
                          filter == 'TRABAJO'
                              ? 'No tienes expedientes pendientes'
                              : 'No hay expedientes en este estado',
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: filteredRows.length,
                        itemBuilder: (context, index) {
                          final e = filteredRows[index];
                          final r = Map<String, dynamic>.from(
                            e['responsable'] ?? {},
                          );
                          return Card(
                            child: ListTile(
                              isThreeLine: true,
                              leading: CircleAvatar(
                                child: Text((e['nombre'] ?? '?').toString()[0]),
                              ),
                              title: Text(
                                '${e['nombre']} ${e['apellidos']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${_label(e['figura'])} · Responsable: ${r['nombre'] ?? ''} ${r['apellidos'] ?? ''}\nEstado: ${_visibleState(e)}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => IncorporacionDetail(
                                      expediente: e,
                                      admin: admin,
                                    ),
                                  ),
                                );
                                load();
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
  );
}

class IncorporacionWizard extends StatefulWidget {
  const IncorporacionWizard({super.key, this.candidate});
  final Map<String, dynamic>? candidate;
  @override
  State<IncorporacionWizard> createState() => _IncorporacionWizardState();
}

class _IncorporacionWizardState extends State<IncorporacionWizard> {
  final repo = IncorporacionRepository(), key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> ctrl;
  int step = 0;
  bool busy = true;
  String? figure, responsible, id;
  List<String> figures = [];
  List<Map<String, dynamic>> responsibles = [];
  final docs = <String, PlatformFile>{};
  @override
  void initState() {
    super.initState();
    final c = widget.candidate ?? {};
    ctrl = {
      'nombre': TextEditingController(text: c['nombre']?.toString() ?? ''),
      'apellidos': TextEditingController(
        text: c['apellidos']?.toString() ?? '',
      ),
      'dni_nie': TextEditingController(text: c['dni']?.toString() ?? ''),
      'direccion': TextEditingController(
        text: c['direccion']?.toString() ?? '',
      ),
      'telefono': TextEditingController(text: c['telefono']?.toString() ?? ''),
      'email': TextEditingController(text: c['email']?.toString() ?? ''),
      'fecha': TextEditingController(),
    };
    init();
  }

  Future<void> init() async {
    figures = await repo.allowedFigures();
    figure = figures.isEmpty ? null : figures.first;
    if (figure != null) responsibles = await repo.allowedResponsibles(figure!);
    if (mounted) setState(() => busy = false);
  }

  Future<void> choose(String type) async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'doc', 'docx'],
    );
    if (r != null) setState(() => docs[type] = r.files.single);
  }

  Map<String, dynamic> data() => {
    'candidato_captacion_id': widget.candidate?['id'],
    'nombre': ctrl['nombre']!.text.trim(),
    'apellidos': ctrl['apellidos']!.text.trim(),
    'dni_nie': ctrl['dni_nie']!.text.trim().toUpperCase(),
    'direccion': ctrl['direccion']!.text.trim(),
    'telefono': ctrl['telefono']!.text.trim(),
    'email': ctrl['email']!.text.trim().toLowerCase(),
    'fecha_prevista_incorporacion': ctrl['fecha']!.text.trim(),
    'figura': figure,
    'responsable_id': responsible,
  };
  Future<void> persist() async {
    final e = await repo.saveDraft(data(), id: id);
    id = e['id'].toString();
  }

  Future<void> next() async {
    if (busy) return;
    if (step == 0 && !key.currentState!.validate()) return;
    if (step == 1 && (figure == null || responsible == null)) {
      snack('Selecciona figura y responsable');
      return;
    }
    if (step == 1) {
      setState(() => busy = true);
      try {
        await persist();
        if (mounted) setState(() => step++);
      } catch (error) {
        snack('No se pudo guardar figura y asignación: $error');
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    if (step < 3) setState(() => step++);
  }

  Future<void> send() async {
    if (docs.length < IncorporacionRepository.requiredTypes.length) {
      snack('Adjunta los cinco documentos obligatorios');
      return;
    }
    setState(() => busy = true);
    try {
      await persist();
      for (final entry in docs.entries)
        await repo.upload(id!, entry.key, entry.value);
      await repo.setState(id!, 'ENVIADO');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      snack('No se pudo enviar: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Widget field(String k, String label, {TextInputType? type}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: ctrl[k],
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) => (v ?? '').trim().isEmpty ? 'Campo obligatorio' : null,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nueva incorporación')),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: key,
            child: Stepper(
              currentStep: step,
              onStepTapped: (v) {
                if (v <= step) setState(() => step = v);
              },
              controlsBuilder: (c, d) => Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Row(
                  children: [
                    if (step < 3)
                      FilledButton(
                        onPressed: next,
                        child: const Text('Continuar'),
                      ),
                    if (step == 3)
                      FilledButton(
                        onPressed: send,
                        child: const Text('Enviar a Administración'),
                      ),
                    if (step > 0) ...[
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () => setState(() => step--),
                        child: const Text('Atrás'),
                      ),
                    ],
                  ],
                ),
              ),
              steps: [
                Step(
                  title: const Text('Datos personales'),
                  isActive: step >= 0,
                  content: Column(
                    children: [
                      field('nombre', 'Nombre'),
                      field('apellidos', 'Apellidos'),
                      field('dni_nie', 'DNI/NIE'),
                      field('direccion', 'Dirección'),
                      field('telefono', 'Teléfono', type: TextInputType.phone),
                      field('email', 'Email', type: TextInputType.emailAddress),
                      field(
                        'fecha',
                        'Fecha prevista (AAAA-MM-DD)',
                        type: TextInputType.datetime,
                      ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('Figura y asignación'),
                  isActive: step >= 1,
                  content: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: figure,
                        decoration: const InputDecoration(
                          labelText: 'Figura',
                          border: OutlineInputBorder(),
                        ),
                        items: figures
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(_label(v)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) async {
                          figure = v;
                          responsible = null;
                          responsibles = v == null
                              ? []
                              : await repo.allowedResponsibles(v);
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: responsible,
                        decoration: const InputDecoration(
                          labelText: 'Responsable jerárquico',
                          border: OutlineInputBorder(),
                        ),
                        items: responsibles
                            .map(
                              (u) => DropdownMenuItem(
                                value: u['id'].toString(),
                                child: Text(
                                  '${u['nombre']} ${u['apellidos']} · ${_label(u['rol_usuario'])}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => responsible = v),
                      ),
                    ],
                  ),
                ),
                Step(
                  title: const Text('Documentación'),
                  isActive: step >= 2,
                  content: Column(
                    children: IncorporacionRepository.requiredTypes
                        .map(
                          (t) => Card(
                            child: ListTile(
                              title: Text(_label(t)),
                              subtitle: Text(
                                docs[t]?.name ??
                                    'Obligatorio · PDF, imagen o Word',
                              ),
                              trailing: IconButton(
                                onPressed: () => choose(t),
                                icon: Icon(
                                  docs.containsKey(t)
                                      ? Icons.check_circle
                                      : Icons.upload_file,
                                  color: docs.containsKey(t)
                                      ? Colors.green
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Step(
                  title: const Text('Revisión y envío'),
                  isActive: step >= 3,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ctrl['nombre']!.text} ${ctrl['apellidos']!.text}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('${ctrl['dni_nie']!.text} · ${ctrl['email']!.text}'),
                      Text('Figura: ${_label(figure)}'),
                      Text('Documentos: ${docs.length}/5'),
                      const SizedBox(height: 10),
                      const Text(
                        'Al enviar, Administración recibirá una notificación y revisará cada documento.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
  );
}

class IncorporacionDetail extends StatefulWidget {
  const IncorporacionDetail({
    super.key,
    required this.expediente,
    required this.admin,
  });
  final Map<String, dynamic> expediente;
  final bool admin;
  @override
  State<IncorporacionDetail> createState() => _IncorporacionDetailState();
}

class _IncorporacionDetailState extends State<IncorporacionDetail> {
  final repo = IncorporacionRepository();
  late Map<String, dynamic> e;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    e = widget.expediente;
  }

  List<Map<String, dynamic>> get docs =>
      List<Map<String, dynamic>>.from(e['documentos'] ?? []);
  Future<void> openDoc(Map<String, dynamic> d) async {
    final url = await repo.signedUrl(d['storage_path']);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> upload(String type) async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
    );
    if (r == null) return;
    await repo.upload(e['id'], type, r.files.single);
    await refresh();
  }

  Future<void> refresh() async {
    final all = await repo.list();
    e = all.firstWhere((x) => x['id'] == e['id']);
    if (mounted) setState(() {});
  }

  Future<void> state(String s, {String? notes}) async {
    setState(() => busy = true);
    try {
      await repo.setState(e['id'], s, observations: notes);
      await refresh();
    } catch (x) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$x')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> correction() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Solicitar corrección'),
        content: TextField(
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Observaciones concretas',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty)
      await state('CORRECCION_REQUERIDA', notes: c.text.trim());
  }

  Future<void> rejectSignedContract() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rechazar contrato firmado'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo del rechazo',
            hintText: 'Indica exactamente qué debe corregirse',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Rechazar y notificar'),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    if (confirmed != true || reason.isEmpty) return;
    setState(() => busy = true);
    try {
      await repo.rejectSignedContract(e['id'].toString(), reason);
      await refresh();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo rechazar el contrato: $error')),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = Map<String, dynamic>.from(e['responsable'] ?? {});
    return Scaffold(
      appBar: AppBar(title: Text('${e['nombre']} ${e['apellidos']}')),
      body: busy
          ? const LinearProgressIndicator()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _visibleState(e),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${_label(e['figura'])} · ${r['nombre'] ?? ''} ${r['apellidos'] ?? ''}',
                        ),
                        Text(
                          '${e['dni_nie']} · ${e['telefono']} · ${e['email']}',
                        ),
                        Text(e['direccion'] ?? ''),
                        Text(
                          'Incorporación prevista: ${e['fecha_prevista_incorporacion']}',
                        ),
                        if (e['observaciones_correccion'] != null)
                          Text(
                            'Corrección: ${e['observaciones_correccion']}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Documentos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ...docs.map(
                  (d) => Card(
                    child: ListTile(
                      title: Text(_label(d['tipo'])),
                      subtitle: Text(
                        '${d['nombre_archivo']} · ${_label(d['estado'])}${d['observaciones'] == null ? '' : '\n${d['observaciones']}'}',
                      ),
                      onTap: () => openDoc(d),
                      trailing:
                          widget.admin &&
                              IncorporacionRepository.requiredTypes.contains(
                                d['tipo'],
                              )
                          ? Wrap(
                              children: [
                                IconButton(
                                  tooltip: 'Validar',
                                  onPressed: () async {
                                    await repo.reviewDocument(
                                      d['id'],
                                      true,
                                      null,
                                    );
                                    refresh();
                                  },
                                  icon: const Icon(
                                    Icons.check,
                                    color: Colors.green,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Rechazar',
                                  onPressed: () async {
                                    final c = TextEditingController();
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (x) => AlertDialog(
                                        title: const Text('Observación'),
                                        content: TextField(controller: c),
                                        actions: [
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(x, true),
                                            child: const Text('Guardar'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await repo.reviewDocument(
                                        d['id'],
                                        false,
                                        c.text,
                                      );
                                      refresh();
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            )
                          : const Icon(Icons.open_in_new),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.admin)
                  ...adminActions()
                else
                  ...responsibleActions(),
              ],
            ),
    );
  }

  List<Widget> adminActions() => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (e['estado'] == 'ENVIADO' ||
            (e['estado'] == 'BORRADOR' &&
                IncorporacionRepository.requiredTypes.every(
                  (type) => docs.any((d) => d['tipo'] == type),
                )))
          FilledButton(
            onPressed: () => state('EN_REVISION'),
            child: const Text('Iniciar revisión'),
          ),
        if (e['estado'] == 'EN_REVISION') ...[
          FilledButton(
            onPressed: () => state('DOCUMENTACION_VALIDADA'),
            child: const Text('Validar documentación'),
          ),
          OutlinedButton(
            onPressed: correction,
            child: const Text('Solicitar corrección'),
          ),
        ],
        if (e['estado'] == 'DOCUMENTACION_VALIDADA')
          FilledButton.icon(
            onPressed: () => upload('CONTRATO'),
            icon: const Icon(Icons.upload),
            label: const Text('Adjuntar contrato'),
          ),
        if (docs.any((d) => d['tipo'] == 'CONTRATO') &&
            e['estado'] == 'DOCUMENTACION_VALIDADA')
          FilledButton(
            onPressed: () => state('CONTRATO_DISPONIBLE'),
            child: const Text('Publicar contrato'),
          ),
        if (e['estado'] == 'CONTRATO_DISPONIBLE')
          FilledButton(
            onPressed: () => state('PENDIENTE_FIRMA'),
            child: const Text('Marcar pendiente de firma'),
          ),
        if (e['estado'] == 'CONTRATO_DISPONIBLE' ||
            e['estado'] == 'PENDIENTE_FIRMA')
          FilledButton.icon(
            onPressed: () => upload('CONTRATO_FIRMADO'),
            icon: const Icon(Icons.upload_file),
            label: const Text('Subir contrato firmado'),
          ),
        if (docs.any(
              (d) => d['tipo'] == 'CONTRATO_FIRMADO' && d['estado'] == 'SUBIDO',
            ) &&
            (e['estado'] == 'CONTRATO_DISPONIBLE' ||
                e['estado'] == 'PENDIENTE_FIRMA'))
          FilledButton(
            onPressed: () => state('CONTRATO_FIRMADO'),
            child: const Text('Confirmar contrato firmado'),
          ),
        if (docs.any(
              (d) => d['tipo'] == 'CONTRATO_FIRMADO' && d['estado'] == 'SUBIDO',
            ) &&
            (e['estado'] == 'PENDIENTE_FIRMA' ||
                e['estado'] == 'CONTRATO_FIRMADO'))
          OutlinedButton.icon(
            onPressed: rejectSignedContract,
            icon: const Icon(Icons.undo),
            label: const Text('Rechazar contrato firmado'),
          ),
        if (e['estado'] == 'CONTRATO_FIRMADO')
          FilledButton(
            onPressed: () => state('ALTA_COMPLETADA'),
            child: const Text('Completar incorporación'),
          ),
      ],
    ),
  ];
  List<Widget> responsibleActions() => [
    if (e['estado'] == 'CORRECCION_REQUERIDA')
      ...IncorporacionRepository.requiredTypes.map(
        (t) => OutlinedButton.icon(
          onPressed: () => upload(t),
          icon: const Icon(Icons.upload),
          label: Text('Sustituir ${_label(t)}'),
        ),
      ),
    if (e['estado'] == 'CORRECCION_REQUERIDA')
      FilledButton(
        onPressed: () => state('ENVIADO'),
        child: const Text('Reenviar expediente'),
      ),
    if (e['estado'] == 'CONTRATO_DISPONIBLE' ||
        e['estado'] == 'PENDIENTE_FIRMA')
      FilledButton.icon(
        onPressed: () => upload('CONTRATO_FIRMADO'),
        icon: const Icon(Icons.upload),
        label: const Text('Subir contrato firmado'),
      ),
    if (docs.any(
          (d) => d['tipo'] == 'CONTRATO_FIRMADO' && d['estado'] == 'SUBIDO',
        ) &&
        (e['estado'] == 'CONTRATO_DISPONIBLE' ||
            e['estado'] == 'PENDIENTE_FIRMA'))
      FilledButton(
        onPressed: () => state('CONTRATO_FIRMADO'),
        child: const Text('Enviar contrato firmado'),
      ),
  ];
}
