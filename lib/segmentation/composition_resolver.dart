import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

enum CompositionMode {
  none,
  horizon,
  ruleOfThirds,
  genericLandscape,
}

class CompositionDecision {
  final CompositionMode compositionMode;
  final CompositionMode? secondaryComposition;
  final String overlayType;
  final String primaryGuidance;
  final String? secondaryGuidance;
  final double confidence;
  final double? leadingCenterScore;
  final double? leadingLeftScore;
  final double? leadingRightScore;
  final double? leadingAnchorScore;
  final double? leadingAngleDeg;
  final double? leadingVanishingXNorm;

  const CompositionDecision({
    required this.compositionMode,
    required this.secondaryComposition,
    required this.overlayType,
    required this.primaryGuidance,
    required this.secondaryGuidance,
    required this.confidence,
    this.leadingCenterScore,
    this.leadingLeftScore,
    this.leadingRightScore,
    this.leadingAnchorScore,
    this.leadingAngleDeg,
    this.leadingVanishingXNorm,
  });
}

class CompositionResolver {
  static const double _noneLandscapeThreshold = 0.10;
  static const double _skyRatioGuideMin = 0.14;
  static const double _horizonConfidenceMin = 0.28;
  static const double _horizonAlignedDistance = 0.12;
  static const double _ruleOfThirdsLandscapeMin = 0.42;

  const CompositionResolver();

  CompositionDecision resolve(LandscapeFeatures f) {
    if (f.landscapeConfidence < _noneLandscapeThreshold) {
      return CompositionDecision(
        compositionMode: CompositionMode.none,
        secondaryComposition: null,
        overlayType: 'none',
        primaryGuidance: '하늘과 지면이 함께 보이도록 프레임을 다시 잡아보세요.',
        secondaryGuidance: null,
        confidence: 1.0 - f.landscapeConfidence,
      );
    }

    final horizonY = f.horizonPosition;
    final applySkyRatioLogic = f.skyRatio >= _skyRatioGuideMin;
    final preferredTarget = applySkyRatioLogic
        ? _preferredHorizonTarget(f.skyRatio)
        : _nearestThirdTarget(horizonY);
    final horizonDistance =
        horizonY == null ? 1.0 : (horizonY - preferredTarget).abs();
    final hasReliableHorizon =
        horizonY != null && f.horizonConfidence >= _horizonConfidenceMin;

    if (hasReliableHorizon) {
      final overlayType =
          preferredTarget <= 0.5 ? 'horizon_upper_third' : 'horizon_lower_third';
      final guidance = horizonDistance <= _horizonAlignedDistance
          ? '좋아요. 수평선을 3분할선 근처에 잘 맞추고 있어요.'
          : preferredTarget <= 0.5
              ? '수평선을 위쪽 3분할선에 맞춰보세요.'
              : '수평선을 아래쪽 3분할선에 맞춰보세요.';
      final confidence =
          (0.55 * f.horizonConfidence +
                  0.45 * (1.0 - (horizonDistance / 0.33)).clamp(0.0, 1.0))
              .clamp(0.0, 1.0);
      return CompositionDecision(
        compositionMode: CompositionMode.horizon,
        secondaryComposition: null,
        overlayType: overlayType,
        primaryGuidance: guidance,
        secondaryGuidance: null,
        confidence: confidence,
      );
    }

    final ruleConfidence = applySkyRatioLogic
        ? (0.65 * f.landscapeConfidence + 0.35 * _ratioBalanceScore(f.skyRatio))
            .clamp(0.0, 1.0)
        : f.landscapeConfidence.clamp(0.0, 1.0);

    if (f.landscapeConfidence >= _ruleOfThirdsLandscapeMin) {
      return CompositionDecision(
        compositionMode: CompositionMode.ruleOfThirds,
        secondaryComposition: null,
        overlayType: 'thirds_grid',
        primaryGuidance: '3분할선을 기준으로 수평선과 주요 경계를 맞춰보세요.',
        secondaryGuidance: null,
        confidence: ruleConfidence,
      );
    }

    return CompositionDecision(
      compositionMode: CompositionMode.genericLandscape,
      secondaryComposition: null,
      overlayType: 'thirds_grid',
      primaryGuidance: applySkyRatioLogic
          ? '하늘과 지면 비율을 보면서 3분할선에 맞춰 구도를 잡아보세요.'
          : '수평선이 보이면 3분할선에 맞춰 구도를 잡아보세요.',
      secondaryGuidance: null,
      confidence: ruleConfidence,
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

  double _ratioBalanceScore(double skyRatio) {
    final upper = (1.0 - ((skyRatio - (1.0 / 3.0)).abs() / 0.33)).clamp(0.0, 1.0);
    final lower = (1.0 - ((skyRatio - (2.0 / 3.0)).abs() / 0.34)).clamp(0.0, 1.0);
    return upper > lower ? upper : lower;
  }
}
