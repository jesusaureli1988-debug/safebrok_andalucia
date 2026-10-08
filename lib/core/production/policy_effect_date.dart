/// Fecha exclusiva para imputar producción: nunca emisión ni importación.
class PolicyEffectDate {
  static DateTime? configuredMonth(
    DateTime date,
    List<Map<String, dynamic>> closures,
  ) {
    final day = DateTime(date.year, date.month, date.day);
    for (final closure in closures) {
      final from = DateTime.tryParse((closure['fecha_desde'] ?? '').toString());
      final to = DateTime.tryParse((closure['fecha_hasta'] ?? '').toString());
      final year = int.tryParse((closure['anio'] ?? '').toString());
      final month = int.tryParse((closure['mes'] ?? '').toString());
      if (from == null || to == null || year == null || month == null) continue;
      if (!day.isBefore(DateTime(from.year, from.month, from.day)) &&
          !day.isAfter(DateTime(to.year, to.month, to.day)))
        return DateTime(year, month);
    }
    return null;
  }

  static DateTime? read(Map<String, dynamic> sale) {
    for (final key in const [
      'fecha_efecto',
      'FECHA_EFECTO',
      'fecha efecto',
      'FECHA EFECTO',
    ]) {
      final value = sale[key];
      final parsed = value is DateTime
          ? value
          : DateTime.tryParse((value ?? '').toString());
      if (parsed != null)
        return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return null;
  }
}
