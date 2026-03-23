import 'dart:math' as math;

import 'package:flutter/material.dart';

class FoodScoreEngine {
  double calculate({
    required Offset virtualSubjectPosition,
    required Offset targetPosition,
    required Size screenSize,
    required bool isPerfect,
  }) {
    final distance = (virtualSubjectPosition - targetPosition).distance;
    final maxDistance = screenSize.width * 0.45;
    final alignmentScore = (1 - (distance / maxDistance).clamp(0.0, 1.0)) * 75;

    final centerRatioX = (virtualSubjectPosition.dx / screenSize.width - 0.5).abs();
    final centerRatioY = (virtualSubjectPosition.dy / screenSize.height - 0.5).abs();
    final balancePenalty = ((centerRatioX + centerRatioY) * 25).clamp(0.0, 15.0);
    final balanceScore = 15 - balancePenalty;

    final perfectBonus = isPerfect ? 10.0 : 0.0;
    return math.min(100, alignmentScore + balanceScore + perfectBonus);
  }
}
