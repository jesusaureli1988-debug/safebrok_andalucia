import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:safebrok_andalucia/core/auth/login_screen.dart';
import 'package:safebrok_andalucia/core/auth/password_recovery_state.dart';
import 'package:safebrok_andalucia/core/auth/role_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _ambientController;
  bool _navigationCompleted = false;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 10000),
    );
    unawaited(_runLogoLoop());
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    initFlow();
  }

  Future<void> _runLogoLoop() async {
    while (mounted && !_navigationCompleted) {
      await _logoController.forward(from: 0);
      if (!mounted || _navigationCompleted) return;
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }

  Future<void> initFlow() async {
    await Future.delayed(const Duration(milliseconds: 12000));
    if (!mounted || _navigationCompleted) return;
    if (PasswordRecoveryState.active.value) return;

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (PasswordRecoveryState.active.value) return;

      if (session != null) {
        final profile = await Supabase.instance.client
            .from('usuarios')
            .select()
            .eq('auth_id', session.user.id)
            .maybeSingle();

        if (!mounted ||
            _navigationCompleted ||
            PasswordRecoveryState.active.value) {
          return;
        }

        if (profile != null) {
          _navigationCompleted = true;
          _goTo(RoleRouter.getHomeByRole(profile['rol_usuario']));
          return;
        }
      }

      if (!mounted ||
          _navigationCompleted ||
          PasswordRecoveryState.active.value) {
        return;
      }
      _navigationCompleted = true;
      _goTo(const LoginScreen());
    } catch (e, stackTrace) {
      debugPrint('ERROR SPLASH: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted ||
          _navigationCompleted ||
          PasswordRecoveryState.active.value) {
        return;
      }
      _navigationCompleted = true;
      _goTo(const LoginScreen());
    }
  }

  void _goTo(Widget page) {
    _logoController.stop(canceled: false);
    _ambientController.stop(canceled: false);
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: page,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (_, __) => CustomPaint(
                painter: _CinematicBackgroundPainter(_ambientController.value),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _logoController,
                    _ambientController,
                  ]),
                  builder: (context, _) {
                    final value = Curves.easeInOutCubic.transform(
                      _logoController.value,
                    );
                    final fill = ((_logoController.value - .04) / .90).clamp(
                      0.0,
                      1.0,
                    );
                    final pulse = .98 + (_ambientController.value * .025);
                    final orbitPhase = _ambientController.value * math.pi * 2;
                    final tiltX = math.cos(orbitPhase) * .035;
                    final tiltY = math.sin(orbitPhase) * .075;
                    final finale = Curves.easeOutBack.transform(
                      ((value - .72) / .28).clamp(0.0, 1.0),
                    );

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, .0018)
                            ..rotateX(tiltX)
                            ..rotateY(tiltY),
                          child: Transform.scale(
                            scale: pulse,
                            child: Container(
                              width: 224,
                              height: 224,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(54),
                                border: Border.all(
                                  color: const Color(0xFFDCE6F2),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1D4ED8).withOpacity(
                                      .13 + .07 * _ambientController.value,
                                    ),
                                    blurRadius: 54,
                                    spreadRadius: 3,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: 160,
                                    height: 166,
                                    child: RepaintBoundary(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Opacity(
                                            opacity: .24 + .12 * fill,
                                            child: ColorFiltered(
                                              colorFilter:
                                                  const ColorFilter.mode(
                                                    Color(0xFF168F98),
                                                    BlendMode.srcIn,
                                                  ),
                                              child: Image.asset(
                                                'assets/images/safebrok_mark.png',
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                          ClipPath(
                                            clipper: _TraceRevealClipper(fill),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                ...List.generate(5, (index) {
                                                  final depth = 5 - index;
                                                  return Transform.translate(
                                                    offset: Offset(
                                                      depth * 1.25,
                                                      depth * .95,
                                                    ),
                                                    child: Opacity(
                                                      opacity:
                                                          .16 + index * .025,
                                                      child: ColorFiltered(
                                                        colorFilter:
                                                            ColorFilter.mode(
                                                              Color.lerp(
                                                                const Color(
                                                                  0xFF071A3A,
                                                                ),
                                                                const Color(
                                                                  0xFF1D4ED8,
                                                                ),
                                                                index / 8,
                                                              )!,
                                                              BlendMode.srcIn,
                                                            ),
                                                        child: Image.asset(
                                                          'assets/images/safebrok_mark.png',
                                                          fit: BoxFit.contain,
                                                          filterQuality:
                                                              FilterQuality
                                                                  .medium,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                Image.asset(
                                                  'assets/images/safebrok_mark.png',
                                                  fit: BoxFit.contain,
                                                  filterQuality:
                                                      FilterQuality.high,
                                                ),
                                              ],
                                            ),
                                          ),
                                          CustomPaint(
                                            painter: _EnergyTracePainter(fill),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                        _AnimatedBrandLockup(progress: fill),
                        const SizedBox(height: 54),
                        SizedBox(
                          width: 230,
                          child: Column(
                            children: [
                              SizedBox(
                                height: 5,
                                child: CustomPaint(
                                  size: const Size(double.infinity, 5),
                                  painter: _PremiumProgressPainter(value),
                                ),
                              ),
                              const SizedBox(height: 13),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 320),
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, .25),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: Text(
                                  _loadingLabel(value),
                                  key: ValueKey(_loadingLabel(value)),
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Path _energyRoute(Size size) {
  const rows = 12;
  final path = Path();
  final left = size.width * .07;
  final right = size.width * .93;
  final top = size.height * .06;
  final step = size.height * .88 / (rows - 1);
  path.moveTo(left, top);
  for (var row = 0; row < rows; row++) {
    final y = top + row * step;
    final targetX = row.isEven ? right : left;
    if (row == 0) {
      path.lineTo(targetX, y);
    } else {
      final previousY = y - step;
      final previousX = row.isEven ? left : right;
      path.cubicTo(
        previousX,
        previousY + step * .48,
        previousX,
        y - step * .48,
        targetX,
        y,
      );
    }
  }
  return path;
}

class _TraceRevealClipper extends CustomClipper<Path> {
  final double progress;
  const _TraceRevealClipper(this.progress);

  @override
  Path getClip(Size size) {
    if (progress >= .995) return Path()..addRect(Offset.zero & size);
    final metric = _energyRoute(size).computeMetrics().first;
    final reveal = Path();
    final distance = metric.length * progress;
    final radius = size.width * .082;
    for (double offset = 0; offset <= distance; offset += 5.5) {
      final tangent = metric.getTangentForOffset(offset);
      if (tangent != null) {
        reveal.addOval(
          Rect.fromCircle(center: tangent.position, radius: radius),
        );
      }
    }
    return reveal;
  }

  @override
  bool shouldReclip(covariant _TraceRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}

class _EnergyTracePainter extends CustomPainter {
  final double progress;
  const _EnergyTracePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= .995) return;
    final metric = _energyRoute(size).computeMetrics().first;
    final end = metric.length * progress;
    final start = (end - size.width * .42).clamp(0.0, end);
    final activeTrail = metric.extractPath(start, end);
    final tangent = metric.getTangentForOffset(end);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF22D3EE).withOpacity(.34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(activeTrail, glow);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0x0018C7BE), Color(0xFF18C7BE), Colors.white],
      ).createShader(Offset.zero & size);
    canvas.drawPath(activeTrail, core);
    if (tangent != null) {
      final halo = Paint()
        ..color = const Color(0xFF38BDF8).withOpacity(.48)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
      canvas.drawCircle(tangent.position, 11, halo);
      canvas.drawCircle(tangent.position, 3.8, Paint()..color = Colors.white);
      canvas.drawCircle(
        tangent.position,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFF67E8F9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EnergyTracePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _LogoAuraPainter extends CustomPainter {
  final double progress;
  final double ambient;

  const _LogoAuraPainter({required this.progress, required this.ambient});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final entrance = Curves.easeOutCubic.transform(
      (progress / .28).clamp(0.0, 1.0),
    );
    final finale = Curves.easeOutCubic.transform(
      ((progress - .72) / .28).clamp(0.0, 1.0),
    );

    final aura = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF22D3EE).withOpacity(.14 + .08 * ambient),
          const Color(0xFF2563EB).withOpacity(.05),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * .48));
    canvas.drawCircle(center, size.width * (.32 + .05 * ambient), aura);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final radius = size.width * (.34 + i * .055) * entrance;
      final rotation = progress * math.pi * (i.isEven ? 1.35 : -1.05);
      ringPaint.color = const Color(0xFF1D4ED8).withOpacity(.10 + i * .025);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        rotation,
        math.pi * (.42 + i * .13),
        false,
        ringPaint,
      );
      ringPaint.color = const Color(0xFF14B8A6).withOpacity(.14);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        rotation + math.pi,
        math.pi * .22,
        false,
        ringPaint,
      );
    }

    final sparkPaint = Paint()..color = const Color(0xFF38BDF8);
    for (var i = 0; i < 8; i++) {
      final angle = progress * math.pi * 2 + i * math.pi / 4;
      final radius = size.width * (.39 + .035 * ((i % 3) / 2));
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final alpha = (.20 + .42 * finale) * (i.isEven ? 1 : .65);
      sparkPaint.color =
          (i % 3 == 0 ? const Color(0xFF14B8A6) : const Color(0xFF2563EB))
              .withOpacity(alpha.clamp(0.0, 1.0));
      canvas.drawCircle(point, i.isEven ? 2.2 : 1.3, sparkPaint);
    }

    if (finale > 0 && finale < 1) {
      final shockwave = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * (1 - finale)
        ..color = const Color(0xFF22D3EE).withOpacity(.65 * (1 - finale));
      canvas.drawCircle(center, size.width * (.24 + .28 * finale), shockwave);
    }
  }

  @override
  bool shouldRepaint(covariant _LogoAuraPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.ambient != ambient;
}

class _AnimatedBrandLockup extends StatelessWidget {
  final double progress;
  const _AnimatedBrandLockup({required this.progress});

  @override
  Widget build(BuildContext context) {
    final writeProgress = progress.clamp(0.0, 1.0);
    final subtitle = Curves.easeOutCubic.transform(
      ((progress - .72) / .28).clamp(0.0, 1.0),
    );
    return Column(
      children: [
        SizedBox(
          width: 214,
          height: 54,
          child: CustomPaint(painter: _HandwrittenBrandPainter(writeProgress)),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: subtitle,
          child: Transform.translate(
            offset: Offset(0, 7 * (1 - subtitle)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 22, child: Divider(color: Color(0xFF14B8A6))),
                SizedBox(width: 10),
                Text(
                  'TECNOLOGÍA PARA CRECER',
                  style: TextStyle(
                    color: Color(0xFF52657D),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.85,
                  ),
                ),
                SizedBox(width: 10),
                SizedBox(width: 22, child: Divider(color: Color(0xFF2563EB))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HandwrittenBrandPainter extends CustomPainter {
  final double progress;
  const _HandwrittenBrandPainter(this.progress);

  TextPainter _textPainter(Paint foreground) {
    return TextPainter(
      text: TextSpan(
        text: 'SafeBrok',
        style: TextStyle(
          foreground: foreground,
          fontSize: 44,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..color = const Color(0xFF0F766E).withOpacity(.16);
    final outline = _textPainter(outlinePaint);
    final origin = Offset(
      (size.width - outline.width) / 2,
      (size.height - outline.height) / 2,
    );
    outline.paint(canvas, origin);

    if (progress <= 0) return;
    final textRect = origin & outline.size;
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF0F766E),
          Color(0xFF14B8A6),
          Color(0xFF0891B2),
          Color(0xFF2563EB),
          Color(0xFF0F2747),
        ],
        stops: [0, .28, .48, .72, 1],
      ).createShader(textRect);
    final filled = _textPainter(fillPaint);
    final edge = textRect.left + textRect.width * progress;

    final reveal = Path()
      ..moveTo(textRect.left, textRect.top)
      ..lineTo(edge - 5, textRect.top)
      ..quadraticBezierTo(
        edge + 5,
        textRect.center.dy,
        edge - 2,
        textRect.bottom,
      )
      ..lineTo(textRect.left, textRect.bottom)
      ..close();
    canvas.save();
    canvas.clipPath(reveal);
    filled.paint(canvas, origin);
    canvas.restore();

    if (progress < .995) {
      final phase = progress * math.pi * 14;
      final nibY = textRect.center.dy + math.sin(phase) * textRect.height * .24;
      final nib = Offset(edge, nibY);
      final trail = Path()
        ..moveTo(edge - 25, nibY + math.sin(phase - .8) * 4)
        ..quadraticBezierTo(edge - 11, nibY - 7, edge, nibY);
      canvas.drawPath(
        trail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 7
          ..color = const Color(0xFF22D3EE).withOpacity(.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        trail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.7
          ..color = Colors.white,
      );
      canvas.drawCircle(
        nib,
        10,
        Paint()
          ..color = const Color(0xFF2563EB).withOpacity(.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawCircle(nib, 3.2, Paint()..color = Colors.white);
      canvas.drawCircle(
        nib,
        5.8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF14B8A6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HandwrittenBrandPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

String _loadingLabel(double progress) {
  if (progress < .25) return 'Activando núcleo SafeBrok';
  if (progress < .55) return 'Conectando tu organización';
  if (progress < .82) return 'Sincronizando tu espacio';
  return 'Todo listo';
}

class _PremiumProgressPainter extends CustomPainter {
  final double progress;
  const _PremiumProgressPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height),
    );
    canvas.drawRRect(track, Paint()..color = const Color(0xFFE2E8F0));
    if (progress <= 0) return;
    final width = size.width * progress;
    final active = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, size.height),
      Radius.circular(size.height),
    );
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF0F766E), Color(0xFF14B8A6), Color(0xFF2563EB)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(active, paint);
    final glowX = width.clamp(3.0, size.width - 3.0);
    canvas.drawCircle(
      Offset(glowX, size.height / 2),
      7,
      Paint()
        ..color = const Color(0xFF38BDF8).withOpacity(.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      Offset(glowX, size.height / 2),
      2.4,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _PremiumProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _CinematicBackgroundPainter extends CustomPainter {
  final double animation;
  const _CinematicBackgroundPainter(this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.15, -.35),
          radius: 1.15,
          colors: [Color(0xFFFFFFFF), Color(0xFFF4F7FC), Color(0xFFE8EEF8)],
        ).createShader(rect),
    );

    final drift = animation * math.pi * 2;
    final glowCenters = [
      Offset(size.width * (.18 + .025 * math.sin(drift)), size.height * .22),
      Offset(size.width * (.82 + .02 * math.cos(drift)), size.height * .72),
    ];
    for (var i = 0; i < glowCenters.length; i++) {
      final color = i == 0 ? const Color(0xFF14B8A6) : const Color(0xFF2563EB);
      canvas.drawCircle(
        glowCenters[i],
        size.shortestSide * .32,
        Paint()
          ..color = color.withOpacity(.055)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 72),
      );
    }

    final grid = Paint()
      ..color = const Color(0xFF1D4ED8).withOpacity(.035)
      ..strokeWidth = .7;
    const spacing = 44.0;
    final shift = animation * spacing;
    for (double x = -spacing + shift; x < size.width + spacing; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = -spacing + shift; y < size.height + spacing; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _CinematicBackgroundPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _SplashBackground extends StatelessWidget {
  const _SplashBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [Color(0xFFFFFFFF), Color(0xFFF4F6FB), Color(0xFFEAF0F8)],
        ),
      ),
    );
  }
}
