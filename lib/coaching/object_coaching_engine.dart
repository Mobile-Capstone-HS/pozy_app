import 'package:flutter/material.dart';

import 'coaching_result.dart';

/// 피사체 박스와 기울기를 기준으로 즉시 코칭을 만드는 경량 엔진.
///
/// NIMA/VLM이 저빈도 품질 코칭을 맡고, 이 엔진은 프레임 단위로
/// 거리감과 수평 문제를 먼저 잡아준다.
class ObjectCoachingEngine {
  static const double _minAreaWarning = 0.04;
  static const double _maxAreaWarning = 0.60;

  static const double _tiltCautionThreshold = 0.35; // ≈ 2°
  static const double _tiltWarningThreshold = 0.85; // ≈ 5°

  CoachingResult? evaluateTiltOnly({double tiltX = 0.0}) =>
      _tiltGuidance(tiltX);

  CoachingResult? evaluateZoomAndTilt(
    Rect? normalizedBox, {
    double tiltX = 0.0,
  }) {
    if (normalizedBox == null) {
      return null;
    }

    final area = normalizedBox.width * normalizedBox.height;
    if (area < _minAreaWarning) {
      return const CoachingResult(
        guidance: '조금 더 가까이 다가가볼까요?',
        level: CoachingLevel.warning,
        subGuidance: '화면 속 대상이 너무 작아요',
      );
    }

    if (area > _maxAreaWarning) {
      return const CoachingResult(
        guidance: '한 발 뒤로 물러나볼까요?',
        level: CoachingLevel.warning,
        subGuidance: '너무 가까워서 전체가 잘리고 있어요',
      );
    }

    return _tiltGuidance(tiltX);
  }

  CoachingResult? _tiltGuidance(double tiltX) {
    final absTilt = tiltX.abs();
    if (absTilt < _tiltCautionThreshold) {
      return null;
    }

    final direction = tiltX > 0 ? '오른쪽' : '왼쪽';
    if (absTilt >= _tiltWarningThreshold) {
      return CoachingResult(
        guidance: '카메라를 수평으로 맞춰주세요',
        level: CoachingLevel.warning,
        subGuidance: '$direction으로 많이 기울어져 있어요',
      );
    }

    return CoachingResult(
      guidance: '카메라를 조금 더 수평으로 맞춰주세요',
      level: CoachingLevel.caution,
      subGuidance: '$direction으로 살짝 기울어져 있어요',
    );
  }
}
