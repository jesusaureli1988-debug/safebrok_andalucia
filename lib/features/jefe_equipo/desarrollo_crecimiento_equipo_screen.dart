import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/features/jefe_equipo/captacion/candidatos_captacion_screen.dart';
import 'package:safebrok_andalucia/features/jefe_equipo/nuevo_candidato_screen.dart';
import 'package:safebrok_andalucia/features/jefe_equipo/formacion_equipo_screen.dart';
import 'package:safebrok_andalucia/features/jefe_equipo/integracion_equipo_screen.dart';

class DesarrolloCrecimientoEquipoScreen extends StatelessWidget {
  const DesarrolloCrecimientoEquipoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Stack(
        children: [
          const _JobTodayBackground(),

          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _topBar(context),
                        const SizedBox(height: 26),
                        _heroSection(context),
                        const SizedBox(height: 26),
                        const Text(
                          "Centro de crecimiento",
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Capta, forma e integra nuevos perfiles en tu estructura.",
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.48),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        _moduleCard(
                          context: context,
                          title: "Captación de talento",
                          subtitle:
                              "Gestiona candidatos, entrevistas, estados y seguimiento.",
                          tag: "Selección",
                          icon: Icons.person_search_rounded,
                          gradient: const [
                            Color(0xFF00C2FF),
                            Color(0xFF0077FF),
                          ],
                          imageIcon: Icons.work_rounded,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CandidatosCaptacionScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _moduleCard(
                          context: context,
                          title: "Formación del equipo",
                          subtitle:
                              "Controla aprendizaje, progreso y evolución comercial.",
                          tag: "Academia",
                          icon: Icons.school_rounded,
                          gradient: const [
                            Color(0xFF8B5CF6),
                            Color(0xFFEC4899),
                          ],
                          imageIcon: Icons.auto_stories_rounded,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FormacionEquipoScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        _moduleCard(
                          context: context,
                          title: "Integración y actividad",
                          subtitle:
                              "Acompañamiento, reuniones, adaptación y productividad.",
                          tag: "Onboarding",
                          icon: Icons.groups_2_rounded,
                          gradient: const [
                            Color(0xFF22C55E),
                            Color(0xFF14B8A6),
                          ],
                          imageIcon: Icons.handshake_rounded,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const IntegracionEquipoScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 26),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF111827),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            "Desarrollo",
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.bolt_rounded,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _heroSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF111827),
            Color(0xFF1D4ED8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withOpacity(0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -10,
            child: Icon(
              Icons.diversity_3_rounded,
              size: 130,
              color: Colors.white.withOpacity(0.09),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  "SAFEBROK TALENT",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Construye tu equipo como una empresa de selección.",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                "Todo el proceso de crecimiento en un solo lugar: captación, formación e integración.",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _heroMini("3", "módulos"),
                  const SizedBox(width: 10),
                  _heroMini("360º", "seguimiento"),
                  const SizedBox(width: 10),
                  _heroMini("ERP", "talento"),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroMini(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moduleCard({
  required BuildContext context,
  required String title,
  required String subtitle,
  required String tag,
  required IconData icon,
  required List<Color> gradient,
  required IconData imageIcon,
  required VoidCallback onTap,
}) {
  return _HoverModuleCard(
    color: gradient.first,
    onTap: onTap,
    child: Container(
      height: 170,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withOpacity(0.18),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            bottom: -26,
            child: Icon(
              imageIcon,
              size: 145,
              color: gradient.first.withOpacity(0.08),
            ),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: gradient.first.withOpacity(0.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  color: gradient.last,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  height: 62,
                  width: 62,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.first.withOpacity(0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 17),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.52),
                            fontSize: 13,
                            height: 1.28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              "Entrar",
                              style: TextStyle(
                                color: gradient.last,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: gradient.last,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}

class _HoverModuleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color color;

  const _HoverModuleCard({
    required this.child,
    required this.onTap,
    required this.color,
  });

  @override
  State<_HoverModuleCard> createState() => _HoverModuleCardState();
}

class _HoverModuleCardState extends State<_HoverModuleCard> {
  bool hovering = false;
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    final scale = pressing
        ? 0.985
        : hovering
            ? 1.018
            : 1.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) {
        setState(() {
          hovering = false;
          pressing = false;
        });
      },
      child: Listener(
        onPointerDown: (_) => setState(() => pressing = true),
        onPointerUp: (_) => setState(() => pressing = false),
        onPointerCancel: (_) => setState(() => pressing = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(34),
              boxShadow: [
                BoxShadow(
                  color: hovering
                      ? widget.color.withOpacity(0.26)
                      : Colors.black.withOpacity(0.04),
                  blurRadius: hovering ? 30 : 14,
                  offset: Offset(0, hovering ? 16 : 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(34),
              child: InkWell(
                borderRadius: BorderRadius.circular(34),
                splashColor: widget.color.withOpacity(0.14),
                highlightColor: widget.color.withOpacity(0.06),
                hoverColor: widget.color.withOpacity(0.035),
                mouseCursor: SystemMouseCursors.click,
                onTap: widget.onTap,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JobTodayBackground extends StatelessWidget {
  const _JobTodayBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -110,
          right: -80,
          child: _bubble(const Color(0xFF00C2FF), 240),
        ),
        Positioned(
          top: 180,
          left: -130,
          child: _bubble(const Color(0xFF8B5CF6), 260),
        ),
        Positioned(
          bottom: -150,
          right: -90,
          child: _bubble(const Color(0xFF22C55E), 260),
        ),
      ],
    );
  }

  Widget _bubble(Color color, double size) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.14),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: const SizedBox(),
      ),
    );
  }
}