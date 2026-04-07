/// 인물 모드 코칭 규칙 엔진 v2.1
///
/// 상황 분류 → 조명 코칭 → 구도 코칭 → 포즈 코칭 → 칭찬
/// 5클래스 조명, 6종 샷 타입, 상황별 규칙 적용
library;

import 'portrait_scene_state.dart';

class PortraitCoachEngine {
  static const double _minConf = 0.5;

  CoachingResult evaluate(PortraitSceneState s) {
    // ════════════════════════════════════════════════
    // P0: 감지 실패
    // ════════════════════════════════════════════════

    if (s.personCount == 0) {
      return const CoachingResult(
        message: '사람이 보이지 않아요',
        priority: CoachingPriority.critical,
        confidence: 1.0,
      );
    }

    if (!s.hasNose && !s.hasEyes && !s.hasShoulders) {
      return const CoachingResult(
        message: '얼굴이나 상체를 더 보여주세요',
        priority: CoachingPriority.critical,
        confidence: 0.95,
      );
    }

    if (s.visibleKeypointCount < 3) {
      return const CoachingResult(
        message: '조금 더 뒤로 가주세요',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    if (s.personCount >= 3) {
      return const CoachingResult(
        message: '인물을 한두 명으로 정리해보세요',
        priority: CoachingPriority.critical,
        confidence: 0.92,
      );
    }

    // ════════════════════════════════════════════════
    // P1: 치명적 문제
    // ════════════════════════════════════════════════

    if (s.areEyesClosed) {
      return const CoachingResult(
        message: '눈을 감고 계세요',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    // 강한 역광 (클로즈업/상반신)
    if (s.lightingCondition == LightingCondition.back &&
        s.lightingConfidence > 0.8 &&
        s.personBboxRatio >= 0.4) {
      return const CoachingResult(
        message: '강한 역광이에요, 방향을 바꿔보세요',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    // ════════════════════════════════════════════════
    // P2: 조명 코칭
    // ════════════════════════════════════════════════

    final lightResult = _evaluateLighting(s);
    if (lightResult != null) return lightResult;

    // ════════════════════════════════════════════════
    // P3: 구도 코칭 (샷 타입별)
    // ════════════════════════════════════════════════

    final compResult = _evaluateComposition(s);
    if (compResult != null) return compResult;

    // ════════════════════════════════════════════════
    // P4: 포즈 코칭
    // ════════════════════════════════════════════════

    final poseResult = _evaluatePose(s);
    if (poseResult != null) return poseResult;

    // ════════════════════════════════════════════════
    // P5: 얼굴 세부 조정
    // ════════════════════════════════════════════════

    final faceResult = _evaluateFaceDirection(s);
    if (faceResult != null) return faceResult;

    // ════════════════════════════════════════════════
    // P6: 모든 규칙 통과 — 칭찬
    // ════════════════════════════════════════════════

    if (!s.hasEyes || !s.hasShoulders) {
      return const CoachingResult(
        message: '상체를 조금 더 보여주세요',
        priority: CoachingPriority.composition,
        confidence: 0.7,
      );
    }

    return CoachingResult(
      message: _perfectMessage(s),
      priority: CoachingPriority.perfect,
      confidence: 1.0,
    );
  }

  // ─── 조명 평가 ────────────────────────────────────

  CoachingResult? _evaluateLighting(PortraitSceneState s) {
    if (s.lightingConfidence < 0.5) return null;
    final lc = s.lightingCondition;

    // 사광(short) → 좋은 빛, 코칭 스킵
    if (lc == LightingCondition.short) return null;

    // 순광 → 밋밋함 경고
    if (lc == LightingCondition.normal && s.lightingConfidence > 0.6) {
      return const CoachingResult(
        message: '빛이 정면이에요, 살짝 비스듬하게 서보세요',
        priority: CoachingPriority.composition,
        confidence: 0.7,
      );
    }

    // 측광 → yaw에 따라 분기
    if (lc == LightingCondition.side) {
      if (s.faceYaw != null) {
        final absYaw = s.faceYaw!.abs();
        if (absYaw >= 15 && absYaw <= 30) {
          // 렘브란트 조명 — 칭찬, 코칭 스킵
          return null;
        }
        if (absYaw < 10) {
          return const CoachingResult(
            message: '얼굴을 빛 쪽으로 살짝 돌려보세요',
            priority: CoachingPriority.refinement,
            confidence: 0.65,
          );
        }
        if (absYaw > 30) {
          return const CoachingResult(
            message: '그림자가 강해요, 빛 쪽으로 돌려보세요',
            priority: CoachingPriority.composition,
            confidence: 0.7,
          );
        }
      }
    }

    // 역사광 → 인물 크기에 따라
    if (lc == LightingCondition.rim) {
      if (s.personBboxRatio >= 0.4) {
        return const CoachingResult(
          message: '윤곽 빛이 강해요, 빛 쪽으로 살짝 돌려보세요',
          priority: CoachingPriority.composition,
          confidence: 0.65,
        );
      }
      // 환경 포트레이트에서는 OK
      return null;
    }

    // 역광 → 인물 크기에 따라
    if (lc == LightingCondition.back) {
      if (s.personBboxRatio < 0.4) {
        // 환경 포트레이트 — 실루엣 제안
        return const CoachingResult(
          message: '실루엣 샷을 노려보세요! 🌅',
          priority: CoachingPriority.refinement,
          confidence: 0.7,
        );
      }
      // confidence 0.6~0.8 (약한 역광)
      return const CoachingResult(
        message: '역광이에요, 방향을 바꾸거나 림라이트를 활용해보세요',
        priority: CoachingPriority.composition,
        confidence: 0.75,
      );
    }

    return null;
  }

  // ─── 구도 평가 (샷 타입별) ────────────────────────

  CoachingResult? _evaluateComposition(PortraitSceneState s) {
    // 관절 크로핑 (익스트림 클로즈업 제외)
    if (s.isJointCropped &&
        s.shotType != ShotType.extremeCloseUp) {
      return const CoachingResult(
        message: '관절이 잘리고 있어요, 조금 조정해주세요',
        priority: CoachingPriority.composition,
        confidence: 0.9,
      );
    }

    // 눈 위치 삼분할 (샷 타입별 기준 다름)
    if (s.eyeMidpoint != null && s.eyeConfidence > _minConf) {
      final eyeY = s.eyeMidpoint!.dy;
      final result = _checkEyePosition(eyeY, s.shotType);
      if (result != null) return result;
    }

    // 헤드룸 (샷 타입별 기준 다름)
    if (s.hasPose || s.hasNose) {
      final result = _checkHeadroom(s.headroomRatio, s.shotType);
      if (result != null) return result;
    }

    // 풋스페이스 (전신만)
    if (s.shotType == ShotType.fullBody && s.footSpaceRatio < 0.03) {
      return const CoachingResult(
        message: '발 아래 공간을 남겨주세요',
        priority: CoachingPriority.composition,
        confidence: 0.8,
      );
    }

    // 전신/환경: 인물이 정중앙에 있음
    if ((s.shotType == ShotType.fullBody ||
         s.shotType == ShotType.environmental) &&
        s.personCenterX > 0.42 && s.personCenterX < 0.58) {
      return const CoachingResult(
        message: '인물을 좌/우로 살짝 이동해보세요',
        priority: CoachingPriority.composition,
        confidence: 0.65,
      );
    }

    // 환경 포트레이트: 인물 비율 체크
    if (s.shotType == ShotType.environmental) {
      if (s.personBboxRatio > 0.5) {
        return const CoachingResult(
          message: '뒤로 물러서서 배경을 더 담아보세요',
          priority: CoachingPriority.composition,
          confidence: 0.7,
        );
      }
      if (s.personBboxRatio < 0.15) {
        return const CoachingResult(
          message: '인물에 좀 더 가까이 가보세요',
          priority: CoachingPriority.composition,
          confidence: 0.65,
        );
      }
    }

    if (s.hasFace &&
        (s.shotType == ShotType.closeUp || s.shotType == ShotType.upperBody)) {
      if (s.faceCenterX < 0.22 || s.faceCenterX > 0.78) {
        return const CoachingResult(
          message: '얼굴이 너무 옆으로 치우쳤어요',
          priority: CoachingPriority.composition,
          confidence: 0.72,
        );
      }
      if (s.faceBoxRatio > 0.22 && s.shotType == ShotType.closeUp) {
        return const CoachingResult(
          message: '얼굴이 너무 크게 잡혀 있어요',
          priority: CoachingPriority.composition,
          confidence: 0.7,
        );
      }
    }

    return null;
  }

  CoachingResult? _checkEyePosition(double eyeY, ShotType shot) {
    double targetY;
    double tolerance;

    switch (shot) {
      case ShotType.extremeCloseUp:
        targetY = 0.45; // 중앙 근처
        tolerance = 0.10;
      case ShotType.closeUp:
        targetY = 0.33; // 상단 1/3
        tolerance = 0.08;
      case ShotType.upperBody:
        targetY = 0.32;
        tolerance = 0.08;
      case ShotType.kneeShot:
        targetY = 0.28;
        tolerance = 0.08;
      case ShotType.fullBody:
        return null; // 전신은 눈 위치보다 전체 배치가 중요
      case ShotType.environmental:
        return null;
      default:
        targetY = 0.33;
        tolerance = 0.12;
    }

    final deviation = (eyeY - targetY).abs();
    if (deviation > tolerance) {
      final message = eyeY < targetY
          ? '카메라를 살짝 내려보세요'
          : '카메라를 살짝 올려보세요';
      return CoachingResult(
        message: message,
        priority: CoachingPriority.composition,
        confidence: 0.8,
      );
    }
    return null;
  }

  CoachingResult? _checkHeadroom(double headroom, ShotType shot) {
    double minH, maxH;

    switch (shot) {
      case ShotType.extremeCloseUp:
        minH = 0.0;
        maxH = 0.08;
      case ShotType.closeUp:
        minH = 0.05;
        maxH = 0.15;
      case ShotType.upperBody:
        minH = 0.08;
        maxH = 0.18;
      case ShotType.kneeShot:
        minH = 0.05;
        maxH = 0.12;
      case ShotType.fullBody:
        minH = 0.05;
        maxH = 0.12;
      default:
        return null;
    }

    if (headroom < minH) {
      return const CoachingResult(
        message: '머리 위 공간이 부족해요',
        priority: CoachingPriority.composition,
        confidence: 0.85,
      );
    }
    if (headroom > maxH) {
      return const CoachingResult(
        message: '좀 더 가까이 가보세요',
        priority: CoachingPriority.composition,
        confidence: 0.75,
      );
    }
    return null;
  }

  // ─── 포즈 평가 ────────────────────────────────────

  CoachingResult? _evaluatePose(PortraitSceneState s) {
    // 어깨 수평 (클로즈업/상반신에서만)
    if (s.shoulderAngleDeg != null &&
        s.shoulderConfidence > _minConf &&
        (s.shotType == ShotType.closeUp ||
         s.shotType == ShotType.upperBody)) {
      if (s.shoulderAngleDeg!.abs() < 3) {
        return const CoachingResult(
          message: '어깨를 살짝 틀어보세요',
          priority: CoachingPriority.pose,
          confidence: 0.75,
        );
      }
      if (s.shoulderAngleDeg!.abs() > 25) {
        return const CoachingResult(
          message: '어깨가 너무 기울었어요',
          priority: CoachingPriority.pose,
          confidence: 0.7,
        );
      }
    }

    // 양팔 다 붙음 (한 팔만 붙은 건 자연스러움)
    if (s.leftArmBodyGap != null &&
        s.rightArmBodyGap != null &&
        s.elbowConfidence > _minConf) {
      if (s.leftArmBodyGap! < 0.02 && s.rightArmBodyGap! < 0.02) {
        return const CoachingResult(
          message: '팔을 몸에서 살짝 떼어보세요',
          priority: CoachingPriority.pose,
          confidence: 0.7,
        );
      }
    }

    return null;
  }

  // ─── 얼굴 방향 세부 조정 ──────────────────────────

  CoachingResult? _evaluateFaceDirection(PortraitSceneState s) {
    if (!s.hasFace) return null;

    // 턱 올라감
    if (s.facePitch != null && s.facePitch! > 15) {
      return const CoachingResult(
        message: '턱을 살짝 당겨주세요',
        priority: CoachingPriority.refinement,
        confidence: 0.65,
      );
    }

    // 턱 내려감
    if (s.facePitch != null && s.facePitch! < -15) {
      return const CoachingResult(
        message: '턱을 살짝 올려주세요',
        priority: CoachingPriority.refinement,
        confidence: 0.6,
      );
    }

    // 고개 기울어짐 (20도 이상만)
    if (s.faceRoll != null && s.faceRoll!.abs() > 20) {
      return const CoachingResult(
        message: '고개가 많이 기울었어요',
        priority: CoachingPriority.refinement,
        confidence: 0.7,
      );
    }

    // 완전 정면 — 클로즈업은 OK, 나머지는 부드러운 제안
    if (s.faceYaw != null && s.faceYaw!.abs() < 5) {
      if (s.shotType != ShotType.extremeCloseUp &&
          s.shotType != ShotType.closeUp) {
        return const CoachingResult(
          message: '고개를 살짝 돌리면 더 자연스러워요',
          priority: CoachingPriority.refinement,
          confidence: 0.55,
        );
      }
    }

    if (s.smileProbability != null &&
        !s.isSmiling &&
        s.shotType != ShotType.environmental &&
        s.faceYaw != null &&
        s.faceYaw!.abs() < 20) {
      return const CoachingResult(
        message: '표정을 조금 더 부드럽게 풀어보세요',
        priority: CoachingPriority.refinement,
        confidence: 0.52,
      );
    }

    return null;
  }

  // ─── Perfect 메시지 (상황별) ──────────────────────

  String _perfectMessage(PortraitSceneState s) {
    // 사광 + 통과
    if (s.lightingCondition == LightingCondition.short &&
        s.lightingConfidence > 0.5) {
      return '완벽한 빛과 구도예요! 📸✨';
    }

    // 측광 + 렘브란트 각도
    if (s.lightingCondition == LightingCondition.side &&
        s.faceYaw != null &&
        s.faceYaw!.abs() >= 15 && s.faceYaw!.abs() <= 30) {
      return '렘브란트 조명에 멋진 구도예요! 📸✨';
    }

    switch (s.shotType) {
      case ShotType.extremeCloseUp:
        return '인상적인 클로즈업이에요! 📸';
      case ShotType.fullBody:
        return '멋진 전신 샷이에요! 📸';
      case ShotType.environmental:
        return '멋진 환경 포트레이트예요! 📸';
      default:
        return '좋은 구도예요! 📸';
    }
  }
}
