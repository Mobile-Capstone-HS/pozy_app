/// 인물 모드 코칭 규칙 엔진
///
/// PortraitSceneState를 받아서 우선순위가 가장 높은
/// 코칭 메시지 하나를 반환합니다.
library;

import 'portrait_scene_state.dart';

class PortraitCoachEngine {
  /// 최소 키포인트 신뢰도 — 이 값 미만이면 해당 코칭을 건너뜀
  static const double _minConfidence = 0.5;

  /// 장면 상태를 평가해서 가장 중요한 코칭 하나를 반환합니다.
  /// 모든 규칙을 통과하면 "좋은 구도예요!" 를 반환합니다.
  CoachingResult evaluate(PortraitSceneState state) {
    // ──────────────────────────────────────────────
    // P1: 치명적 문제 (반드시 먼저 해결해야 하는 것)
    // ──────────────────────────────────────────────

    if (state.personCount == 0) {
      return const CoachingResult(
        message: '사람이 보이지 않아요',
        priority: CoachingPriority.critical,
        confidence: 1.0,
      );
    }

    // 최소 키포인트 가시성 체크 — 코+눈 또는 어깨가 보여야 코칭 시작
    if (!state.hasNose && !state.hasEyes && !state.hasShoulders) {
      return const CoachingResult(
        message: '얼굴이나 상체를 더 보여주세요',
        priority: CoachingPriority.critical,
        confidence: 0.95,
      );
    }

    // 키포인트가 너무 적으면 (이마만 보이는 등) 더 보여달라고 요청
    if (state.visibleKeypointCount < 3) {
      return const CoachingResult(
        message: '조금 더 뒤로 가주세요',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    if (state.areEyesClosed) {
      return const CoachingResult(
        message: '눈을 감고 계세요',
        priority: CoachingPriority.critical,
        confidence: 0.9,
      );
    }

    if (state.lightingCondition == LightingCondition.back &&
        state.lightingConfidence > 0.6) {
      return const CoachingResult(
        message: '역광이에요, 방향을 바꿔보세요',
        priority: CoachingPriority.critical,
        confidence: 0.85,
      );
    }

    if (state.lightingCondition == LightingCondition.side &&
        state.lightingConfidence > 0.7) {
      return const CoachingResult(
        message: '측면에서 빛이 강해요',
        priority: CoachingPriority.critical,
        confidence: 0.75,
      );
    }

    // ──────────────────────────────────────────────
    // P2: 구도 문제
    // ──────────────────────────────────────────────

    // 관절 크로핑 체크
    if (state.isJointCropped) {
      return const CoachingResult(
        message: '관절이 잘리고 있어요, 조금 뒤로',
        priority: CoachingPriority.composition,
        confidence: 0.9,
      );
    }

    // 눈 위치가 삼분할 라인에서 벗어남
    if (state.eyeMidpoint != null && state.eyeConfidence > _minConfidence) {
      final eyeY = state.eyeMidpoint!.dy;
      const thirdLine = 1.0 / 3.0;
      final deviation = (eyeY - thirdLine).abs();

      if (deviation > 0.12) {
        final message = eyeY < thirdLine
            ? '카메라를 살짝 내려보세요'
            : '카메라를 살짝 올려보세요';
        return CoachingResult(
          message: message,
          priority: CoachingPriority.composition,
          confidence: 0.8,
        );
      }
    }

    // 헤드룸 체크
    if (state.headroomRatio < 0.05 && state.hasPose) {
      return const CoachingResult(
        message: '머리 위 공간이 부족해요',
        priority: CoachingPriority.composition,
        confidence: 0.85,
      );
    }

    if (state.headroomRatio > 0.25 && state.hasPose) {
      return const CoachingResult(
        message: '머리 위 공간이 너무 많아요',
        priority: CoachingPriority.composition,
        confidence: 0.8,
      );
    }

    // 전신 촬영 시 풋스페이스 체크
    if (state.shotType == ShotType.fullBody) {
      if (state.footSpaceRatio < 0.03) {
        return const CoachingResult(
          message: '발 아래 공간을 좀 더 남겨주세요',
          priority: CoachingPriority.composition,
          confidence: 0.8,
        );
      }
    }

    // ──────────────────────────────────────────────
    // P3: 포즈 문제
    // ──────────────────────────────────────────────

    // 어깨가 너무 수평 (자연스럽지 않음)
    if (state.shoulderAngleDeg != null &&
        state.shoulderConfidence > _minConfidence) {
      if (state.shoulderAngleDeg!.abs() < 3) {
        return const CoachingResult(
          message: '어깨를 살짝 틀어보세요',
          priority: CoachingPriority.pose,
          confidence: 0.75,
        );
      }
    }

    // 왼팔이 몸에 붙어있음
    if (state.leftArmBodyGap != null &&
        state.elbowConfidence > _minConfidence) {
      if (state.leftArmBodyGap! < 0.02) {
        return const CoachingResult(
          message: '왼팔을 몸에서 살짝 떼어보세요',
          priority: CoachingPriority.pose,
          confidence: 0.7,
        );
      }
    }

    // 오른팔이 몸에 붙어있음
    if (state.rightArmBodyGap != null &&
        state.elbowConfidence > _minConfidence) {
      if (state.rightArmBodyGap! < 0.02) {
        return const CoachingResult(
          message: '오른팔을 몸에서 살짝 떼어보세요',
          priority: CoachingPriority.pose,
          confidence: 0.7,
        );
      }
    }

    // ──────────────────────────────────────────────
    // P4: 세부 조정
    // ──────────────────────────────────────────────

    // 완전 정면 — 살짝 돌리면 더 자연스러움
    if (state.faceYaw != null && state.hasFace) {
      if (state.faceYaw!.abs() < 5) {
        return const CoachingResult(
          message: '고개를 살짝 돌려보세요',
          priority: CoachingPriority.refinement,
          confidence: 0.6,
        );
      }
    }

    // 고개가 너무 기울어짐
    if (state.faceRoll != null && state.hasFace) {
      if (state.faceRoll!.abs() > 15) {
        return const CoachingResult(
          message: '고개를 바로 해주세요',
          priority: CoachingPriority.refinement,
          confidence: 0.7,
        );
      }
    }

    // 턱이 너무 올라감
    if (state.facePitch != null && state.hasFace) {
      if (state.facePitch! > 15) {
        return const CoachingResult(
          message: '턱을 살짝 당겨주세요',
          priority: CoachingPriority.refinement,
          confidence: 0.65,
        );
      }
    }

    // ──────────────────────────────────────────────
    // P5: 모든 규칙 통과!
    // ──────────────────────────────────────────────

    // "좋은 구도"는 최소한 눈+어깨가 보여야 판정
    if (!state.hasEyes || !state.hasShoulders) {
      return const CoachingResult(
        message: '상체를 조금 더 보여주세요',
        priority: CoachingPriority.composition,
        confidence: 0.7,
      );
    }

    return const CoachingResult(
      message: '좋은 구도예요! 📸',
      priority: CoachingPriority.perfect,
      confidence: 1.0,
    );
  }
}
