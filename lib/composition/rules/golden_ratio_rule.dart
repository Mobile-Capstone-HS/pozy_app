import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../composition_rule.dart';

/// 황금비 규칙: 1:1.618 → 0.382 / 0.618 지점의 수평·수직선과 4개 교차점.
class GoldenRatioRule extends CompositionRule {
  const GoldenRatioRule();

  /// 1/phi ≈ 0.382, 1 - 1/phi ≈ 0.618.
  static const double _a = 0.381966;
  static const double _b = 0.618034;

  static const _targets = <Offset>[
    Offset(_a, _a),
    Offset(_b, _a),
    Offset(_a, _b),
    Offset(_b, _b),
  ];

  static const _maxAlignedDistance = 0.33;

  @override
  CompositionRuleType get type => CompositionRuleType.goldenRatio;

  @override
  String get label => '황금비';

  @override
  IconData get icon => Icons.hexagon_outlined;

  @override
  void paintOverlay(
    Canvas canvas,
    Rect bounds, {
    required Color color,
    double strokeWidth = 1.0,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;

    final dx1 = bounds.left + bounds.width * _a;
    final dx2 = bounds.left + bounds.width * _b;
    final dy1 = bounds.top + bounds.height * _a;
    final dy2 = bounds.top + bounds.height * _b;

    canvas.drawLine(
        Offset(dx1, bounds.top), Offset(dx1, bounds.bottom), paint);
    canvas.drawLine(
        Offset(dx2, bounds.top), Offset(dx2, bounds.bottom), paint);
    canvas.drawLine(
        Offset(bounds.left, dy1), Offset(bounds.right, dy1), paint);
    canvas.drawLine(
        Offset(bounds.left, dy2), Offset(bounds.right, dy2), paint);

    // 4개 교차점에 작은 원
    final dotPaint = Paint()..color = color;
    for (final pt in [
      Offset(dx1, dy1),
      Offset(dx2, dy1),
      Offset(dx1, dy2),
      Offset(dx2, dy2),
    ]) {
      canvas.drawCircle(pt, 3.0, dotPaint);
    }
  }

  @override
  double scoreAlignment(Offset subjectCenter, {Size? subjectSize}) {
    final minDist = _targets
        .map((t) => (subjectCenter - t).distance)
        .reduce(math.min);
    final clamped = minDist.clamp(0.0, _maxAlignedDistance);
    return 1.0 - clamped / _maxAlignedDistance;
  }

  @override
  String guidance(Offset subjectCenter) {
    var nearest = _targets.first;
    var nearestDist = double.infinity;
    for (final t in _targets) {
      final d = (subjectCenter - t).distance;
      if (d < nearestDist) {
        nearestDist = d;
        nearest = t;
      }
    }
    if (nearestDist < 0.06) {
      return '좋아요. 황금비 교차점에 잘 맞았어요.';
    }
    final dx = nearest.dx - subjectCenter.dx;
    final dy = nearest.dy - subjectCenter.dy;
    if (dx.abs() > dy.abs()) {
      return dx > 0 ? '황금비선 오른쪽으로 조금' : '황금비선 왼쪽으로 조금';
    }
    return dy > 0 ? '황금비선 아래로 조금' : '황금비선 위로 조금';
  }
}
