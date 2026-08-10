enum AppRole {
  directorNacional('director_nacional', 'Director nacional'),
  administracion('administracion', 'Administración'),
  directorZona('director_zona', 'Director de zona'),
  jefeVentas('jefe_ventas', 'Jefe de ventas'),
  jefeEquipo('jefe_equipo', 'Jefe de equipo'),
  agente('agente', 'Agente comercial');

  const AppRole(this.value, this.label);

  final String value;
  final String label;

  static String normalize(dynamic value) {
    final normalized = (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if (normalized == 'admin' || normalized == 'administrador') {
      return administracion.value;
    }
    return normalized;
  }

  static AppRole? from(dynamic value) {
    final normalized = normalize(value);
    for (final role in values) {
      if (role.value == normalized) return role;
    }
    return null;
  }

  static bool isLeadership(dynamic value) {
    final role = from(value);
    return role == directorNacional ||
        role == administracion ||
        role == directorZona ||
        role == jefeVentas;
  }
}
