import 'package:supabase_flutter/supabase_flutter.dart';

class UserService {
  final supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> getUserData() async {
    final user = supabase.auth.currentUser;

    if (user == null) return null;

    final response = await supabase
        .from('usuarios')
        .select()
        .eq('email', user.email!)
        .single();

    return response;
  }
}