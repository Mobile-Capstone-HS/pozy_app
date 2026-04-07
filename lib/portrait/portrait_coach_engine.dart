library;

import 'portrait_scene_state.dart';

class PortraitCoachEngine {
  static const double _minConf = 0.5;

  CoachingResult evaluate(PortraitSceneState s) {
    if (s.personCount == 0) {
      return const CoachingResult(
        message: '인물이 보이지 않아요.',
        priority: CoachingPriority.critical,
        confidence: 1.0,
      );
    }

    if (!s.hasNose && !s.hasEyes && !s.hasShoulders) {
      return const CoachingResult(
        message: '얼굴이나 상체를 더 보여주세요.',
        priority: CoachingPriority.critical,
        confidence: 0.95,
      );
    }

    if (s.visibleKeypointCount < 3) {
      return const CoachingResult(
        message: '조금 더 뒤로 가주세요.',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    if (s.personCount >= 3) {
      return const CoachingResult(
        message: '인원을 두 명 이하로 정리해보세요.',
        priority: CoachingPriority.critical,
        confidence: 0.92,
      );
    }

    if (s.areEyesClosed) {
      return const CoachingResult(
        message: '눈을 감고 계세요.',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    if (s.isOneEyeClosed) {
      return const CoachingResult(
        message: '한쪽 눈이 감겨 있어요.',
        priority: CoachingPriority.composition,
        confidence: 0.72,
      );
    }

    if (s.lightingCondition == LightingCondition.back &&
        s.lightingConfidence > 0.8 &&
        s.personBboxRatio >= 0.4) {
      return const CoachingResult(
        message: '강한 역광이라 방향을 바꿔보세요.',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    final lighting = _evaluateLighting(s);
    if (lighting != null) return lighting;

    final composition = _evaluateComposition(s);
    if (composition != null) return composition;

    final pose = _evaluatePose(s);
    if (pose != null) return pose;

    final face = _evaluateFaceDirection(s);
    if (face != null) return face;

    if (!s.hasEyes || !s.hasShoulders) {
      return const CoachingResult(
        message: '상체를 조금 더 보여주세요.',
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

  CoachingResult? _evaluateLighting(PortraitSceneState s) {
    if (s.lightingConfidence < 0.5) return null;

    switch (s.lightingCondition) {
      case LightingCondition.short:
        return null;
      case LightingCondition.normal:
        if (s.lightingConfidence > 0.6) {
          return const CoachingResult(
            message: '빛이 정면이라 조금 밋밋해 보여요.',
            priority: CoachingPriority.composition,
            confidence: 0.7,
          );
        }
        return null;
      case LightingCondition.side:
        final yaw = s.faceYaw?.abs();
        if (yaw == null) return null;
        if (yaw >= 15 && yaw <= 30) return null;
        if (yaw < 10) {
          return const CoachingResult(
            message: '얼굴을 빛 쪽으로 조금 돌려보세요.',
            priority: CoachingPriority.refinement,
            confidence: 0.65,
          );
        }
        if (yaw > 30) {
          return const CoachingResult(
            message: '그림자가 강해서 빛 쪽으로 돌려보세요.',
            priority: CoachingPriority.composition,
            confidence: 0.7,
          );
        }
        return null;
      case LightingCondition.rim:
        if (s.personBboxRatio >= 0.4) {
          return const CoachingResult(
            message: '윤곽 빛이 강해서 얼굴을 빛 쪽으로 조금 돌려보세요.',
            priority: CoachingPriority.composition,
            confidence: 0.65,
          );
        }
        return null;
      case LightingCondition.back:
        if (s.personBboxRatio < 0.4) {
          return const CoachingResult(
            message: '실루엣을 살려보세요.',
            priority: CoachingPriority.refinement,
            confidence: 0.7,
          );
        }
        if (s.lightingConfidence >= 0.6) {
          return const CoachingResult(
            message: '역광이라 방향을 바꾸거나 림라이트처럼 활용해보세요.',
            priority: CoachingPriority.composition,
            confidence: 0.75,
          );
        }
        return const CoachingResult(
          message: '빛을 정면으로 받도록 방향을 조금 조정해보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.62,
        );
      case LightingCondition.unknown:
        return null;
    }
  }

  CoachingResult? _evaluateComposition(PortraitSceneState s) {
    if (s.isJointCropped && s.shotType != ShotType.extremeCloseUp) {
      return const CoachingResult(
        message: '관절이 잘리지 않게 조금 조정해주세요.',
        priority: CoachingPriority.composition,
        confidence: 0.9,
      );
    }

    if (s.eyeMidpoint != null && s.eyeConfidence > _minConf) {
      final result = _checkEyePosition(s.eyeMidpoint!.dy, s.shotType);
      if (result != null) return result;
    }

    if (s.hasPose || s.hasNose) {
      final result = _checkHeadroom(s.headroomRatio, s.shotType);
      if (result != null) return result;
    }

    if (s.shotType == ShotType.fullBody) {
      if (s.footSpaceRatio < 0.03) {
        return const CoachingResult(
          message: '발 아래 공간을 더 넣어주세요.',
          priority: CoachingPriority.composition,
          confidence: 0.8,
        );
      }
      if (s.footSpaceRatio > 0.12) {
        return const CoachingResult(
          message: '인물에 조금 더 가까이 가보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.68,
        );
      }
    }

    if ((s.shotType == ShotType.fullBody ||
            s.shotType == ShotType.environmental) &&
        s.personCenterX > 0.42 &&
        s.personCenterX < 0.58) {
      return const CoachingResult(
        message: '인물을 좌우 한쪽으로 조금 이동해보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.65,
      );
    }

    if (s.shotType == ShotType.environmental) {
      if (s.personBboxRatio > 0.5) {
        return const CoachingResult(
          message: '조금 물러서서 배경을 더 담아보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.7,
        );
      }
      if (s.personBboxRatio < 0.15) {
        return const CoachingResult(
          message: '인물에 조금 더 가까이 가보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.65,
        );
      }
    }

    if (s.hasFace &&
        (s.shotType == ShotType.closeUp || s.shotType == ShotType.upperBody)) {
      if (s.faceCenterX < 0.22 || s.faceCenterX > 0.78) {
        return const CoachingResult(
          message: '얼굴이 너무 한쪽으로 치우쳐 있어요.',
          priority: CoachingPriority.composition,
          confidence: 0.72,
        );
      }
      if (s.faceBoxRatio > 0.22 && s.shotType == ShotType.closeUp) {
        return const CoachingResult(
          message: '얼굴이 너무 크게 차고 있어요.',
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
        targetY = 0.45;
        tolerance = 0.10;
      case ShotType.closeUp:
        targetY = 0.33;
        tolerance = 0.08;
      case ShotType.upperBody:
        targetY = 0.32;
        tolerance = 0.07;
      case ShotType.kneeShot:
        targetY = 0.28;
        tolerance = 0.07;
      case ShotType.fullBody:
      case ShotType.environmental:
      case ShotType.unknown:
        return null;
    }

    if ((eyeY - targetY).abs() <= tolerance) return null;

    return CoachingResult(
      message: eyeY < targetY ? '카메라를 조금 내려보세요.' : '카메라를 조금 올려보세요.',
      priority: CoachingPriority.composition,
      confidence: 0.8,
    );
  }

  CoachingResult? _checkHeadroom(double headroom, ShotType shot) {
    double minH;
    double maxH;

    switch (shot) {
      case ShotType.extremeCloseUp:
        minH = 0.0;
        maxH = 0.08;
      case ShotType.closeUp:
        minH = 0.05;
        maxH = 0.12;
      case ShotType.upperBody:
        minH = 0.08;
        maxH = 0.15;
      case ShotType.kneeShot:
        minH = 0.05;
        maxH = 0.10;
      case ShotType.fullBody:
        minH = 0.05;
        maxH = 0.10;
      case ShotType.environmental:
      case ShotType.unknown:
        return null;
    }

    if (headroom < minH) {
      return const CoachingResult(
        message: '머리 위 공간이 부족해요.',
        priority: CoachingPriority.composition,
        confidence: 0.85,
      );
    }
    if (headroom > maxH) {
      return const CoachingResult(
        message: '조금 더 가까이 가보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.75,
      );
    }
    return null;
  }

  CoachingResult? _evaluatePose(PortraitSceneState s) {
    if (s.shoulderAngleDeg != null &&
        s.shoulderConfidence > _minConf &&
        (s.shotType == ShotType.closeUp || s.shotType == ShotType.upperBody)) {
      if (s.shoulderAngleDeg!.abs() < 2) {
        return const CoachingResult(
          message: '어깨를 조금 틀어보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.7,
        );
      }
      if (s.shoulderAngleDeg!.abs() > 25) {
        return const CoachingResult(
          message: '어깨 각도가 너무 커요.',
          priority: CoachingPriority.pose,
          confidence: 0.7,
        );
      }
    }

    if (s.leftArmBodyGap != null &&
        s.rightArmBodyGap != null &&
        s.elbowConfidence > _minConf &&
        s.leftArmBodyGap! < 0.02 &&
        s.rightArmBodyGap! < 0.02) {
      return const CoachingResult(
        message: '팔을 몸에서 조금 떨어뜨려보세요.',
        priority: CoachingPriority.pose,
        confidence: 0.7,
      );
    }

    return null;
  }

  CoachingResult? _evaluateFaceDirection(PortraitSceneState s) {
    if (!s.hasFace) return null;

    if (s.facePitch != null && s.facePitch! > 20) {
      return const CoachingResult(
        message: '턱이 많이 올라가 있어요. 조금 내려주세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.72,
      );
    }

    if (s.facePitch != null && s.facePitch! > 10) {
      return const CoachingResult(
        message: '턱을 조금 내려주세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.65,
      );
    }

    if (s.facePitch != null && s.facePitch! < -15) {
      return const CoachingResult(
        message: '턱을 조금 올려주세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.6,
      );
    }

    if (s.faceRoll != null && s.faceRoll!.abs() > 20) {
      return const CoachingResult(
        message: '고개가 많이 기울어 있어요.',
        priority: CoachingPriority.refinement,
        confidence: 0.7,
      );
    }

    return null;
  }

  String _perfectMessage(PortraitSceneState s) {
    if (s.lightingCondition == LightingCondition.short &&
        s.lightingConfidence > 0.5) {
      return '예쁜 빛과 구도예요!';
    }

    if (s.lightingCondition == LightingCondition.side &&
        s.faceYaw != null &&
        s.faceYaw!.abs() >= 15 &&
        s.faceYaw!.abs() <= 30) {
      return '사이드 조명이 멋진 구도예요!';
    }

    switch (s.shotType) {
      case ShotType.extremeCloseUp:
        return '인상적인 클로즈업이에요!';
      case ShotType.fullBody:
        return '멋진 전신 구도예요!';
      case ShotType.environmental:
        return '멋진 환경 인물 사진이에요!';
      case ShotType.closeUp:
      case ShotType.upperBody:
      case ShotType.kneeShot:
      case ShotType.unknown:
        return '좋은 구도예요!';
    }
  }
}
