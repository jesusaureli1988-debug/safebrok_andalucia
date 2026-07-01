import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';


class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() =>
      _AdminPanelScreenState();
}

class _AdminPanelScreenState
    extends State<AdminPanelScreen> {

    @override
void initState() {
  super.initState();
  inicializarPermisosERP();
}

double produccionTotal = 0;
int ventasTotales = 0;

Map<String, dynamic>? usuarioActualERP;
List<String> authIdsPermitidosERP = [];
bool cargandoPermisosERP = true;
bool accesoAdminPanelERP = false;

double recibosCobrados = 0;
double recibosDevueltos = 0;

double produccionVsMesAnterior = 0;
double ventasVsMesAnterior = 0;
double cobradosVsMesAnterior = 0;
double devueltosVsMesAnterior = 0;

    final TextEditingController polizaCtrl = TextEditingController();
final TextEditingController clienteCtrl = TextEditingController();
final TextEditingController importeCtrl = TextEditingController();
final TextEditingController companiaCtrl = TextEditingController();
final TextEditingController estadoCtrl = TextEditingController();
final TextEditingController fechaCtrl = TextEditingController();

int importProgress = 0;
int importTotal = 0;


    List<List<dynamic>> excelPreview = [];

List<String> headers = [];
List<List<dynamic>> dataRows = [];

List<Map<String, dynamic>> recibos = [];
bool loadingRecibos = false;

Map<String, String> columnMapping = {};

List<String> polizasHeaders = [];
List<List<dynamic>> polizasRows = [];
List<List<dynamic>> polizasPreview = [];

Map<String, String> polizasColumnMapping = {};

int polizasImportProgress = 0;
int polizasImportTotal = 0;
bool importingPolizas = false;

final List<String> camposCargaPolizas = [
  "cliente.nombre",
  "cliente.apellidos",
  "cliente.telefono",
  "cliente.email",
  "cliente.codigo_postal",
  "cliente.provincia",
  "cliente.poblacion",
  "cliente.direccion",
  "cliente.numero",
  "cliente.dni",

  "venta.agente_auth_id",
  "venta.agente_nombre",
"venta.agente_apellidos",
"venta.agente_nombre_completo",
  "venta.producto",
  "venta.compania",
  "venta.forma_pago",
  "venta.precio",
  "venta.numero_asegurados",
  "venta.fecha_efecto",
  "venta.prima_anual",
  "venta.categoria_producto",
  "venta.prima_anual_bruta",
  "venta.comision",
  "venta.numero_poliza",
  "venta.estado_poliza",
];

bool isImporting = false;
double progress = 0;

Map<String, String> autoMap = {
  "poliza": "poliza",
  "nº poliza": "poliza",
  "numero poliza": "poliza",
  "cliente": "cliente",
  "tomador": "cliente",
  "importe": "importe",
  "total": "importe",
  "compania": "compania",
  "compañia": "compania",
  "estado": "estado",
  "fecha": "fecha",
};

String tipoReciboSeleccionado = "all";

String? filtroCompania;
String? filtroAgente;
String? filtroEstado;
String? filtroJefeEquipo;

DateTime? fechaDesde;
DateTime? fechaHasta;

List<String> listaAgentes = [];
List<String> listaJefes = [];
List<String> listaCompanias = [];

String? filtroVentaCompania;
String? filtroVentaCategoria;

DateTime? ventaFechaDesde;
DateTime? ventaFechaHasta;

List<String> listaVentaCompanias = [];
List<String> listaVentaCategorias = [];

String? filtroVentaAgente;
String? filtroVentaJefe;

List<String> listaVentaAgentes = [];
List<String> listaVentaJefes = [];

    String modoCarga = '';
  String selectedMenu = "dashboard";

  Future<void> seleccionarExcel() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls'],
  );

  if (result == null) return;

  final bytes = result.files.first.bytes;
  if (bytes == null) return;

  final archivoExcel = excel.Excel.decodeBytes(bytes);

  final sheet = archivoExcel.tables.values.first;
  final rows = sheet.rows;

  if (rows.isEmpty) return;

  // 1. CABECERAS
 headers = rows.first
    .map((e) => e?.value.toString().trim().toUpperCase() ?? '')
    .toList();
      autoDetectMapping();

  // 2. DATOS
  dataRows = rows
      .skip(1)
      .take(200)
      .map((row) {
        return row.map((e) => e?.value ?? '').toList();
      }).toList();

  // 3. PREVIEW (para tabla visual)
  excelPreview = [headers, ...dataRows];

  setState(() {});
}

Future<void> importarASupabase() async {
  print("🚀 INICIO IMPORTACIÓN");
  print("ROWS TOTALES: ${dataRows.length}");
  print("HEADERS: $headers");
  print("MAPEO: $columnMapping");

  for (final h in headers) {
  print("HEADER RAW => [$h]");
  print("MAP RESULT => ${columnMapping[h]}");
}

  setState(() {
  isImporting = true;
  progress = 0;
});

  final supabase = Supabase.instance.client;

  final data = dataRows.map((row) {
    Map<String, dynamic> item = {};

    for (int i = 0; i < headers.length; i++) {
     final header = headers[i].trim().toUpperCase();
final mapped = columnMapping[header];

     if (i < row.length) {
  final mapped = columnMapping[header];

 if (mapped != null && i < row.length) {
  final rawValue = row[i];
  final value = cleanExcelValue(rawValue);

  if (value == null) continue;

  if (value is String ||
      value is num ||
      value is bool ||
      value is DateTime) {
    item[mapped] = value;
  } else {
    item[mapped] = value.toString();
  }
}
}
    }

    return item;
  }).toList();

  data.removeWhere((row) => row.isEmpty);

  print("📦 DATA FINAL:");
  print(data.take(3).toList()); // solo primeras 3 filas
  print("TOTAL A INSERTAR: ${data.length}");


  try {
    const batchSize = 200;

for (int i = 0; i < data.length; i += batchSize) {
  final batch = data.sublist(
    i,
    i + batchSize > data.length ? data.length : i + batchSize,
  );

  await supabase
      .from('recibos')
      .upsert(batch, onConflict: 'poliza');

  setState(() {
    progress = (i + batch.length) / data.length;
  });

  print("✔ Importado: ${i + batch.length}/${data.length}");
}

    print("✅ INSERT OK");
    print("✅ IMPORTACIÓN FINALIZADA");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Importados ${data.length} recibos"),
      ),
    );
  } catch (e) {
  setState(() {
  isImporting = false;
});
    print("❌ ERROR SUPABASE:");
    print(e);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Error al importar"),
      ),
    );
  }
  setState(() {
  isImporting = false;
  progress = 1;
});
}

Future<void> insertarManual() async {
  print("🚀 INSERT MANUAL INICIADO");

  final supabase = Supabase.instance.client;

  final data = {
    'poliza': polizaCtrl.text,
    'cliente': clienteCtrl.text,
    'importe': double.tryParse(importeCtrl.text) ?? 0,
    'compania': companiaCtrl.text,
    'estado': estadoCtrl.text,
    'fecha': convertirFecha(fechaCtrl.text),
  };

  print("📦 DATA A INSERTAR:");
  print(data);

  try {
    final response = await supabase
        .from('recibos')
        .insert(data)
        .select();

    print("✅ INSERT OK:");
    print(response);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Recibo guardado correctamente")),
    );

  } catch (e) {
    print("❌ ERROR INSERT MANUAL:");
    print(e);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error: $e")),
    );
  }
}

String convertirFecha(String input) {
  try {
    final parts = input.split('/');

    if (parts.length == 3) {
      final day = parts[0];
      final month = parts[1];
      final year = parts[2];

      return "$year-$month-$day";
    }

    return input;
  } catch (e) {
    return input;
  }
}

Future<void> exportarExcel(
    List<Map<String, dynamic>> recibos,
) async {

print("RECIBOS RECIBIDOS: ${recibos.length}");

  final excelFile = excel.Excel.createExcel();

  final sheet = excelFile['Recibos'];

  sheet.appendRow([
    excel.TextCellValue('Fecha'),
    excel.TextCellValue('Compañía'),
    excel.TextCellValue('Póliza'),
    excel.TextCellValue('Cliente'),
    excel.TextCellValue('Agente'),
    excel.TextCellValue('Importe'),
    excel.TextCellValue('Estado'),
  ]);

  for (final r in recibos) {
    sheet.appendRow([
  excel.TextCellValue(r['fecha']?.toString() ?? ''),
  excel.TextCellValue(r['compania']?.toString() ?? ''),
  excel.TextCellValue(r['poliza']?.toString() ?? ''),
  excel.TextCellValue(r['cliente']?.toString() ?? ''),
  excel.TextCellValue(r['agente']?.toString() ?? ''),
  excel.TextCellValue(r['importe']?.toString() ?? ''),
  excel.TextCellValue(r['estado']?.toString() ?? ''),
]);
  }
  print("FILAS EXCEL: ${sheet.maxRows}");
  final bytes = excelFile.save();
  excelFile.setDefaultSheet('Recibos');
  print("BYTES EXCEL: ${bytes?.length}");

  if (bytes == null) return;

  final dir = await getApplicationDocumentsDirectory();

final file = File('${dir.path}/recibos.xlsx');

await file.writeAsBytes(bytes, flush: true);

await OpenFilex.open(file.path);
}
Future<void> importarMasivoASupabase() async {
  final supabase = Supabase.instance.client;

  setState(() {
    isImporting = true;
    importProgress = 0;
    importTotal = dataRows.length;
  });

  print("🚀 INICIO IMPORTACIÓN MASIVA");
  print("TOTAL FILAS: $importTotal");

  try {
    // 🧱 DIVIDIR EN BLOQUES
    const int batchSize = 200;

    for (int i = 0; i < dataRows.length; i += batchSize) {
      final batch = dataRows.skip(i).take(batchSize).toList();

      final data = batch.map((row) {
        Map<String, dynamic> item = {};

        for (int j = 0; j < headers.length; j++) {
          final header = headers[j].trim().toUpperCase();
          final mapped = columnMapping[header];

          if (mapped != null && j < row.length) {
            final value = cleanExcelValue(row[j]);

            if (value == null) continue;

            item[mapped] = value.toString();
          }
        }

        return item;
      }).toList();

      await supabase.from('recibos').insert(data);

      setState(() {
        importProgress += batch.length;
      });

      print("✔ Lote importado: ${importProgress}/${importTotal}");
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("IMPORTACIÓN COMPLETA: $importTotal recibos"),
      ),
    );

  } catch (e) {
    print("❌ ERROR IMPORTACIÓN MASIVA:");
    print(e);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Error en importación masiva"),
      ),
    );
  }

  setState(() {
    isImporting = false;
  });
}
Future<void> cargarRecibos() async {
  setState(() {
    loadingRecibos = true;
  });

  try {
    final data = await getRecibos(selectedMenu);

    setState(() {
      recibos = data;
      loadingRecibos = false;
    });

    print("📦 RECIBOS CARGADOS: ${recibos.length}");
  } catch (e) {
    setState(() {
      loadingRecibos = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Error al cargar recibos: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }
}
Future<List<Map<String, dynamic>>> _getRecibos() async {
  return await getRecibos(selectedMenu);
}
dynamic cleanExcelValue(dynamic value) {
  if (value == null) return null;

  // 🧠 SI YA ES STRING / NUMERO
  if (value is String || value is num || value is bool) {
    return value;
  }

  // 🧠 EXCEL TYPES
  try {
    final type = value.runtimeType.toString();

    if (type.contains('IntCellValue')) {
      return value.value;
    }

    if (type.contains('DoubleCellValue')) {
      return value.value;
    }

    if (type.contains('TextCellValue')) {
      return value.value;
    }

    // 🚨 CASO PROBLEMÁTICO REAL
   if (type.contains('TextSpan')) {
  try {
    return value.toPlainText();
  } catch (_) {
    return value.toString();
  }
}

  } catch (e) {
    return value.toString();
  }

  // 🧯 FALLBACK TOTAL
  try {
    return value.toString();
  } catch (e) {
    return null;
  }
}
Future<List<Map<String, dynamic>>> getRecibos(String tipo) async {
  final supabase = Supabase.instance.client;

  List<String> polizasPermitidas = [];

  if (!veTodoERP) {
    if (authIdsPermitidosERP.isEmpty) return [];

    final ventasPermitidas = await supabase
        .from('ventas')
        .select('numero_poliza')
        .inFilter('agente_auth_id', authIdsPermitidosERP);

    polizasPermitidas = List<Map<String, dynamic>>.from(ventasPermitidas)
        .map((v) => v['numero_poliza']?.toString() ?? '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    if (polizasPermitidas.isEmpty) return [];
  }

  dynamic query = supabase
      .from('recibos')
      .select();

  if (!veTodoERP) {
    query = query.inFilter('poliza', polizasPermitidas);
  }

  if (tipo == "recibos_cobrados") {
    query = query.eq('estado', 'COBRADO');
  }

  if (tipo == "recibos_devueltos") {
    query = query.eq('estado', 'DEVUELTO');
  }

  if (tipo == "recibos_pendientes") {
    query = query.eq('estado', 'PENDIENTE');
  }

  if (filtroCompania != null &&
      filtroCompania!.isNotEmpty &&
      filtroCompania != "Todas") {
    query = query.eq('compania', filtroCompania!);
  }

  if (filtroAgente != null &&
      filtroAgente!.isNotEmpty &&
      filtroAgente != "Todos") {
    query = query.eq('agente', filtroAgente!);
  }

  if (filtroEstado != null &&
      filtroEstado!.isNotEmpty &&
      filtroEstado != "Todos") {
    query = query.eq('estado', filtroEstado!);
  }

  if (fechaDesde != null) {
    final inicioDia = DateTime(
      fechaDesde!.year,
      fechaDesde!.month,
      fechaDesde!.day,
      0,
      0,
      0,
    );

    query = query.gte(
      'fecha',
      inicioDia.toIso8601String(),
    );
  }

  if (fechaHasta != null) {
    final finDia = DateTime(
      fechaHasta!.year,
      fechaHasta!.month,
      fechaHasta!.day,
      23,
      59,
      59,
    );

    query = query.lte(
      'fecha',
      finDia.toIso8601String(),
    );
  }

  final response = await query.order('fecha', ascending: false);

  final data = List<Map<String, dynamic>>.from(response);

  print("📦 RECIBOS FILTRADOS: ${data.length}");

  return data;
}
double totalImporteRecibos(List<Map<String, dynamic>> lista) {
  return lista.fold<double>(0, (suma, r) {
    return suma + _toDoubleKpi(
      r['importe'] ??
      r['precio'] ??
      r['prima'] ??
      r['total'] ??
      0,
    );
  });
}

int totalRecibosPorEstado(
  List<Map<String, dynamic>> lista,
  String estado,
) {
  return lista.where((r) {
    return (r['estado']?.toString().toUpperCase() ?? '') ==
        estado.toUpperCase();
  }).length;
}

double totalDineroRecibosPorEstado(
  List<Map<String, dynamic>> lista,
  String estado,
) {
  final filtrados = lista.where((r) {
    return (r['estado']?.toString().toUpperCase() ?? '') ==
        estado.toUpperCase();
  }).toList();

  return totalImporteRecibos(filtrados);
}

Future<void> seleccionarArchivoPolizas() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'csv'],
    withData: true,
  );

  if (result == null) return;

  final file = result.files.first;
  Uint8List? bytes = file.bytes;

  if (bytes == null && file.path != null) {
    bytes = await File(file.path!).readAsBytes();
  }

  if (bytes == null) return;

  polizasHeaders.clear();
  polizasRows.clear();
  polizasPreview.clear();
  polizasColumnMapping.clear();

  final extension = file.extension?.toLowerCase();

  if (extension == 'csv') {
    final content = utf8.decode(bytes, allowMalformed: true);
    final lines = const LineSplitter()
        .convert(content)
        .where((l) => l.trim().isNotEmpty)
        .toList();

    if (lines.isEmpty) return;

    final separator = lines.first.contains(';') ? ';' : ',';

    polizasHeaders = lines.first
        .split(separator)
        .map((e) => e.trim().toUpperCase())
        .toList();

    polizasRows = lines.skip(1).map((line) {
      return line.split(separator).map((e) => e.trim()).toList();
    }).toList();
  } else {
    final archivoExcel = excel.Excel.decodeBytes(bytes);
    final sheet = archivoExcel.tables.values.first;
    final rows = sheet.rows;

    if (rows.isEmpty) return;

    polizasHeaders = rows.first
        .map((e) => e?.value.toString().trim().toUpperCase() ?? '')
        .toList();

    polizasRows = rows.skip(1).map((row) {
      return row.map((e) => e?.value ?? '').toList();
    }).toList();
  }

  autoMapearPolizas();

  polizasPreview = [
    polizasHeaders,
    ...polizasRows.take(80),
  ];

  setState(() {});
}

void autoMapearPolizas() {
  final Map<String, String> auto = {
    "NOMBRE": "cliente.nombre",
    "CLIENTE": "cliente.nombre",
    "NOMBRE CLIENTE": "cliente.nombre",
    "TOMADOR": "cliente.nombre",

    "APELLIDOS": "cliente.apellidos",
    "APELLIDO": "cliente.apellidos",

    "TELEFONO": "cliente.telefono",
    "TELÉFONO": "cliente.telefono",
    "MOVIL": "cliente.telefono",
    "MÓVIL": "cliente.telefono",

    "EMAIL": "cliente.email",
    "CORREO": "cliente.email",

    "CP": "cliente.codigo_postal",
    "CODIGO POSTAL": "cliente.codigo_postal",
    "CÓDIGO POSTAL": "cliente.codigo_postal",

    "PROVINCIA": "cliente.provincia",
    "POBLACION": "cliente.poblacion",
    "POBLACIÓN": "cliente.poblacion",
    "LOCALIDAD": "cliente.poblacion",

    "DIRECCION": "cliente.direccion",
    "DIRECCIÓN": "cliente.direccion",
    "DOMICILIO": "cliente.direccion",

    "NUMERO": "cliente.numero",
    "NÚMERO": "cliente.numero",
    "NUM": "cliente.numero",

    "DNI": "cliente.dni",
    "NIF": "cliente.dni",
    "NIE": "cliente.dni",

    "AUTH_ID": "venta.agente_auth_id",
"AGENTE_AUTH_ID": "venta.agente_auth_id",
"EMAIL AGENTE": "venta.agente_auth_id",
"CORREO AGENTE": "venta.agente_auth_id",

"AGENTE": "venta.agente_nombre_completo",
"COMERCIAL": "venta.agente_nombre_completo",
"MEDIADOR": "venta.agente_nombre_completo",
"ASESOR": "venta.agente_nombre_completo",
"VENDEDOR": "venta.agente_nombre_completo",
"NOMBRE COMERCIAL": "venta.agente_nombre_completo",
"NOMBRE MEDIADOR": "venta.agente_nombre_completo",

"NOMBRE AGENTE": "venta.agente_nombre",
"NOMBRE DEL AGENTE": "venta.agente_nombre",
"NOMBRE MEDIADOR": "venta.agente_nombre",
"NOMBRE DEL MEDIADOR": "venta.agente_nombre",

"APELLIDOS AGENTE": "venta.agente_apellidos",
"APELLIDOS DEL AGENTE": "venta.agente_apellidos",
"APELLIDOS MEDIADOR": "venta.agente_apellidos",
"APELLIDOS DEL MEDIADOR": "venta.agente_apellidos",

    "PRODUCTO": "venta.producto",
    "RAMO": "venta.producto",

    "COMPAÑIA": "venta.compania",
    "COMPANIA": "venta.compania",
    "ASEGURADORA": "venta.compania",

    "FORMA PAGO": "venta.forma_pago",
"FORMA DE PAGO": "venta.forma_pago",
"PAGO": "venta.forma_pago",

"FRECUENCIA": "venta.forma_pago",
"PERIODICIDAD": "venta.forma_pago",
"PERIOCIDAD": "venta.forma_pago",
"PERIODO": "venta.forma_pago",
"PERÍODO": "venta.forma_pago",
"FRACCIONAMIENTO": "venta.forma_pago",

    "PRECIO": "venta.precio",
"IMPORTE": "venta.precio",

"CUOTA": "venta.precio",
"PRIMA": "venta.precio",
"IMPORTE RECIBO": "venta.precio",
"RECIBO": "venta.precio",

    "ASEGURADOS": "venta.numero_asegurados",
    "NUMERO ASEGURADOS": "venta.numero_asegurados",
    "Nº ASEGURADOS": "venta.numero_asegurados",

    "FECHA EFECTO": "venta.fecha_efecto",
    "FECHA_EFECTO": "venta.fecha_efecto",
    "EFECTO": "venta.fecha_efecto",

    "PRIMA ANUAL": "venta.prima_anual",
    "PRIMA_ANUAL": "venta.prima_anual",

    "CATEGORIA": "venta.categoria_producto",
    "CATEGORIA PRODUCTO": "venta.categoria_producto",
    "CATEGORÍA PRODUCTO": "venta.categoria_producto",

    "PRIMA BRUTA": "venta.prima_anual_bruta",
    "PRIMA ANUAL BRUTA": "venta.prima_anual_bruta",

    "COMISION": "venta.comision",
    "COMISIÓN": "venta.comision",

    "POLIZA": "venta.numero_poliza",
    "PÓLIZA": "venta.numero_poliza",
    "NUMERO POLIZA": "venta.numero_poliza",
    "Nº POLIZA": "venta.numero_poliza",
    "Nº PÓLIZA": "venta.numero_poliza",

    "ESTADO": "venta.estado_poliza",
    "ESTADO POLIZA": "venta.estado_poliza",
    "ESTADO PÓLIZA": "venta.estado_poliza",
  };

  for (final h in polizasHeaders) {
    final key = h.trim().toUpperCase();
    if (auto.containsKey(key)) {
      polizasColumnMapping[key] = auto[key]!;
    }
  }
}

dynamic valorPolizaMapeado(List<dynamic> row, String campo) {
  for (int i = 0; i < polizasHeaders.length; i++) {
    final header = polizasHeaders[i].trim().toUpperCase();
    final mapped = polizasColumnMapping[header];

    if (mapped == campo && i < row.length) {
      final value = cleanExcelValue(row[i]);

      if (value == null) return null;

      final text = value.toString().trim();

      if (text.isEmpty) return null;

      return text;
    }
  }

  return null;
}

double? toDoublePoliza(dynamic value) {
  if (value == null) return null;

  final text = value
      .toString()
      .replaceAll('€', '')
      .replaceAll('.', '')
      .replaceAll(',', '.')
      .trim();

  return double.tryParse(text);
}

int? toIntPoliza(dynamic value) {
  if (value == null) return null;

  final text = value.toString().trim();

  return int.tryParse(text);
}

String? toFechaSupabase(dynamic value) {
  if (value == null) return null;

  final text = value.toString().trim();

  if (text.isEmpty) return null;

  try {
    if (text.contains('/')) {
      final parts = text.split('/');

      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);

        return DateTime(year, month, day).toIso8601String();
      }
    }

    final parsed = DateTime.tryParse(text);

    return parsed?.toIso8601String() ?? text;
  } catch (_) {
    return text;
  }
}

double calcularPrimaAnualMasiva({
  required double precio,
  required String? formaPago,
}) {
  final pago = formaPago
          ?.toLowerCase()
          .replaceAll('á', 'a')
          .replaceAll('é', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ú', 'u')
          .trim() ??
      '';

  if (pago.contains('mensual') || pago == 'm') {
    return precio * 12;
  }

  if (pago.contains('trimestral') || pago == 't') {
    return precio * 4;
  }

  if (pago.contains('semestral') || pago == 's') {
    return precio * 2;
  }

  if (pago.contains('anual') ||
      pago == 'a' ||
      pago.contains('unico') ||
      pago.contains('único')) {
    return precio;
  }

  return precio;
}

double calcularComisionMasiva({
  required double primaAnualBruta,
  required String? producto,
}) {
  final primaNeta = primaAnualBruta * 0.87;
  final p = producto?.toLowerCase().trim() ?? '';

  if (p.contains('decesos') || p.contains('vida')) {
    return primaNeta * 0.50;
  }

  if (p.contains('salud') || p.contains('baja laboral')) {
    return primaNeta * 0.15;
  }

  return primaNeta * 0.09;
}

Future<String?> resolverAgenteAuthId(dynamic value) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (value == null || value.toString().trim().isEmpty) {
    return currentUser?.id;
  }

  final raw = value.toString().trim();

  if (raw.length > 25 && raw.contains('-')) {
    return raw;
  }

  String normalizar(String text) {
    return text
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  final rawNormalizado = normalizar(raw);

  final usuariosResponse = await supabase
      .from('usuarios')
      .select('auth_id, nombre, apellidos, email');

  final usuarios = List<Map<String, dynamic>>.from(usuariosResponse);

  for (final u in usuarios) {
    final email = normalizar(u['email']?.toString() ?? '');

    if (email.isNotEmpty && email == rawNormalizado) {
      return u['auth_id']?.toString();
    }
  }

  for (final u in usuarios) {
    final nombre = normalizar(u['nombre']?.toString() ?? '');
    final apellidos = normalizar(u['apellidos']?.toString() ?? '');
    final nombreCompleto = normalizar('$nombre $apellidos');
    final nombreInvertido = normalizar('$apellidos $nombre');

    if (nombreCompleto == rawNormalizado ||
        nombreInvertido == rawNormalizado) {
      return u['auth_id']?.toString();
    }
  }

  for (final u in usuarios) {
    final nombre = normalizar(u['nombre']?.toString() ?? '');
    final apellidos = normalizar(u['apellidos']?.toString() ?? '');

    if (nombre.isNotEmpty &&
        apellidos.isNotEmpty &&
        rawNormalizado.contains(nombre) &&
        rawNormalizado.contains(apellidos)) {
      return u['auth_id']?.toString();
    }
  }

  return currentUser?.id;
}

Map<String, dynamic> limpiarNulls(Map<String, dynamic> data) {
  data.removeWhere((key, value) {
    if (value == null) return true;
    if (value is String && value.trim().isEmpty) return true;
    return false;
  });

  return data;
}

Future<void> importarPolizasMasivasASupabase() async {
  if (polizasRows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Primero selecciona un archivo")),
    );
    return;
  }

  final supabase = Supabase.instance.client;

  setState(() {
    importingPolizas = true;
    polizasImportProgress = 0;
    polizasImportTotal = polizasRows.length;
  });

  int ventasInsertadas = 0;
  int errores = 0;

  try {
    for (final row in polizasRows) {
      try {
        final clienteData = limpiarNulls({
          'auth_id': await resolverAgenteAuthId(
            valorPolizaMapeado(row, 'venta.agente_auth_id'),
          ),
          'nombre': valorPolizaMapeado(row, 'cliente.nombre'),
          'apellidos': valorPolizaMapeado(row, 'cliente.apellidos'),
          'telefono': valorPolizaMapeado(row, 'cliente.telefono'),
          'email': valorPolizaMapeado(row, 'cliente.email'),
          'codigo_postal': valorPolizaMapeado(row, 'cliente.codigo_postal'),
          'provincia': valorPolizaMapeado(row, 'cliente.provincia'),
          'poblacion': valorPolizaMapeado(row, 'cliente.poblacion'),
          'direccion': valorPolizaMapeado(row, 'cliente.direccion'),
          'numero': valorPolizaMapeado(row, 'cliente.numero'),
          'dni': valorPolizaMapeado(row, 'cliente.dni'),
        });

        final clienteResponse = await supabase
            .from('clientes')
            .insert(clienteData)
            .select('id')
            .single();

        final clienteId = clienteResponse['id'];

        final agenteDirecto = valorPolizaMapeado(row, 'venta.agente_auth_id');

final agenteNombre = valorPolizaMapeado(row, 'venta.agente_nombre');
final agenteApellidos = valorPolizaMapeado(row, 'venta.agente_apellidos');
final agenteCompleto = valorPolizaMapeado(row, 'venta.agente_nombre_completo');

final textoAgente = agenteDirecto ??
    agenteCompleto ??
    "${agenteNombre ?? ''} ${agenteApellidos ?? ''}".trim();

final agenteAuthId = await resolverAgenteAuthId(textoAgente);

        final producto = valorPolizaMapeado(row, 'venta.producto')?.toString();
        final formaPago = valorPolizaMapeado(row, 'venta.forma_pago')?.toString();

        final precio = toDoublePoliza(
          valorPolizaMapeado(row, 'venta.precio'),
        );

        final primaAnualExcel = toDoublePoliza(
          valorPolizaMapeado(row, 'venta.prima_anual'),
        );

        final primaBrutaExcel = toDoublePoliza(
          valorPolizaMapeado(row, 'venta.prima_anual_bruta'),
        );

        final primaBase = primaAnualExcel ??
            (precio == null
                ? null
                : calcularPrimaAnualMasiva(
                    precio: precio,
                    formaPago: formaPago,
                  ));

        final primaBruta = primaBrutaExcel ?? primaBase;

        final comisionExcel = toDoublePoliza(
          valorPolizaMapeado(row, 'venta.comision'),
        );

        final comision = comisionExcel ??
            (primaBruta == null
                ? null
                : calcularComisionMasiva(
                    primaAnualBruta: primaBruta,
                    producto: producto,
                  ));

        final ventaData = limpiarNulls({
          'cliente_id': clienteId,
          'agente_auth_id': agenteAuthId,

          'producto': producto,
          'compania': valorPolizaMapeado(row, 'venta.compania'),
          'forma_pago': formaPago,

          'precio': precio,
          'numero_asegurados': toIntPoliza(
            valorPolizaMapeado(row, 'venta.numero_asegurados'),
          ),

          'fecha_efecto': toFechaSupabase(
            valorPolizaMapeado(row, 'venta.fecha_efecto'),
          ),

          'prima_anual': primaBase,
          'prima_anual_bruta': primaBruta,
          'prima_anual_neta': primaBruta == null ? null : primaBruta * 0.87,
          'comision': comision,

          'categoria_producto':
              valorPolizaMapeado(row, 'venta.categoria_producto') ?? producto,

          'numero_poliza': valorPolizaMapeado(row, 'venta.numero_poliza'),
          'estado_poliza': valorPolizaMapeado(row, 'venta.estado_poliza'),
        });

        await supabase.from('ventas').insert(ventaData);

        ventasInsertadas++;
      } catch (e) {
        errores++;
        debugPrint("ERROR FILA CARGA PÓLIZA: $e");
      }

      setState(() {
        polizasImportProgress++;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Carga finalizada: $ventasInsertadas ventas importadas · $errores errores",
        ),
        backgroundColor: errores == 0 ? Colors.green : Colors.orange,
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Error en carga masiva: $e"),
        backgroundColor: Colors.red,
      ),
    );
  }

  setState(() {
    importingPolizas = false;
  });
}

Widget buildCargaMasivaPolizas() {
  return SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Carga Masiva de Pólizas",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          "Importa ventas completas desde Excel o CSV. Se crearán clientes y ventas en Supabase.",
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 24),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.cloud_upload_rounded,
                  color: Colors.indigo.shade700,
                  size: 36,
                ),
              ),

              const SizedBox(width: 14),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Importador inteligente",
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Detecta columnas automáticamente y permite corregir el mapeo antes de subir.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),

              ElevatedButton.icon(
                onPressed: importingPolizas ? null : seleccionarArchivoPolizas,
                icon: const Icon(Icons.file_open_rounded),
                label: const Text("Seleccionar archivo"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        if (polizasHeaders.isNotEmpty) buildMapeoPolizas(),

        const SizedBox(height: 20),

        if (polizasPreview.isNotEmpty) buildPreviewPolizas(),

        const SizedBox(height: 20),

        if (polizasRows.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Filas detectadas: ${polizasRows.length}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),

                const SizedBox(height: 12),

                if (importingPolizas)
                  LinearProgressIndicator(
                    value: polizasImportTotal == 0
                        ? 0
                        : polizasImportProgress / polizasImportTotal,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(20),
                  ),

                if (importingPolizas) const SizedBox(height: 8),

                if (importingPolizas)
                  Text(
                    "Importando: $polizasImportProgress / $polizasImportTotal",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed:
                        importingPolizas ? null : importarPolizasMasivasASupabase,
                    icon: importingPolizas
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(
                      importingPolizas
                          ? "Subiendo pólizas..."
                          : "Guardar en Supabase",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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

Widget buildMapeoPolizas() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                "Mapeo de columnas",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                autoMapearPolizas();
                setState(() {});
              },
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text("Auto-mapear"),
            ),
          ],
        ),

        const SizedBox(height: 14),

        ...polizasHeaders.map((header) {
          final key = header.trim().toUpperCase();

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    key,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    value: polizasColumnMapping[key],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: "Campo destino",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text("No importar"),
                      ),
                      ...camposCargaPolizas.map((campo) {
                        return DropdownMenuItem<String>(
                          value: campo,
                          child: Text(campo),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        if (value == null) {
                          polizasColumnMapping.remove(key);
                        } else {
                          polizasColumnMapping[key] = value;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    ),
  );
}

Widget buildPreviewPolizas() {
  return Container(
    height: 360,
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Vista previa",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    Colors.grey.shade100,
                  ),
                  columns: polizasPreview.first.map((e) {
                    return DataColumn(
                      label: Text(
                        e.toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  rows: polizasPreview.skip(1).map((row) {
                    return DataRow(
                      cells: row.map((cell) {
                        return DataCell(
                          Text(
                            cell.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> inicializarPermisosERP() async {
  try {
    print("ERP -> 1 INICIO");

    if (mounted) {
      setState(() {
        cargandoPermisosERP = true;
      });
    }

    await cargarPermisosERP();

    print("ERP -> 2 permisos cargados");
    print("ACCESO ERP: $accesoAdminPanelERP");
    print("VE TODO ERP: $veTodoERP");
    print("AUTH IDS PERMITIDOS: ${authIdsPermitidosERP.length}");

    if (accesoAdminPanelERP) {
      try {
        print("ERP -> cargarRecibos");
        await cargarRecibos();
      } catch (e) {
        print("❌ ERROR cargarRecibos: $e");
      }

      try {
        print("ERP -> cargarAgentesFiltro");
        await cargarAgentesFiltro();
      } catch (e) {
        print("❌ ERROR cargarAgentesFiltro: $e");
      }

      try {
        print("ERP -> cargarJefesFiltro");
        await cargarJefesFiltro();
      } catch (e) {
        print("❌ ERROR cargarJefesFiltro: $e");
      }

      try {
        print("ERP -> cargarCompanias");
        await cargarCompanias();
      } catch (e) {
        print("❌ ERROR cargarCompanias: $e");
      }

      try {
        print("ERP -> cargarFiltrosClientes");
        await cargarFiltrosClientes();
      } catch (e) {
        print("❌ ERROR cargarFiltrosClientes: $e");
      }

      try {
        print("ERP -> cargarFiltrosVentas");
        await cargarFiltrosVentas();
      } catch (e) {
        print("❌ ERROR cargarFiltrosVentas: $e");
      }
    }
  } catch (e) {
    print("❌ ERROR GENERAL inicializarPermisosERP: $e");
  } finally {
    if (mounted) {
      setState(() {
        cargandoPermisosERP = false;
      });
    }

    print("ERP -> FIN");
  }
}

Future<void> cargarPermisosERP() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    accesoAdminPanelERP = false;
    authIdsPermitidosERP = [];
    return;
  }

  final usuario = await supabase
      .from('usuarios')
      .select('id, auth_id, rol_usuario, parent_id, nombre, apellidos')
      .eq('auth_id', user.id)
      .maybeSingle();

  if (usuario == null) {
    accesoAdminPanelERP = false;
    authIdsPermitidosERP = [];
    return;
  }

  usuarioActualERP = Map<String, dynamic>.from(usuario);

  final rol = usuario['rol_usuario']?.toString().toUpperCase() ?? '';

  final rolesPermitidos = [
    'JEFE_EQUIPO',
    'JEFE_VENTAS',
    'DIRECTOR_ZONA',
    'DIRECTOR_NACIONAL',
    'ADMIN',
    'ADMINISTRACION',
    'ADMINISTRACIÓN',
  ];

  accesoAdminPanelERP = rolesPermitidos.contains(rol);

  if (!accesoAdminPanelERP) {
    authIdsPermitidosERP = [];
    return;
  }

  if (rol == 'ADMIN' ||
      rol == 'ADMINISTRACION' ||
      rol == 'ADMINISTRACIÓN' ||
      rol == 'DIRECTOR_NACIONAL') {
    authIdsPermitidosERP = [];
    return;
  }

  final usuariosResponse = await supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, rol_usuario, nombre, apellidos');

  final usuarios = List<Map<String, dynamic>>.from(usuariosResponse);

  final Set<String> permitidos = {};

 final Set<String> visitados = {};

void agregarDescendientes(dynamic parentId) {
  final parentKey = parentId?.toString() ?? '';

  if (parentKey.isEmpty) return;

  if (visitados.contains(parentKey)) {
    print("⚠️ Ciclo detectado en jerarquía con parentId: $parentKey");
    return;
  }

  visitados.add(parentKey);

  final hijos = usuarios.where((u) {
    final idHijo = u['id']?.toString() ?? '';
    final parentHijo = u['parent_id']?.toString() ?? '';

    return parentHijo == parentKey && idHijo != parentKey;
  }).toList();

  for (final h in hijos) {
    final authId = h['auth_id']?.toString();

    if (authId != null && authId.isNotEmpty) {
      permitidos.add(authId);
    }

    agregarDescendientes(h['id']);
  }
}

  final miAuthId = usuario['auth_id']?.toString();

  if (miAuthId != null && miAuthId.isNotEmpty) {
    permitidos.add(miAuthId);
  }

  agregarDescendientes(usuario['id']);

  authIdsPermitidosERP = permitidos.toList();

  print("ROL ERP: $rol");
  print("AUTH IDS PERMITIDOS: ${authIdsPermitidosERP.length}");
}

bool get veTodoERP {
  final rol = usuarioActualERP?['rol_usuario']?.toString().toUpperCase() ?? '';

  return rol == 'ADMIN' ||
      rol == 'ADMINISTRACION' ||
      rol == 'ADMINISTRACIÓN' ||
      rol == 'DIRECTOR_NACIONAL';
}

  @override
Widget build(BuildContext context) {
  if (cargandoPermisosERP) {
    return const Scaffold(
      backgroundColor: Color(0xFFF3F6FA),
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  if (!accesoAdminPanelERP) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: Center(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 54,
                color: Colors.red,
              ),
              SizedBox(height: 16),
              Text(
                "Acceso no autorizado",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Esta pantalla solo está disponible para jefes, dirección y administración.",
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  return Scaffold(
    backgroundColor: const Color(0xFFF3F6FA),
    body: Row(
      children: [
        // MENÚ IZQUIERDO ERP
        Container(
          width: 285,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(4, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 34),

              // LOGO / MARCA
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.blue.shade400,
                            Colors.indigo.shade600,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "SafeBrok",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            "ERP Administrador",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    _menuSection("GENERAL"),

                    _menuItem(
                      "Dashboard",
                      "dashboard",
                      Icons.dashboard_rounded,
                    ),

                    _menuItem(
                      "Producción",
                      "produccion",
                      Icons.bar_chart_rounded,
                    ),

                    _menuItem(
                      "Ventas",
                      "ventas",
                      Icons.euro_rounded,
                    ),

                    _menuItem(
                      "Clientes",
                      "clientes",
                      Icons.people_alt_rounded,
                    ),

                    const SizedBox(height: 14),

                    _menuSection("RECIBOS"),

                    _menuItem(
                      "Recibos Cobrados",
                      "recibos_cobrados",
                      Icons.check_circle_rounded,
                    ),

                    _menuItem(
                      "Recibos Devueltos",
                      "recibos_devueltos",
                      Icons.cancel_rounded,
                    ),

                    _menuItem(
                      "Recibos Pendientes",
                      "recibos_pendientes",
                      Icons.schedule_rounded,
                    ),

                    _menuItem(
                      "Cargar Recibos",
                      "cargar_recibos",
                      Icons.upload_file_rounded,
                    ),

                    _menuItem(
  "Cargar Pólizas",
  "cargar_polizas",
  Icons.cloud_upload_rounded,
),
                    const SizedBox(height: 14),

                    _menuSection("EQUIPO"),

                    _menuItem(
                      "Agentes",
                      "agentes",
                      Icons.person_rounded,
                    ),

                    _menuItem(
                      "Jefes Equipo",
                      "jefes",
                      Icons.groups_rounded,
                    ),

                    _menuItem(
                      "Referencias",
                      "referencias",
                      Icons.flag_rounded,
                    ),

                    _menuItem(
                      "Nóminas",
                      "nominas",
                      Icons.payments_rounded,
                    ),

                    const SizedBox(height: 14),

                    _menuSection("SISTEMA"),

                    _menuItem(
                      "Mensajes",
                      "mensajes",
                      Icons.message_rounded,
                    ),

                    _menuItem(
                      "Alertas",
                      "alertas",
                      Icons.notification_important_rounded,
                    ),

                    _menuItem(
                      "Configuración",
                      "configuracion",
                      Icons.settings_rounded,
                    ),
                  ],
                ),
              ),

              // USUARIO ABAJO
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.blue.shade600,
                      child: const Text(
                        "A",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Administrador",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Sesión activa",
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // CONTENIDO DERECHO
        Expanded(
          child: Column(
            children: [
              buildTopBar(),

              Expanded(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFF3F6FA),
                  padding: const EdgeInsets.all(22),
                  child: buildContent(),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _menuItem(
  String title,
  String value,
  IconData icon,
) {
  final selected = selectedMenu == value;

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() {
          selectedMenu = value;
        });

        if (value == "recibos_cobrados" ||
            value == "recibos_devueltos" ||
            value == "recibos_pendientes") {
          cargarRecibos();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade600 : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Colors.blue.shade400
                : Colors.white.withOpacity(0.04),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 20,
              ),
          ],
        ),
      ),
    ),
  );
}
Widget _menuSection(String title) {
  return Padding(
    padding: const EdgeInsets.only(
      left: 10,
      right: 10,
      bottom: 8,
      top: 6,
    ),
    child: Text(
      title,
      style: TextStyle(
        color: Colors.white.withOpacity(0.38),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    ),
  );
}


  Widget buildTopBar() {
  final email = Supabase.instance.client.auth.currentUser?.email ?? "";

  return Container(
    height: 78,
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 25),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(
        bottom: BorderSide(color: Colors.grey.shade200),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.menu,
            size: 26,
            color: Colors.blue.shade700,
          ),
        ),

        const SizedBox(width: 15),

        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Panel Administrador",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "SafeBrok ERP · Control operativo",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),

        const Spacer(),

        FutureBuilder<int>(
          future: contarNotificacionesPendientes(),
          builder: (context, snapshot) {
            final pendientes = snapshot.data ?? 0;

            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                await abrirNotificacionesDialog();
                setState(() {});
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      size: 28,
                    ),
                  ),

                  if (pendientes > 0)
                    Positioned(
                      right: -5,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Text(
                          pendientes > 99 ? "99+" : pendientes.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),

        const SizedBox(width: 26),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.blue.shade700,
                child: Text(
                  email.isNotEmpty ? email[0].toUpperCase() : "A",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 210,
                    child: Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Text(
                    "Administrador",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
Future<int> contarNotificacionesPendientes() async {
  final email = Supabase.instance.client.auth.currentUser?.email;

  dynamic query = Supabase.instance.client
      .from('notificaciones')
      .select('id')
      .eq('leida', false);

  if (email != null && email.isNotEmpty) {
    query = query.or('usuario_email.eq.$email,usuario_email.is.null');
  }

  final data = await query;

  return data.length;
}

Future<void> abrirNotificacionesDialog() async {
  final email = Supabase.instance.client.auth.currentUser?.email;

  dynamic query = Supabase.instance.client
      .from('notificaciones')
      .select();

  if (email != null && email.isNotEmpty) {
    query = query.or('usuario_email.eq.$email,usuario_email.is.null');
  }

  final notificaciones = await query.order(
    'created_at',
    ascending: false,
  );

  final pendientes = notificaciones.where((n) => n['leida'] != true).length;
  final leidas = notificaciones.where((n) => n['leida'] == true).length;

  await showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.notifications_active_outlined,
                      color: Colors.orange.shade700,
                      size: 34,
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Centro de notificaciones",
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Avisos operativos, recibos, agentes, gestiones y documentación adjunta",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  TextButton.icon(
                    onPressed: pendientes == 0
                        ? null
                        : () async {
                            dynamic updateQuery = Supabase.instance.client
                                .from('notificaciones')
                                .update({'leida': true})
                                .eq('leida', false);

                            if (email != null && email.isNotEmpty) {
                              updateQuery = updateQuery.or(
                                'usuario_email.eq.$email,usuario_email.is.null',
                              );
                            }

                            await updateQuery;

                            Navigator.pop(context);
                            await abrirNotificacionesDialog();
                          },
                    icon: const Icon(Icons.done_all),
                    label: const Text("Marcar todas"),
                  ),

                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _kpiNotificacionERP(
                    "Pendientes",
                    pendientes.toString(),
                    Icons.mark_email_unread_outlined,
                    Colors.red,
                  ),
                  _kpiNotificacionERP(
                    "Leídas",
                    leidas.toString(),
                    Icons.mark_email_read_outlined,
                    Colors.green,
                  ),
                  _kpiNotificacionERP(
                    "Total",
                    notificaciones.length.toString(),
                    Icons.notifications_outlined,
                    Colors.blue,
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Expanded(
                child: notificaciones.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              "No hay notificaciones",
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "Cuando haya avisos, recibos, gestiones o archivos compartidos aparecerán aquí.",
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: notificaciones.length,
                        itemBuilder: (context, index) {
                          final n = Map<String, dynamic>.from(
                            notificaciones[index],
                          );

                          final leida = n['leida'] == true;

                          return _tarjetaNotificacionERP(n, leida);
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
Widget _kpiNotificacionERP(
  String titulo,
  String valor,
  IconData icono,
  MaterialColor color,
) {
  return Container(
    width: 180,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icono,
            color: color.shade700,
            size: 24,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              Text(
                valor,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _tarjetaNotificacionERP(Map<String, dynamic> n, bool leida) {
  final tipo = n['tipo']?.toString() ?? 'general';
  final prioridad = n['prioridad']?.toString() ?? 'normal';

  IconData icono = Icons.notifications_outlined;
  Color color = Colors.blue;

  if (tipo.contains('recibo')) {
    icono = Icons.receipt_long_outlined;
    color = Colors.red;
  } else if (tipo.contains('gestion')) {
    icono = Icons.manage_accounts_outlined;
    color = Colors.deepPurple;
  } else if (tipo.contains('anulacion')) {
    icono = Icons.cancel_outlined;
    color = Colors.red;
  } else if (tipo.contains('poliza')) {
    icono = Icons.description_outlined;
    color = Colors.indigo;
  }

  if (prioridad == 'alta') {
    color = Colors.red;
  }

  return InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () async {
      await Supabase.instance.client
          .from('notificaciones')
          .update({'leida': true})
          .eq('id', n['id']);

      setState(() {});
      Navigator.pop(context);
      await abrirNotificacionesDialog();
    },
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: leida ? Colors.grey.shade50 : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: leida ? Colors.grey.shade300 : color.withOpacity(0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icono,
                  color: color,
                  size: 28,
                ),
              ),

              if (!leida)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n['titulo']?.toString() ?? 'Notificación',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: leida ? FontWeight.w600 : FontWeight.bold,
                        ),
                      ),
                    ),

                    if (!leida)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          "PENDIENTE",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 6),

                Text(
                  n['mensaje']?.toString() ?? '',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 10),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipNotificacion("Tipo", tipo),
                    if ((n['poliza']?.toString() ?? '').isNotEmpty)
                      _chipNotificacion("Póliza", n['poliza'].toString()),
                    _chipNotificacion(
                      "Fecha",
                      n['created_at']?.toString().split('T').first ?? '',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
Widget _chipNotificacion(String titulo, String valor) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Text(
      "$titulo: $valor",
      style: TextStyle(
        fontSize: 11,
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
Future<void> crearNotificacionReciboDevuelto({
  required dynamic ventaId,
  required String poliza,
  required dynamic reciboId,
  required dynamic importe,
}) async {
  await Supabase.instance.client
      .from('notificaciones')
      .insert({
        'titulo': 'Recibo devuelto',
        'mensaje': 'Se ha detectado un recibo devuelto de la póliza $poliza por importe de $importe €.',
        'tipo': 'recibo_devuelto',
        'leida': false,
        'venta_id': ventaId,
        'poliza': poliza,
        'recibo_id': reciboId,
        'usuario_email': Supabase.instance.client.auth.currentUser?.email,
        'prioridad': 'alta',
      });
}




  Widget buildFilters() {
    return Text(
      "Filtros: $selectedMenu",
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    );
  }

Widget buildContent() {
  // DASHBOARD
  if (selectedMenu == 'dashboard') {
    return buildDashboardPageERP();
  }

  // CARGAR RECIBOS
  if (selectedMenu == 'cargar_recibos') {
    return buildCargarRecibos();
  }
  if (selectedMenu == 'cargar_polizas') {
  return buildCargaMasivaPolizas();
}

  if (selectedMenu == 'agentes') {
  return buildAgentesPageERP();
}
  // CLIENTES
  if (selectedMenu == 'clientes') {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 210,
          child: buildDashboardKpis(),
        ),
        const SizedBox(height: 20),
        Expanded(child: buildClientesPage()),
      ],
    );
  }

  // VENTAS
  if (selectedMenu == 'ventas') {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 210,
          child: buildDashboardKpis(),
        ),
        const SizedBox(height: 20),
        Expanded(child: buildVentasPage()),
      ],
    );
  }

  // PRODUCCIÓN
  if (selectedMenu == 'produccion') {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 210,
          child: buildDashboardKpis(),
        ),
        const SizedBox(height: 20),
        Expanded(child: buildProduccionPage()),
      ],
    );
  }

  // RECIBOS
  if (selectedMenu == 'recibos_cobrados' ||
      selectedMenu == 'recibos_devueltos' ||
      selectedMenu == 'recibos_pendientes') {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 210,
          child: buildDashboardKpis(),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: buildRecibosPage(selectedMenu),
        ),
      ],
    );
  }

  // DEFAULT
  return buildDashboardPageERP();
}
Future<List<Map<String, dynamic>>> getAgentesERP() async {
  try {
    final supabase = Supabase.instance.client;

    dynamic usuariosQuery = supabase
        .from('usuarios')
        .select('id, auth_id, parent_id, nombre, apellidos, email, rol_usuario, estado');

    if (!veTodoERP) {
      if (authIdsPermitidosERP.isEmpty) return [];

      usuariosQuery = usuariosQuery.inFilter(
        'auth_id',
        authIdsPermitidosERP,
      );
    }

    final usuariosResponse = await usuariosQuery;

    dynamic ventasQuery = supabase.from('ventas').select();

    if (!veTodoERP) {
      ventasQuery = ventasQuery.inFilter(
        'agente_auth_id',
        authIdsPermitidosERP,
      );
    }

    final ventasResponse = await ventasQuery;

    final usuarios = List<Map<String, dynamic>>.from(usuariosResponse);
    final ventas = List<Map<String, dynamic>>.from(ventasResponse);

    final agentes = <Map<String, dynamic>>[];

    for (final u in usuarios) {
      final authId = u['auth_id']?.toString() ?? '';

      final ventasAgente = ventas.where((v) {
        return v['agente_auth_id']?.toString() == authId;
      }).toList();

      final jefe = usuarios.firstWhere(
        (j) => j['id']?.toString() == u['parent_id']?.toString(),
        orElse: () => <String, dynamic>{},
      );

      final primaTotal = ventasAgente.fold<double>(0, (suma, v) {
        return suma +
            _toDoubleKpi(
              v['prima_anual_bruta'] ??
                  v['prima_anual'] ??
                  v['prima_anual_neta'] ??
                  0,
            );
      });

      final comisionTotal = ventasAgente.fold<double>(0, (suma, v) {
        return suma +
            _toDoubleKpi(
              v['comision'] ??
                  v['comison'] ??
                  0,
            );
      });

      agentes.add({
        ...u,
        'nombre_completo':
            "${u['nombre'] ?? ''} ${u['apellidos'] ?? ''}".trim(),
        'jefe_nombre': jefe.isEmpty
            ? 'Sin jefe'
            : "${jefe['nombre'] ?? ''} ${jefe['apellidos'] ?? ''}".trim(),
        'total_ventas': ventasAgente.length,
        'prima_total': primaTotal,
        'comision_total': comisionTotal,
        'recibos_devueltos': 0,
      });
    }

    print("AGENTES CARGADOS ERP: ${agentes.length}");
    return agentes;
  } catch (e) {
    print("❌ ERROR getAgentesERP: $e");
    return [];
  }
}
Widget buildAgentesPageERP() {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: getAgentesERP(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final agentes = snapshot.data!;

      final totalAgentes = agentes.length;

final comerciales = agentes.where((a) {
  final rol = a['rol_usuario']?.toString().toLowerCase() ?? '';
  return rol.contains('agente') || rol.contains('comercial');
}).length;

final jefes = agentes.where((a) {
  final rol = a['rol_usuario']?.toString().toLowerCase() ?? '';
  return rol.contains('jefe') && rol.contains('equipo');
}).length;

final jefesVentas = agentes.where((a) {
  final rol = a['rol_usuario']?.toString().toLowerCase() ?? '';
  return rol.contains('jefe') && rol.contains('venta');
}).length;

      final produccion = agentes.fold<double>(0, (suma, a) {
        return suma + _toDoubleKpi(a['prima_total']);
      });

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.groups_rounded,
                      color: Colors.blue.shade700,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Centro de Agentes",
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          "Consulta de comerciales, roles, responsables, producción y seguimiento",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
               _kpiAgenteERP("Usuarios", totalAgentes.toString(), Icons.people_alt_outlined, Colors.blue),
_kpiAgenteERP("Agentes", comerciales.toString(), Icons.person_outline, Colors.green),
_kpiAgenteERP("Jefes equipo", jefes.toString(), Icons.groups_outlined, Colors.indigo),
_kpiAgenteERP("Jefes ventas", jefesVentas.toString(), Icons.workspace_premium_outlined, Colors.deepPurple),
_kpiAgenteERP("Producción", _formatoEuroKpi(produccion), Icons.euro_outlined, Colors.orange),
              ],
            ),

            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: _decoracionAgenteERP(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        "Listado profesional de agentes",
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${agentes.length} registros",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
  height: 620,
  child: SingleChildScrollView(
    scrollDirection: Axis.vertical,
    child: TablaConScrollHorizontalERP(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 360,
        ),
        child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                Colors.grey.shade100,
                              ),
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 78,
                              columnSpacing: 28,
                              horizontalMargin: 14,
                              border: TableBorder(
                                horizontalInside: BorderSide(
                                  color: Colors.grey.shade200,
                                ),
                              ),
                              columns: const [
                                DataColumn(label: Text("Agente")),
                                DataColumn(label: Text("Rol")),
                                DataColumn(label: Text("Jefe equipo")),
                                DataColumn(label: Text("Ventas")),
                                DataColumn(label: Text("Producción")),
                                DataColumn(label: Text("Comisión")),
                                DataColumn(label: Text("Devueltos")),
                                DataColumn(label: Text("Estado")),
                                DataColumn(label: Text("Acciones")),
                              ],
                              rows: agentes.map((a) {
                                return DataRow(
  onSelectChanged: (_) async {
    await mostrarEnviarNotificacionAgenteERP(a);
  },
  cells: [
                                    DataCell(
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 17,
                                            backgroundColor: Colors.blue.shade700,
                                            child: Text(
                                              (a['nombre_completo']?.toString().isNotEmpty ?? false)
                                                  ? a['nombre_completo'].toString()[0].toUpperCase()
                                                  : "A",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                a['nombre_completo']?.toString() ?? 'Sin nombre',
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                a['email']?.toString() ?? '',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(_chipRolAgenteERP(a['rol_usuario']?.toString() ?? '')),
                                    DataCell(Text(a['jefe_nombre']?.toString() ?? '')),
                                    DataCell(Text(a['total_ventas'].toString())),
                                    DataCell(Text(_formatoEuroKpi(a['prima_total']))),
                                    DataCell(Text(_formatoEuroKpi(a['comision_total']))),
                                    DataCell(Text(a['recibos_devueltos'].toString())),
                                    DataCell(_chipEstadoAgenteERP(a)),
                                    DataCell(
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert),
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: "detalle",
                                            child: ListTile(
                                              leading: Icon(Icons.visibility_outlined),
                                              title: Text("Ver ficha"),
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: "produccion",
                                            child: ListTile(
                                              leading: Icon(Icons.bar_chart_outlined),
                                              title: Text("Ver producción"),
                                            ),
                                          ),
                                          PopupMenuItem(
  value: "gestionar",
  child: ListTile(
    leading: Icon(Icons.admin_panel_settings_outlined),
    title: Text("Gestionar agente"),
  ),
),
                                        ],
                                        onSelected: (value) {
                                          if (value == "detalle") {
                                            mostrarDetalleAgenteERP(a);
                                          }

                                          if (value == "produccion") {
                                            mostrarProduccionAgenteERP(a);
                                          }
                                          if (value == "gestionar") {
  mostrarGestionarAgenteERP(a);
}
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
BoxDecoration _decoracionAgenteERP() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: Colors.grey.shade300),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.03),
        blurRadius: 14,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

Widget _kpiAgenteERP(
  String titulo,
  String valor,
  IconData icono,
  MaterialColor color,
) {
  return Container(
    width: 220,
    padding: const EdgeInsets.all(17),
    decoration: _decoracionAgenteERP(),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icono, color: color.shade700, size: 27),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _chipRolAgenteERP(String rol) {
  final rolUpper = rol.toUpperCase();

  MaterialColor color = Colors.blue;
  IconData icono = Icons.person_outline;
  String texto = rolUpper.isEmpty ? "SIN ROL" : rolUpper;

  if (rolUpper == "JEFE_EQUIPO") {
    color = Colors.indigo;
    icono = Icons.groups_outlined;
    texto = "JEFE EQUIPO";
  }

  if (rolUpper == "AGENTE") {
    color = Colors.green;
    icono = Icons.person_outline;
    texto = "AGENTE";
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.shade100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 16, color: color.shade700),
        const SizedBox(width: 6),
        Text(
          texto,
          style: TextStyle(
            color: color.shade800,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

Widget _chipEstadoAgenteERP(Map<String, dynamic> a) {
  final ventas = int.tryParse(a['total_ventas']?.toString() ?? '0') ?? 0;
  final devueltos = int.tryParse(a['recibos_devueltos']?.toString() ?? '0') ?? 0;

  String texto = "Activo";
  MaterialColor color = Colors.green;
  IconData icono = Icons.check_circle_outline;

  if (ventas == 0) {
    texto = "Sin producción";
    color = Colors.orange;
    icono = Icons.info_outline;
  }

  if (devueltos >= 3) {
    texto = "Revisar";
    color = Colors.red;
    icono = Icons.warning_amber_rounded;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.shade100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 16, color: color.shade700),
        const SizedBox(width: 6),
        Text(
          texto,
          style: TextStyle(
            color: color.shade800,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}
Future<void> mostrarDetalleAgenteERP(Map<String, dynamic> a) async {
  await showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.blue.shade700,
                    child: Text(
                      (a['nombre_completo']?.toString().isNotEmpty ?? false)
                          ? a['nombre_completo'].toString()[0].toUpperCase()
                          : "A",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a['nombre_completo']?.toString() ?? 'Agente',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          a['email']?.toString() ?? '',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _miniDatoAgenteERP("Rol", a['rol_usuario']),
                  _miniDatoAgenteERP("Jefe equipo", a['jefe_nombre']),
                  _miniDatoAgenteERP("Ventas", a['total_ventas']),
                  _miniDatoAgenteERP("Producción", _formatoEuroKpi(a['prima_total'])),
                  _miniDatoAgenteERP("Comisión", _formatoEuroKpi(a['comision_total'])),
                  _miniDatoAgenteERP("Devueltos", a['recibos_devueltos']),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> mostrarProduccionAgenteERP(Map<String, dynamic> a) async {
  await showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 760),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.indigo.shade700,
                      child: Text(
                        (a['nombre_completo']?.toString().isNotEmpty ?? false)
                            ? a['nombre_completo'].toString()[0].toUpperCase()
                            : "A",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Producción del agente",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            a['nombre_completo']?.toString() ?? 'Agente',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _miniDatoAgenteERP("Ventas realizadas", a['total_ventas']),
                    _miniDatoAgenteERP("Producción bruta", _formatoEuroKpi(a['prima_total'])),
                    _miniDatoAgenteERP("Comisión generada", _formatoEuroKpi(a['comision_total'])),
                    _miniDatoAgenteERP("Recibos devueltos", a['recibos_devueltos']),
                    _miniDatoAgenteERP("Rol", a['rol_usuario']),
                    _miniDatoAgenteERP("Jefe equipo", a['jefe_nombre']),
                  ],
                ),

                const SizedBox(height: 22),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insights_outlined, color: Colors.indigo.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Este resumen muestra la producción vinculada al agente según las ventas registradas y los recibos asociados a sus pólizas.",
                          style: TextStyle(
                            color: Colors.indigo.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> mostrarGestionarAgenteERP(Map<String, dynamic> a) async {
  final nombreController = TextEditingController(text: a['nombre']?.toString() ?? '');
  final apellidosController = TextEditingController(text: a['apellidos']?.toString() ?? '');
  final emailController = TextEditingController(text: a['email']?.toString() ?? '');
  final direccionController = TextEditingController(text: a['direccion']?.toString() ?? '');
  final numeroController = TextEditingController(text: a['numero_direccion']?.toString() ?? '');
  final cpController = TextEditingController(text: a['codigo_postal']?.toString() ?? '');
  final provinciaController = TextEditingController(text: a['provincia']?.toString() ?? '');
  final localidadController = TextEditingController(text: a['localidad']?.toString() ?? '');

  String rolSeleccionado = a['rol_usuario']?.toString().toUpperCase() ?? 'AGENTE';
String estadoSeleccionado = a['estado']?.toString().toUpperCase() ?? 'ACTIVO';

if (!["ADMIN", "JEFE_EQUIPO", "AGENTE"].contains(rolSeleccionado)) {
  rolSeleccionado = "AGENTE";
}

if (!["ACTIVO", "INACTIVO", "BAJA", "SUSPENDIDO"].contains(estadoSeleccionado)) {
  estadoSeleccionado = "ACTIVO";
}

  bool guardando = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 820),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.admin_panel_settings_outlined,
                            color: Colors.blue.shade700,
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Gestionar agente",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Editar datos, rol y estado operativo del usuario",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: guardando ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    Row(
                      children: [
                        Expanded(
                          child: _campoGestionAgente(
                            "Nombre",
                            Icons.person_outline,
                            nombreController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campoGestionAgente(
                            "Apellidos",
                            Icons.badge_outlined,
                            apellidosController,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    _campoGestionAgente(
                      "Email",
                      Icons.email_outlined,
                      emailController,
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: rolSeleccionado,
                            decoration: _decoracionGestionAgente(
                              "Rol usuario",
                              Icons.manage_accounts_outlined,
                            ),
                            items: const [
                              DropdownMenuItem(value: "ADMIN", child: Text("Administrador")),
                              DropdownMenuItem(value: "JEFE_EQUIPO", child: Text("Jefe de equipo")),
                              DropdownMenuItem(value: "AGENTE", child: Text("Agente")),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                rolSeleccionado = value ?? "AGENTE";
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: estadoSeleccionado,
                            decoration: _decoracionGestionAgente(
                              "Estado",
                              Icons.power_settings_new_outlined,
                            ),
                            items: const [
                              DropdownMenuItem(value: "ACTIVO", child: Text("Activo")),
                              DropdownMenuItem(value: "INACTIVO", child: Text("Inactivo")),
                              DropdownMenuItem(value: "BAJA", child: Text("Baja")),
                              DropdownMenuItem(value: "SUSPENDIDO", child: Text("Suspendido")),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                estadoSeleccionado = value ?? "ACTIVO";
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      "Datos de dirección",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _campoGestionAgente(
                            "Dirección",
                            Icons.home_outlined,
                            direccionController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campoGestionAgente(
                            "Número",
                            Icons.pin_outlined,
                            numeroController,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _campoGestionAgente(
                            "Código postal",
                            Icons.markunread_mailbox_outlined,
                            cpController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campoGestionAgente(
                            "Localidad",
                            Icons.location_city_outlined,
                            localidadController,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _campoGestionAgente(
                            "Provincia",
                            Icons.map_outlined,
                            provinciaController,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: estadoSeleccionado == "BAJA" || estadoSeleccionado == "INACTIVO"
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: estadoSeleccionado == "BAJA" || estadoSeleccionado == "INACTIVO"
                              ? Colors.red.shade100
                              : Colors.green.shade100,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            estadoSeleccionado == "BAJA" || estadoSeleccionado == "INACTIVO"
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            color: estadoSeleccionado == "BAJA" || estadoSeleccionado == "INACTIVO"
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              estadoSeleccionado == "BAJA"
                                  ? "El usuario quedará marcado como BAJA en el sistema."
                                  : estadoSeleccionado == "INACTIVO"
                                      ? "El usuario quedará desactivado operativamente."
                                      : "El usuario quedará activo y operativo.",
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: guardando ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            label: const Text("Cancelar"),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: guardando
                                ? null
                                : () async {
                                    setDialogState(() {
                                      guardando = true;
                                    });

                                    try {
                                      await Supabase.instance.client
                                          .from('usuarios')
                                          .update({
                                            'nombre': nombreController.text.trim(),
                                            'apellidos': apellidosController.text.trim(),
                                            'email': emailController.text.trim(),
                                            'rol_usuario': rolSeleccionado,
                                            'estado': estadoSeleccionado,
                                            'direccion': direccionController.text.trim(),
                                            'numero_direccion': numeroController.text.trim(),
                                            'codigo_postal': cpController.text.trim(),
                                            'provincia': provinciaController.text.trim(),
                                            'localidad': localidadController.text.trim(),
                                          })
                                          .eq('id', a['id']);

                                      Navigator.pop(context);

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Agente actualizado correctamente"),
                                          backgroundColor: Colors.green,
                                        ),
                                      );

                                      setState(() {});
                                    } catch (e) {
                                      setDialogState(() {
                                        guardando = false;
                                      });

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("Error al actualizar agente: $e"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                            icon: guardando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(guardando ? "Guardando..." : "Guardar cambios"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  nombreController.dispose();
  apellidosController.dispose();
  emailController.dispose();
  direccionController.dispose();
  numeroController.dispose();
  cpController.dispose();
  provinciaController.dispose();
  localidadController.dispose();
}
Widget _campoGestionAgente(
  String label,
  IconData icon,
  TextEditingController controller,
) {
  return TextField(
    controller: controller,
    decoration: _decoracionGestionAgente(label, icon),
  );
}

InputDecoration _decoracionGestionAgente(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.grey.shade50,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.blue, width: 1.6),
    ),
  );
}


Widget _miniDatoAgenteERP(String titulo, dynamic valor) {
  return Container(
    width: 200,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          valor?.toString().isEmpty ?? true ? "—" : valor.toString(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}
Future<void> mostrarEnviarNotificacionAgenteERP(Map<String, dynamic> a) async {
  final tituloController = TextEditingController(
    text: "Aviso de administración",
  );

  final mensajeController = TextEditingController();

  String tipoSeleccionado = "agente";
  String prioridadSeleccionada = "normal";
  bool enviando = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 760),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.blue.shade700,
                          child: Text(
                            (a['nombre_completo']?.toString().isNotEmpty ?? false)
                                ? a['nombre_completo'].toString()[0].toUpperCase()
                                : "A",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Enviar notificación",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                a['nombre_completo']?.toString() ?? 'Agente',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: enviando ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active_outlined, color: Colors.blue.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Esta notificación se enviará al centro de notificaciones del agente.",
                              style: TextStyle(
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    TextField(
                      controller: tituloController,
                      decoration: _decoracionGestionAgente(
                        "Título de la notificación",
                        Icons.title_outlined,
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: mensajeController,
                      maxLines: 5,
                      decoration: _decoracionGestionAgente(
                        "Mensaje para el agente",
                        Icons.message_outlined,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: tipoSeleccionado,
                            decoration: _decoracionGestionAgente(
                              "Tipo",
                              Icons.category_outlined,
                            ),
                            items: const [
                              DropdownMenuItem(value: "agente", child: Text("Aviso agente")),
                              DropdownMenuItem(value: "produccion", child: Text("Producción")),
                              DropdownMenuItem(value: "recibo", child: Text("Recibo")),
                              DropdownMenuItem(value: "gestion", child: Text("Gestión")),
                              DropdownMenuItem(value: "sistema", child: Text("Sistema")),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                tipoSeleccionado = value ?? "agente";
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: prioridadSeleccionada,
                            decoration: _decoracionGestionAgente(
                              "Prioridad",
                              Icons.priority_high_outlined,
                            ),
                            items: const [
                              DropdownMenuItem(value: "normal", child: Text("Normal")),
                              DropdownMenuItem(value: "alta", child: Text("Alta")),
                              DropdownMenuItem(value: "urgente", child: Text("Urgente")),
                            ],
                            onChanged: (value) {
                              setDialogState(() {
                                prioridadSeleccionada = value ?? "normal";
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: enviando ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            label: const Text("Cancelar"),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: enviando
                                ? null
                                : () async {
                                    if (mensajeController.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Escribe un mensaje antes de enviar"),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    setDialogState(() {
                                      enviando = true;
                                    });

                                    try {
                                      await Supabase.instance.client
                                          .from('notificaciones')
                                          .insert({
                                            'titulo': tituloController.text.trim(),
                                            'mensaje': mensajeController.text.trim(),
                                            'tipo': tipoSeleccionado,
                                            'leida': false,
                                            'usuario_email': a['email']?.toString(),
                                            'prioridad': prioridadSeleccionada,
                                            'poliza': null,
                                            'venta_id': null,
                                            'recibo_id': null,
                                          });

                                      Navigator.pop(context);

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Notificación enviada correctamente"),
                                          backgroundColor: Colors.green,
                                        ),
                                      );

                                      setState(() {});
                                    } catch (e) {
                                      setDialogState(() {
                                        enviando = false;
                                      });

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("Error al enviar notificación: $e"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                            icon: enviando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send),
                            label: Text(enviando ? "Enviando..." : "Enviar notificación"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  tituloController.dispose();
  mensajeController.dispose();
}

Widget buildRecibosPage(String tipo) {
  final titulo = switch (tipo) {
    "recibos_cobrados" => "Recibos Cobrados",
    "recibos_devueltos" => "Recibos Devueltos",
    "recibos_pendientes" => "Recibos Pendientes",
    _ => "Todos los Recibos",
  };

  final subtitulo = switch (tipo) {
    "recibos_cobrados" => "Control de recibos cobrados y producción consolidada",
    "recibos_devueltos" => "Seguimiento profesional de devoluciones e incidencias",
    "recibos_pendientes" => "Recibos pendientes de cobro y próximas gestiones",
    _ => "Listado general de recibos",
  };

  final color = switch (tipo) {
    "recibos_cobrados" => Colors.green,
    "recibos_devueltos" => Colors.red,
    "recibos_pendientes" => Colors.orange,
    _ => Colors.blue,
  };

  final icono = switch (tipo) {
    "recibos_cobrados" => Icons.check_circle_rounded,
    "recibos_devueltos" => Icons.cancel_rounded,
    "recibos_pendientes" => Icons.schedule_rounded,
    _ => Icons.receipt_long_rounded,
  };

  return FutureBuilder<List<Map<String, dynamic>>>(
    future: getRecibos(tipo),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final data = snapshot.data!;
      final totalImporte = totalImporteRecibos(data);
      final cobrados = totalDineroRecibosPorEstado(data, "COBRADO");
      final devueltos = totalDineroRecibosPorEstado(data, "DEVUELTO");
      final pendientes = totalDineroRecibosPorEstado(data, "PENDIENTE");

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: color.shade50,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      icono,
                      color: color.shade700,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitulo,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final exportData = await getRecibos(selectedMenu);
                      await exportarExcel(exportData);
                      print("EXPORTAR -> ${exportData.length} RECIBOS");
                    },
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text("Exportar Excel"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _kpiReciboERP(
                  "Total recibos",
                  data.length.toString(),
                  Icons.receipt_long_outlined,
                  Colors.blue,
                ),
                _kpiReciboERP(
                  "Importe total",
                  _formatoEuroKpi(totalImporte),
                  Icons.euro_outlined,
                  Colors.indigo,
                ),
                _kpiReciboERP(
                  "Cobrados",
                  _formatoEuroKpi(cobrados),
                  Icons.check_circle_outline,
                  Colors.green,
                ),
                _kpiReciboERP(
                  "Devueltos",
                  _formatoEuroKpi(devueltos),
                  Icons.cancel_outlined,
                  Colors.red,
                ),
                _kpiReciboERP(
                  "Pendientes",
                  _formatoEuroKpi(pendientes),
                  Icons.schedule_outlined,
                  Colors.orange,
                ),
              ],
            ),

            const SizedBox(height: 16),

            buildRecibosFilters(),

            const SizedBox(height: 16),

            buildRecibosListFiltrado(tipo),

            const SizedBox(height: 40),
          ],
        ),
      );
    },
  );
}
Widget buildRecibosListFiltrado(String tipo) {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: getRecibos(tipo),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return Container(
          height: 350,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        );
      }

      if (snapshot.hasError) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: _decoracionRecibosERP(),
          child: const Text("Error cargando recibos"),
        );
      }

      final recibos = snapshot.data ?? [];

      if (recibos.isEmpty) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(30),
          decoration: _decoracionRecibosERP(),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 54,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                "No hay recibos",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "No se han encontrado recibos con los filtros actuales.",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        );
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _decoracionRecibosERP(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Listado de recibos",
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  "${recibos.length} registros encontrados",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            SizedBox(
  height: 560,
  child: SingleChildScrollView(
    scrollDirection: Axis.vertical,
    child: TablaConScrollHorizontalERP(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 330,
        ),
        child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        Colors.grey.shade100,
                      ),
                      dataRowMinHeight: 62,
                      dataRowMaxHeight: 76,
                      headingRowHeight: 58,
                      columnSpacing: 28,
                      horizontalMargin: 14,
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: Colors.grey.shade200,
                        ),
                      ),
                      columns: const [
                        DataColumn(label: Text("Estado")),
                        DataColumn(label: Text("Fecha")),
                        DataColumn(label: Text("Compañía")),
                        DataColumn(label: Text("Póliza")),
                        DataColumn(label: Text("Cliente")),
                        DataColumn(label: Text("Agente")),
                        DataColumn(label: Text("Importe")),
                        DataColumn(label: Text("Motivo")),
                        DataColumn(label: Text("Acciones")),
                      ],
                      rows: recibos.map((r) {
                        final estado = r['estado']?.toString() ?? '';

                        return DataRow(
                          color: WidgetStateProperty.resolveWith<Color?>(
                            (states) {
                              if (estado.toUpperCase() == "DEVUELTO") {
                                return Colors.red.shade50;
                              }
                              if (estado.toUpperCase() == "PENDIENTE") {
                                return Colors.orange.shade50;
                              }
                              return null;
                            },
                          ),
                          cells: [
                            DataCell(_chipEstadoReciboERP(estado)),
                            DataCell(_textoReciboTabla(r['fecha'])),
                            DataCell(_textoReciboTabla(r['compania'])),
                            DataCell(
                              Text(
                                r['poliza']?.toString() ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataCell(_textoReciboTabla(r['cliente'])),
                            DataCell(_textoReciboTabla(r['agente'])),
                            DataCell(
                              Text(
                                _formatoEuroKpi(r['importe']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataCell(_textoReciboTabla(r['motivo'])),
                            DataCell(
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                tooltip: "Acciones del recibo",
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: "ver",
                                    child: ListTile(
                                      leading: Icon(Icons.visibility_outlined),
                                      title: Text("Ver detalle"),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: "editar",
                                    child: ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text("Editar"),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: "gestionar",
                                    child: ListTile(
                                      leading: Icon(Icons.manage_accounts_outlined),
                                      title: Text("Gestionar"),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: "comentario",
                                    child: ListTile(
                                      leading: Icon(Icons.comment_outlined),
                                      title: Text("Añadir comentario"),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: "notificar",
                                    child: ListTile(
                                      leading: Icon(Icons.notifications_active_outlined),
                                      title: Text("Notificar"),
                                    ),
                                  ),
                                ],
                                onSelected: (value) {
                                  if (value == "ver") {
                                    mostrarDetalleRecibo(r);
                                  } else if (value == "editar") {
                                    mostrarEditarRecibo(r);
                                  } else if (value == "gestionar") {
                                    mostrarGestionRecibo(r);
                                  } else if (value == "comentario") {
                                    mostrarComentarioRecibo(r);
                                  } else if (value == "notificar") {
                                    abrirPantallaNotificacion(context, r);
                                  }
                                },
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                    ),
                  
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
Widget buildRecibosFilters() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: _decoracionRecibosERP(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.filter_alt_outlined),
            SizedBox(width: 8),
            Text(
              "Filtros de recibos",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _dropdownFiltroReciboERP(
              label: "Compañía",
              value: filtroCompania ?? "Todas",
              items: ["Todas", ...listaCompanias],
              onChanged: (value) {
                setState(() {
                  filtroCompania = value == "Todas" ? null : value;
                });
              },
            ),

            _dropdownFiltroReciboERP(
              label: "Estado",
              value: filtroEstado ?? "Todos",
              items: const ["Todos", "COBRADO", "DEVUELTO", "PENDIENTE"],
              onChanged: (value) {
                setState(() {
                  filtroEstado = value == "Todos" ? null : value;
                });
              },
            ),

            _dropdownFiltroReciboERP(
              label: "Agente",
              value: filtroAgente ?? "Todos",
              items: ["Todos", ...listaAgentes],
              onChanged: (value) {
                setState(() {
                  filtroAgente = value == "Todos" ? null : value;
                });
              },
            ),

            _botonFechaReciboERP(
              texto: fechaDesde == null
                  ? "Fecha desde"
                  : fechaDesde.toString().split(" ")[0],
              icono: Icons.calendar_month_outlined,
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  initialDate: DateTime.now(),
                );

                if (date != null) {
                  setState(() {
                    fechaDesde = date;
                  });
                }
              },
            ),

            _botonFechaReciboERP(
              texto: fechaHasta == null
                  ? "Fecha hasta"
                  : fechaHasta.toString().split(" ")[0],
              icono: Icons.event_available_outlined,
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  initialDate: DateTime.now(),
                );

                if (date != null) {
                  setState(() {
                    fechaHasta = date;
                  });
                }
              },
            ),

            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  filtroCompania = null;
                  filtroAgente = null;
                  filtroEstado = null;
                  filtroJefeEquipo = null;
                  fechaDesde = null;
                  fechaHasta = null;
                });
              },
              icon: const Icon(Icons.clear),
              label: const Text("Limpiar filtros"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
Widget _buildFilterBox({
  required String title,
  required Widget child,
}) {
  return SizedBox(
    width: 200,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(14),
          ),
          child: child,
        ),
      ],
    ),
  );
}
BoxDecoration _decoracionRecibosERP() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: Colors.grey.shade300),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.03),
        blurRadius: 14,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

Widget _kpiReciboERP(
  String titulo,
  String valor,
  IconData icono,
  MaterialColor color,
) {
  return Container(
    width: 210,
    padding: const EdgeInsets.all(17),
    decoration: _decoracionRecibosERP(),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icono,
            color: color.shade700,
            size: 27,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _chipEstadoReciboERP(String estado) {
  final estadoUpper = estado.toUpperCase();

  MaterialColor color = Colors.blue;
  IconData icono = Icons.receipt_long_outlined;
  String texto = estadoUpper.isEmpty ? "SIN ESTADO" : estadoUpper;

  if (estadoUpper == "COBRADO") {
    color = Colors.green;
    icono = Icons.check_circle_outline;
  } else if (estadoUpper == "DEVUELTO") {
    color = Colors.red;
    icono = Icons.cancel_outlined;
  } else if (estadoUpper == "PENDIENTE") {
    color = Colors.orange;
    icono = Icons.schedule_outlined;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.shade100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 16, color: color.shade700),
        const SizedBox(width: 6),
        Text(
          texto,
          style: TextStyle(
            color: color.shade800,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

Widget _textoReciboTabla(dynamic valor) {
  final texto = valor?.toString() ?? "";

  return Text(
    texto.isEmpty ? "—" : texto,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

Widget _dropdownFiltroReciboERP({
  required String label,
  required String value,
  required List<String> items,
  required Function(String?) onChanged,
}) {
  final uniqueItems = items.toSet().toList();

  return SizedBox(
    width: 190,
    child: DropdownButtonFormField<String>(
      value: uniqueItems.contains(value) ? value : uniqueItems.first,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      items: uniqueItems.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(
            item,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged,
    ),
  );
}

Widget _botonFechaReciboERP({
  required String texto,
  required IconData icono,
  required VoidCallback onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icono),
    label: Text(texto),
    style: OutlinedButton.styleFrom(
      backgroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}


Widget buildRecibosList() {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: _getRecibos(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return Container(
          height: 300,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        );
      }

      final data = snapshot.data!;

      if (data.isEmpty) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(30),
          decoration: _decoracionRecibosERP(),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 54,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              const Text(
                "No hay recibos",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "No se han encontrado recibos con los filtros actuales.",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        );
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _decoracionRecibosERP(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Últimos recibos",
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 14),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = data[i];
                final estado = item['estado']?.toString() ?? '';

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      _chipEstadoReciboERP(estado),

                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['cliente']?.toString().isEmpty ?? true
                                  ? "Cliente sin nombre"
                                  : item['cliente'].toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Póliza: ${item['poliza'] ?? 'Sin póliza'} · ${item['compania'] ?? 'Sin compañía'}",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 14),

                      Text(
                        _formatoEuroKpi(item['importe']),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),

                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: "ver",
                            child: Text("Ver detalle"),
                          ),
                          PopupMenuItem(
                            value: "editar",
                            child: Text("Editar"),
                          ),
                          PopupMenuItem(
                            value: "gestionar",
                            child: Text("Gestionar"),
                          ),
                          PopupMenuItem(
                            value: "comentario",
                            child: Text("Añadir comentario"),
                          ),
                          PopupMenuItem(
                            value: "notificar",
                            child: Text("Notificar"),
                          ),
                        ],
                        onSelected: (value) {
                          if (value == "ver") {
                            mostrarDetalleRecibo(item);
                          } else if (value == "editar") {
                            mostrarEditarRecibo(item);
                          } else if (value == "gestionar") {
                            mostrarGestionRecibo(item);
                          } else if (value == "comentario") {
                            mostrarComentarioRecibo(item);
                          } else if (value == "notificar") {
                            abrirPantallaNotificacion(context, item);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );
}
Widget buildCargarRecibos() {
  return SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const Text(
          "Cargar Recibos",
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 30),

        Row(
          children: [

            Expanded(
              child: _actionCard(
                Icons.edit_note,
                "Carga Manual",
                "Introducir recibos uno a uno",
              ),
            ),

            const SizedBox(width: 20),

            Expanded(
              child: _actionCard(
                Icons.file_upload,
                "Importar Excel",
                "Subir CSV o Excel",
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          children: [

            Expanded(
              child: _actionCard(
                Icons.cloud_upload,
                "Carga Masiva",
                "Miles de recibos a la vez",
              ),
            ),

            const Spacer(),
          ],
        ),

        const SizedBox(height: 40),

        const Text(
          "Últimos archivos cargados",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 20),

        if (modoCarga == "Importar Excel")
  buildImportadorExcel(),

  if (modoCarga == "Carga Manual")
  Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [

        TextField(
          controller: polizaCtrl,
          decoration: const InputDecoration(labelText: "Póliza"),
        ),

        TextField(
          controller: clienteCtrl,
          decoration: const InputDecoration(labelText: "Cliente"),
        ),

        TextField(
          controller: importeCtrl,
          decoration: const InputDecoration(labelText: "Importe"),
        ),

        TextField(
          controller: companiaCtrl,
          decoration: const InputDecoration(labelText: "Compañía"),
        ),

        TextField(
          controller: estadoCtrl,
          decoration: const InputDecoration(labelText: "Estado"),
        ),

        TextField(
          controller: fechaCtrl,
          decoration: const InputDecoration(labelText: "Fecha"),
        ),

        const SizedBox(height: 20),

        ElevatedButton(
          onPressed: insertarManual,
          child: const Text("GUARDAR RECIBO"),
        ),

      ],
    ),
  ),

  if (headers.isNotEmpty)
  buildColumnMapper(),

        Container(
          height: 300,
          width: double.infinity,

          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.grey.shade300,
            ),
            borderRadius: BorderRadius.circular(12),
          ),

          child: const Center(
            child: Text(
              "Aquí aparecerán los archivos importados",
            ),
          ),
        ),
      ],
    ),
  );
}
Widget _actionCard(
  IconData icon,
  String title,
  String subtitle,
) {
  return InkWell(
    onTap: () {
  setState(() {
    modoCarga = title;
  });
},

    child: Container(
      height: 170,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [

          Icon(
            icon,
            size: 50,
            color: Colors.blue,
          ),

          const SizedBox(height: 15),

          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.grey,
            ),
          ),
        ],
      ),
    ),
  );
}
Widget buildImportadorExcel() {
  return Container(
    margin: const EdgeInsets.only(top: 20),

    padding: const EdgeInsets.all(25),

    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: Colors.grey.shade300,
      ),
    ),

    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const Text(
          "Importación de Excel",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 20),

        Container(
          height: 200,
          width: double.infinity,

          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: Colors.grey.shade400,
              width: 2,
            ),
          ),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              Icon(
                Icons.upload_file,
                size: 70,
                color: Colors.blue.shade700,
              ),

              const SizedBox(height: 15),

              const Text(
                "Arrastra aquí el Excel",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              ElevatedButton.icon(
                onPressed: seleccionarExcel,
                icon: const Icon(Icons.folder_open),
                label: const Text("Seleccionar archivo"),
              ),
            ],
          ),
        ),

        const SizedBox(height: 25),

        const Text(
          "Previsualización",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),

        const SizedBox(height: 10),

        Container(
  height: 250,
  decoration: BoxDecoration(
    border: Border.all(
      color: Colors.grey.shade300,
    ),
    borderRadius: BorderRadius.circular(12),
  ),
  child: excelPreview.isEmpty
      ? const Center(
          child: Text(
            "Aquí se mostrarán las filas del Excel",
          ),
        )
      : SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: excelPreview.first
                .map(
                  (e) => DataColumn(
                    label: Text(e.toString()),
                  ),
                )
                .toList(),
            rows: excelPreview
                .skip(1)
                .map(
                  (row) => DataRow(
                    cells: row
                        .map(
                          (cell) => DataCell(
                            Text(cell.toString()),
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        ),
),
const SizedBox(height: 20),

ElevatedButton(
  onPressed: isImporting ? null : importarMasivoASupabase,
  child: Text(
    isImporting ? "IMPORTANDO..." : "IMPORTACIÓN MASIVA",
  ),
),

const SizedBox(height: 10),

if (isImporting)
  Text(
    "Progreso: $importProgress / $importTotal",
    style: const TextStyle(fontWeight: FontWeight.bold),
  ),
      ],
    ),
  );
}
Widget buildColumnMapper() {
ElevatedButton(
  onPressed: autoDetectMapping,
  child: const Text("AUTO-MAPEAR COLUMNAS"),
);

  return Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "MAPEO DE COLUMNAS",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 15),

        ...headers.map((header) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    header,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                Expanded(
                  flex: 3,
                  child: DropdownButton<String>(
                    value: columnMapping[header],
                    isExpanded: true,
                    hint: const Text("No mapear"),
                    items: [
                      "poliza",
                      "cliente",
                      "importe",
                      "compania",
                      "estado",
                      "fecha",
                    ].map((field) {
                      return DropdownMenuItem(
                        value: field,
                        child: Text(field),
                      );
                    }).toList(),
                    onChanged: (value) {
  setState(() {
    columnMapping[header.trim().toUpperCase()] = value!;
  });
},
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    ),
  );
}
void autoDetectMapping() {
  columnMapping.clear();

  for (final header in headers) {
    final normalized = header.toLowerCase().trim();

    for (final key in autoMap.keys) {
      if (normalized.contains(key)) {
        columnMapping[header] = autoMap[key]!;
        break;
      }
    }
  }

  setState(() {});
}
Widget buildDashboardKpis() {
  return FutureBuilder<Map<String, dynamic>>(
    future: obtenerKpisDashboard(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final k = snapshot.data!;

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _kpiDashboardERP(
              icono: Icons.bar_chart_rounded,
              titulo: "Producción Total",
              valor: _formatoEuroKpi(k['produccionActual']),
              porcentaje: _formatoPorcentajeKpi(k['produccionPorcentaje']),
              color: Colors.blue,
            ),
            const SizedBox(width: 14),

            _kpiDashboardERP(
              icono: Icons.shopping_cart_checkout_rounded,
              titulo: "Ventas Totales",
              valor: k['ventasActual'].toString(),
              porcentaje: _formatoPorcentajeKpi(k['ventasPorcentaje']),
              color: Colors.indigo,
            ),
            const SizedBox(width: 14),

            _kpiDashboardERP(
              icono: Icons.check_circle_rounded,
              titulo: "Recibos Cobrados",
              valor: _formatoEuroKpi(k['cobradosActual']),
              porcentaje: _formatoPorcentajeKpi(k['cobradosPorcentaje']),
              color: Colors.green,
            ),
            const SizedBox(width: 14),

            _kpiDashboardERP(
              icono: Icons.cancel_rounded,
              titulo: "Recibos Devueltos",
              valor: _formatoEuroKpi(k['devueltosActual']),
              porcentaje: _formatoPorcentajeKpi(k['devueltosPorcentaje']),
              color: Colors.red,
            ),
          ],
        ),
      );
    },
  );
}
Widget buildDashboardPageERP() {
  return FutureBuilder<Map<String, dynamic>>(
    future: obtenerKpisDashboard(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final k = snapshot.data!;

      final produccion = _toDoubleKpi(k['produccionActual']);
      final ventas = k['ventasActual'] ?? 0;
      final cobrados = _toDoubleKpi(k['cobradosActual']);
      final devueltos = _toDoubleKpi(k['devueltosActual']);
      final primaBrutaEmitida = _toDoubleKpi(k['primaBrutaEmitida']);

     
final porcentajeDevolucion =
    primaBrutaEmitida == 0
        ? 0
        : (devueltos / primaBrutaEmitida) * 100;

      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade800,
                    Colors.indigo.shade700,
                  ],
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Dashboard Ejecutivo",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Centro de mando mensual de SafeBrok",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.auto_graph_rounded,
                    color: Colors.white.withOpacity(0.9),
                    size: 50,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            buildDashboardKpis(),

            const SizedBox(height: 20),

            _panelDashboardERP(
              titulo: "Salud del negocio",
              icono: Icons.health_and_safety_outlined,
              color: porcentajeDevolucion >= 15
                  ? Colors.red
                  : porcentajeDevolucion >= 8
                      ? Colors.orange
                      : Colors.green,
              child: Column(
                children: [
                 _lineaDashboardERP(
  "Prima bruta emitida",
  _formatoEuroKpi(primaBrutaEmitida),
),
                  _lineaDashboardERP("Ventas emitidas", ventas.toString()),
                  _lineaDashboardERP("Recibos cobrados", _formatoEuroKpi(cobrados)),
                  _lineaDashboardERP("Recibos devueltos", _formatoEuroKpi(devueltos)),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Ratio devolución: ${porcentajeDevolucion.toStringAsFixed(1)}%",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (porcentajeDevolucion / 30).clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            _panelDashboardERP(
              titulo: "Alertas inteligentes",
              icono: Icons.notifications_active_outlined,
              color: Colors.orange,
              child: Column(
                children: [
                  if (devueltos > 0)
                    _alertaDashboardERP(
                      "Recibos devueltos detectados",
                      "Hay ${_formatoEuroKpi(devueltos)} en recibos devueltos este mes.",
                      Colors.red,
                      Icons.warning_amber_rounded,
                    )
                  else
                    _alertaDashboardERP(
                      "Todo bajo control",
                      "No hay recibos devueltos detectados este mes.",
                      Colors.green,
                      Icons.check_circle_outline,
                    ),

                  if (ventas == 0)
                    _alertaDashboardERP(
                      "Sin ventas este mes",
                      "Todavía no hay ventas registradas en el mes actual.",
                      Colors.blueGrey,
                      Icons.info_outline,
                    ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            _panelDashboardERP(
              titulo: "Acciones rápidas",
              icono: Icons.flash_on_outlined,
              color: Colors.blue,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _botonDashboardERP(
                    "Ventas",
                    Icons.euro_outlined,
                    Colors.blue,
                    () {
                      setState(() {
                        selectedMenu = "ventas";
                      });
                    },
                  ),
                  _botonDashboardERP(
                    "Cargar recibos",
                    Icons.upload_file,
                    Colors.indigo,
                    () {
                      setState(() {
                        selectedMenu = "cargar_recibos";
                      });
                    },
                  ),
                  _botonDashboardERP(
                    "Devueltos",
                    Icons.cancel_outlined,
                    Colors.red,
                    () {
                      setState(() {
                        selectedMenu = "recibos_devueltos";
                      });
                      cargarRecibos();
                    },
                  ),
                  _botonDashboardERP(
                    "Pendientes",
                    Icons.schedule_outlined,
                    Colors.orange,
                    () {
                      setState(() {
                        selectedMenu = "recibos_pendientes";
                      });
                      cargarRecibos();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
Widget _panelDashboardERP({
  required String titulo,
  required IconData icono,
  required MaterialColor color,
  required Widget child,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, color: color.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

Widget _lineaDashboardERP(String titulo, String valor) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          valor,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}

Widget _alertaDashboardERP(
  String titulo,
  String texto,
  MaterialColor color,
  IconData icono,
) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.shade100),
    ),
    child: Row(
      children: [
        Icon(icono, color: color.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(
                texto,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _botonDashboardERP(
  String texto,
  IconData icono,
  MaterialColor color,
  VoidCallback onTap,
) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: 165,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        children: [
          Icon(icono, color: color.shade700, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _kpiDashboardERP({
  required IconData icono,
  required String titulo,
  required String valor,
  required String porcentaje,
  required MaterialColor color,
}) {
  final esNegativo = porcentaje.startsWith('-');

  return Container(
    width: 250,
    height: 170,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.grey.shade300),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icono,
                color: color.shade700,
                size: 25,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: esNegativo ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                porcentaje,
                style: TextStyle(
                  color: esNegativo ? Colors.red.shade700 : Colors.green.shade700,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        Text(
          titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          "vs mes anterior",
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

Widget _panelDashboardSimple({
  required String titulo,
  required IconData icono,
  required MaterialColor color,
  required List<Widget> children,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.grey.shade300),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icono,
                color: color.shade700,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    ),
  );
}

Widget _lineaDashboardSimple(String titulo, String valor) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          valor,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

Widget _alertaDashboardSimple(
  String titulo,
  String texto,
  MaterialColor color,
  IconData icono,
) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.shade100),
    ),
    child: Row(
      children: [
        Icon(icono, color: color.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                texto,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _botonDashboardSimple(
  String texto,
  IconData icono,
  MaterialColor color,
  VoidCallback onTap,
) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        children: [
          Icon(icono, color: color.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget buildKpiCard(
  IconData icon,
  String titulo,
  String valor,
  String porcentaje,
  MaterialColor color,
) {
  final esNegativo = porcentaje.startsWith('-');

  return Container(
    width: 270,
    constraints: const BoxConstraints(
      minHeight: 185,
    ),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 28,
                color: color.shade700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: esNegativo ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: esNegativo ? Colors.red.shade100 : Colors.green.shade100,
                ),
              ),
              child: Text(
                porcentaje,
                style: TextStyle(
                  color: esNegativo ? Colors.red.shade700 : Colors.green.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Text(
          titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          valor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          "Mes actual vs mes anterior",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    ),
  );
}
Future<Map<String, dynamic>> obtenerKpisDashboard() async {
  try {
    final supabase = Supabase.instance.client;

    final ahora = DateTime.now();

    final inicioMesActual = DateTime(ahora.year, ahora.month, 1);
    final inicioMesSiguiente = DateTime(ahora.year, ahora.month + 1, 1);
    final inicioMesAnterior = DateTime(ahora.year, ahora.month - 1, 1);

    dynamic ventasQuery = supabase.from('ventas').select();

    if (!veTodoERP) {
      if (authIdsPermitidosERP.isEmpty) {
        return _kpisDashboardVacios();
      }

      ventasQuery = ventasQuery.inFilter(
        'agente_auth_id',
        authIdsPermitidosERP,
      );
    }

    final ventasResponse = await ventasQuery;
    final ventas = List<Map<String, dynamic>>.from(ventasResponse);

    final ventasMesActual = ventas.where((v) {
      final fecha = _leerFechaKpi(v['fecha_efecto']);

      return fecha != null &&
          !fecha.isBefore(inicioMesActual) &&
          fecha.isBefore(inicioMesSiguiente);
    }).toList();

    final ventasMesAnterior = ventas.where((v) {
      final fecha = _leerFechaKpi(v['fecha_efecto']);

      return fecha != null &&
          !fecha.isBefore(inicioMesAnterior) &&
          fecha.isBefore(inicioMesActual);
    }).toList();

    double calcularPrima(Map<String, dynamic> v) {
      return _toDoubleKpi(
        v['prima_anual_neta'] ??
            v['prima_neta'] ??
            v['prima_anual'] ??
            v['prima_anual_bruta'] ??
            v['precio'] ??
            0,
      );
    }

    final produccionActual = ventasMesActual.fold<double>(
      0,
      (suma, v) => suma + calcularPrima(v),
    );

    final produccionAnterior = ventasMesAnterior.fold<double>(
      0,
      (suma, v) => suma + calcularPrima(v),
    );

    final ventasActual = ventasMesActual.length;
    final ventasAnterior = ventasMesAnterior.length;

    final polizasMesActual = ventasMesActual
        .map((v) => v['numero_poliza']?.toString() ?? '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    final polizasMesAnterior = ventasMesAnterior
        .map((v) => v['numero_poliza']?.toString() ?? '')
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList();

    Future<List<Map<String, dynamic>>> cargarRecibosPorPolizas(
      List<String> polizas,
    ) async {
      if (polizas.isEmpty) return [];

      final response = await supabase
          .from('recibos')
          .select()
          .inFilter('poliza', polizas);

      return List<Map<String, dynamic>>.from(response);
    }

    final recibosMesActual = await cargarRecibosPorPolizas(polizasMesActual);
    final recibosMesAnterior =
        await cargarRecibosPorPolizas(polizasMesAnterior);

    final cobradosActual = recibosMesActual.where((r) {
      final estado = '${r['estado'] ?? r['gestion'] ?? ''}'.toUpperCase();
      return estado.contains('COBRADO');
    }).fold<double>(
      0,
      (suma, r) => suma + _importeReciboKpi(r),
    );

    final cobradosAnterior = recibosMesAnterior.where((r) {
      final estado = '${r['estado'] ?? r['gestion'] ?? ''}'.toUpperCase();
      return estado.contains('COBRADO');
    }).fold<double>(
      0,
      (suma, r) => suma + _importeReciboKpi(r),
    );

    final devueltosActual = recibosMesActual.where((r) {
      final estado = '${r['estado'] ?? r['gestion'] ?? ''}'.toUpperCase();
      return estado.contains('DEVUELTO');
    }).fold<double>(
      0,
      (suma, r) => suma + _importeReciboKpi(r),
    );

    final devueltosAnterior = recibosMesAnterior.where((r) {
      final estado = '${r['estado'] ?? r['gestion'] ?? ''}'.toUpperCase();
      return estado.contains('DEVUELTO');
    }).fold<double>(
      0,
      (suma, r) => suma + _importeReciboKpi(r),
    );

    final primaBrutaEmitida = ventasMesActual.fold<double>(
      0,
      (suma, v) =>
          suma +
          _toDoubleKpi(
            v['prima_anual_bruta'] ??
                v['prima_anual'] ??
                v['prima_anual_neta'] ??
                v['precio'] ??
                0,
          ),
    );

    print("KPIS ERP MES ACTUAL -> ventas: ${ventasMesActual.length}");
    print("KPIS ERP MES ACTUAL -> produccion: $produccionActual");
    print("KPIS ERP MES ACTUAL -> recibos: ${recibosMesActual.length}");

    return {
      'produccionActual': produccionActual,
      'produccionPorcentaje': _calcularPorcentajeKpi(
        produccionActual,
        produccionAnterior,
      ),
      'ventasActual': ventasActual,
      'ventasPorcentaje': _calcularPorcentajeKpi(
        ventasActual.toDouble(),
        ventasAnterior.toDouble(),
      ),
      'cobradosActual': cobradosActual,
      'cobradosPorcentaje': _calcularPorcentajeKpi(
        cobradosActual,
        cobradosAnterior,
      ),
      'devueltosActual': devueltosActual,
      'devueltosPorcentaje': _calcularPorcentajeKpi(
        devueltosActual,
        devueltosAnterior,
      ),
      'primaBrutaEmitida': primaBrutaEmitida,
    };
  } catch (e) {
    print("❌ ERROR obtenerKpisDashboard: $e");
    return _kpisDashboardVacios();
  }
}
Map<String, dynamic> _kpisDashboardVacios() {
  return {
    'produccionActual': 0,
    'produccionPorcentaje': 0,
    'ventasActual': 0,
    'ventasPorcentaje': 0,
    'cobradosActual': 0,
    'cobradosPorcentaje': 0,
    'devueltosActual': 0,
    'devueltosPorcentaje': 0,
    'primaBrutaEmitida': 0,
  };
}

DateTime? _leerFechaKpi(dynamic valor) {
  if (valor == null) return null;

  final texto = valor.toString();

  if (texto.contains('/')) {
    final partes = texto.split('/');
    if (partes.length == 3) {
      return DateTime.tryParse(
        '${partes[2]}-${partes[1].padLeft(2, '0')}-${partes[0].padLeft(2, '0')}',
      );
    }
  }

  return DateTime.tryParse(texto);
}

double _toDoubleKpi(dynamic valor) {
  if (valor == null) return 0;

  return double.tryParse(
        valor.toString().replaceAll(',', '.'),
      ) ??
      0;
}

double _importeReciboKpi(Map<String, dynamic> r) {
  return _toDoubleKpi(
    r['importe'] ??
    r['precio'] ??
    r['cantidad'] ??
    r['prima'] ??
    r['total'],
  );
}

double _calcularPorcentajeKpi(double actual, double anterior) {
  if (anterior == 0 && actual == 0) return 0;
  if (anterior == 0 && actual > 0) return 100;

  return ((actual - anterior) / anterior) * 100;
}

String _formatoPorcentajeKpi(dynamic valor) {
  final numero = _toDoubleKpi(valor);
  final signo = numero > 0 ? '+' : '';

  return '$signo${numero.toStringAsFixed(1)}%';
}

String _formatoEuroKpi(dynamic valor) {
  final numero = _toDoubleKpi(valor);
  return '${numero.toStringAsFixed(2)} €';
}
void mostrarDetalleRecibo(Map<String, dynamic> recibo) {
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: 900,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // HEADER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Detalle del Recibo",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    )
                  ],
                ),

                const SizedBox(height: 20),

                // RECIBO
                _buildSectionTitle("🧾 Recibo"),
                _buildDetail("Póliza", recibo['poliza']),
                _buildDetail("Estado", recibo['estado']),
                _buildDetail("Importe", recibo['importe']),
                _buildDetail("Fecha", recibo['fecha']),
                _buildDetail("Motivo", recibo['motivo']),

                const SizedBox(height: 20),

                // CLIENTE (vinculado por póliza)
                _buildSectionTitle("👤 Cliente"),
                FutureBuilder<Map<String, dynamic>?>(
                  future: getClientePorPoliza(recibo['poliza']),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }

                    final cliente = snapshot.data;

                    if (cliente == null) {
                      return const Text("Cliente no encontrado");
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetail("Nombre", cliente['nombre']),
                        _buildDetail("DNI", cliente['dni']),
                        _buildDetail("Teléfono", cliente['telefono']),
                        _buildDetail("Email", cliente['email']),
                        _buildDetail("Dirección", cliente['direccion']),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 20),

                // AGENTE
                _buildSectionTitle("🏢 Agente"),
                _buildDetail("Agente", recibo['agente']),
                _buildDetail("Compañía", recibo['compania']),

                const SizedBox(height: 20),

_buildSectionTitle("💬 Comentarios"),
FutureBuilder<List<Map<String, dynamic>>>(
  future: getComentarios(recibo['poliza']),
  builder: (context, snapshot) {

    if (!snapshot.hasData) {
      return const CircularProgressIndicator();
    }

    final comentarios = snapshot.data!;

    if (comentarios.isEmpty) {
      return const Text("Sin comentarios");
    }

    return Column(
      children: comentarios.map((c) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c['comentario'] ?? ''),

              const SizedBox(height: 5),
              Text(
                c['created_at'] ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        );
      }).toList(),
    );
  },
),

const SizedBox(height: 20),

_buildSectionTitle("💳 Historial de pagos"),

FutureBuilder<List<Map<String, dynamic>>>(
  future: getPagos(recibo['poliza']),
  builder: (context, snapshot) {

    if (!snapshot.hasData) {
      return const CircularProgressIndicator();
    }

    final pagos = snapshot.data!;

    if (pagos.isEmpty) {
      return const Text("Sin pagos registrados");
    }

    return Column(
      children: pagos.map((p) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Método: ${p['metodo']}"),
                  Text("Estado: ${p['estado']}"),
                  Text(
  p['created_at'] != null
      ? "Fecha: ${DateTime.parse(p['created_at']).toLocal().toString().split('.')[0]}"
      : "Fecha: sin fecha",
  style: const TextStyle(fontSize: 12, color: Colors.grey),
),

                ],
              ),
              Text("${p['importe']} €"),

            ],

          ),
        );
      }).toList(),
    );
  },
),

              ],
            ),
          ),
        ),
      );
    },
  );
}
Future<Map<String, dynamic>?> getClientePorPoliza(String poliza) async {
  final response = await Supabase.instance.client
      .from('clientes')
      .select()
      .eq('poliza', poliza)
      .maybeSingle();

  return response;
}
Widget _buildSectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

Widget _buildDetail(String label, dynamic value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            "$label:",
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(value?.toString() ?? ''),
        ),
      ],
    ),
  );
}
void mostrarEditarRecibo(Map<String, dynamic> recibo) {
  final estadoController = TextEditingController(text: recibo['estado']);
  final importeController = TextEditingController(text: recibo['importe'].toString());
  final motivoController = TextEditingController(text: recibo['motivo']);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Editar Recibo"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              TextField(
                controller: estadoController,
                decoration: const InputDecoration(labelText: "Estado"),
              ),

              TextField(
                controller: importeController,
                decoration: const InputDecoration(labelText: "Importe"),
                keyboardType: TextInputType.number,
              ),

              TextField(
                controller: motivoController,
                decoration: const InputDecoration(labelText: "Motivo"),
              ),
            ],
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),

          ElevatedButton(
            onPressed: () async {
              await Supabase.instance.client
                  .from('recibos')
                  .update({
                    'estado': estadoController.text,
                    'importe': double.tryParse(importeController.text) ?? 0,
                    'motivo': motivoController.text,
                  })
                  .eq('poliza', recibo['poliza']);

              Navigator.pop(context);

              setState(() {});

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Recibo actualizado")),
              );
            },
            child: const Text("Guardar"),
          ),
        ],
      );
    },
  );
}
void mostrarComentarioRecibo(Map<String, dynamic> recibo) {

  final controller = TextEditingController();

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Añadir comentario"),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: "Escribe el comentario...",
          ),
        ),
        actions: [

          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),

          ElevatedButton(
            onPressed: () async {

              await Supabase.instance.client
                  .from('recibos_comentarios')
                  .insert({
                    'poliza': recibo['poliza'],
                    'comentario': controller.text,
                    'usuario': 'admin',
                  });

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Comentario guardado"),
                ),
              );
            },
            child: const Text("Guardar"),
          ),
        ],
      );
    },
  );

}
Future<List<Map<String, dynamic>>> getComentarios(String poliza) async {
  final response = await Supabase.instance.client
      .from('recibos_comentarios')
      .select()
      .eq('poliza', poliza)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(response);
}
void mostrarGestionRecibo(Map<String, dynamic> recibo) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Gestionar Recibo"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

           ListTile(
              leading: const Icon(Icons.account_balance),
              title: const Text("Enviar a banco"),
              enabled: false,
            ),

            ListTile(
              leading: const Icon(Icons.credit_card),
              title: const Text("Pago TPV / Tarjeta"),
              onTap: () {
                Navigator.pop(context);
                abrirPasarelaTPV(recibo);
              },
            ),

           ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text("Transferencia"),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Próximamente"),
                  ),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text("Dar de baja"),
              onTap: () async {
                await actualizarEstadoRecibo(recibo, "baja");
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    },
  );
}
Future<void> actualizarEstadoRecibo(
  Map<String, dynamic> recibo,
  String estado,
) async {
  await Supabase.instance.client
      .from('recibos')
      .update({
        'estado': estado,
      })
      .eq('poliza', recibo['poliza']);

  setState(() {});
}
void abrirPasarelaTPV(Map<String, dynamic> recibo) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Pago TPV"),
        content: Text(
          "Total a pagar: ${recibo['importe']} €",
        ),
        actions: [
                  ElevatedButton(
            onPressed: () async {

              Navigator.pop(context);

              // 🔥 simulamos pago exitoso
              await Future.delayed(const Duration(seconds: 2));

              await Supabase.instance.client.from('recibos_pagos').insert({
  'poliza': recibo['poliza'],
  'importe': recibo['importe'],
  'metodo': 'tpv',
  'estado': 'ok',
  'created_at': DateTime.now().toIso8601String(),
});

              await actualizarEstadoRecibo(recibo, "COBRADO");

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Pago realizado correctamente"),
                ),
              );
            },
            child: const Text("Pagar ahora"),
          ),
                    TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
        ],
      );
    },
  );
}
Future<List<Map<String, dynamic>>> getPagos(String poliza) async {
  final response = await Supabase.instance.client
      .from('recibos_pagos')
      .select()
      .eq('poliza', poliza)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(response);
}
void abrirPantallaNotificacion(
  BuildContext context,
  Map<String, dynamic> recibo,
) {
  final TextEditingController comentarioController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Notificar póliza"),

        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 👇 AGENTE AUTOMÁTICO
            FutureBuilder(
              future: Supabase.instance.client
                  .from('agentes')
                  .select()
                  .eq('poliza', recibo['poliza'])
                  .single(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                final agente = snapshot.data as Map<String, dynamic>;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Agente: ${agente['nombre']}"),
                    Text("Email: ${agente['email']}"),

                    const SizedBox(height: 10),

                    Text(
                      "Jefe equipo: ${agente['parent_id']}",
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 15),

            TextField(
              controller: comentarioController,
              decoration: const InputDecoration(
                labelText: "Comentario (opcional)",
              ),
              maxLines: 3,
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),

          ElevatedButton(
            onPressed: () async {
              final comentario = comentarioController.text;

              // 🔥 INSERT NOTIFICACIÓN
              await Supabase.instance.client.from('notificaciones').insert({
                'poliza': recibo['poliza'],
                'agente_id': recibo['agente'],
                'comentario': comentario,
                'leido_agente': false,
                'leido_jefe': false,
                'created_at': DateTime.now().toIso8601String(),
              });

              Navigator.pop(context);
            },
            child: const Text("Enviar"),
          ),
        ],
      );
    },
  );
}
Widget buildClientesPage() {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: getClientes(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }

      if (snapshot.hasError) {
        return Center(
          child: Text(
            "Error cargando clientes: ${snapshot.error}",
            style: const TextStyle(color: Colors.red),
          ),
        );
      }

      final clientes = filtrarClientes(snapshot.data ?? []);

      final totalClientes = clientes.length;

      final conTelefono = clientes.where((c) {
        return (c['telefono']?.toString().trim() ?? '').isNotEmpty;
      }).length;

      final conEmail = clientes.where((c) {
        return (c['email']?.toString().trim() ?? '').isNotEmpty;
      }).length;

      final conPoliza = clientes.where((c) {
        return (c['compania']?.toString().trim() ?? '').isNotEmpty;
      }).length;

      final provincias = clientes
          .map((c) => c['provincia']?.toString().trim() ?? '')
          .where((p) => p.isNotEmpty)
          .toSet()
          .length;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.people_alt_outlined,
                      color: Colors.blue.shade700,
                      size: 36,
                    ),
                  ),

                  const SizedBox(width: 16),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Clientes",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          "Panel profesional de clientes, pólizas, recibos y gestiones",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                  ElevatedButton.icon(
                    onPressed: () async {
                      await exportClientes(clientes);
                    },
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text("Exportar Excel"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _kpiAgenteERP(
                  "Clientes",
                  totalClientes.toString(),
                  Icons.people_alt_outlined,
                  Colors.blue,
                ),
                _kpiAgenteERP(
                  "Con teléfono",
                  conTelefono.toString(),
                  Icons.phone_android_outlined,
                  Colors.green,
                ),
                _kpiAgenteERP(
                  "Con email",
                  conEmail.toString(),
                  Icons.email_outlined,
                  Colors.indigo,
                ),
                _kpiAgenteERP(
                  "Con póliza",
                  conPoliza.toString(),
                  Icons.description_outlined,
                  Colors.orange,
                ),
                _kpiAgenteERP(
                  "Provincias",
                  provincias.toString(),
                  Icons.map_outlined,
                  Colors.deepPurple,
                ),
              ],
            ),

            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.035),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Filtros de clientes",
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildFilterBox(
                        title: "Agente",
                        child: SizedBox(
                          width: 190,
                          child: DropdownButton<String>(
                            value: filtroAgente,
                            isExpanded: true,
                            hint: const Text("Todos"),
                            items: listaAgentes.map((agente) {
                              return DropdownMenuItem(
                                value: agente,
                                child: Text(
                                  agente,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                filtroAgente = value;
                              });
                            },
                          ),
                        ),
                      ),

                      _buildFilterBox(
                        title: "Jefe Equipo",
                        child: SizedBox(
                          width: 190,
                          child: DropdownButton<String>(
                            value: filtroJefeEquipo,
                            isExpanded: true,
                            hint: const Text("Todos"),
                            items: listaJefes.map((jefe) {
                              return DropdownMenuItem(
                                value: jefe,
                                child: Text(
                                  jefe,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                filtroJefeEquipo = value;
                              });
                            },
                          ),
                        ),
                      ),

                      _buildFilterBox(
                        title: "Compañía",
                        child: SizedBox(
                          width: 190,
                          child: DropdownButton<String>(
                            value: filtroCompania,
                            isExpanded: true,
                            hint: const Text("Todas"),
                            items: listaCompanias.map((compania) {
                              return DropdownMenuItem(
                                value: compania,
                                child: Text(
                                  compania,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                filtroCompania = value;
                              });
                            },
                          ),
                        ),
                      ),

                      _buildFilterBox(
                        title: "Fecha desde",
                        child: TextButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              initialDate: DateTime.now(),
                            );

                            if (date != null) {
                              setState(() {
                                fechaDesde = date;
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            fechaDesde == null
                                ? "Seleccionar"
                                : fechaDesde.toString().split(" ")[0],
                          ),
                        ),
                      ),

                      _buildFilterBox(
                        title: "Fecha hasta",
                        child: TextButton.icon(
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              initialDate: DateTime.now(),
                            );

                            if (date != null) {
                              setState(() {
                                fechaHasta = date;
                              });
                            }
                          },
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(
                            fechaHasta == null
                                ? "Seleccionar"
                                : fechaHasta.toString().split(" ")[0],
                          ),
                        ),
                      ),

                      SizedBox(
                        height: 62,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              filtroAgente = null;
                              filtroJefeEquipo = null;
                              filtroCompania = null;
                              fechaDesde = null;
                              fechaHasta = null;
                            });
                          },
                          icon: const Icon(Icons.clear),
                          label: const Text("Limpiar filtros"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.035),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "Listado profesional de clientes",
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        "${clientes.length} registros",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  if (clientes.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 54,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "No hay clientes para mostrar",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Revisa los filtros o la estructura de permisos del usuario.",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  else
                    TablaConScrollHorizontalERP(
  child: DataTable(
                        columnSpacing: 22,
                        horizontalMargin: 12,
                        dataRowMinHeight: 64,
                        dataRowMaxHeight: 72,
                        headingRowHeight: 58,
                        headingRowColor: WidgetStateProperty.all(
                          Colors.grey.shade100,
                        ),
                        columns: const [
                          DataColumn(label: Text("Cliente")),
                          DataColumn(label: Text("Contacto")),
                          DataColumn(label: Text("Ubicación")),
                          DataColumn(label: Text("Agente")),
                          DataColumn(label: Text("Jefe")),
                          DataColumn(label: Text("Compañía")),
                          DataColumn(label: Text("Fecha")),
                          DataColumn(label: Text("Acciones")),
                        ],
                        rows: clientes.map((c) {
                          final nombreCompleto =
                              "${c['nombre'] ?? ''} ${c['apellidos'] ?? ''}"
                                  .trim();

                          return DataRow(
                            cells: [
                              DataCell(
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.blue.shade50,
                                      child: Icon(
                                        Icons.person_outline,
                                        color: Colors.blue.shade700,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 210,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nombreCompleto.isEmpty
                                                ? "Cliente sin nombre"
                                                : nombreCompleto,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            c['dni']?.toString() ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              DataCell(
                                SizedBox(
                                  width: 190,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c['telefono']?.toString() ?? '—',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        c['email']?.toString() ?? '—',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c['poblacion']?.toString() ?? '—',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        "${c['provincia'] ?? ''} ${c['codigo_postal'] ?? ''}"
                                            .trim(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              DataCell(
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    c['agente_nombre']?.toString() ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),

                              DataCell(
                                SizedBox(
                                  width: 180,
                                  child: Text(
                                    c['jefe_nombre']?.toString() ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),

                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    c['compania']?.toString() ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.indigo.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),

                              DataCell(
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    c['created_at']
                                            ?.toString()
                                            .split('T')
                                            .first ??
                                        '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),

                              DataCell(
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert),
                                  onSelected: (value) {
                                    if (value == 'detalle') {
                                      mostrarDetalleCliente(c);
                                    }

                                    if (value == 'editar') {
                                      editarCliente(c);
                                    }

                                    if (value == 'polizas') {
                                      verPolizasCliente(c);
                                    }

                                    if (value == 'recibos') {
                                      mostrarRecibosCliente(c);
                                    }

                                    if (value == 'gestion') {
                                      registrarGestionCliente(c);
                                    }

                                    if (value == 'anular') {
                                      anularCliente(c);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'detalle',
                                      child: Text('👁 Ver detalle'),
                                    ),
                                    PopupMenuItem(
                                      value: 'editar',
                                      child: Text('✏️ Editar cliente'),
                                    ),
                                    PopupMenuItem(
                                      value: 'polizas',
                                      child: Text('📄 Ver pólizas'),
                                    ),
                                    PopupMenuItem(
                                      value: 'recibos',
                                      child: Text('💰 Ver recibos'),
                                    ),
                                    PopupMenuItem(
                                      value: 'gestion',
                                      child: Text('📞 Registrar gestión'),
                                    ),
                                    PopupMenuItem(
                                      value: 'anular',
                                      child: Text('🚫 Anular cliente'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
Future<void> mostrarDetalleCliente(
  Map<String, dynamic> cliente,
) async {

  final ventas = await Supabase.instance.client
      .from('ventas')
      .select()
      .eq('cliente_id', cliente['id']);

  double primaTotal = 0;
  double comisionTotal = 0;

  for (final venta in ventas) {
    primaTotal +=
        (venta['prima_anual'] ?? 0).toDouble();

    comisionTotal +=
        (venta['comision'] ?? 0).toDouble();
  }

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (_) {

      return Dialog(
        child: Container(
          width: 1000,
          padding: const EdgeInsets.all(25),

          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              Text(
                "${cliente['nombre']} ${cliente['apellidos']}",
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              Wrap(
                spacing: 30,
                runSpacing: 20,
                children: [

                  Text(
                    "📧 ${cliente['email'] ?? ''}",
                  ),

                  Text(
                    "📱 ${cliente['telefono'] ?? ''}",
                  ),

                  Text(
                    "📍 ${cliente['direccion'] ?? ''}",
                  ),

                  Text(
                    "${cliente['codigo_postal'] ?? ''}",
                  ),

                  Text(
                    "${cliente['provincia'] ?? ''}",
                  ),

                  Text(
                    "${cliente['poblacion'] ?? ''}",
                  ),
                ],
              ),

              const SizedBox(height: 30),

              Row(
                children: [

                  _detalleKpi(
                    "Pólizas",
                    ventas.length.toString(),
                  ),

                  const SizedBox(width: 20),

                  _detalleKpi(
                    "Prima Total",
                    "${primaTotal.toStringAsFixed(2)}€",
                  ),

                  const SizedBox(width: 20),

                  _detalleKpi(
                    "Comisiones",
                    "${comisionTotal.toStringAsFixed(2)}€",
                  ),
                ],
              ),

              const SizedBox(height: 30),

              const Text(
                "Pólizas del cliente",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 15),

              SizedBox(
                height: 300,

                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [

                      DataColumn(
                        label: Text("Producto"),
                      ),

                      DataColumn(
                        label: Text("Compañía"),
                      ),

                      DataColumn(
                        label: Text("Prima"),
                      ),

                      DataColumn(
                        label: Text("Comisión"),
                      ),

                      DataColumn(
                        label: Text("Póliza"),
                      ),
                    ],

                    rows: ventas.map((v) {

                      return DataRow(
                        cells: [

                          DataCell(
                            Text(
                              v['producto']
                                  ?.toString() ?? '',
                            ),
                          ),

                          DataCell(
                            Text(
                              v['compania']
                                  ?.toString() ?? '',
                            ),
                          ),

                          DataCell(
                            Text(
                              "${v['prima_anual'] ?? 0}€",
                            ),
                          ),

                          DataCell(
                            Text(
                              "${v['comision'] ?? 0}€",
                            ),
                          ),

                          DataCell(
  InkWell(
    onTap: () {
      mostrarDetallePoliza(v);
    },
    child: Text(
      v['numero_poliza']?.toString() ?? '',
      style: const TextStyle(
        color: Colors.blue,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("Cerrar"),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
Widget _detalleKpi(
  String titulo,
  String valor,
) {
  return Container(
    width: 180,
    padding: const EdgeInsets.all(15),

    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
    ),

    child: Column(
      children: [

        Text(
          valor,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 5),

        Text(titulo),
      ],
    ),
  );
}
Widget _detalleKpiColor(
  String titulo,
  String valor,
  Color fondo,
  Color texto,
) {
  return Container(
    width: 170,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: fondo,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: texto.withOpacity(0.25),
      ),
    ),
    child: Column(
      children: [
        Text(
          valor,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: texto,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: texto,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

Widget _filaDetalle(
  String titulo,
  dynamic valor,
) {
  return Padding(
    padding: const EdgeInsets.only(
      bottom: 12,
    ),
    child: Row(
      children: [

        SizedBox(
          width: 220,
          child: Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        Expanded(
          child: Text(
            valor?.toString() ?? '',
          ),
        ),
      ],
    ),
  );
}


Future<void> editarCliente(
  Map<String, dynamic> cliente,
) async {

  final nombreController =
      TextEditingController(
    text: cliente['nombre'] ?? '',
  );

  final apellidosController =
      TextEditingController(
    text: cliente['apellidos'] ?? '',
  );

  final emailController =
      TextEditingController(
    text: cliente['email'] ?? '',
  );

  final telefonoController =
      TextEditingController(
    text: cliente['telefono'] ?? '',
  );

  final direccionController =
      TextEditingController(
    text: cliente['direccion'] ?? '',
  );

  final numeroController =
      TextEditingController(
    text: cliente['numero']?.toString() ?? '',
  );

  final cpController =
      TextEditingController(
    text: cliente['codigo_postal'] ?? '',
  );

  final provinciaController =
      TextEditingController(
    text: cliente['provincia'] ?? '',
  );

  final poblacionController =
      TextEditingController(
    text: cliente['poblacion'] ?? '',
  );

  showDialog(
    context: context,
    builder: (_) {

      return Dialog(
        child: Container(
          width: 800,
          padding: const EdgeInsets.all(25),

          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                const Text(
                  "Editar cliente",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 25),

                TextField(
                  controller: nombreController,
                  decoration:
                      const InputDecoration(
                    labelText: "Nombre",
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller:
                      apellidosController,
                  decoration:
                      const InputDecoration(
                    labelText: "Apellidos",
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller: emailController,
                  decoration:
                      const InputDecoration(
                    labelText: "Email",
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller:
                      telefonoController,
                  decoration:
                      const InputDecoration(
                    labelText: "Teléfono",
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller:
                      direccionController,
                  decoration:
                      const InputDecoration(
                    labelText: "Dirección",
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller:
                      numeroController,
                  decoration:
                      const InputDecoration(
                    labelText: "Número",
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller: cpController,
                  decoration:
                      const InputDecoration(
                    labelText:
                        "Código Postal",
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller:
                      provinciaController,
                  decoration:
                      const InputDecoration(
                    labelText: "Provincia",
                  ),
                ),

                const SizedBox(height: 15),

                TextField(
                  controller:
                      poblacionController,
                  decoration:
                      const InputDecoration(
                    labelText: "Población",
                  ),
                ),

                const SizedBox(height: 30),

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.end,
                  children: [

                    TextButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                        );
                      },
                      child:
                          const Text("Cancelar"),
                    ),

                    const SizedBox(width: 10),

                    ElevatedButton(
                      onPressed: () async {

                        await Supabase
                            .instance
                            .client
                            .from('clientes')
                            .update({

                          'nombre':
                              nombreController.text,

                          'apellidos':
                              apellidosController.text,

                          'email':
                              emailController.text,

                          'telefono':
                              telefonoController.text,

                          'direccion':
                              direccionController.text,

                          'numero':
                              numeroController.text,

                          'codigo_postal':
                              cpController.text,

                          'provincia':
                              provinciaController.text,

                          'poblacion':
                              poblacionController.text,

                        })
                            .eq(
                          'id',
                          cliente['id'],
                        );

                        Navigator.pop(
                          context,
                        );

                        setState(() {});

                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          const SnackBar(
                            content: Text(
                              "Cliente actualizado correctamente",
                            ),
                          ),
                        );
                      },
                      child:
                          const Text("Guardar"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> verPolizasCliente(
  Map<String, dynamic> cliente,
) async {

  final ventas = await Supabase.instance.client
      .from('ventas')
      .select()
      .eq('cliente_id', cliente['id']);

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (_) {

      return Dialog(
        child: Container(
          width: 1200,
          height: 700,
          padding: const EdgeInsets.all(25),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: [

              Text(
                "Pólizas de ${cliente['nombre']} ${cliente['apellidos']}",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,

                  child: DataTable(
                    columns: const [

                      DataColumn(
                        label: Text("Póliza"),
                      ),

                      DataColumn(
                        label: Text("Producto"),
                      ),

                      DataColumn(
                        label: Text("Compañía"),
                      ),

                      DataColumn(
                        label: Text("Prima"),
                      ),

                      DataColumn(
                        label: Text("Comisión"),
                      ),

                      DataColumn(
                        label: Text("Asegurados"),
                      ),

                      DataColumn(
                        label: Text("Fecha efecto"),
                      ),
                    ],

                    rows: ventas.map((v) {

                      return DataRow(
                        cells: [

                          DataCell(
                            Text(
                              v['numero_poliza']
                                      ?.toString() ??
                                  '',
                            ),
                          ),

                          DataCell(
                            Text(
                              v['producto']
                                      ?.toString() ??
                                  '',
                            ),
                          ),

                          DataCell(
                            Text(
                              v['compania']
                                      ?.toString() ??
                                  '',
                            ),
                          ),

                          DataCell(
                            Text(
                              "${v['prima_anual'] ?? 0}€",
                            ),
                          ),

                          DataCell(
                            Text(
                              "${v['comision'] ?? 0}€",
                            ),
                          ),

                          DataCell(
                            Text(
                              "${v['numero_asegurados'] ?? 0}",
                            ),
                          ),

                          DataCell(
                            Text(
                              v['fecha_efecto']
                                      ?.toString() ??
                                  '',
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text("Cerrar"),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
Future<void> mostrarDetallePoliza(
  Map<String, dynamic> venta,
) async {
final agente = await Supabase.instance.client
    .from('usuarios')
    .select()
    .eq(
      'auth_id',
      venta['agente_auth_id'],
    )
    .maybeSingle();

    Map<String, dynamic>? jefe;

if (agente != null &&
    agente['parent_id'] != null) {

  jefe = await Supabase.instance.client
      .from('usuarios')
      .select()
      .eq(
        'id',
        agente['parent_id'],
      )
      .maybeSingle();
}
final recibos = await Supabase.instance.client
    .from('recibos')
    .select()
    .eq(
      'numero_poliza',
      venta['numero_poliza'],
    );
    final cobrados = recibos
    .where((r) => r['estado'] == 'COBRADO')
    .length;

final devueltos = recibos
    .where((r) => r['estado'] == 'DEVUELTO')
    .length;

final pendientes = recibos
    .where((r) => r['estado'] == 'PENDIENTE')
    .length;


  showDialog(
    context: context,
    builder: (_) {

      return Dialog(
        child: Container(
          width: 1000,
          padding: const EdgeInsets.all(25),

          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Text(
                  "Póliza ${venta['numero_poliza']}",
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 25),

Wrap(
  spacing: 25,
  runSpacing: 20,
  children: [

    _detalleKpi(
      "Agente",
      agente == null
          ? "-"
          : "${agente['nombre']} ${agente['apellidos']}",
    ),

    _detalleKpi(
      "Jefe Equipo",
      jefe == null
          ? "-"
          : "${jefe['nombre']} ${jefe['apellidos']}",
    ),

    _detalleKpi(
      "Compañía",
      venta['compania'] ?? "-",
    ),

    _detalleKpi(
      "Prima",
      "${venta['prima_anual'] ?? 0}€",
    ),

    _detalleKpi(
      "Comisión",
      "${venta['comision'] ?? 0}€",
    ),

    _detalleKpi(
      "Asegurados",
      "${venta['numero_asegurados'] ?? 0}",
    ),
  ],
),
const SizedBox(height: 25),

Wrap(
  spacing: 25,
  runSpacing: 20,
  children: [

    _detalleKpi(
      "Cobrados",
      "$cobrados",
    ),

    _detalleKpi(
      "Devueltos",
      "$devueltos",
    ),

    _detalleKpi(
      "Pendientes",
      "$pendientes",
    ),
  ],
),

const SizedBox(height: 30),

                const SizedBox(height: 30),

                _filaDetalle(
                  "Producto",
                  venta['producto'],
                ),

                _filaDetalle(
                  "Compañía",
                  venta['compania'],
                ),

                _filaDetalle(
                  "Forma pago",
                  venta['forma_pago'],
                ),

                _filaDetalle(
                  "Fecha efecto",
                  venta['fecha_efecto'],
                ),

                _filaDetalle(
                  "Precio",
                  venta['precio'],
                ),

                _filaDetalle(
                  "Prima anual",
                  venta['prima_anual'],
                ),

                _filaDetalle(
                  "Prima bruta",
                  venta['prima_anual_bruta'],
                ),

                _filaDetalle(
                  "Prima neta",
                  venta['prima_anual_neta'],
                ),

                _filaDetalle(
                  "Comisión",
                  venta['comision'],
                ),

                _filaDetalle(
                  "Categoría",
                  venta['categoria_producto'],
                ),

                const SizedBox(height: 30),

                const SizedBox(height: 40),

const Text(
  "Historial de recibos",
  style: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  ),
),

const SizedBox(height: 15),

SizedBox(
  height: 250,
  child: SingleChildScrollView(
    child: DataTable(
      columns: const [

        DataColumn(
          label: Text("Estado"),
        ),

        DataColumn(
          label: Text("Importe"),
        ),

        DataColumn(
          label: Text("Fecha"),
        ),
      ],

      rows: recibos.map<DataRow>((r) {

        return DataRow(
          cells: [

            DataCell(
  Container(
    padding: const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 4,
    ),
    decoration: BoxDecoration(
      color:
          r['estado'] == 'COBRADO'
              ? Colors.green.shade100
              : r['estado'] == 'DEVUELTO'
                  ? Colors.red.shade100
                  : Colors.orange.shade100,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      r['estado'] ?? '',
      style: TextStyle(
        color:
            r['estado'] == 'COBRADO'
                ? Colors.green
                : r['estado'] == 'DEVUELTO'
                    ? Colors.red
                    : Colors.orange,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
),

            DataCell(
              Text(
                r['importe']?.toString() ?? '',
              ),
            ),

            DataCell(
              Text(
                r['fecha']?.toString() ?? '',
              ),
            ),
          ],
        );
      }).toList(),
    ),
  ),
),

                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text("Cerrar"),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> mostrarRecibosCliente(
  Map<String, dynamic> cliente,
) async {

  final ventas = await Supabase.instance.client
      .from('ventas')
      .select()
      .eq(
        'cliente_id',
        cliente['id'],
      );

  final numerosPoliza = ventas
      .map((v) => v['numero_poliza'])
      .toList();

  List<Map<String, dynamic>> recibos = [];

  if (numerosPoliza.isNotEmpty) {

    final response = await Supabase.instance.client
        .from('recibos')
        .select()
        .inFilter(
          'numero_poliza',
          numerosPoliza,
        );

    recibos = List<Map<String, dynamic>>.from(
      response,
    );
  }

  showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        child: Container(
          width: 1200,
          height: 700,
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [

              Text(
                "Recibos de ${cliente['nombre']} ${cliente['apellidos']}",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              Expanded(
                child: SingleChildScrollView(
                  child: DataTable(

                    columns: const [

                      DataColumn(
                        label: Text("Póliza"),
                      ),

                      DataColumn(
                        label: Text("Estado"),
                      ),

                      DataColumn(
                        label: Text("Importe"),
                      ),

                      DataColumn(
                        label: Text("Fecha"),
                      ),
                    ],

                    rows: recibos.map((r) {

                      return DataRow(
                        cells: [

                          DataCell(
                            Text(
                              r['numero_poliza']
                                  ?.toString() ??
                                  '',
                            ),
                          ),

                          DataCell(
                            Text(
                              r['estado']
                                  ?.toString() ??
                                  '',
                            ),
                          ),

                          DataCell(
                            Text(
                              r['importe']
                                  ?.toString() ??
                                  '',
                            ),
                          ),

                          DataCell(
                            Text(
                              r['fecha']
                                  ?.toString() ??
                                  '',
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void registrarGestionCliente(Map<String,dynamic> cliente) {
  print(cliente);
}

void anularCliente(Map<String,dynamic> cliente) {
  print(cliente);
}
Future<List<Map<String, dynamic>>> getClientes() async {
  try {
    final supabase = Supabase.instance.client;

    dynamic clientesQuery = supabase.from('clientes').select();

    if (!veTodoERP) {
      if (authIdsPermitidosERP.isEmpty) return [];

      clientesQuery = clientesQuery.inFilter(
        'auth_id',
        authIdsPermitidosERP,
      );
    }

    final clientesResponse = await clientesQuery;

    final usuariosResponse = await supabase
        .from('usuarios')
        .select('id, auth_id, parent_id, nombre, apellidos');

    dynamic ventasQuery = supabase
        .from('ventas')
        .select('cliente_id, agente_auth_id, compania');

    if (!veTodoERP) {
      ventasQuery = ventasQuery.inFilter(
        'agente_auth_id',
        authIdsPermitidosERP,
      );
    }

    final ventasResponse = await ventasQuery;

    final clientes = List<Map<String, dynamic>>.from(clientesResponse);
    final usuarios = List<Map<String, dynamic>>.from(usuariosResponse);
    final ventas = List<Map<String, dynamic>>.from(ventasResponse);

    for (final cliente in clientes) {
      final ventaCliente = ventas.firstWhere(
        (v) => v['cliente_id']?.toString() == cliente['id']?.toString(),
        orElse: () => <String, dynamic>{},
      );

      if (ventaCliente.isNotEmpty) {
        cliente['compania'] = ventaCliente['compania'];

        final authId = ventaCliente['agente_auth_id']?.toString();

        final agente = usuarios.firstWhere(
          (u) => u['auth_id']?.toString() == authId,
          orElse: () => <String, dynamic>{},
        );

        if (agente.isNotEmpty) {
          cliente['agente_nombre'] =
              "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}".trim();

          final jefe = usuarios.firstWhere(
            (u) => u['id']?.toString() == agente['parent_id']?.toString(),
            orElse: () => <String, dynamic>{},
          );

          cliente['jefe_nombre'] = jefe.isEmpty
              ? ''
              : "${jefe['nombre'] ?? ''} ${jefe['apellidos'] ?? ''}".trim();
        }
      }
    }

    clientes.sort((a, b) {
      final fa = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime(1900);
      final fb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime(1900);
      return fb.compareTo(fa);
    });

    print("CLIENTES CARGADOS ERP: ${clientes.length}");
    return clientes;
  } catch (e) {
    print("❌ ERROR getClientes: $e");
    return [];
  }
}

Future<void> exportClientes(List<Map<String, dynamic>> clientes) async {
  final excelFile = excel.Excel.createExcel();
  final sheet = excelFile['Clientes'];

  sheet.appendRow([
    excel.TextCellValue('Nombre'),
    excel.TextCellValue('Apellidos'),
    excel.TextCellValue('Email'),
    excel.TextCellValue('Teléfono'),
    excel.TextCellValue('CP'),
    excel.TextCellValue('Provincia'),
    excel.TextCellValue('Población'),
    excel.TextCellValue('Dirección'),
    excel.TextCellValue('Número'),
  ]);

  for (final c in clientes) {
    sheet.appendRow([
      excel.TextCellValue(c['nombre']?.toString() ?? ''),
      excel.TextCellValue(c['apellidos']?.toString() ?? ''),
      excel.TextCellValue(c['email']?.toString() ?? ''),
      excel.TextCellValue(c['telefono']?.toString() ?? ''),
      excel.TextCellValue(c['codigo_postal']?.toString() ?? ''),
      excel.TextCellValue(c['provincia']?.toString() ?? ''),
      excel.TextCellValue(c['poblacion']?.toString() ?? ''),
      excel.TextCellValue(c['direccion']?.toString() ?? ''),
      excel.TextCellValue(c['numero']?.toString() ?? ''),
    ]);
  }

  final bytes = excelFile.encode();

  if (bytes == null) return;

  final dir = await getApplicationDocumentsDirectory();

  final file = File('${dir.path}/clientes.xlsx');

  await file.writeAsBytes(bytes, flush: true);

  await OpenFilex.open(file.path);
}

Future<void> exportVentas(
  List<Map<String, dynamic>> ventas,
) async {

  final excelFile = excel.Excel.createExcel();

  final sheet = excelFile['Ventas'];

  sheet.appendRow([
    excel.TextCellValue('Poliza'),
    excel.TextCellValue('Producto'),
    excel.TextCellValue('Compania'),
    excel.TextCellValue('Precio'),
    excel.TextCellValue('Prima Anual'),
    excel.TextCellValue('Comision'),
    excel.TextCellValue('Fecha'),
  ]);

  for (final v in ventas) {

    sheet.appendRow([
      excel.TextCellValue(
        v['numero_poliza']?.toString() ?? '',
      ),

      excel.TextCellValue(
        v['producto']?.toString() ?? '',
      ),

      excel.TextCellValue(
        v['compania']?.toString() ?? '',
      ),

      excel.TextCellValue(
        v['precio']?.toString() ?? '',
      ),

      excel.TextCellValue(
        v['prima_anual']?.toString() ?? '',
      ),

      excel.TextCellValue(
        v['comision']?.toString() ?? '',
      ),

      excel.TextCellValue(
        v['created_at']?.toString() ?? '',
      ),
    ]);
  }

  final bytes = excelFile.encode();

  if (bytes == null) return;

  final dir = await getApplicationDocumentsDirectory();

final file = File('${dir.path}/ventas.xlsx');

await file.writeAsBytes(bytes, flush: true);

await OpenFilex.open(file.path);
}

Widget buildVentasPage() {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: getVentas(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final ventas = filtrarVentas(snapshot.data!);

      final totalVentas = ventas.length;
      final anuladas = ventas.where((v) =>
          (v['estado_poliza']?.toString().toUpperCase() ?? '') == 'ANULADA'
      ).length;

      final activas = totalVentas - anuladas;

      final primaTotal = ventas.fold<double>(0, (suma, v) {
        return suma + (double.tryParse(v['prima_anual']?.toString() ?? '0') ?? 0);
      });

      final comisionTotal = ventas.fold<double>(0, (suma, v) {
        return suma + (double.tryParse(
          v['comision']?.toString()
              ?? v['comison']?.toString()
              ?? '0',
        ) ?? 0);
      });

      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // CABECERA ERP
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      color: Colors.blue.shade700,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Ventas",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          "Panel profesional de control, seguimiento y gestión de pólizas",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                  ElevatedButton.icon(
                    onPressed: () async {
                      await exportVentas(ventas);
                    },
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text("Exportar Excel"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // TARJETAS KPI
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _kpiVentaERP(
                  titulo: "Total pólizas",
                  valor: totalVentas.toString(),
                  icono: Icons.description_outlined,
                  color: Colors.blue,
                ),
                _kpiVentaERP(
                  titulo: "Activas",
                  valor: activas.toString(),
                  icono: Icons.check_circle_outline,
                  color: Colors.green,
                ),
                _kpiVentaERP(
                  titulo: "Anuladas",
                  valor: anuladas.toString(),
                  icono: Icons.cancel_outlined,
                  color: Colors.red,
                ),
                _kpiVentaERP(
                  titulo: "Prima anual",
                  valor: _formatoEuro(primaTotal),
                  icono: Icons.euro_outlined,
                  color: Colors.indigo,
                ),
                _kpiVentaERP(
                  titulo: "Comisión",
                  valor: _formatoEuro(comisionTotal),
                  icono: Icons.payments_outlined,
                  color: Colors.orange,
                ),
              ],
            ),

            const SizedBox(height: 18),

            // FILTROS ERP
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.filter_alt_outlined),
                      SizedBox(width: 8),
                      Text(
                        "Filtros de búsqueda",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _dropdownFiltroVentaERP(
                        label: "Compañía",
                        value: filtroVentaCompania,
                        items: listaVentaCompanias,
                        onChanged: (value) {
                          setState(() {
                            filtroVentaCompania = value;
                          });
                        },
                      ),

                      _dropdownFiltroVentaERP(
                        label: "Agente",
                        value: filtroVentaAgente,
                        items: listaVentaAgentes,
                        onChanged: (value) {
                          setState(() {
                            filtroVentaAgente = value;
                          });
                        },
                      ),

                      _dropdownFiltroVentaERP(
                        label: "Jefe equipo",
                        value: filtroVentaJefe,
                        items: listaVentaJefes,
                        onChanged: (value) {
                          setState(() {
                            filtroVentaJefe = value;
                          });
                        },
                      ),

                      _dropdownFiltroVentaERP(
                        label: "Categoría",
                        value: filtroVentaCategoria,
                        items: listaVentaCategorias,
                        onChanged: (value) {
                          setState(() {
                            filtroVentaCategoria = value;
                          });
                        },
                      ),

                      _botonFechaVentaERP(
                        texto: ventaFechaDesde == null
                            ? "Fecha desde"
                            : ventaFechaDesde.toString().split(" ")[0],
                        icono: Icons.calendar_month_outlined,
                        onPressed: () async {
                          final fecha = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            initialDate: DateTime.now(),
                          );

                          if (fecha != null) {
                            setState(() {
                              ventaFechaDesde = fecha;
                            });
                          }
                        },
                      ),

                      _botonFechaVentaERP(
                        texto: ventaFechaHasta == null
                            ? "Fecha hasta"
                            : ventaFechaHasta.toString().split(" ")[0],
                        icono: Icons.event_available_outlined,
                        onPressed: () async {
                          final fecha = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            initialDate: DateTime.now(),
                          );

                          if (fecha != null) {
                            setState(() {
                              ventaFechaHasta = fecha;
                            });
                          }
                        },
                      ),

                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            filtroVentaCompania = null;
                            filtroVentaCategoria = null;
                            ventaFechaDesde = null;
                            ventaFechaHasta = null;
                            filtroVentaAgente = null;
                            filtroVentaJefe = null;
                          });
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text("Limpiar filtros"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // TABLA PROFESIONAL
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Listado de pólizas",
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "$totalVentas registros encontrados",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
  height: 620,
  child: SingleChildScrollView(
    scrollDirection: Axis.vertical,
    child: TablaConScrollHorizontalERP(
      child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              Colors.grey.shade100,
                            ),
                            dataRowMinHeight: 62,
                            dataRowMaxHeight: 76,
                            columnSpacing: 28,
                            border: TableBorder(
                              horizontalInside: BorderSide(
                                color: Colors.grey.shade200,
                              ),
                            ),
                            columns: const [
                              DataColumn(label: Text("Estado")),
                              DataColumn(label: Text("Póliza")),
                              DataColumn(label: Text("Producto")),
                              DataColumn(label: Text("Compañía")),
                              DataColumn(label: Text("Forma pago")),
                              DataColumn(label: Text("Precio")),
                              DataColumn(label: Text("Prima anual")),
                              DataColumn(label: Text("Comisión")),
                              DataColumn(label: Text("Fecha efecto")),
                              DataColumn(label: Text("Agente")),
                              DataColumn(label: Text("Acciones")),
                            ],

                            rows: ventas.map((v) {
                              final estado = v['estado_poliza']?.toString() ?? 'ACTIVA';

                              return DataRow(
                                color: WidgetStateProperty.resolveWith<Color?>(
                                  (states) {
                                    if (estado.toUpperCase() == 'ANULADA') {
                                      return Colors.red.shade50;
                                    }
                                    return null;
                                  },
                                ),
                                cells: [
                                  DataCell(_chipEstadoPolizaERP(estado)),

                                  DataCell(
                                    Text(
                                      v['numero_poliza']?.toString().isEmpty ?? true
                                          ? 'Sin póliza'
                                          : v['numero_poliza'].toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),

                                  DataCell(_textoTablaVenta(v['producto'])),
                                  DataCell(_textoTablaVenta(v['compañia'] ?? v['compania'])),
                                  DataCell(_textoTablaVenta(v['forma_pago'])),

                                  DataCell(
                                    Text(
                                      _formatoEuroDesdeDynamic(v['precio']),
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),

                                  DataCell(
                                    Text(
                                      _formatoEuroDesdeDynamic(v['prima_anual']),
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),

                                  DataCell(
                                    Text(
                                      _formatoEuroDesdeDynamic(v['comision'] ?? v['comison']),
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),

                                  DataCell(_textoTablaVenta(v['fecha_efecto'])),
                                  DataCell(_textoTablaVenta(v['agente_nombre'])),

                                  DataCell(
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert),
                                      tooltip: "Acciones de póliza",
                                      onSelected: (value) async {
                                        print("ACCION VENTAS PULSADA: $value");
                                        print("POLIZA: ${v['numero_poliza']}");
                                        print("VENTA COMPLETA:");
                                        print(v);

                                        if (value == 'detalle') {
                                          await mostrarDetalleVentaERP(v);
                                        }

                                        if (value == 'editar') {
                                          await editarPolizaDialog(v);
                                        }

                                        if (value == 'recibos') {
                                          await consultarRecibosDialog(v);
                                        }

                                        if (value == 'gestionar') {
                                          await gestionarPolizaDialog(v);
                                        }

                                        if (value == 'anular') {
                                          await anularPolizaDialog(v);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'detalle',
                                          child: ListTile(
                                            leading: Icon(Icons.visibility_outlined),
                                            title: Text('Ver detalle'),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'editar',
                                          child: ListTile(
                                            leading: Icon(Icons.edit_outlined),
                                            title: Text('Editar póliza'),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'recibos',
                                          child: ListTile(
                                            leading: Icon(Icons.receipt_long_outlined),
                                            title: Text('Consultar recibos'),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'gestionar',
                                          child: ListTile(
                                            leading: Icon(Icons.manage_accounts_outlined),
                                            title: Text('Gestionar'),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'anular',
                                          enabled: estado.toUpperCase() != 'ANULADA',
                                          child: const ListTile(
                                            leading: Icon(
                                              Icons.cancel_outlined,
                                              color: Colors.red,
                                            ),
                                            title: Text(
                                              'Anular póliza',
                                              style: TextStyle(color: Colors.red),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
Widget _kpiVentaERP({
  required String titulo,
  required String valor,
  required IconData icono,
  required MaterialColor color,
}) {
  return Container(
    width: 210,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade300),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icono,
            color: color.shade700,
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _dropdownFiltroVentaERP({
  required String label,
  required String? value,
  required List<String> items,
  required Function(String?) onChanged,
}) {
  return SizedBox(
    width: 190,
    child: DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(
            item,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: onChanged,
    ),
  );
}

Widget _botonFechaVentaERP({
  required String texto,
  required IconData icono,
  required VoidCallback onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icono),
    label: Text(texto),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}

Widget _chipEstadoPolizaERP(String estado) {
  final estadoUpper = estado.toUpperCase();

  Color color = Colors.green;
  IconData icono = Icons.check_circle_outline;
  String texto = estadoUpper.isEmpty ? "ACTIVA" : estadoUpper;

  if (estadoUpper == 'ANULADA') {
    color = Colors.red;
    icono = Icons.cancel_outlined;
    texto = "ANULADA";
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          texto,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

Widget _textoTablaVenta(dynamic valor) {
  final texto = valor?.toString() ?? '';

  return Text(
    texto.isEmpty ? '—' : texto,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

String _formatoEuroDesdeDynamic(dynamic valor) {
  final numero = double.tryParse(valor?.toString().replaceAll(',', '.') ?? '');

  if (numero == null) {
    return '—';
  }

  return '${numero.toStringAsFixed(2)} €';
}

String _formatoEuro(double valor) {
  return '${valor.toStringAsFixed(2)} €';
}

Widget buildProduccionPage() {
  return const Center(
    child: Text("Producción (en desarrollo)"),
  );
}
Future<void> cargarCompanias() async {

  final response = await Supabase.instance.client
      .from('ventas')
      .select('compania');

  final companias = response
      .map((e) => e['compania']?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  setState(() {
    listaCompanias = companias;
  });
}
Future<void> cargarJefesFiltro() async {

  final response = await Supabase.instance.client
      .from('usuarios')
      .select();

  final jefes = response
      .where((u) => u['rol_usuario'] == 'JEFE_EQUIPO')
      .map((u) => "${u['nombre']} ${u['apellidos']}")
      .toList();

  setState(() {
    listaJefes = jefes;
  });
}
Future<void> cargarAgentesFiltro() async {

  final ventas = await Supabase.instance.client
      .from('ventas')
      .select('compania');

  final companias = ventas
      .map((e) => e['compania']?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  setState(() {
    listaCompanias = companias;
  });

  print("COMPANIAS CARGADAS: ${listaCompanias.length}");
}
List<Map<String, dynamic>> filtrarClientes(
  List<Map<String, dynamic>> clientes,
) {
  return clientes.where((c) {
    if (filtroAgente != null && filtroAgente!.isNotEmpty) {
      if ((c['agente_nombre'] ?? '') != filtroAgente) return false;
    }

    if (filtroJefeEquipo != null && filtroJefeEquipo!.isNotEmpty) {
      if ((c['jefe_nombre'] ?? '') != filtroJefeEquipo) return false;
    }

    if (filtroCompania != null && filtroCompania!.isNotEmpty) {
      if ((c['compania'] ?? '') != filtroCompania) return false;
    }

    if (fechaDesde != null) {
      final fecha = DateTime.tryParse(c['created_at']?.toString() ?? '');
      if (fecha != null && fecha.isBefore(fechaDesde!)) return false;
    }

    if (fechaHasta != null) {
      final finDia = DateTime(
        fechaHasta!.year,
        fechaHasta!.month,
        fechaHasta!.day,
        23,
        59,
        59,
      );

      final fecha = DateTime.tryParse(c['created_at']?.toString() ?? '');
      if (fecha != null && fecha.isAfter(finDia)) return false;
    }

    return true;
  }).toList();
}
Future<void> cargarFiltrosClientes() async {
  final supabase = Supabase.instance.client;

  dynamic ventasQuery = supabase
      .from('ventas')
      .select('compania, agente_auth_id');

  if (!veTodoERP) {
    if (authIdsPermitidosERP.isEmpty) return;

    ventasQuery = ventasQuery.inFilter(
      'agente_auth_id',
      authIdsPermitidosERP,
    );
  }

  final ventas = await ventasQuery;

  dynamic usuariosQuery = supabase
      .from('usuarios')
      .select('id, auth_id, nombre, apellidos, parent_id');

  if (!veTodoERP) {
    usuariosQuery = usuariosQuery.inFilter(
      'auth_id',
      authIdsPermitidosERP,
    );
  }

  final usuarios = await usuariosQuery;

  final companias = ventas
      .map((e) => e['compania']?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  final agentes = <String>{};
  final jefes = <String>{};

  for (final venta in ventas) {
    final authId = venta['agente_auth_id']?.toString();

    final agente = usuarios.firstWhere(
      (u) => u['auth_id']?.toString() == authId,
      orElse: () => <String, dynamic>{},
    );

    if (agente.isNotEmpty) {
      agentes.add(
        "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}".trim(),
      );

      final jefe = usuarios.firstWhere(
        (u) => u['id']?.toString() == agente['parent_id']?.toString(),
        orElse: () => <String, dynamic>{},
      );

      if (jefe.isNotEmpty) {
        jefes.add(
          "${jefe['nombre'] ?? ''} ${jefe['apellidos'] ?? ''}".trim(),
        );
      }
    }
  }

  setState(() {
    listaCompanias = companias;
    listaAgentes = agentes.toList();
    listaJefes = jefes.toList();
  });
}
Future<void> cargarFiltrosVentas() async {
  final supabase = Supabase.instance.client;

  dynamic ventasQuery = supabase
      .from('ventas')
      .select('compania, categoria_producto, agente_auth_id');

  if (!veTodoERP) {
    if (authIdsPermitidosERP.isEmpty) return;

    ventasQuery = ventasQuery.inFilter(
      'agente_auth_id',
      authIdsPermitidosERP,
    );
  }

  final ventas = await ventasQuery;

  dynamic usuariosQuery = supabase
      .from('usuarios')
      .select('id, auth_id, parent_id, nombre, apellidos');

  if (!veTodoERP) {
    usuariosQuery = usuariosQuery.inFilter(
      'auth_id',
      authIdsPermitidosERP,
    );
  }

  final usuarios = await usuariosQuery;

  final companias = ventas
      .map((e) => e['compania']?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  final categorias = ventas
      .map((e) => e['categoria_producto']?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  final agentes = <String>{};
  final jefes = <String>{};

  for (final venta in ventas) {
    final authId = venta['agente_auth_id']?.toString();

    final agente = usuarios.firstWhere(
      (u) => u['auth_id']?.toString() == authId,
      orElse: () => <String, dynamic>{},
    );

    if (agente.isNotEmpty) {
      agentes.add(
        "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}".trim(),
      );

      final jefe = usuarios.firstWhere(
        (u) => u['id']?.toString() == agente['parent_id']?.toString(),
        orElse: () => <String, dynamic>{},
      );

      if (jefe.isNotEmpty) {
        jefes.add(
          "${jefe['nombre'] ?? ''} ${jefe['apellidos'] ?? ''}".trim(),
        );
      }
    }
  }

  setState(() {
    listaVentaCompanias = companias;
    listaVentaCategorias = categorias;
    listaVentaAgentes = agentes.toList();
    listaVentaJefes = jefes.toList();
  });
}
Future<List<Map<String, dynamic>>> getVentas() async {
  try {
    final supabase = Supabase.instance.client;

    dynamic query = supabase.from('ventas').select();

    if (!veTodoERP) {
      if (authIdsPermitidosERP.isEmpty) return [];

      query = query.inFilter(
        'agente_auth_id',
        authIdsPermitidosERP,
      );
    }

    final ventasResponse = await query;

    dynamic usuariosQuery = supabase
        .from('usuarios')
        .select('id, auth_id, parent_id, nombre, apellidos, rol_usuario');

    final usuariosResponse = await usuariosQuery;

    final usuarios = List<Map<String, dynamic>>.from(usuariosResponse);
    final ventas = List<Map<String, dynamic>>.from(ventasResponse);

    for (final venta in ventas) {
      final authId = venta['agente_auth_id']?.toString();

      final agente = usuarios.firstWhere(
        (u) => u['auth_id']?.toString() == authId,
        orElse: () => <String, dynamic>{},
      );

      if (agente.isNotEmpty) {
        venta['agente_nombre'] =
            "${agente['nombre'] ?? ''} ${agente['apellidos'] ?? ''}".trim();

        final jefe = usuarios.firstWhere(
          (u) => u['id']?.toString() == agente['parent_id']?.toString(),
          orElse: () => <String, dynamic>{},
        );

        venta['jefe_nombre'] = jefe.isEmpty
            ? ''
            : "${jefe['nombre'] ?? ''} ${jefe['apellidos'] ?? ''}".trim();
      }
    }

    ventas.sort((a, b) {
      final fa = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.tryParse(a['fecha_efecto']?.toString() ?? '') ??
          DateTime(1900);

      final fb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.tryParse(b['fecha_efecto']?.toString() ?? '') ??
          DateTime(1900);

      return fb.compareTo(fa);
    });

    print("VENTAS CARGADAS ERP: ${ventas.length}");
    return ventas;
  } catch (e) {
    print("❌ ERROR getVentas: $e");
    return [];
  }
}
List<Map<String, dynamic>> filtrarVentas(
  List<Map<String, dynamic>> ventas,
) {
  return ventas.where((v) {

    if (filtroVentaCompania != null &&
        filtroVentaCompania!.isNotEmpty) {

      if (v['compania'] != filtroVentaCompania) {
        return false;
      }
    }

    if (filtroVentaCategoria != null &&
        filtroVentaCategoria!.isNotEmpty) {

      if (v['categoria_producto'] !=
          filtroVentaCategoria) {
        return false;
      }
    }

    if (filtroVentaAgente != null &&
        filtroVentaAgente!.isNotEmpty) {

      if (v['agente_nombre'] !=
          filtroVentaAgente) {
        return false;
      }
    }

    if (filtroVentaJefe != null &&
        filtroVentaJefe!.isNotEmpty) {

      if (v['jefe_nombre'] !=
          filtroVentaJefe) {
        return false;
      }
    }

    return true;

  }).toList();
}
Future<void> mostrarDetalleVentaERP(Map<String, dynamic> venta) async {
  final agente = await Supabase.instance.client
      .from('usuarios')
      .select()
      .eq('auth_id', venta['agente_auth_id'])
      .maybeSingle();

  Map<String, dynamic>? jefe;

  if (agente != null && agente['parent_id'] != null) {
    jefe = await Supabase.instance.client
        .from('usuarios')
        .select()
        .eq('id', agente['parent_id'])
        .maybeSingle();
  }

  final cliente = await Supabase.instance.client
      .from('clientes')
      .select()
      .eq('id', venta['cliente_id'])
      .maybeSingle();

  final numeroPoliza = venta['numero_poliza']?.toString() ?? '';

final recibos = numeroPoliza.isEmpty
    ? []
    : await Supabase.instance.client
        .from('recibos')
        .select()
        .eq('numero_poliza', numeroPoliza);

  final cobrados = recibos.where((r) => r['estado'] == 'COBRADO').length;
  final devueltos = recibos.where((r) => r['estado'] == 'DEVUELTO').length;
  final pendientes = recibos.where((r) => r['estado'] == 'PENDIENTE').length;

  if (!mounted) return;

  showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        child: Container(
          width: 1150,
          height: 750,
          padding: const EdgeInsets.all(25),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Ficha de venta / póliza ${numeroPoliza.isEmpty ? 'Sin póliza' : numeroPoliza}",
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

               Wrap(
  spacing: 20,
  runSpacing: 20,
  children: [
    _detalleKpiColor(
      "Prima anual",
      "${((venta['prima_anual'] ?? 0) as num).toStringAsFixed(2)} €",
      Colors.blue.shade50,
      Colors.blue.shade700,
    ),

    _detalleKpiColor(
      "Prima bruta",
      "${((venta['prima_anual_bruta'] ?? 0) as num).toStringAsFixed(2)} €",
      Colors.purple.shade50,
      Colors.purple.shade700,
    ),

    _detalleKpiColor(
      "Prima neta",
      "${((venta['prima_anual_neta'] ?? 0) as num).toStringAsFixed(2)} €",
      Colors.green.shade50,
      Colors.green.shade700,
    ),

    _detalleKpiColor(
      "Comisión",
      "${((venta['comision'] ?? 0) as num).toStringAsFixed(2)} €",
      Colors.orange.shade50,
      Colors.orange.shade700,
    ),

    _detalleKpiColor(
      "Cobrados",
      "$cobrados",
      Colors.green.shade50,
      Colors.green.shade700,
    ),

    _detalleKpiColor(
      "Devueltos",
      "$devueltos",
      Colors.red.shade50,
      Colors.red.shade700,
    ),

    _detalleKpiColor(
      "Pendientes",
      "$pendientes",
      Colors.amber.shade50,
      Colors.amber.shade800,
    ),
  ],
),

                const SizedBox(height: 30),

                const Text(
                  "Datos del cliente",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                _filaDetalle("Cliente", cliente == null ? "-" : "${cliente['nombre']} ${cliente['apellidos']}"),
                _filaDetalle("Email", cliente?['email']),
                _filaDetalle("Teléfono", cliente?['telefono']),
                _filaDetalle("Provincia", cliente?['provincia']),
                _filaDetalle("Población", cliente?['poblacion']),

                const SizedBox(height: 25),

                const Text(
                  "Datos comerciales",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                _filaDetalle("Agente", agente == null ? "-" : "${agente['nombre']} ${agente['apellidos']}"),
                _filaDetalle("Jefe equipo", jefe == null ? "-" : "${jefe['nombre']} ${jefe['apellidos']}"),
                _filaDetalle("Compañía", venta['compania']),
                _filaDetalle("Producto", venta['producto']),
                _filaDetalle("Categoría", venta['categoria_producto']),
                _filaDetalle("Forma de pago", venta['forma_pago']),
                _filaDetalle("Fecha efecto", venta['fecha_efecto']),
                _filaDetalle("Número asegurados", venta['numero_asegurados']),
                _filaDetalle("Precio", venta['precio']),

                const SizedBox(height: 25),

                const Text(
                  "Historial de recibos",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  height: 250,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text("Fecha")),
                          DataColumn(label: Text("Importe")),
                          DataColumn(label: Text("Estado")),
                          DataColumn(label: Text("Motivo")),
                        ],
                        rows: recibos.map<DataRow>((r) {
                          return DataRow(
                            cells: [
                              DataCell(Text(r['fecha']?.toString() ?? '')),
                              DataCell(Text(r['importe']?.toString() ?? '')),
                              DataCell(Text(r['estado']?.toString() ?? '')),
                              DataCell(Text(r['motivo']?.toString() ?? '')),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        editarPolizaDialog(venta);
                      },
                      child: const Text("Editar póliza"),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cerrar"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
Future<void> editarPolizaDialog(Map<String, dynamic> v) async {
  final productoController = TextEditingController(text: v['producto']?.toString() ?? '');
  final companiaController = TextEditingController(text: v['compañia']?.toString() ?? '');
  final formaPagoController = TextEditingController(text: v['forma_pago']?.toString() ?? '');
  final precioController = TextEditingController(text: v['precio']?.toString() ?? '');
  final aseguradosController = TextEditingController(text: v['numero_asegurados']?.toString() ?? '');
  final fechaEfectoController = TextEditingController(text: v['fecha_efecto']?.toString() ?? '');
  final primaAnualController = TextEditingController(text: v['prima_anual']?.toString() ?? '');
  final categoriaController = TextEditingController(text: v['categoria_producto']?.toString() ?? '');
  final primaNetaController = TextEditingController(text: v['prima_anula_nete']?.toString() ?? '');
  final primaBrutaController = TextEditingController(text: v['prima_anula_bruta']?.toString() ?? '');
  final comisionController = TextEditingController(text: v['comison']?.toString() ?? '');

  bool guardando = false;

  double? toDouble(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  int? toInt(String value) {
    if (value.trim().isEmpty) return null;
    return int.tryParse(value);
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.edit_document,
                            color: Colors.blue.shade700,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Editar póliza",
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Modifica los datos de la póliza seleccionada",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, color: Colors.grey.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Número de póliza: ${v['numero_poliza'] ?? 'Sin número'}",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    _tituloSeccionEditar("Datos principales"),

                    const SizedBox(height: 12),

                    _campoEditarPoliza(
                      label: "Producto",
                      icon: Icons.inventory_2_outlined,
                      controller: productoController,
                    ),

                    _campoEditarPoliza(
                      label: "Compañía",
                      icon: Icons.business_outlined,
                      controller: companiaController,
                    ),

                    _campoEditarPoliza(
                      label: "Categoría producto",
                      icon: Icons.category_outlined,
                      controller: categoriaController,
                    ),

                    _campoEditarPoliza(
                      label: "Forma de pago",
                      icon: Icons.payments_outlined,
                      controller: formaPagoController,
                    ),

                    _campoEditarPoliza(
                      label: "Fecha efecto",
                      icon: Icons.calendar_month_outlined,
                      controller: fechaEfectoController,
                    ),

                    const SizedBox(height: 20),

                    _tituloSeccionEditar("Importes y asegurados"),

                    const SizedBox(height: 12),

                    _campoEditarPoliza(
                      label: "Precio",
                      icon: Icons.euro_outlined,
                      controller: precioController,
                      keyboardType: TextInputType.number,
                    ),

                    _campoEditarPoliza(
                      label: "Número de asegurados",
                      icon: Icons.groups_outlined,
                      controller: aseguradosController,
                      keyboardType: TextInputType.number,
                    ),

                    _campoEditarPoliza(
                      label: "Prima anual",
                      icon: Icons.receipt_long_outlined,
                      controller: primaAnualController,
                      keyboardType: TextInputType.number,
                    ),

                    _campoEditarPoliza(
                      label: "Prima anual neta",
                      icon: Icons.trending_up_outlined,
                      controller: primaNetaController,
                      keyboardType: TextInputType.number,
                    ),

                    _campoEditarPoliza(
                      label: "Prima anual bruta",
                      icon: Icons.account_balance_wallet_outlined,
                      controller: primaBrutaController,
                      keyboardType: TextInputType.number,
                    ),

                    _campoEditarPoliza(
                      label: "Comisión",
                      icon: Icons.percent_outlined,
                      controller: comisionController,
                      keyboardType: TextInputType.number,
                    ),

                    const SizedBox(height: 26),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: guardando
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            label: const Text("Cancelar"),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: guardando
                                ? null
                                : () async {
                                    setDialogState(() {
                                      guardando = true;
                                    });

                                    try {
                                      await Supabase.instance.client
                                          .from('ventas')
                                          .update({
                                            'producto': productoController.text.trim(),
                                            'compañia': companiaController.text.trim(),
                                            'forma_pago': formaPagoController.text.trim(),
                                            'precio': toDouble(precioController.text),
                                            'numero_asegurados': toInt(aseguradosController.text),
                                            'fecha_efecto': fechaEfectoController.text.trim(),
                                            'prima_anual': toDouble(primaAnualController.text),
                                            'categoria_producto': categoriaController.text.trim(),
                                            'prima_anula_nete': toDouble(primaNetaController.text),
                                            'prima_anula_bruta': toDouble(primaBrutaController.text),
                                            'comison': toDouble(comisionController.text),
                                          })
                                          .eq('id', v['id']);

                                      Navigator.pop(context);
                                      setState(() {});

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Póliza actualizada correctamente"),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } catch (e) {
                                      setDialogState(() {
                                        guardando = false;
                                      });

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("Error al actualizar la póliza: $e"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                            icon: guardando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(guardando ? "Guardando..." : "Guardar cambios"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  productoController.dispose();
  companiaController.dispose();
  formaPagoController.dispose();
  precioController.dispose();
  aseguradosController.dispose();
  fechaEfectoController.dispose();
  primaAnualController.dispose();
  categoriaController.dispose();
  primaNetaController.dispose();
  primaBrutaController.dispose();
  comisionController.dispose();
}
Widget _tituloSeccionEditar(String titulo) {
  return Text(
    titulo,
    style: const TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.bold,
    ),
  );
}

Widget _campoEditarPoliza({
  required String label,
  required IconData icon,
  required TextEditingController controller,
  TextInputType keyboardType = TextInputType.text,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.blue, width: 1.6),
        ),
      ),
    ),
  );
}
Future<void> consultarRecibosDialog(Map<String, dynamic> v) async {
print("CONSULTAR RECIBOS PULSADO");
print("POLIZA: ${v['numero_poliza']}");
print("FECHA EFECTO: ${v['fecha_efecto']}");

  final numeroPoliza = v['numero_poliza']?.toString() ?? '';
  final formaPago = v['forma_pago']?.toString() ?? '';
  final fechaEfectoTexto = v['fecha_efecto']?.toString() ?? '';

 DateTime? fechaEfecto;

if (fechaEfectoTexto.contains('/')) {
  final partes = fechaEfectoTexto.split('/');

  if (partes.length == 3) {
    fechaEfecto = DateTime(
      int.parse(partes[2]),
      int.parse(partes[1]),
      int.parse(partes[0]),
    );
  }
} else {
  fechaEfecto = DateTime.tryParse(fechaEfectoTexto);
}

  if (fechaEfecto == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("La póliza no tiene una fecha de efecto válida"),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  final recibosDevueltos = await Supabase.instance.client
    .from('recibos')
    .select()
    .eq('poliza', numeroPoliza);

  final List<Map<String, dynamic>> historial = [];

  int mesesSalto = 1;

  final fp = formaPago.toLowerCase();

  if (fp.contains('trimes')) {
    mesesSalto = 3;
  } else if (fp.contains('semes')) {
    mesesSalto = 6;
  } else if (fp.contains('anual')) {
    mesesSalto = 12;
  } else {
    mesesSalto = 1;
  }

  DateTime fechaRecibo = DateTime(
    fechaEfecto.year,
    fechaEfecto.month,
    fechaEfecto.day,
  );

  final hoy = DateTime.now();

  while (!fechaRecibo.isAfter(hoy)) {
    final devuelto = recibosDevueltos.where((r) {
      final fechaReciboTabla = r['fecha']?.toString() ?? '';
      final estado = r['estado']?.toString().toLowerCase() ?? '';
      final gestion = r['gestion']?.toString().toLowerCase() ?? '';

      final coincideMes = fechaReciboTabla.contains(
        "${fechaRecibo.year}-${fechaRecibo.month.toString().padLeft(2, '0')}",
      );

      return coincideMes &&
          (estado.contains('devuelto') || gestion.contains('devuelto'));
    }).toList();

    historial.add({
      'fecha': fechaRecibo,
      'estado': devuelto.isEmpty ? 'COBRADO' : 'DEVUELTO',
      'detalle': devuelto.isEmpty ? null : devuelto.first,
    });

    fechaRecibo = DateTime(
      fechaRecibo.year,
      fechaRecibo.month + mesesSalto,
      fechaRecibo.day,
    );
  }

  await showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 780),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.receipt_long,
                        color: Colors.indigo.shade700,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Historial de recibos",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Póliza $numeroPoliza",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _miniDatoRecibo("Fecha efecto", fechaEfectoTexto),
                      _miniDatoRecibo("Forma de pago", formaPago),
                      _miniDatoRecibo("Recibos generados", historial.length.toString()),
                      _miniDatoRecibo(
                        "Devueltos",
                        historial.where((e) => e['estado'] == 'DEVUELTO').length.toString(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                const Text(
                  "Evolución de recibos",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                ...historial.map((r) {
                  final fecha = r['fecha'] as DateTime;
                  final estado = r['estado'] as String;
                  final esDevuelto = estado == 'DEVUELTO';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: esDevuelto
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: esDevuelto
                            ? Colors.red.shade200
                            : Colors.green.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: esDevuelto
                              ? Colors.red.shade100
                              : Colors.green.shade100,
                          child: Icon(
                            esDevuelto
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            color: esDevuelto
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                esDevuelto
                                    ? "Recibo devuelto encontrado en tabla recibos"
                                    : "Recibo cobrado automáticamente",
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: esDevuelto
                                ? Colors.red.shade600
                                : Colors.green.shade600,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            estado,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      );
    },
  );
}
Widget _miniDatoRecibo(String titulo, String valor) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          valor.isEmpty ? "Sin dato" : valor,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}
Future<void> gestionarPolizaDialog(Map<String, dynamic> v) async {
  final comentarioController = TextEditingController();
  final proximaAccionController = TextEditingController();
  final fechaProximaController = TextEditingController();

  String tipoGestion = "Seguimiento";
  String estadoGestion = "Pendiente";

  final poliza = v['numero_poliza']?.toString() ?? '';
  final ventaId = v['id'];

  final gestiones = await Supabase.instance.client
      .from('gestiones_poliza')
      .select()
      .eq('venta_id', ventaId)
      .order('created_at', ascending: false);

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 850),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.manage_accounts,
                            color: Colors.deepPurple.shade700,
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Centro de gestión de póliza",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                poliza.isEmpty
                                    ? "Póliza pendiente de asignar"
                                    : "Póliza $poliza",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _chipGestion("Producto", v['producto']),
                          _chipGestion("Compañía", v['compañia']),
                          _chipGestion("Forma pago", v['forma_pago']),
                          _chipGestion("Fecha efecto", v['fecha_efecto']),
                          _chipGestion("Prima anual", v['prima_anual']),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      "Nueva gestión",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 14),

                    DropdownButtonFormField<String>(
                      value: tipoGestion,
                      decoration: _decoracionGestion(
                        "Tipo de gestión",
                        Icons.task_alt,
                      ),
                      items: const [
                        DropdownMenuItem(value: "Seguimiento", child: Text("Seguimiento")),
                        DropdownMenuItem(value: "Recibo devuelto", child: Text("Recibo devuelto")),
                        DropdownMenuItem(value: "Cambio de datos", child: Text("Cambio de datos")),
                        DropdownMenuItem(value: "Consulta cliente", child: Text("Consulta cliente")),
                        DropdownMenuItem(value: "Incidencia", child: Text("Incidencia")),
                        DropdownMenuItem(value: "Baja posible", child: Text("Baja posible")),
                        DropdownMenuItem(value: "Retención", child: Text("Retención")),
                        DropdownMenuItem(value: "Venta cruzada", child: Text("Venta cruzada")),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          tipoGestion = value ?? "Seguimiento";
                        });
                      },
                    ),

                    const SizedBox(height: 14),

                    DropdownButtonFormField<String>(
                      value: estadoGestion,
                      decoration: _decoracionGestion(
                        "Estado",
                        Icons.flag_outlined,
                      ),
                      items: const [
                        DropdownMenuItem(value: "Pendiente", child: Text("Pendiente")),
                        DropdownMenuItem(value: "En gestión", child: Text("En gestión")),
                        DropdownMenuItem(value: "Solucionado", child: Text("Solucionado")),
                        DropdownMenuItem(value: "No localizado", child: Text("No localizado")),
                        DropdownMenuItem(value: "Revisar urgente", child: Text("Revisar urgente")),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          estadoGestion = value ?? "Pendiente";
                        });
                      },
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: comentarioController,
                      maxLines: 4,
                      decoration: _decoracionGestion(
                        "Comentario de la gestión",
                        Icons.notes,
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: proximaAccionController,
                      decoration: _decoracionGestion(
                        "Próxima acción",
                        Icons.next_plan_outlined,
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: fechaProximaController,
                      decoration: _decoracionGestion(
                        "Fecha próxima acción, ejemplo 2026-06-30",
                        Icons.calendar_month,
                      ),
                    ),

                    const SizedBox(height: 22),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text("Guardar gestión"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: () async {
                          await Supabase.instance.client
                              .from('gestiones_poliza')
                              .insert({
                                'venta_id': ventaId,
                                'poliza': poliza,
                                'tipo_gestion': tipoGestion,
                                'estado': estadoGestion,
                                'comentario': comentarioController.text.trim(),
                                'proxima_accion': proximaAccionController.text.trim(),
                                'fecha_proxima_accion': fechaProximaController.text.trim().isEmpty
                                    ? null
                                    : fechaProximaController.text.trim(),
                              });

                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Gestión guardada correctamente"),
                              backgroundColor: Colors.green,
                            ),
                          );

                          setState(() {});
                        },
                      ),
                    ),

                    const SizedBox(height: 28),

                    const Text(
                      "Historial de gestiones",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (gestiones.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Text(
                          "Todavía no hay gestiones registradas para esta póliza.",
                        ),
                      )
                    else
                      ...gestiones.map((g) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.blueGrey.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.history,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "${g['tipo_gestion'] ?? ''} · ${g['estado'] ?? ''}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(g['comentario']?.toString() ?? ''),
                              const SizedBox(height: 8),
                              if ((g['proxima_accion']?.toString() ?? '').isNotEmpty)
                                Text(
                                  "Próxima acción: ${g['proxima_accion']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if ((g['fecha_proxima_accion']?.toString() ?? '').isNotEmpty)
                                Text(
                                  "Fecha: ${g['fecha_proxima_accion']}",
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  comentarioController.dispose();
  proximaAccionController.dispose();
  fechaProximaController.dispose();
}
Widget _chipGestion(String titulo, dynamic valor) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          valor?.toString().isEmpty ?? true ? "Sin dato" : valor.toString(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

InputDecoration _decoracionGestion(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.grey.shade50,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.deepPurple, width: 1.6),
    ),
  );
}

Future<void> anularPolizaDialog(Map<String, dynamic> v) async {
  final detalleController = TextEditingController();
  final fechaController = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );

  String motivoSeleccionado = "Impago";
  bool confirmacion = false;
  bool guardando = false;

  final poliza = v['numero_poliza']?.toString() ?? '';
  final ventaId = v['id'];

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 760),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.cancel_outlined,
                            color: Colors.red.shade700,
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Anular póliza",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                poliza.isEmpty
                                    ? "Póliza pendiente de número"
                                    : "Póliza $poliza",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: guardando ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "Esta acción marcará la póliza como ANULADA y guardará un expediente de anulación. No se eliminará la venta.",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    DropdownButtonFormField<String>(
                      value: motivoSeleccionado,
                      decoration: _decoracionAnulacion(
                        "Motivo de anulación",
                        Icons.report_problem_outlined,
                      ),
                      items: const [
                        DropdownMenuItem(value: "Impago", child: Text("Impago")),
                        DropdownMenuItem(value: "Baja voluntaria", child: Text("Baja voluntaria")),
                        DropdownMenuItem(value: "Cambio de compañía", child: Text("Cambio de compañía")),
                        DropdownMenuItem(value: "Error en emisión", child: Text("Error en emisión")),
                        DropdownMenuItem(value: "Duplicada", child: Text("Póliza duplicada")),
                        DropdownMenuItem(value: "No conforme cliente", child: Text("Cliente no conforme")),
                        DropdownMenuItem(value: "Fallecimiento", child: Text("Fallecimiento")),
                        DropdownMenuItem(value: "Otro", child: Text("Otro motivo")),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          motivoSeleccionado = value ?? "Impago";
                        });
                      },
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: fechaController,
                      decoration: _decoracionAnulacion(
                        "Fecha de anulación, ejemplo 2026-06-26",
                        Icons.calendar_month_outlined,
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: detalleController,
                      maxLines: 5,
                      decoration: _decoracionAnulacion(
                        "Detalle de la anulación",
                        Icons.notes_outlined,
                      ),
                    ),

                    const SizedBox(height: 16),

                    CheckboxListTile(
                      value: confirmacion,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        "Confirmo que quiero anular esta póliza",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        "La póliza quedará marcada como ANULADA en el sistema.",
                      ),
                      onChanged: guardando
                          ? null
                          : (value) {
                              setDialogState(() {
                                confirmacion = value ?? false;
                              });
                            },
                    ),

                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: guardando ? null : () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                            label: const Text("Cancelar"),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: guardando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.cancel),
                            label: Text(guardando ? "Anulando..." : "Anular póliza"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: !confirmacion || guardando
                                ? null
                                : () async {
                                    setDialogState(() {
                                      guardando = true;
                                    });

                                    try {
                                      await Supabase.instance.client
                                          .from('anulaciones_poliza')
                                          .insert({
                                            'venta_id': ventaId,
                                            'poliza': poliza,
                                            'motivo': motivoSeleccionado,
                                            'detalle': detalleController.text.trim(),
                                            'fecha_anulacion': fechaController.text.trim(),
                                            'estado': 'ANULADA',
                                            'usuario': Supabase.instance.client.auth.currentUser?.email,
                                          });

                                      await Supabase.instance.client
                                          .from('ventas')
                                          .update({
                                            'estado_poliza': 'ANULADA',
                                          })
                                          .eq('id', ventaId);

                                      Navigator.pop(context);

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Póliza anulada correctamente"),
                                          backgroundColor: Colors.green,
                                        ),
                                      );

                                      setState(() {});
                                    } catch (e) {
                                      setDialogState(() {
                                        guardando = false;
                                      });

                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("Error al anular la póliza: $e"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  detalleController.dispose();
  fechaController.dispose();
}
InputDecoration _decoracionAnulacion(String label, IconData icon) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.grey.shade50,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Colors.red, width: 1.6),
    ),
  );
}
}
class TablaConScrollHorizontalERP extends StatefulWidget {
  final Widget child;

  const TablaConScrollHorizontalERP({
    super.key,
    required this.child,
  });

  @override
  State<TablaConScrollHorizontalERP> createState() =>
      _TablaConScrollHorizontalERPState();
}

class _TablaConScrollHorizontalERPState
    extends State<TablaConScrollHorizontalERP> {
  final ScrollController horizontalController = ScrollController();

  @override
  void dispose() {
    horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: horizontalController,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      thickness: 12,
      radius: const Radius.circular(20),
      child: SingleChildScrollView(
        controller: horizontalController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 16),
        child: widget.child,
      ),
    );
  }
}