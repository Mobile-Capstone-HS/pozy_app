import 'package:flutter/material.dart';

import '../../../composition/composition_rule.dart';

/// 현재 선택된 [CompositionRule]의 격자/가이드를 카메라 프리뷰 전체에 그리는 페인터.
///
/// Phase 1에서 쓰던 `ThirdsGridPainter`의 대체. 규칙이 바뀌면 rule 인스턴스만
/// 교체해 다시 주입한다.
class CompositionGridPainter extends CustomPainter {
  final CompositionRule rule;
  final Color color;
  final double strokeWidth;

  const CompositionGridPainter({
    required this.rule,
    this.color = const Color(0x33FFFFFF),
    this.strokeWidth = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    rule.paintOverlay(
      canvas,
      bounds,
      color: color,
      strokeWidth: strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant CompositionGridPainter old) {
    return old.rule.type != rule.type ||
        old.color != color ||
        old.strokeWidth != strokeWidth;
  }
}
