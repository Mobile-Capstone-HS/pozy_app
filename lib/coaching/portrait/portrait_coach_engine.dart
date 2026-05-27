library;

import 'package:flutter/material.dart';

import '../../composition/composition_rule.dart';
import '../../composition/composition_rule_registry.dart';
import 'portrait_scene_state.dart';
import 'dart:math' as math;

enum _PoseIntent {
  standingBasic,
  seated,
  selfie,
  fashion,
  casualSnapshot,
  couple,
}

class PortraitCoachEngine {
  static const double _minConf = 0.5;
  static const bool _enableShoulderAngleCoaching = false;
  static const bool _enableSmileCoaching = false;

  /// 사용자가 선택한 구도 규칙. none이면 기존 하드코딩 3분할 휴리스틱.
  CompositionRule _rule = CompositionRuleRegistry.of(CompositionRuleType.none);

  void setRule(CompositionRule rule) {
    _rule = rule;
  }

  CoachingResult evaluate(PortraitSceneState s) {
    final poseIntent = _inferPoseIntent(s);

    if (s.personCount == 0) {
      return const CoachingResult(
        message: '인물을 화면 안에 담아보세요',
        priority: CoachingPriority.critical,
        confidence: 1.0,
        reason: '얼굴과 자세가 보이면 구도를 안내할게요',
      );
    }

    // ─── 그룹샷 코칭 (2명 이상) ──────────────────────────
    // 그룹샷은 메인 인물 키포인트 체크보다 우선 판정합니다.
    // 3명 이상도 인원 제한 없이 실질적인 피드백을 제공합니다.
    if (s.intent == PortraitIntent.group && !s.isGroupShot) {
      return const CoachingResult(
        message: '두 명 이상을 화면 안에 함께 담아보세요',
        priority: CoachingPriority.composition,
        confidence: 0.65,
        reason: '여러 명이 보이면 간격과 구도를 기준으로 안내할게요',
      );
    }

    if (s.isGroupShot) {
      if (s.personCount == 2) {
        return _evaluateCoupleShot(s);
      }
      return _evaluateGroupShot(s);
    }

    if (s.lightingCondition == LightingCondition.back &&
        s.lightingConfidence >= 0.6 &&
        (!s.hasNose || !s.hasEyes || s.visibleKeypointCount < 3)) {
      return CoachingResult(
        message: s.isFrontCamera ? '역광 때문에 얼굴이 어두워요' : '역광으로 얼굴이 어두워 보여요',
        priority: CoachingPriority.composition,
        confidence: 0.72,
        reason: s.isFrontCamera
            ? '빛을 정면으로 받도록 몸을 살짝 돌려보세요'
            : '얼굴을 살리려면 빛이 옆에서 오도록 위치를 조금 바꿔보세요',
      );
    }

    if (!s.hasNose && !s.hasEyes && !s.hasShoulders) {
      return const CoachingResult(
        message: '인물이 더 잘 보이도록 화면을 맞춰보세요',
        priority: CoachingPriority.critical,
        confidence: 0.95,
        reason: '얼굴과 자세가 보이면 구도 안내가 더 정확해져요',
      );
    }

    if (s.visibleKeypointCount < 3) {
      return const CoachingResult(
        message: '상체가 보이도록 화면을 맞춰보세요',
        priority: CoachingPriority.critical,
        confidence: 0.9,
        reason: '핵심 자세가 보이면 구도 안내가 더 정확해져요',
      );
    }

    if (s.areEyesClosed) {
      return const CoachingResult(
        message: '눈을 감은 것 같아요',
        priority: CoachingPriority.critical,
        confidence: 0.9,
        reason: '눈을 뜬 상태에서 다시 맞춰보세요',
      );
    }

    if (s.isOneEyeClosed) {
      return const CoachingResult(
        message: '한쪽 눈이 감긴 것 같아요',
        priority: CoachingPriority.composition,
        confidence: 0.72,
        reason: '눈이 또렷하게 보이도록 다시 맞춰보세요',
      );
    }

    if (s.leftEyeOpenProb != null &&
        s.rightEyeOpenProb != null &&
        !s.areEyesClosed &&
        !s.isOneEyeClosed) {
      final minEye = math.min(s.leftEyeOpenProb!, s.rightEyeOpenProb!);
      final maxEye = math.max(s.leftEyeOpenProb!, s.rightEyeOpenProb!);
      if (s.eyeConfidence < 0.35) {
        return const CoachingResult(
          message: '눈 상태가 잘 보이지 않아요',
          priority: CoachingPriority.composition,
          confidence: 0.6,
          reason: '얼굴이 더 또렷하게 보이도록 맞춰보세요',
        );
      }
      if (minEye < 0.55 && maxEye < 0.75) {
        return const CoachingResult(
          message: '눈이 조금 작게 보여요',
          priority: CoachingPriority.refinement,
          confidence: 0.58,
          reason: '눈을 조금 더 또렷하게 떠보세요',
        );
      }
    }

    if (s.lightingCondition == LightingCondition.back &&
        s.lightingConfidence > 0.8 &&
        s.personBboxRatio >= 0.4) {
      return CoachingResult(
        message: s.isFrontCamera ? '강한 역광이에요' : '얼굴이 어두워질 수 있어요',
        priority: s.isFrontCamera
            ? CoachingPriority.critical
            : CoachingPriority.composition,
        confidence: s.isFrontCamera ? 0.9 : 0.78,
        reason: s.isFrontCamera
            ? '몸을 살짝 돌려 빛을 받아보세요'
            : '얼굴을 살리려면 빛이 정면보다 옆에서 오게 움직여보세요',
      );
    }

    if (s.isFrontCamera) {
      final lighting = _evaluateLighting(s);
      if (lighting != null) return lighting;
    }

    if (s.isFrontCamera && _enableShoulderAngleCoaching) {
      final lightPose = _evaluateLightingPoseCombined(s);
      if (lightPose != null) return lightPose;
    }

    final composition = _evaluateComposition(s, poseIntent);
    if (composition != null) return composition;

    final pose = _evaluatePose(s, poseIntent);
    if (pose != null) return pose;

    final face = _evaluateFaceDirection(s, poseIntent);
    if (face != null) return face;

    if (!s.hasEyes || !s.hasShoulders) {
      return const CoachingResult(
        message: '상체가 조금 더 보이면 안내가 더 정확해져요.',
        priority: CoachingPriority.composition,
        confidence: 0.7,
      );
    }

    if (!s.isFrontCamera) {
      final lighting = _evaluateLighting(s);
      if (lighting != null) return lighting;
    }

    if (!s.isFrontCamera && _enableShoulderAngleCoaching) {
      final lightPose = _evaluateLightingPoseCombined(s);
      if (lightPose != null) return lightPose;
    }

    // ─── 카메라 안정성은 구도/조명/포즈보다 뒤에서 보조적으로 사용 ──────
    final stability = _evaluateStability(s);
    if (stability != null) return stability;

    // ─── 셀카 전용 미세 조정은 공통 인물 규칙 뒤에서 적용 ─────────────
    if (s.isFrontCamera) {
      final selfie = _evaluateSelfie(s, poseIntent);
      if (selfie != null) return selfie;
    }

    if (_enableSmileCoaching) {
      final expression = _evaluateExpression(s);
      if (expression != null) return expression;
    }

    if (s.isFrontCamera) {
      return _selfieFallbackResult(s);
    }

    return CoachingResult(
      message: _perfectMessage(s),
      priority: CoachingPriority.perfect,
      confidence: 1.0,
    );
  }

  _PoseIntent _inferPoseIntent(PortraitSceneState s) {
    if (s.intent == PortraitIntent.environmental ||
        s.shotType == ShotType.environmental) {
      return _PoseIntent.standingBasic;
    }
    if (s.isFrontCamera) return _PoseIntent.selfie;
    if (s.personCount == 2 && s.isGroupShot) return _PoseIntent.couple;
    if (_isLikelySeated(s)) return _PoseIntent.seated;
    if (_isLikelyFashionPose(s)) return _PoseIntent.fashion;
    return _PoseIntent.standingBasic;
  }

  bool _isLikelySeated(PortraitSceneState s) {
    final hipY = _averageDefined([s.leftHipPosition?.dy, s.rightHipPosition?.dy]);
    final kneeY = _averageDefined(
      [s.leftKneePosition?.dy, s.rightKneePosition?.dy],
    );
    if (hipY == null || kneeY == null) return false;
    final compressedLeg = (kneeY - hipY) < 0.18;
    final upperBodyShot =
        s.shotType == ShotType.waistShot ||
        s.shotType == ShotType.upperBody ||
        s.shotType == ShotType.kneeShot;
    return compressedLeg && upperBodyShot;
  }

  bool _isLikelyFashionPose(PortraitSceneState s) {
    final dramaticFullBody =
        s.shotType == ShotType.fullBody || s.shotType == ShotType.kneeShot;
    if (!dramaticFullBody) return false;
    final crossedOrTightFeet =
        s.ankleSpacingRatio != null && s.ankleSpacingRatio! < 0.45;
    final wideFeet =
        s.ankleSpacingRatio != null && s.ankleSpacingRatio! > 1.6;
    final offCenter = (s.personCenterX - 0.5).abs() > 0.14;
    return s.hasContrapposto || crossedOrTightFeet || wideFeet || offCenter;
  }

  double? _averageDefined(List<double?> values) {
    final defined = values.whereType<double>().toList(growable: false);
    if (defined.isEmpty) return null;
    return defined.reduce((a, b) => a + b) / defined.length;
  }

  // ─── 그룹샷 코칭 (2명 이상) ───────────────────────────
  CoachingResult _evaluateGroupShot(PortraitSceneState s) {
    // 그룹 모드는 개별 포즈보다 전체 프레이밍을 우선합니다.
    if (s.groupCroppedCount > 0) {
      final isMajority = s.groupCroppedCount >= (s.personCount / 2).ceil();
      return CoachingResult(
        message: isMajority ? '여러 명이 화면 밖으로 걸려요' : '가장자리 사람이 잘려요',
        priority: CoachingPriority.composition,
        confidence: 0.88,
        reason: isMajority ? '조금 뒤로 물러나 모두 담아보세요' : '조금 뒤로 물러나 여유를 주세요',
      );
    }

    final minBboxRatio = s.personCount >= 4
        ? 0.06
        : s.personCount >= 3
        ? 0.08
        : 0.12;
    if (s.personBboxRatio < minBboxRatio) {
      return const CoachingResult(
        message: '사람들이 조금 작게 보여요',
        priority: CoachingPriority.composition,
        confidence: 0.72,
        reason: '조금 가까이 가서 더 크게 담아보세요',
      );
    }

    final maxBboxRatio = s.personCount >= 4
        ? 0.86
        : s.personCount >= 3
        ? 0.82
        : 0.76;
    if (s.personBboxRatio > maxBboxRatio) {
      return const CoachingResult(
        message: '사람들이 화면에 꽉 차요',
        priority: CoachingPriority.composition,
        confidence: 0.78,
        reason: '조금 뒤로 물러나 여유를 만들어보세요',
      );
    }

    if (s.headroomRatio < 0.04) {
      return const CoachingResult(
        message: '머리 위가 좁아요',
        priority: CoachingPriority.composition,
        confidence: 0.80,
        reason: '폰을 살짝 올려 여유를 만들어보세요',
      );
    }

    if (s.footSpaceRatio < 0.035) {
      return const CoachingResult(
        message: '아래쪽이 좁아요',
        priority: CoachingPriority.composition,
        confidence: 0.76,
        reason: '발끝까지 조금 더 담아보세요',
      );
    }

    final groupOffCenter = (s.personCenterX - 0.5).abs();
    if (groupOffCenter > 0.15) {
      final direction = s.personCenterX < 0.5 ? '오른쪽' : '왼쪽';
      return CoachingResult(
        message: '사람들이 한쪽으로 치우쳐요',
        priority: CoachingPriority.composition,
        confidence: 0.78,
        reason: '폰을 $direction으로 살짝 옮겨보세요',
      );
    }

    if (s.personCount >= 3) {
      if (s.spacingUnevenness > 0.5) {
        return const CoachingResult(
          message: '사람 간격이 조금 달라요',
          priority: CoachingPriority.composition,
          confidence: 0.72,
          reason: '가운데로 살짝 모여보세요',
        );
      }

      if (s.heightVariation > 0.15) {
        return const CoachingResult(
          message: '줄 높이가 조금 달라요',
          priority: CoachingPriority.composition,
          confidence: 0.68,
          reason: '키 큰 분은 살짝 뒤로 서보세요',
        );
      }
    }

    if (s.personCount == 2 && s.secondPersonSizeRatio < 0.35) {
      return const CoachingResult(
        message: '두 사람 크기 차이가 커요',
        priority: CoachingPriority.composition,
        confidence: 0.82,
        reason: '비슷한 거리에서 서보세요',
      );
    }

    // 얼굴/눈은 멀어질수록 불안정하므로 프레이밍 이후의 보조 안내로만 사용합니다.
    if (s.faceHiddenCount > 0) {
      return CoachingResult(
        message: s.faceHiddenCount == 1
            ? '얼굴이 가려진 사람이 있어요'
            : '${s.faceHiddenCount}명의 얼굴이 덜 보여요',
        priority: CoachingPriority.composition,
        confidence: 0.68,
        reason: s.faceHiddenCount == 1
            ? '얼굴이 보이게 살짝 움직여보세요'
            : '얼굴이 보이게 살짝 모여보세요',
      );
    }

    if (s.anyFaceEyesClosed || s.areEyesClosed) {
      return CoachingResult(
        message: s.closedFaceCount > 1
            ? '${s.closedFaceCount}명이 눈을 감은 것 같아요.'
            : '눈을 감은 사람이 있는 것 같아요.',
        priority: CoachingPriority.composition,
        confidence: 0.68,
      );
    }

    return CoachingResult(
      message: '${s.personCount}명 모두 화면에 잘 들어왔어요!',
      priority: CoachingPriority.perfect,
      confidence: 0.85,
    );
  }

  CoachingResult _evaluateCoupleShot(PortraitSceneState s) {
    if (s.groupCroppedCount > 0) {
      return const CoachingResult(
        message: '두 사람이 모두 잘 보이게 조금만 여유를 주세요',
        priority: CoachingPriority.composition,
        confidence: 0.86,
        reason: '가장자리 잘림만 줄여도 훨씬 자연스러워져요',
      );
    }

    if (s.headroomRatio < 0.03) {
      return const CoachingResult(
        message: '머리 위가 조금 좁아요',
        priority: CoachingPriority.composition,
        confidence: 0.72,
        reason: '윗부분에 살짝만 여유를 두면 더 편안해 보여요',
      );
    }

    if (s.footSpaceRatio < 0.025 &&
        (s.shotType == ShotType.fullBody || s.shotType == ShotType.kneeShot)) {
      return const CoachingResult(
        message: '아래쪽에 조금만 더 여유를 주세요',
        priority: CoachingPriority.composition,
        confidence: 0.70,
      );
    }

    if (s.secondPersonSizeRatio < 0.28) {
      return const CoachingResult(
        message: '두 사람 크기가 조금 차이 나 보여요',
        priority: CoachingPriority.composition,
        confidence: 0.72,
        reason: '서 있는 위치를 살짝만 맞추면 더 자연스러워요',
      );
    }

    if (s.faceHiddenCount > 0) {
      return const CoachingResult(
        message: '두 사람 얼굴이 모두 잘 보이게 맞춰보세요',
        priority: CoachingPriority.composition,
        confidence: 0.70,
      );
    }

    if (s.anyFaceEyesClosed || s.areEyesClosed) {
      return const CoachingResult(
        message: '눈을 감은 사람이 있는 것 같아요',
        priority: CoachingPriority.composition,
        confidence: 0.68,
      );
    }

    return const CoachingResult(
      message: '두 사람 분위기가 자연스럽게 잘 담기고 있어요',
      priority: CoachingPriority.perfect,
      confidence: 0.82,
    );
  }

  CoachingResult? _evaluateLighting(PortraitSceneState s) {
    if (s.lightingConfidence < 0.5) return null;

    switch (s.lightingCondition) {
      case LightingCondition.short:
        return null;
      case LightingCondition.normal:
        if (s.lightingConfidence > 0.6) {
          return CoachingResult(
            message: '빛이 정면에서 와요',
            priority: CoachingPriority.composition,
            confidence: 0.7,
            reason: s.isFrontCamera
                ? '몸을 살짝 비스듬히 틀어보세요'
                : '피사체가 살짝 비스듬히 서면 얼굴이 더 입체적으로 보여요',
          );
        }
        return null;
      case LightingCondition.side:
        final yaw = s.faceYaw?.abs();
        if (yaw == null) return null;
        if (yaw >= 15 && yaw <= 30) {
          return const CoachingResult(
            message: '빛 방향이 좋아요. 얼굴이 입체적으로 보여요.',
            priority: CoachingPriority.perfect,
            confidence: 0.8,
          );
        }
        if (yaw < 10) {
          return CoachingResult(
            message: '얼굴 방향을 맞춰보세요',
            priority: CoachingPriority.refinement,
            confidence: 0.65,
            reason: s.isFrontCamera
                ? '얼굴을 빛 쪽으로 조금 돌려보세요'
                : '피사체 얼굴이 빛 쪽을 살짝 보게 해보세요',
          );
        }
        if (yaw > 30) {
          return CoachingResult(
            message: '그림자가 강해요',
            priority: CoachingPriority.composition,
            confidence: 0.7,
            reason: s.isFrontCamera
                ? '얼굴을 빛 쪽으로 살짝 돌려보세요'
                : '얼굴을 살리려면 피사체가 빛 쪽을 조금 더 보게 해보세요',
          );
        }
        return null;
      case LightingCondition.rim:
        if (s.personBboxRatio < 0.4) {
          return const CoachingResult(
            message: '뒤쪽 빛이 자연스럽게 들어오고 있어요.',
            priority: CoachingPriority.refinement,
            confidence: 0.65,
          );
        }
        if (s.personBboxRatio >= 0.4) {
          return CoachingResult(
            message: '뒤에서 빛이 들어와요',
            priority: CoachingPriority.composition,
            confidence: s.isFrontCamera ? 0.65 : 0.58,
            reason: s.isFrontCamera
                ? '얼굴을 빛 쪽으로 살짝 돌려보세요'
                : '얼굴이 어두우면 피사체가 빛 쪽을 살짝 보게 해보세요',
          );
        }
        return null;
      case LightingCondition.back:
        if (s.personBboxRatio < 0.4) {
          return const CoachingResult(
            message: '배경 빛이 좋아요. 사람 윤곽을 살려보세요.',
            priority: CoachingPriority.refinement,
            confidence: 0.7,
          );
        }
        if (s.lightingConfidence >= 0.6) {
          return CoachingResult(
            message: '역광이에요',
            priority: s.isFrontCamera
                ? CoachingPriority.composition
                : CoachingPriority.refinement,
            confidence: s.isFrontCamera ? 0.75 : 0.62,
            reason: s.isFrontCamera
                ? '빛이 직접 들어오지 않게 각도를 바꿔보세요'
                : '실루엣 느낌이 아니라면 빛이 옆에서 오도록 살짝 이동해보세요',
          );
        }
        return CoachingResult(
          message: '빛이 뒤에서 들어와요',
          priority: s.isFrontCamera
              ? CoachingPriority.composition
              : CoachingPriority.refinement,
          confidence: s.isFrontCamera ? 0.62 : 0.55,
          reason: s.isFrontCamera
              ? '몸을 조금 돌려 빛을 받아보세요'
              : '얼굴을 밝히고 싶다면 촬영 위치를 살짝 옮겨보세요',
        );
      case LightingCondition.unknown:
        return null;
    }
  }

  CoachingResult? _evaluateComposition(PortraitSceneState s, _PoseIntent intent) {
    final relaxedCropIntent =
        intent == _PoseIntent.seated ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot ||
        intent == _PoseIntent.selfie;
    final relaxedBalanceIntent =
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot ||
        intent == _PoseIntent.selfie;

    // ─── 1. 관절 커팅 감지 (인물사진 최우선 규칙) ──────────────
    // "관절에서 자르지 마라" — 가장자리 관절 + 프레임 하단 관절 모두 체크
    if (s.shotType != ShotType.extremeCloseUp) {
      // (a) 프레임 하단에서 관절이 잘리는 경우 (더 중요)
      final bottomResult = _checkBottomJointCut(s, intent);
      if (bottomResult != null) return bottomResult;

      // (b) 프레임 가장자리에서 관절이 잘리는 경우
      if (s.croppedJoints.isNotEmpty && !relaxedCropIntent) {
        final joint = s.croppedJoints.firstWhere(
          (joint) => joint == 'knee' || joint == 'ankle',
          orElse: () => '',
        );
        if (joint.isNotEmpty) {
          final msg = switch (joint) {
            'knee' => '무릎선에 걸려요. 허벅지 중간이나 종아리까지 담아보세요.',
            'ankle' => '발끝까지 담거나, 종아리 중간에서 맞춰보세요.',
            'wrist' => '손이 살짝 걸려요. 손 전체를 넣거나 과감히 빼보세요.',
            'elbow' => '팔꿈치가 프레임에 걸려요. 팔 중간에서 맞춰보세요.',
            _ => '관절이 화면 끝에 걸려요. 조금 더 여유를 주세요.',
          };
          final reason = switch (joint) {
            'knee' || 'ankle' => '무릎이나 발목에서 딱 잘리면 어색해 보여요',
            'wrist' => '반쯤 보이는 손은 어색해요',
            'elbow' => '팔꿈치보다 팔 중간에서 자르면 자연스러워요',
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
    }

    // ─── 2. 전신 전용 구도 체크 ───────────────────────────────
    if (s.shotType == ShotType.fullBody) {
      final fullBodyResult = _checkFullBodyComposition(s, intent);
      if (fullBodyResult != null) return fullBodyResult;
    }

    // ─── 3. 무릎샷 전용 구도 체크 ─────────────────────────────
    if (s.shotType == ShotType.kneeShot) {
      final kneeResult = _checkKneeShotComposition(s, intent);
      if (kneeResult != null) return kneeResult;
    }

    if (s.lowerBodyTouchesBottom && !relaxedCropIntent) {
      return const CoachingResult(
        message: '아래쪽이 잘릴 수 있어요',
        priority: CoachingPriority.composition,
        confidence: 0.82,
        reason: '발끝까지 담거나 허벅지 중간에서 맞춰보세요',
      );
    }

    // ─── 4. 눈 위치 (삼분할 법칙) ─────────────────────────────
    if (s.eyeMidpoint != null && s.eyeConfidence > _minConf) {
      final result = _checkEyePosition(s.eyeMidpoint!.dy, s.shotType, intent);
      if (result != null) return result;
    }

    // ─── 5. 헤드룸 ───────────────────────────────────────────
    if ((s.hasPose || s.hasNose) &&
        !_shouldSkipGenericHeadroomForSelfieCloseShot(s, intent)) {
      final result = _checkHeadroom(
        s.headroomRatio,
        s.shotType,
        intent,
        isFrontCamera: s.isFrontCamera,
        footSpace: s.footSpaceRatio,
      );
      if (result != null) return result;
    }

    // ─── 6. 전신 발 아래 공간 ─────────────────────────────────
    if (s.shotType == ShotType.fullBody && intent == _PoseIntent.standingBasic) {
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
    if (s.intent == PortraitIntent.environmental) {
      final maxEnvironmentalRatio = switch (s.shotType) {
        ShotType.fullBody => 0.35,
        ShotType.kneeShot || ShotType.waistShot => 0.42,
        ShotType.upperBody || ShotType.headShot => 0.48,
        _ => 0.45,
      };
      if (s.personBboxRatio > maxEnvironmentalRatio) {
        return const CoachingResult(
          message: '장소가 더 읽히도록 한 걸음만 뒤로 가볼게요',
          priority: CoachingPriority.composition,
          confidence: 0.72,
          reason: '환경샷은 인물과 배경이 함께 보여야 공간의 이야기가 살아나요',
        );
      }
      if (s.personBboxRatio < 0.08) {
        return const CoachingResult(
          message: '인물이 너무 작아져서 표정이 약해졌어요',
          priority: CoachingPriority.composition,
          confidence: 0.62,
          reason: '반 걸음만 가까이 가서 인물의 존재감을 살려보세요',
        );
      }
    }

    if (s.shotType == ShotType.fullBody ||
        s.intent == PortraitIntent.environmental) {
      final ruleResult = _checkRuleAlignment(s, intent);
      if (ruleResult != null) return ruleResult;
    }

    // ─── 7. 리딩룸 (시선 방향 여백) ──────────────────────────
    if (s.faceYaw != null) {
      final needsLeadingRoom =
          s.shotType == ShotType.upperBody ||
          s.shotType == ShotType.waistShot ||
          s.shotType == ShotType.kneeShot;
      final yawThreshold = s.intent == PortraitIntent.environmental
          ? 5.0
          : 10.0;
      final posThreshold = s.intent == PortraitIntent.environmental
          ? 0.55
          : 0.6;
      final negThreshold = s.intent == PortraitIntent.environmental
          ? 0.45
          : 0.4;

      if (!relaxedBalanceIntent &&
          (needsLeadingRoom || s.intent == PortraitIntent.environmental) &&
          ((s.faceYaw! > yawThreshold && s.personCenterX > posThreshold) ||
              (s.faceYaw! < -yawThreshold && s.personCenterX < negThreshold))) {
        return CoachingResult(
          message: s.intent == PortraitIntent.environmental
              ? '시선이 향하는 쪽에 장소의 여백을 남겨보세요'
              : '바라보는 쪽에 공간을 더 두세요.',
          priority: CoachingPriority.composition,
          confidence: 0.68,
          reason: s.intent == PortraitIntent.environmental
              ? '인물이 바라보는 방향으로 공간이 열리면 장면이 더 자연스럽게 읽혀요'
              : '시선 앞쪽이 비어 있으면 더 자연스러워요',
        );
      }
    }

    // ─── 9. 얼굴 프레이밍 ────────────────────────────────────
    if (s.hasFace &&
        !relaxedBalanceIntent &&
        (s.shotType == ShotType.closeUp || s.shotType == ShotType.upperBody)) {
      if (s.faceCenterX < 0.22 || s.faceCenterX > 0.78) {
        return const CoachingResult(
          message: '얼굴이 한쪽으로 치우쳐 있어요.',
          priority: CoachingPriority.composition,
          confidence: 0.72,
        );
      }
      if (s.faceBoxRatio > 0.30 && s.shotType == ShotType.closeUp) {
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
  CoachingResult? _checkBottomJointCut(
    PortraitSceneState s,
    _PoseIntent intent,
  ) {
    if (!s.isBottomJointCut) return null;
    final joint = s.bottomJoint!;
    final y = s.bottomJointY!;

    if (s.intent == PortraitIntent.environmental &&
        (joint == 'wrist' || joint == 'elbow')) {
      return null;
    }

    if (joint == 'wrist') {
      return null;
    }

    if ((joint == 'knee' && !s.hasReliableKnees) ||
        (joint == 'ankle' && !s.hasReliableAnkles)) {
      return null;
    }

    // 관절이 프레임 하단 12% 안에 있는 경우만 (y > 0.85)
    // 매우 하단(y > 0.93)은 거의 프레임 밖이므로 더 강한 경고
    final isVeryBottom = y > 0.93;
    if (s.isFrontCamera && joint == 'hip' && !isVeryBottom) {
      return null;
    }
    final relaxLegCrop =
        intent == _PoseIntent.seated ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot;
    if (relaxLegCrop &&
        !isVeryBottom &&
        (joint == 'knee' || joint == 'ankle' || joint == 'hip')) {
      return null;
    }

    return switch (joint) {
      'knee' => CoachingResult(
        message: isVeryBottom ? '무릎이 프레임에 걸려요' : '무릎선에 걸릴 수 있어요',
        priority: CoachingPriority.composition,
        confidence: 0.92,
        reason: isVeryBottom ? '허벅지 중간이나 종아리까지 담아보세요' : '무릎선보다 살짝 위나 아래로 맞춰보세요',
      ),
      'ankle' => CoachingResult(
        message: isVeryBottom ? '발끝이 프레임에 걸려요' : '발목선에 걸려요',
        priority: CoachingPriority.composition,
        confidence: 0.92,
        reason: isVeryBottom ? '발끝 아래를 조금 더 담아보세요' : '발끝까지 담거나 종아리 중간에서 맞춰보세요',
      ),
      'hip' when s.shotType == ShotType.waistShot => const CoachingResult(
        message: '골반이 화면 끝에 걸려요',
        priority: CoachingPriority.composition,
        confidence: 0.85,
        reason: '프레임을 살짝 아래로 내려 골반 아래까지 담아보세요',
      ),
      _ => null,
    };
  }

  /// 전신 촬영 전용 구도 체크
  CoachingResult? _checkFullBodyComposition(
    PortraitSceneState s,
    _PoseIntent intent,
  ) {
    if (intent == _PoseIntent.seated ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot) {
      return null;
    }

    // (1) 양발 가시성: 전신인데 한쪽 발만 보이면 경고
    if (s.hasReliableAnkles &&
        !s.hasReliableBothAnkles &&
        s.personBboxRatio >= 0.16) {
      return const CoachingResult(
        message: '양발이 모두 보이면 좋아요',
        priority: CoachingPriority.composition,
        confidence: 0.82,
        reason: '양발을 모두 담아 더 안정적으로 맞춰보세요',
      );
    }

    // (2) 발 아래 공간
    if (s.hasReliableAnkles && s.footSpaceRatio < 0.04) {
      return const CoachingResult(
        message: '발끝 아래 여유가 좁아요',
        priority: CoachingPriority.composition,
        confidence: 0.85,
        reason: '발끝 아래를 조금 더 담아보세요',
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
          message: '폰 높이를 조금 낮춰보세요',
          priority: CoachingPriority.composition,
          confidence: 0.72,
          reason: '허리쯤 높이에서 찍으면 더 안정적이에요',
        );
      }
    }

    return null;
  }

  /// 무릎샷 전용 구도 체크
  CoachingResult? _checkKneeShotComposition(
    PortraitSceneState s,
    _PoseIntent intent,
  ) {
    if (intent == _PoseIntent.seated ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot) {
      return null;
    }
    if (!s.hasReliableKnees) return null;

    // 무릎이 프레임 하단 가까이에 있으면 관절 커팅 위험
    final lk = s.leftKneePosition?.dy;
    final rk = s.rightKneePosition?.dy;
    final kneeY = (lk != null && rk != null) ? (lk > rk ? lk : rk) : lk ?? rk;

    if (kneeY != null && kneeY > 0.82) {
      return const CoachingResult(
        message: '무릎선에 걸려요',
        priority: CoachingPriority.composition,
        confidence: 0.88,
        reason: '무릎선보다 살짝 위나 아래로 프레임을 맞춰보세요',
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
  CoachingResult? _checkRuleAlignment(
    PortraitSceneState s,
    _PoseIntent intent,
  ) {
    if (intent == _PoseIntent.selfie ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot ||
        intent == _PoseIntent.seated) {
      return null;
    }
    // 인물의 대표 y좌표: 눈 중점 → 얼굴 중심 → 0.5 fallback.
    final subjectY = s.eyeMidpoint?.dy ?? (s.hasFace ? s.faceCenterY : 0.5);
    final subject = Offset(s.personCenterX, subjectY);
    if (_rule.type == CompositionRuleType.none) {
      // 기존 휴리스틱: 중앙(0.42~0.58) 안에 있으면 좌우 한쪽으로 이동 권장.
      if (s.personCenterX > 0.42 && s.personCenterX < 0.58) {
        return const CoachingResult(
          message: '인물을 화면 한쪽에 살짝 배치해보세요.',
          priority: CoachingPriority.composition,
          confidence: 0.65,
          reason: '중앙에서 살짝 벗어나면 더 자연스러워요',
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
      reason: '선택한 구도에 맞춰보세요',
    );
  }

  CoachingResult? _checkEyePosition(
    double eyeY,
    ShotType shot,
    _PoseIntent intent,
  ) {
    if (intent == _PoseIntent.selfie ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot) {
      return null;
    }
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
        // Head shots on front-camera selfies often sit slightly lower
        // than the ideal eye line while still feeling natural.
        tolerance = 0.10;
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

    if (intent == _PoseIntent.seated) {
      tolerance += 0.05;
      targetY += 0.02;
    } else if (intent == _PoseIntent.couple) {
      tolerance += 0.03;
    }

    if ((eyeY - targetY).abs() <= tolerance) return null;

    return CoachingResult(
      message: eyeY < targetY ? '프레임을 살짝 위로 맞춰보세요.' : '프레임을 살짝 아래로 맞춰보세요.',
      priority: CoachingPriority.composition,
      confidence: 0.8,
      reason: '눈 위치가 맞으면 더 자연스러워요',
    );
  }

  CoachingResult? _checkHeadroom(
    double headroom,
    ShotType shot,
    _PoseIntent intent,
    {required bool isFrontCamera, required double footSpace}
  ) {
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
        maxH = 0.14;
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

    if (intent == _PoseIntent.seated) {
      minH = math.max(0.0, minH - 0.03);
      maxH += 0.05;
    } else if (intent == _PoseIntent.selfie ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot) {
      minH = math.max(0.0, minH - 0.04);
      maxH += 0.06;
    } else if (intent == _PoseIntent.couple) {
      minH = math.max(0.0, minH - 0.02);
      maxH += 0.03;
    }

    if (!isFrontCamera) {
      maxH += switch (shot) {
        ShotType.extremeCloseUp => 0.03,
        ShotType.closeUp => 0.04,
        ShotType.headShot => 0.06,
        ShotType.upperBody => 0.07,
        ShotType.waistShot => 0.08,
        ShotType.kneeShot || ShotType.fullBody => 0.08,
        ShotType.environmental ||
        ShotType.groupShot ||
        ShotType.unknown => 0.0,
      };

      if (shot == ShotType.waistShot && footSpace < 0.18) {
        maxH += 0.04;
      }
    }

    if (headroom < minH) {
      return const CoachingResult(
        message: '머리 위가 좁아요',
        priority: CoachingPriority.composition,
        confidence: 0.85,
        reason: '폰을 살짝 올려 여유를 만들어보세요',
      );
    }
    if (headroom > maxH) {
      if (!isFrontCamera) {
        return const CoachingResult(
          message: '머리 위 공간이 조금 많아요',
          priority: CoachingPriority.composition,
          confidence: 0.58,
          reason: '거리는 유지하고 프레임을 살짝 아래로 맞춰보세요',
        );
      }
      return const CoachingResult(
        message: '머리 위가 너무 비었어요. 한 걸음 다가가보세요.',
        priority: CoachingPriority.composition,
        confidence: 0.75,
      );
    }
    return null;
  }

  bool _shouldSkipGenericHeadroomForSelfieCloseShot(
    PortraitSceneState s,
    _PoseIntent intent,
  ) {
    if (!s.isFrontCamera || intent != _PoseIntent.selfie) return false;
    return s.shotType == ShotType.extremeCloseUp ||
        s.shotType == ShotType.closeUp ||
        s.shotType == ShotType.headShot;
  }

  CoachingResult? _evaluatePose(PortraitSceneState s, _PoseIntent intent) {
    final relaxedBodyPose =
        intent == _PoseIntent.seated ||
        intent == _PoseIntent.selfie ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot;

    // 어깨 각도: headShot 포함 어깨가 보이는 샷 전체 적용
    final checkShoulder =
        s.shotType == ShotType.headShot ||
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
          reason: '몸이 덜 납작해 보여요',
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
    final checkArm =
        s.shotType == ShotType.upperBody ||
        s.shotType == ShotType.waistShot ||
        s.shotType == ShotType.kneeShot ||
        s.shotType == ShotType.fullBody;

    if (checkArm &&
        !relaxedBodyPose &&
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
          reason: '팔 라인이 더 잘 보여요',
        );
      }
    }

    // fullBody/kneeShot: 발 간격 체크 (어깨 너비 대비)
    if ((s.shotType == ShotType.fullBody || s.shotType == ShotType.kneeShot) &&
        !relaxedBodyPose &&
        s.hasReliableBothAnkles &&
        s.ankleSpacingRatio != null) {
      if (s.ankleSpacingRatio! < 0.3) {
        return const CoachingResult(
          message: '발을 어깨 너비 정도로 벌려보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.68,
          reason: '발이 너무 모이면 자세가 불안정해 보여요',
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
        intent == _PoseIntent.standingBasic &&
        s.hasReliableKnees &&
        !s.hasContrapposto &&
        s.hasReliableAnkles) {
      return const CoachingResult(
        message: '한쪽 다리에 무게를 실어보세요.',
        priority: CoachingPriority.pose,
        confidence: 0.65,
        reason: '서 있는 자세가 더 자연스러워져요',
      );
    }

    final handFraming = _checkHandFraming(s);
    if (handFraming != null) return handFraming;

    return null;
  }

  CoachingResult? _checkHandFraming(PortraitSceneState s) {
    if (s.isFrontCamera || s.intent == PortraitIntent.environmental) {
      return null;
    }

    final handTouchesBottom =
        s.isBottomJointCut && s.bottomJoint == 'wrist';
    final wristTouchesSide = s.croppedJoints.contains('wrist');
    if (handTouchesBottom || wristTouchesSide) {
      return const CoachingResult(
        message: '손이 살짝 걸려요',
        priority: CoachingPriority.refinement,
        confidence: 0.58,
        reason: '손 전체를 넣거나 과감히 빼면 더 자연스러워요',
      );
    }

    if (s.croppedJoints.contains('elbow')) {
      return const CoachingResult(
        message: '팔꿈치가 프레임에 걸려요',
        priority: CoachingPriority.refinement,
        confidence: 0.56,
        reason: '팔꿈치보다 팔 중간에서 맞추면 더 자연스러워요',
      );
    }

    return null;
  }

  CoachingResult? _evaluateFaceDirection(
    PortraitSceneState s,
    _PoseIntent intent,
  ) {
    if (!s.hasFace) return null;

    final deferGenericFaceAngleToSelfie =
        s.isFrontCamera && intent == _PoseIntent.selfie;
    final relaxedSelfieLike =
        intent == _PoseIntent.selfie ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot;
    final highPitchThreshold = relaxedSelfieLike ? 28.0 : 20.0;
    final midPitchThreshold = relaxedSelfieLike ? 16.0 : 10.0;
    final lowPitchThreshold = relaxedSelfieLike ? -22.0 : -15.0;
    if (!deferGenericFaceAngleToSelfie &&
        s.facePitch != null &&
        s.facePitch! > highPitchThreshold) {
      return const CoachingResult(
        message: '턱이 많이 올라갔어요. 살짝 당겨주세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.72,
      );
    }

    if (!deferGenericFaceAngleToSelfie &&
        s.facePitch != null &&
        s.facePitch! > midPitchThreshold) {
      return const CoachingResult(
        message: '턱을 조금 내려주세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.65,
      );
    }

    if (!deferGenericFaceAngleToSelfie &&
        s.facePitch != null &&
        s.facePitch! < lowPitchThreshold) {
      return const CoachingResult(
        message: '턱을 조금 올려주세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.6,
      );
    }

    if (s.faceRoll != null && s.faceRoll!.abs() > 28) {
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
        message: '얼굴 방향이 좋아요.',
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
      message: s.isFrontCamera ? '흔들려요. 팔꿈치를 몸에 붙여보세요.' : '흔들려요. 잠시 멈추고 찍어보세요.',
      priority: CoachingPriority.composition,
      confidence: 0.82,
    );
  }

  // ─── 셀카 모드 전용 코칭 ─────────────────────────────

  CoachingResult? _evaluateSelfie(PortraitSceneState s, _PoseIntent intent) {
    final relaxedSelfie =
        intent == _PoseIntent.selfie ||
        intent == _PoseIntent.fashion ||
        intent == _PoseIntent.casualSnapshot;

    // ── 1. 광각 왜곡 경고 (전면 카메라 = 광각, 가까울수록 왜곡 심함) ──
    if (s.personBboxRatio > 0.90) {
      return const CoachingResult(
        message: '너무 가까워요',
        priority: CoachingPriority.composition,
        confidence: 0.88,
        reason: '팔을 조금 더 뻗으면 자연스러워요',
      );
    }
    if (s.faceBoxRatio > 0.32 &&
        (s.shotType == ShotType.closeUp ||
            s.shotType == ShotType.headShot ||
            s.shotType == ShotType.extremeCloseUp)) {
      return const CoachingResult(
        message: '얼굴이 너무 크게 잡혀요',
        priority: CoachingPriority.composition,
        confidence: 0.80,
        reason: '조금 더 떨어져 자연스럽게 맞춰보세요',
      );
    }

    // ── 2. 역광 (셀카에서도 중요) ─────────────────────────
    if (s.lightingCondition == LightingCondition.back &&
        s.lightingConfidence > 0.7) {
      return const CoachingResult(
        message: '역광이에요',
        priority: CoachingPriority.composition,
        confidence: 0.85,
        reason: '빛을 향해 살짝 돌아서보세요',
      );
    }

    // ── 3. 카메라 높이 (셀카 핵심!) ───────────────────────
    // pitch > 0: 턱 올라감 = 카메라가 아래에 있음 (올려다보는 중)
    // pitch < 0: 턱 내려감 = 카메라가 위에 있음 (내려다보는 중)
    // 이상적: 카메라가 눈높이 살짝 위 → pitch 약간 양수(5~15°)
    if (s.facePitch != null) {
      if (s.facePitch! < -20) {
        // 카메라가 아래에 있음 → 이중턱, 불리한 각도
        return const CoachingResult(
          message: '폰을 조금 올려보세요',
          priority: CoachingPriority.composition,
          confidence: 0.85,
          reason: '눈높이보다 살짝 위가 더 자연스러워요',
        );
      }
      if (s.facePitch! > (relaxedSelfie ? 32 : 25)) {
        // 카메라가 너무 위에 있음 → 부자연스러운 시선
        return const CoachingResult(
          message: '폰이 조금 높아요',
          priority: CoachingPriority.composition,
          confidence: 0.78,
          reason: '눈높이보다 살짝 위로 내려보세요',
        );
      }
    }

    // ── 4. 셀카 조명 (순광에 더 관대) ─────────────────────
    final lighting = _evaluateSelfieLighting(s);
    if (lighting != null) return lighting;

    // ── 5. 헤드룸 ────────────────────────────────────────
    if (s.hasPose || s.hasNose) {
      if (s.headroomRatio < (relaxedSelfie ? 0.025 : 0.04)) {
        return const CoachingResult(
          message: '얼굴 가장자리가 잘려요',
          priority: CoachingPriority.composition,
          confidence: 0.80,
          reason: '폰을 조금 멀리해 얼굴 전체가 들어오게 맞춰보세요',
        );
      }
      if (s.headroomRatio > (relaxedSelfie ? 0.24 : 0.18)) {
        return const CoachingResult(
          message: '머리 위가 많이 비었어요',
          priority: CoachingPriority.composition,
          confidence: 0.65,
          reason: '폰을 조금 가까이 해보세요',
        );
      }
    }

    // ── 6. 얼굴 각도 (3/4 뷰가 최적) ─────────────────────
    final selfieAngle = _evaluateSelfieAngle(s);
    if (selfieAngle != null) return selfieAngle;

    if (s.faceYaw != null) {
      if (s.faceYaw!.abs() > (relaxedSelfie ? 48 : 40)) {
        return const CoachingResult(
          message: '고개를 너무 많이 돌렸어요. 살짝만 돌려보세요.',
          priority: CoachingPriority.pose,
          confidence: 0.75,
        );
      }
      if (!relaxedSelfie && s.faceYaw!.abs() < 5) {
        return const CoachingResult(
          message: '살짝 고개를 돌리면 입체감이 생겨요.',
          priority: CoachingPriority.pose,
          confidence: 0.62,
          reason: '완전 정면보다 조금 돌린 얼굴이 자연스러워요',
        );
      }
    }

    // ── 7. 턱 라인 트릭 (프로 인물사진 핵심) ───────────────
    // 카메라 높이가 적절하고 다른 이슈 없을 때 턱 포워드 제안
    if (s.facePitch != null && s.facePitch! >= -5 && s.facePitch! <= 10) {
      return const CoachingResult(
        message: '턱선을 살짝 살려보세요',
        priority: CoachingPriority.refinement,
        confidence: 0.45,
        reason: '턱을 조금 앞으로 내밀면 또렷해져요',
      );
    }

    // ── 8. 고개 기울기 ───────────────────────────────────
    if (s.faceRoll != null && s.faceRoll!.abs() > (relaxedSelfie ? 28 : 20)) {
      return const CoachingResult(
        message: '고개가 기울었어요. 바로 세워보세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.7,
      );
    }

    return null;
  }

  CoachingResult? _evaluateSelfieAngle(PortraitSceneState s) {
    if (!s.isFrontCamera || !s.hasFace) return null;

    final yaw = s.faceYaw?.abs();
    final pitch = s.facePitch;
    final roll = s.faceRoll?.abs();

    if (yaw != null && yaw < 8) {
      return const CoachingResult(
        message: '얼굴을 살짝만 옆으로 틀어보세요.',
        priority: CoachingPriority.pose,
        confidence: 0.64,
        reason: '정면보다 살짝 틀어진 각도가 셀카에 더 자연스러워요',
      );
    }

    if (yaw != null && yaw > 32) {
      return const CoachingResult(
        message: '얼굴을 정면 쪽으로 조금만 돌려보세요.',
        priority: CoachingPriority.pose,
        confidence: 0.66,
        reason: '너무 옆을 보면 얼굴선이 강해 보여요',
      );
    }

    if (pitch != null && pitch < -12) {
      return const CoachingResult(
        message: '폰을 눈높이에 조금 더 가깝게 맞춰보세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.60,
        reason: '눈높이보다 살짝 위 각도가 셀카에 가장 자연스러워요',
      );
    }

    if (pitch != null && pitch > 12) {
      return const CoachingResult(
        message: '폰을 조금만 더 높여보세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.60,
        reason: '아래에서 올려다보는 각도보다 살짝 위가 더 안정적이에요',
      );
    }

    if (roll != null && roll > 18) {
      return const CoachingResult(
        message: '고개 기울임을 조금만 줄여보세요.',
        priority: CoachingPriority.refinement,
        confidence: 0.58,
        reason: '앵글은 좋고 기울기만 정리되면 더 자연스러워요',
      );
    }

    if (yaw != null &&
        pitch != null &&
        roll != null &&
        yaw >= 12 &&
        yaw <= 28 &&
        pitch >= -12 &&
        pitch <= 8 &&
        roll <= 18) {
      return const CoachingResult(
        message: '셀카 앵글이 좋아요',
        priority: CoachingPriority.refinement,
        confidence: 0.58,
        reason: '빛과 거리까지 맞으면 더 자연스러워요',
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
            message: '빛이 좋아요',
            priority: CoachingPriority.refinement,
            confidence: 0.55,
            reason: '얼굴을 살짝 돌리면 더 자연스러워요',
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
          message: '빛 방향을 맞춰보세요',
          priority: CoachingPriority.refinement,
          confidence: 0.60,
          reason: '빛 쪽으로 살짝 고개를 돌려보세요',
        );
      case LightingCondition.rim:
        return const CoachingResult(
          message: '뒤쪽 빛이 강해요',
          priority: CoachingPriority.composition,
          confidence: 0.65,
          reason: '얼굴을 빛 쪽으로 조금 돌려보세요',
        );
      case LightingCondition.back:
        return null; // 역광은 이미 위에서 처리됨
      case LightingCondition.unknown:
        return null;
    }
  }

  CoachingResult _selfieFallbackResult(PortraitSceneState s) {
    final goodAngle =
        s.faceYaw != null &&
        s.facePitch != null &&
        s.faceRoll != null &&
        s.faceYaw!.abs() >= 12 &&
        s.faceYaw!.abs() <= 28 &&
        s.facePitch! >= -12 &&
        s.facePitch! <= 8 &&
        s.faceRoll!.abs() <= 18;
    final goodLighting =
        s.lightingCondition == LightingCondition.short &&
        s.lightingConfidence > 0.5;

    if (goodAngle && goodLighting) {
      return const CoachingResult(
        message: '셀카 조명과 앵글이 좋아요',
        priority: CoachingPriority.perfect,
        confidence: 0.84,
        reason: '지금 상태로 찍어도 자연스럽게 나와요',
      );
    }

    if (goodLighting) {
      return const CoachingResult(
        message: '빛이 좋아요',
        priority: CoachingPriority.refinement,
        confidence: 0.56,
        reason: '얼굴 각도만 조금 더 맞춰보세요',
      );
    }

    if (_enableSmileCoaching && s.isSmiling) {
      return const CoachingResult(
        message: '자연스러운 미소가 좋아요',
        priority: CoachingPriority.refinement,
        confidence: 0.55,
      );
    }

    return const CoachingResult(
      message: '각도와 빛을 조금 더 맞춰볼게요',
      priority: CoachingPriority.refinement,
      confidence: 0.42,
      reason: '얼굴이 또렷해지면 좋은 타이밍을 알려드릴게요',
    );
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
        reason: '정면으로만 서면 조금 밋밋해 보여요',
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
        message: '빛과 자세가 좋아요. 지금 찍기 좋아요.',
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
        message: '배경 빛이 좋아요. 사람 윤곽을 살려보세요.',
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
      return '빛 방향이 좋은 구도예요!';
    }

    switch (s.shotType) {
      case ShotType.extremeCloseUp:
        return '인상적인 클로즈업이에요!';
      case ShotType.fullBody:
        return '멋진 전신 구도예요! 발끝까지 잘 담겼어요.';
      case ShotType.kneeShot:
        return '좋은 무릎샷이에요! 화면에 자연스럽게 담겼어요.';
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
