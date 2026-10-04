import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:safebrok_andalucia/features/profile/profile_screen.dart';
import 'package:safebrok_andalucia/features/invoices/my_invoices_screen.dart';
import 'package:safebrok_andalucia/features/incidencias/incidencias_screen.dart';
import 'package:safebrok_andalucia/features/settings/security/security_screen.dart';
import 'package:safebrok_andalucia/features/support/support_screen.dart';
import 'package:safebrok_andalucia/features/app_info/app_info_screen.dart';
import 'package:safebrok_andalucia/features/business/crear_visita_screen.dart';
import 'package:safebrok_andalucia/features/business/mis_visitas_screen.dart';
import 'package:safebrok_andalucia/features/admin/admin_panel_screen.dart';
import 'package:safebrok_andalucia/core/auth/app_role.dart';
import 'package:safebrok_andalucia/features/incorporaciones/incorporaciones_screen.dart';
import 'package:safebrok_andalucia/features/admin/cambios_rol_panel.dart';

class SettingsScreen extends StatelessWidget {
  final String role;

  const SettingsScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    final email = user?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    final normalizedRole = AppRole.normalize(role);
    final bool showAdmin = AppRole.isLeadership(normalizedRole);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      extendBodyBehindAppBar: true,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Ajustes',
          style: TextStyle(
            color: const Color(0xFF111827),
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
                _profileHeader(email: email, initial: initial, role: role),

                const SizedBox(height: 20),

                _section(
                  title: 'Cuenta',
                  children: [
                    _item(
                      icon: Icons.description_outlined,
                      title: 'Cambio de figura y contrato',
                      subtitle: 'Revisar, firmar y seguir el nuevo contrato',
                      color: Colors.orangeAccent,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CambiosRolPanel(
                              canManage:
                                  normalizedRole ==
                                      AppRole.administracion.value ||
                                  normalizedRole ==
                                      AppRole.directorNacional.value,
                              embedded: false,
                            ),
                          ),
                        );
                      },
                    ),
                    _item(
                      icon: Icons.person_rounded,
                      title: 'Mi perfil',
                      subtitle: 'Datos personales y configuración',
                      color: const Color(0xFF2563EB),
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
                      icon: Icons.receipt_long_rounded,
                      title: 'Facturas',
                      subtitle: 'Consulta y descarga tus facturas mensuales',
                      color: const Color(0xFF2454D3),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MyInvoicesScreen(),
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
                  ],
                ),

                const SizedBox(height: 18),

                _section(
                  title: 'Actividad comercial',
                  children: [
                    _item(
                      icon: Icons.badge_outlined,
                      title: 'Incorporaciones',
                      subtitle: normalizedRole == AppRole.administracion.value
                          ? 'Revisar expedientes, contratos y altas'
                          : 'Preparar y seguir altas de candidatos',
                      color: const Color(0xFF2563EB),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const IncorporacionesScreen(),
                          ),
                        );
                      },
                    ),
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
                      color: const Color(0xFF2563EB),
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
                      color: const Color(0xFF2563EB),
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF111827), Color(0xFF1D4ED8)],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [const Color(0xFF2563EB), Color(0xFF1D7CFF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.25),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
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
                        color: const Color(0xFFD8E2F2),
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
                        color: const Color(0xFF2563EB).withOpacity(0.13),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        role,
                        style: const TextStyle(
                          color: Colors.white,
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

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: const Color(0xFF64748B),
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
    const accent = Color(0xFF2563EB);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          splashColor: accent.withOpacity(0.08),
          highlightColor: accent.withOpacity(0.04),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Icon(icon, color: accent, size: 25),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Color(0xFF475569),
                  size: 15,
                ),
              ],
            ),
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
    return const Positioned.fill(child: ColoredBox(color: Color(0xFFF4F6FB)));
  }
}
