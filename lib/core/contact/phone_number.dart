/// Conserva el prefijo introducido; nunca presupone que el país sea España.
String normalizePhoneNumber(String value) {
  final compact = value.trim().replaceAll(RegExp(r'[\s().-]'), '');
  return compact.startsWith('00') ? '+${compact.substring(2)}' : compact;
}

String? validatePhoneNumber(String? value) {
  if (value == null || value.trim().isEmpty) return 'Introduce un teléfono';
  if (!RegExp(r'^\+?[0-9\s().-]+$').hasMatch(value.trim())) {
    return 'Usa números y, si corresponde, el prefijo + o 00';
  }
  final phone = normalizePhoneNumber(value);
  final digits = phone.startsWith('+') ? phone.substring(1) : phone;
  if (digits.length < 7 || digits.length > 15) {
    return 'Introduce entre 7 y 15 dígitos, incluido el prefijo';
  }
  return null;
}
