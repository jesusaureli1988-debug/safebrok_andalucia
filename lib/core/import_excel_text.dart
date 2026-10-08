import 'package:excel/excel.dart' as excel;

/// Excel 4 almacena el texto dentro de un TextSpan, que no es serializable
/// como JSON. Extraer siempre el texto, nunca el objeto interno.
String importExcelText(excel.TextCellValue cell) => cell.value.toString();
