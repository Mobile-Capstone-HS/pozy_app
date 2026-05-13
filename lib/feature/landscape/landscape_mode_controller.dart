import 'package:pose_camera_app/coaching/coaching_result.dart';
import 'package:pose_camera_app/feature/landscape/landscape_ui_state.dart';
import 'package:pose_camera_app/segmentation/composition_engine.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/composition_summary.dart';
import 'package:pose_camera_app/segmentation/composition_temporal_filter.dart';
import 'package:pose_camera_app/segmentation/fastscnn_view.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class LandscapeModeController {
  final LandscapeAnalyzer _landscapeAnalyzer = LandscapeAnalyzer();
  final CompositionEngine _compositionEngine = CompositionEngine();
  final CompositionResolver _resolver = const CompositionResolver();
  final CompositionTemporalFilter _temporalFilter = CompositionTemporalFilter();

  void reset() {
    _landscapeAnalyzer.reset();
    _compositionEngine.reset();
    _temporalFilter.reset();
  }

  LandscapeUiState processFrame(
    FastScnnFrame frame, {
    required LandscapeUiState currentState,
  }) {
    final analysis = _landscapeAnalyzer.analyze(frame.result);
    final smoothed = _temporalFilter.smooth(analysis.features);
    final decision = _temporalFilter.stabilize(
      _resolver.resolve(smoothed),
      smoothed,
    );
    final summary = _compositionEngine.evaluate(
      features: smoothed,
      decision: decision,
    );
    final subGuidance =
        analysis.advice.secondaryGuidance ??
        decision.secondaryGuidance ??
        (decision.primaryGuidance == summary.guideMessage
            ? null
            : decision.primaryGuidance);
    final guidance = _visibleGuidanceFor(
      primaryGuidance: analysis.advice.primaryGuidance,
      summary: summary,
    );

    return currentState.copyWith(
      decision: decision,
      overlayAdvice: analysis.advice,
      isFrontCamera: frame.isFrontCamera,
      currentZoom: frame.zoomLevel,
      guidance: guidance,
      subGuidance: subGuidance,
      coachingLevel: _coachingLevelFor(summary.guideState),
    );
  }

  String _visibleGuidanceFor({
    required String primaryGuidance,
    required CompositionSummary summary,
  }) {
    if (_startsWithPositiveGuidance(primaryGuidance) &&
        summary.guideState != CompositionGuideState.aligned) {
      return summary.guideMessage;
    }
    return primaryGuidance;
  }

  bool _startsWithPositiveGuidance(String message) {
    return message.startsWith('좋아요.') || message.startsWith('좋아요,');
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
