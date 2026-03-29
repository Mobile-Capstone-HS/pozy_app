/// 인물 모드 실시간 코칭을 위한 장면 상태 데이터 클래스
///
/// ML Kit Pose, ML Kit Face, 밝기 분석의 결과를 하나로 모아서
/// 코칭 엔진에 전달합니다.
library;

import 'dart:ui';

// ─── 샷 타입 ────────────────────────────────────────────────

enum ShotType {
  closeUp,    // 클로즈업 (얼굴 + 어깨)
  upperBody,  // 상반신 (허리 위)
  fullBody,   // 전신
  unknown,
}

// ─── 조명 상태 ──────────────────────────────────────────────

enum LightingCondition {
  normal,    // 순광 / 확산광 (정상)
  side,      // 측광
  back,      // 역광
  unknown,
}

// ─── 코칭 우선순위 ──────────────────────────────────────────

enum CoachingPriority {
  critical,    // P1: 역광, 사람 없음, 눈 감음
  composition, // P2: 구도 문제
  pose,        // P3: 포즈 문제
  refinement,  // P4: 세부 조정
  perfect,     // P5: 모든 규칙 통과
}

// ─── 코칭 결과 ──────────────────────────────────────────────

class CoachingResult {
  final String message;
  final CoachingPriority priority;
  final double confidence;

  const CoachingResult({
    required this.message,
    required this.priority,
    required this.confidence,
  });
}

// ─── 장면 상태 ──────────────────────────────────────────────

class PortraitSceneState {
  // 기본 정보
  final int personCount;
  final ShotType shotType;

  // 얼굴 데이터 (ML Kit Face Detection)
  final double? faceYaw;           // 좌우 회전 (-45 ~ +45)
  final double? facePitch;         // 상하 기울기
  final double? faceRoll;          // 갸웃한 각도
  final double? smileProbability;  // 웃음 확률 (0.0 ~ 1.0)
  final double? leftEyeOpenProb;   // 왼눈 뜬 확률
  final double? rightEyeOpenProb;  // 오른눈 뜬 확률

  // 포즈 데이터 (ML Kit Pose Detection)
  final double? shoulderAngleDeg;  // 어깨 기울기 (도)
  final double? leftArmBodyGap;    // 왼팔-몸통 거리 (정규화 0~1)
  final double? rightArmBodyGap;   // 오른팔-몸통 거리 (정규화 0~1)
  final Offset? eyeMidpoint;       // 눈 중심 좌표 (정규화 0~1)
  final bool isJointCropped;       // 관절이 프레임 경계에 걸림
  final double headroomRatio;      // 머리 위 여백 비율 (0~1)
  final double footSpaceRatio;     // 발 아래 여백 비율 (0~1)

  // 키포인트 신뢰도 (낮은 키포인트 기반 코칭은 건너뜀)
  final double shoulderConfidence;
  final double elbowConfidence;
  final double eyeConfidence;

  // 키포인트 가시성 — 17개 중 감지된 개수/비율
  final int visibleKeypointCount;    // 감지된 키포인트 수 (0~17)
  final bool hasNose;
  final bool hasEyes;                // 양쪽 눈 모두 감지
  final bool hasShoulders;           // 양쪽 어깨 모두 감지

  // 조명 데이터
  final LightingCondition lightingCondition;
  final double lightingConfidence; // 조명 판단의 확신도

  const PortraitSceneState({
    this.personCount = 0,
    this.shotType = ShotType.unknown,
    // 얼굴
    this.faceYaw,
    this.facePitch,
    this.faceRoll,
    this.smileProbability,
    this.leftEyeOpenProb,
    this.rightEyeOpenProb,
    // 포즈
    this.shoulderAngleDeg,
    this.leftArmBodyGap,
    this.rightArmBodyGap,
    this.eyeMidpoint,
    this.isJointCropped = false,
    this.headroomRatio = 0.0,
    this.footSpaceRatio = 0.0,
    // 키포인트 신뢰도
    this.shoulderConfidence = 0.0,
    this.elbowConfidence = 0.0,
    this.eyeConfidence = 0.0,
    // 키포인트 가시성
    this.visibleKeypointCount = 0,
    this.hasNose = false,
    this.hasEyes = false,
    this.hasShoulders = false,
    // 조명
    this.lightingCondition = LightingCondition.unknown,
    this.lightingConfidence = 0.0,
  });

  /// 눈이 감겨있는지 판단
  bool get areEyesClosed =>
      leftEyeOpenProb != null &&
      rightEyeOpenProb != null &&
      leftEyeOpenProb! < 0.3 &&
      rightEyeOpenProb! < 0.3;

  /// 얼굴이 감지되었는지
  bool get hasFace => faceYaw != null;

  /// 포즈가 감지되었는지
  bool get hasPose => shoulderAngleDeg != null;
}
