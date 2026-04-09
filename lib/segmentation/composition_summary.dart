import 'composition_resolver.dart';

enum CompositionGuideState {
  searchingLeading,
  moveLeft,
  moveRight,
  moveUp,
  moveDown,
  adjustHorizon,
  adjustSkyMore,
  adjustGroundMore,
  nearlyAligned,
  aligned,
}

class CompositionSummary {
  final bool leadingAligned;
  final String leadingTemplateType;
  final double leadingScore;
  final double leadingStabilityScore;
  final double? vanishingPointXNorm;
  final double? vanishingPointYNorm;
  final double vanishingOffsetX;
  final double vanishingOffsetY;
  final double skyRatio;
  final double groundRatio;
  final double? horizonYNorm;
  final double distanceToUpperThird;
  final double distanceToLowerThird;
  final double bestHorizonThirdDistance;
  final double vanishingPointThirdDistance;
  final double compositionQualityScore;
  final CompositionGuideState guideState;
  final String guideMessage;
  final CompositionMode compositionMode;

  const CompositionSummary({
    required this.leadingAligned,
    required this.leadingTemplateType,
    required this.leadingScore,
    required this.leadingStabilityScore,
    required this.vanishingPointXNorm,
    required this.vanishingPointYNorm,
    required this.vanishingOffsetX,
    required this.vanishingOffsetY,
    required this.skyRatio,
    required this.groundRatio,
    required this.horizonYNorm,
    required this.distanceToUpperThird,
    required this.distanceToLowerThird,
    required this.bestHorizonThirdDistance,
    required this.vanishingPointThirdDistance,
    required this.compositionQualityScore,
    required this.guideState,
    required this.guideMessage,
    required this.compositionMode,
  });
}
