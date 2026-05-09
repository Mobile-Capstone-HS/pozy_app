import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main_shell.dart';

const _kBlue = Color(0xFF2F9AF2);
const _kDeepBlue = Color(0xFF1769C2);
const _kBg = Color(0xFFF6FAFF);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _exitController;
  bool _loggedFirstBuild = false;

  late final Animation<double> _bracketProgress;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _taglineFade;
  late final Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();
    debugPrint('[SplashScreen] initState');

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

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
      curve: const Interval(0.0, 0.48, curve: Curves.easeOutCubic),
    );

    _logoFade = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.28, 0.72, curve: Curves.easeOut),
    );

    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.28, 0.72, curve: Curves.easeOutBack),
      ),
    );

    _taglineFade = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.62, 1.0, curve: Curves.easeOut),
    );

    _exitFade = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    _logoController.forward();
    debugPrint('[SplashScreen] timer scheduled -> MainShell in 2400ms');
    Timer(const Duration(milliseconds: 2400), _navigateToMain);
  }

  Future<void> _navigateToMain() async {
    debugPrint('[SplashScreen] _navigateToMain start mounted=$mounted');
    if (!mounted) return;
    await _exitController.forward();
    if (!mounted) return;
    debugPrint('[SplashScreen] pushing MainShell');
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
    if (!_loggedFirstBuild) {
      _loggedFirstBuild = true;
      debugPrint('[SplashScreen] first build');
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: FadeTransition(
        opacity: _exitFade,
        child: Stack(
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFF3F9FF),
                    Color(0xFFEAF5FF),
                  ],
                ),
              ),
              child: SizedBox.expand(),
            ),
            Positioned(
              top: -96,
              right: -104,
              child: Transform.rotate(
                angle: 0.28,
                child: CustomPaint(
                  size: const Size(300, 300),
                  painter: const _ShutterSplashShadowPainter(opacity: 0.085),
                ),
              ),
            ),
            Positioned(
              bottom: -118,
              left: -112,
              child: Transform.rotate(
                angle: -0.18,
                child: CustomPaint(
                  size: const Size(320, 320),
                  painter: const _ShutterSplashShadowPainter(opacity: 0.075),
                ),
              ),
            ),
            Center(
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 5),
                    AnimatedBuilder(
                      animation: _logoController,
                      builder: (context, child) {
                        return SizedBox(
                          width: 292,
                          height: 206,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _LogoDepthPainter(
                                    progress: _logoFade.value,
                                  ),
                                ),
                              ),
                              CustomPaint(
                                size: const Size(292, 206),
                                painter: _BracketPainter(
                                  progress: _bracketProgress.value,
                                ),
                              ),
                              FadeTransition(
                                opacity: _logoFade,
                                child: ScaleTransition(
                                  scale: _logoScale,
                                  child: Container(
                                    width: 248,
                                    height: 174,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(34),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _kDeepBlue.withValues(
                                            alpha: 0.14,
                                          ),
                                          blurRadius: 28,
                                          spreadRadius: -10,
                                          offset: const Offset(0, 18),
                                        ),
                                        BoxShadow(
                                          color: Colors.white.withValues(
                                            alpha: 0.92,
                                          ),
                                          blurRadius: 14,
                                          spreadRadius: -6,
                                          offset: const Offset(-8, -10),
                                        ),
                                      ],
                                    ),
                                    child: Image.asset(
                                      'assets/images/pozy_logo2.png',
                                      width: 238,
                                      height: 166,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Image.asset(
                                              'assets/images/pozy_logo2.png',
                                              width: 238,
                                              height: 166,
                                              fit: BoxFit.contain,
                                            );
                                          },
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 42,
                                bottom: 26,
                                child: Opacity(
                                  opacity: _logoFade.value,
                                  child: const _MiniLens(),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    FadeTransition(
                      opacity: _taglineFade,
                      child: Column(
                        children: [
                          const _RaisedDivider(),
                          const SizedBox(height: 16),
                          const Text(
                            '\uCC0D\uB294 \uC21C\uAC04\uBD80\uD130 \uACE0\uB974\uB294 \uC21C\uAC04\uAE4C\uC9C0',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF5798CF),
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 4),
                    FadeTransition(
                      opacity: _taglineFade,
                      child: const _PulsingDots(),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoDepthPainter extends CustomPainter {
  final double progress;

  const _LogoDepthPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = progress.clamp(0.0, 1.0);
    if (opacity == 0) return;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 + 8),
      width: size.width * 0.78,
      height: size.height * 0.58,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(42));

    final shadowPaint = Paint()
      ..color = _kDeepBlue.withValues(alpha: 0.10 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawRRect(rrect.shift(const Offset(0, 18)), shadowPaint);

    final platePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFE9F6FF), Color(0xFFD9EEFF)],
      ).createShader(rect);
    canvas.drawRRect(rrect, platePaint);

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.88 * opacity),
          Colors.white.withValues(alpha: 0.05),
          _kBlue.withValues(alpha: 0.22 * opacity),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(1), highlightPaint);
  }

  @override
  bool shouldRepaint(_LogoDepthPainter old) => old.progress != progress;
}

class _MiniLens extends StatelessWidget {
  const _MiniLens();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.45, -0.5),
          radius: 0.9,
          colors: [Colors.white, Color(0xFF7CCAFF), _kBlue, _kDeepBlue],
          stops: [0.0, 0.2, 0.66, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: _kDeepBlue.withValues(alpha: 0.24),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.9),
            blurRadius: 4,
            offset: const Offset(-2, -2),
          ),
        ],
      ),
    );
  }
}

class _RaisedDivider extends StatelessWidget {
  const _RaisedDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFF8FD0FF), _kBlue],
        ),
        boxShadow: [
          BoxShadow(
            color: _kDeepBlue.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.85),
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
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

    final opacity = progress.clamp(0.0, 1.0);
    const arm = 33.0;
    const inset = 8.0;

    void drawCorner(Offset corner, double xDir, double yDir) {
      final horizontalEnd = Offset(
        corner.dx + xDir * arm * progress,
        corner.dy,
      );
      final verticalEnd = Offset(corner.dx, corner.dy + yDir * arm * progress);

      final shadowPaint = Paint()
        ..color = _kDeepBlue.withValues(alpha: 0.12 * opacity)
        ..strokeWidth = 4.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
      final basePaint = Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF7CC8FF).withValues(alpha: 0.72 * opacity),
                _kBlue.withValues(alpha: 0.62 * opacity),
                _kDeepBlue.withValues(alpha: 0.46 * opacity),
              ],
            ).createShader(
              Rect.fromCenter(
                center: corner,
                width: arm * 1.6,
                height: arm * 1.6,
              ),
            )
        ..strokeWidth = 3.7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final glossPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.46 * opacity)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(corner.dx, corner.dy)
        ..lineTo(horizontalEnd.dx, horizontalEnd.dy)
        ..moveTo(corner.dx, corner.dy)
        ..lineTo(verticalEnd.dx, verticalEnd.dy);

      canvas.drawPath(path.shift(const Offset(0, 2.5)), shadowPaint);
      canvas.drawPath(path, basePaint);

      final glossPath = Path()
        ..moveTo(corner.dx + xDir * 4, corner.dy - 1.0)
        ..lineTo(corner.dx + xDir * arm * 0.72 * progress, corner.dy - 1.0);
      canvas.drawPath(glossPath, glossPaint);
    }

    drawCorner(const Offset(inset, inset), 1, 1);
    drawCorner(Offset(size.width - inset, inset), -1, 1);
    drawCorner(Offset(inset, size.height - inset), 1, -1);
    drawCorner(Offset(size.width - inset, size.height - inset), -1, -1);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.progress != progress;
}

class _ShutterSplashShadowPainter extends CustomPainter {
  final double opacity;

  const _ShutterSplashShadowPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.47;
    final paint = Paint()
      ..color = _kBlue.withValues(alpha: opacity)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    for (var index = 0; index < 6; index++) {
      final angle = (math.pi * 2 / 6) * index - math.pi / 2;
      final nextAngle = angle + math.pi / 3;
      final path = Path()
        ..moveTo(
          center.dx + math.cos(angle + 0.25) * radius * 0.22,
          center.dy + math.sin(angle + 0.25) * radius * 0.22,
        )
        ..lineTo(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius,
        )
        ..quadraticBezierTo(
          center.dx + math.cos((angle + nextAngle) / 2) * radius * 1.06,
          center.dy + math.sin((angle + nextAngle) / 2) * radius * 1.06,
          center.dx + math.cos(nextAngle) * radius,
          center.dy + math.sin(nextAngle) * radius,
        )
        ..lineTo(
          center.dx + math.cos(nextAngle - 0.25) * radius * 0.22,
          center.dy + math.sin(nextAngle - 0.25) * radius * 0.22,
        )
        ..close();
      canvas.drawPath(path, paint);
    }

    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.36)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius * 0.28, centerPaint);
  }

  @override
  bool shouldRepaint(_ShutterSplashShadowPainter old) => old.opacity != opacity;
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_ctrl.value + (index * 0.18)) % 1.0;
            final opacity = phase < 0.5
                ? 0.35 + (phase * 1.3)
                : 1.0 - ((phase - 0.5) * 1.1);
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.45, -0.5),
                  radius: 0.85,
                  colors: [
                    Colors.white.withValues(alpha: opacity.clamp(0.35, 0.9)),
                    const Color(
                      0xFF8BD3FF,
                    ).withValues(alpha: opacity.clamp(0.35, 0.85)),
                    _kBlue.withValues(alpha: opacity.clamp(0.35, 0.82)),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _kDeepBlue.withValues(
                      alpha: (opacity * 0.14).clamp(0.05, 0.14),
                    ),
                    blurRadius: 7,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
