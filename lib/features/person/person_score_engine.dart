import 'dart:math' as math;

import 'package:flutter/material.dart';

class PersonScoreEngine {
  double calculate({
    required Offset subjectPosition,
    required Offset targetPosition,
    required Size screenSize,
    Rect? subjectBox,
    required bool isPerfect,
  }) {
    final distance = (subjectPosition - targetPosition).distance;
    final maxDistance = screenSize.width * 0.45;
    final alignmentScore = (1 - (distance / maxDistance).clamp(0.0, 1.0)) * 70;

    double sizeScore = 0;
    double headroomScore = 0;

    if (subjectBox != null) {
      final areaRatio =
          (subjectBox.width * subjectBox.height) / (screenSize.width * screenSize.height);
      sizeScore = (1 - ((areaRatio - 0.22).abs() / 0.22).clamp(0.0, 1.0)) * 15;

      final headroomRatio = subjectBox.top / screenSize.height;
      headroomScore =
          (1 - ((headroomRatio - 0.10).abs() / 0.10).clamp(0.0, 1.0)) * 15;
    }

    final perfectBonus = isPerfect ? 8.0 : 0.0;
    return math.min(100, alignmentScore + sizeScore + headroomScore + perfectBonus);
  }
}
