import 'package:safebrok_andalucia/core/widgets/progressive_records.dart';
import 'dart:typed_data';

import 'package:safebrok_andalucia/core/production/policy_effect_date.dart';
import 'package:safebrok_andalucia/core/production/policy_sales_query.dart';
import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';
import 'package:safebrok_andalucia/core/payroll/role_compensation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MyInvoicesScreen extends StatefulWidget {
  const MyInvoicesScreen({super.key});

  @override
  State<MyInvoicesScreen> createState() => _MyInvoicesScreenState();
}

class _MyInvoicesScreenState extends State<MyInvoicesScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _currency = NumberFormat.currency(locale: 'es_ES', symbol: '€');

  List<Map<String, dynamic>> _invoices = [];
  bool _loading = true;
  bool _openingPdf = false;
  String? _error;
  String _statusFilter = 'todas';
  int? _yearFilter;

  static const _months = <String>[
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

  @override
  void initState() {
    super.initState();
    _loadInvoices();
    _searchController.addListener(_refresh);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInvoices({bool showLoader = true}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'No hay una sesión activa.';
      });
      return;
    }

    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _supabase
            .from('nominas_facturas')
            .select()
            .eq('usuario_auth_id', user.id)
            .order('anio', ascending: false)
            .order('mes', ascending: false),
        _calculateDraftMonths(user.id),
      ]);

      final official = (results[0] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final calculated = results[1] as List<Map<String, dynamic>>;

      final byPeriod = <String, Map<String, dynamic>>{};
      for (final draft in calculated) {
        byPeriod[_periodKey(draft['anio'], draft['mes'])] = draft;
      }
      for (final invoice in official) {
        final key = _periodKey(invoice['anio'], invoice['mes']);
        final draft = byPeriod[key];
        if (draft != null) {
          invoice['_draft_lines'] = draft['_draft_lines'];
          invoice['_prima_neta_total'] = draft['_prima_neta_total'];
          invoice['_primas_dv'] = draft['_primas_dv'];
          invoice['_condicion_aplicada'] = draft['_condicion_aplicada'];
        }
        byPeriod[key] = invoice;
      }

      final merged = byPeriod.values.toList()
        ..sort((a, b) {
          final aDate = DateTime(_integer(a['anio']), _integer(a['mes']));
          final bDate = DateTime(_integer(b['anio']), _integer(b['mes']));
          return bDate.compareTo(aDate);
        });

      if (!mounted) return;
      setState(() {
        _invoices = merged;
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No hemos podido calcular tus facturas.';
      });
      debugPrint('ERROR MIS FACTURAS: $error');
      debugPrint('$stack');
    }
  }

  Future<List<Map<String, dynamic>>> _calculateDraftMonths(
    String authId,
  ) async {
    final data = await Future.wait<dynamic>([
      _supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          )
          .eq('auth_id', authId)
          .maybeSingle(),
      _supabase
          .from('usuarios')
          .select(
            'id, auth_id, parent_id, rol_usuario, nombre, apellidos, email',
          ),
      _supabase
          .from('cierres_produccion')
          .select('anio, mes, fecha_desde, fecha_hasta, estado')
          .order('fecha_desde'),
    ]);

    if (data[0] == null) return [];
    final profile = Map<String, dynamic>.from(data[0] as Map);
    final users = (data[1] as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final closures = (data[2] as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final role = _normaliseRole(profile['rol_usuario']);
    final structure = _validStructure(profile, users);
    final authIds = structure
        .map((item) => _text(item['auth_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (authIds.isEmpty) return [];

    final salesData = await PolicySalesQuery.load(_supabase, authIds: authIds);
    final sales = (salesData as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final grouped = <String, Map<String, dynamic>>{};
    for (final sale in sales) {
      final effectDate = _effectDate(sale);
      if (effectDate == null) continue;
      final period = _periodForDate(effectDate, closures);
      final end = period.$2;
      final cargo =
          PolicyEffectDate.configuredMonth(effectDate, closures) ?? end;
      final key = _periodKey(cargo.year, cargo.month);
      final group = grouped.putIfAbsent(
        key,
        () => {
          'mes': cargo.month,
          'anio': cargo.year,
          'usuario_auth_id': authId,
          'usuario_nombre':
              (_text(profile['nombre']) + ' ' + _text(profile['apellidos']))
                  .trim(),
          'usuario_email': _text(profile['email']),
          'usuario_rol': role,
          'comisiones': 0.0,
          'rappel': 0.0,
          'rappel_base': 0.0,
          'diferencial_variable': 0.0,
          'fijo': 0.0,
          'base_imponible': 0.0,
          'irpf_porcentaje': 15.0,
          'importe_irpf': 0.0,
          'total_factura': 0.0,
          'estado': 'pendiente_tramitar',
          'factura_url': null,
          '_virtual': true,
          '_prima_neta_total': 0.0,
          '_primas_dv': 0.0,
          '_condicion_aplicada': _roleCondition(role),
          '_draft_lines': <Map<String, dynamic>>[],
        },
      );

      final premium = PremiumWeighting.net(sale);
      group['_prima_neta_total'] = _money(group['_prima_neta_total']) + premium;
      if (_isLifeOrFuneral(sale['producto'])) {
        group['_primas_dv'] = _money(group['_primas_dv']) + premium;
      }

      final ownSale = _text(sale['agente_auth_id']) == authId;
      if (ownSale) {
        group['comisiones'] =
            _money(group['comisiones']) + _money(sale['comision']);
      }

      (group['_draft_lines'] as List<Map<String, dynamic>>).add({
        'numero_poliza':
            sale['numero_poliza'] ??
            sale['poliza'] ??
            sale['numero'] ??
            'Sin póliza',
        'cliente_nombre':
            sale['cliente_nombre'] ??
            sale['nombre_cliente'] ??
            sale['cliente'] ??
            'Sin cliente',
        'prima_neta': premium,
        'comision': ownSale ? _money(sale['comision']) : 0.0,
        'tipo_movimiento': 'VENTA',
      });
    }

    for (final group in grouped.values) {
      final premium = _money(
        group['_prima_neta_total'],
      ).clamp(0, double.infinity).toDouble();
      final life = _money(
        group['_primas_dv'],
      ).clamp(0, double.infinity).toDouble();
      final commissions = _money(group['comisiones']);
      final compensation = RoleCompensationRules.calculate(
        role: role,
        premiums: premium,
        deathAndLifePremiums: life,
      );
      group['rappel'] = compensation.total;
      group['rappel_base'] = compensation.rappel;
      group['diferencial_variable'] = compensation.variable;
      group['fijo'] = 0.0;
      final base = commissions + compensation.total;
      final withholding = base * 0.15;
      group['base_imponible'] = base;
      group['importe_irpf'] = withholding;
      group['total_factura'] = base - withholding;
    }

    return grouped.values
        .where(
          (invoice) =>
              _money(invoice['_prima_neta_total']).abs() > .001 ||
              _money(invoice['base_imponible']).abs() > .001,
        )
        .toList();
  }

  String _periodKey(dynamic year, dynamic month) =>
      _integer(year).toString() +
      '-' +
      _integer(month).toString().padLeft(2, '0');

  String _normaliseRole(dynamic value) =>
      _text(value).toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');

  int _roleLevel(dynamic value) {
    switch (_normaliseRole(value)) {
      case 'director_nacional':
        return 5;
      case 'director_regional':
        return 5;
      case 'director_zona':
        return 4;
      case 'jefe_ventas':
        return 3;
      case 'jefe_equipo':
        return 2;
      case 'agente':
        return 1;
      default:
        return 0;
    }
  }

  List<Map<String, dynamic>> _validStructure(
    Map<String, dynamic> profile,
    List<Map<String, dynamic>> users,
  ) {
    final role = _normaliseRole(profile['rol_usuario']);
    if (role == 'administracion') return [profile];

    final result = <Map<String, dynamic>>[profile];
    final visited = <String>{_text(profile['id'])};
    final queue = <Map<String, dynamic>>[profile];

    while (queue.isNotEmpty) {
      final parent = queue.removeAt(0);
      final parentId = _text(parent['id']);
      final parentLevel = _roleLevel(parent['rol_usuario']);
      for (final user in users) {
        if (_text(user['parent_id']) != parentId) continue;
        final id = _text(user['id']);
        final childLevel = _roleLevel(user['rol_usuario']);
        if (id.isEmpty ||
            visited.contains(id) ||
            childLevel <= 0 ||
            childLevel >= parentLevel) {
          continue;
        }
        visited.add(id);
        result.add(user);
        queue.add(user);
      }
    }
    return result;
  }

  DateTime? _effectDate(Map<String, dynamic> sale) =>
      PolicyEffectDate.read(sale);

  (DateTime, DateTime) _periodForDate(
    DateTime date,
    List<Map<String, dynamic>> closures,
  ) {
    final cleanDate = DateTime(date.year, date.month, date.day);
    for (final closure in closures) {
      final startValue = DateTime.tryParse(_text(closure['fecha_desde']));
      final endValue = DateTime.tryParse(_text(closure['fecha_hasta']));
      if (startValue == null || endValue == null) continue;
      final start = DateTime(startValue.year, startValue.month, startValue.day);
      final end = DateTime(endValue.year, endValue.month, endValue.day);
      if (!cleanDate.isBefore(start) && !cleanDate.isAfter(end)) {
        return (start, end.add(const Duration(days: 1)));
      }
    }

    final start = date.day >= 24
        ? DateTime(date.year, date.month, 24)
        : DateTime(date.year, date.month - 1, 24);
    return (start, DateTime(start.year, start.month + 1, 24));
  }

  bool _isLifeOrFuneral(dynamic value) {
    final product = _text(value).toLowerCase();
    return product.contains('decesos') ||
        product.contains('vida') ||
        product.contains('prima unica') ||
        product.contains('prima única');
  }

  String _roleCondition(String role) =>
      RoleCompensationRules.conditionForRole(role);

  List<Map<String, dynamic>> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    return _invoices.where((invoice) {
      final status = _text(invoice['estado']);
      final year = _integer(invoice['anio']);
      final month = _integer(invoice['mes']);
      final searchable = [
        _text(invoice['numero_factura']),
        month > 0 && month < _months.length ? _months[month] : '',
        year.toString(),
        _statusLabel(status),
      ].join(' ').toLowerCase();

      if (_statusFilter == 'emitidas' && !_isAvailable(invoice)) return false;
      if (_statusFilter == 'preparacion' && _isAvailable(invoice)) return false;
      if (_yearFilter != null && year != _yearFilter) return false;
      return query.isEmpty || searchable.contains(query);
    }).toList();
  }

  List<int> get _years {
    final years =
        _invoices
            .map((invoice) => _integer(invoice['anio']))
            .where((year) => year > 0)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return years;
  }

  double get _availableTotal => _invoices
      .where(_isAvailable)
      .fold(0, (sum, invoice) => sum + _money(invoice['total_factura']));

  int get _availableCount => _invoices.where(_isAvailable).length;

  String _text(dynamic value) => value?.toString().trim() ?? '';

  int _integer(dynamic value) =>
      value is int ? value : int.tryParse(_text(value)) ?? 0;

  double _money(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(_text(value)) ?? 0;

  bool _isAvailable(Map<String, dynamic> invoice) =>
      _text(invoice['factura_url']).isNotEmpty &&
      (_text(invoice['estado']) == 'tramitada' ||
          _text(invoice['estado']) == 'enviada_email');

  String _monthName(dynamic value) {
    final month = _integer(value);
    return month > 0 && month < _months.length ? _months[month] : 'Sin mes';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'enviada_email':
        return 'Emitida';
      case 'tramitada':
        return 'Emitida';
      case 'pendiente_tramitar':
        return 'En preparación';
      default:
        return status.isEmpty ? 'En preparación' : status.replaceAll('_', ' ');
    }
  }

  Future<String> _freshPdfUrl(Map<String, dynamic> invoice) async {
    final savedUrl = _text(invoice['factura_url']);
    if (savedUrl.isEmpty) throw Exception('Esta factura todavía no tiene PDF.');

    try {
      final uri = Uri.parse(savedUrl);
      const signedMarker = '/storage/v1/object/sign/facturas/';
      const publicMarker = '/storage/v1/object/public/facturas/';
      String? path;
      if (uri.path.contains(signedMarker)) {
        path = Uri.decodeComponent(uri.path.split(signedMarker).last);
      } else if (uri.path.contains(publicMarker)) {
        path = Uri.decodeComponent(uri.path.split(publicMarker).last);
      }
      if (path != null && path.isNotEmpty) {
        return await _supabase.storage
            .from('facturas')
            .createSignedUrl(path, 3600);
      }
    } catch (error) {
      debugPrint('No se pudo renovar URL factura: $error');
    }
    return savedUrl;
  }

  Future<void> _openInvoiceDocument(Map<String, dynamic> invoice) async {
    if (_isAvailable(invoice)) {
      await _openPdf(invoice);
    } else {
      await _openDraftPdf(invoice);
    }
  }

  Future<void> _openDraftPdf(Map<String, dynamic> invoice) async {
    if (_openingPdf) return;
    setState(() => _openingPdf = true);
    try {
      final lines = <Map<String, dynamic>>[];
      final cachedLines = invoice['_draft_lines'];

      if (cachedLines is List) {
        for (final item in cachedLines) {
          if (item is Map) {
            lines.add(
              item.map((key, value) => MapEntry(key.toString(), value)),
            );
          }
        }
      } else {
        final invoiceId = _text(invoice['id']);
        if (invoiceId.isNotEmpty) {
          final data = await _supabase
              .from('nominas_facturas_lineas')
              .select()
              .eq('factura_id', invoiceId)
              .order('created_at', ascending: true);
          for (final item in data as List) {
            if (item is Map) {
              lines.add(
                item.map((key, value) => MapEntry(key.toString(), value)),
              );
            }
          }
        }
      }

      final safeInvoice = invoice.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final bytes = await _buildDraftPdf(safeInvoice, lines);
      final name =
          'Factura_en_preparacion_' +
          _integer(invoice['mes']).toString().padLeft(2, '0') +
          '_' +
          _integer(invoice['anio']).toString() +
          '.pdf';

      final opened = await Printing.layoutPdf(
        name: name,
        onLayout: (_) => Future<Uint8List>.value(bytes),
      );
      if (!opened) {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
    } catch (error, stack) {
      debugPrint('ERROR PDF PROVISIONAL: $error');
      debugPrint('$stack');
      if (!mounted) return;
      _message(
        'No se ha podido abrir el PDF provisional. Inténtalo de nuevo.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _openingPdf = false);
    }
  }

  Future<Uint8List> _buildDraftPdf(
    Map<String, dynamic> invoice,
    List<Map<String, dynamic>> lines,
  ) async {
    final document = pw.Document();
    final month = _monthName(invoice['mes']);
    final year = _integer(invoice['anio']).toString();
    final irpf = _money(invoice['irpf_porcentaje']);
    final total = _money(invoice['total_factura']);

    String euros(dynamic value) => _money(value).toStringAsFixed(2) + ' EUR';

    pw.Widget infoLine(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 88,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  color: PdfColors.blueGrey500,
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: const pw.TextStyle(
                  color: PdfColors.blueGrey900,
                  fontSize: 8.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget totalLine(String label, dynamic value, {bool strong = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: strong ? 11 : 9,
                  fontWeight: strong
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  color: PdfColors.blueGrey800,
                ),
              ),
            ),
            pw.Text(
              euros(value),
              style: pw.TextStyle(
                fontSize: strong ? 12 : 9,
                fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: strong ? PdfColors.blue700 : PdfColors.blueGrey900,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget tableCell(String value, {bool header = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: pw.Text(
          value,
          maxLines: 2,
          style: pw.TextStyle(
            color: header ? PdfColors.white : PdfColors.blueGrey800,
            fontSize: header ? 8.5 : 8,
            fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(34),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.blueGrey100),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'SAFEBROK',
                style: pw.TextStyle(
                  color: PdfColors.blue800,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'VISTA PROVISIONAL',
                style: pw.TextStyle(
                  color: PdfColors.orange700,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Pagina ' +
                context.pageNumber.toString() +
                ' de ' +
                context.pagesCount.toString(),
            style: const pw.TextStyle(
              color: PdfColors.blueGrey400,
              fontSize: 8,
            ),
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 20),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey900,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'FACTURA EN PREPARACION',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  month.toUpperCase() + ' ' + year,
                  style: const pw.TextStyle(
                    color: PdfColors.blueGrey100,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.blue100),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      infoLine('Colaborador', _text(invoice['usuario_nombre'])),
                      infoLine('Email', _text(invoice['usuario_email'])),
                      infoLine('Figura', _text(invoice['usuario_rol'])),
                      infoLine(
                        'Condición',
                        _text(invoice['_condicion_aplicada']),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 18),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      infoLine('Periodo', month + ' ' + year),
                      infoLine('IRPF aplicado', irpf.toStringAsFixed(0) + '%'),
                      infoLine('Estado', 'Pendiente de emision'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Condiciones e importes calculados',
            style: pw.TextStyle(
              color: PdfColors.blueGrey900,
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.blueGrey200),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              children: [
                totalLine('Comisiones', invoice['comisiones']),
                totalLine(
                  'Rappel',
                  invoice['rappel_base'] ?? invoice['rappel'],
                ),
                totalLine(
                  'Diferencial variable',
                  invoice['diferencial_variable'] ?? 0,
                ),
                totalLine('Fijo', invoice['fijo']),
                pw.Divider(color: PdfColors.blueGrey200),
                totalLine('Base imponible', invoice['base_imponible']),
                totalLine(
                  'Retencion IRPF ' + irpf.toStringAsFixed(0) + '%',
                  -_money(invoice['importe_irpf']),
                ),
                pw.Divider(color: PdfColors.blueGrey400),
                totalLine('TOTAL PREVISTO', total, strong: true),
              ],
            ),
          ),
          pw.SizedBox(height: 22),
          pw.Text(
            'Detalle incluido en el calculo',
            style: pw.TextStyle(
              color: PdfColors.blueGrey900,
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 9),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.blueGrey100, width: .6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.5),
              1: pw.FlexColumnWidth(2.8),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue700),
                children: [
                  tableCell('Poliza / movimiento', header: true),
                  tableCell('Cliente', header: true),
                  tableCell('Prima neta', header: true),
                  tableCell('Comision', header: true),
                ],
              ),
              if (lines.isEmpty)
                pw.TableRow(
                  children: [
                    tableCell('Sin detalle'),
                    tableCell('-'),
                    tableCell('-'),
                    tableCell('-'),
                  ],
                )
              else
                ...lines.map((line) {
                  final movement = _text(line['tipo_movimiento']);
                  final policy = _text(line['numero_poliza'] ?? line['poliza']);
                  final title = movement.isEmpty
                      ? policy
                      : movement + ' · ' + policy;
                  return pw.TableRow(
                    children: [
                      tableCell(title),
                      tableCell(
                        _text(line['cliente_nombre'] ?? line['cliente']),
                      ),
                      tableCell(euros(line['prima_neta'])),
                      tableCell(euros(line['comision'])),
                    ],
                  );
                }),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.orange50,
              borderRadius: pw.BorderRadius.circular(7),
              border: pw.Border.all(color: PdfColors.orange100),
            ),
            child: pw.Text(
              'Documento provisional sin validez fiscal. Los importes reflejan '
              'las condiciones registradas para el periodo y pueden variar hasta '
              'que Administracion emita la factura definitiva.',
              style: const pw.TextStyle(
                color: PdfColors.orange900,
                fontSize: 8.5,
                lineSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  Future<void> _openPdf(Map<String, dynamic> invoice) async {
    if (_openingPdf) return;
    setState(() => _openingPdf = true);
    try {
      final url = await _freshPdfUrl(invoice);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('No se ha podido abrir el documento.');
    } catch (error) {
      if (!mounted) return;
      _message(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _openingPdf = false);
    }
  }

  void _message(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xFFB42318)
            : const Color(0xFF15803D),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showDetails(Map<String, dynamic> invoice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InvoiceDetailsSheet(
        invoice: invoice,
        currency: _currency,
        monthName: _monthName(invoice['mes']),
        status: _statusLabel(_text(invoice['estado'])),
        available: _isAvailable(invoice),
        opening: _openingPdf,
        onOpen: () {
          Navigator.pop(context);
          _openInvoiceDocument(invoice);
        },
      ),
    );
  }

  void _showFilters() {
    String temporaryStatus = _statusFilter;
    int? temporaryYear = _yearFilter;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.sizeOf(context).height * .68,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7DEE9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Filtrar facturas',
                  style: TextStyle(
                    color: Color(0xFF071A3A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ESTADO',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in const {
                      'todas': 'Todas',
                      'emitidas': 'Emitidas',
                      'preparacion': 'En preparación',
                    }.entries)
                      ChoiceChip(
                        label: Text(option.value),
                        selected: temporaryStatus == option.key,
                        onSelected: (_) =>
                            setSheetState(() => temporaryStatus = option.key),
                      ),
                  ],
                ),
                if (_years.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Text(
                    'AÑO',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Todos'),
                        selected: temporaryYear == null,
                        onSelected: (_) =>
                            setSheetState(() => temporaryYear = null),
                      ),
                      for (final year in _years)
                        ChoiceChip(
                          label: Text(year.toString()),
                          selected: temporaryYear == year,
                          onSelected: (_) =>
                              setSheetState(() => temporaryYear = year),
                        ),
                    ],
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _statusFilter = temporaryStatus;
                        _yearFilter = temporaryYear;
                      });
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2454D3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Aplicar filtros'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2454D3)),
              )
            : _error != null
            ? _errorState()
            : RefreshIndicator(
                color: const Color(0xFF2454D3),
                onRefresh: () => _loadInvoices(showLoader: false),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _topBar(),
                          const SizedBox(height: 18),
                          _hero(),
                          const SizedBox(height: 18),
                          _searchAndFilter(),
                          const SizedBox(height: 16),
                          _activeFilterRow(),
                          const SizedBox(height: 16),
                        ]),
                      ),
                    ),
                    if (_filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _emptyState(),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 34),
                        sliver: ProgressiveSliverList.separated(
                          itemCount: _filtered.length,
                          resetKey: progressiveRecordKey(_filtered),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, index) =>
                              _invoiceCard(_filtered[index]),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.maybePop(context),
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(Icons.arrow_back_rounded, color: Color(0xFF071A3A)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mis facturas',
                style: TextStyle(
                  color: Color(0xFF071A3A),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Tu archivo económico, siempre disponible',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Actualizar',
          onPressed: () => _loadInvoices(showLoader: false),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF2454D3),
          ),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF13244D), Color(0xFF2454D3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x242454D3),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: -12,
            top: -18,
            child: Icon(
              Icons.receipt_long_rounded,
              size: 128,
              color: Color(0x14FFFFFF),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.folder_copy_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Centro de facturación',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Consulta y descarga tus documentos oficiales.',
                style: TextStyle(color: Color(0xFFD7E2FF), fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _heroStat(_availableCount.toString(), 'disponibles'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _heroStat(
                      _currency.format(_availableTotal),
                      'importe total',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFD7E2FF), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _searchAndFilter() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            style: const TextStyle(
              color: Color(0xFF071A3A),
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar por mes, año o número...',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF2454D3),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: _fieldBorder(),
              enabledBorder: _fieldBorder(),
              focusedBorder: _fieldBorder(
                color: const Color(0xFF2454D3),
                width: 1.6,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 54,
          height: 54,
          child: FilledButton(
            onPressed: _showFilters,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: const Color(0xFF2454D3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune_rounded, color: Colors.white),
                if (_statusFilter != 'todas' || _yearFilter != null)
                  const Positioned(
                    right: -7,
                    top: -7,
                    child: CircleAvatar(
                      radius: 5,
                      backgroundColor: Color(0xFFFFB020),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _fieldBorder({
    Color color = const Color(0xFFDCE5F2),
    double width = 1,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  Widget _activeFilterRow() {
    final hasFilters = _statusFilter != 'todas' || _yearFilter != null;
    return Row(
      children: [
        Text(
          _filtered.length.toString() +
              (_filtered.length == 1 ? ' factura' : ' facturas'),
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (hasFilters)
          TextButton.icon(
            onPressed: () => setState(() {
              _statusFilter = 'todas';
              _yearFilter = null;
            }),
            icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
            label: const Text('Quitar filtros'),
          ),
      ],
    );
  }

  Widget _invoiceCard(Map<String, dynamic> invoice) {
    final available = _isAvailable(invoice);
    final status = _statusLabel(_text(invoice['estado']));
    final month = _monthName(invoice['mes']);
    final year = _integer(invoice['anio']);
    final number = _text(invoice['numero_factura']);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showDetails(invoice),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFDCE5F2)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D0F2B5B),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: available
                          ? const Color(0xFFEAF0FF)
                          : const Color(0xFFFFF4DF),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      available
                          ? Icons.picture_as_pdf_outlined
                          : Icons.hourglass_top_rounded,
                      color: available
                          ? const Color(0xFF2454D3)
                          : const Color(0xFFB7791F),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          month + ' ' + year.toString(),
                          style: const TextStyle(
                            color: Color(0xFF071A3A),
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          number.isEmpty ? 'Pendiente de numeración' : number,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(status, available),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFE7ECF3)),
              const SizedBox(height: 14),
              Row(
                children: [
                  _amountColumn(
                    'Base imponible',
                    _currency.format(_money(invoice['base_imponible'])),
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: const Color(0xFFE7ECF3),
                  ),
                  _amountColumn(
                    'Total factura',
                    _currency.format(_money(invoice['total_factura'])),
                    highlighted: true,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String label, bool available) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: available ? const Color(0xFFE8F7EE) : const Color(0xFFFFF4DF),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: available ? const Color(0xFF15803D) : const Color(0xFF9A6700),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _amountColumn(String label, String value, {bool highlighted = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlighted
                    ? const Color(0xFF2454D3)
                    : const Color(0xFF071A3A),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final filtered =
        _searchController.text.isNotEmpty ||
        _statusFilter != 'todas' ||
        _yearFilter != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 78,
            height: 78,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF0FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              filtered ? Icons.search_off_rounded : Icons.receipt_long_outlined,
              color: const Color(0xFF2454D3),
              size: 36,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            filtered ? 'No hay resultados' : 'Todavía no tienes facturas',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF071A3A),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filtered
                ? 'Prueba otra búsqueda o elimina los filtros aplicados.'
                : 'Cuando Administración tramite una factura aparecerá aquí automáticamente.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (filtered) ...[
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _statusFilter = 'todas';
                  _yearFilter = null;
                });
              },
              child: const Text('Limpiar búsqueda'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEAEA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFFB42318),
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _error ?? 'No hemos podido cargar tus facturas.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF071A3A),
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadInvoices,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final NumberFormat currency;
  final String monthName;
  final String status;
  final bool available;
  final bool opening;
  final VoidCallback onOpen;

  const _InvoiceDetailsSheet({
    required this.invoice,
    required this.currency,
    required this.monthName,
    required this.status,
    required this.available,
    required this.opening,
    required this.onOpen,
  });

  double _money(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  String _text(dynamic value) => value?.toString().trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final year = invoice['anio']?.toString() ?? '';
    final number = _text(invoice['numero_factura']);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F6FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7DEE9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF13244D), Color(0xFF2454D3)],
                  ),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            monthName + ' ' + year,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            number.isEmpty ? 'Pendiente de numeración' : number,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD7E2FF),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Resumen económico',
                style: TextStyle(
                  color: Color(0xFF071A3A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: _cardDecoration(),
                child: Column(
                  children: [
                    _row(
                      'Comisiones',
                      currency.format(_money(invoice['comisiones'])),
                    ),
                    _divider(),
                    _row(
                      'Rappel',
                      currency.format(
                        _money(invoice['rappel_base'] ?? invoice['rappel']),
                      ),
                    ),
                    _divider(),
                    _row(
                      'Diferencial variable',
                      currency.format(_money(invoice['diferencial_variable'])),
                    ),
                    _divider(),
                    _row('Fijo', currency.format(_money(invoice['fijo']))),
                    _divider(),
                    _row(
                      'Base imponible',
                      currency.format(_money(invoice['base_imponible'])),
                    ),
                    _divider(),
                    _row(
                      'IRPF (' +
                          _money(
                            invoice['irpf_porcentaje'],
                          ).toStringAsFixed(0) +
                          '%)',
                      '- ' + currency.format(_money(invoice['importe_irpf'])),
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF0FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _row(
                        'Total factura',
                        currency.format(_money(invoice['total_factura'])),
                        highlighted: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _cardDecoration(),
                child: Row(
                  children: [
                    Icon(
                      available
                          ? Icons.verified_rounded
                          : Icons.schedule_rounded,
                      color: available
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB7791F),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estado del documento',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            status,
                            style: const TextStyle(
                              color: Color(0xFF071A3A),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (!available) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4DF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Vista provisional calculada con las condiciones actuales. '
                    'Administración todavía no ha emitido el documento fiscal definitivo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF805B10),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: opening ? null : onOpen,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2454D3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  icon: opening
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          available
                              ? Icons.download_rounded
                              : Icons.picture_as_pdf_outlined,
                        ),
                  label: Text(
                    available
                        ? 'Consultar o descargar PDF'
                        : 'Ver PDF provisional',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool highlighted = false}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: highlighted
                  ? const Color(0xFF071A3A)
                  : const Color(0xFF64748B),
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: highlighted
                ? const Color(0xFF2454D3)
                : const Color(0xFF071A3A),
            fontSize: highlighted ? 18 : 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 11),
      child: Divider(height: 1, color: Color(0xFFE7ECF3)),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFDCE5F2)),
    );
  }
}
