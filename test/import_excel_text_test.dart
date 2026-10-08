import 'dart:convert';
import 'package:excel/excel.dart' as excel;
import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/import_excel_text.dart';

void main() {
  test(
    'Un Excel real conserva textos y permite codificar los datos de importacion',
    () {
      final libro = excel.Excel.createExcel();
      libro['Polizas'].appendRow([
        excel.TextCellValue('Compañía'),
        excel.TextCellValue('Dirección'),
      ]);
      libro['Polizas'].appendRow([
        excel.TextCellValue('Seguros Ejemplo'),
        excel.TextCellValue('Calle Andalucía 12'),
      ]);
      final leido = excel.Excel.decodeBytes(libro.encode()!);
      final fila = leido['Polizas'].rows[1];
      final compania = fila[0]!.value as excel.TextCellValue;
      final direccion = fila[1]!.value as excel.TextCellValue;
      // Reproduce el fallo anterior: el valor interno no es un texto JSON.
      expect(
        () => jsonEncode({'compania': compania.value}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      final envio = jsonEncode({
        'cliente_datos': {'direccion': importExcelText(direccion)},
        'venta_datos': {'compania': importExcelText(compania)},
      });
      final recuperado = jsonDecode(envio) as Map<String, dynamic>;
      expect(recuperado['cliente_datos']['direccion'], 'Calle Andalucía 12');
      expect(recuperado['venta_datos']['compania'], 'Seguros Ejemplo');
    },
  );
}
