import 'package:pose_camera_app/coaching/coaching_result.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class LandscapeUiState {
  final CompositionDecision? decision;
  final LandscapeOverlayAdvice overlayAdvice;
  final double currentZoom;
  final double selectedZoom;
  final bool isFrontCamera;
  final String guidance;
  final String? subGuidance;
  final CoachingLevel coachingLevel;

  const LandscapeUiState({
    required this.decision,
    required this.overlayAdvice,
    required this.currentZoom,
    required this.selectedZoom,
    required this.isFrontCamera,
    required this.guidance,
    required this.subGuidance,
    required this.coachingLevel,
  });

  const LandscapeUiState.initial()
    : decision = null,
      overlayAdvice = const LandscapeOverlayAdvice.none(),
      currentZoom = 1.0,
      selectedZoom = 1.0,
      isFrontCamera = false,
      guidance = '구도를 분석 중입니다.',
      subGuidance = null,
      coachingLevel = CoachingLevel.caution;

  LandscapeUiState copyWith({
    CompositionDecision? decision,
    LandscapeOverlayAdvice? overlayAdvice,
    double? currentZoom,
    double? selectedZoom,
    bool? isFrontCamera,
    String? guidance,
    String? subGuidance,
    CoachingLevel? coachingLevel,
    bool clearDecision = false,
    bool clearSubGuidance = false,
  }) {
    return LandscapeUiState(
      decision: clearDecision ? null : (decision ?? this.decision),
      overlayAdvice: overlayAdvice ?? this.overlayAdvice,
      currentZoom: currentZoom ?? this.currentZoom,
      selectedZoom: selectedZoom ?? this.selectedZoom,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      guidance: guidance ?? this.guidance,
      subGuidance: clearSubGuidance ? null : (subGuidance ?? this.subGuidance),
      coachingLevel: coachingLevel ?? this.coachingLevel,
    );
  }
}
