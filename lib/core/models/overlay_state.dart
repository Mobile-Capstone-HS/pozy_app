import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/enums/scene_type.dart';

class OverlayState {
  const OverlayState({
    required this.resolvedScene,
    required this.manualScene,
    required this.personDetected,
    required this.isPerfect,
    required this.score,
    required this.headline,
    required this.detail,
    required this.movementHint,
    required this.targetLocked,
    required this.classificationSource,
    required this.classificationConfidence,
    required this.labelPreview,
    required this.alignmentLevel,
    this.subjectPosition,
    this.targetPosition,
    this.boundingBox,
  });

  final SceneType resolvedScene;
  final SceneType manualScene;
  final bool personDetected;
  final bool isPerfect;
  final double score;
  final String headline;
  final String detail;
  final String movementHint;
  final bool targetLocked;
  final String classificationSource;
  final double classificationConfidence;
  final String labelPreview;
  final String alignmentLevel; // far / near / perfect
  final Offset? subjectPosition;
  final Offset? targetPosition;
  final Rect? boundingBox;

  bool get hasSubject => subjectPosition != null;
  bool get hasTarget => targetPosition != null;

  factory OverlayState.initial() {
    return const OverlayState(
      resolvedScene: SceneType.object,
      manualScene: SceneType.object,
      personDetected: false,
      isPerfect: false,
      score: 0,
      headline: '카메라 준비 중',
      detail: '사람 / 음식 / 사물 중 하나를 고르고 시작해.',
      movementHint: '타깃 점을 탭해서 원하는 구도 포인트를 고정할 수 있어.',
      targetLocked: false,
      classificationSource: 'none',
      classificationConfidence: 0,
      labelPreview: '',
      alignmentLevel: 'far',
    );
  }

  OverlayState copyWith({
    SceneType? resolvedScene,
    SceneType? manualScene,
    bool? personDetected,
    bool? isPerfect,
    double? score,
    String? headline,
    String? detail,
    String? movementHint,
    bool? targetLocked,
    String? classificationSource,
    double? classificationConfidence,
    String? labelPreview,
    String? alignmentLevel,
    Offset? subjectPosition,
    Offset? targetPosition,
    Rect? boundingBox,
    bool clearSubjectPosition = false,
    bool clearTargetPosition = false,
    bool clearBoundingBox = false,
  }) {
    return OverlayState(
      resolvedScene: resolvedScene ?? this.resolvedScene,
      manualScene: manualScene ?? this.manualScene,
      personDetected: personDetected ?? this.personDetected,
      isPerfect: isPerfect ?? this.isPerfect,
      score: score ?? this.score,
      headline: headline ?? this.headline,
      detail: detail ?? this.detail,
      movementHint: movementHint ?? this.movementHint,
      targetLocked: targetLocked ?? this.targetLocked,
      classificationSource: classificationSource ?? this.classificationSource,
      classificationConfidence:
          classificationConfidence ?? this.classificationConfidence,
      labelPreview: labelPreview ?? this.labelPreview,
      alignmentLevel: alignmentLevel ?? this.alignmentLevel,
      subjectPosition: clearSubjectPosition
          ? null
          : (subjectPosition ?? this.subjectPosition),
      targetPosition:
          clearTargetPosition ? null : (targetPosition ?? this.targetPosition),
      boundingBox: clearBoundingBox ? null : (boundingBox ?? this.boundingBox),
    );
  }
}