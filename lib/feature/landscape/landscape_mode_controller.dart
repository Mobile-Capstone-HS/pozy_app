import 'package:pose_camera_app/coaching/coaching_result.dart';
import 'package:pose_camera_app/feature/landscape/landscape_ui_state.dart';
import 'package:pose_camera_app/segmentation/composition_engine.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/composition_summary.dart';
import 'package:pose_camera_app/segmentation/composition_temporal_filter.dart';
import 'package:pose_camera_app/segmentation/fastscnn_view.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class LandscapeModeController {
  final CompositionEngine _compositionEngine = CompositionEngine();
  final CompositionResolver _resolver = const CompositionResolver();
  final CompositionTemporalFilter _temporalFilter = CompositionTemporalFilter();

  void reset() {
    _compositionEngine.reset();
    _temporalFilter.reset();
  }

  LandscapeUiState processFrame(
    FastScnnFrame frame, {
    required LandscapeUiState currentState,
  }) {
    final raw = LandscapeAnalyzer.analyzeFeatures(frame.result);
    final smoothed = _temporalFilter.smooth(raw);
    final decision = _temporalFilter.stabilize(_resolver.resolve(smoothed));
    final summary = _compositionEngine.evaluate(
      features: smoothed,
      decision: decision,
    );
    final subGuidance =
        decision.secondaryGuidance ??
        (decision.primaryGuidance == summary.guideMessage
            ? null
            : decision.primaryGuidance);

    return currentState.copyWith(
      decision: decision,
      segmentation: frame.result,
      isFrontCamera: frame.isFrontCamera,
      currentZoom: frame.zoomLevel,
      guidance: summary.guideMessage,
      subGuidance: subGuidance,
      coachingLevel: _coachingLevelFor(summary.guideState),
    );
  }

  CoachingLevel _coachingLevelFor(CompositionGuideState state) {
    switch (state) {
      case CompositionGuideState.aligned:
        return CoachingLevel.good;
      case CompositionGuideState.searchingLeading:
      case CompositionGuideState.moveLeft:
      case CompositionGuideState.moveRight:
      case CompositionGuideState.moveUp:
      case CompositionGuideState.moveDown:
      case CompositionGuideState.adjustHorizon:
      case CompositionGuideState.adjustSkyMore:
      case CompositionGuideState.adjustGroundMore:
      case CompositionGuideState.nearlyAligned:
        return CoachingLevel.warning;
    }
  }
}
