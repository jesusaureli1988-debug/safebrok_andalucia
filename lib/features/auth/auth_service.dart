import '../../core/supabase_client.dart';

class AuthService {

/// 🔥 Devuelve parent según jerarquía
Future<String?> getParentId(String role) async {
try {


  if (role == 'director_zona') return null;

  String parentRole;

  switch (role) {
    case 'jefe_ventas':
      parentRole = 'director_zona';
      break;

    case 'jefe_equipo':
      parentRole = 'jefe_ventas';
      break;

    case 'agente':
      parentRole = 'jefe_equipo';
      break;

    default:
      return null;
  }

  final response = await supabase
      .from('usuarios')
      .select('id')
      .eq('rol_usuario', parentRole)
      .limit(1)
      .maybeSingle();

  if (response == null) return null;

  return response['id'];

} catch (e) {
  return null;
}


}

/// 🔥 REGISTRO
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
}) async {


try {

  // COMPROBAR SI YA EXISTE
  final existing = await supabase
      .from('usuarios')
      .select('id')
      .eq('email', email)
      .maybeSingle();

  if (existing != null) {
    return "Este email ya existe";
  }

  // CREAR EN AUTH
  final authResponse = await supabase.auth.signUp(
    email: email,
    password: password,
  );

  final user = authResponse.user;

  if (user == null) {
    return "Error creando usuario";
  }

  final parentId = await getParentId(role);

  // GUARDAR PERFIL
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
    'password': password,
    'rol_usuario': role,
    'parent_id': parentId,
    'estado': 'activo',
  });

  return null;

} catch (e) {
  return e.toString();
}


}

/// 🔐 LOGIN REAL SUPABASE AUTH
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
    return "Credenciales incorrectas";
  }

  return null;

} catch (e) {
  return e.toString();
}


}
}
