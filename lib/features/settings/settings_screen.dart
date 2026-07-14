import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safebrok_andalucia/features/profile/profile_screen.dart';
import 'package:safebrok_andalucia/features/incidencias/incidencias_screen.dart';
import 'package:safebrok_andalucia/features/settings/security/security_screen.dart';
import 'package:safebrok_andalucia/features/support/support_screen.dart';
import 'package:safebrok_andalucia/features/app_info/app_info_screen.dart';
import 'package:safebrok_andalucia/features/business/crear_visita_screen.dart';
import 'package:safebrok_andalucia/features/business/mis_visitas_screen.dart';
import 'package:safebrok_andalucia/features/admin/admin_panel_screen.dart';

class SettingsScreen extends StatelessWidget {
  final String role;

  const SettingsScreen({
    super.key,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    final email = user?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    final normalizedRole = role.trim().toLowerCase();

    final bool showAdmin =
        normalizedRole == 'director_zona' ||
        normalizedRole == 'jefe_ventas' ||
        normalizedRole == 'director_nacional' ||
        normalizedRole == 'administracion';

    return Scaffold(
      backgroundColor: const Color(0xFF050B12),
      extendBodyBehindAppBar: true,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Ajustes',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),

      body: Stack(
        children: [
          const _SettingsBackground(),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
              children: [
                _profileHeader(
                  email: email,
                  initial: initial,
                  role: role,
                ),

                const SizedBox(height: 20),

                _section(
                  title: 'Cuenta',
                  children: [
                    _item(
                      icon: Icons.person_rounded,
                      title: 'Mi perfil',
                      subtitle: 'Datos personales y configuración',
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        );
                      },
                    ),
                    _item(
                      icon: Icons.security_rounded,
                      title: 'Seguridad',
                      subtitle: 'Acceso, contraseña y protección',
                      color: Colors.greenAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SecurityScreen(),
                          ),
                        );
                      },
                    ),
                    _item(
                      icon: Icons.notifications_rounded,
                      title: 'Notificaciones',
                      subtitle: 'Avisos y actividad pendiente',
                      color: Colors.orangeAccent,
                      onTap: () {
                        _soon(context);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                _section(
                  title: 'Actividad comercial',
                  children: [
                    _item(
                      icon: Icons.calendar_month_rounded,
                      title: 'Crear visita',
                      subtitle: 'Registra una nueva visita comercial',
                      color: Colors.purpleAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CrearVisitaScreen(),
                          ),
                        );
                      },
                    ),
                    _item(
                      icon: Icons.list_alt_rounded,
                      title: 'Mis visitas',
                      subtitle: 'Consulta y revisa tus visitas',
                      color: Colors.lightBlueAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MisVisitasScreen(),
                          ),
                        );
                      },
                    ),
                    _item(
                      icon: Icons.report_problem_rounded,
                      title: 'Incidencias',
                      subtitle: 'Gestión de problemas y avisos',
                      color: Colors.redAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const IncidenciasScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                _section(
                  title: 'Soporte',
                  children: [
                    _item(
                      icon: Icons.help_rounded,
                      title: 'Ayuda y soporte',
                      subtitle: 'Contacta o revisa ayuda disponible',
                      color: Colors.amberAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SupportScreen(),
                          ),
                        );
                      },
                    ),
                    _item(
                      icon: Icons.info_outline_rounded,
                      title: 'Información de la app',
                      subtitle: 'Versión, sistema y detalles',
                      color: Colors.cyanAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AppInfoScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                if (showAdmin) ...[
                  const SizedBox(height: 18),
                  _section(
                    title: 'Administración',
                    children: [
                      _item(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Panel de administración',
                        subtitle: 'Control avanzado de la organización',
                        color: Colors.deepPurpleAccent,
                        premium: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminPanelScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileHeader({
    required String email,
    required String initial,
    required String role,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.14),
                Colors.white.withOpacity(0.045),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.12),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      Colors.cyanAccent,
                      Color(0xFF1D7CFF),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.25),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usuario conectado',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      email.isEmpty ? 'Sin email' : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        role,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.48),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.9,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool premium = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          splashColor: color.withOpacity(0.10),
          highlightColor: color.withOpacity(0.06),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                colors: premium
                    ? [
                        color.withOpacity(0.22),
                        Colors.white.withOpacity(0.05),
                      ]
                    : [
                        Colors.white.withOpacity(0.07),
                        Colors.white.withOpacity(0.025),
                      ],
              ),
              border: Border.all(
                color: premium
                    ? color.withOpacity(0.32)
                    : Colors.white.withOpacity(0.07),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: color.withOpacity(0.22),
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 25,
                  ),
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (premium) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Colors.amberAccent,
                              size: 17,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.48),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withOpacity(0.35),
                  size: 15,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF102331),
        behavior: SnackBarBehavior.floating,
        content: const Text(
          'Próximamente activaremos esta sección',
          style: TextStyle(
            color: Colors.cyanAccent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SettingsBackground extends StatelessWidget {
  const _SettingsBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF050B12),
                Color(0xFF071A2E),
                Color(0xFF050B12),
              ],
            ),
          ),
        ),

        Positioned(
          top: -150,
          right: -110,
          child: _glow(Colors.cyanAccent, 330, 0.15),
        ),

        Positioned(
          bottom: -170,
          left: -120,
          child: _glow(Colors.blueAccent, 370, 0.14),
        ),

        Positioned(
          top: 310,
          left: -120,
          child: _glow(Colors.purpleAccent, 250, 0.08),
        ),

        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            color: Colors.black.withOpacity(0.05),
          ),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
      ),
    );
  }
}