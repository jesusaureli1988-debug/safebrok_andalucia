import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';
import 'password_recovery_state.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> updatePassword() async {
    if (loading) return;

    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => loading = true);

    try {
      final response =
          await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          password: passwordController.text,
        ),
      );

      if (response.user == null) {
        throw const AuthException(
          'No se ha podido actualizar la contraseña.',
        );
      }

      await Supabase.instance.client.auth.signOut();

      PasswordRecoveryState.finish();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF087A6A),
          content: Text(
            'Contraseña actualizada correctamente.',
          ),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(
            'Error: ${e.message}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            'No se ha podido cambiar la contraseña.',
          ),
        ),
      );

      debugPrint('Error cambiando contraseña: $e');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required bool obscure,
    required VoidCallback onVisibilityPressed,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFFB7C9D6),
      ),
      prefixIcon: const Icon(
        Icons.lock_outline_rounded,
        color: Color(0xFF35D6E8),
      ),
      suffixIcon: IconButton(
        onPressed: onVisibilityPressed,
        icon: Icon(
          obscure
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: Colors.white60,
        ),
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: Colors.white.withOpacity(0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFF35D6E8),
          width: 1.5,
        ),
      ),
      errorStyle: const TextStyle(
        color: Color(0xFFFFA6A6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF06111B),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF06111B),
                Color(0xFF0B2434),
                Color(0xFF0B3546),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 500,
                  ),
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        width: 130,
                        height: 130,
                        fit: BoxFit.contain,
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        'Nueva contraseña',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'Escribe y confirma la contraseña que utilizarás para entrar en SafeBrok.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.60),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 28),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.10),
                          ),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: passwordController,
                                enabled: !loading,
                                obscureText: obscurePassword,
                                textInputAction:
                                    TextInputAction.next,
                                style: const TextStyle(
                                  color: Colors.white,
                                ),
                                decoration: _inputDecoration(
                                  label: 'Contraseña nueva',
                                  obscure: obscurePassword,
                                  onVisibilityPressed: () {
                                    setState(() {
                                      obscurePassword =
                                          !obscurePassword;
                                    });
                                  },
                                ),
                                validator: (value) {
                                  final password = value ?? '';

                                  if (password.isEmpty) {
                                    return 'Introduce la contraseña nueva';
                                  }

                                  if (password.length < 8) {
                                    return 'Debe tener al menos 8 caracteres';
                                  }

                                  if (!RegExp(r'[A-Z]')
                                      .hasMatch(password)) {
                                    return 'Añade una letra mayúscula';
                                  }

                                  if (!RegExp(r'[a-z]')
                                      .hasMatch(password)) {
                                    return 'Añade una letra minúscula';
                                  }

                                  if (!RegExp(r'[0-9]')
                                      .hasMatch(password)) {
                                    return 'Añade al menos un número';
                                  }

                                  return null;
                                },
                              ),

                              const SizedBox(height: 18),

                              TextFormField(
                                controller:
                                    confirmPasswordController,
                                enabled: !loading,
                                obscureText:
                                    obscureConfirmPassword,
                                textInputAction:
                                    TextInputAction.done,
                                style: const TextStyle(
                                  color: Colors.white,
                                ),
                                decoration: _inputDecoration(
                                  label: 'Repite la contraseña',
                                  obscure:
                                      obscureConfirmPassword,
                                  onVisibilityPressed: () {
                                    setState(() {
                                      obscureConfirmPassword =
                                          !obscureConfirmPassword;
                                    });
                                  },
                                ),
                                validator: (value) {
                                  if ((value ?? '').isEmpty) {
                                    return 'Repite la contraseña';
                                  }

                                  if (value !=
                                      passwordController.text) {
                                    return 'Las contraseñas no coinciden';
                                  }

                                  return null;
                                },
                                onFieldSubmitted: (_) {
                                  updatePassword();
                                },
                              ),

                              const SizedBox(height: 24),

                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed:
                                      loading ? null : updatePassword,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF1687D8),
                                    disabledBackgroundColor:
                                        const Color(0xFF45606F),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: loading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'GUARDAR CONTRASEÑA',
                                          style: TextStyle(
                                            fontWeight:
                                                FontWeight.w900,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        'Debe contener al menos 8 caracteres, una mayúscula, una minúscula y un número.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.42),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}