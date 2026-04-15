import 'package:flutter/material.dart';

/// 객체 모드에서 ROI(관심 영역)를 표시하는 페인터.
/// - 드래그 중: 점선 사각형
/// - 잠긴 상태: 파란 실선 사각형 + 반투명 채우기
class RoiPainter extends CustomPainter {
  final Rect? lockedRoi;
  final Offset? dragStart;
  final Offset? dragEnd;
  final bool isDrawing;

  const RoiPainter({
    this.lockedRoi,
    this.dragStart,
    this.dragEnd,
    required this.isDrawing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isDrawing && dragStart != null && dragEnd != null) {
      final rect = Rect.fromPoints(dragStart!, dragEnd!);
      _drawDashedRect(canvas, rect, const Color(0xCCFFFFFF), strokeWidth: 1.5);
      return;
    }

    if (lockedRoi != null) {
      final r = lockedRoi!;
      final rect = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      );
      _drawLockedDetectionRect(canvas, rect, const Color(0xFF38BDF8));
    }
  }

  void _drawLockedDetectionRect(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, Paint()..color = const Color(0x1438BDF8));
  }

  void _drawDashedRect(
    Canvas canvas,
    Rect rect,
    Color color, {
    double strokeWidth = 1.5,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    const dash = 8.0;
    const gap = 5.0;

    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var d = 0.0;
      while (d < total) {
        canvas.drawLine(
          a + dir * d,
          a + dir * (d + dash).clamp(0.0, total),
          paint,
        );
        d += dash + gap;
      }
    }

    line(rect.topLeft, rect.topRight);
    line(rect.topRight, rect.bottomRight);
    line(rect.bottomRight, rect.bottomLeft);
    line(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(RoiPainter old) =>
      old.lockedRoi != lockedRoi ||
      old.dragStart != dragStart ||
      old.dragEnd != dragEnd ||
      old.isDrawing != isDrawing;
}
