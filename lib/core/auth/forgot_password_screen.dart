import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const resetUrl =
      'https://safebrok-acceso-47f45.web.app/crear-password.html';

  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  bool loading = false;
  bool sent = false;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> sendResetEmail() async {
    if (loading || !(formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        emailController.text.trim().toLowerCase(),
        redirectTo: resetUrl,
      );
      if (!mounted) return;
      setState(() => sent = true);
    } on AuthException catch (error) {
      if (!mounted) return;
      final limited =
          error.message.toLowerCase().contains('rate') ||
          error.message.toLowerCase().contains('too many');
      _showError(
        limited
            ? 'Has solicitado demasiados correos. Espera unos minutos e inténtalo de nuevo.'
            : 'No se pudo enviar el correo. Comprueba la dirección e inténtalo de nuevo.',
      );
    } catch (_) {
      if (mounted) {
        _showError(
          'No se pudo conectar con el servidor. Comprueba tu conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB42318),
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      backgroundColor: const Color(0xFFF2FCFD),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2FCFD), Color(0xFF0B2434), Color(0xFF0B3546)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: desktop ? 32 : 8,
                top: 8,
                child: IconButton(
                  tooltip: 'Volver',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: desktop ? 48 : 22,
                    vertical: 70,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: desktop ? 560 : 500),
                    child: sent ? _successCard() : _requestCard(desktop),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _requestCard(bool desktop) => _card(
    child: Form(
      key: formKey,
      child: Column(
        children: [
          Image.asset(
            'assets/images/logo.png',
            width: desktop ? 120 : 96,
            height: desktop ? 120 : 96,
          ),
          const SizedBox(height: 18),
          Text(
            'Recuperar contraseña',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF071A3A),
              fontSize: desktop ? 30 : 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Introduce el correo de tu cuenta. Te enviaremos un enlace que funciona desde móvil, tablet u ordenador.',
            textAlign: TextAlign.center,
            style: TextStyle(color: const Color(0xFF53627A), height: 1.5),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: emailController,
            enabled: !loading,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(color: const Color(0xFF071A3A)),
            decoration: InputDecoration(
              labelText: 'Correo electrónico',
              hintText: 'nombre@correo.com',
              labelStyle: const TextStyle(color: Color(0xFFB7C9D6)),
              hintStyle: TextStyle(color: const Color(0xFF53627A)),
              prefixIcon: const Icon(
                Icons.alternate_email_rounded,
                color: Color(0xFF20C7C2),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: .14),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF20C7C2),
                  width: 1.5,
                ),
              ),
              errorStyle: const TextStyle(color: Color(0xFFFFA6A6)),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'Introduce tu correo electrónico';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                return 'Introduce un correo válido';
              }
              return null;
            },
            onFieldSubmitted: (_) => sendResetEmail(),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: loading ? null : sendResetEmail,
              icon: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.mark_email_read_outlined),
              label: Text(
                loading ? 'Enviando…' : 'Enviar enlace de recuperación',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF168ADD),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _successCard() => _card(
    child: Column(
      children: [
        const Icon(
          Icons.mark_email_read_rounded,
          size: 72,
          color: Color(0xFF20C7C2),
        ),
        const SizedBox(height: 20),
        const Text(
          'Revisa tu correo',
          style: TextStyle(
            color: const Color(0xFF071A3A),
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Si existe una cuenta asociada a ${emailController.text.trim()}, recibirás un enlace para crear una nueva contraseña. Revisa también la carpeta de correo no deseado.',
          textAlign: TextAlign.center,
          style: TextStyle(color: const Color(0xFF53627A), height: 1.55),
        ),
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Volver al inicio de sesión'),
          ),
        ),
      ],
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(
      color: const Color(0xFF0B1E2B).withValues(alpha: .94),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 36, offset: Offset(0, 18)),
      ],
    ),
    child: child,
  );
}
