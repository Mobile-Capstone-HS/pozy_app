import 'package:flutter/material.dart';

import '../composition_rule.dart';

/// 중앙 정렬 규칙: 중앙 십자선과 원을 가이드로 사용.
class CenterWeightedRule extends CompositionRule {
  const CenterWeightedRule();

  /// normalized 좌표계에서 중앙까지의 거리가 이 값 이상이면 score=0.
  static const _maxDistance = 0.5;

  @override
  CompositionRuleType get type => CompositionRuleType.centerWeighted;

  @override
  String get label => '중앙';

  @override
  IconData get icon => Icons.center_focus_strong_rounded;

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

    final center = bounds.center;

    // 중앙 십자
    const crossHalfLen = 24.0;
    canvas.drawLine(
      center + const Offset(-crossHalfLen, 0),
      center + const Offset(crossHalfLen, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, -crossHalfLen),
      center + const Offset(0, crossHalfLen),
      paint,
    );

    // 중앙 기준 원 (안내용)
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final radius = bounds.shortestSide * 0.2;
    canvas.drawCircle(center, radius, circlePaint);
  }

  @override
  double scoreAlignment(Offset subjectCenter, {Size? subjectSize}) {
    final dist = (subjectCenter - const Offset(0.5, 0.5)).distance;
    final clamped = dist.clamp(0.0, _maxDistance);
    return 1.0 - clamped / _maxDistance;
  }

  @override
  String guidance(Offset subjectCenter) {
    const center = Offset(0.5, 0.5);
    final dist = (subjectCenter - center).distance;
    if (dist < 0.06) {
      return '좋아요. 중앙에 잘 맞았어요.';
    }
    final dx = center.dx - subjectCenter.dx;
    final dy = center.dy - subjectCenter.dy;
    if (dx.abs() > dy.abs()) {
      return dx > 0 ? '중앙으로 오른쪽으로' : '중앙으로 왼쪽으로';
    }
    return dy > 0 ? '중앙으로 아래로' : '중앙으로 위로';
  }
}
