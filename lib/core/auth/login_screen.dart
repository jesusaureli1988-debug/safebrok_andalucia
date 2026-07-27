import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'role_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode emailFocusNode = FocusNode();
  final FocusNode passwordFocusNode = FocusNode();

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  bool loading = false;
  bool obscurePassword = true;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();

    emailFocusNode.dispose();
    passwordFocusNode.dispose();

    _animationController.dispose();

    super.dispose();
  }

  Future<void> login() async {
    if (loading) return;

    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => loading = true);

    try {
      final email = emailController.text.trim().toLowerCase();
      final password = passwordController.text;

      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user == null) {
        throw const AuthException(
          'No se ha podido identificar al usuario.',
        );
      }

      final profile = await supabase
          .from('usuarios')
          .select('id, auth_id, nombre, apellidos, rol_usuario')
          .eq('auth_id', user.id)
          .maybeSingle();

      if (profile == null) {
        await supabase.auth.signOut();

        if (!mounted) return;

        _showMessage(
          'Tu acceso es correcto, pero no existe un perfil asociado en SafeBrok.',
          isError: true,
        );

        return;
      }

      final role = profile['rol_usuario']?.toString().trim();

      if (role == null || role.isEmpty) {
        await supabase.auth.signOut();

        if (!mounted) return;

        _showMessage(
          'El usuario no tiene ningún rol asignado.',
          isError: true,
        );

        return;
      }

      if (!mounted) return;

      HapticFeedback.lightImpact();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => RoleRouter.getHomeByRole(role),
        ),
        (route) => false,
      );
    } on AuthException catch (error) {
      if (!mounted) return;

      _showMessage(
        _translateAuthError(error.message),
        isError: true,
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;

      _showMessage(
        'No se ha podido cargar el perfil del usuario. '
        'Código: ${error.code}',
        isError: true,
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        'No se ha podido iniciar sesión. Comprueba tu conexión.',
        isError: true,
      );

      debugPrint('Error LoginScreen.login: $error');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  String _translateAuthError(String message) {
    final normalized = message.toLowerCase();

    if (normalized.contains('invalid login credentials')) {
      return 'El correo o la contraseña no son correctos.';
    }

    if (normalized.contains('email not confirmed')) {
      return 'Debes confirmar tu correo electrónico antes de entrar.';
    }

    if (normalized.contains('too many requests') ||
        normalized.contains('rate limit')) {
      return 'Has realizado demasiados intentos. Espera unos minutos.';
    }

    if (normalized.contains('network') ||
        normalized.contains('socket') ||
        normalized.contains('connection')) {
      return 'No hay conexión con el servidor. Comprueba tu internet.';
    }

    return message;
  }

  void _showMessage(
    String message, {
    required bool isError,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFB42318)
              : const Color(0xFF087A6A),
          margin: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: Color(0xFFB7C9D6),
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.30),
      ),
      prefixIcon: Icon(
        icon,
        color: const Color(0xFF35D6E8),
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.055),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 19,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFF35D6E8),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFFF6B6B),
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFFF6B6B),
          width: 1.5,
        ),
      ),
      errorStyle: const TextStyle(
        color: Color(0xFFFFA6A6),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: const Color(0xFF06111B),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF06111B),
                    Color(0xFF0B2434),
                    Color(0xFF0B3546),
                    Color(0xFF08212E),
                  ],
                  stops: [0, 0.36, 0.72, 1],
                ),
              ),
            ),
          ),

          Positioned(
            top: -130,
            right: -100,
            child: _GlowCircle(
              size: 320,
              color: const Color(0xFF1D8FE1).withValues(alpha: 0.22),
            ),
          ),

          Positioned(
            bottom: -160,
            left: -120,
            child: _GlowCircle(
              size: 360,
              color: const Color(0xFF00D5C7).withValues(alpha: 0.16),
            ),
          ),

          Positioned(
            top: 170,
            left: -80,
            child: _GlowCircle(
              size: 220,
              color: const Color(0xFF35D6E8).withValues(alpha: 0.08),
            ),
          ),

          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 50,
                sigmaY: 50,
              ),
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 28,
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 500,
                      ),
                      child: Column(
                        children: [
                          _buildBrandHeader(),
                          const SizedBox(height: 30),
                          _buildLoginCard(),
                          const SizedBox(height: 24),
                          _buildRegisterSection(),
                          const SizedBox(height: 16),
                          Text(
                            'Acceso exclusivo para la red SafeBrok',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.38),
                              fontSize: screenWidth < 370 ? 11 : 12,
                              fontWeight: FontWeight.w500,
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
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
       Container(
  width: 170,
  height: 170,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(30),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF00D4FF).withValues(alpha: 0.35),
        blurRadius: 40,
        spreadRadius: 4,
      ),
    ],
  ),
  child: Image.asset(
    'assets/images/logo.png',
    fit: BoxFit.contain,
  ),
),
        const SizedBox(height: 20),
        const Text(
          'SafeBrok',
          style: TextStyle(
            color: Colors.white,
            fontSize: 35,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        
        const SizedBox(height: 14),
        Text(
          'Gestión, producción y crecimiento\npara toda tu red comercial',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            height: 1.45,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 22,
          sigmaY: 22,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            24,
            26,
            24,
            24,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1E2B).withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 35,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bienvenido de nuevo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Introduce tus datos para acceder a SafeBrok.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.52),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextFormField(
                    controller: emailController,
                    focusNode: emailFocusNode,
                    enabled: !loading,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _inputDecoration(
                      label: 'Correo electrónico',
                      hint: 'nombre@correo.com',
                      icon: Icons.alternate_email_rounded,
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';

                      if (email.isEmpty) {
                        return 'Introduce tu correo electrónico';
                      }

                      final validEmail = RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch(email);

                      if (!validEmail) {
                        return 'Introduce un correo válido';
                      }

                      return null;
                    },
                    onFieldSubmitted: (_) {
                      passwordFocusNode.requestFocus();
                    },
                  ),

                  const SizedBox(height: 17),

                  TextFormField(
                    controller: passwordController,
                    focusNode: passwordFocusNode,
                    enabled: !loading,
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [
                      AutofillHints.password,
                    ],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _inputDecoration(
                      label: 'Contraseña',
                      hint: 'Introduce tu contraseña',
                      icon: Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        tooltip: obscurePassword
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').isEmpty) {
                        return 'Introduce tu contraseña';
                      }

                      return null;
                    },
                    onFieldSubmitted: (_) => login(),
                  ),

                  const SizedBox(height: 10),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: loading
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ForgotPasswordScreen(),
                                ),
                              );
                            },
                      icon: const Icon(
                        Icons.key_rounded,
                        size: 17,
                      ),
                      label: const Text(
                        'He olvidado mi contraseña',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF35D6E8),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 13),

                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: loading
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF45606F),
                                  Color(0xFF45606F),
                                ],
                              )
                            : const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Color(0xFF187FD1),
                                  Color(0xFF15B9CB),
                                ],
                              ),
                        boxShadow: loading
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(0xFF15B9CB)
                                      .withValues(alpha: 0.25),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                      ),
                      child: ElevatedButton(
                        onPressed: loading ? null : login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: loading
                            ? const SizedBox(
                                width: 25,
                                height: 25,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'ENTRAR EN SAFEBROK',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  SizedBox(width: 9),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 21,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '¿Todavía no tienes acceso?',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.58),
            fontSize: 13,
          ),
        ),
        TextButton(
          onPressed: loading
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RegisterScreen(),
                    ),
                  );
                },
          child: const Text(
            'REGÍSTRATE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}