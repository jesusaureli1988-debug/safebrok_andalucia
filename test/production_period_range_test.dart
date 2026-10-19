import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/production/production_period_service.dart';

void main() {
  ProductionPeriod period(DateTime from, DateTime to) => ProductionPeriod(
    id: 'cargo',
    year: 2026,
    month: 10,
    from: from,
    to: to,
    status: 'abierto',
    configured: true,
  );
  test('El cargo incluye efecto del primer y ultimo dia, no emision', () {
    final cargo = period(DateTime(2026, 9, 24), DateTime(2026, 10, 23));
    expect(cargo.contains(DateTime(2026, 9, 24)), isTrue);
    expect(cargo.contains(DateTime(2026, 10, 23, 23, 59)), isTrue);
    expect(cargo.contains(DateTime(2026, 9, 23)), isFalse);
    expect(cargo.contains(DateTime(2026, 10, 24)), isFalse);
    expect(cargo.endExclusive, DateTime(2026, 10, 24));
  });
  test(
    'El limite exclusivo avanza un dia natural incluso al cambiar la hora',
    () {
      final cargo = period(DateTime(2026, 10, 1), DateTime(2026, 10, 25));
      expect(cargo.endExclusive, DateTime(2026, 10, 26));
    },
  );
}
