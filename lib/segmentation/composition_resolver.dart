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
  static const bool _useLegacySkyRatioTargeting = false;
  static const double _horizonGoodDistance = 0.16;
  static const double _ruleOfThirdsLandscapeMin = 0.42;
  static const double _leadingConfidenceMin = 0.30;
  static const double _leadingStrengthMin = 0.26;
  static const double _weakHorizonSceneMin = 0.24;

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
    final effectiveSkyRatio = f.skyOnlyRatio;
    final applySkyRatioLogic = effectiveSkyRatio >= _skyRatioGuideMin;
    final preferredTarget = _selectHorizonTarget(
      horizonY: horizonY,
      skyRatio: effectiveSkyRatio,
      topOpenRatio: f.topOpenAreaRatio,
    );
    final horizonDistance =
        horizonY == null ? 1.0 : (horizonY - preferredTarget).abs();
    final hasReliableHorizon = horizonY != null &&
        f.horizonConfidence >= _horizonConfidenceMin &&
        f.horizonValidity != HorizonValidity.invalid &&
        f.horizonStability >= 0.18;
    final hasWeakHorizonScene = horizonY != null &&
        f.horizonConfidence >= _weakHorizonSceneMin &&
        f.topOpenAreaRatio >= 0.10;

    if (hasReliableHorizon) {
      final overlayType =
          preferredTarget <= 0.5 ? 'horizon_upper_third' : 'horizon_lower_third';
      final guidance = horizonDistance <= _horizonGoodDistance
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
        ? (0.65 * f.landscapeConfidence +
                0.35 * _ratioBalanceScore(effectiveSkyRatio))
            .clamp(0.0, 1.0)
        : f.landscapeConfidence.clamp(0.0, 1.0);

    final hasLeadingGuide = f.leadingConfidence >= _leadingConfidenceMin &&
        f.leadingLineStrength >= _leadingStrengthMin;

    if (hasLeadingGuide && !hasWeakHorizonScene) {
      final vanishingX = f.leadingTargetX ?? 0.5;
      final offset = vanishingX - 0.5;
      final guidance = offset.abs() <= 0.10
          ? '장면의 중심축이 잘 맞아요. 원근감을 살려 촬영해보세요.'
          : offset < 0
          ? '장면의 중심축이 왼쪽에 있어요. 화면 중심으로 조금 맞춰보세요.'
          : '장면의 중심축이 오른쪽에 있어요. 화면 중심으로 조금 맞춰보세요.';
      return CompositionDecision(
        compositionMode: CompositionMode.genericLandscape,
        secondaryComposition: null,
        overlayType: 'leading_center',
        primaryGuidance: guidance,
        secondaryGuidance: '수평선보다 장면의 중심 흐름을 먼저 맞추는 편이 좋아요.',
        confidence: (0.55 * f.leadingConfidence + 0.45 * f.leadingLineStrength)
            .clamp(0.0, 1.0),
        leadingCenterScore: 1.0 - offset.abs().clamp(0.0, 1.0),
        leadingAnchorScore: f.leadingLineStrength,
        leadingVanishingXNorm: vanishingX,
      );
    }

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

  double _selectHorizonTarget({
    required double? horizonY,
    required double skyRatio,
    required double topOpenRatio,
  }) {
    if (horizonY == null) {
      return _useLegacySkyRatioTargeting
          ? _legacySkyRatioTarget(skyRatio, topOpenRatio)
          : 1.0 / 3.0;
    }
    if (_useLegacySkyRatioTargeting) {
      return _legacySkyRatioTarget(skyRatio, topOpenRatio);
    }

    final nearest = _nearestThirdTarget(horizonY);
    final preferred = _legacySkyRatioTarget(skyRatio, topOpenRatio);
    final nearestDistance = (horizonY - nearest).abs();
    final preferredDistance = (horizonY - preferred).abs();
    final distancesAreClose = (nearestDistance - preferredDistance).abs() <= 0.04;
    if (!distancesAreClose) return nearest;

    final strongSkyPreference = skyRatio >= 0.62 || skyRatio <= 0.26;
    return strongSkyPreference ? preferred : nearest;
  }

  double _legacySkyRatioTarget(double skyRatio, double topOpenRatio) {
    if (skyRatio > 0.58) return 2.0 / 3.0;
    if (skyRatio < 0.34) return 1.0 / 3.0;
    return topOpenRatio > 0.36 ? 2.0 / 3.0 : 1.0 / 3.0;
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
