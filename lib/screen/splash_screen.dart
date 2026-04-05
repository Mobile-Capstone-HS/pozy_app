import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main_shell.dart';

// Blue accent used throughout the splash
const _kBlue = Color(0xFF4A90E2);
const _kBlueSoft = Color(0xFF6AAEF5);
const _kBg = Color(0xFFF5F8FF); // very light blue-white

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _exitController;

  late final Animation<double> _bracketProgress;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _taglineFade;
  late final Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _bracketProgress = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.0, 0.48, curve: Curves.easeOut),
    );

    _logoFade = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.28, 0.7, curve: Curves.easeOut),
    );

    _logoScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.28, 0.7, curve: Curves.easeOut),
      ),
    );

    _taglineFade = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.62, 1.0, curve: Curves.easeOut),
    );

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );

    _logoController.forward();
    Timer(const Duration(milliseconds: 2400), _navigateToMain);
  }

  Future<void> _navigateToMain() async {
    if (!mounted) return;
    await _exitController.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (ctx, anim, secondAnim) => const MainShell(),
        transitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: FadeTransition(
        opacity: _exitFade,
        child: Stack(
          children: [
            // Soft gradient wash top-right
            Positioned(
              top: -80,
              right: -80,
              child: AnimatedBuilder(
                animation: _logoFade,
                builder: (context, child) => Opacity(
                  opacity: _logoFade.value * 0.45,
                  child: Container(
                    width: 340,
                    height: 340,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xFFBDD8FA), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Soft gradient wash bottom-left
            Positioned(
              bottom: -60,
              left: -60,
              child: AnimatedBuilder(
                animation: _logoFade,
                builder: (context, child) => Opacity(
                  opacity: _logoFade.value * 0.3,
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xFFBDD8FA), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Center content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Viewfinder brackets + Pozy logo
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      return SizedBox(
                        width: 230,
                        height: 150,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(230, 150),
                              painter: _BracketPainter(
                                progress: _bracketProgress.value,
                              ),
                            ),
                            FadeTransition(
                              opacity: _logoFade,
                              child: ScaleTransition(
                                scale: _logoScale,
                                child: ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                    colors: [_kBlue, _kBlueSoft],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(bounds),
                                  child: const Text(
                                    'Pozy',
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 56,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -2.0,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 18),

                  // Thin divider line
                  FadeTransition(
                    opacity: _taglineFade,
                    child: Container(
                      width: 32,
                      height: 1.5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          colors: [Colors.transparent, _kBlue, Colors.transparent],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Tagline
                  FadeTransition(
                    opacity: _taglineFade,
                    child: const Text(
                      '당신의 촬영을 보다 이롭게',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF7B9ABF),
                        letterSpacing: 0.3,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom pulsing dot
            Positioned(
              bottom: 52,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _taglineFade,
                child: const Center(child: _PulsingDot()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final double progress;

  const _BracketPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;

    final paint = Paint()
      ..color = _kBlue.withValues(alpha: (progress * 0.7).clamp(0.0, 1.0))
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const arm = 24.0;
    const r = 5.0;

    void drawCorner(Offset corner, double xDir, double yDir) {
      canvas.drawLine(corner, Offset(corner.dx + xDir * arm * progress, corner.dy), paint);
      canvas.drawLine(corner, Offset(corner.dx, corner.dy + yDir * arm * progress), paint);
    }

    drawCorner(const Offset(r, r), 1, 1);
    drawCorner(Offset(size.width - r, r), -1, 1);
    drawCorner(Offset(r, size.height - r), 1, -1);
    drawCorner(Offset(size.width - r, size.height - r), -1, -1);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.progress != progress;
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kBlue.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
