import 'package:flutter/material.dart';

import '../widget/app_top_bar.dart';
import '../widget/home_bottom_nav.dart';
import 'camera_screen.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onMoveTab;

  const HomeScreen({super.key, required this.onMoveTab});

  void _openCamera(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          onMoveTab: (index) {
            Navigator.of(context).pop();
            onMoveTab(index);
          },
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // 상단 바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppTopBar(
              title: '',
              leadingIcon: Icons.settings_outlined,
              trailing: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF81D4FA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined, color: Colors.white, size: 13),
                      SizedBox(width: 4),
                      Text(
                        '촬영 스팟 지도',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              trailingWidth: 120,
            ),
          ),

          const SizedBox(height: 8),

          // 로고 이미지 영역
          Expanded(
            child: Container(
              color: const Color(0x12000000),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _GridPainter()),
                  CustomPaint(painter: _VignettePainter()),
                  Center(
                    child: Image.asset(
                      'assets/images/pozy_logo.png',
                      fit: BoxFit.contain,
                      width: 240,
                      height: 240,
                    ),
                  ),
                  const _ViewfinderBrackets(),
                  CustomPaint(painter: _FocusPointPainter()),
                ],
              ),
            ),
          ),

          // 말풍선
          _SpeechBubble(),

          // 홈 전용 하단 네비게이션 바
          HomeBottomNav(
            currentIndex: 0,
            onTap: onMoveTab,
            onShutter: () => _openCamera(context),
          ),
        ],
      ),
    );
  }
}

// ── 말풍선 ───────────────────────────────────────────────
class _SpeechBubble extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF81D4FA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '셔터를 눌러 촬영을 시작해보세요!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(12, 7),
          painter: _BubbleTailPainter(),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ── 뷰파인더 브라켓 ──────────────────────────────────────
class _ViewfinderBrackets extends StatelessWidget {
  const _ViewfinderBrackets();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _BracketPainter());
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const margin = 20.0;
    const arm = 24.0;

    canvas.drawLine(const Offset(margin, margin), Offset(margin + arm, margin), paint);
    canvas.drawLine(const Offset(margin, margin), Offset(margin, margin + arm), paint);
    canvas.drawLine(Offset(size.width - margin, margin), Offset(size.width - margin - arm, margin), paint);
    canvas.drawLine(Offset(size.width - margin, margin), Offset(size.width - margin, margin + arm), paint);
    canvas.drawLine(Offset(margin, size.height - margin), Offset(margin + arm, size.height - margin), paint);
    canvas.drawLine(Offset(margin, size.height - margin), Offset(margin, size.height - margin - arm), paint);
    canvas.drawLine(Offset(size.width - margin, size.height - margin), Offset(size.width - margin - arm, size.height - margin), paint);
    canvas.drawLine(Offset(size.width - margin, size.height - margin), Offset(size.width - margin, size.height - margin - arm), paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}

// ── 말풍선 꼬리 Painter ──────────────────────────────────
class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF81D4FA)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) => false;
}

// ── Pulse 셔터 버튼 ──────────────────────────────────────
class _PulsingShutterButton extends StatefulWidget {
  final VoidCallback onTap;
  const _PulsingShutterButton({required this.onTap});

  @override
  State<_PulsingShutterButton> createState() => _PulsingShutterButtonState();
}

class _PulsingShutterButtonState extends State<_PulsingShutterButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _scale = Tween<double>(begin: 1.0, end: 1.55).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.45, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => Transform.scale(
                scale: _scale.value,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF29B6F6)
                        .withValues(alpha: _opacity.value),
                  ),
                ),
              ),
            ),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF29B6F6), width: 2.5),
                color: Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 3분할 그리드 Painter ─────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF29B6F6).withValues(alpha: 0.25)
      ..strokeWidth = 0.8;

    // 세로선 2개 (1/3, 2/3)
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), paint);

    // 가로선 2개 (1/3, 2/3)
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), paint);
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

// ── 비네팅 Painter ───────────────────────────────────────
class _VignettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.longestSide * 0.75;

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.35),
        ],
        stops: const [0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_VignettePainter old) => false;
}

// ── 포커스 포인트 Painter ────────────────────────────────
class _FocusPointPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const crossSize = 10.0;
    const gap = 6.0;

    final paint = Paint()
      ..color = const Color(0xFF29B6F6).withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 수평선 (가운데 gap)
    canvas.drawLine(Offset(center.dx - crossSize - gap, center.dy), Offset(center.dx - gap, center.dy), paint);
    canvas.drawLine(Offset(center.dx + gap, center.dy), Offset(center.dx + crossSize + gap, center.dy), paint);
    // 수직선 (가운데 gap)
    canvas.drawLine(Offset(center.dx, center.dy - crossSize - gap), Offset(center.dx, center.dy - gap), paint);
    canvas.drawLine(Offset(center.dx, center.dy + gap), Offset(center.dx, center.dy + crossSize + gap), paint);
  }

  @override
  bool shouldRepaint(_FocusPointPainter old) => false;
}
