import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pose_camera_app/features/composition/composition_policy.dart';

class GoldenRatioPolicy implements CompositionPolicy {
  static const double _perfectThresholdRatio = 0.10;
  static const double _phi = 1.6180339887;
  static const double _ratio = 1 / _phi;

  @override
  String get label => '황금비율';

  @override
  Color get accentColor => const Color(0xFFFFD54F);

  @override
  List<Offset> getTargets(Size size) {
    Rect rect0 = Rect.fromLTWH(0, 0, size.width, size.height);
    Rect rect1 = Rect.fromLTWH(0, 0, size.width, size.height);
    Rect rect2 = Rect.fromLTWH(0, 0, size.width, size.height);
    Rect rect3 = Rect.fromLTWH(0, 0, size.width, size.height);

    rect0 = _shrinkRect(rect0, const [2, 3, 0, 1]);
    rect1 = _shrinkRect(rect1, const [0, 3, 2, 1]);
    rect2 = _shrinkRect(rect2, const [2, 1, 0, 3]);
    rect3 = _shrinkRect(rect3, const [0, 1, 2, 3]);

    return [
      rect0.center,
      rect1.center,
      rect2.center,
      rect3.center,
    ];
  }

  @override
  bool isPerfect(double distance, Size size) {
    return distance < size.width * _perfectThresholdRatio;
  }

  @override
  void paintGuide(Canvas canvas, Size size) {
    final spiralLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final spiralShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final targets = getTargets(size);

    double xMin = 0;
    double yMin = 0;
    double xMax = size.width;
    double yMax = size.height;

    void drawSpiralArc(Rect rect, double startAngle, double sweepAngle) {
      canvas.drawArc(rect, startAngle, sweepAngle, false, spiralShadowPaint);
      canvas.drawArc(rect, startAngle, sweepAngle, false, spiralLinePaint);
    }

    void drawSpiralRect(Rect rect) {
      canvas.drawRect(rect, spiralShadowPaint);
      canvas.drawRect(rect, spiralLinePaint);
    }

    for (int i = 0; i < 8; i++) {
      final w = xMax - xMin;
      final h = yMax - yMin;
      if (w <= 2 || h <= 2) break;

      final dir = i % 4;
      if (dir == 0) {
        drawSpiralRect(Rect.fromLTRB(xMin, yMin, xMin + w * _ratio, yMax));
        drawSpiralArc(
          Rect.fromCenter(
            center: Offset(xMin + w * _ratio, yMax),
            width: w * _ratio * 2,
            height: h * 2,
          ),
          math.pi,
          math.pi / 2,
        );
        xMin += w * _ratio;
      } else if (dir == 1) {
        drawSpiralRect(Rect.fromLTRB(xMin, yMin, xMax, yMin + h * _ratio));
        drawSpiralArc(
          Rect.fromCenter(
            center: Offset(xMin, yMin + h * _ratio),
            width: w * 2,
            height: h * _ratio * 2,
          ),
          -math.pi / 2,
          math.pi / 2,
        );
        yMin += h * _ratio;
      } else if (dir == 2) {
        drawSpiralRect(Rect.fromLTRB(xMin + w * (1 - _ratio), yMin, xMax, yMax));
        drawSpiralArc(
          Rect.fromCenter(
            center: Offset(xMin + w * (1 - _ratio), yMin),
            width: w * _ratio * 2,
            height: h * 2,
          ),
          0,
          math.pi / 2,
        );
        xMax -= w * _ratio;
      } else {
        drawSpiralRect(Rect.fromLTRB(xMin, yMin + h * (1 - _ratio), xMax, yMax));
        drawSpiralArc(
          Rect.fromCenter(
            center: Offset(xMax, yMin + h * (1 - _ratio)),
            width: w * 2,
            height: h * _ratio * 2,
          ),
          math.pi / 2,
          math.pi / 2,
        );
        yMax -= h * _ratio;
      }
    }

    final targetPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;

    for (final target in targets) {
      canvas.drawCircle(target, 4.0, targetPaint);
    }
  }

  Rect _shrinkRect(Rect rect, List<int> directions) {
    double left = rect.left;
    double top = rect.top;
    double right = rect.right;
    double bottom = rect.bottom;

    for (int i = 0; i < 8; i++) {
      final width = right - left;
      final height = bottom - top;
      final dir = directions[i % 4];

      if (dir == 0) {
        left += width * _ratio;
      } else if (dir == 1) {
        top += height * _ratio;
      } else if (dir == 2) {
        right -= width * _ratio;
      } else {
        bottom -= height * _ratio;
      }
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }
}
