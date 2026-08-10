import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/auth/app_role.dart';

void main() {
  test('normaliza todos los formatos de rol admitidos', () {
    expect(AppRole.normalize(' Director-Nacional '), 'director_nacional');
    expect(AppRole.normalize('JEFE VENTAS'), 'jefe_ventas');
    expect(AppRole.normalize('admin'), 'administracion');
  });

  test('rechaza roles no reconocidos', () {
    expect(AppRole.from('reviewer'), isNull);
    expect(AppRole.from(''), isNull);
  });

  test('director nacional tiene acceso de liderazgo', () {
    expect(AppRole.isLeadership('director_nacional'), isTrue);
    expect(AppRole.isLeadership('agente'), isFalse);
  });
}
