import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';

class CierresProduccionScreen extends StatefulWidget {
  const CierresProduccionScreen({super.key});

  @override
  State<CierresProduccionScreen> createState() =>
      _CierresProduccionScreenState();
}

class _CierresProduccionScreenState extends State<CierresProduccionScreen> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  bool _authorized = false;
  int _selectedYear = DateTime.now().year;
  List<Map<String, dynamic>> _cierres = [];

  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _blue = Color(0xFF2563EB);
  static const _green = Color(0xFF059669);
  static const _orange = Color(0xFFEA580C);
  static const _border = Color(0xFFE2E8F0);
  static const _background = Color(0xFFF4F7FB);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  String _normalizeRole(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  Future<void> _initialize() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final profile = await _supabase
          .from('usuarios')
          .select('rol_usuario')
          .eq('auth_id', user.id)
          .maybeSingle();

      final authorized =
          _normalizeRole(profile?['rol_usuario']) == 'director_nacional';

      if (!mounted) return;
      setState(() => _authorized = authorized);

      if (authorized) await _loadClosures();
    } catch (error) {
      _showMessage('No se pudo comprobar el acceso: $error', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadClosures() async {
    try {
      final data = await _supabase
          .from('cierres_produccion')
          .select()
          .eq('anio', _selectedYear)
          .order('mes');

      if (!mounted) return;
      setState(() {
        _cierres = List<Map<String, dynamic>>.from(data);
      });
    } catch (error) {
      _showMessage(
        'No se pudieron cargar los cierres. Ejecuta primero el SQL de configuración.\n$error',
        isError: true,
      );
    }
  }

  DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _dateText(dynamic value) {
    final date = _date(value);
    if (date == null) return 'Sin fecha';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _databaseDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _monthName(int month) {
    const months = [
      '',
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return month >= 1 && month <= 12 ? months[month] : 'Periodo';
  }

  bool _isCurrent(Map<String, dynamic> closure) {
    final from = _date(closure['fecha_desde']);
    final to = _date(closure['fecha_hasta']);
    if (from == null || to == null) return false;
    final today = DateUtils.dateOnly(DateTime.now());
    return !today.isBefore(from) && !today.isAfter(to);
  }

  Future<void> _changeYear(int delta) async {
    setState(() {
      _selectedYear += delta;
      _loading = true;
    });
    await _loadClosures();
    if (mounted) setState(() => _loading = false);
  }

  Future<DateTime?> _pickDate(DateTime initial) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100, 12, 31),
      locale: const Locale('es', 'ES'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _blue,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: _ink,
          ),
        ),
        child: child!,
      ),
    );
  }

  Future<void> _openEditor([Map<String, dynamic>? existing]) async {
    if (_saving) return;

    var month = existing?['mes'] as int? ?? DateTime.now().month;
    var year = existing?['anio'] as int? ?? _selectedYear;
    var from = _date(existing?['fecha_desde']) ?? DateTime(year, month - 1, 24);
    var to = _date(existing?['fecha_hasta']) ?? DateTime(year, month, 23);
    final notes = TextEditingController(
      text: (existing?['observaciones'] ?? '').toString(),
    );

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            22,
            14,
            22,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  existing == null ? 'Nuevo cierre' : 'Editar cierre',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Define el periodo oficial de producción. Las dos fechas se consideran incluidas.',
                  style: TextStyle(color: _muted, height: 1.4),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: month,
                        decoration: _inputDecoration('Mes de producción'),
                        items: List.generate(
                          12,
                          (index) => DropdownMenuItem(
                            value: index + 1,
                            child: Text(_monthName(index + 1)),
                          ),
                        ),
                        onChanged: existing == null
                            ? (value) {
                                if (value != null) {
                                  setSheetState(() => month = value);
                                }
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 112,
                      child: TextFormField(
                        initialValue: year.toString(),
                        enabled: existing == null,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('Año'),
                        onChanged: (value) {
                          year = int.tryParse(value) ?? year;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _dateButton(
                        label: 'Fecha desde',
                        date: from,
                        onTap: () async {
                          final value = await _pickDate(from);
                          if (value != null) setSheetState(() => from = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dateButton(
                        label: 'Fecha hasta',
                        date: to,
                        onTap: () async {
                          final value = await _pickDate(to);
                          if (value != null) setSheetState(() => to = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: _inputDecoration('Observaciones opcionales'),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (year < 2024 || year > 2100) {
                        _showMessage('Introduce un año válido.', isError: true);
                        return;
                      }
                      if (to.isBefore(from)) {
                        _showMessage(
                          'La fecha hasta no puede ser anterior a la fecha desde.',
                          isError: true,
                        );
                        return;
                      }
                      Navigator.pop(sheetContext, true);
                    },
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Guardar periodo'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) {
      notes.dispose();
      return;
    }

    await _saveClosure(
      existing: existing,
      month: month,
      year: year,
      from: from,
      to: to,
      notes: notes.text.trim(),
    );
    notes.dispose();
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _blue, width: 1.5),
    ),
  );

  Widget _dateButton({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  color: _blue,
                  size: 19,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    _dateText(date.toIso8601String()),
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveClosure({
    required Map<String, dynamic>? existing,
    required int month,
    required int year,
    required DateTime from,
    required DateTime to,
    required String notes,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final payload = {
        'anio': year,
        'mes': month,
        'fecha_desde': _databaseDate(from),
        'fecha_hasta': _databaseDate(to),
        'observaciones': notes.isEmpty ? null : notes,
      };

      if (existing == null) {
        await _supabase.from('cierres_produccion').insert({
          ...payload,
          'estado': 'abierto',
          'creado_por': user.id,
        });
      } else {
        await _supabase
            .from('cierres_produccion')
            .update(payload)
            .eq('id', existing['id']);
      }

      ProductionPeriodService.instance.invalidateCache();

      _selectedYear = year;

      await _loadClosures();
      _showMessage('Periodo guardado correctamente.');
    } on PostgrestException catch (error) {
      final overlap =
          error.message.toLowerCase().contains('overlap') ||
          error.message.toLowerCase().contains('solap');
      _showMessage(
        overlap
            ? 'Las fechas coinciden con otro periodo existente.'
            : 'No se pudo guardar el periodo: ${error.message}',
        isError: true,
      );
    } catch (error) {
      _showMessage('No se pudo guardar el periodo: $error', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> closure) async {
    final isClosed = closure['estado'] == 'cerrado';
    final user = _supabase.auth.currentUser;
    if (user == null || _saving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isClosed ? 'Reabrir periodo' : 'Cerrar producción'),
        content: Text(
          isClosed
              ? 'El periodo volverá a admitir revisiones y cambios.'
              : 'El periodo quedará marcado oficialmente como cerrado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isClosed ? 'Reabrir' : 'Cerrar periodo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _supabase
          .from('cierres_produccion')
          .update({
            'estado': isClosed ? 'abierto' : 'cerrado',
            'cerrado_por': isClosed ? null : user.id,
            'cerrado_at': isClosed ? null : DateTime.now().toIso8601String(),
          })
          .eq('id', closure['id']);
      ProductionPeriodService.instance.invalidateCache();
      await _loadClosures();
      _showMessage(isClosed ? 'Periodo reabierto.' : 'Producción cerrada.');
    } catch (error) {
      _showMessage('No se pudo cambiar el estado: $error', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFB91C1C) : _green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
        ),
        title: const Text(
          'Cierres de producción',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _authorized ? _loadClosures : null,
            icon: const Icon(Icons.refresh_rounded),
            color: _blue,
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _authorized
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : () => _openEditor(),
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Nuevo periodo',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : !_authorized
          ? _accessDenied()
          : RefreshIndicator(
              onRefresh: _loadClosures,
              color: _blue,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
                children: [
                  _hero(),
                  const SizedBox(height: 16),
                  _yearSelector(),
                  const SizedBox(height: 16),
                  if (_cierres.isEmpty)
                    _emptyState()
                  else
                    ..._cierres.map(_closureCard),
                ],
              ),
            ),
    );
  }

  Widget _hero() {
    final closed = _cierres.where((item) => item['estado'] == 'cerrado').length;
    final current = _cierres.where(_isCurrent).firstOrNull;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2B5B), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332563EB),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            color: Colors.white,
            size: 34,
          ),
          const SizedBox(height: 18),
          const Text(
            'Calendario oficial de producción',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            current == null
                ? 'No hay un periodo configurado para la fecha actual.'
                : '${_monthName(current['mes'])}: ${_dateText(current['fecha_desde'])} — ${_dateText(current['fecha_hasta'])}',
            style: const TextStyle(color: Color(0xFFDDEAFE), height: 1.4),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _heroChip('${_cierres.length} periodos en $_selectedYear'),
              _heroChip('$closed cerrados'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.14),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white.withOpacity(0.18)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );

  Widget _yearSelector() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _border),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: () => _changeYear(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(
            children: [
              const Text(
                'EJERCICIO',
                style: TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '$_selectedYear',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _changeYear(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ),
  );

  Widget _closureCard(Map<String, dynamic> closure) {
    final closed = closure['estado'] == 'cerrado';
    final current = _isCurrent(closure);
    final month = int.tryParse(closure['mes'].toString()) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: current ? _blue : _border,
          width: current ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: closed
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  month.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: closed ? _green : _blue,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${_monthName(month)} ${closure['anio']}',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (current) ...[
                          const SizedBox(width: 8),
                          _statusPill('ACTUAL', _blue),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_dateText(closure['fecha_desde'])} — ${_dateText(closure['fecha_hasta'])}',
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(
                closed ? 'CERRADO' : 'ABIERTO',
                closed ? _green : _orange,
              ),
            ],
          ),
          if ((closure['observaciones'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                closure['observaciones'].toString(),
                style: const TextStyle(color: _muted, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _openEditor(closure),
                  icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                  label: const Text('Editar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _toggleStatus(closure),
                  icon: Icon(
                    closed ? Icons.lock_open_rounded : Icons.lock_rounded,
                    size: 18,
                  ),
                  label: Text(closed ? 'Reabrir' : 'Cerrar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: closed ? _blue : _ink,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10),
    ),
  );

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _border),
    ),
    child: const Column(
      children: [
        Icon(Icons.event_busy_rounded, color: Color(0xFF94A3B8), size: 52),
        SizedBox(height: 14),
        Text(
          'No hay cierres configurados',
          style: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Crea el primer periodo para comenzar a centralizar el calendario de producción.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, height: 1.4),
        ),
      ],
    ),
  );

  Widget _accessDenied() => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.admin_panel_settings_rounded, size: 62, color: _orange),
          SizedBox(height: 18),
          Text(
            'Acceso exclusivo',
            style: TextStyle(
              color: _ink,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'Solo el director nacional puede gestionar los cierres de producción.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted),
          ),
        ],
      ),
    ),
  );
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
