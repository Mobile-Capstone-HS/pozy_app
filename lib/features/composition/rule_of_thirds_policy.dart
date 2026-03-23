import 'package:flutter/material.dart';
import 'package:pose_camera_app/features/composition/composition_policy.dart';

class RuleOfThirdsPolicy implements CompositionPolicy {
  static const double _perfectThresholdRatio = 0.10;

  @override
  String get label => '3분할';

  @override
  Color get accentColor => const Color(0xFF4FC3F7);

  @override
  List<Offset> getTargets(Size size) {
    final x1 = size.width / 3;
    final x2 = size.width * 2 / 3;
    final y1 = size.height / 3;
    final y2 = size.height * 2 / 3;

    return [
      Offset(x1, y1),
      Offset(x2, y1),
      Offset(x1, y2),
      Offset(x2, y2),
    ];
  }

  @override
  bool isPerfect(double distance, Size size) {
    return distance < size.width * _perfectThresholdRatio;
  }

  @override
  void paintGuide(Canvas canvas, Size size) {
    final targets = getTargets(size);
    final x1 = size.width / 3;
    final x2 = size.width * 2 / 3;
    final y1 = size.height / 3;
    final y2 = size.height * 2 / 3;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    canvas.drawLine(Offset(x1, 0), Offset(x1, size.height), gridPaint);
    canvas.drawLine(Offset(x2, 0), Offset(x2, size.height), gridPaint);
    canvas.drawLine(Offset(0, y1), Offset(size.width, y1), gridPaint);
    canvas.drawLine(Offset(0, y2), Offset(size.width, y2), gridPaint);

    final targetPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    for (final target in targets) {
      canvas.drawCircle(target, 4.0, targetPaint);
    }
  }
}
