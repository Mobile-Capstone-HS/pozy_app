import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../composition_rule.dart';

/// 3분할 규칙: 격자를 3등분한 교차점 4곳을 기준.
class RuleOfThirds extends CompositionRule {
  const RuleOfThirds();

  static const _targets = <Offset>[
    Offset(1 / 3, 1 / 3),
    Offset(2 / 3, 1 / 3),
    Offset(1 / 3, 2 / 3),
    Offset(2 / 3, 2 / 3),
  ];

  /// 정렬 양호로 간주하는 거리 상한 (normalized). 이 값을 넘으면 score=0.
  static const _maxAlignedDistance = 0.33;

  @override
  CompositionRuleType get type => CompositionRuleType.ruleOfThirds;

  @override
  String get label => '3분할';

  @override
  IconData get icon => Icons.grid_3x3_rounded;

  @override
  void paintOverlay(
    Canvas canvas,
    Rect bounds, {
    required Color color,
    double strokeWidth = 1.0,
  }) {
    final gridPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;

    final dx1 = bounds.left + bounds.width / 3;
    final dx2 = bounds.left + bounds.width * 2 / 3;
    final dy1 = bounds.top + bounds.height / 3;
    final dy2 = bounds.top + bounds.height * 2 / 3;

    canvas.drawLine(
        Offset(dx1, bounds.top), Offset(dx1, bounds.bottom), gridPaint);
    canvas.drawLine(
        Offset(dx2, bounds.top), Offset(dx2, bounds.bottom), gridPaint);
    canvas.drawLine(
        Offset(bounds.left, dy1), Offset(bounds.right, dy1), gridPaint);
    canvas.drawLine(
        Offset(bounds.left, dy2), Offset(bounds.right, dy2), gridPaint);

    // 교차점 타겟 (+ 모양)
    final targetPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final pt in [
      Offset(dx1, dy1),
      Offset(dx2, dy1),
      Offset(dx1, dy2),
      Offset(dx2, dy2),
    ]) {
      canvas.drawLine(
          pt + const Offset(-8, 0), pt + const Offset(8, 0), targetPaint);
      canvas.drawLine(
          pt + const Offset(0, -8), pt + const Offset(0, 8), targetPaint);
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
      return '좋아요. 3분할 교차점에 잘 맞았어요.';
    }
    final dx = nearest.dx - subjectCenter.dx;
    final dy = nearest.dy - subjectCenter.dy;
    final horizontal = dx.abs() > dy.abs();
    if (horizontal) {
      return dx > 0 ? '조금 오른쪽으로' : '조금 왼쪽으로';
    }
    return dy > 0 ? '조금 아래로' : '조금 위로';
  }
}
