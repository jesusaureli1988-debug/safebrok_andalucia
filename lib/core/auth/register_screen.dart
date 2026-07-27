import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/auth/auth_service.dart';
import 'package:safebrok_andalucia/core/supabase_client.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final formKey = GlobalKey<FormState>();

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
  bool loadingJefes = true;
  bool showPassword = false;
  bool showRepeatPassword = false;

  String selectedRole = 'agente';
  String? selectedParentId;
  List<Map<String, dynamic>> jefes = [];

  static const bg = Color(0xFF07111D);
  static const card = Color(0xFF101C2B);
  static const card2 = Color(0xFF132437);
  static const blue = Color(0xFF2563EB);
  static const cyan = Color(0xFF22D3EE);

  @override
  void initState() {
    super.initState();
    cargarJefes();
  }

  String _normalizarRol(dynamic value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  String _rolTexto(String role) {
    switch (_normalizarRol(role)) {
      case 'director_zona':
        return 'Director de zona';
      case 'jefe_ventas':
        return 'Jefe de ventas';
      case 'jefe_equipo':
        return 'Jefe de equipo';
      case 'agente':
        return 'Agente comercial';
      default:
        return role;
    }
  }

  int _nivelRol(String role) {
    switch (_normalizarRol(role)) {
      case 'director_zona':
        return 3;
      case 'jefe_ventas':
        return 2;
      case 'jefe_equipo':
        return 1;
      default:
        return 0;
    }
  }

  Set<String> get _rolesJefePermitidos {
    switch (selectedRole) {
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

  List<Map<String, dynamic>> get _jefesFiltrados {
    final permitidos = _rolesJefePermitidos;

    final resultado = jefes
        .where(
          (jefe) => permitidos.contains(_normalizarRol(jefe['rol_usuario'])),
        )
        .toList();

    resultado.sort((a, b) {
      final nivel = _nivelRol(
        b['rol_usuario']?.toString() ?? '',
      ).compareTo(_nivelRol(a['rol_usuario']?.toString() ?? ''));

      if (nivel != 0) return nivel;

      final nombreA = '${a['nombre'] ?? ''} ${a['apellidos'] ?? ''}'
          .toLowerCase();
      final nombreB = '${b['nombre'] ?? ''} ${b['apellidos'] ?? ''}'
          .toLowerCase();
      return nombreA.compareTo(nombreB);
    });

    return resultado;
  }

  Future<void> cargarJefes() async {
    try {
      final data = await supabase
          .from('usuarios')
          .select('id, nombre, apellidos, rol_usuario')
          .inFilter('rol_usuario', [
            'jefe_equipo',
            'jefe_ventas',
            'director_zona',
          ])
          .eq('estado', 'activo');

      if (!mounted) return;

      setState(() {
        jefes = List<Map<String, dynamic>>.from(data);
        loadingJefes = false;
      });
    } catch (e) {
      debugPrint('ERROR CARGANDO JEFES: $e');

      if (!mounted) return;

      setState(() {
        jefes = [];
        loadingJefes = false;
      });
    }
  }

  void _cambiarRol(String? value) {
    if (value == null) return;

    setState(() {
      selectedRole = value;
      selectedParentId = null;
    });
  }

  Future<void> register() async {
    if (loading) return;

    if (!(formKey.currentState?.validate() ?? false)) return;

    if (selectedRole != 'director_zona' && selectedParentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes elegir un jefe'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final auth = AuthService();

      final error = await auth.registerUser(
        nombre: nombreController.text.trim(),
        apellidos: apellidosController.text.trim(),
        direccion: direccionController.text.trim(),
        numeroDireccion: numeroController.text.trim(),
        codigoPostal: codigoPostalController.text.trim(),
        provincia: provinciaController.text.trim(),
        localidad: localidadController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text,
        role: selectedRole,
        parentId: selectedParentId,
      );

      if (!mounted) return;

      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuario registrado correctamente'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String? _obligatorio(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo obligatorio';
    }
    return null;
  }

  String? _validarEmail(String? value) {
    final obligatorio = _obligatorio(value);
    if (obligatorio != null) return obligatorio;

    final email = value!.trim();
    if (!email.contains('@') || !email.contains('.')) {
      return 'Introduce un email válido';
    }
    return null;
  }

  String? _validarPassword(String? value) {
    final obligatorio = _obligatorio(value);
    if (obligatorio != null) return obligatorio;

    if (value!.length < 8) {
      return 'Utiliza al menos 8 caracteres';
    }
    return null;
  }

  String? _validarRepeticion(String? value) {
    final obligatorio = _obligatorio(value);
    if (obligatorio != null) return obligatorio;

    if (value != passwordController.text) {
      return 'Las contraseñas no coinciden';
    }
    return null;
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
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: Colors.white.withOpacity(0.10),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(context),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 19,
              ),
            ),
          ),
        ),
        title: const Text(
          'Nuevo usuario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      body: Stack(
        children: [
          Positioned(top: -100, right: -80, child: _glow(cyan, 240)),
          Positioned(bottom: 80, left: -100, child: _glow(blue, 260)),
          SafeArea(
            top: false,
            child: Form(
              key: formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _hero(),
                  const SizedBox(height: 18),
                  _section(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Perfil profesional',
                    subtitle: 'Define el cargo y su responsable directo.',
                    children: [
                      _roleDropdown(),
                      const SizedBox(height: 14),
                      _bossSelector(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _section(
                    icon: Icons.person_rounded,
                    title: 'Datos personales',
                    subtitle: 'Información básica del nuevo usuario.',
                    children: [
                      _field(
                        controller: nombreController,
                        label: 'Nombre',
                        icon: Icons.person_outline_rounded,
                      ),
                      _field(
                        controller: apellidosController,
                        label: 'Apellidos',
                        icon: Icons.badge_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _section(
                    icon: Icons.location_on_rounded,
                    title: 'Dirección',
                    subtitle: 'Datos de residencia y localización.',
                    children: [
                      _field(
                        controller: direccionController,
                        label: 'Dirección',
                        icon: Icons.home_outlined,
                      ),
                      _field(
                        controller: numeroController,
                        label: 'Número / Piso',
                        icon: Icons.pin_drop_outlined,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              controller: codigoPostalController,
                              label: 'Código postal',
                              icon: Icons.local_post_office_outlined,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              controller: provinciaController,
                              label: 'Provincia',
                              icon: Icons.map_outlined,
                            ),
                          ),
                        ],
                      ),
                      _field(
                        controller: localidadController,
                        label: 'Localidad',
                        icon: Icons.location_city_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _section(
                    icon: Icons.lock_rounded,
                    title: 'Acceso a la cuenta',
                    subtitle: 'Credenciales con las que iniciará sesión.',
                    children: [
                      _field(
                        controller: emailController,
                        label: 'Email',
                        icon: Icons.alternate_email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validarEmail,
                      ),
                      _field(
                        controller: passwordController,
                        label: 'Contraseña',
                        icon: Icons.lock_outline_rounded,
                        obscureText: !showPassword,
                        validator: _validarPassword,
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => showPassword = !showPassword),
                          icon: Icon(
                            showPassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      _field(
                        controller: repeatPasswordController,
                        label: 'Repetir contraseña',
                        icon: Icons.verified_user_outlined,
                        obscureText: !showRepeatPassword,
                        validator: _validarRepeticion,
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => showRepeatPassword = !showRepeatPassword,
                          ),
                          icon: Icon(
                            showRepeatPassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 58,
                    child: ElevatedButton.icon(
                      onPressed: loading ? null : register,
                      icon: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(
                        loading ? 'Creando usuario...' : 'Crear usuario',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white.withOpacity(0.10),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF102A43), Color(0xFF0B1624)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [cyan, blue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Alta de usuario',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Crea su cuenta y sitúalo correctamente '
                  'en la estructura comercial.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: cyan, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.48),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _roleDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedRole,
      dropdownColor: card2,
      iconEnabledColor: cyan,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      decoration: _decoration(
        label: 'Cargo',
        icon: Icons.workspace_premium_outlined,
      ),
      items: const [
        DropdownMenuItem(
          value: 'director_zona',
          child: Text('Director de zona'),
        ),
        DropdownMenuItem(value: 'jefe_ventas', child: Text('Jefe de ventas')),
        DropdownMenuItem(value: 'jefe_equipo', child: Text('Jefe de equipo')),
        DropdownMenuItem(value: 'agente', child: Text('Agente comercial')),
      ],
      onChanged: loading ? null : _cambiarRol,
    );
  }

  Widget _bossSelector() {
    if (selectedRole == 'director_zona') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: cyan.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cyan.withOpacity(0.18)),
        ),
        child: const Row(
          children: [
            Icon(Icons.account_tree_rounded, color: cyan),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'El director de zona no necesita un jefe asignado.',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (loadingJefes) {
      return const SizedBox(
        height: 58,
        child: Center(child: CircularProgressIndicator(color: cyan)),
      );
    }

    final disponibles = _jefesFiltrados;

    if (disponibles.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.25)),
        ),
        child: const Text(
          'No hay responsables compatibles disponibles.',
          style: TextStyle(
            color: Color(0xFFFCA5A5),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: selectedParentId,
      isExpanded: true,
      dropdownColor: card2,
      iconEnabledColor: cyan,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      decoration: _decoration(
        label: 'Elige tu jefe',
        icon: Icons.account_tree_outlined,
      ),
      validator: (value) {
        if (selectedRole != 'director_zona' && value == null) {
          return 'Debes elegir un jefe';
        }
        return null;
      },
      items: disponibles.map((jefe) {
        final id = jefe['id'].toString();
        final nombre = '${jefe['nombre'] ?? ''} ${jefe['apellidos'] ?? ''}'
            .trim();
        final rol = _rolTexto(jefe['rol_usuario']?.toString() ?? '');

        return DropdownMenuItem<String>(
          value: id,
          child: Text(
            '${nombre.isEmpty ? 'Usuario sin nombre' : nombre} · $rol',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: loading
          ? null
          : (value) => setState(() => selectedParentId = value),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator ?? _obligatorio,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        decoration: _decoration(
          label: label,
          icon: icon,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      prefixIcon: Icon(icon, color: cyan, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: cyan, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      errorStyle: const TextStyle(color: Color(0xFFFCA5A5)),
    );
  }

  Widget _glow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.08),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.14),
              blurRadius: 80,
              spreadRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}
