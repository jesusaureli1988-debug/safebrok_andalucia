/// Provincia correspondiente al prefijo postal español (códigos INE).
/// https://ine.es/daco/daco42/codmun/cod_provincia.htm
const _provincias = <String, String>{
  '01': 'Álava',
  '02': 'Albacete',
  '03': 'Alicante',
  '04': 'Almería',
  '05': 'Ávila',
  '06': 'Badajoz',
  '07': 'Illes Balears',
  '08': 'Barcelona',
  '09': 'Burgos',
  '10': 'Cáceres',
  '11': 'Cádiz',
  '12': 'Castellón',
  '13': 'Ciudad Real',
  '14': 'Córdoba',
  '15': 'A Coruña',
  '16': 'Cuenca',
  '17': 'Girona',
  '18': 'Granada',
  '19': 'Guadalajara',
  '20': 'Gipuzkoa',
  '21': 'Huelva',
  '22': 'Huesca',
  '23': 'Jaén',
  '24': 'León',
  '25': 'Lleida',
  '26': 'La Rioja',
  '27': 'Lugo',
  '28': 'Madrid',
  '29': 'Málaga',
  '30': 'Murcia',
  '31': 'Navarra',
  '32': 'Ourense',
  '33': 'Asturias',
  '34': 'Palencia',
  '35': 'Las Palmas',
  '36': 'Pontevedra',
  '37': 'Salamanca',
  '38': 'Santa Cruz de Tenerife',
  '39': 'Cantabria',
  '40': 'Segovia',
  '41': 'Sevilla',
  '42': 'Soria',
  '43': 'Tarragona',
  '44': 'Teruel',
  '45': 'Toledo',
  '46': 'Valencia',
  '47': 'Valladolid',
  '48': 'Bizkaia',
  '49': 'Zamora',
  '50': 'Zaragoza',
  '51': 'Ceuta',
  '52': 'Melilla',
};

String? importPostalCode(dynamic value) {
  if (value == null) return null;
  String text;
  if (value is num) {
    if (!value.isFinite || value != value.truncateToDouble())
      return value.toString();
    text = value.toInt().toString();
  } else {
    text = value.toString().trim();
  }
  if (text.isEmpty) return null;
  // Excel puede eliminar el cero inicial si el CP está como número.
  if (RegExp(r'^\d{4,5}$').hasMatch(text)) return text.padLeft(5, '0');
  return text;
}

String importProvince(dynamic province, dynamic postalCode) {
  final supplied = province?.toString().trim() ?? '';
  if (supplied.isNotEmpty) return supplied;
  final postal = importPostalCode(postalCode);
  if (postal != null && RegExp(r'^\d{5}$').hasMatch(postal)) {
    return _provincias[postal.substring(0, 2)] ?? 'No informada';
  }
  return 'No informada';
}

/// No deducir periodicidad a partir de la prima: el Excel no la informa.
String importPaymentFrequency(dynamic value) {
  final supplied = value?.toString().trim() ?? '';
  return supplied.isEmpty ? 'No informada' : supplied;
}

/// La dirección del Excel se conserva completa en direccion. Si no hay una
/// columna específica para el número, indicar ausencia sin inventar domicilio.
String importAddressNumber(dynamic value) {
  final supplied = value?.toString().trim() ?? '';
  return supplied.isEmpty ? 'No informado' : supplied;
}

/// La base exige contacto no nulo, pero el Excel puede no contenerlo.
/// Vacío expresa ausencia sin inventar emails ni teléfonos. Aplicar solo a
/// clientes nuevos; para actualizaciones se omiten los campos ausentes.
Map<String, dynamic> importNewClientContacts(Map<String, dynamic> data) => {
  ...data,
  'email': data['email']?.toString().trim() ?? '',
  'telefono': data['telefono']?.toString().trim() ?? '',
};
