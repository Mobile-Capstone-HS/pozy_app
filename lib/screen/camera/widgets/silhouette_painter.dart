import 'package:flutter/material.dart';
import '../../../coaching/portrait/silhouette_shapes.dart';

class SilhouettePainter extends CustomPainter {
  final SilhouetteType type;

  SilhouettePainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    if (type == SilhouetteType.none) return;

    final path = SilhouetteShapes.getPath(type, size);

    // 반투명 면 그리기
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x33FFFFFF) // 매우 옅은 흰색
        ..style = PaintingStyle.fill,
    );

    // 글로우 효과를 위한 외곽선
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x6638BDF8) // 옅은 Cyan 글로우
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 선명한 실선 외곽선
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xAAFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant SilhouettePainter oldDelegate) {
    return oldDelegate.type != type;
  }
}
