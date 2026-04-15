import 'package:flutter/material.dart';

import '../composition_rule.dart';

/// 격자 없음. paintOverlay는 no-op, score는 항상 중립값 1.0.
class NoneRule extends CompositionRule {
  const NoneRule();

  @override
  CompositionRuleType get type => CompositionRuleType.none;

  @override
  String get label => '없음';

  @override
  IconData get icon => Icons.grid_off_outlined;

  @override
  void paintOverlay(
    Canvas canvas,
    Rect bounds, {
    required Color color,
    double strokeWidth = 1.0,
  }) {
    // no-op
  }

  @override
  double scoreAlignment(Offset subjectCenter, {Size? subjectSize}) => 1.0;

  @override
  String guidance(Offset subjectCenter) => '';
}
