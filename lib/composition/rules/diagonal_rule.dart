import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../composition_rule.dart';

/// 대각선 구도: 두 대각선(좌상-우하, 우상-좌하)을 가이드로 사용.
///
/// 정렬은 피사체 중심에서 가장 가까운 대각선까지의 수직 거리로 평가.
class DiagonalRule extends CompositionRule {
  const DiagonalRule();

  /// normalized 좌표계에서 대각선까지의 거리가 이 값 이상이면 score=0.
  static const _maxDistance = 0.35;

  @override
  CompositionRuleType get type => CompositionRuleType.diagonal;

  @override
  String get label => '대각선';

  @override
  IconData get icon => Icons.signal_cellular_4_bar_rounded;

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

    canvas.drawLine(bounds.topLeft, bounds.bottomRight, paint);
    canvas.drawLine(bounds.topRight, bounds.bottomLeft, paint);

    // 중앙 교차점
    canvas.drawCircle(bounds.center, 3.0, Paint()..color = color);
  }

  /// 점과 두 대각선(y=x, y=-x+1) 간의 정규화된 최소 거리.
  /// 대각선 y=x: |dy - dx| / sqrt(2)
  /// 대각선 y=-x+1: |dx + dy - 1| / sqrt(2)
  double _distanceToDiagonal(Offset p) {
    final d1 = (p.dy - p.dx).abs() / math.sqrt2;
    final d2 = (p.dx + p.dy - 1).abs() / math.sqrt2;
    return math.min(d1, d2);
  }

  @override
  double scoreAlignment(Offset subjectCenter, {Size? subjectSize}) {
    final dist = _distanceToDiagonal(subjectCenter);
    final clamped = dist.clamp(0.0, _maxDistance);
    return 1.0 - clamped / _maxDistance;
  }

  @override
  String guidance(Offset subjectCenter) {
    final dist = _distanceToDiagonal(subjectCenter);
    if (dist < 0.05) {
      return '좋아요. 대각선 위에 잘 맞았어요.';
    }
    // 어느 대각선에 더 가까운지 판단해 방향 안내
    final d1 = (subjectCenter.dy - subjectCenter.dx).abs();
    final d2 = (subjectCenter.dx + subjectCenter.dy - 1).abs();
    final nearFirst = d1 < d2;
    if (nearFirst) {
      // y=x 대각선. dy < dx면 아래, dy > dx면 위로 조정해야 가까워짐.
      return subjectCenter.dy < subjectCenter.dx
          ? '대각선(↘) 쪽으로 아래로 조금'
          : '대각선(↘) 쪽으로 위로 조금';
    }
    return subjectCenter.dx + subjectCenter.dy < 1
        ? '대각선(↗) 쪽으로 아래로 조금'
        : '대각선(↗) 쪽으로 위로 조금';
  }
}
