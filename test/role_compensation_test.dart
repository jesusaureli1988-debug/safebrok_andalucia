import 'package:flutter_test/flutter_test.dart';
import 'package:safebrok_andalucia/core/payroll/role_compensation.dart';

void main() {
  group('RoleCompensationRules', () {
    test('agente conserva sus tramos actuales', () {
      final result = RoleCompensationRules.calculate(
        role: 'agente',
        premiums: 6000,
        deathAndLifePremiums: 1800,
      );
      expect(result.rappel, 800);
      expect(result.variable, 0);
    });

    test('jefe de equipo: 800 de rappel y 10% del exceso', () {
      final threshold = RoleCompensationRules.calculate(
        role: 'jefe_equipo',
        premiums: 4000,
        deathAndLifePremiums: 1200,
      );
      final above = RoleCompensationRules.calculate(
        role: 'jefe_equipo',
        premiums: 5500,
        deathAndLifePremiums: 1650,
      );
      expect(threshold.rappel, 800);
      expect(threshold.variable, 0);
      expect(above.rappel, 800);
      expect(above.variable, 150);
      expect(above.total, 950);
    });

    test('jefe de ventas: 1500 de rappel y 10% del exceso', () {
      final result = RoleCompensationRules.calculate(
        role: 'jefe_ventas',
        premiums: 8000,
        deathAndLifePremiums: 2400,
      );
      expect(result.rappel, 1500);
      expect(result.variable, 150);
      expect(result.total, 1650);
    });

    test('director de zona: 1500 desde 15500 y 10% del exceso', () {
      final threshold = RoleCompensationRules.calculate(
        role: 'director_zona',
        premiums: 15500,
        deathAndLifePremiums: 4650,
      );
      final above = RoleCompensationRules.calculate(
        role: 'director_zona',
        premiums: 17500,
        deathAndLifePremiums: 5250,
      );
      expect(threshold.total, 1500);
      expect(above.rappel, 1500);
      expect(above.variable, 200);
      expect(above.total, 1700);
    });

    test('las figuras responsables necesitan mix minimo del 30%', () {
      for (final role in ['jefe_equipo', 'jefe_ventas', 'director_zona']) {
        final result = RoleCompensationRules.calculate(
          role: role,
          premiums: 20000,
          deathAndLifePremiums: 5999,
        );
        expect(result.total, 0, reason: role);
      }
    });
  });
}
