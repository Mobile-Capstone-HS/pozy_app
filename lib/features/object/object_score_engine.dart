import 'dart:math' as math;

import 'package:flutter/material.dart';

class ObjectScoreEngine {
  double calculate({
    required Offset virtualSubjectPosition,
    required Offset targetPosition,
    required Size screenSize,
    required bool isPerfect,
  }) {
    final distance = (virtualSubjectPosition - targetPosition).distance;
    final maxDistance = screenSize.width * 0.45;
    final alignmentScore = (1 - (distance / maxDistance).clamp(0.0, 1.0)) * 80;

    final marginX = math.min(
      virtualSubjectPosition.dx,
      screenSize.width - virtualSubjectPosition.dx,
    );
    final marginY = math.min(
      virtualSubjectPosition.dy,
      screenSize.height - virtualSubjectPosition.dy,
    );
    final marginScore = ((marginX + marginY) / (screenSize.width * 0.35))
            .clamp(0.0, 1.0) *
        12;

    final perfectBonus = isPerfect ? 8.0 : 0.0;
    return math.min(100, alignmentScore + marginScore + perfectBonus);
  }
}
