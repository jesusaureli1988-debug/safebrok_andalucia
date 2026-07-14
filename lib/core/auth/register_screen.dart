import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/auth/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nombreController = TextEditingController();
  final apellidosController = TextEditingController();
  final direccionController = TextEditingController();
  final numeroController = TextEditingController();
  final codigoPostalController = TextEditingController();
  final provinciaController = TextEditingController();
  final localidadController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final repeatPasswordController = TextEditingController();

  bool loading = false;
  bool showPassword = false;
  bool showRepeatPassword = false;

  String selectedRole = 'agente';

  // -------------------------------
  // 🚀 REGISTER
  // -------------------------------
  Future<void> register() async {
    if (loading) return;

    final nombre = nombreController.text.trim();
    final apellidos = apellidosController.text.trim();
    final direccion = direccionController.text.trim();
    final numero = numeroController.text.trim();
    final cp = codigoPostalController.text.trim();
    final provincia = provinciaController.text.trim();
    final localidad = localidadController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final repeat = repeatPasswordController.text.trim();

    // 🔴 VALIDACIÓN SIMPLE
    if ([nombre, apellidos, direccion, numero, cp, provincia, localidad, email, password, repeat]
        .any((e) => e.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Todos los campos son obligatorios")),
      );
      return;
    }

    if (password != repeat) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Las contraseñas no coinciden")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final auth = AuthService();

      final error = await auth.registerUser(
        nombre: nombre,
        apellidos: apellidos,
        direccion: direccion,
        numeroDireccion: numero,
        codigoPostal: cp,
        provincia: provincia,
        localidad: localidad,
        email: email,
        password: password,
        role: selectedRole,
      );

      if (!mounted) return;

      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Usuario registrado correctamente")),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  // -------------------------------
  // 🎨 INPUTS
  // -------------------------------
  Widget customField({
    required TextEditingController controller,
    required String hint,
    bool password = false,
    bool showPasswordValue = false,
    VoidCallback? togglePassword,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        obscureText: password ? !showPasswordValue : false,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          suffixIcon: password
              ? IconButton(
                  onPressed: togglePassword,
                  icon: Icon(
                    showPasswordValue ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white70,
                  ),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    nombreController.dispose();
    apellidosController.dispose();
    direccionController.dispose();
    numeroController.dispose();
    codigoPostalController.dispose();
    provinciaController.dispose();
    localidadController.dispose();
    emailController.dispose();
    passwordController.dispose();
    repeatPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 🌌 Fondo
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF08121C),
                  Color(0xFF102331),
                  Color(0xFF16384D),
                ],
              ),
            ),
          ),

          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withOpacity(0.15)),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [

                  // ROLE
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedRole,
                        dropdownColor: const Color(0xFF102331),
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: 'director_zona', child: Text('Director Zona')),
                          DropdownMenuItem(value: 'jefe_ventas', child: Text('Jefe Ventas')),
                          DropdownMenuItem(value: 'jefe_equipo', child: Text('Jefe Equipo')),
                          DropdownMenuItem(value: 'agente', child: Text('Agente')),
                        ],
                        onChanged: (value) {
                          setState(() => selectedRole = value!);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  const Text(
                    "Crear Cuenta",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 30),

                  customField(controller: nombreController, hint: "Nombre"),
                  customField(controller: apellidosController, hint: "Apellidos"),
                  customField(controller: direccionController, hint: "Dirección"),
                  customField(controller: numeroController, hint: "Número / Piso"),
                  customField(controller: codigoPostalController, hint: "Código Postal"),
                  customField(controller: provinciaController, hint: "Provincia"),
                  customField(controller: localidadController, hint: "Localidad"),
                  customField(controller: emailController, hint: "Email"),

                  customField(
                    controller: passwordController,
                    hint: "Contraseña",
                    password: true,
                    showPasswordValue: showPassword,
                    togglePassword: () => setState(() {
                      showPassword = !showPassword;
                    }),
                  ),

                  customField(
                    controller: repeatPasswordController,
                    hint: "Repetir contraseña",
                    password: true,
                    showPasswordValue: showRepeatPassword,
                    togglePassword: () => setState(() {
                      showRepeatPassword = !showRepeatPassword;
                    }),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: loading ? null : register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E88E5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "CREAR CUENTA",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}