import 'composition_resolver.dart';
import 'composition_summary.dart';
import 'landscape_analyzer.dart';

class CompositionGuideInput {
  final LandscapeFeatures features;
  final CompositionDecision decision;
  final double leadingScore;
  final double horizonScore;
  final double ratioScore;
  final double thirdsScore;
  final double compositionQualityScore;
  final double? horizonYNorm;
  final double bestHorizonThirdDistance;
  final double skyRatio;
  final double groundRatio;
  final double vanishingOffsetX;
  final bool leadingAligned;
  final bool horizonValid;
  final bool horizonNeedsAdjust;
  final bool ratioNeedsAdjust;

  const CompositionGuideInput({
    required this.features,
    required this.decision,
    required this.leadingScore,
    required this.horizonScore,
    required this.ratioScore,
    required this.thirdsScore,
    required this.compositionQualityScore,
    required this.horizonYNorm,
    required this.bestHorizonThirdDistance,
    required this.skyRatio,
    required this.groundRatio,
    required this.vanishingOffsetX,
    required this.leadingAligned,
    required this.horizonValid,
    required this.horizonNeedsAdjust,
    required this.ratioNeedsAdjust,
  });
}

class CompositionGuideResult {
  final CompositionGuideState state;
  final String message;

  const CompositionGuideResult({
    required this.state,
    required this.message,
  });
}

class CompositionGuideResolver {
  static const double kSkyRatioGuideMin = 0.14;
  static const double kRatioLowThreshold = 0.16;
  static const double kRatioHighThreshold = 0.84;
  static const double kSkyThirdAlignedDistance = 0.18;
  static const double kAlignedScoreThreshold = 0.78;

  const CompositionGuideResolver();

  CompositionGuideResult resolve(CompositionGuideInput i) {
    if (i.horizonValid && i.horizonNeedsAdjust) {
      final desired = i.skyRatio >= kSkyRatioGuideMin
          ? _preferredHorizonTarget(i.skyRatio)
          : _nearestThirdTarget(i.horizonYNorm);
      final current = i.horizonYNorm ?? desired;
      if (current > desired) {
        return const CompositionGuideResult(
          state: CompositionGuideState.moveDown,
          message: '카메라를 조금 내려주세요',
        );
      }
      return const CompositionGuideResult(
        state: CompositionGuideState.moveUp,
        message: '카메라를 조금 들어주세요',
      );
    }

    if (i.ratioNeedsAdjust && i.skyRatio >= kSkyRatioGuideMin) {
      if (i.skyRatio < kRatioLowThreshold) {
        return const CompositionGuideResult(
          state: CompositionGuideState.adjustSkyMore,
          message: '카메라를 조금 들어서 하늘을 더 담아보세요',
        );
      }
      if (i.skyRatio > kRatioHighThreshold) {
        return const CompositionGuideResult(
          state: CompositionGuideState.adjustGroundMore,
          message: '카메라를 조금 내려서 지면을 더 담아보세요',
        );
      }
    }

    if (_isSkyNearThird(i.skyRatio)) {
      return const CompositionGuideResult(
        state: CompositionGuideState.aligned,
        message: '하늘 분포가 3분할선 근처에 있어 지금 구도가 잘 맞아요',
      );
    }

    if (i.compositionQualityScore >= kAlignedScoreThreshold) {
      return const CompositionGuideResult(
        state: CompositionGuideState.aligned,
        message: '좋아요, 지금 구도로 촬영해보세요',
      );
    }

    return const CompositionGuideResult(
      state: CompositionGuideState.nearlyAligned,
      message: '3분할선을 보면서 수평선 위치를 조금만 더 맞춰보세요',
    );
  }

  double _preferredHorizonTarget(double skyRatio) {
    if (skyRatio > 0.58) return 1.0 / 3.0;
    if (skyRatio < 0.34) return 2.0 / 3.0;
    return 1.0 / 3.0;
  }

  double _nearestThirdTarget(double? horizonY) {
    if (horizonY == null) return 1.0 / 3.0;
    final upper = (horizonY - (1.0 / 3.0)).abs();
    final lower = (horizonY - (2.0 / 3.0)).abs();
    return upper <= lower ? 1.0 / 3.0 : 2.0 / 3.0;
  }

  bool _isSkyNearThird(double skyRatio) {
    if (skyRatio < kSkyRatioGuideMin) return false;
    final upper = (skyRatio - (1.0 / 3.0)).abs();
    final lower = (skyRatio - (2.0 / 3.0)).abs();
    return upper <= kSkyThirdAlignedDistance ||
        lower <= kSkyThirdAlignedDistance;
  }
}
