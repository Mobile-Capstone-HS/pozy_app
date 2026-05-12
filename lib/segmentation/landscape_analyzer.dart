import 'dart:math' as math;

import 'fastscnn_segmentor.dart';

enum HorizonType { flat, ridge, uncertain }

enum HorizonDetectionSource {
  directSkyMask,
  terrainFallback,
  gradientFallback,
  temporalHold,
  none,
}

enum HorizonValidity { valid, weak, invalid }

enum TiltDirection { uphillLeft, uphillRight, level, unknown }

enum OverlayGuidanceState {
  hidden,
  searching,
  unstable,
  adjustUp,
  adjustDown,
  aligned,
}

class HorizonBoundaryPoint {
  final double xNorm;
  final double yNorm;

  const HorizonBoundaryPoint({required this.xNorm, required this.yNorm});
}

class HorizonConfidenceBreakdown {
  final double coverageScore;
  final double residualScore;
  final double roughnessScore;
  final double tiltScore;
  final double validityScore;
  final double sourceScore;

  const HorizonConfidenceBreakdown({
    required this.coverageScore,
    required this.residualScore,
    required this.roughnessScore,
    required this.tiltScore,
    required this.validityScore,
    required this.sourceScore,
  });

  const HorizonConfidenceBreakdown.zero()
    : coverageScore = 0.0,
      residualScore = 0.0,
      roughnessScore = 0.0,
      tiltScore = 0.0,
      validityScore = 0.0,
      sourceScore = 0.0;
}

class HorizonDetectionResult {
  final bool horizonDetected;
  final double confidence;
  final double stability;
  final double? averageY;
  final double? tiltAngleDeg;
  final List<HorizonBoundaryPoint> boundaryPoints;
  final HorizonType horizonType;
  final HorizonDetectionSource source;
  final HorizonValidity validity;
  final TiltDirection tiltDirection;
  final HorizonConfidenceBreakdown breakdown;

  const HorizonDetectionResult({
    required this.horizonDetected,
    required this.confidence,
    required this.stability,
    required this.averageY,
    required this.tiltAngleDeg,
    required this.boundaryPoints,
    required this.horizonType,
    required this.source,
    required this.validity,
    required this.tiltDirection,
    required this.breakdown,
  });

  const HorizonDetectionResult.none()
    : horizonDetected = false,
      confidence = 0.0,
      stability = 0.0,
      averageY = null,
      tiltAngleDeg = null,
      boundaryPoints = const [],
      horizonType = HorizonType.uncertain,
      source = HorizonDetectionSource.none,
      validity = HorizonValidity.invalid,
      tiltDirection = TiltDirection.unknown,
      breakdown = const HorizonConfidenceBreakdown.zero();

  HorizonDetectionResult copyWith({
    bool? horizonDetected,
    double? confidence,
    double? stability,
    double? averageY,
    double? tiltAngleDeg,
    List<HorizonBoundaryPoint>? boundaryPoints,
    HorizonType? horizonType,
    HorizonDetectionSource? source,
    HorizonValidity? validity,
    TiltDirection? tiltDirection,
    HorizonConfidenceBreakdown? breakdown,
  }) {
    return HorizonDetectionResult(
      horizonDetected: horizonDetected ?? this.horizonDetected,
      confidence: confidence ?? this.confidence,
      stability: stability ?? this.stability,
      averageY: averageY ?? this.averageY,
      tiltAngleDeg: tiltAngleDeg ?? this.tiltAngleDeg,
      boundaryPoints: boundaryPoints ?? this.boundaryPoints,
      horizonType: horizonType ?? this.horizonType,
      source: source ?? this.source,
      validity: validity ?? this.validity,
      tiltDirection: tiltDirection ?? this.tiltDirection,
      breakdown: breakdown ?? this.breakdown,
    );
  }
}

class LandscapeOverlayAdvice {
  final OverlayGuidanceState overlayState;
  final double? targetHorizonY;
  final double? recommendedAdjustmentY;
  final TiltDirection tiltDirection;
  final String primaryGuidance;
  final String? secondaryGuidance;
  final bool showHorizonGuide;

  const LandscapeOverlayAdvice({
    required this.overlayState,
    required this.targetHorizonY,
    required this.recommendedAdjustmentY,
    required this.tiltDirection,
    required this.primaryGuidance,
    required this.secondaryGuidance,
    required this.showHorizonGuide,
  });

  const LandscapeOverlayAdvice.none()
    : overlayState = OverlayGuidanceState.hidden,
      targetHorizonY = null,
      recommendedAdjustmentY = null,
      tiltDirection = TiltDirection.unknown,
      primaryGuidance = '장면을 천천히 맞춰보세요.',
      secondaryGuidance = null,
      showHorizonGuide = false;
}

class LandscapeAnalysisFrame {
  final LandscapeFeatures features;
  final HorizonDetectionResult horizon;
  final LandscapeOverlayAdvice advice;
  final HorizonDetectorDebug debug;

  const LandscapeAnalysisFrame({
    required this.features,
    required this.horizon,
    required this.advice,
    required this.debug,
  });
}

class HorizonDetectorDebug {
  final HorizonDetectionResult direct;
  final HorizonDetectionResult terrainFallback;
  final HorizonDetectionResult gradientFallback;
  final HorizonDetectionSource selectedSource;

  const HorizonDetectorDebug({
    required this.direct,
    required this.terrainFallback,
    required this.gradientFallback,
    required this.selectedSource,
  });
}

class LandscapeFeatures {
  final double skyRatio;
  final double skyOnlyRatio;
  final double topOpenAreaRatio;
  final double vegRatio;
  final double terrainRatio;
  final double roadRatio;
  final double buildingRatio;
  final double waterRatio;
  final double openness;
  final double landscapeConfidence;
  final bool horizonDetected;
  final double? horizonPosition;
  final double? horizonTiltDeg;
  final double? horizonThirdDistance;
  final double horizonConfidence;
  final double horizonStability;
  final List<HorizonBoundaryPoint> boundaryPoints;
  final HorizonType horizonType;
  final HorizonDetectionSource horizonSource;
  final HorizonValidity horizonValidity;
  final TiltDirection tiltDirection;
  final double diagonalStrength;
  final double diagonalConfidence;
  final double leadingLineStrength;
  final double leadingConfidence;
  final double? dominantLineAngleDeg;
  final double? leadingEntryX;
  final double? leadingTargetX;
  final double nativeLeadingScore;
  final double nativeLeadingLineCount;
  final double? nativeLeadingEntryX;
  final double? nativeLeadingTargetX;
  final double vegLeftRatio;
  final double vegRightRatio;
  final double foregroundRatio;

  const LandscapeFeatures({
    required this.skyRatio,
    required this.skyOnlyRatio,
    required this.topOpenAreaRatio,
    required this.vegRatio,
    required this.terrainRatio,
    required this.roadRatio,
    required this.buildingRatio,
    required this.waterRatio,
    required this.openness,
    required this.landscapeConfidence,
    required this.horizonDetected,
    required this.horizonPosition,
    required this.horizonTiltDeg,
    required this.horizonThirdDistance,
    required this.horizonConfidence,
    required this.horizonStability,
    required this.boundaryPoints,
    required this.horizonType,
    required this.horizonSource,
    required this.horizonValidity,
    required this.tiltDirection,
    required this.diagonalStrength,
    required this.diagonalConfidence,
    required this.leadingLineStrength,
    required this.leadingConfidence,
    required this.dominantLineAngleDeg,
    required this.leadingEntryX,
    required this.leadingTargetX,
    required this.nativeLeadingScore,
    required this.nativeLeadingLineCount,
    required this.nativeLeadingEntryX,
    required this.nativeLeadingTargetX,
    required this.vegLeftRatio,
    required this.vegRightRatio,
    required this.foregroundRatio,
  });

  LandscapeFeatures copyWith({
    double? skyRatio,
    double? skyOnlyRatio,
    double? topOpenAreaRatio,
    double? vegRatio,
    double? terrainRatio,
    double? roadRatio,
    double? buildingRatio,
    double? waterRatio,
    double? openness,
    double? landscapeConfidence,
    bool? horizonDetected,
    double? horizonPosition,
    double? horizonTiltDeg,
    double? horizonThirdDistance,
    double? horizonConfidence,
    double? horizonStability,
    List<HorizonBoundaryPoint>? boundaryPoints,
    HorizonType? horizonType,
    HorizonDetectionSource? horizonSource,
    HorizonValidity? horizonValidity,
    TiltDirection? tiltDirection,
    double? diagonalStrength,
    double? diagonalConfidence,
    double? leadingLineStrength,
    double? leadingConfidence,
    double? dominantLineAngleDeg,
    double? leadingEntryX,
    double? leadingTargetX,
    double? nativeLeadingScore,
    double? nativeLeadingLineCount,
    double? nativeLeadingEntryX,
    double? nativeLeadingTargetX,
    double? vegLeftRatio,
    double? vegRightRatio,
    double? foregroundRatio,
  }) {
    return LandscapeFeatures(
      skyRatio: skyRatio ?? this.skyRatio,
      skyOnlyRatio: skyOnlyRatio ?? this.skyOnlyRatio,
      topOpenAreaRatio: topOpenAreaRatio ?? this.topOpenAreaRatio,
      vegRatio: vegRatio ?? this.vegRatio,
      terrainRatio: terrainRatio ?? this.terrainRatio,
      roadRatio: roadRatio ?? this.roadRatio,
      buildingRatio: buildingRatio ?? this.buildingRatio,
      waterRatio: waterRatio ?? this.waterRatio,
      openness: openness ?? this.openness,
      landscapeConfidence: landscapeConfidence ?? this.landscapeConfidence,
      horizonDetected: horizonDetected ?? this.horizonDetected,
      horizonPosition: horizonPosition ?? this.horizonPosition,
      horizonTiltDeg: horizonTiltDeg ?? this.horizonTiltDeg,
      horizonThirdDistance: horizonThirdDistance ?? this.horizonThirdDistance,
      horizonConfidence: horizonConfidence ?? this.horizonConfidence,
      horizonStability: horizonStability ?? this.horizonStability,
      boundaryPoints: boundaryPoints ?? this.boundaryPoints,
      horizonType: horizonType ?? this.horizonType,
      horizonSource: horizonSource ?? this.horizonSource,
      horizonValidity: horizonValidity ?? this.horizonValidity,
      tiltDirection: tiltDirection ?? this.tiltDirection,
      diagonalStrength: diagonalStrength ?? this.diagonalStrength,
      diagonalConfidence: diagonalConfidence ?? this.diagonalConfidence,
      leadingLineStrength: leadingLineStrength ?? this.leadingLineStrength,
      leadingConfidence: leadingConfidence ?? this.leadingConfidence,
      dominantLineAngleDeg: dominantLineAngleDeg ?? this.dominantLineAngleDeg,
      leadingEntryX: leadingEntryX ?? this.leadingEntryX,
      leadingTargetX: leadingTargetX ?? this.leadingTargetX,
      nativeLeadingScore: nativeLeadingScore ?? this.nativeLeadingScore,
      nativeLeadingLineCount:
          nativeLeadingLineCount ?? this.nativeLeadingLineCount,
      nativeLeadingEntryX: nativeLeadingEntryX ?? this.nativeLeadingEntryX,
      nativeLeadingTargetX: nativeLeadingTargetX ?? this.nativeLeadingTargetX,
      vegLeftRatio: vegLeftRatio ?? this.vegLeftRatio,
      vegRightRatio: vegRightRatio ?? this.vegRightRatio,
      foregroundRatio: foregroundRatio ?? this.foregroundRatio,
    );
  }
}

class LandscapeAnalyzer {
  final HorizonDetector horizonDetector;
  final HorizonTemporalStabilizer temporalStabilizer;
  final LandscapeCompositionAdvisor compositionAdvisor;

  LandscapeAnalyzer({
    HorizonDetector? horizonDetector,
    HorizonTemporalStabilizer? temporalStabilizer,
    LandscapeCompositionAdvisor? compositionAdvisor,
  }) : horizonDetector = horizonDetector ?? HorizonDetector(),
       temporalStabilizer =
           temporalStabilizer ?? HorizonTemporalStabilizer(),
       compositionAdvisor =
           compositionAdvisor ?? const LandscapeCompositionAdvisor();

  void reset() {
    temporalStabilizer.reset();
  }

  LandscapeAnalysisFrame analyze(
    SegmentationResult result, {
    List<List<double>>? skyConfidenceMap,
    List<List<double>>? brightnessMap,
    List<List<double>>? saturationMap,
  }) {
    final rawHorizon = horizonDetector.detect(
      result,
      skyConfidenceMap: skyConfidenceMap,
      brightnessMap: brightnessMap,
      saturationMap: saturationMap,
    );
    final stabilizedHorizon = temporalStabilizer.update(rawHorizon);
    final features = _buildFeatures(result, stabilizedHorizon);
    final advice = compositionAdvisor.build(features);
    return LandscapeAnalysisFrame(
      features: features,
      horizon: stabilizedHorizon,
      advice: advice,
      debug: horizonDetector.lastDebug,
    );
  }

  LandscapeFeatures _buildFeatures(
    SegmentationResult result,
    HorizonDetectionResult horizon,
  ) {
    final skyOnlyRatio = _computeSkyOnlyRatio(result);
    final topOpenAreaRatio = _computeTopOpenAreaRatio(result);
    final skyRatio = (skyOnlyRatio * 0.78 + topOpenAreaRatio * 0.22)
        .clamp(0.0, 1.0);
    final vegRatio = result.classRatio(CityscapesClass.vegetation);
    final terrainRatio = result.classRatio(CityscapesClass.terrain);
    final roadRatio = result.classRatio(CityscapesClass.road);
    final buildingRatio = result.classRatio(CityscapesClass.building);
    final openness = _computeOpenness(result);
    final leading = _computeLeadingLineMetrics(result);
    final midCol = result.width ~/ 2;
    final foregroundStart = result.height * 2 ~/ 3;
    final foregroundRatio =
        result.classRatioInRows(
          CityscapesClass.vegetation,
          foregroundStart,
          result.height,
        ) +
        result.classRatioInRows(
          CityscapesClass.terrain,
          foregroundStart,
          result.height,
        );
    final confidence = _computeLandscapeConfidence(
      skyOnlyRatio: skyOnlyRatio,
      topOpenAreaRatio: topOpenAreaRatio,
      vegRatio: vegRatio,
      terrainRatio: terrainRatio,
      roadRatio: roadRatio,
      buildingRatio: buildingRatio,
      openness: openness,
      foregroundRatio: foregroundRatio,
      horizonDetected: horizon.horizonDetected,
      horizonPosition: horizon.averageY,
      horizonConfidence: horizon.confidence,
      horizonStability: horizon.stability,
      leading: leading,
    );

    return LandscapeFeatures(
      skyRatio: skyRatio,
      skyOnlyRatio: skyOnlyRatio,
      topOpenAreaRatio: topOpenAreaRatio,
      vegRatio: vegRatio,
      terrainRatio: terrainRatio,
      roadRatio: roadRatio,
      buildingRatio: buildingRatio,
      waterRatio: 0.0,
      openness: openness,
      landscapeConfidence: confidence,
      horizonDetected: horizon.horizonDetected,
      horizonPosition: horizon.averageY,
      horizonTiltDeg: horizon.tiltAngleDeg,
      horizonThirdDistance: horizon.averageY == null
          ? null
          : math.min(
              (horizon.averageY! - (1 / 3)).abs(),
              (horizon.averageY! - (2 / 3)).abs(),
            ),
      horizonConfidence: horizon.confidence,
      horizonStability: horizon.stability,
      boundaryPoints: horizon.boundaryPoints,
      horizonType: horizon.horizonType,
      horizonSource: horizon.source,
      horizonValidity: horizon.validity,
      tiltDirection: horizon.tiltDirection,
      diagonalStrength: leading.diagonalStrength,
      diagonalConfidence: leading.diagonalConfidence,
      leadingLineStrength: leading.strength,
      leadingConfidence: leading.confidence,
      dominantLineAngleDeg: leading.angleDeg,
      leadingEntryX: leading.entryX,
      leadingTargetX: leading.targetX,
      nativeLeadingScore: 0.0,
      nativeLeadingLineCount: 0.0,
      nativeLeadingEntryX: null,
      nativeLeadingTargetX: null,
      vegLeftRatio: result.classRatioInCols(
        CityscapesClass.vegetation,
        0,
        midCol,
      ),
      vegRightRatio: result.classRatioInCols(
        CityscapesClass.vegetation,
        midCol,
        result.width,
      ),
      foregroundRatio: foregroundRatio,
    );
  }

  static double _computeLandscapeConfidence({
    required double skyOnlyRatio,
    required double topOpenAreaRatio,
    required double vegRatio,
    required double terrainRatio,
    required double roadRatio,
    required double buildingRatio,
    required double openness,
    required double foregroundRatio,
    required bool horizonDetected,
    required double? horizonPosition,
    required double horizonConfidence,
    required double horizonStability,
    required _LeadingLineMetrics leading,
  }) {
    final naturalCoverage = (vegRatio + terrainRatio).clamp(0.0, 1.0);
    final urbanCoverage = (buildingRatio + roadRatio).clamp(0.0, 1.0);
    final scenicCoverage = (naturalCoverage + roadRatio + buildingRatio * 0.8)
        .clamp(0.0, 1.0);
    final leadingPresence =
        (0.55 * leading.confidence + 0.45 * leading.strength).clamp(0.0, 1.0);
    final openPresence = math.max(openness, topOpenAreaRatio * 0.85);
    final horizonPresence = horizonDetected ? horizonConfidence.clamp(0.0, 1.0) : 0.0;

    final horizonScene = (0.30 * skyOnlyRatio +
            0.16 * topOpenAreaRatio +
            0.30 * horizonPresence +
            0.12 * naturalCoverage +
            0.12 * openPresence)
        .clamp(0.0, 1.0);
    final naturalScene = (0.36 * naturalCoverage +
            0.24 * foregroundRatio.clamp(0.0, 1.0) +
            0.24 * leadingPresence +
            0.16 * openPresence)
        .clamp(0.0, 1.0);
    final urbanScene = (0.22 * buildingRatio +
            0.18 * roadRatio +
            0.28 * leadingPresence +
            0.16 * topOpenAreaRatio +
            0.16 * openPresence)
        .clamp(0.0, 1.0);
    final blendedBase = (0.24 * scenicCoverage +
            0.22 * leadingPresence +
            0.18 * openPresence +
            0.16 * foregroundRatio.clamp(0.0, 1.0) +
            0.12 * skyOnlyRatio +
            0.08 * urbanCoverage)
        .clamp(0.0, 1.0);
    final sunsetBandScene =
        horizonDetected &&
            horizonPosition != null &&
            horizonPosition >= 0.22 &&
            horizonPosition <= 0.62 &&
            topOpenAreaRatio >= 0.10 &&
            horizonPresence >= 0.24
        ? (0.36 +
                0.18 * topOpenAreaRatio +
                0.22 * horizonPresence +
                0.14 * horizonStability.clamp(0.0, 1.0) +
                0.10 * openPresence)
            .clamp(0.0, 1.0)
        : 0.0;

    return math.max(
      math.max(blendedBase, sunsetBandScene),
      math.max(horizonScene, math.max(naturalScene, urbanScene)),
    );
  }

  static double _computeSkyOnlyRatio(SegmentationResult result) {
    return result.classRatio(CityscapesClass.sky).clamp(0.0, 1.0);
  }

  static double _computeTopOpenAreaRatio(SegmentationResult result) {
    if (result.height <= 0 || result.width <= 0) return 0.0;
    final topEnd = (result.height * 0.42).floor().clamp(1, result.height);
    var total = 0;
    var open = 0;
    for (int y = 0; y < topEnd; y++) {
      final yWeight = 1.0 - (y / math.max(1, topEnd - 1)) * 0.35;
      for (int x = 0; x < result.width; x++) {
        total++;
        final id = result.classMap[y][x];
        if (id == CityscapesClass.sky ||
            id == CityscapesClass.terrain ||
            id == CityscapesClass.road ||
            id == CityscapesClass.sidewalk) {
          open += yWeight.round();
        }
      }
    }
    if (total == 0) return 0.0;
    return (open / total).clamp(0.0, 1.0);
  }

  static double _computeOpenness(SegmentationResult result) {
    final xStart = result.width ~/ 3;
    final xEnd = result.width * 2 ~/ 3;
    final yStart = result.height ~/ 3;
    final yEnd = result.height * 2 ~/ 3;
    var total = 0;
    var open = 0;
    for (int y = yStart; y < yEnd; y++) {
      for (int x = xStart; x < xEnd; x++) {
        total++;
        final id = result.classMap[y][x];
        if (id == CityscapesClass.sky ||
            id == CityscapesClass.terrain ||
            id == CityscapesClass.road ||
            id == CityscapesClass.sidewalk) {
          open++;
        }
      }
    }
    return total == 0 ? 0.0 : open / total;
  }

  static _LeadingLineMetrics _computeLeadingLineMetrics(
    SegmentationResult result,
  ) {
    if (result.height < 8 || result.width < 8) {
      return const _LeadingLineMetrics.none();
    }

    final centers = <double>[];
    final rowNorms = <double>[];
    final rowCoverages = <double>[];
    final startRow = (result.height * 0.42).floor();
    for (int y = startRow; y < result.height; y++) {
      var weightedCount = 0.0;
      var sumX = 0.0;
      for (int x = 0; x < result.width; x++) {
        final id = result.classMap[y][x];
        final weight = id == CityscapesClass.road
            ? 1.0
            : id == CityscapesClass.sidewalk
            ? 0.85
            : 0.0;
        if (weight <= 0.0) continue;
        weightedCount += weight;
        sumX += x * weight;
      }
      final coverage = weightedCount / result.width;
      if (coverage < 0.10) continue;
      centers.add((sumX / weightedCount) / math.max(1, result.width - 1));
      rowNorms.add(y / math.max(1, result.height - 1));
      rowCoverages.add(coverage);
    }

    if (centers.length < 4) return const _LeadingLineMetrics.none();

    final meanCenter = centers.reduce((a, b) => a + b) / centers.length;
    final variance = centers
            .map((value) => math.pow(value - meanCenter, 2).toDouble())
            .reduce((a, b) => a + b) /
        centers.length;
    final centerStability = (1.0 - (math.sqrt(variance) / 0.22)).clamp(0.0, 1.0);
    final meanCoverage =
        rowCoverages.reduce((a, b) => a + b) / rowCoverages.length;
    final bottomCoverage = rowCoverages.last;
    final topCoverage = rowCoverages.first;
    final taperScore =
        ((bottomCoverage - topCoverage) / 0.28).clamp(0.0, 1.0);
    final fit = HorizonDetector._leastSquares(rowNorms, centers);
    final entryX = centers.last;
    final targetX = centers.first;
    final centerBias =
        (1.0 - (((targetX - 0.5).abs()) / 0.35)).clamp(0.0, 1.0);
    if (bottomCoverage < 0.16 || taperScore < 0.18) {
      return const _LeadingLineMetrics.none();
    }
    final confidence =
        (0.22 * meanCoverage +
                0.24 * centerStability +
                0.18 * centerBias +
                0.36 * taperScore)
            .clamp(0.0, 1.0);
    final strength =
        (0.26 * meanCoverage +
                0.18 * centerStability +
                0.16 * centerBias +
                0.40 * taperScore)
            .clamp(0.0, 1.0);

    return _LeadingLineMetrics(
      strength: strength,
      confidence: confidence,
      entryX: entryX,
      targetX: targetX,
      angleDeg: math.atan(fit.slope) * 180.0 / math.pi,
      diagonalStrength: math.min(strength * fit.slope.abs() * 1.8, 1.0),
      diagonalConfidence: math.min(confidence * 0.85, 1.0),
    );
  }
}

class HorizonDetector {
  static const int _horizonDownsampleStride = 3;
  static const double _directAcceptConfidence = 0.34;
  static const double _directCoverageMin = 0.35;
  static const double _gradientMinScore = 0.12;
  static const double _gradientCoverageMin = 0.30;
  static const double _terrainCoverageMin = 0.42;
  static const double _terrainObstacleDominanceMax = 0.62;
  static const double _validConfidenceMin = 0.34;
  static const double _weakConfidenceMin = 0.22;

  HorizonDetectorDebug _lastDebug = HorizonDetectorDebug(
    direct: const HorizonDetectionResult.none(),
    terrainFallback: const HorizonDetectionResult.none(),
    gradientFallback: const HorizonDetectionResult.none(),
    selectedSource: HorizonDetectionSource.none,
  );

  HorizonDetector();

  HorizonDetectorDebug get lastDebug => _lastDebug;

  HorizonDetectionResult detect(
    SegmentationResult result, {
    List<List<double>>? skyConfidenceMap,
    List<List<double>>? brightnessMap,
    List<List<double>>? saturationMap,
  }) {
    final sampleCount = _adaptiveSampleCount(result.width);
    final horizonResult = _horizonDownsampleStride > 1
        ? _downsampleSegmentationResult(result, _horizonDownsampleStride)
        : result;
    final score = _buildSkyScore(
      horizonResult,
      skyConfidenceMap: _downsampleDoubleMap(
        skyConfidenceMap,
        _horizonDownsampleStride,
      ),
      brightnessMap: _downsampleDoubleMap(
        brightnessMap,
        _horizonDownsampleStride,
      ),
      saturationMap: _downsampleDoubleMap(
        saturationMap,
        _horizonDownsampleStride,
      ),
    );

    var mask = _thresholdSkyMask(score);
    mask = _morphClose(mask);
    mask = _morphOpen(mask);
    mask = _retainTopConnected(mask, score);
    mask = _morphClose(mask);

    final direct = _extractBoundary(mask, sampleCount);
    final terrain = _terrainFallback(horizonResult, sampleCount);
    final gradient = _gradientFallback(score, sampleCount);

    if (direct.validity == HorizonValidity.valid &&
        direct.confidence >= _directAcceptConfidence) {
      _lastDebug = HorizonDetectorDebug(
        direct: direct,
        terrainFallback: terrain,
        gradientFallback: gradient,
        selectedSource: direct.source,
      );
      return direct;
    }

    final candidates = <HorizonDetectionResult>[
      direct,
      terrain,
      gradient,
    ].where((candidate) => candidate.validity != HorizonValidity.invalid).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    if (candidates.isEmpty) {
      _lastDebug = HorizonDetectorDebug(
        direct: direct,
        terrainFallback: terrain,
        gradientFallback: gradient,
        selectedSource: HorizonDetectionSource.none,
      );
      return const HorizonDetectionResult.none();
    }
    _lastDebug = HorizonDetectorDebug(
      direct: direct,
      terrainFallback: terrain,
      gradientFallback: gradient,
      selectedSource: candidates.first.source,
    );
    return candidates.first;
  }

  static int _adaptiveSampleCount(int width) {
    if (width >= 320) return 32;
    if (width >= 192) return 24;
    return 16;
  }

  static List<List<double>> _buildSkyScore(
    SegmentationResult result, {
    List<List<double>>? skyConfidenceMap,
    List<List<double>>? brightnessMap,
    List<List<double>>? saturationMap,
  }) {
    return List<List<double>>.generate(result.height, (y) {
      final yNorm = y / math.max(1, result.height - 1);
      final topPrior = math.pow(1.0 - yNorm, 1.15).toDouble();
      return List<double>.generate(result.width, (x) {
        final id = result.classMap[y][x];
        var score = _classSkyPrior(id) * 0.55 + topPrior * 0.35;
        final conf = _sampleMap(skyConfidenceMap, x, y);
        if (conf != null) {
          score = score * 0.7 + conf.clamp(0.0, 1.0) * 0.3;
        }
        final brightness = _sampleMap(brightnessMap, x, y);
        final saturation = _sampleMap(saturationMap, x, y);
        if (brightness != null &&
            saturation != null &&
            brightness >= 0.58 &&
            saturation <= 0.20 &&
            yNorm < 0.72) {
          score += 0.16 + (1.0 - yNorm) * 0.10;
        }
        if (_isObstacleClass(id)) score -= 0.22;
        if (_isGroundClass(id)) score -= 0.10 + yNorm * 0.08;
        return score.clamp(0.0, 1.0);
      }, growable: false);
    }, growable: false);
  }

  static HorizonDetectionResult _extractBoundary(
    List<List<bool>> mask,
    int sampleCount,
  ) {
    if (mask.isEmpty || mask.first.isEmpty) {
      return const HorizonDetectionResult.none();
    }
    final height = mask.length;
    final width = mask.first.length;
    final points = <_SamplePoint>[];
    for (int i = 0; i < sampleCount; i++) {
      final x = ((i * (width - 1)) / math.max(1, sampleCount - 1)).round();
      final y = _findBoundary(mask, x);
      if (y != null) points.add(_SamplePoint(i, x, y));
    }
    if (points.length < (sampleCount * _directCoverageMin).ceil()) {
      return const HorizonDetectionResult.none();
    }
    final median = _median(points.map((point) => point.y.toDouble()).toList());
    final smoothed = <_SamplePoint>[];
    for (int i = 0; i < points.length; i++) {
      smoothed.add(_SamplePoint(points[i].index, points[i].x, median[i].round()));
    }
    return _buildResult(
      _filterOutliers(smoothed, height),
      width,
      height,
      sampleCount,
      confidenceScale: 1.0,
      confidenceBias: 0.04,
      source: HorizonDetectionSource.directSkyMask,
    );
  }

  static HorizonDetectionResult _terrainFallback(
    SegmentationResult result,
    int sampleCount,
  ) {
    final points = <_SamplePoint>[];
    var obstacleHits = 0;
    for (int i = 0; i < sampleCount; i++) {
      final x = ((i * (result.width - 1)) / math.max(1, sampleCount - 1)).round();
      for (int y = 0; y < result.height; y++) {
        final id = result.classMap[y][x];
        if (_isGroundClass(id) || _isObstacleClass(id)) {
          if (_isObstacleClass(id)) obstacleHits++;
          points.add(_SamplePoint(i, x, y));
          break;
        }
      }
    }
    final coverage = points.length / math.max(1, sampleCount);
    final obstacleDominance = obstacleHits / math.max(1, points.length);
    if (coverage < _terrainCoverageMin ||
        obstacleDominance > _terrainObstacleDominanceMax) {
      return const HorizonDetectionResult.none();
    }
    return _buildResult(
      _filterOutliers(points, result.height),
      result.width,
      result.height,
      sampleCount,
      confidenceScale: 0.74,
      confidenceBias: -0.08,
      source: HorizonDetectionSource.terrainFallback,
    );
  }

  static HorizonDetectionResult _gradientFallback(
    List<List<double>> score,
    int sampleCount,
  ) {
    final height = score.length;
    final width = height == 0 ? 0 : score.first.length;
    final points = <_SamplePoint>[];
    for (int i = 0; i < sampleCount; i++) {
      final x = ((i * (width - 1)) / math.max(1, sampleCount - 1)).round();
      var bestY = -1;
      var bestGradient = 0.0;
      for (int y = 1; y < math.max(1, (height * 0.78).floor()) - 1; y++) {
        final gradient = (score[y + 1][x] - score[y - 1][x]).abs();
        if (gradient > bestGradient) {
          bestGradient = gradient;
          bestY = y;
        }
      }
      if (bestY != -1 && bestGradient >= _gradientMinScore) {
        points.add(_SamplePoint(i, x, bestY));
      }
    }
    if (points.length < (sampleCount * _gradientCoverageMin).ceil()) {
      return const HorizonDetectionResult.none();
    }
    return _buildResult(
      _filterOutliers(points, height),
      width,
      height,
      sampleCount,
      confidenceScale: 0.68,
      confidenceBias: -0.12,
      source: HorizonDetectionSource.gradientFallback,
    );
  }

  static HorizonDetectionResult _buildResult(
    List<_SamplePoint> points,
    int width,
    int height,
    int sampleCount, {
    required double confidenceScale,
    required double confidenceBias,
    required HorizonDetectionSource source,
  }) {
    if (points.length < (sampleCount * 0.30).ceil() || width <= 1 || height <= 1) {
      return const HorizonDetectionResult.none();
    }
    final xs = points.map((point) => point.x.toDouble()).toList(growable: false);
    final ys = points.map((point) => point.y.toDouble()).toList(growable: false);
    final fit = _leastSquares(xs, ys);
    final averageY = ys.reduce((a, b) => a + b) / ys.length / height;
    final tilt = math.atan(fit.slope) * 180.0 / math.pi;
    final residuals = <double>[
      for (int i = 0; i < xs.length; i++)
        (ys[i] - (fit.slope * xs[i] + fit.intercept)).abs(),
    ];
    final averageResidual =
        residuals.reduce((a, b) => a + b) / residuals.length;
    final deltas = <double>[
      for (int i = 1; i < ys.length; i++) (ys[i] - ys[i - 1]).abs(),
    ];
    final roughness = deltas.isEmpty
        ? 0.0
        : deltas.reduce((a, b) => a + b) / deltas.length / height;
    final coverageScore = (points.length / sampleCount).clamp(0.0, 1.0);
    final residualScore =
        (1.0 - (averageResidual / (height * 0.11)).clamp(0.0, 1.0))
            .clamp(0.0, 1.0);
    final roughnessScore =
        (1.0 - (roughness / 0.09).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final tiltScore =
        (1.0 - (tilt.abs() / 50.0).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final validityScore = averageY < 0.08 || averageY > 0.90 ? 0.0 : 1.0;
    final sourceScore = source == HorizonDetectionSource.directSkyMask
        ? 1.0
        : source == HorizonDetectionSource.terrainFallback
        ? 0.78
        : 0.70;
    final confidence = ((coverageScore * 0.36 +
                residualScore * 0.24 +
                roughnessScore * 0.18 +
                tiltScore * 0.10 +
                validityScore * 0.12) *
            confidenceScale *
            sourceScore +
        confidenceBias)
        .clamp(0.0, 1.0);
    final validity = validityScore <= 0.01
        ? HorizonValidity.invalid
        : confidence >= _validConfidenceMin
        ? HorizonValidity.valid
        : confidence >= _weakConfidenceMin
        ? HorizonValidity.weak
        : HorizonValidity.invalid;
    return HorizonDetectionResult(
      horizonDetected: validity != HorizonValidity.invalid,
      confidence: confidence,
      stability: confidence * 0.5,
      averageY: averageY,
      tiltAngleDeg: tilt,
      boundaryPoints: [
        for (final point in points)
          HorizonBoundaryPoint(
            xNorm: point.x / (width - 1),
            yNorm: point.y.clamp(0, height - 1) / (height - 1),
          ),
      ],
      horizonType: confidence < 0.40
          ? HorizonType.uncertain
          : roughness < 0.022 && tilt.abs() <= 4.0
          ? HorizonType.flat
          : roughness < 0.09
          ? HorizonType.ridge
          : HorizonType.uncertain,
      source: source,
      validity: validity,
      tiltDirection: _tiltDirection(tilt),
      breakdown: HorizonConfidenceBreakdown(
        coverageScore: coverageScore,
        residualScore: residualScore,
        roughnessScore: roughnessScore,
        tiltScore: tiltScore,
        validityScore: validityScore,
        sourceScore: sourceScore,
      ),
    );
  }

  static SegmentationResult _downsampleSegmentationResult(
    SegmentationResult source,
    int stride,
  ) {
    if (stride <= 1 || source.width < 2 || source.height < 2) {
      return source;
    }
    final downHeight = (source.height / stride).ceil();
    final downWidth = (source.width / stride).ceil();
    final classMap = List<List<int>>.generate(downHeight, (y) {
      final sourceY = math.min(y * stride, source.height - 1);
      return List<int>.generate(downWidth, (x) {
        final sourceX = math.min(x * stride, source.width - 1);
        return source.classMap[sourceY][sourceX];
      }, growable: false);
    }, growable: false);
    return SegmentationResult(
      classMap: classMap,
      height: downHeight,
      width: downWidth,
    );
  }

  static List<List<double>>? _downsampleDoubleMap(
    List<List<double>>? source,
    int stride,
  ) {
    if (source == null || source.isEmpty || stride <= 1) return source;
    final sourceHeight = source.length;
    final sourceWidth = source.first.length;
    if (sourceHeight < 2 || sourceWidth < 2) return source;
    final downHeight = (sourceHeight / stride).ceil();
    final downWidth = (sourceWidth / stride).ceil();
    return List<List<double>>.generate(downHeight, (y) {
      final sourceY = math.min(y * stride, sourceHeight - 1);
      return List<double>.generate(downWidth, (x) {
        final sourceX = math.min(x * stride, sourceWidth - 1);
        return source[sourceY][sourceX];
      }, growable: false);
    }, growable: false);
  }

  static List<_SamplePoint> _filterOutliers(
    List<_SamplePoint> points,
    int height,
  ) {
    if (points.length < 3) return points;
    final fit = _leastSquares(
      points.map((point) => point.x.toDouble()).toList(growable: false),
      points.map((point) => point.y.toDouble()).toList(growable: false),
    );
    final filtered = points.where((point) {
      return (point.y - (fit.slope * point.x + fit.intercept)).abs() <=
          math.max(6.0, height * 0.08);
    }).toList(growable: false);
    return filtered.length >= 3 ? filtered : points;
  }

  static int? _findBoundary(List<List<bool>> mask, int x) {
    var lastSky = -1;
    var gap = 0;
    for (int y = 0; y < mask.length; y++) {
      if (mask[y][x]) {
        lastSky = y;
        gap = 0;
      } else if (lastSky >= 0 && ++gap > 2) {
        return lastSky;
      }
    }
    return lastSky >= 0 && lastSky < mask.length - 1 ? lastSky : null;
  }

  static List<double> _median(List<double> values) {
    return List<double>.generate(values.length, (index) {
      final start = math.max(0, index - 2);
      final end = math.min(values.length, index + 3);
      final window = values.sublist(start, end)..sort();
      return window[window.length ~/ 2];
    }, growable: false);
  }

  static List<List<bool>> _retainTopConnected(
    List<List<bool>> mask,
    List<List<double>> score,
  ) {
    if (mask.isEmpty) return mask;
    final height = mask.length;
    final width = mask.first.length;
    final visited = List.generate(
      height,
      (_) => List<bool>.filled(width, false),
      growable: false,
    );
    final kept = List.generate(
      height,
      (_) => List<bool>.filled(width, false),
      growable: false,
    );
    var bestScore = -1.0;
    List<_IntPoint> best = const [];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (!mask[y][x] || visited[y][x]) continue;
        final queue = <_IntPoint>[_IntPoint(x, y)];
        final points = <_IntPoint>[];
        visited[y][x] = true;
        var touchesTop = y == 0;
        var sum = 0.0;
        while (queue.isNotEmpty) {
          final point = queue.removeLast();
          points.add(point);
          sum += score[point.y][point.x];
          if (point.y == 0) touchesTop = true;
          for (final neighbor in _neighbors(point.x, point.y, width, height)) {
            if (!visited[neighbor.y][neighbor.x] && mask[neighbor.y][neighbor.x]) {
              visited[neighbor.y][neighbor.x] = true;
              queue.add(neighbor);
            }
          }
        }
        final componentScore = touchesTop
            ? points.length * (0.7 + sum / points.length)
            : 0.0;
        if (componentScore > bestScore) {
          bestScore = componentScore;
          best = points;
        }
      }
    }
    for (final point in best) {
      kept[point.y][point.x] = true;
    }
    return kept;
  }

  static List<List<bool>> _morphClose(List<List<bool>> mask) =>
      _erode(_dilate(mask));

  static List<List<bool>> _morphOpen(List<List<bool>> mask) =>
      _dilate(_erode(mask));

  static List<List<bool>> _dilate(List<List<bool>> mask) {
    if (mask.isEmpty) return mask;
    final height = mask.length;
    final width = mask.first.length;
    return List.generate(height, (y) {
      return List<bool>.generate(width, (x) {
        for (int nextY = y - 1; nextY <= y + 1; nextY++) {
          for (int nextX = x - 1; nextX <= x + 1; nextX++) {
            if (nextX < 0 || nextY < 0 || nextX >= width || nextY >= height) {
              continue;
            }
            if (mask[nextY][nextX]) return true;
          }
        }
        return false;
      }, growable: false);
    }, growable: false);
  }

  static List<List<bool>> _erode(List<List<bool>> mask) {
    if (mask.isEmpty) return mask;
    final height = mask.length;
    final width = mask.first.length;
    return List.generate(height, (y) {
      return List<bool>.generate(width, (x) {
        for (int nextY = y - 1; nextY <= y + 1; nextY++) {
          for (int nextX = x - 1; nextX <= x + 1; nextX++) {
            if (nextX < 0 || nextY < 0 || nextX >= width || nextY >= height) {
              return false;
            }
            if (!mask[nextY][nextX]) return false;
          }
        }
        return true;
      }, growable: false);
    }, growable: false);
  }

  static _Line _leastSquares(List<double> xs, List<double> ys) {
    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (int i = 0; i < xs.length; i++) {
      final dx = xs[i] - meanX;
      numerator += dx * (ys[i] - meanY);
      denominator += dx * dx;
    }
    final slope = denominator.abs() < 1e-6 ? 0.0 : numerator / denominator;
    return _Line(slope, meanY - slope * meanX, xs.length);
  }

  static Iterable<_IntPoint> _neighbors(int x, int y, int width, int height) sync* {
    for (int nextY = y - 1; nextY <= y + 1; nextY++) {
      for (int nextX = x - 1; nextX <= x + 1; nextX++) {
        if (nextX == x && nextY == y) continue;
        if (nextX < 0 || nextY < 0 || nextX >= width || nextY >= height) {
          continue;
        }
        yield _IntPoint(nextX, nextY);
      }
    }
  }

  static List<List<bool>> _thresholdSkyMask(List<List<double>> score) {
    final height = score.length;
    final width = height == 0 ? 0 : score.first.length;
    return List.generate(height, (y) {
      final yNorm = y / math.max(1, height - 1);
      final threshold = (0.52 + yNorm * 0.18).clamp(0.50, 0.72);
      return List.generate(
        width,
        (x) => score[y][x] >= threshold,
        growable: false,
      );
    }, growable: false);
  }

  static double _classSkyPrior(int id) {
    if (id == CityscapesClass.sky) return 0.92;
    if (_isObstacleClass(id)) return 0.06;
    if (_isGroundClass(id)) return 0.12;
    return 0.36;
  }

  static double? _sampleMap(List<List<double>>? map, int x, int y) {
    if (map == null || map.isEmpty || y < 0 || y >= map.length) return null;
    if (x < 0 || x >= map[y].length) return null;
    return map[y][x];
  }

  static bool _isGroundClass(int id) {
    return id == CityscapesClass.terrain ||
        id == CityscapesClass.road ||
        id == CityscapesClass.sidewalk ||
        id == CityscapesClass.vegetation ||
        id == CityscapesClass.building;
  }

  static bool _isObstacleClass(int id) {
    return id == CityscapesClass.building ||
        id == CityscapesClass.wall ||
        id == CityscapesClass.fence ||
        id == CityscapesClass.pole ||
        id == CityscapesClass.trafficLight ||
        id == CityscapesClass.trafficSign;
  }

  static TiltDirection _tiltDirection(double tilt) {
    if (tilt.abs() <= 2.0) return TiltDirection.level;
    return tilt > 0 ? TiltDirection.uphillRight : TiltDirection.uphillLeft;
  }
}

class HorizonTemporalStabilizer {
  final double alphaY;
  final double alphaTilt;
  final double alphaConfidence;
  final double acquireThreshold;
  final double releaseThreshold;
  final int acquireFrames;
  final int releaseFrames;

  HorizonDetectionResult? _stable;
  int _validFrames = 0;
  int _invalidFrames = 0;

  HorizonTemporalStabilizer({
    this.alphaY = 0.22,
    this.alphaTilt = 0.18,
    this.alphaConfidence = 0.22,
    this.acquireThreshold = 0.42,
    this.releaseThreshold = 0.24,
    this.acquireFrames = 2,
    this.releaseFrames = 4,
  });

  void reset() {
    _stable = null;
    _validFrames = 0;
    _invalidFrames = 0;
  }

  HorizonDetectionResult update(HorizonDetectionResult raw) {
    final qualifies =
        raw.validity == HorizonValidity.valid && raw.confidence >= acquireThreshold;
    final weak =
        raw.validity == HorizonValidity.invalid || raw.confidence < releaseThreshold;

    final stable = _stable;
    if (stable == null) {
      if (qualifies) {
        _validFrames++;
        if (_validFrames >= acquireFrames) {
          _stable = raw.copyWith(stability: raw.confidence);
        }
      } else {
        _validFrames = 0;
      }
      return _stable ?? raw;
    }

    if (qualifies) {
      _validFrames++;
      _invalidFrames = 0;
      _stable = _merge(stable, raw);
      return _stable!;
    }

    if (weak) {
      _invalidFrames++;
      if (_invalidFrames >= releaseFrames) {
        _stable = raw.copyWith(stability: raw.confidence * 0.4);
      } else {
        _stable = stable.copyWith(
          source: HorizonDetectionSource.temporalHold,
          stability: (stable.stability * 0.92).clamp(0.0, 1.0),
          confidence: math.max(stable.confidence * 0.94, raw.confidence),
        );
      }
      return _stable!;
    }

    _invalidFrames = 0;
    return stable;
  }

  HorizonDetectionResult _merge(
    HorizonDetectionResult previous,
    HorizonDetectionResult current,
  ) {
    double ema(double prev, double next, double alpha) => prev * (1 - alpha) + next * alpha;

    return current.copyWith(
      averageY: previous.averageY == null || current.averageY == null
          ? current.averageY ?? previous.averageY
          : ema(previous.averageY!, current.averageY!, alphaY),
      tiltAngleDeg: previous.tiltAngleDeg == null || current.tiltAngleDeg == null
          ? current.tiltAngleDeg ?? previous.tiltAngleDeg
          : ema(previous.tiltAngleDeg!, current.tiltAngleDeg!, alphaTilt),
      confidence: ema(previous.confidence, current.confidence, alphaConfidence),
      stability: (previous.stability * 0.72 + current.confidence * 0.28)
          .clamp(0.0, 1.0),
      boundaryPoints: _smoothBoundaryPoints(
        previous.boundaryPoints,
        current.boundaryPoints,
      ),
    );
  }

  List<HorizonBoundaryPoint> _smoothBoundaryPoints(
    List<HorizonBoundaryPoint> previous,
    List<HorizonBoundaryPoint> current,
  ) {
    if (previous.isEmpty) return current;
    if (current.isEmpty) return previous;
    if (previous.length != current.length) {
      return current.length >= previous.length ? current : previous;
    }
    return List<HorizonBoundaryPoint>.generate(previous.length, (index) {
      final prev = previous[index];
      final next = current[index];
      return HorizonBoundaryPoint(
        xNorm: next.xNorm,
        yNorm: prev.yNorm * (1 - alphaY) + next.yNorm * alphaY,
      );
    }, growable: false);
  }
}

class LandscapeCompositionAdvisor {
  static const double _landscapeGuideMin = 0.38;
  static const double _skyGuideMin = 0.12;
  static const bool _useLegacySkyRatioTargeting = false;
  static const double _alignedDistance = 0.06;
  static const double _goodDistance = 0.16;
  static const double _unstableConfidence = 0.30;
  static const double _leadingConfidenceMin = 0.30;
  static const double _leadingStrengthMin = 0.26;
  static const double _weakHorizonSceneMin = 0.24;

  const LandscapeCompositionAdvisor();

  bool _hasSufficientLandscapeContext(LandscapeFeatures features) {
    final naturalCoverage =
        (features.vegRatio + features.terrainRatio).clamp(0.0, 1.0);
    final urbanCoverage =
        (features.roadRatio + features.buildingRatio).clamp(0.0, 1.0);
    final openSkyCue = features.skyOnlyRatio >= 0.05;
    final topOpenCue = features.topOpenAreaRatio >= 0.10;
    final horizonCue =
        features.horizonDetected &&
        features.horizonPosition != null &&
        features.horizonConfidence >= 0.20 &&
        features.horizonValidity != HorizonValidity.invalid;
    final naturalScene =
        naturalCoverage >= 0.20 &&
        (features.foregroundRatio >= 0.10 || topOpenCue || openSkyCue);
    final urbanScene =
        features.roadRatio >= 0.10 &&
        features.buildingRatio >= 0.10 &&
        (topOpenCue || openSkyCue || horizonCue);
    final openScene =
        features.landscapeConfidence >= _landscapeGuideMin &&
        (naturalCoverage + urbanCoverage) >= 0.22 &&
        (topOpenCue || openSkyCue);

    return horizonCue || naturalScene || urbanScene || openScene;
  }

  bool _hasOutdoorLeadingContext(LandscapeFeatures features) {
    final naturalCoverage =
        (features.vegRatio + features.terrainRatio).clamp(0.0, 1.0);
    final strongNaturalScene =
        naturalCoverage >= 0.22 && features.foregroundRatio >= 0.10;
    final streetScene =
        features.roadRatio >= 0.12 &&
        (features.buildingRatio >= 0.10 ||
            features.skyOnlyRatio >= 0.05 ||
            (features.horizonDetected && features.horizonConfidence >= 0.20));
    final skylineScene =
        features.skyOnlyRatio >= 0.05 ||
        (features.horizonDetected && features.horizonConfidence >= 0.20);

    return strongNaturalScene || streetScene || skylineScene;
  }

  LandscapeOverlayAdvice build(LandscapeFeatures features) {
    final hasSufficientLandscapeContext =
        _hasSufficientLandscapeContext(features);
    final hasLeadingGuide = features.leadingConfidence >= _leadingConfidenceMin &&
        features.leadingLineStrength >= _leadingStrengthMin;
    final hasOutdoorLeadingContext = _hasOutdoorLeadingContext(features);
    final hasWeakHorizonScene = features.horizonPosition != null &&
        features.horizonConfidence >= _weakHorizonSceneMin &&
        features.topOpenAreaRatio >= 0.10;
    final reliableHorizon = features.horizonDetected &&
        features.horizonValidity != HorizonValidity.invalid &&
        features.horizonConfidence >= _unstableConfidence &&
        features.horizonPosition != null;

    if (!hasSufficientLandscapeContext && !reliableHorizon) {
      return const LandscapeOverlayAdvice(
        overlayState: OverlayGuidanceState.searching,
        targetHorizonY: null,
        recommendedAdjustmentY: null,
        tiltDirection: TiltDirection.unknown,
        primaryGuidance: '풍경이 더 잘 보이도록 배경을 조금 더 담아보세요.',
        secondaryGuidance: null,
        showHorizonGuide: false,
      );
    }

    if (hasSufficientLandscapeContext &&
        !reliableHorizon &&
        hasLeadingGuide &&
        hasOutdoorLeadingContext &&
        !hasWeakHorizonScene) {
      final targetX = features.leadingTargetX ?? 0.5;
      final offset = targetX - 0.5;
      return LandscapeOverlayAdvice(
        overlayState: offset.abs() <= 0.10
            ? OverlayGuidanceState.aligned
            : OverlayGuidanceState.searching,
        targetHorizonY: null,
        recommendedAdjustmentY: null,
        tiltDirection: features.tiltDirection,
        primaryGuidance: offset.abs() <= 0.10
            ? '좋아요. 장면의 중심축이 안정적으로 맞고 있어요.'
            : offset < 0
            ? '장면의 중심축이 왼쪽에 있어요. 화면 중앙으로 조금 맞춰보세요.'
            : '장면의 중심축이 오른쪽에 있어요. 화면 중앙으로 조금 맞춰보세요.',
        secondaryGuidance: '이 장면은 수평선보다 길이나 경계선 방향을 먼저 맞춰보세요.',
        showHorizonGuide: false,
      );
    }

    if (!reliableHorizon && hasWeakHorizonScene) {
      final targetY = _targetY(features);
      final delta = targetY == null || features.horizonPosition == null
          ? null
          : features.horizonPosition! - targetY;
      final aligned = delta == null || delta.abs() <= _goodDistance;
      return LandscapeOverlayAdvice(
        overlayState: aligned
            ? OverlayGuidanceState.aligned
            : delta > 0
            ? OverlayGuidanceState.adjustDown
            : OverlayGuidanceState.adjustUp,
        targetHorizonY: targetY,
        recommendedAdjustmentY: delta == null ? null : -delta,
        tiltDirection: features.tiltDirection,
        primaryGuidance: aligned
            ? '좋아요. 노을 풍경의 수평선이 안정적으로 있어요.'
            : delta > 0
            ? '카메라를 조금 내려 노을 수평선을 맞춰보세요.'
            : '카메라를 조금 올려 노을 수평선을 맞춰보세요.',
        secondaryGuidance: '하늘 색이 강한 장면이라 수평선 위치를 먼저 맞춰보세요.',
        showHorizonGuide: targetY != null,
      );
    }

    if (!reliableHorizon) {
      return const LandscapeOverlayAdvice(
        overlayState: OverlayGuidanceState.searching,
        targetHorizonY: null,
        recommendedAdjustmentY: null,
        tiltDirection: TiltDirection.unknown,
        primaryGuidance: '수평선이 더 잘 보이도록 프레임을 단순하게 맞춰보세요.',
        secondaryGuidance: null,
        showHorizonGuide: false,
      );
    }

    final targetY = _targetY(features);
    if (targetY == null) {
      return LandscapeOverlayAdvice(
        overlayState: OverlayGuidanceState.unstable,
        targetHorizonY: null,
        recommendedAdjustmentY: null,
        tiltDirection: features.tiltDirection,
        primaryGuidance: '장면 경계는 보이지만 수평선이 아직 불안정해요.',
        secondaryGuidance: _tiltHint(features),
        showHorizonGuide: false,
      );
    }

    final delta = features.horizonPosition! - targetY;
    final strictlyAligned = delta.abs() <= _alignedDistance;
    final aligned = strictlyAligned || delta.abs() <= _goodDistance;
    final overlayState = aligned
        ? OverlayGuidanceState.aligned
        : delta > 0
        ? OverlayGuidanceState.adjustDown
        : OverlayGuidanceState.adjustUp;

    return LandscapeOverlayAdvice(
      overlayState: overlayState,
      targetHorizonY: targetY,
      recommendedAdjustmentY: aligned ? null : -delta,
      tiltDirection: features.tiltDirection,
      primaryGuidance: aligned
          ? '좋아요. 수평선이 3분할선 근처에 안정적으로 있어요.'
          : delta > 0
          ? '카메라를 조금 내려 수평선을 맞춰보세요.'
          : '카메라를 조금 올려 수평선을 맞춰보세요.',
      secondaryGuidance: _tiltHint(features),
      showHorizonGuide: true,
    );
  }

  double? _targetY(LandscapeFeatures features) {
    if (features.horizonPosition == null) {
      return _useLegacySkyRatioTargeting ? _legacySkyRatioTargetY(features) : null;
    }
    if (_useLegacySkyRatioTargeting) {
      return _legacySkyRatioTargetY(features);
    }

    final nearest = _nearestThirdTargetY(features.horizonPosition!);
    final preferred = _legacySkyRatioTargetY(features);
    if (preferred == null) return nearest;

    final nearestDistance = (features.horizonPosition! - nearest).abs();
    final preferredDistance = (features.horizonPosition! - preferred).abs();
    final distancesAreClose = (nearestDistance - preferredDistance).abs() <= 0.04;
    if (!distancesAreClose) return nearest;

    final strongSkyPreference =
        features.skyOnlyRatio >= 0.62 || features.skyOnlyRatio <= 0.26;
    return strongSkyPreference ? preferred : nearest;
  }

  double? _legacySkyRatioTargetY(LandscapeFeatures features) {
    if (features.skyOnlyRatio < _skyGuideMin &&
        features.topOpenAreaRatio < (_skyGuideMin + 0.05)) {
      return null;
    }
    if (features.skyOnlyRatio > 0.58) return 2 / 3;
    if (features.skyOnlyRatio < 0.34) return 1 / 3;
    return features.topOpenAreaRatio > 0.36 ? 2 / 3 : 1 / 3;
  }

  double _nearestThirdTargetY(double horizonY) {
    final upperDistance = (horizonY - (1 / 3)).abs();
    final lowerDistance = (horizonY - (2 / 3)).abs();
    return upperDistance <= lowerDistance ? 1 / 3 : 2 / 3;
  }

  String? _tiltHint(LandscapeFeatures features) {
    if (features.horizonTiltDeg == null ||
        features.tiltDirection == TiltDirection.unknown ||
        features.tiltDirection == TiltDirection.level ||
        features.horizonTiltDeg!.abs() <= 2.5) {
      return null;
    }
    return features.tiltDirection == TiltDirection.uphillRight
        ? '오른쪽이 조금 올라가 보여요.'
        : '왼쪽이 조금 올라가 보여요.';
  }
}

class _SamplePoint {
  final int index;
  final int x;
  final int y;

  const _SamplePoint(this.index, this.x, this.y);
}

class _IntPoint {
  final int x;
  final int y;

  const _IntPoint(this.x, this.y);
}

class _Line {
  final double slope;
  final double intercept;
  final int support;

  const _Line(this.slope, this.intercept, this.support);
}

class _LeadingLineMetrics {
  final double strength;
  final double confidence;
  final double? entryX;
  final double? targetX;
  final double? angleDeg;
  final double diagonalStrength;
  final double diagonalConfidence;

  const _LeadingLineMetrics({
    required this.strength,
    required this.confidence,
    required this.entryX,
    required this.targetX,
    required this.angleDeg,
    required this.diagonalStrength,
    required this.diagonalConfidence,
  });

  const _LeadingLineMetrics.none()
    : strength = 0.0,
      confidence = 0.0,
      entryX = null,
      targetX = null,
      angleDeg = null,
      diagonalStrength = 0.0,
      diagonalConfidence = 0.0;
}
