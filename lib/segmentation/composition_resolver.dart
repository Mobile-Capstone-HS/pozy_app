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
  static const double _noneLandscapeThreshold = 0.38;
  static const double _skyRatioGuideMin = 0.14;
  static const double _horizonConfidenceMin = 0.28;
  static const bool _useLegacySkyRatioTargeting = false;
  static const double _horizonGoodDistance = 0.16;
  static const double _ruleOfThirdsLandscapeMin = 0.50;
  static const double _leadingConfidenceMin = 0.30;
  static const double _leadingStrengthMin = 0.26;
  static const double _weakHorizonSceneMin = 0.24;

  const CompositionResolver();

  bool _hasSufficientLandscapeContext(LandscapeFeatures f) {
    final naturalCoverage = (f.vegRatio + f.terrainRatio).clamp(0.0, 1.0);
    final urbanCoverage = (f.roadRatio + f.buildingRatio).clamp(0.0, 1.0);
    final openSkyCue = f.skyOnlyRatio >= 0.05;
    final topOpenCue = f.topOpenAreaRatio >= 0.10;
    final horizonCue =
        f.horizonDetected &&
        f.horizonPosition != null &&
        f.horizonConfidence >= 0.20 &&
        f.horizonValidity != HorizonValidity.invalid;
    final naturalScene =
        naturalCoverage >= 0.20 &&
        (f.foregroundRatio >= 0.10 || topOpenCue || openSkyCue);
    final urbanScene =
        f.roadRatio >= 0.10 &&
        f.buildingRatio >= 0.10 &&
        (topOpenCue || openSkyCue || horizonCue);
    final openScene =
        f.landscapeConfidence >= _noneLandscapeThreshold &&
        (naturalCoverage + urbanCoverage) >= 0.22 &&
        (topOpenCue || openSkyCue);

    return horizonCue || naturalScene || urbanScene || openScene;
  }

  bool _hasOutdoorLeadingContext(LandscapeFeatures f) {
    final naturalCoverage = (f.vegRatio + f.terrainRatio).clamp(0.0, 1.0);
    final strongNaturalScene =
        naturalCoverage >= 0.22 && f.foregroundRatio >= 0.10;
    final streetScene =
        f.roadRatio >= 0.12 &&
        (f.buildingRatio >= 0.10 ||
            f.skyOnlyRatio >= 0.05 ||
            (f.horizonDetected && f.horizonConfidence >= 0.20));
    final skylineScene =
        f.skyOnlyRatio >= 0.05 ||
        (f.horizonDetected && f.horizonConfidence >= 0.20);

    return strongNaturalScene || streetScene || skylineScene;
  }

  CompositionDecision resolve(LandscapeFeatures f) {
    final hasSufficientLandscapeContext = _hasSufficientLandscapeContext(f);
    final hasLeadingGuide = f.leadingConfidence >= _leadingConfidenceMin &&
        f.leadingLineStrength >= _leadingStrengthMin;
    final hasOutdoorLeadingContext = _hasOutdoorLeadingContext(f);
    final structuredScene = hasSufficientLandscapeContext &&
        hasLeadingGuide &&
        hasOutdoorLeadingContext &&
        (f.foregroundRatio >= 0.12 ||
            f.roadRatio >= 0.10 ||
            f.buildingRatio >= 0.12 ||
            (f.vegRatio + f.terrainRatio) >= 0.28);
    final scenicHorizonScene = f.horizonDetected &&
        f.horizonPosition != null &&
        f.horizonPosition! >= 0.22 &&
        f.horizonPosition! <= 0.62 &&
        f.topOpenAreaRatio >= 0.10 &&
        f.horizonConfidence >= 0.24;

    if (!hasSufficientLandscapeContext &&
        !structuredScene &&
        !scenicHorizonScene) {
      return CompositionDecision(
        compositionMode: CompositionMode.none,
        secondaryComposition: null,
        overlayType: 'none',
        primaryGuidance: '풍경이 더 잘 보이도록 프레임에 배경을 조금 더 담아보세요.',
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
          ? '좋아요. 수평선이 3분할 구도에 안정적으로 맞고 있어요.'
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

    if (hasSufficientLandscapeContext &&
        hasLeadingGuide &&
        hasOutdoorLeadingContext &&
        !hasWeakHorizonScene) {
      final vanishingX = f.leadingTargetX ?? 0.5;
      final offset = vanishingX - 0.5;
      final guidance = offset.abs() <= 0.10
          ? '길이나 경계선이 화면 가운데로 잘 향하고 있어요. 이 구도를 유지해보세요.'
          : offset < 0
              ? '길이나 경계선이 왼쪽으로 치우쳐 있어요. 화면 가운데 쪽으로 조금 맞춰보세요.'
              : '길이나 경계선이 오른쪽으로 치우쳐 있어요. 화면 가운데 쪽으로 조금 맞춰보세요.';
      return CompositionDecision(
        compositionMode: CompositionMode.genericLandscape,
        secondaryComposition: null,
        overlayType: 'leading_center',
        primaryGuidance: guidance,
        secondaryGuidance: '수평선이 잘 안 보일 때는 길이나 경계선 방향부터 먼저 맞추면 좋아요.',
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
          ? '풍경을 조금 더 담은 뒤 3분할선을 기준으로 구도를 맞춰보세요.'
          : '풍경이 충분히 보이면 3분할선을 기준으로 구도를 안내해드릴게요.',
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
