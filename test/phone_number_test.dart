import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/contact/phone_number.dart';

void main() {
  test('acepta números españoles e internacionales sin imponer +34', () {
    for (final phone in [
      '612345678',
      '+34 612 345 678',
      '+44 7700 900123',
      '0049 15123456789',
      '+1 (202) 555-0123',
      '+212 612345678',
      '+351 912 345 678',
      '0612345678',
    ]) {
      expect(validatePhoneNumber(phone), isNull, reason: phone);
    }
    expect(normalizePhoneNumber('612 345 678'), '612345678');
    expect(normalizePhoneNumber('0049 15123456789'), '+4915123456789');
    expect(normalizePhoneNumber('+1 (202) 555-0123'), '+12025550123');
    expect(normalizePhoneNumber('0612345678'), '0612345678');
  });
  test('rechaza texto, prefijos mal situados y longitudes inválidas', () {
    for (final phone in [
      '',
      'abc',
      '+44+7700900123',
      '123',
      '+1234567890123456',
    ]) {
      expect(validatePhoneNumber(phone), isNotNull, reason: phone);
    }
  });
}
