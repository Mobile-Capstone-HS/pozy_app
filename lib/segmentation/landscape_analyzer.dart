import 'dart:math' as math;

import 'fastscnn_segmentor.dart';

class LandscapeFeatures {
  final double skyRatio;
  final double vegRatio;
  final double terrainRatio;
  final double roadRatio;
  final double buildingRatio;
  final double waterRatio;
  final double openness;
  final double landscapeConfidence;
  final double? horizonPosition;
  final double? horizonTiltDeg;
  final double? horizonThirdDistance;
  final double horizonConfidence;
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
    required this.vegRatio,
    required this.terrainRatio,
    required this.roadRatio,
    required this.buildingRatio,
    required this.waterRatio,
    required this.openness,
    required this.landscapeConfidence,
    required this.horizonPosition,
    required this.horizonTiltDeg,
    required this.horizonThirdDistance,
    required this.horizonConfidence,
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
    double? vegRatio,
    double? terrainRatio,
    double? roadRatio,
    double? buildingRatio,
    double? waterRatio,
    double? openness,
    double? landscapeConfidence,
    double? horizonPosition,
    double? horizonTiltDeg,
    double? horizonThirdDistance,
    double? horizonConfidence,
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
      vegRatio: vegRatio ?? this.vegRatio,
      terrainRatio: terrainRatio ?? this.terrainRatio,
      roadRatio: roadRatio ?? this.roadRatio,
      buildingRatio: buildingRatio ?? this.buildingRatio,
      waterRatio: waterRatio ?? this.waterRatio,
      openness: openness ?? this.openness,
      landscapeConfidence: landscapeConfidence ?? this.landscapeConfidence,
      horizonPosition: horizonPosition ?? this.horizonPosition,
      horizonTiltDeg: horizonTiltDeg ?? this.horizonTiltDeg,
      horizonThirdDistance: horizonThirdDistance ?? this.horizonThirdDistance,
      horizonConfidence: horizonConfidence ?? this.horizonConfidence,
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

abstract final class LandscapeAnalyzer {
  static LandscapeFeatures analyzeFeatures(SegmentationResult result) {
    final skyRatio = _computeSkyLikeRatio(result);
    final vegRatio = result.classRatio(CityscapesClass.vegetation);
    final terrainRatio = result.classRatio(CityscapesClass.terrain);
    final roadRatio = result.classRatio(CityscapesClass.road);
    final buildingRatio = result.classRatio(CityscapesClass.building);
    final waterRatio = 0.0;
    final openness = _computeOpenness(result);
    final landscapeConfidence = (0.38 * skyRatio +
            0.22 * (vegRatio + terrainRatio) +
            0.18 * roadRatio +
            0.12 * buildingRatio +
            0.10 * openness)
        .clamp(0.0, 1.0);

    final horizonStats = _detectHorizonStats(result);
    final midCol = result.width ~/ 2;
    final vegLeftRatio = result.classRatioInCols(
      CityscapesClass.vegetation,
      0,
      midCol,
    );
    final vegRightRatio = result.classRatioInCols(
      CityscapesClass.vegetation,
      midCol,
      result.width,
    );
    final bottomStart = result.height * 2 ~/ 3;
    final foregroundRatio =
        result.classRatioInRows(
          CityscapesClass.vegetation,
          bottomStart,
          result.height,
        ) +
        result.classRatioInRows(
          CityscapesClass.terrain,
          bottomStart,
          result.height,
        );

    return LandscapeFeatures(
      skyRatio: skyRatio,
      vegRatio: vegRatio,
      terrainRatio: terrainRatio,
      roadRatio: roadRatio,
      buildingRatio: buildingRatio,
      waterRatio: waterRatio,
      openness: openness,
      landscapeConfidence: landscapeConfidence,
      horizonPosition: horizonStats?.position,
      horizonTiltDeg: horizonStats?.tiltDeg,
      horizonThirdDistance: horizonStats?.thirdDistance,
      horizonConfidence: horizonStats?.confidence ?? 0.0,
      diagonalStrength: 0.0,
      diagonalConfidence: 0.0,
      leadingLineStrength: 0.0,
      leadingConfidence: 0.0,
      dominantLineAngleDeg: null,
      leadingEntryX: null,
      leadingTargetX: null,
      nativeLeadingScore: 0.0,
      nativeLeadingLineCount: 0.0,
      nativeLeadingEntryX: null,
      nativeLeadingTargetX: null,
      vegLeftRatio: vegLeftRatio,
      vegRightRatio: vegRightRatio,
      foregroundRatio: foregroundRatio,
    );
  }

  static double _computeSkyLikeRatio(SegmentationResult result) {
    final rawSkyRatio = result.classRatio(CityscapesClass.sky).clamp(0.0, 1.0);
    final height = result.height;
    final width = result.width;
    if (height <= 0 || width <= 0) return rawSkyRatio;

    final topEnd = (height * 0.45).floor().clamp(1, height);
    int total = 0;
    int skyLike = 0;
    int obstacle = 0;

    for (int y = 0; y < topEnd; y++) {
      final row = result.classMap[y];
      for (int x = 0; x < width; x++) {
        total++;
        final id = row[x];
        if (_isSkyLikeCandidateClass(id)) {
          skyLike++;
        }
        if (_isObstacleClass(id)) {
          obstacle++;
        }
      }
    }

    if (total == 0) return rawSkyRatio;
    final topSkyLikeRatio = skyLike / total;
    final topObstacleRatio = obstacle / total;
    final skyLikeSignal =
        (topSkyLikeRatio - topObstacleRatio * 0.20).clamp(0.0, 1.0);

    var corrected = math.max(
      rawSkyRatio,
      (rawSkyRatio * 0.55 + skyLikeSignal * 0.45).clamp(0.0, 1.0),
    );
    if (rawSkyRatio < 0.12 && topSkyLikeRatio > 0.22) {
      corrected = math.max(corrected, (topSkyLikeRatio * 0.85).clamp(0.0, 0.42));
    }
    return corrected;
  }

  static bool _isSkyLikeCandidateClass(int id) {
    if (id == CityscapesClass.sky) return true;
    return !_isObstacleClass(id);
  }

  static bool _isObstacleClass(int id) {
    return id == CityscapesClass.building ||
        id == CityscapesClass.wall ||
        id == CityscapesClass.fence ||
        id == CityscapesClass.pole ||
        id == CityscapesClass.trafficLight ||
        id == CityscapesClass.trafficSign;
  }

  static double _computeOpenness(SegmentationResult result) {
    final xStart = result.width ~/ 3;
    final xEnd = result.width * 2 ~/ 3;
    final yStart = result.height ~/ 3;
    final yEnd = result.height * 2 ~/ 3;

    int total = 0;
    int open = 0;
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
    if (total == 0) return 0;
    return open / total;
  }

  static _HorizonStats? _detectHorizonStats(SegmentationResult result) {
    final width = result.width;
    final height = result.height;
    if (width < 8 || height < 8) return null;

    final sampleStep = math.max(1, width ~/ 24);
    final xs = <int>[];
    final ys = <int>[];

    for (int x = 0; x < width; x += sampleStep) {
      int? boundaryY;
      for (int y = 0; y < height; y++) {
        if (result.classMap[y][x] != CityscapesClass.sky) {
          boundaryY = y;
          break;
        }
      }
      if (boundaryY != null) {
        xs.add(x);
        ys.add(boundaryY);
      }
    }

    if (xs.length < 4) return null;

    final avgY = ys.reduce((a, b) => a + b) / ys.length;
    final position = avgY / height;
    final x0 = xs.first.toDouble();
    final y0 = ys.first.toDouble();
    final x1 = xs.last.toDouble();
    final y1 = ys.last.toDouble();
    final dx = (x1 - x0).abs() < 1e-6 ? 1.0 : (x1 - x0);
    final slope = (y1 - y0) / dx;
    final tiltDeg = math.atan(slope) * 180.0 / math.pi;
    final thirdDistance = math.min(
      (position - (1.0 / 3.0)).abs(),
      (position - (2.0 / 3.0)).abs(),
    );
    final variance =
        ys.map((y) => (y - avgY) * (y - avgY)).reduce((a, b) => a + b) /
        ys.length;
    final varianceNorm = math.min(1.0, variance / (height * height * 0.025));
    final coverage = ys.length / ((width / sampleStep).ceil());
    final linearity = 1.0 - math.min(1.0, tiltDeg.abs() / 55.0);
    final confidence =
        (coverage * 0.45 + (1.0 - varianceNorm) * 0.40 + linearity * 0.15)
            .clamp(0.0, 1.0);

    return _HorizonStats(
      position: position,
      tiltDeg: tiltDeg,
      thirdDistance: thirdDistance,
      confidence: confidence,
    );
  }
}

class _HorizonStats {
  final double position;
  final double tiltDeg;
  final double thirdDistance;
  final double confidence;

  const _HorizonStats({
    required this.position,
    required this.tiltDeg,
    required this.thirdDistance,
    required this.confidence,
  });
}
