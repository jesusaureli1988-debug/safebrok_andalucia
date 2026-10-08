import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/import_policy_defaults.dart';
import 'package:safebrok_andalucia/core/production/premium_weighting.dart';

void main() {
  test('Clientes nuevos sin contacto no envían null ni datos inventados', () {
    final cliente = importNewClientContacts({
      'nombre': 'Cliente',
      'email': null,
    });
    expect(cliente['email'], '');
    expect(cliente['telefono'], '');
    expect(cliente['nombre'], 'Cliente');
    final conContacto = importNewClientContacts({
      'email': 'cliente@example.com',
      'telefono': '600123456',
    });
    expect(conContacto['email'], 'cliente@example.com');
    expect(conContacto['telefono'], '600123456');
  });
  test(
    'Sin columna de número se conserva una indicación explícita no nula',
    () {
      expect(importAddressNumber(null), 'No informado');
      expect(importAddressNumber('  '), 'No informado');
      expect(importAddressNumber('12 B'), '12 B');
      expect(importAddressNumber(13), '13');
    },
  );
  test('Primas importadas sin periodicidad siguen siendo importes anuales', () {
    final venta = <String, dynamic>{
      'producto': 'Hogar',
      'forma_pago': importPaymentFrequency(null),
      'prima_anual_neta': 400.0,
      'prima_anual_bruta': 480.0,
      'prima_anual': 480.0,
      'precio': 480.0,
    };
    expect(PremiumWeighting.net(venta), 400.0);
    expect(PremiumWeighting.gross(venta), 480.0);
  });
  test(
    'Excel sin provincia y sin forma de pago satisface campos obligatorios',
    () {
      final cliente = {'provincia': importProvince(null, 41200)};
      final venta = {'forma_pago': importPaymentFrequency(null)};
      expect(cliente['provincia'], 'Sevilla');
      expect(venta['forma_pago'], 'No informada');
    },
  );
  test('Conserva datos explícitos y códigos postales con cero inicial', () {
    expect(importPostalCode(1001), '01001');
    expect(importProvince(null, 1001), 'Álava');
    expect(importProvince('Madrid', '41200'), 'Madrid');
    expect(importPaymentFrequency('Mensual'), 'Mensual');
  });
  test('Ausencia o CP inválido no inventa provincia ni periodicidad', () {
    expect(importProvince(null, null), 'No informada');
    expect(importProvince('', '99999'), 'No informada');
    expect(importProvince('', 'AB123'), 'No informada');
    expect(importPaymentFrequency('  '), 'No informada');
  });
}
