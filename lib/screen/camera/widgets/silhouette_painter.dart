import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../../coaching/portrait/silhouette_shapes.dart';

class SilhouettePainter extends CustomPainter {
  final SilhouetteType type;
  final Rect? targetBox;

  SilhouettePainter({required this.type, this.targetBox});

  @override
  void paint(Canvas canvas, Size size) {
    if (type == SilhouetteType.none) return;

    // targetBox가 주어지면 해당 크기에 맞춰 Path를 생성, 없으면 전체 크기 사용
    final boxSize = targetBox?.size ?? size;
    final path = SilhouetteShapes.getPath(type, boxSize);

    // targetBox 위치로 Path 이동
    final finalPath = targetBox != null ? path.shift(targetBox!.topLeft) : path;

    // 1. 반투명한 내부 채우기 (연한 핑크/퍼플 그라데이션)
    final gradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0x33FF69B4), // 연한 핫핑크
        Color(0x228A2BE2), // 연한 블루바이올렛
      ],
    ).createShader(targetBox ?? (Offset.zero & size));

    canvas.drawPath(
      finalPath,
      Paint()
        ..shader = gradient
        ..style = PaintingStyle.fill,
    );

    // 2. 외부 글로우 효과 (네온 스타일)
    canvas.drawPath(
      finalPath,
      Paint()
        ..color = const Color(0x99FF69B4) // 네온 핑크 글로우
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // 3. 점선(Dashed) 형태의 선명한 외곽선 (TikTok 스타일)
    // 점선을 위한 PathMetric 활용
    final dashPath = Path();
    const dashWidth = 8.0;
    const dashSpace = 6.0;

    for (final ui.PathMetric metric in finalPath.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final length = distance + dashWidth < metric.length
            ? dashWidth
            : metric.length - distance;
        dashPath.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(
      dashPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant SilhouettePainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.targetBox != targetBox;
  }
}
