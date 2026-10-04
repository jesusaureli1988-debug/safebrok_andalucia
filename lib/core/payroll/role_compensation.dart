class RoleCompensation {
  final double rappel;
  final double variable;

  const RoleCompensation({required this.rappel, required this.variable});

  double get total => rappel + variable;
}

class RoleCompensationRules {
  const RoleCompensationRules._();

  static String normalizeRole(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('-', '_')
      .replaceAll(' ', '_');

  static double mixPercentage(double premiums, double deathAndLifePremiums) {
    if (premiums <= 0) return 0;
    return (deathAndLifePremiums / premiums * 100).clamp(0, 100).toDouble();
  }

  static RoleCompensation calculate({
    required String role,
    required double premiums,
    required double deathAndLifePremiums,
  }) {
    final normalizedRole = normalizeRole(role);
    final safePremiums = premiums < 0 ? 0.0 : premiums;
    final safeLife = deathAndLifePremiums < 0 ? 0.0 : deathAndLifePremiums;
    final mix = mixPercentage(safePremiums, safeLife);

    if (normalizedRole == 'agente') {
      return RoleCompensation(
        rappel: _agentRappel(safePremiums, mix),
        variable: 0,
      );
    }

    if (normalizedRole == 'jefe_equipo') {
      return _thresholdRule(
        premiums: safePremiums,
        mix: mix,
        threshold: 4000,
        baseRappel: 800,
      );
    }

    if (normalizedRole == 'jefe_ventas') {
      return _thresholdRule(
        premiums: safePremiums,
        mix: mix,
        threshold: 6500,
        baseRappel: 1500,
      );
    }

    if (normalizedRole == 'director_zona') {
      return _thresholdRule(
        premiums: safePremiums,
        mix: mix,
        threshold: 15500,
        baseRappel: 1500,
      );
    }

    if (normalizedRole == 'director_regional' ||
        normalizedRole == 'director_nacional') {
      return RoleCompensation(rappel: 0, variable: safePremiums * .05);
    }

    return const RoleCompensation(rappel: 0, variable: 0);
  }

  static RoleCompensation _thresholdRule({
    required double premiums,
    required double mix,
    required double threshold,
    required double baseRappel,
  }) {
    if (premiums < threshold || mix < 30) {
      return const RoleCompensation(rappel: 0, variable: 0);
    }
    return RoleCompensation(
      rappel: baseRappel,
      variable: (premiums - threshold) * .10,
    );
  }

  static double _agentRappel(double premiums, double mix) {
    if (premiums >= 12000 && mix >= 30) return 1500;
    if (premiums >= 9000 && mix >= 30) return 1200;
    if (premiums >= 6000 && mix >= 30) return 800;
    if (premiums >= 4000 && mix >= 30) return 600;
    if (premiums >= 2500 && mix >= 99.999) return 400;
    if (premiums >= 1500 && mix >= 99.999) return 200;
    return 0;
  }

  static String conditionForRole(String role) {
    switch (normalizeRole(role)) {
      case 'agente':
        return 'Comisiones propias y rappel según los tramos vigentes del agente.';
      case 'jefe_equipo':
        return '800 € de rappel desde 4.000 € y 10% sobre el exceso, con mix mínimo del 30%.';
      case 'jefe_ventas':
        return '1.500 € de rappel desde 6.500 € y 10% sobre el exceso, con mix mínimo del 30%.';
      case 'director_zona':
        return '1.500 € de rappel desde 15.500 € y 10% sobre el exceso, con mix mínimo del 30%.';
      case 'director_regional':
      case 'director_nacional':
        return 'Condiciones económicas vigentes sobre la producción ponderada de la estructura.';
      default:
        return 'Condiciones económicas configuradas para la figura del usuario.';
    }
  }
}
