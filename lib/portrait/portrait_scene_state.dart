/// 인물 모드 실시간 코칭을 위한 장면 상태 데이터 클래스
///
/// YOLO Pose, ML Kit Face, 조명 분석의 결과를 하나로 모아서
/// 코칭 엔진에 전달합니다.
library;

import 'dart:ui';

// ─── 샷 타입 ────────────────────────────────────────────────

enum ShotType {
  extremeCloseUp,  // 익스트림 클로즈업 (얼굴 일부만)
  closeUp,         // 클로즈업 (얼굴 + 어깨)
  upperBody,       // 상반신 (허리 위)
  kneeShot,        // 무릎샷
  fullBody,        // 전신
  environmental,   // 환경 포트레이트 (인물 + 풍경)
  unknown,
}

// ─── 조명 상태 ──────────────────────────────────────────────

enum LightingCondition {
  normal,    // 순광 (front_light)
  short,     // 사광 (short_light, 가장 이상적)
  side,      // 측광 (side_light)
  rim,       // 역사광 (rim_light)
  back,      // 역광 (back_light)
  unknown,
}

// ─── 코칭 우선순위 ──────────────────────────────────────────

enum CoachingPriority {
  critical,    // P0~P1: 사람 없음, 눈 감음, 강한 역광
  composition, // P2~P3: 조명 개선, 구도 문제
  pose,        // P4: 포즈 문제
  refinement,  // P5: 세부 조정
  perfect,     // P6: 모든 규칙 통과 (칭찬)
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
  final double? faceYaw;
  final double? facePitch;
  final double? faceRoll;
  final double? smileProbability;
  final double? leftEyeOpenProb;
  final double? rightEyeOpenProb;
  final double faceCenterX;
  final double faceCenterY;
  final double faceBoxRatio;

  // 포즈 데이터 (YOLO Pose)
  final double? shoulderAngleDeg;
  final double? leftArmBodyGap;
  final double? rightArmBodyGap;
  final Offset? eyeMidpoint;
  final bool isJointCropped;
  final double headroomRatio;
  final double footSpaceRatio;

  // 인물 위치/크기
  final double personCenterX;      // 인물 중심 x좌표 (정규화 0~1)
  final double personBboxRatio;    // 인물 bbox / 프레임 면적 비율 (0~1)

  // 키포인트 신뢰도
  final double shoulderConfidence;
  final double elbowConfidence;
  final double eyeConfidence;

  // 키포인트 가시성
  final int visibleKeypointCount;
  final bool hasNose;
  final bool hasEyes;
  final bool hasShoulders;

  // 조명 데이터
  final LightingCondition lightingCondition;
  final double lightingConfidence;

  const PortraitSceneState({
    this.personCount = 0,
    this.shotType = ShotType.unknown,
    this.faceYaw,
    this.facePitch,
    this.faceRoll,
    this.smileProbability,
    this.leftEyeOpenProb,
    this.rightEyeOpenProb,
    this.faceCenterX = 0.5,
    this.faceCenterY = 0.33,
    this.faceBoxRatio = 0.0,
    this.shoulderAngleDeg,
    this.leftArmBodyGap,
    this.rightArmBodyGap,
    this.eyeMidpoint,
    this.isJointCropped = false,
    this.headroomRatio = 0.0,
    this.footSpaceRatio = 0.0,
    this.personCenterX = 0.5,
    this.personBboxRatio = 0.0,
    this.shoulderConfidence = 0.0,
    this.elbowConfidence = 0.0,
    this.eyeConfidence = 0.0,
    this.visibleKeypointCount = 0,
    this.hasNose = false,
    this.hasEyes = false,
    this.hasShoulders = false,
    this.lightingCondition = LightingCondition.unknown,
    this.lightingConfidence = 0.0,
  });

  bool get areEyesClosed =>
      leftEyeOpenProb != null &&
      rightEyeOpenProb != null &&
      leftEyeOpenProb! < 0.3 &&
      rightEyeOpenProb! < 0.3;

  bool get isOneEyeClosed =>
      leftEyeOpenProb != null &&
      rightEyeOpenProb != null &&
      !areEyesClosed &&
      (leftEyeOpenProb! < 0.3 || rightEyeOpenProb! < 0.3);

  bool get isSmiling =>
      smileProbability != null && smileProbability! >= 0.65;

  bool get hasFace => faceYaw != null;
  bool get hasPose => shoulderAngleDeg != null;
}
