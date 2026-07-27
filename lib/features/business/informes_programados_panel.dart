import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class InformesProgramadosPanel extends StatefulWidget {
  const InformesProgramadosPanel({super.key});

  @override
  State<InformesProgramadosPanel> createState() =>
      _InformesProgramadosPanelState();
}

class _InformesProgramadosPanelState extends State<InformesProgramadosPanel> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  bool _generating = false;
  String _email = '';
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _history = [];

  static const _reportTypes = {
    'objetivo_individual': 'Un objetivo concreto',
    'objetivos_generales': 'Resumen general de objetivos',
    'estructura': 'Informe completo de estructura',
    'ventas': 'Ventas detalladas',
    'anulaciones': 'Anulaciones detalladas',
    'recibos': 'Recibos y pendiente',
    'captacion': 'Captación',
  };

  static const _objectives = {
    'incremento_prima_sin_vehiculos': 'Incremento de prima',
    'incremento_asegurados': 'Incremento de asegurados',
    'incremento_ventas_netas': 'Incremento de ventas netas',
    'porcentaje_pendiente': 'Pendiente de recibos',
    'anulaciones_decesos': 'Anulaciones decesos',
    'anulaciones_resto': 'Anulaciones resto',
    'ventas_netas': 'Ventas netas',
    'facturacion': 'Facturación',
    'captacion': 'Captación',
    'liquido_decesos': 'Líquido decesos',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait([
        _supabase
            .from('usuarios')
            .select('email')
            .eq('auth_id', user.id)
            .maybeSingle(),
        _supabase
            .from('programaciones_informes_comerciales')
            .select()
            .eq('owner_auth_id', user.id)
            .order('created_at', ascending: false),
        _supabase
            .from('informes_comerciales_generados')
            .select()
            .eq('owner_auth_id', user.id)
            .order('created_at', ascending: false)
            .limit(20),
      ]);
      if (!mounted) return;
      setState(() {
        _email = _text((results[0] as Map<String, dynamic>?)?['email']);
        _schedules = List<Map<String, dynamic>>.from(results[1] as List);
        _history = List<Map<String, dynamic>>.from(results[2] as List);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('No se pudieron cargar los informes: $error', error: true);
    }
  }

  DateTime _nextExecution(
    String frequency, {
    int weekday = DateTime.monday,
    int monthDay = 1,
  }) {
    final now = DateTime.now();
    if (frequency == 'diaria') {
      var next = DateTime(now.year, now.month, now.day, 5);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      return next;
    }
    if (frequency == 'semanal') {
      var difference = weekday - now.weekday;
      if (difference < 0 ||
          (difference == 0 &&
              now.isAfter(DateTime(now.year, now.month, now.day, 5)))) {
        difference += 7;
      }
      return DateTime(now.year, now.month, now.day + difference, 5);
    }
    var next = DateTime(now.year, now.month, monthDay, 5);
    if (!next.isAfter(now)) {
      next = DateTime(now.year, now.month + 1, monthDay, 5);
    }
    return next;
  }

  Future<void> _createSchedule() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController(text: _email);
    var type = 'objetivos_generales';
    var objective = _objectives.keys.first;
    var frequency = 'diaria';
    var weekday = DateTime.monday;
    var monthDay = 1;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva programación de informe'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la programación',
                      hintText: 'Ej. Informe semanal de mi estructura',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Informe',
                      border: OutlineInputBorder(),
                    ),
                    items: _reportTypes.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => type = value!),
                  ),
                  if (type == 'objetivo_individual') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: objective,
                      decoration: const InputDecoration(
                        labelText: 'Objetivo incluido',
                        helperText:
                            'Esta programación solo incluirá este objetivo.',
                        border: OutlineInputBorder(),
                      ),
                      items: _objectives.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => objective = value!),
                    ),
                  ],
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: frequency,
                    decoration: const InputDecoration(
                      labelText: 'Frecuencia',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'diaria', child: Text('Diaria')),
                      DropdownMenuItem(
                        value: 'semanal',
                        child: Text('Semanal'),
                      ),
                      DropdownMenuItem(
                        value: 'mensual',
                        child: Text('Mensual'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => frequency = value!),
                  ),
                  if (frequency == 'semanal') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: weekday,
                      decoration: const InputDecoration(
                        labelText: 'Día de recepción',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Lunes')),
                        DropdownMenuItem(value: 2, child: Text('Martes')),
                        DropdownMenuItem(value: 3, child: Text('Miércoles')),
                        DropdownMenuItem(value: 4, child: Text('Jueves')),
                        DropdownMenuItem(value: 5, child: Text('Viernes')),
                        DropdownMenuItem(value: 6, child: Text('Sábado')),
                        DropdownMenuItem(value: 7, child: Text('Domingo')),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => weekday = value!),
                    ),
                  ],
                  if (frequency == 'mensual') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: monthDay,
                      decoration: const InputDecoration(
                        labelText: 'Día del mes',
                        helperText:
                            'Se limita al día 28 para funcionar todos los meses.',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(
                        28,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('Día ${index + 1}'),
                        ),
                      ),
                      onChanged: (value) =>
                          setDialogState(() => monthDay = value!),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo de destino',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.schedule_rounded),
                    title: Text('Entrega a las 05:00'),
                    subtitle: Text(
                      'La hora se interpreta siempre en Europe/Madrid.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.add_alarm_rounded),
              label: const Text('Crear programación'),
            ),
          ],
        ),
      ),
    );
    if (save != true) return;
    if (nameController.text.trim().isEmpty ||
        !emailController.text.contains('@')) {
      _message('Introduce un nombre y un correo válido.', error: true);
      return;
    }
    final user = _supabase.auth.currentUser!;
    await _supabase.from('programaciones_informes_comerciales').insert({
      'owner_auth_id': user.id,
      'nombre': nameController.text.trim(),
      'tipo_informe': type,
      'parametro_objetivo': type == 'objetivo_individual' ? objective : null,
      'frecuencia': frequency,
      'dia_semana': frequency == 'semanal' ? weekday : null,
      'dia_mes': frequency == 'mensual' ? monthDay : null,
      'email_destino': emailController.text.trim(),
      'activa': true,
      'proxima_ejecucion': _nextExecution(
        frequency,
        weekday: weekday,
        monthDay: monthDay,
      ).toUtc().toIso8601String(),
    });
    await _load();
    _message('Programación creada correctamente.');
  }

  Future<void> _generateNow(Map<String, dynamic> schedule) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final response = await _supabase.functions.invoke(
        'informes-plan-comercial',
        body: {'action': 'generate_now', 'programacion': schedule},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['ok'] != true) throw Exception(_text(data['error']));
      await _load();
      final url = _text(data['signed_url']);
      if (url.isNotEmpty) await launchUrl(Uri.parse(url));
      _message(
        data['enviado'] == true
            ? 'Informe generado, enviado y guardado en SafeCloud.'
            : 'Informe generado y guardado en SafeCloud.',
      );
    } catch (error) {
      _message('No se pudo generar el informe: $error', error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> schedule, bool active) async {
    await _supabase
        .from('programaciones_informes_comerciales')
        .update({'activa': active})
        .eq('id', schedule['id']);
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> schedule) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar programación'),
        content: Text(
          'Se eliminará “${_text(schedule['nombre'])}”. '
          'Los PDF ya generados permanecerán en SafeCloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _supabase
        .from('programaciones_informes_comerciales')
        .delete()
        .eq('id', schedule['id']);
    await _load();
  }

  Future<void> _openHistory(Map<String, dynamic> item) async {
    final path = _text(item['storage_path']);
    if (path.isEmpty) return;
    final signed = await _supabase.storage
        .from('safecloud')
        .createSignedUrl(path, 3600);
    await launchUrl(Uri.parse(signed));
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  String _frequencyLabel(Map<String, dynamic> row) {
    switch (_text(row['frecuencia'])) {
      case 'semanal':
        return 'Semanal · día ${row['dia_semana']} · 05:00';
      case 'mensual':
        return 'Mensual · día ${row['dia_mes']} · 05:00';
      default:
        return 'Diario · 05:00';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(30),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF071A2D),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SizedBox(
                width: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centro de informes programados',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Programa tantos informes como necesites. Cada '
                      'programación contiene un único informe y se entrega '
                      'en PDF por correo, con copia en SafeCloud.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _createSchedule,
                icon: const Icon(Icons.add_alarm_rounded),
                label: const Text('Nueva programación'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_schedules.isEmpty)
            const _EmptyReports()
          else
            ..._schedules.map(
              (schedule) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: schedule['activa'] == true
                        ? const Color(0xFFE7F8F1)
                        : Colors.grey.shade200,
                    child: Icon(
                      schedule['activa'] == true
                          ? Icons.schedule_send_rounded
                          : Icons.pause_rounded,
                      color: schedule['activa'] == true
                          ? const Color(0xFF047857)
                          : Colors.grey,
                    ),
                  ),
                  title: Text(
                    _text(schedule['nombre']),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${_reportTypes[_text(schedule['tipo_informe'])]} · '
                    '${_frequencyLabel(schedule)}\n'
                    '${_text(schedule['email_destino'])}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 3,
                    children: [
                      Switch(
                        value: schedule['activa'] == true,
                        onChanged: (value) => _toggle(schedule, value),
                      ),
                      IconButton(
                        tooltip: 'Generar ahora',
                        onPressed: _generating
                            ? null
                            : () => _generateNow(schedule),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        onPressed: () => _delete(schedule),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'Últimos informes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const Text(
              'Todavía no se ha generado ningún informe.',
              style: TextStyle(color: Colors.white60),
            )
          else
            ..._history
                .take(8)
                .map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    textColor: Colors.white,
                    iconColor: Colors.lightBlueAccent,
                    leading: const Icon(Icons.picture_as_pdf_rounded),
                    title: Text(_text(item['nombre_archivo'])),
                    subtitle: Text(
                      '${_text(item['estado']).toUpperCase()} · '
                      '${_text(item['created_at']).replaceFirst('T', ' ').split('.').first}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                    trailing: IconButton(
                      tooltip: 'Descargar',
                      onPressed: () => _openHistory(item),
                      icon: const Icon(Icons.download_rounded),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _EmptyReports extends StatelessWidget {
  const _EmptyReports();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Column(
      children: [
        Icon(
          Icons.mark_email_unread_outlined,
          color: Colors.lightBlueAccent,
          size: 36,
        ),
        SizedBox(height: 8),
        Text(
          'No tienes informes programados',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 4),
        Text(
          'Crea el primero y SafeBrok se encargará del resto.',
          style: TextStyle(color: Colors.white60),
        ),
      ],
    ),
  );
}
