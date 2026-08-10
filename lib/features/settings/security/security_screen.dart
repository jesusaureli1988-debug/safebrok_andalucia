import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/auth/login_screen.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final supabase = Supabase.instance.client;

  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  bool deletionLoading = false;
  Map<String, dynamic>? pendingDeletion;

  @override
  void initState() {
    super.initState();
    _loadDeletionRequest();
  }

  Future<void> _loadDeletionRequest() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final request = await supabase
        .from('solicitudes_eliminacion_cuenta')
        .select('id, estado, solicitado_at, fecha_limite')
        .eq('auth_id', user.id)
        .inFilter('estado', ['pendiente', 'en_proceso'])
        .maybeSingle();
    if (mounted) setState(() => pendingDeletion = request);
  }

  Future<void> requestAccountDeletion() async {
    if (deletionLoading || pendingDeletion != null) return;
    final reasonController = TextEditingController();
    final continueRequest = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Solicitar eliminación de cuenta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SafeBrok tramitará la eliminación en un máximo de 30 días. '
              'Se eliminará la cuenta y la información personal que no deba '
              'conservarse por obligaciones legales o contractuales.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (continueRequest != true || !mounted) {
      reasonController.dispose();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmación final'),
        content: const Text(
          'Esta acción iniciará formalmente la eliminación de tu cuenta. '
          '¿Quieres enviar la solicitud?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No, volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sí, solicitar eliminación'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      reasonController.dispose();
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      reasonController.dispose();
      return;
    }

    setState(() => deletionLoading = true);
    try {
      await supabase.from('solicitudes_eliminacion_cuenta').insert({
        'auth_id': user.id,
        'email': user.email,
        'motivo': reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      });
      await _loadDeletionRequest();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Solicitud registrada'),
          content: const Text(
            'Hemos recibido la solicitud. SafeBrok la tramitará en un máximo '
            'de 30 días y te informará cuando termine.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar la solicitud: ${error.message}')),
      );
    } finally {
      reasonController.dispose();
      if (mounted) setState(() => deletionLoading = false);
    }
  }

  /// 🔐 CAMBIAR PASSWORD (FIX AUTH SESSION)
  Future<void> changePassword() async {
    final session = supabase.auth.currentSession;
    final user = session?.user;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Sesión no válida, inicia sesión otra vez"),
        ),
      );
      return;
    }

    final password = passwordController.text.trim();

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("La contraseña debe tener mínimo 6 caracteres"),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      await supabase.auth.updateUser(UserAttributes(password: password));

      passwordController.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Contraseña actualizada correctamente")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }

    if (mounted) setState(() => loading = false);
  }

  /// 🚪 LOGOUT REAL
  Future<void> logout() async {
    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
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

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
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

                const Divider(color: Colors.white24),

                ListTile(
                  leading: const Icon(Icons.person_remove_rounded, color: Colors.redAccent),
                  title: Text(
                    pendingDeletion == null
                        ? 'Solicitar eliminación de mi cuenta'
                        : 'Eliminación de cuenta solicitada',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    pendingDeletion == null
                        ? 'Inicia la eliminación de la cuenta y los datos personales no sujetos a conservación legal.'
                        : 'La solicitud está ${pendingDeletion!['estado'] == 'en_proceso' ? 'en proceso' : 'pendiente'}. Plazo máximo: 30 días.',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: deletionLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: pendingDeletion == null && !deletionLoading
                      ? requestAccountDeletion
                      : null,
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
                Text(
                  "✔ Sesión activa",
                  style: TextStyle(color: Colors.greenAccent),
                ),
                SizedBox(height: 6),
                Text(
                  "✔ Autenticación Supabase OK",
                  style: TextStyle(color: Colors.greenAccent),
                ),
                SizedBox(height: 6),
                Text(
                  "⚠ 2FA no activado",
                  style: TextStyle(color: Colors.orange),
                ),
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
