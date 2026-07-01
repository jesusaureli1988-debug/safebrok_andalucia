class RolePermissions {
  static bool isDirector(String role) => role == 'director_zona';

  static bool isJefeVentas(String role) => role == 'jefe_ventas';

  static bool isJefeEquipo(String role) => role == 'jefe_equipo';

  static bool isAgente(String role) => role == 'agente';
}