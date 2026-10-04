class PremiumWeighting {
  static final DateTime autoCutoff = DateTime(2026, 8, 27);

  static String _text(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u');

  static double number(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final raw = value.toString().trim();
    if (raw.isEmpty) return 0;
    final normalized = raw.contains(',')
        ? raw.replaceAll('.', '').replaceAll(',', '.')
        : raw;
    return double.tryParse(normalized) ?? 0;
  }

  static bool isAuto(dynamic product) {
    final value = _text(product);
    return value.contains('auto') ||
        value.contains('coche') ||
        value.contains('vehicul') ||
        value.contains('turismo') ||
        value.contains('moto') ||
        value.contains('camion');
  }

  static DateTime? effectDate(Map<String, dynamic> sale) {
    for (final key in const [
      'fecha_efecto_poliza',
      'fecha_efecto',
      'FECHA_EFECTO',
      'FECHA EFECTO',
    ]) {
      final value = sale[key];
      if (value == null) continue;
      final parsed = value is DateTime
          ? value
          : DateTime.tryParse(value.toString());
      if (parsed != null)
        return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return null;
  }

  static double factor(Map<String, dynamic> sale) {
    if (!isAuto(sale['producto'] ?? sale['ramo'] ?? sale['tipo_seguro']))
      return 1;
    final date = effectDate(sale);
    // Desde el cargo de septiembre de 2026, Auto conserva su prima real
    // para comisiones, pero no aporta producción computable.
    return date != null && !date.isBefore(autoCutoff) ? 0 : 1;
  }

  static double amount(Map<String, dynamic> sale, dynamic rawAmount) =>
      number(rawAmount) * factor(sale);

  static double net(Map<String, dynamic> sale) => amount(
    sale,
    sale['prima_anual_neta'] ??
        sale['prima_neta'] ??
        sale['PRIMA_ANUAL_NETA'] ??
        sale['PRIMA NETA'] ??
        sale['prima_anual'] ??
        sale['precio'],
  );

  static double gross(Map<String, dynamic> sale) => amount(
    sale,
    sale['prima_anual_bruta'] ??
        sale['prima_bruta'] ??
        sale['prima_total'] ??
        sale['prima_anual'] ??
        sale['prima_anual_neta'],
  );
}
