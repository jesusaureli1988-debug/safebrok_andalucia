import '../../core/supabase_client.dart';

class AuthService {
  String _normalizarRol(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  Set<String> _rolesJefePermitidos(String role) {
    switch (_normalizarRol(role)) {
      case 'agente':
        return {'jefe_equipo', 'jefe_ventas', 'director_zona'};
      case 'jefe_equipo':
        return {'jefe_ventas', 'director_zona'};
      case 'jefe_ventas':
        return {'director_zona'};
      case 'director_zona':
        return {};
      default:
        return {};
    }
  }

  Future<String?> registerUser({
    required String nombre,
    required String apellidos,
    required String direccion,
    required String numeroDireccion,
    required String codigoPostal,
    required String provincia,
    required String localidad,
    required String email,
    required String password,
    required String role,
    required String? parentId,
  }) async {
    try {
      final roleNormalizado = _normalizarRol(role);
      final rolesPermitidos = _rolesJefePermitidos(roleNormalizado);

      if (roleNormalizado != 'director_zona' &&
          (parentId == null || parentId.trim().isEmpty)) {
        return 'Debes elegir un jefe';
      }

      String? parentIdValidado;

      if (parentId != null && parentId.trim().isNotEmpty) {
        final jefe = await supabase
            .from('usuarios')
            .select('id, rol_usuario')
            .eq('id', parentId.trim())
            .maybeSingle();

        if (jefe == null) {
          return 'El jefe seleccionado ya no está disponible';
        }

        final rolJefe = _normalizarRol(jefe['rol_usuario']);

        if (!rolesPermitidos.contains(rolJefe)) {
          return 'El jefe seleccionado no es válido para este rol';
        }

        parentIdValidado = jefe['id'].toString();
      }

      final existing = await supabase
          .from('usuarios')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (existing != null) {
        return 'Este email ya existe';
      }

      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      final user = authResponse.user;

      if (user == null) {
        return 'Error creando usuario';
      }

      await supabase.from('usuarios').insert({
        'auth_id': user.id,
        'nombre': nombre,
        'apellidos': apellidos,
        'direccion': direccion,
        'numero_direccion': numeroDireccion,
        'codigo_postal': codigoPostal,
        'provincia': provincia,
        'localidad': localidad,
        'email': email,
        'rol_usuario': roleNormalizado,
        'parent_id': parentIdValidado,
        'estado': 'activo',
      });

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return 'Credenciales incorrectas';
      }

      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
