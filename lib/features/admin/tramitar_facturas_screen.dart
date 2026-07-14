import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

class TramitarFacturasScreen extends StatefulWidget {
  const TramitarFacturasScreen({super.key});

  @override
  State<TramitarFacturasScreen> createState() => _TramitarFacturasScreenState();
}

class _TramitarFacturasScreenState extends State<TramitarFacturasScreen> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  String role = '';
  List<Map<String, dynamic>> lineasFactura = [];
  String estadoFiltro = 'pendiente_tramitar';
  String busqueda = '';
  int? mesFiltro;
  Map<String, dynamic>? facturaSeleccionada;

  Future<void> cargarLineasFactura(Map<String, dynamic> factura) async {
  try {
    final data = await supabase
        .from('nominas_facturas_lineas')
        .select()
        .eq('factura_id', factura['id'])
        .order('created_at', ascending: true);

    setState(() {
      facturaSeleccionada = factura;
      lineasFactura = (data as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  } catch (e) {
    debugPrint('ERROR CARGAR LINEAS FACTURA: $e');

    setState(() {
      facturaSeleccionada = factura;
      lineasFactura = [];
    });
  }
}

  List<Map<String, dynamic>> facturas = [];

  @override
  void initState() {
    super.initState();
    cargarFacturas();
  }

  double _money(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

 bool get esAdmin =>
    role == 'administracion' || role == 'director_nacional';

  String nombreMes(dynamic mes) {
    final m = mes is int ? mes : int.tryParse(mes.toString()) ?? 0;
    const meses = [
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
    if (m < 1 || m > 12) return '';
    return meses[m];
  }

  Future<void> cargarFacturas() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      setState(() => loading = false);
      return;
    }

    try {
      setState(() => loading = true);

      final perfil = await supabase
          .from('usuarios')
          .select('rol_usuario')
          .eq('auth_id', user.id)
          .maybeSingle();

      role = perfil?['rol_usuario']?.toString() ?? '';

      final data = await supabase
          .from('nominas_facturas')
          .select()
          .order('created_at', ascending: false);

      final lista = (data as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      setState(() {
        facturas = lista;
        facturaSeleccionada = lista.isNotEmpty ? lista.first : null;
        loading = false;
      });
    } catch (e) {
      debugPrint('ERROR CARGAR FACTURAS: $e');
      setState(() {
        facturas = [];
        loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filtradas {
    return facturas.where((f) {
      final estado = f['estado']?.toString() ?? '';
      final texto = busqueda.toLowerCase().trim();

      final nombre = f['usuario_nombre']?.toString().toLowerCase() ?? '';
      final email = f['usuario_email']?.toString().toLowerCase() ?? '';
      final rolUsuario = f['usuario_rol']?.toString().toLowerCase() ?? '';

      if (estadoFiltro != 'todas' && estado != estadoFiltro) return false;
      if (mesFiltro != null && f['mes'] != mesFiltro) return false;

      if (texto.isNotEmpty &&
          !nombre.contains(texto) &&
          !email.contains(texto) &&
          !rolUsuario.contains(texto)) {
        return false;
      }

      return true;
    }).toList();
  }

  int get pendientes =>
      facturas.where((f) => f['estado'] == 'pendiente_tramitar').length;

  int get tramitadas =>
      facturas.where((f) => f['estado'] == 'tramitada').length;

  int get enviadas =>
      facturas.where((f) => f['estado'] == 'enviada_email').length;

      double get totalPagado {
  return facturas
      .where((f) =>
          f['estado'] == 'tramitada' || f['estado'] == 'enviada_email')
      .fold(0.0, (s, f) => s + _money(f['total_factura']));
}

  double get importePendiente {
    return facturas
        .where((f) => f['estado'] == 'pendiente_tramitar')
        .fold(0.0, (s, f) => s + _money(f['base_imponible']));
  }

  Future<void> tramitarFactura(Map<String, dynamic> f) async {
  if (!esAdmin) return;

  final user = supabase.auth.currentUser;
  if (user == null) return;

  try {
    final base = _money(f['base_imponible']);
    final comisiones = _money(f['comisiones']);
    final rappel = _money(f['rappel']);
    final fijo = _money(f['fijo']);
    final irpf = _money(f['irpf_porcentaje']) == 0
        ? 15.0
        : _money(f['irpf_porcentaje']);
    final importeIrpf = base * irpf / 100;
final total = base - importeIrpf;

    final numeroFactura =
        'FAC-${f['anio']}-${f['mes'].toString().padLeft(2, '0')}-${DateTime.now().millisecondsSinceEpoch}';

    final lineas = await supabase
        .from('nominas_facturas_lineas')
        .select()
        .eq('factura_id', f['id']);

    final pdfBytes = await _generarPdfFactura(
      factura: f,
      lineas: (lineas as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      numeroFactura: numeroFactura,
      comisiones: comisiones,
      rappel: rappel,
      fijo: fijo,
      base: base,
      irpf: irpf,
      importeIrpf: importeIrpf,
     
      total: total,
    );

    final fileName = '$numeroFactura.pdf';
    final path = 'facturas/${f['anio']}/${f['mes']}/$fileName';

    await supabase.storage.from('facturas').uploadBinary(
          path,
          pdfBytes,
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );

    final signedUrl = await supabase.storage
        .from('facturas')
        .createSignedUrl(path, 60 * 60 * 24 * 365);

    await supabase.from('nominas_facturas').update({
      'estado': 'tramitada',
      'numero_factura': numeroFactura,
      'importe_irpf': importeIrpf,
      
      'total_factura': total,
      'factura_url': signedUrl,
      'tramitada_por': user.id,
      'fecha_tramitacion': DateTime.now().toIso8601String(),
    }).eq('id', f['id']);

    await supabase.functions.invoke(
      'enviar-factura-nomina',
      body: {
        'factura_id': f['id'],
        'email': f['usuario_email'],
        'nombre': f['usuario_nombre'],
        'mes': nombreMes(f['mes']),
        'anio': f['anio'],
        'numero_factura': numeroFactura,
        'pdf_url': signedUrl,
      },
    );

    await supabase.from('nominas_facturas').update({
      'estado': 'enviada_email',
      'fecha_envio_email': DateTime.now().toIso8601String(),
    }).eq('id', f['id']);

    await cargarFacturas();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Factura generada y enviada por email correctamente'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    debugPrint('ERROR TRAMITAR FACTURA: $e');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error generando/enviando factura: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

Future<Uint8List> _generarPdfFactura({
  required Map<String, dynamic> factura,
  required List<Map<String, dynamic>> lineas,
  required String numeroFactura,
  required double comisiones,
  required double rappel,
  required double fijo,
  required double base,
  required double irpf,
  required double importeIrpf,
  required double total,
}) async {
  final pdf = pw.Document();

  String euros(double value) => '${value.toStringAsFixed(2)} EUR';

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(34),
      build: (context) {
        return [
          pw.Container(
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: PdfColors.blueGrey900,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'SAFEBROK',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Documento de facturación',
                      style: const pw.TextStyle(
                        color: PdfColors.blueGrey100,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'FACTURA',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      numeroFactura,
                      style: const pw.TextStyle(
                        color: PdfColors.blueGrey100,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 22),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _pdfInfoBox(
                  title: 'Colaborador',
                  lines: [
                    'Nombre: ${factura['usuario_nombre'] ?? ''}',
                    'Email: ${factura['usuario_email'] ?? ''}',
                    'Rol: ${factura['usuario_rol'] ?? ''}',
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: _pdfInfoBox(
                  title: 'Datos factura',
                  lines: [
                    'Fecha: ${DateTime.now().toString().split(' ').first}',
                    'Periodo: ${nombreMes(factura['mes'])} ${factura['anio']}',
                    'IRPF aplicado: ${irpf.toStringAsFixed(0)}%',
                  ],
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 24),

          pw.Text(
           'Pólizas incluidas y extornos aplicados',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey900,
            ),
          ),

          pw.SizedBox(height: 10),

          pw.Table(
            border: pw.TableBorder.all(
              color: PdfColors.blueGrey100,
              width: 0.6,
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.6),
              1: pw.FlexColumnWidth(3.2),
              2: pw.FlexColumnWidth(1.3),
              3: pw.FlexColumnWidth(1.3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blue700,
                ),
                children: [
                  _pdfHeaderCell('Póliza'),
                  _pdfHeaderCell('Cliente'),
                  _pdfHeaderCell('Prima neta'),
                  _pdfHeaderCell('Comisión'),
                ],
              ),
              if (lineas.isEmpty)
  pw.TableRow(
    children: [
      _pdfCell('Sin detalle'),
      _pdfCell('-'),
      _pdfCell('-'),
      _pdfCell('-'),
    ],
  )
else
  ...lineas.map((l) {
    final numeroPoliza =
        (l['numero_poliza'] ?? l['poliza'] ?? l['numero'] ?? 'Sin póliza')
            .toString();

    final cliente =
        (l['cliente_nombre'] ?? l['cliente'] ?? l['nombre_cliente'] ?? 'Sin cliente')
            .toString();

    final prima = _money(
      l['prima_neta'] ??
          l['prima_anual_neta'] ??
          l['prima'] ??
          l['importe_prima'],
    );

    final comision = _money(
      l['comision'] ??
          l['importe_comision'] ??
          l['comision_total'] ??
          0,
    );

   final tipo = l['tipo_movimiento']?.toString() ?? 'VENTA';
final esExtorno = tipo == 'EXTORNO';

return pw.TableRow(
  decoration: esExtorno
      ? const pw.BoxDecoration(color: PdfColors.red50)
      : null,
  children: [
    _pdfCell(esExtorno ? 'EXTORNO · $numeroPoliza' : numeroPoliza),
    _pdfCell(cliente),
    _pdfCell(euros(prima), alignRight: true),
    _pdfCell(euros(comision), alignRight: true),
  ],
);
  }),
            ],
          ),

          pw.SizedBox(height: 26),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blueGrey50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'Factura generada automáticamente desde el sistema interno de gestión. '
                    'El detalle anterior recoge las pólizas incluidas en el periodo facturado.',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.blueGrey600,
                      lineSpacing: 2,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 18),
              pw.Container(
                width: 260,
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blueGrey200),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  children: [
                    _pdfTotalLine('Comisiones', comisiones),
                    _pdfTotalLine('Rappel', rappel),
                    _pdfTotalLine('Fijo', fijo),
                    pw.Divider(color: PdfColors.blueGrey200),
                    _pdfTotalLine('Base imponible', base),
                    _pdfTotalLine(
                      'IRPF ${irpf.toStringAsFixed(0)}%',
                      -importeIrpf,
                    ),
                    pw.Divider(color: PdfColors.blueGrey400),
                    _pdfTotalLine(
                      'TOTAL A PERCIBIR',
                      total,
                      bold: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ];
      },
    ),
  );

  return pdf.save();
}

pw.Widget _pdfInfoBox({
  required String title,
  required List<String> lines,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(13),
    decoration: pw.BoxDecoration(
      color: PdfColors.blue50,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: PdfColors.blue100),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 11,
            color: PdfColors.blueGrey900,
          ),
        ),
        pw.SizedBox(height: 8),
        ...lines.map(
          (line) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              line,
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.blueGrey700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _pdfHeaderCell(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
      ),
    ),
  );
}

pw.Widget _pdfCell(String text, {bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      maxLines: 2,
      style: const pw.TextStyle(
        fontSize: 8.5,
        color: PdfColors.blueGrey800,
      ),
    ),
  );
}

pw.Widget _pdfTotalLine(String title, double value, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 7),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 9.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: bold ? PdfColors.blueGrey900 : PdfColors.blueGrey700,
            ),
          ),
        ),
        pw.Text(
          '${value.toStringAsFixed(2)} EUR',
          style: pw.TextStyle(
            fontSize: bold ? 12 : 9.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: bold ? PdfColors.blue700 : PdfColors.blueGrey900,
          ),
        ),
      ],
    ),
  );
}


 Future<void> cambiarIrpf(Map<String, dynamic> f, double irpf) async {
  final base = _money(f['base_imponible']);
  final rappel = _money(f['rappel']);

  await supabase.from('nominas_facturas').update({
    'irpf_porcentaje': irpf,
    'importe_irpf': base * irpf / 100,
    'total_factura': base - (base * irpf / 100),
  }).eq('id', f['id']);

  await cargarFacturas();
}

  @override
  Widget build(BuildContext context) {
    final lista = filtradas;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FD),
      body: SafeArea(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2563EB)),
              )
            : Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topBar(),
        const SizedBox(height: 22),
        _kpiRow(),
        const SizedBox(height: 18),
        _filters(),
        const SizedBox(height: 18),
       Expanded(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 280,
        child: _colaTrabajoPanel(),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: _tablaFacturas(lista),
      ),
      const SizedBox(width: 16),
      SizedBox(
        width: 320,
        child: _detalleFactura(),
      ),
    ],
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
        InkWell(
          onTap: () => Navigator.pop(context),
          child: const Row(
            children: [
              Icon(Icons.chevron_left_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 4),
              Text(
                'CUADRO DE MANDOS',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        _topChip(Icons.calendar_month_rounded, 'Mes actual'),
        const SizedBox(width: 14),
        _topChip(Icons.person_rounded, role.isEmpty ? 'Usuario' : role),
      ],
    );
  }

  Widget _topChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tramitar facturas',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Centro de expedición y control de facturación',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            _kpiCard('Pendientes', pendientes.toString(), 'Por tramitar',
                Icons.pending_actions_rounded, const Color(0xFF2563EB)),
            _kpiCard('Tramitadas', tramitadas.toString(), 'Este mes',
                Icons.verified_rounded, const Color(0xFF16A34A)),
            _kpiCard(
                'Importe pendiente',
                '${importePendiente.toStringAsFixed(0)} EUR',
                'Base imponible',
                Icons.euro_rounded,
                const Color(0xFF7C3AED)),
           _kpiCard(
  'Total pagado',
  '${totalPagado.toStringAsFixed(0)} EUR',
  'Facturas tramitadas',
  Icons.account_balance_wallet_rounded,
  const Color(0xFF0284C7),
),
            _kpiCard('IRPF más usado', '15%', 'Este mes',
                Icons.percent_rounded, const Color(0xFFEF4444)),
          ],
        ),
      ],
    );
  }

  Widget _kpiCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.blueGrey.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  onChanged: (v) => setState(() => busqueda = v),
                  decoration: _inputDecoration(
                    'Buscar por nombre, email o factura...',
                    Icons.search_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: estadoFiltro,
                  decoration: _selectDecoration('Estado'),
                  items: const [
                    DropdownMenuItem(
                      value: 'pendiente_tramitar',
                      child: Text('Pendientes'),
                    ),
                    DropdownMenuItem(
                      value: 'tramitada',
                      child: Text('Tramitadas'),
                    ),
                    DropdownMenuItem(
                      value: 'enviada_email',
                      child: Text('Enviadas'),
                    ),
                    DropdownMenuItem(
                      value: 'todas',
                      child: Text('Todas'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => estadoFiltro = v ?? 'pendiente_tramitar'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int?>(
                  value: mesFiltro,
                  decoration: _selectDecoration('Mes'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text(nombreMes(i + 1)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => mesFiltro = v),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    estadoFiltro = 'pendiente_tramitar';
                    mesFiltro = null;
                    busqueda = '';
                  });
                },
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: const Text('Limpiar filtros'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }

  InputDecoration _selectDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
    );
  }

  

Widget _colaTrabajoPanel() {
  final pendientesLista = facturas
      .where((f) => f['estado'] == 'pendiente_tramitar')
      .toList();

  final tramitadasLista = facturas
      .where((f) => f['estado'] == 'tramitada')
      .toList();

  return SingleChildScrollView(
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'COLA DE TRABAJO',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              _workQueueStat(
                title: 'Pendientes',
                value: pendientesLista.length.toString(),
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 8),
              _workQueueStat(
                title: 'Tramitadas',
                value: tramitadasLista.length.toString(),
                icon: Icons.verified_rounded,
                color: const Color(0xFF16A34A),
              ),
              const SizedBox(height: 8),
              _workQueueStat(
                title: 'Total pagado',
                value: '${totalPagado.toStringAsFixed(0)} €',
                icon: Icons.account_balance_wallet_rounded,
                color: const Color(0xFF2563EB),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PENDIENTES DE TRAMITAR',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              if (pendientesLista.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 35),
                  child: Center(
                    child: Text(
                      'No hay facturas pendientes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                ...pendientesLista
                    .take(8)
                    .toList()
                    .asMap()
                    .entries
                    .map(
                      (entry) => _workQueueFacturaCard(
                        entry.value,
                        urgente: entry.key <= 1,
                      ),
                    ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _workQueueStat({
  required String title,
  required String value,
  required IconData icon,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: color.withOpacity(0.09),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.16)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _workQueueFacturaCard(
  Map<String, dynamic> f, {
  required bool urgente,
}) {
  final selected = facturaSeleccionada?['id'] == f['id'];
  final base = _money(f['base_imponible']);
  final rappel = _money(f['rappel']);

  return InkWell(
    onTap: () => cargarLineasFactura(f),
    borderRadius: BorderRadius.circular(18),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? const Color(0xFF2563EB)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: urgente
                    ? const Color(0xFFFFEDD5)
                    : const Color(0xFFEFF6FF),
                child: Icon(
                  urgente
                      ? Icons.priority_high_rounded
                      : Icons.receipt_long_rounded,
                  color: urgente
                      ? const Color(0xFFF97316)
                      : const Color(0xFF2563EB),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f['usuario_nombre']?.toString() ?? 'Usuario',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${nombreMes(f['mes'])} ${f['anio']}',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${base.toStringAsFixed(2)} €',
                  style: const TextStyle(
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              if (urgente)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'URGENTE',
                    style: TextStyle(
                      color: Color(0xFFF97316),
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
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

  Widget _treeLine(String text, int count, int level) {
    return Padding(
      padding: EdgeInsets.only(left: level * 16, bottom: 14),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 7, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tablaFacturas(List<Map<String, dynamic>> lista) {
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: _HeaderCell('USUARIO')),
                Expanded(child: _HeaderCell('MES / AÑO')),
                Expanded(child: _HeaderCell('RAPPEL')),
Expanded(child: _HeaderCell('BASE')),
                Expanded(child: _HeaderCell('IRPF')),
                Expanded(child: _HeaderCell('TOTAL')),
                Expanded(child: _HeaderCell('ESTADO')),
                SizedBox(width: 50, child: _HeaderCell('')),
              ],
            ),
          ),
          Expanded(
            child: lista.isEmpty
                ? const Center(
                    child: Text(
                      'No hay facturas con estos filtros',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: lista.length,
                    itemBuilder: (_, i) => _facturaRow(lista[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _facturaRow(Map<String, dynamic> f) {
    final selected = facturaSeleccionada?['id'] == f['id'];
    final estado = f['estado']?.toString() ?? '';
    final color = _estadoColor(estado);

    return InkWell(
      onTap: () => cargarLineasFactura(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.white,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withOpacity(0.14),
                    child: Text(
                      _iniciales(f['usuario_nombre']),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f['usuario_nombre']?.toString() ?? 'Usuario',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          f['usuario_rol']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Text(
                '${nombreMes(f['mes'])}\n${f['anio']}',
                style: const TextStyle(
                  color: Color(0xFF334155),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(child: _bodyText('${_money(f['rappel']).toStringAsFixed(2)} €')),
Expanded(child: _bodyText('${_money(f['base_imponible']).toStringAsFixed(2)} €')),
Expanded(child: _bodyText('${_money(f['irpf_porcentaje']).toStringAsFixed(0)}%')),
            Expanded(child: _bodyText('${_money(f['total_factura']).toStringAsFixed(2)} €')),
            Expanded(child: _estadoBadge(estado)),
            SizedBox(
              width: 50,
              child: IconButton(
                onPressed: () => cargarLineasFactura(f),
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detalleFactura() {
    final f = facturaSeleccionada;

    if (f == null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: _cardDecoration(),
        child: const Center(
          child: Text(
            'Selecciona una factura',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    final comisiones = _money(f['comisiones']);
final rappel = _money(f['rappel']);
final fijo = _money(f['fijo']);
final base = _money(f['base_imponible']);
    final irpf = _money(f['irpf_porcentaje']) == 0
        ? 15.0
        : _money(f['irpf_porcentaje']);
    final importeIrpf = base * irpf / 100;
final total = base - importeIrpf;

    final estado = f['estado']?.toString() ?? '';
    final color = _estadoColor(estado);

    return Container(
  padding: const EdgeInsets.all(20),
  decoration: _cardDecoration(),
  child: SingleChildScrollView(
    child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'DETALLE DE FACTURA',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => facturaSeleccionada = null),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 14),
          CircleAvatar(
            radius: 31,
            backgroundColor: color.withOpacity(0.13),
            child: Text(
              _iniciales(f['usuario_nombre']),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            f['usuario_nombre']?.toString() ?? 'Usuario',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            f['usuario_rol']?.toString() ?? '',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            f['usuario_email']?.toString() ?? '',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          _estadoBadge(estado),
          const SizedBox(height: 22),
          Text(
            '${nombreMes(f['mes']).toUpperCase()} ${f['anio']}',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const Text(
            'Factura pendiente de tramitar',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
  'CONCEPTOS FACTURADOS',
  style: TextStyle(
    color: Color(0xFF0F172A),
    fontWeight: FontWeight.w900,
    fontSize: 12,
  ),
),

const SizedBox(height: 14),

_detailLine(
  'Comisiones',
  comisiones,
  const Color(0xFF2563EB),
),

_detailLine(
  'Rappel',
  rappel,
  const Color(0xFF7C3AED),
),

_detailLine(
  'Fijo',
  fijo,
  const Color(0xFF16A34A),
),

const Divider(height: 28),

_detailLine(
  'BASE IMPONIBLE',
  base,
  const Color(0xFF0F172A),
),

_detailLine(
  'IRPF (${irpf.toStringAsFixed(0)}%)',
  -importeIrpf,
  Colors.red,
),

const Divider(height: 28),

_detailLine(
  'TOTAL FACTURA',
  total,
  const Color(0xFF2563EB),
  big: true,
),
          
          const Divider(height: 28),
          _detailLine('TOTAL FACTURA', total, const Color(0xFF2563EB), big: true),
          const SizedBox(height: 20),

const Text(
  'DETALLE DE PÓLIZAS Y EXTORNOS',
  style: TextStyle(
    color: Color(0xFF0F172A),
    fontWeight: FontWeight.w900,
    fontSize: 12,
  ),
),

const SizedBox(height: 10),

if (lineasFactura.isEmpty)
  const Text(
    'No hay líneas cargadas para esta factura.',
    style: TextStyle(
      color: Color(0xFF64748B),
      fontWeight: FontWeight.w600,
    ),
  )
else
  ...lineasFactura.map((l) {
    final tipo = l['tipo_movimiento']?.toString() ?? 'VENTA';
    final esExtorno = tipo == 'EXTORNO';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: esExtorno
            ? const Color(0xFFFFF1F2)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: esExtorno
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  esExtorno
                      ? 'EXTORNO · ${l['numero_poliza'] ?? 'Sin póliza'}'
                      : 'VENTA · ${l['numero_poliza'] ?? 'Sin póliza'}',
                  style: TextStyle(
                    color: esExtorno
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '${_money(l['comision']).toStringAsFixed(2)} €',
                style: TextStyle(
                  color: esExtorno
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l['cliente_nombre']?.toString() ?? 'Sin cliente',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Prima: ${_money(l['prima_neta']).toStringAsFixed(2)} €',
            style: TextStyle(
              color: esExtorno
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }),
          const SizedBox(height: 22),
          const Text(
            'CONFIGURACIÓN FISCAL',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _irpfButton(f, 7, irpf == 7)),
              const SizedBox(width: 10),
              Expanded(child: _irpfButton(f, 15, irpf == 15)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            maxLines: 3,
            decoration: _inputDecoration('Añade una observación...', Icons.edit_note),
          ),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: estado == 'pendiente_tramitar' && esAdmin
                  ? () => tramitarFactura(f)
                  : null,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Tramitar factura'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: f == null
    ? null
    : () async {
    final base = _money(f['base_imponible']);
    final rappel = _money(f['rappel']);
    final irpf = _money(f['irpf_porcentaje']) == 0
        ? 15.0
        : _money(f['irpf_porcentaje']);

    final importeIrpf = base * irpf / 100;
    final total = base - importeIrpf;

       final comisiones = _money(f['comisiones']);

final fijo = _money(f['fijo']);

final lineasPreview = await supabase
    .from('nominas_facturas_lineas')
    .select()
    .eq('factura_id', f['id'])
    .order('created_at', ascending: true);

final lineasPdf = (lineasPreview as List)
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

final bytes = await _generarPdfFactura(
  factura: f,
  lineas: lineasPdf,
  numeroFactura: f['numero_factura']?.toString() ?? 'BORRADOR',
  comisiones: comisiones,
  rappel: rappel,
  fijo: fijo,
  base: base,
  irpf: irpf,
  importeIrpf: importeIrpf,
  total: total,
);

        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
        );
      },
              icon: const Icon(Icons.remove_red_eye_rounded),
              label: const Text('Vista previa PDF'),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _irpfButton(Map<String, dynamic> f, double value, bool selected) {
    return OutlinedButton(
      onPressed: esAdmin ? () => cambiarIrpf(f, value) : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? const Color(0xFF2563EB) : Colors.white,
        foregroundColor: selected ? Colors.white : const Color(0xFF0F172A),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text('${value.toStringAsFixed(0)}%'),
    );
  }

  Widget _detailLine(String title, double value, Color color, {bool big = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: const Color(0xFF64748B),
                fontWeight: big ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} €',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: big ? 19 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }

  Widget _estadoBadge(String estado) {
    final color = _estadoColor(estado);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }

  Color _estadoColor(String estado) {
    if (estado == 'tramitada') return const Color(0xFF16A34A);
    if (estado == 'enviada_email') return const Color(0xFF2563EB);
    if (estado == 'error_email') return const Color(0xFFDC2626);
    return const Color(0xFFF59E0B);
  }

  String _iniciales(dynamic nombre) {
    final text = nombre?.toString().trim() ?? '';
    if (text.isEmpty) return 'US';

    final partes = text.split(' ');
    if (partes.length == 1) {
      return partes.first.substring(0, partes.first.length >= 2 ? 2 : 1).toUpperCase();
    }

    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.blueGrey.withOpacity(0.06),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontWeight: FontWeight.w900,
        fontSize: 11,
      ),
    );
  }
}