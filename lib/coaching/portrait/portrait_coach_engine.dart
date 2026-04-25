library;

import 'package:flutter/material.dart';

import '../../composition/composition_rule.dart';
import '../../composition/composition_rule_registry.dart';
import 'portrait_scene_state.dart';

class PortraitCoachEngine {
  static const double _minConf = 0.5;
  static const bool _enableShoulderAngleCoaching = false;
  static const bool _enableSmileCoaching = false;

  /// 사용자가 선택한 구도 규칙. none이면 기존 하드코딩 3분할 휴리스틱.
  CompositionRule _rule =
      CompositionRuleRegistry.of(CompositionRuleType.none);

  void setRule(CompositionRule rule) {
    _rule = rule;
  }

  CoachingResult evaluate(PortraitSceneState s) {
    if (s.personCount == 0) {
      return const CoachingResult(
        message: '인물이 보이지 않아요.',
        priority: CoachingPriority.critical,
        confidence: 1.0,
      );
    }

    // ─── 그룹샷 코칭 (2명 이상) ──────────────────────────
    // 그룹샷은 메인 인물 키포인트 체크보다 우선 판정합니다.
    // 3명 이상도 인원 제한 없이 실질적인 피드백을 제공합니다.
    if (s.intent == PortraitIntent.group && !s.isGroupShot) {
      return const CoachingResult(
        message: '다중 인물 모드예요. 함께 화면에 들어오면 그룹 기준으로 볼게요.',
        priority: CoachingPriority.composition,
        confidence: 0.65,
      );
    }

    if (s.isGroupShot) {
      return _evaluateGroupShot(s);
    }

    if (!s.hasNose && !s.hasEyes && !s.hasShoulders) {
      return const CoachingResult(
        message: '인물이 조금 더 보이게 화면을 맞춰주세요.',
        priority: CoachingPriority.critical,
        confidence: 0.95,
      );
    }

    if (s.visibleKeypointCount < 3) {
      return const CoachingResult(
        message: '한 걸음만 뒤로 가면 인물이 더 안정적으로 잡혀요.',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    if (s.areEyesClosed) {
      return const CoachingResult(
        message: '눈 감김이 보여요. 한 번 더 맞춰볼게요.',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    if (s.isOneEyeClosed) {
      return const CoachingResult(
        message: '한쪽 눈이 작게 잡혔어요. 잠깐만 다시 맞춰보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.72,
      );
    }

    if (s.lightingCondition == LightingCondition.back &&
        s.lightingConfidence > 0.8 &&
        s.personBboxRatio >= 0.4) {
      return const CoachingResult(
        message: '강한 역광이에요. 몸을 돌려 빛을 정면으로 받아보세요.',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    final lighting = _evaluateLighting(s);
    if (lighting != null) return lighting;

    if (_enableShoulderAngleCoaching) {
      final lightPose = _evaluateLightingPoseCombined(s);
      if (lightPose != null) return lightPose;
    }

    final composition = _evaluateComposition(s);
    if (composition != null) return composition;

    final pose = _evaluatePose(s);
    if (pose != null) return pose;

    final face = _evaluateFaceDirection(s);
    if (face != null) return face;

    if (!s.hasEyes || !s.hasShoulders) {
      return const CoachingResult(
        message: '상체가 조금 더 보이면 안내가 더 정확해져요.',
        priority: CoachingPriority.composition,
        confidence: 0.7,
      );
    }

    // ─── 카메라 안정성은 구도/조명/포즈보다 뒤에서 보조적으로 사용 ──────
    final stability = _evaluateStability(s);
    if (stability != null) return stability;

    // ─── 셀카 전용 미세 조정은 공통 인물 규칙 뒤에서 적용 ─────────────
    if (s.isFrontCamera) {
      final selfie = _evaluateSelfie(s);
      if (selfie != null) return selfie;
    }

    if (_enableSmileCoaching) {
      final expression = _evaluateExpression(s);
      if (expression != null) return expression;
    }

    return CoachingResult(
      message: s.isFrontCamera ? _selfiePerfectMessage(s) : _perfectMessage(s),
      priority: CoachingPriority.perfect,
      confidence: 1.0,
    );
  }

  // ─── 그룹샷 코칭 (2명 이상) ───────────────────────────
  CoachingResult _evaluateGroupShot(PortraitSceneState s) {
    // 그룹 모드는 개별 포즈보다 전체 프레이밍을 우선합니다.
    if (s.groupCroppedCount > 0) {
      final isMajority = s.groupCroppedCount >= (s.personCount / 2).ceil();
      return CoachingResult(
        message: isMajority
            ? '여러 분이 프레임에 걸려요. 조금 더 넓게 담아보세요.'
            : '가장자리 분이 살짝 걸려요. 조금만 넓게 담아보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.88,
      );
    }

    final minBboxRatio = s.personCount >= 4 ? 0.06
        : s.personCount >= 3 ? 0.08
        : 0.12;
    if (s.personBboxRatio < minBboxRatio) {
      return const CoachingResult(
        message: '인물이 조금 작게 보여요. 살짝 가까이 가보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.72,
      );
    }

    final maxBboxRatio = s.personCount >= 4 ? 0.86
        : s.personCount >= 3 ? 0.82
        : 0.76;
    if (s.personBboxRatio > maxBboxRatio) {
      return const CoachingResult(
        message: '그룹이 화면에 꽉 차요. 반 걸음만 뒤로 가보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.78,
      );
    }

    if (s.headroomRatio < 0.04) {
      return const CoachingResult(
        message: '머리 위가 살짝 좁아요. 폰을 조금 아래로 향해보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.80,
      );
    }

    if (s.footSpaceRatio < 0.035) {
      return const CoachingResult(
        message: '아래쪽 여유가 좁아요. 발끝까지 조금 더 담아보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.76,
      );
    }

    final groupOffCenter = (s.personCenterX - 0.5).abs();
    if (groupOffCenter > 0.15) {
      final direction = s.personCenterX < 0.5 ? '오른쪽' : '왼쪽';
      return CoachingResult(
        message: '그룹이 한쪽으로 치우쳐요. 카메라를 $direction으로 살짝 옮겨보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.78,
      );
    }

    if (s.personCount >= 3) {
      if (s.spacingUnevenness > 0.5) {
        return const CoachingResult(
          message: '사람 간격이 조금 달라요. 가운데로 살짝 모여보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.72,
          reason: '균등한 간격이 안정적인 단체 사진이에요',
        );
      }

      if (s.heightVariation > 0.15) {
        return const CoachingResult(
          message: '줄 높이가 조금 달라요. 키 큰 분이 살짝 뒤로 가면 균형이 좋아요.',
          priority: CoachingPriority.composition,
          confidence: 0.68,
        );
      }
    }

    if (s.personCount == 2 && s.secondPersonSizeRatio < 0.35) {
      return const CoachingResult(
        message: '두 분 거리 차이가 커요. 비슷한 위치에 서보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.82,
      );
    }

    // 얼굴/눈은 멀어질수록 불안정하므로 프레이밍 이후의 보조 안내로만 사용합니다.
    if (s.faceHiddenCount > 0) {
      return CoachingResult(
        message: s.faceHiddenCount == 1
            ? '얼굴이 가려진 분이 있어요. 얼굴만 보이게 살짝 조정해보세요.'
            : '${s.faceHiddenCount}명의 얼굴이 덜 보여요. 얼굴이 보이게 살짝 모여주세요.',
        priority: CoachingPriority.composition,
        confidence: 0.68,
      );
    }

    if (s.anyFaceEyesClosed || s.areEyesClosed) {
      return CoachingResult(
        message: s.closedFaceCount > 1
            ? '${s.closedFaceCount}명 눈감음 의심이 있어요.'
            : '눈감음 의심이 있어요.',
        priority: CoachingPriority.composition,
        confidence: 0.68,
      );
    }

    return CoachingResult(
      message: '${s.personCount}명 모두 프레임에 잘 들어왔어요!',
      priority: CoachingPriority.perfect,
      confidence: 0.85,
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
            message: '빛이 정면이에요. 몸을 살짝 비스듬히 틀어보세요.',
            priority: CoachingPriority.composition,
            confidence: 0.7,
          );
        }
        return null;
      case LightingCondition.side:
        final yaw = s.faceYaw?.abs();
        if (yaw == null) return null;
        if (yaw >= 15 && yaw <= 30) {
          return const CoachingResult(
            message: '사이드 조명이 얼굴에 입체감을 줘요!',
            priority: CoachingPriority.perfect,
            confidence: 0.8,
          );
        }
        if (yaw < 10) {
          return const CoachingResult(
            message: '얼굴을 빛 쪽으로 조금 돌려보세요.',
            priority: CoachingPriority.refinement,
            confidence: 0.65,
            reason: '렘브란트 조명 효과예요',
          );
        }
        if (yaw > 30) {
          return const CoachingResult(
            message: '그림자가 강해요. 얼굴을 빛 쪽으로 살짝 돌려보세요.',
            priority: CoachingPriority.composition,
            confidence: 0.7,
          );
        }
        return null;
      case LightingCondition.rim:
        if (s.personBboxRatio < 0.4) {
          return const CoachingResult(
            message: '윤곽이 살아나는 빛이에요!',
            priority: CoachingPriority.refinement,
            confidence: 0.65,
          );
        }
        if (s.personBboxRatio >= 0.4) {
          return const CoachingResult(
            message: '뒤에서 빛이 와요. 얼굴을 빛 쪽으로 돌려보세요.',
            priority: CoachingPriority.composition,
            confidence: 0.65,
          );
        }
        return null;
      case LightingCondition.back:
        if (s.personBboxRatio < 0.4) {
          return const CoachingResult(
            message: '실루엣 샷을 노려보세요!',
            priority: CoachingPriority.refinement,
            confidence: 0.7,
          );
        }
        if (s.lightingConfidence >= 0.6) {
          return const CoachingResult(
            message: '역광이에요. 돌아서거나 빛을 화면 밖으로 빼보세요.',
            priority: CoachingPriority.composition,
            confidence: 0.75,
          );
        }
        return const CoachingResult(
          message: '빛이 뒤에서 와요. 몸을 돌려 빛을 받아보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.62,
        );
      case LightingCondition.unknown:
        return null;
    }
  }

  CoachingResult? _evaluateComposition(PortraitSceneState s) {
    // ─── 1. 관절 커팅 감지 (인물사진 최우선 규칙) ──────────────
    // "관절에서 자르지 마라" — 가장자리 관절 + 프레임 하단 관절 모두 체크
    if (s.shotType != ShotType.extremeCloseUp) {
      // (a) 프레임 하단에서 관절이 잘리는 경우 (더 중요)
      final bottomResult = _checkBottomJointCut(s);
      if (bottomResult != null) return bottomResult;

      // (b) 프레임 가장자리에서 관절이 잘리는 경우
      if (s.croppedJoints.isNotEmpty) {
        final joint = s.croppedJoints.first;
        final msg = switch (joint) {
          'knee' => '무릎선에 걸려요. 허벅지 중간이나 종아리까지 담아보세요.',
          'ankle' => '발끝까지 담거나, 종아리 중간에서 맞춰보세요.',
          'wrist' => '손이 살짝 걸려요. 손 전체를 넣거나 과감히 빼보세요.',
          'elbow' => '팔꿈치가 프레임에 걸려요. 팔 중간에서 맞춰보세요.',
          _ => '관절선에 걸려요. 관절 사이 중간에서 맞추면 자연스러워요.',
        };
        final reason = switch (joint) {
          'knee' || 'ankle' => '관절에서 자르면 절단된 느낌이 나요',
          'wrist' => '반쯤 보이는 손은 어색해요',
          'elbow' => '관절 사이 중간이 자연스러워요',
          _ => null,
        };
        return CoachingResult(
          message: msg,
          priority: CoachingPriority.composition,
          confidence: 0.9,
          reason: reason,
        );
      }
    }

    // ─── 2. 전신 전용 구도 체크 ───────────────────────────────
    if (s.shotType == ShotType.fullBody) {
      final fullBodyResult = _checkFullBodyComposition(s);
      if (fullBodyResult != null) return fullBodyResult;
    }

    // ─── 3. 무릎샷 전용 구도 체크 ─────────────────────────────
    if (s.shotType == ShotType.kneeShot) {
      final kneeResult = _checkKneeShotComposition(s);
      if (kneeResult != null) return kneeResult;
    }

    if (s.lowerBodyTouchesBottom) {
      return const CoachingResult(
        message: '아래쪽이 잘릴 수 있어요. 발끝까지 담거나 허벅지 중간에서 맞춰보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.82,
        reason: '하체가 프레임 끝에 붙으면 잘린 느낌이 날 수 있어요',
      );
    }

    // ─── 4. 눈 위치 (삼분할 법칙) ─────────────────────────────
    if (s.eyeMidpoint != null && s.eyeConfidence > _minConf) {
      final result = _checkEyePosition(s.eyeMidpoint!.dy, s.shotType);
      if (result != null) return result;
    }

    // ─── 5. 헤드룸 ───────────────────────────────────────────
    if (s.hasPose || s.hasNose) {
      final result = _checkHeadroom(s.headroomRatio, s.shotType);
      if (result != null) return result;
    }

    // ─── 6. 전신 발 아래 공간 ─────────────────────────────────
    if (s.shotType == ShotType.fullBody) {
      if (s.footSpaceRatio < 0.05) {
        return const CoachingResult(
          message: '발 아래 공간을 더 넣어주세요.',
          priority: CoachingPriority.composition,
          confidence: 0.8,
        );
      }
      if (s.footSpaceRatio > 0.10) {
        return const CoachingResult(
          message: '인물이 조금 작게 보여요. 살짝 가까이 가보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.68,
        );
      }
    }

    // ─── 구도 규칙 정렬 (전신/환경) ─────────────────────────
    if (s.shotType == ShotType.fullBody ||
        s.intent == PortraitIntent.environmental) {
      final ruleResult = _checkRuleAlignment(s);
      if (ruleResult != null) return ruleResult;
    }

    // ─── 7. 리딩룸 (시선 방향 여백) ──────────────────────────
    if (s.faceYaw != null) {
      final needsLeadingRoom =
          s.shotType == ShotType.upperBody ||
          s.shotType == ShotType.waistShot ||
          s.shotType == ShotType.kneeShot;
      final yawThreshold = s.intent == PortraitIntent.environmental ? 5.0 : 10.0;
      final posThreshold = s.intent == PortraitIntent.environmental ? 0.55 : 0.6;
      final negThreshold = s.intent == PortraitIntent.environmental ? 0.45 : 0.4;

      if ((needsLeadingRoom || s.intent == PortraitIntent.environmental) &&
          ((s.faceYaw! > yawThreshold && s.personCenterX > posThreshold) ||
           (s.faceYaw! < -yawThreshold && s.personCenterX < negThreshold))) {
        return const CoachingResult(
          message: '바라보는 쪽에 공간을 더 두세요.',
          priority: CoachingPriority.composition,
          confidence: 0.68,
          reason: '시선이 막히면 답답해 보여요',
        );
      }
    }

    // ─── 8. 환경 포트레이트 크기 ─────────────────────────────
    if (s.intent == PortraitIntent.environmental) {
      if (s.personBboxRatio > 0.65) {
        return const CoachingResult(
          message: '조금 물러서서 배경을 더 담아보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.62,
        );
      }
      if (s.personBboxRatio < 0.08) {
        return const CoachingResult(
          message: '인물이 너무 작게 보여요. 살짝 가까이 가보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.58,
        );
      }
    }

    // ─── 9. 얼굴 프레이밍 ────────────────────────────────────
    if (s.hasFace &&
        (s.shotType == ShotType.closeUp || s.shotType == ShotType.upperBody)) {
      if (s.faceCenterX < 0.22 || s.faceCenterX > 0.78) {
        return const CoachingResult(
          message: '얼굴이 한쪽으로 치우쳐 있어요.',
          priority: CoachingPriority.composition,
          confidence: 0.72,
        );
      }
      if (s.faceBoxRatio > 0.22 && s.shotType == ShotType.closeUp) {
        return const CoachingResult(
          message: '조금 뒤로 물러서보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.7,
        );
      }
    }

    return null;
  }

  /// 프레임 하단에서 관절이 잘리는지 감지
  /// 인물사진의 가장 기본적인 규칙: 관절에서 절대 자르지 않는다
  CoachingResult? _checkBottomJointCut(PortraitSceneState s) {
    if (!s.isBottomJointCut) return null;
    final joint = s.bottomJoint!;
    final y = s.bottomJointY!;

    if ((joint == 'knee' && !s.hasReliableKnees) ||
        (joint == 'ankle' && !s.hasReliableAnkles)) {
      return null;
    }

    // 관절이 프레임 하단 12% 안에 있는 경우만 (y > 0.85)
    // 매우 하단(y > 0.93)은 거의 프레임 밖이므로 더 강한 경고
    final isVeryBottom = y > 0.93;

    return switch (joint) {
      'knee' => CoachingResult(
          message: isVeryBottom
              ? '무릎이 프레임에 걸려요. 허벅지 중간이나 종아리까지 담아보세요.'
              : '무릎선보다 살짝 위나 아래로 여유를 주세요.',
          priority: CoachingPriority.composition,
          confidence: 0.92,
          reason: '관절에서 자르면 절단된 느낌이 나요',
        ),
      'ankle' => CoachingResult(
          message: isVeryBottom
              ? '발끝이 프레임에 걸려요. 발끝 아래를 조금 더 담아주세요.'
              : '발목선에 걸려요. 발끝까지 담거나 종아리 중간에서 맞춰보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.92,
          reason: '발은 전부 보이거나 아예 안 보이는 게 자연스러워요',
        ),
      'hip' when s.shotType == ShotType.waistShot => const CoachingResult(
          message: '허리선에서 자르면 몸이 반으로 나눠 보여요. 골반 아래까지 담아보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.85,
          reason: '허리보다 골반 아래가 자연스러운 커팅이에요',
        ),
      'wrist' => const CoachingResult(
          message: '손이 살짝 걸려요. 손 전체를 넣거나 과감히 빼보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.88,
          reason: '반쯤 보이는 손은 어색해요',
        ),
      _ => null,
    };
  }

  /// 전신 촬영 전용 구도 체크
  CoachingResult? _checkFullBodyComposition(PortraitSceneState s) {
    // (1) 양발 가시성: 전신인데 한쪽 발만 보이면 경고
    if (s.hasReliableAnkles && !s.hasReliableBothAnkles && s.personBboxRatio >= 0.16) {
      return const CoachingResult(
        message: '양발이 모두 보이면 전신 구도가 더 안정돼요.',
        priority: CoachingPriority.composition,
        confidence: 0.82,
        reason: '한쪽 발만 보이면 불균형해 보여요',
      );
    }

    // (2) 발 아래 공간
    if (s.hasReliableAnkles && s.footSpaceRatio < 0.04) {
      return const CoachingResult(
        message: '발끝 아래에 여유 공간을 더 넣어주세요.',
        priority: CoachingPriority.composition,
        confidence: 0.85,
        reason: '발이 프레임에 붙으면 답답해 보여요',
      );
    }
    if (s.hasReliableAnkles && s.footSpaceRatio > 0.12) {
      return const CoachingResult(
        message: '아래 여백이 넓어요. 살짝 가까이 가보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.68,
      );
    }

    // (3) 카메라 높이 가이드 (눈 위치로 추정)
    // 전신은 허리~가슴 높이에서 찍어야 다리가 길어 보임
    // 눈이 너무 높으면(eyeY < 0.22) 카메라가 너무 낮음
    // 눈이 너무 낮으면(eyeY > 0.38) 카메라가 너무 높음 (다리가 짧아 보임)
    if (s.eyeMidpoint != null && s.eyeConfidence > _minConf) {
      if (s.eyeMidpoint!.dy > 0.38) {
        return const CoachingResult(
          message: '폰을 허리쯤으로 낮춰보세요. 다리가 길어 보여요.',
          priority: CoachingPriority.composition,
          confidence: 0.72,
          reason: '높은 각도는 다리가 짧아 보여요',
        );
      }
    }

    return null;
  }

  /// 무릎샷 전용 구도 체크
  CoachingResult? _checkKneeShotComposition(PortraitSceneState s) {
    if (!s.hasReliableKnees) return null;

    // 무릎이 프레임 하단 가까이에 있으면 관절 커팅 위험
    final lk = s.leftKneePosition?.dy;
    final rk = s.rightKneePosition?.dy;
    final kneeY = (lk != null && rk != null)
        ? (lk > rk ? lk : rk)
        : lk ?? rk;

    if (kneeY != null && kneeY > 0.82) {
      return const CoachingResult(
        message: '무릎선에 걸려요. 허벅지 중간까지 담아주세요.',
        priority: CoachingPriority.composition,
        confidence: 0.88,
        reason: '관절 사이 중간이 자연스러운 커팅 포인트예요',
      );
    }

    // 발 아래 공간이 너무 없으면 (무릎샷에서 약간의 여유는 필요)
    if (s.hasReliableAnkles && s.footSpaceRatio < 0.03) {
      return const CoachingResult(
        message: '아래쪽 여유가 조금 좁아요. 살짝 뒤로 가보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.72,
      );
    }

    return null;
  }

  /// 사용자가 선택한 구도 규칙에 인물 중심이 정렬되어 있는지 확인.
  /// 규칙 미선택(none)이면 기존 좌우 이동 휴리스틱 유지.
  CoachingResult? _checkRuleAlignment(PortraitSceneState s) {
    // 인물의 대표 y좌표: 눈 중점 → 얼굴 중심 → 0.5 fallback.
    final subjectY = s.eyeMidpoint?.dy ??
        (s.hasFace ? s.faceCenterY : 0.5);
    final subject = Offset(s.personCenterX, subjectY);
    if (_rule.type == CompositionRuleType.none) {
      // 기존 휴리스틱: 중앙(0.42~0.58) 안에 있으면 좌우 한쪽으로 이동 권장.
      if (s.personCenterX > 0.42 && s.personCenterX < 0.58) {
        return const CoachingResult(
          message: '인물을 좌우 한쪽으로 이동해보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.65,
          reason: '삼분할 구도가 안정적이에요',
        );
      }
      return null;
    }
    final score = _rule.scoreAlignment(subject);
    if (score >= 0.75) return null;
    return CoachingResult(
      message: _rule.guidance(subject),
      priority: CoachingPriority.composition,
      confidence: 0.7,
      reason: '${_rule.label} 구도에 맞춰보세요',
    );
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
      case ShotType.headShot:
        targetY = 0.35;
        tolerance = 0.08;
      case ShotType.upperBody:
        targetY = 0.32;
        tolerance = 0.07;
      case ShotType.waistShot:
        targetY = 0.30;
        tolerance = 0.07;
      case ShotType.kneeShot:
        targetY = 0.28;
        tolerance = 0.07;
      case ShotType.fullBody:
      case ShotType.environmental:
      case ShotType.groupShot:
      case ShotType.unknown:
        return null;
    }

    if ((eyeY - targetY).abs() <= tolerance) return null;

    return CoachingResult(
      message: eyeY < targetY ? '폰을 살짝 내려보세요.' : '폰을 살짝 올려보세요.',
      priority: CoachingPriority.composition,
      confidence: 0.8,
      reason: '눈높이에 맞추면 자연스러워요',
    );
  }

  CoachingResult? _checkHeadroom(double headroom, ShotType shot) {
    double minH;
    double maxH;

    switch (shot) {
      case ShotType.extremeCloseUp:
        minH = 0.0;
        maxH = 0.05;
      case ShotType.closeUp:
        minH = 0.05;
        maxH = 0.12;
      case ShotType.headShot:
        minH = 0.06;
        maxH = 0.13;
      case ShotType.upperBody:
        minH = 0.08;
        maxH = 0.15;
      case ShotType.waistShot:
        minH = 0.06;
        maxH = 0.12;
      case ShotType.kneeShot:
        minH = 0.05;
        maxH = 0.10;
      case ShotType.fullBody:
        minH = 0.05;
        maxH = 0.10;
      case ShotType.environmental:
      case ShotType.groupShot:
      case ShotType.unknown:
        return null;
    }

    if (headroom < minH) {
      return const CoachingResult(
        message: '머리 위가 좁아요. 폰을 살짝 올려보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.85,
        reason: '답답해 보일 수 있어요',
      );
    }
    if (headroom > maxH) {
      return const CoachingResult(
        message: '머리 위가 너무 비었어요. 한 걸음 다가가보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.75,
      );
    }
    return null;
  }

  CoachingResult? _evaluatePose(PortraitSceneState s) {
    // 어깨 각도: headShot 포함 어깨가 보이는 샷 전체 적용
    final checkShoulder = s.shotType == ShotType.headShot ||
        s.shotType == ShotType.closeUp ||
        s.shotType == ShotType.upperBody ||
        s.shotType == ShotType.waistShot ||
        s.shotType == ShotType.kneeShot ||
        s.shotType == ShotType.fullBody;

    if (_enableShoulderAngleCoaching &&
        checkShoulder &&
        s.shoulderAngleDeg != null &&
        s.shoulderConfidence > _minConf) {
      if (s.shoulderAngleDeg!.abs() < 5) {
        return const CoachingResult(
          message: '어깨를 조금 틀어보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.7,
          reason: '입체감이 살아요',
        );
      }
      if (s.shoulderAngleDeg!.abs() > 25) {
        return const CoachingResult(
          message: '어깨가 너무 기울었어요. 살짝만 틀어보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.7,
        );
      }
    }

    // 팔 간격: headShot/closeUp 제외
    final checkArm = s.shotType == ShotType.upperBody ||
        s.shotType == ShotType.waistShot ||
        s.shotType == ShotType.kneeShot ||
        s.shotType == ShotType.fullBody;

    if (checkArm &&
        s.leftArmBodyGap != null &&
        s.rightArmBodyGap != null &&
        s.elbowConfidence > _minConf &&
        s.leftArmBodyGap! < 0.02 &&
        s.rightArmBodyGap! < 0.02) {
      // waistShot/upperBody: 손이 허리 근처면 자연스러운 포즈로 무시
      final isNatural =
          (s.shotType == ShotType.waistShot ||
              s.shotType == ShotType.upperBody) &&
          s.hasVisibleHands &&
          s.isHandNearWaist;
      if (!isNatural) {
        return const CoachingResult(
          message: '팔을 몸에서 조금 떨어뜨려보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.7,
          reason: '실루엣이 날씬해 보여요',
        );
      }
    }

    // waistShot/upperBody: 손이 프레임 가장자리에 걸리면
    if ((s.shotType == ShotType.waistShot ||
            s.shotType == ShotType.upperBody) &&
        s.hasVisibleHands) {
      final lw = s.leftWristPosition;
      final rw = s.rightWristPosition;
      if ((lw != null && (lw.dx < 0.05 || lw.dx > 0.95)) ||
          (rw != null && (rw.dx < 0.05 || rw.dx > 0.95))) {
        return const CoachingResult(
          message: '손이 프레임에 걸려요. 안쪽으로 살짝 넣어주세요.',
          priority: CoachingPriority.pose,
          confidence: 0.7,
        );
      }
    }

    // fullBody/kneeShot: 발 간격 체크 (어깨 너비 대비)
    if ((s.shotType == ShotType.fullBody || s.shotType == ShotType.kneeShot) &&
        s.hasReliableBothAnkles &&
        s.ankleSpacingRatio != null) {
      if (s.ankleSpacingRatio! < 0.3) {
        return const CoachingResult(
          message: '발을 어깨 너비 정도로 벌려보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.68,
          reason: '발이 너무 모이면 불안정해 보여요',
        );
      }
      if (s.ankleSpacingRatio! > 2.0) {
        return const CoachingResult(
          message: '발 간격이 너무 넓어요. 자연스럽게 모아보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.65,
        );
      }
    }

    // fullBody: 콘트라포스토 체크
    if (s.shotType == ShotType.fullBody &&
        s.hasReliableKnees &&
        !s.hasContrapposto &&
        s.hasReliableAnkles) {
      return const CoachingResult(
        message: '한쪽 다리에 무게를 실어보세요.',
        priority: CoachingPriority.pose,
        confidence: 0.65,
        reason: '자연스럽고 역동적이에요',
      );
    }

    return null;
  }

  CoachingResult? _evaluateFaceDirection(PortraitSceneState s) {
    if (!s.hasFace) return null;

    if (s.facePitch != null && s.facePitch! > 20) {
      return const CoachingResult(
        message: '턱이 많이 올라갔어요. 살짝 당겨주세요.',
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
        message: '고개가 기울었어요. 바로 세워보세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.7,
      );
    }

    // 적절한 얼굴 각도 칭찬 (headShot/closeUp에서)
    if ((s.shotType == ShotType.headShot || s.shotType == ShotType.closeUp) &&
        s.faceYaw != null &&
        s.faceYaw!.abs() >= 15 &&
        s.faceYaw!.abs() <= 35) {
      return const CoachingResult(
        message: '얼굴 각도가 자연스러워요!',
        priority: CoachingPriority.perfect,
        confidence: 0.7,
      );
    }

    return null;
  }

  // ─── 카메라 안정성 코칭 ──────────────────────────────

  CoachingResult? _evaluateStability(PortraitSceneState s) {
    if (s.cameraStability > 0.22) return null;
    return CoachingResult(
      message: s.isFrontCamera
          ? '흔들려요. 팔꿈치를 몸에 붙여보세요.'
          : '흔들려요. 잠시 멈추고 찍어보세요.',
      priority: CoachingPriority.composition,
      confidence: 0.82,
    );
  }

  // ─── 셀카 모드 전용 코칭 ─────────────────────────────

  CoachingResult? _evaluateSelfie(PortraitSceneState s) {
    // ── 1. 광각 왜곡 경고 (전면 카메라 = 광각, 가까울수록 왜곡 심함) ──
    if (s.personBboxRatio > 0.55) {
      return const CoachingResult(
        message: '너무 가까워요! 팔을 뻗거나 셀카봉을 사용해보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.88,
        reason: '가까울수록 코가 커지고 얼굴이 왜곡돼요',
      );
    }
    if (s.faceBoxRatio > 0.13 &&
        (s.shotType == ShotType.closeUp ||
         s.shotType == ShotType.headShot ||
         s.shotType == ShotType.extremeCloseUp)) {
      return const CoachingResult(
        message: '얼굴이 왜곡될 수 있어요. 조금 더 떨어져서 찍어보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.80,
        reason: '전면 카메라는 광각이라 가까우면 코가 커 보여요',
      );
    }

    // ── 2. 역광 (셀카에서도 중요) ─────────────────────────
    if (s.lightingCondition == LightingCondition.back &&
        s.lightingConfidence > 0.7) {
      return const CoachingResult(
        message: '역광이에요. 빛을 향해 돌아서보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.85,
      );
    }

    // ── 3. 카메라 높이 (셀카 핵심!) ───────────────────────
    // pitch > 0: 턱 올라감 = 카메라가 아래에 있음 (올려다보는 중)
    // pitch < 0: 턱 내려감 = 카메라가 위에 있음 (내려다보는 중)
    // 이상적: 카메라가 눈높이 살짝 위 → pitch 약간 양수(5~15°)
    if (s.facePitch != null) {
      if (s.facePitch! < -10) {
        // 카메라가 아래에 있음 → 이중턱, 불리한 각도
        return const CoachingResult(
          message: '폰을 눈높이 위로 들어보세요. 턱선이 살아나요.',
          priority: CoachingPriority.composition,
          confidence: 0.85,
          reason: '아래에서 찍으면 이중턱이 생길 수 있어요',
        );
      }
      if (s.facePitch! > 25) {
        // 카메라가 너무 위에 있음 → 부자연스러운 시선
        return const CoachingResult(
          message: '폰이 너무 높아요. 눈높이 살짝 위로 내려보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.78,
        );
      }
    }

    // ── 4. 셀카 조명 (순광에 더 관대) ─────────────────────
    final lighting = _evaluateSelfieLighting(s);
    if (lighting != null) return lighting;

    // ── 5. 헤드룸 ────────────────────────────────────────
    if (s.hasPose || s.hasNose) {
      if (s.headroomRatio < 0.04) {
        return const CoachingResult(
          message: '머리가 잘려요. 폰을 살짝 내려보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.80,
        );
      }
      if (s.headroomRatio > 0.18) {
        return const CoachingResult(
          message: '머리 위가 비었어요. 폰을 가까이 해보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.65,
        );
      }
    }

    // ── 6. 얼굴 각도 (3/4 뷰가 최적) ─────────────────────
    if (s.faceYaw != null) {
      if (s.faceYaw!.abs() > 40) {
        return const CoachingResult(
          message: '고개를 너무 많이 돌렸어요. 살짝만 돌려보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.75,
        );
      }
      if (s.faceYaw!.abs() < 5) {
        return const CoachingResult(
          message: '살짝 고개를 돌리면 입체감이 생겨요.',
          priority: CoachingPriority.pose,
          confidence: 0.62,
          reason: '정면보다 3/4 각도가 자연스러워요',
        );
      }
    }

    // ── 7. 턱 라인 트릭 (프로 인물사진 핵심) ───────────────
    // 카메라 높이가 적절하고 다른 이슈 없을 때 턱 포워드 제안
    if (s.facePitch != null &&
        s.facePitch! >= -5 &&
        s.facePitch! <= 10) {
      return const CoachingResult(
        message: '턱을 살짝 앞으로 내밀면 턱선이 선명해져요.',
        priority: CoachingPriority.refinement,
        confidence: 0.65,
        reason: '프로 포트레이트의 턱 라인 기술이에요',
      );
    }

    // ── 8. 고개 기울기 ───────────────────────────────────
    if (s.faceRoll != null && s.faceRoll!.abs() > 20) {
      return const CoachingResult(
        message: '고개가 기울었어요. 바로 세워보세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.7,
      );
    }

    return null;
  }

  CoachingResult? _evaluateSelfieLighting(PortraitSceneState s) {
    if (s.lightingConfidence < 0.5) return null;

    switch (s.lightingCondition) {
      case LightingCondition.short:
        return null; // 사광은 셀카에서도 최고
      case LightingCondition.normal:
        // 셀카에서 순광은 더 관대하게 (refinement로 낮춤)
        if (s.lightingConfidence > 0.7) {
          return const CoachingResult(
            message: '빛이 좋아요. 살짝 비스듬하면 더 입체적이에요.',
            priority: CoachingPriority.refinement,
            confidence: 0.55,
          );
        }
        return null;
      case LightingCondition.side:
        // 측광은 셀카에서도 좋지만 얼굴 방향 맞추면 최적
        if (s.faceYaw != null &&
            s.faceYaw!.abs() >= 10 &&
            s.faceYaw!.abs() <= 35) {
          return null; // 얼굴 각도가 빛과 맞음
        }
        return const CoachingResult(
          message: '빛 방향으로 살짝 고개를 돌려보세요.',
          priority: CoachingPriority.refinement,
          confidence: 0.60,
        );
      case LightingCondition.rim:
        return const CoachingResult(
          message: '윤곽광이에요. 빛을 향해 살짝 돌아보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.65,
        );
      case LightingCondition.back:
        return null; // 역광은 이미 위에서 처리됨
      case LightingCondition.unknown:
        return null;
    }
  }

  String _selfiePerfectMessage(PortraitSceneState s) {
    if (s.lightingCondition == LightingCondition.short &&
        s.lightingConfidence > 0.5) {
      return '완벽한 셀카 조명이에요!';
    }
    if (s.faceYaw != null &&
        s.faceYaw!.abs() >= 15 &&
        s.faceYaw!.abs() <= 35) {
      return '멋진 셀카 각도예요!';
    }
    if (_enableSmileCoaching && s.isSmiling) {
      return '자연스러운 미소가 좋아요!';
    }
    return '좋은 셀카예요!';
  }

  // ─── 표정 코칭 ──────────────────────────────────────

  CoachingResult? _evaluateExpression(PortraitSceneState s) {
    if (s.smileProbability == null) return null;

    if (s.smileProbability! > 0.9) {
      return const CoachingResult(
        message: '미소가 과해요. 조금 부드럽게 웃어보세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.60,
      );
    }

    // 셀카에서만 미소 유도 (후면 카메라는 피사체가 자유롭게 표정 결정)
    if (s.isFrontCamera && s.smileProbability! < 0.05) {
      return const CoachingResult(
        message: '자연스럽게 미소를 지어보세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.50,
      );
    }

    return null;
  }

  // ─── 조명+포즈 연계 코칭 ────────────────────────────

  CoachingResult? _evaluateLightingPoseCombined(PortraitSceneState s) {
    if (s.lightingConfidence < 0.5 || !s.hasFace) return null;
    final yaw = s.faceYaw?.abs() ?? 0;
    final shoulderAng = s.shoulderAngleDeg?.abs();

    // 순광 + 정면 + 수평어깨 = 증명사진 느낌
    if (s.lightingCondition == LightingCondition.normal &&
        s.lightingConfidence > 0.6 &&
        yaw < 8 &&
        shoulderAng != null &&
        shoulderAng < 5) {
      return const CoachingResult(
        message: '증명사진 느낌이에요. 얼굴과 어깨를 살짝 틀어보세요.',
        priority: CoachingPriority.pose,
        confidence: 0.70,
        reason: '순광+정면+수평어깨는 밋밋해 보여요',
      );
    }

    // 측광 + 어깨 비스듬 + 얼굴 돌림 = 3박자 완벽
    if (s.lightingCondition == LightingCondition.side &&
        shoulderAng != null &&
        shoulderAng >= 8 &&
        shoulderAng <= 20 &&
        yaw >= 15 &&
        yaw <= 35) {
      return const CoachingResult(
        message: '빛, 어깨, 시선이 완벽해요! 지금 찍으세요!',
        priority: CoachingPriority.perfect,
        confidence: 0.92,
      );
    }

    // 사광 + 좋은 어깨 + 얼굴 돌림 = 완벽 조합
    if (s.lightingCondition == LightingCondition.short &&
        shoulderAng != null &&
        shoulderAng >= 5 &&
        shoulderAng <= 25 &&
        yaw >= 10) {
      return const CoachingResult(
        message: '빛과 포즈가 완벽하게 어울려요!',
        priority: CoachingPriority.perfect,
        confidence: 0.88,
      );
    }

    // 역사광/역광 + 환경 포트레이트 = 드라마틱 실루엣 기회
    if ((s.lightingCondition == LightingCondition.rim ||
         s.lightingCondition == LightingCondition.back) &&
        s.personBboxRatio < 0.35 &&
        s.shotType == ShotType.environmental) {
      return const CoachingResult(
        message: '드라마틱한 실루엣을 만들어보세요!',
        priority: CoachingPriority.refinement,
        confidence: 0.68,
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
        return '멋진 전신 구도예요! 발끝까지 잘 담겼어요.';
      case ShotType.kneeShot:
        return '좋은 무릎샷이에요! 프레이밍이 자연스러워요.';
      case ShotType.environmental:
        return '멋진 환경 인물 사진이에요!';
      case ShotType.groupShot:
        return '좋은 그룹샷이에요!';
      case ShotType.closeUp:
      case ShotType.headShot:
      case ShotType.upperBody:
      case ShotType.waistShot:
      case ShotType.unknown:
        return '좋은 구도예요!';
    }
  }
}
