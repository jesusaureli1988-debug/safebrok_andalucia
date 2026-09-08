import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';

void main() {
  test('Auto anterior al 27/08/2026 computa al 100 %', () {
    final venta = <String, dynamic>{
      'producto': 'Auto',
      'fecha_efecto': '2026-08-26',
      'prima_anual_neta': 1000,
    };
    expect(PremiumWeighting.net(venta), 1000);
  });

  test('Auto desde el 27/08/2026 computa al 50 %', () {
    final venta = <String, dynamic>{
      'producto': 'Seguro de Auto',
      'fecha_efecto': '2026-08-27',
      'prima_anual_neta': 1000,
      'prima_anual_bruta': 1200,
    };
    expect(PremiumWeighting.net(venta), 500);
    expect(PremiumWeighting.gross(venta), 600);
  });

  test('Otros ramos conservan el 100 % despues de la fecha de corte', () {
    final venta = <String, dynamic>{
      'producto': 'Decesos',
      'fecha_efecto': '2026-09-01',
      'prima_anual_neta': 1000,
    };
    expect(PremiumWeighting.net(venta), 1000);
  });

  test('Un extorno de Auto usa la fecha de efecto original', () {
    final venta = <String, dynamic>{
      'producto': 'Vehiculos',
      'fecha_efecto_poliza': '2026-08-27',
      'fecha_efecto': '2026-10-01',
    };
    expect(PremiumWeighting.amount(venta, 300), 150);
  });
}
