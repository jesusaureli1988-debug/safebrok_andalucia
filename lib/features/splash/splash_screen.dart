import 'dart:async';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:safebrok_andalucia/core/auth/role_router.dart';

final AudioPlayer player = AudioPlayer();

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _introController;
  late AnimationController _pulseController;
  late AnimationController _shineController;

  late Animation<double> _fade;
  late Animation<double> _scale;
  late Animation<double> _pulse;
  late Animation<double> _shine;

  final List<String> letters = "SAFEBROK".split("");
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _fade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: Curves.easeOut,
      ),
    );

    _scale = Tween<double>(
      begin: 0.72,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: Curves.easeOutBack,
      ),
    );

    _pulse = Tween<double>(
      begin: 0.96,
      end: 1.04,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _shine = Tween<double>(
      begin: -1,
      end: 2,
    ).animate(
      CurvedAnimation(
        parent: _shineController,
        curve: Curves.easeInOut,
      ),
    );

    _introController.forward();
    startNetflixIntro();

    player.play(
      AssetSource('audio/startup.mp3'),
    );

    initFlow();
  }

  Future<void> initFlow() async {
    await Future.delayed(const Duration(seconds: 9));

    if (!mounted) return;

    try {
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        print("SESION ENCONTRADA");
        print("SESSION USER: ${session.user.id}");

        final profile = await Supabase.instance.client
            .from('usuarios')
            .select()
            .eq('auth_id', session.user.id)
            .maybeSingle();

        print("PROFILE: $profile");

        if (profile != null) {
          final role = profile['rol_usuario'];

          print("ROLE: $role");

          if (!mounted) return;

          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 750),
              pageBuilder: (_, animation, __) {
                return FadeTransition(
                  opacity: animation,
                  child: RoleRouter.getHomeByRole(role),
                );
              },
            ),
          );

          return;
        }

        print("PROFILE NULL");
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 750),
          pageBuilder: (_, animation, __) {
            return FadeTransition(
              opacity: animation,
              child: const LoginScreen(),
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 750),
          pageBuilder: (_, animation, __) {
            return FadeTransition(
              opacity: animation,
              child: const LoginScreen(),
            );
          },
        ),
      );
    }
  }

  void startNetflixIntro() async {
    currentIndex = 0;

    for (int i = 0; i < letters.length; i++) {
      await Future.delayed(const Duration(milliseconds: 520));

      if (!mounted) return;

      setState(() {
        currentIndex = i + 1;
      });

      await Future.delayed(const Duration(milliseconds: 180));
    }
  }

  @override
  void dispose() {
    player.dispose();
    _introController.dispose();
    _pulseController.dispose();
    _shineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final completed = currentIndex == letters.length;

    return Scaffold(
      body: Stack(
        children: [
          // FONDO OSCURO CINEMÁTICO
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.25,
                colors: [
                  Color(0xFF144A78),
                  Color(0xFF071521),
                  Color(0xFF02060B),
                ],
              ),
            ),
          ),

          // FLASH FINAL
          AnimatedOpacity(
            opacity: completed ? 0.16 : 0,
            duration: const Duration(milliseconds: 350),
            child: Container(
              color: Colors.cyanAccent,
            ),
          ),

          // GLOW SUPERIOR
          Positioned(
            top: -160,
            left: -80,
            child: _glowCircle(
              size: 340,
              color: Colors.blue,
              opacity: 0.25,
            ),
          ),

          // GLOW INFERIOR
          Positioned(
            bottom: -170,
            right: -90,
            child: _glowCircle(
              size: 360,
              color: Colors.cyan,
              opacity: 0.18,
            ),
          ),

          // LUZ CENTRAL
          Center(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulse.value,
                  child: Container(
                    width: 270,
                    height: 270,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.20),
                          blurRadius: 120,
                          spreadRadius: 30,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // BLUR
          BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 34,
              sigmaY: 34,
            ),
            child: Container(
              color: Colors.black.withOpacity(0.18),
            ),
          ),

          // CONTENIDO
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulse.value,
                            child: child,
                          );
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 174,
                              height: 174,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(42),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blueAccent.withOpacity(0.45),
                                    blurRadius: 70,
                                    spreadRadius: 10,
                                  ),
                                  BoxShadow(
                                    color: Colors.cyanAccent.withOpacity(0.22),
                                    blurRadius: 110,
                                    spreadRadius: 18,
                                  ),
                                ],
                              ),
                            ),

                            Container(
                              height: 154,
                              width: 154,
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(38),
                                color: Colors.white.withOpacity(0.08),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.16),
                                  width: 1.2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),

                            // BRILLO PASANDO POR EL LOGO
                            AnimatedBuilder(
                              animation: _shine,
                              builder: (context, child) {
                                return Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(38),
                                    child: Transform.translate(
                                      offset: Offset(_shine.value * 180, 0),
                                      child: Container(
                                        width: 50,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.transparent,
                                              Colors.white.withOpacity(0.22),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 38),

                      // TEXTO ESTILO NETFLIX
                      SizedBox(
                        height: 82,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(letters.length, (i) {
                            final visible = i < currentIndex;

                            return AnimatedOpacity(
                              duration: const Duration(milliseconds: 420),
                              opacity: visible ? 1 : 0,
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 480),
                                curve: Curves.easeOutBack,
                                scale: visible ? 1 : 0.15,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 480),
                                  margin: EdgeInsets.symmetric(
                                    horizontal: completed ? 3.5 : 1.5,
                                  ),
                                  child: Text(
                                    letters[i],
                                    style: TextStyle(
                                      fontSize: completed ? 58 : 52,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 5,
                                      shadows: [
                                        Shadow(
                                          color: Colors.blueAccent.withOpacity(0.95),
                                          blurRadius: 38,
                                        ),
                                        Shadow(
                                          color: Colors.cyanAccent.withOpacity(0.65),
                                          blurRadius: 72,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      const SizedBox(height: 8),

                      AnimatedOpacity(
                        opacity: completed ? 1 : 0,
                        duration: const Duration(milliseconds: 800),
                        child: Text(
                          'Correduría profesional de seguros',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 15,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const SizedBox(height: 54),

                      SizedBox(
                        width: 220,
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(
                                  begin: 0,
                                  end: completed ? 1 : currentIndex / letters.length,
                                ),
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeInOut,
                                builder: (context, value, child) {
                                  return LinearProgressIndicator(
                                    value: value,
                                    minHeight: 5,
                                    backgroundColor: Colors.white.withOpacity(0.12),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.cyanAccent.withOpacity(0.9),
                                    ),
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 14),

                            Text(
                              completed
                                  ? "Preparando tu entorno..."
                                  : "Iniciando SafeBrok...",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.58),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // FIRMA INFERIOR
          Positioned(
            bottom: 26,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: completed ? 1 : 0,
              duration: const Duration(milliseconds: 800),
              child: Text(
                "SafeBrok Andalucía · ERP Comercial",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.38),
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle({
    required double size,
    required Color color,
    required double opacity,
  }) {
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