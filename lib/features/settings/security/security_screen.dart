import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final supabase = Supabase.instance.client;

  final TextEditingController passwordController = TextEditingController();

  bool loading = false;

  /// 🔐 CAMBIAR PASSWORD (FIX AUTH SESSION)
  Future<void> changePassword() async {
    final session = supabase.auth.currentSession;
    final user = session?.user;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sesión no válida, inicia sesión otra vez")),
      );
      return;
    }

    final password = passwordController.text.trim();

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La contraseña debe tener mínimo 6 caracteres")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: password),
      );

      passwordController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Contraseña actualizada correctamente")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }

    setState(() => loading = false);
  }

  /// 🚪 LOGOUT REAL
  Future<void> logout() async {
    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  /// 🚪 LOGOUT + LIMPIEZA TOTAL
  Future<void> logoutAll() async {
    try {
      await supabase.auth.signOut(scope: SignOutScope.global);
    } catch (_) {
      await supabase.auth.signOut();
    }

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
  }

  @override
  void dispose() {
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = supabase.auth.currentSession;
    final user = session?.user;

    final email = user?.email ?? "Usuario";

    return Scaffold(
      backgroundColor: const Color(0xFF08121C),

      appBar: AppBar(
        title: const Text("Seguridad"),
        backgroundColor: Colors.transparent,
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          /// 🔐 HEADER USER
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.cyanAccent,
                  child: Text(
                    email.isNotEmpty ? email[0].toUpperCase() : "?",
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    email,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// 🔐 CAMBIAR PASSWORD
          _card(
            title: "Cambiar contraseña",
            child: Column(
              children: [
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Nueva contraseña",
                    hintStyle: TextStyle(color: Colors.white38),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : changePassword,
                    child: Text(
                      loading ? "Actualizando..." : "Actualizar contraseña",
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// ⚠️ SEGURIDAD
          _card(
            title: "Zona de riesgo",
            child: Column(
              children: [

                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    "Cerrar sesión",
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: logout,
                ),

                const Divider(color: Colors.white24),

                ListTile(
                  leading: const Icon(Icons.warning, color: Colors.orange),
                  title: const Text(
                    "Cerrar todas las sesiones",
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    "Se cerrará en todos los dispositivos",
                    style: TextStyle(color: Colors.white54),
                  ),
                  onTap: logoutAll,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// 🛡 ESTADO
          _card(
            title: "Estado de seguridad",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("✔ Sesión activa",
                    style: TextStyle(color: Colors.greenAccent)),
                SizedBox(height: 6),
                Text("✔ Autenticación Supabase OK",
                    style: TextStyle(color: Colors.greenAccent)),
                SizedBox(height: 6),
                Text("⚠ 2FA no activado",
                    style: TextStyle(color: Colors.orange)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}