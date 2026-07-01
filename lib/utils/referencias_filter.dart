bool esReferenciaActiva(
  Map<String, dynamic> r,
  DateTime now,
) {
  final estado = r['estado'];

  if (estado == 'Resuelto' ||
      estado == 'Contratado' ||
      estado == 'Desechado') {
    return false;
  }

  DateTime? vencimiento = r['fecha_vencimiento'] != null
      ? DateTime.parse(r['fecha_vencimiento'])
      : null;

  DateTime? rellamada = r['fecha_rellamada'] != null
      ? DateTime.parse(r['fecha_rellamada'])
      : null;

  bool okVencimiento = vencimiento != null &&
      vencimiento.isBefore(
        DateTime(now.year, now.month + 2, now.day),
      );

  bool okRellamada = false;

  if (rellamada != null) {
    final inicio = rellamada.subtract(
      const Duration(days: 1),
    );
    final fin = rellamada.add(
      const Duration(days: 2),
    );

    okRellamada =
        now.isAfter(inicio) && now.isBefore(fin);
  }

  if (estado == 'En curso') {
    return okRellamada;
  }

  if (estado == 'Pendiente') {
    return okVencimiento;
  }

  return false;
}