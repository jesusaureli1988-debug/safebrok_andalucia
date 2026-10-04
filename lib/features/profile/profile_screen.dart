import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safebrok_andalucia/core/auth/login_screen.dart';
import 'package:safebrok_andalucia/features/app_info/app_info_screen.dart';
import 'package:safebrok_andalucia/features/settings/security/security_screen.dart';
import 'package:safebrok_andalucia/features/support/support_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final formKey = GlobalKey<FormState>();

  bool loading = true;
  bool saving = false;
  bool editMode = false;
  String? error;
  String appVersion = '';
  Map<String, dynamic>? usuario;

  final nombreCtrl = TextEditingController();
  final apellidosCtrl = TextEditingController();
  final telefonoCtrl = TextEditingController();
  final direccionCtrl = TextEditingController();
  final numeroCtrl = TextEditingController();
  final cpCtrl = TextEditingController();
  final provinciaCtrl = TextEditingController();
  final localidadCtrl = TextEditingController();

  List<TextEditingController> get controllers => [
    nombreCtrl,
    apellidosCtrl,
    telefonoCtrl,
    direccionCtrl,
    numeroCtrl,
    cpCtrl,
    provinciaCtrl,
    localidadCtrl,
  ];

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> loadProfile({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final authUser = supabase.auth.currentUser;
      if (authUser == null) throw Exception('No hay una sesión activa.');

      final results = await Future.wait<dynamic>([
        supabase.from('usuarios').select().eq('auth_id', authUser.id).single(),
        PackageInfo.fromPlatform(),
      ]);

      final data = Map<String, dynamic>.from(results[0] as Map);
      final info = results[1] as PackageInfo;

      usuario = data;
      appVersion = info.version + ' (' + info.buildNumber + ')';
      fillControllers(data);

      if (!mounted) return;
      setState(() {
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void fillControllers(Map<String, dynamic> data) {
    nombreCtrl.text = text(data['nombre']);
    apellidosCtrl.text = text(data['apellidos']);
    telefonoCtrl.text = text(data['telefono']);
    direccionCtrl.text = text(data['direccion']);
    numeroCtrl.text = text(data['numero_direccion']);
    cpCtrl.text = text(data['codigo_postal']);
    provinciaCtrl.text = text(data['provincia']);
    localidadCtrl.text = text(data['localidad']);
  }

  String text(dynamic value) => value?.toString().trim() ?? '';

  String get email {
    final databaseEmail = text(usuario?['email']);
    return databaseEmail.isNotEmpty
        ? databaseEmail
        : (supabase.auth.currentUser?.email ?? '');
  }

  String get fullName {
    final value = (nombreCtrl.text.trim() + ' ' + apellidosCtrl.text.trim())
        .trim();
    return value.isEmpty ? 'Usuario SafeBrok' : value;
  }

  String get roleLabel {
    final raw = text(usuario?['rol_usuario']).toLowerCase();
    const labels = {
      'administracion': 'Administración',
      'director_nacional': 'Director nacional',
      'director_regional': 'Director regional',
      'director_zona': 'Director de zona',
      'jefe_ventas': 'Jefe de ventas',
      'jefe_equipo': 'Jefe de equipo',
      'agente': 'Agente',
    };
    return labels[raw] ??
        (raw.isEmpty ? 'Sin figura asignada' : raw.replaceAll('_', ' '));
  }

  String get statusLabel {
    final value = text(usuario?['estado']);
    return value.isEmpty ? 'Activo' : value;
  }

  String get initials {
    final parts = fullName.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return 'SB';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  double get completion {
    final values = [
      nombreCtrl.text,
      apellidosCtrl.text,
      telefonoCtrl.text,
      direccionCtrl.text,
      cpCtrl.text,
      provinciaCtrl.text,
      localidadCtrl.text,
      email,
    ];
    return values.where((value) => value.trim().isNotEmpty).length /
        values.length;
  }

  Future<void> saveProfile() async {
    if (saving || !(formKey.currentState?.validate() ?? false)) return;
    final authUser = supabase.auth.currentUser;
    if (authUser == null) return;

    setState(() => saving = true);
    try {
      await supabase
          .from('usuarios')
          .update({
            'nombre': nombreCtrl.text.trim(),
            'apellidos': apellidosCtrl.text.trim(),
            'telefono': telefonoCtrl.text.trim(),
            'direccion': direccionCtrl.text.trim(),
            'numero_direccion': numeroCtrl.text.trim(),
            'codigo_postal': cpCtrl.text.trim(),
            'provincia': provinciaCtrl.text.trim(),
            'localidad': localidadCtrl.text.trim(),
          })
          .eq('auth_id', authUser.id);

      await loadProfile(showLoader: false);
      if (!mounted) return;
      setState(() {
        editMode = false;
        saving = false;
      });
      message('Perfil actualizado correctamente.');
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      message(
        'No se han podido guardar los cambios: ' +
            e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    }
  }

  void cancelEditing() {
    if (usuario != null) fillControllers(usuario!);
    setState(() => editMode = false);
  }

  void message(String value, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: isError
            ? const Color(0xFFB91C1C)
            : const Color(0xFF198754),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de SafeBrok en este dispositivo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SafeArea(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF2454D3)),
              )
            : error != null
            ? errorState()
            : RefreshIndicator(
                color: const Color(0xFF2454D3),
                onRefresh: () => loadProfile(showLoader: false),
                child: Form(
                  key: formKey,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 34),
                    children: [
                      topBar(),
                      const SizedBox(height: 18),
                      identityHero(),
                      const SizedBox(height: 18),
                      completionCard(),
                      const SizedBox(height: 22),
                      sectionTitle(
                        'Datos personales',
                        'Información utilizada en tu cuenta y documentación.',
                      ),
                      const SizedBox(height: 12),
                      personalDataCard(),
                      const SizedBox(height: 22),
                      sectionTitle(
                        'Cuenta y aplicación',
                        'Accesos directos a las funciones de tu perfil.',
                      ),
                      const SizedBox(height: 12),
                      accountActions(),
                      const SizedBox(height: 22),
                      sessionCard(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget topBar() {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.maybePop(context),
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(Icons.arrow_back_rounded, color: Color(0xFF071A3A)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mi perfil',
                style: TextStyle(
                  color: Color(0xFF071A3A),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Tu identidad y configuración personal',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
        ),
        if (editMode)
          TextButton(
            onPressed: saving ? null : cancelEditing,
            child: const Text('Cancelar'),
          )
        else
          IconButton.filledTonal(
            tooltip: 'Actualizar perfil',
            onPressed: () => loadProfile(showLoader: false),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF2454D3),
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );
  }

  Widget identityHero() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF13244D), Color(0xFF2454D3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x242454D3),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x4DFFFFFF), width: 4),
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: Color(0xFF2454D3),
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD7E2FF),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    heroBadge(Icons.badge_outlined, roleLabel),
                    heroBadge(
                      Icons.verified_user_outlined,
                      statusLabel,
                      color: const Color(0xFFBDF6D2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget heroBadge(IconData icon, String text, {Color? color}) {
    final foreground = color ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget completionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: whiteCardDecoration(),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: completion,
                  strokeWidth: 6,
                  backgroundColor: const Color(0xFFE5EAF2),
                  color: const Color(0xFF2454D3),
                ),
                Text(
                  (completion * 100).round().toString() + '%',
                  style: const TextStyle(
                    color: Color(0xFF071A3A),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perfil personal',
                  style: TextStyle(
                    color: Color(0xFF071A3A),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Mantén tus datos completos y actualizados.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton.filled(
            tooltip: editMode ? 'Editando' : 'Editar perfil',
            onPressed: editMode ? null : () => setState(() => editMode = true),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEAF0FF),
              foregroundColor: const Color(0xFF2454D3),
              disabledBackgroundColor: const Color(0xFFEAF0FF),
              disabledForegroundColor: const Color(0xFF2454D3),
            ),
            icon: Icon(editMode ? Icons.edit_rounded : Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  Widget personalDataCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: whiteCardDecoration(),
      child: Column(
        children: [
          profileField(
            controller: nombreCtrl,
            label: 'Nombre',
            icon: Icons.person_outline_rounded,
            required: true,
          ),
          divider(),
          profileField(
            controller: apellidosCtrl,
            label: 'Apellidos',
            icon: Icons.badge_outlined,
          ),
          divider(),
          readOnlyField(
            label: 'Correo electrónico',
            value: email,
            icon: Icons.alternate_email_rounded,
            helper: 'El correo de acceso solo puede cambiarlo administración.',
          ),
          divider(),
          profileField(
            controller: telefonoCtrl,
            label: 'Teléfono',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          divider(),
          profileField(
            controller: direccionCtrl,
            label: 'Dirección',
            icon: Icons.location_on_outlined,
          ),
          divider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: profileField(
                  controller: numeroCtrl,
                  label: 'Número',
                  icon: Icons.home_outlined,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: profileField(
                  controller: cpCtrl,
                  label: 'Código postal',
                  icon: Icons.markunread_mailbox_outlined,
                  keyboardType: TextInputType.number,
                  compact: true,
                ),
              ),
            ],
          ),
          divider(),
          profileField(
            controller: localidadCtrl,
            label: 'Localidad',
            icon: Icons.location_city_outlined,
          ),
          divider(),
          profileField(
            controller: provinciaCtrl,
            label: 'Provincia',
            icon: Icons.map_outlined,
          ),
          if (editMode) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: saving ? null : saveProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2454D3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: saving
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(saving ? 'Guardando...' : 'Guardar cambios'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget profileField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool required = false,
    bool compact = false,
  }) {
    if (!editMode) {
      return readOnlyField(
        label: label,
        value: text(controller.text).isEmpty
            ? 'Sin completar'
            : controller.text,
        icon: icon,
        compact: compact,
      );
    }

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization:
          keyboardType == TextInputType.phone ||
              keyboardType == TextInputType.number
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      validator: required
          ? (value) => text(value).isEmpty ? 'Este campo es obligatorio' : null
          : null,
      style: const TextStyle(
        color: Color(0xFF071A3A),
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF2454D3)),
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 17,
        ),
        labelStyle: const TextStyle(color: Color(0xFF64748B)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCE5F2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDCE5F2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2454D3), width: 1.7),
        ),
      ),
    );
  }

  Widget readOnlyField({
    required String label,
    required String value,
    required IconData icon,
    String? helper,
    bool compact = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 36 : 42,
            height: compact ? 36 : 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF2454D3),
              size: compact ? 18 : 21,
            ),
          ),
          SizedBox(width: compact ? 9 : 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: value == 'Sin completar'
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF071A3A),
                    fontSize: compact ? 13 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    helper,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget accountActions() {
    return Container(
      decoration: whiteCardDecoration(),
      child: Column(
        children: [
          actionTile(
            icon: Icons.shield_outlined,
            title: 'Seguridad y acceso',
            subtitle: 'Contraseña, sesiones y protección de la cuenta',
            onTap: () => open(const SecurityScreen()),
          ),
          const Divider(height: 1, indent: 72, color: Color(0xFFE7ECF3)),
          actionTile(
            icon: Icons.support_agent_rounded,
            title: 'Ayuda y soporte',
            subtitle: 'Resuelve dudas o contacta con SafeBrok',
            onTap: () => open(const SupportScreen()),
          ),
          const Divider(height: 1, indent: 72, color: Color(0xFFE7ECF3)),
          actionTile(
            icon: Icons.info_outline_rounded,
            title: 'Acerca de SafeBrok',
            subtitle: appVersion.isEmpty
                ? 'Información de la aplicación'
                : 'Versión ' + appVersion + ' · Información legal',
            onTap: () => open(const AppInfoScreen()),
          ),
        ],
      ),
    );
  }

  Widget actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF0FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF2454D3)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF071A3A),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget sessionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: whiteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.devices_rounded, color: Color(0xFF2454D3)),
              SizedBox(width: 10),
              Text(
                'Sesión actual',
                style: TextStyle(
                  color: Color(0xFF071A3A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Tu cuenta está abierta en este dispositivo. Desde Seguridad puedes cerrar el resto de sesiones.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFF1B8B8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text(
                'Cerrar sesión',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF071A3A),
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1, color: Color(0xFFE7ECF3)),
    );
  }

  BoxDecoration whiteCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFDCE5F2)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F0F2B5B),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  Widget errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEAEA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_off_outlined,
                size: 34,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No hemos podido cargar tu perfil',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF071A3A),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error ?? 'Vuelve a intentarlo en unos segundos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: loadProfile,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
