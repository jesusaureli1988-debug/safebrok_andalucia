import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/production/policy_effect_date.dart';

void main() {
  test(
    'El cargo usa mes y año configurados aunque el final exclusivo sea otro mes',
    () {
      expect(
        PolicyEffectDate.configuredMonth(DateTime(2026, 1, 31), [
          {
            'anio': 2026,
            'mes': 1,
            'fecha_desde': '2026-01-01',
            'fecha_hasta': '2026-01-31',
          },
        ]),
        DateTime(2026, 1),
      );
    },
  );
  test('Importar en octubre no mueve el efecto de enero', () {
    expect(
      PolicyEffectDate.read({
        'fecha_efecto': '2026-01-20',
        'created_at': '2026-10-07',
        'fecha': '2026-10-07',
      }),
      DateTime(2026, 1, 20),
    );
  });
  test('Sin efecto no se usa emisión o importación', () {
    expect(
      PolicyEffectDate.read({
        'created_at': '2026-10-07',
        'fecha': '2026-10-07',
      }),
      isNull,
    );
    expect(
      PolicyEffectDate.read({
        'fecha_efecto': 'incorrecta',
        'created_at': '2026-10-07',
      }),
      isNull,
    );
  });
  test('Fecha de efecto se compara por día completo', () {
    expect(
      PolicyEffectDate.read({'fecha_efecto': '2026-09-23T23:59:59'}),
      DateTime(2026, 9, 23),
    );
  });
}
