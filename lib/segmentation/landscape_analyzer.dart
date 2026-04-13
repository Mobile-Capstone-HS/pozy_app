import 'dart:math' as math;

import 'fastscnn_segmentor.dart';

enum HorizonType { flat, ridge, uncertain }

class HorizonBoundaryPoint {
  final double xNorm;
  final double yNorm;

  const HorizonBoundaryPoint({required this.xNorm, required this.yNorm});
}

class HorizonDetectionResult {
  final bool horizonDetected;
  final double confidence;
  final double? averageY;
  final double? tiltAngleDeg;
  final List<HorizonBoundaryPoint> boundaryPoints;
  final HorizonType horizonType;

  const HorizonDetectionResult({
    required this.horizonDetected,
    required this.confidence,
    required this.averageY,
    required this.tiltAngleDeg,
    required this.boundaryPoints,
    required this.horizonType,
  });

  const HorizonDetectionResult.none()
    : horizonDetected = false,
      confidence = 0.0,
      averageY = null,
      tiltAngleDeg = null,
      boundaryPoints = const [],
      horizonType = HorizonType.uncertain;
}

class LandscapeFeatures {
  final double skyRatio;
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
  final List<HorizonBoundaryPoint> boundaryPoints;
  final HorizonType horizonType;
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
    required this.horizonDetected,
    required this.horizonPosition,
    required this.horizonTiltDeg,
    required this.horizonThirdDistance,
    required this.horizonConfidence,
    required this.boundaryPoints,
    required this.horizonType,
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
    bool? horizonDetected,
    double? horizonPosition,
    double? horizonTiltDeg,
    double? horizonThirdDistance,
    double? horizonConfidence,
    List<HorizonBoundaryPoint>? boundaryPoints,
    HorizonType? horizonType,
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
      horizonDetected: horizonDetected ?? this.horizonDetected,
      horizonPosition: horizonPosition ?? this.horizonPosition,
      horizonTiltDeg: horizonTiltDeg ?? this.horizonTiltDeg,
      horizonThirdDistance: horizonThirdDistance ?? this.horizonThirdDistance,
      horizonConfidence: horizonConfidence ?? this.horizonConfidence,
      boundaryPoints: boundaryPoints ?? this.boundaryPoints,
      horizonType: horizonType ?? this.horizonType,
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
  static const int _samples = 16;
  static const int _horizonDownsampleStride = 3;

  static LandscapeFeatures analyzeFeatures(
    SegmentationResult result, {
    List<List<double>>? skyConfidenceMap,
    List<List<double>>? brightnessMap,
    List<List<double>>? saturationMap,
  }) {
    final skyRatio = _computeSkyLikeRatio(result);
    final vegRatio = result.classRatio(CityscapesClass.vegetation);
    final terrainRatio = result.classRatio(CityscapesClass.terrain);
    final roadRatio = result.classRatio(CityscapesClass.road);
    final buildingRatio = result.classRatio(CityscapesClass.building);
    final openness = _computeOpenness(result);
    final confidence = (0.38 * skyRatio +
            0.22 * (vegRatio + terrainRatio) +
            0.18 * roadRatio +
            0.12 * buildingRatio +
            0.10 * openness)
        .clamp(0.0, 1.0);
    final horizonResult = _horizonDownsampleStride > 1
        ? _downsampleSegmentationResult(result, _horizonDownsampleStride)
        : result;
    final horizon = _detectHorizon(
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
    final midCol = result.width ~/ 2;
    final foregroundStart = result.height * 2 ~/ 3;
    return LandscapeFeatures(
      skyRatio: skyRatio,
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
      boundaryPoints: horizon.boundaryPoints,
      horizonType: horizon.horizonType,
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
      foregroundRatio:
          result.classRatioInRows(
            CityscapesClass.vegetation,
            foregroundStart,
            result.height,
          ) +
          result.classRatioInRows(
            CityscapesClass.terrain,
            foregroundStart,
            result.height,
          ),
    );
  }

  static HorizonDetectionResult _detectHorizon(
    SegmentationResult result, {
    List<List<double>>? skyConfidenceMap,
    List<List<double>>? brightnessMap,
    List<List<double>>? saturationMap,
  }) {
    final score = _buildSkyScore(
      result,
      skyConfidenceMap: skyConfidenceMap,
      brightnessMap: brightnessMap,
      saturationMap: saturationMap,
    );
    var mask = _thresholdSkyMask(score);
    mask = _morphClose(mask);
    mask = _morphOpen(mask);
    mask = _retainTopConnected(mask, score);
    mask = _morphClose(mask);

    final direct = _extractBoundary(mask);
    if (direct.horizonDetected && direct.confidence >= 0.34) return direct;

    final candidates = <HorizonDetectionResult>[
      direct,
      _terrainFallback(result),
      _gradientFallback(score),
    ].where((e) => e.horizonDetected).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    return candidates.isEmpty
        ? const HorizonDetectionResult.none()
        : candidates.first;
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
        var s = _classSkyPrior(id) * 0.55 + topPrior * 0.35;
        final conf = _sampleMap(skyConfidenceMap, x, y);
        if (conf != null) s = s * 0.7 + conf.clamp(0.0, 1.0) * 0.3;
        final b = _sampleMap(brightnessMap, x, y);
        final sat = _sampleMap(saturationMap, x, y);
        if (b != null && sat != null && b >= 0.58 && sat <= 0.20 && yNorm < 0.72) {
          s += 0.16 + (1.0 - yNorm) * 0.10;
        }
        if (_isObstacleClass(id)) s -= 0.22;
        if (_isGroundClass(id)) s -= 0.10 + yNorm * 0.08;
        return s.clamp(0.0, 1.0);
      });
    });
  }

  static HorizonDetectionResult _extractBoundary(List<List<bool>> mask) {
    if (mask.isEmpty || mask.first.isEmpty) {
      return const HorizonDetectionResult.none();
    }
    final h = mask.length;
    final w = mask.first.length;
    final points = <_SamplePoint>[];
    for (int i = 0; i < _samples; i++) {
      final x = ((i * (w - 1)) / math.max(1, _samples - 1)).round();
      final y = _findBoundary(mask, x);
      if (y != null) points.add(_SamplePoint(i, x, y));
    }
    if (points.length < (_samples * 0.40).ceil()) {
      return const HorizonDetectionResult.none();
    }
    final median = _median(points.map((e) => e.y.toDouble()).toList());
    final smoothed = <_SamplePoint>[];
    for (int i = 0; i < points.length; i++) {
      smoothed.add(_SamplePoint(points[i].index, points[i].x, median[i].round()));
    }
    return _buildResult(_filterOutliers(smoothed, h), w, h, 1.0, 0.04);
  }

  static HorizonDetectionResult _terrainFallback(SegmentationResult result) {
    final points = <_SamplePoint>[];
    for (int i = 0; i < _samples; i++) {
      final x = ((i * (result.width - 1)) / math.max(1, _samples - 1)).round();
      for (int y = 0; y < result.height; y++) {
        final id = result.classMap[y][x];
        if (_isGroundClass(id) || _isObstacleClass(id)) {
          points.add(_SamplePoint(i, x, y));
          break;
        }
      }
    }
    return _buildResult(
      _filterOutliers(points, result.height),
      result.width,
      result.height,
      0.78,
      -0.06,
    );
  }

  static HorizonDetectionResult _gradientFallback(List<List<double>> score) {
    final h = score.length;
    final w = h == 0 ? 0 : score.first.length;
    final points = <_SamplePoint>[];
    for (int i = 0; i < _samples; i++) {
      final x = ((i * (w - 1)) / math.max(1, _samples - 1)).round();
      var bestY = -1;
      var best = 0.0;
      for (int y = 1; y < h - 1; y++) {
        final g = (score[y + 1][x] - score[y - 1][x]).abs();
        if (g > best) {
          best = g;
          bestY = y;
        }
      }
      if (bestY != -1 && best >= 0.14) points.add(_SamplePoint(i, x, bestY));
    }
    return _buildResult(_filterOutliers(points, h), w, h, 0.72, -0.10);
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
      final srcY = math.min(y * stride, source.height - 1);
      return List<int>.generate(downWidth, (x) {
        final srcX = math.min(x * stride, source.width - 1);
        return source.classMap[srcY][srcX];
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
      final srcY = math.min(y * stride, sourceHeight - 1);
      return List<double>.generate(downWidth, (x) {
        final srcX = math.min(x * stride, sourceWidth - 1);
        return source[srcY][srcX];
      }, growable: false);
    }, growable: false);
  }

  static HorizonDetectionResult _buildResult(
    List<_SamplePoint> points,
    int width,
    int height,
    double confidenceScale,
    double confidenceBias,
  ) {
    if (points.length < (_samples * 0.28).ceil() || width <= 1 || height <= 1) {
      return const HorizonDetectionResult.none();
    }
    final xs = points.map((e) => e.x.toDouble()).toList();
    final ys = points.map((e) => e.y.toDouble()).toList();
    final fit = _leastSquares(xs, ys);
    final avgY = ys.reduce((a, b) => a + b) / ys.length / height;
    final tilt = math.atan(fit.slope) * 180.0 / math.pi;
    final residuals = <double>[
      for (int i = 0; i < xs.length; i++) (ys[i] - (fit.slope * xs[i] + fit.intercept)).abs(),
    ];
    final avgResidual = residuals.reduce((a, b) => a + b) / residuals.length;
    final deltas = <double>[
      for (int i = 1; i < ys.length; i++) (ys[i] - ys[i - 1]).abs(),
    ];
    final roughness = deltas.isEmpty
        ? 0.0
        : deltas.reduce((a, b) => a + b) / deltas.length / height;
    final coverage = points.length / _samples;
    final confidence = ((coverage * 0.40 +
                (1.0 - (avgResidual / (height * 0.11)).clamp(0.0, 1.0)) * 0.30 +
                (1.0 - (roughness / 0.09).clamp(0.0, 1.0)) * 0.20 +
                (1.0 - (tilt.abs() / 50.0).clamp(0.0, 1.0)) * 0.10) *
            confidenceScale +
        confidenceBias)
        .clamp(0.0, 1.0);
    return HorizonDetectionResult(
      horizonDetected: confidence >= 0.22,
      confidence: confidence,
      averageY: avgY,
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
    );
  }

  static List<_SamplePoint> _filterOutliers(List<_SamplePoint> points, int height) {
    if (points.length < 3) return points;
    final fit = _leastSquares(
      points.map((e) => e.x.toDouble()).toList(),
      points.map((e) => e.y.toDouble()).toList(),
    );
    final filtered = points
        .where(
          (point) =>
              (point.y - (fit.slope * point.x + fit.intercept)).abs() <=
              math.max(6.0, height * 0.08),
        )
        .toList();
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
    });
  }

  static List<List<bool>> _retainTopConnected(
    List<List<bool>> mask,
    List<List<double>> score,
  ) {
    if (mask.isEmpty) return mask;
    final h = mask.length;
    final w = mask.first.length;
    final visited = List.generate(h, (_) => List<bool>.filled(w, false));
    final kept = List.generate(h, (_) => List<bool>.filled(w, false));
    var bestScore = -1.0;
    List<_IntPoint> best = const [];
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (!mask[y][x] || visited[y][x]) continue;
        final queue = <_IntPoint>[_IntPoint(x, y)];
        final points = <_IntPoint>[];
        visited[y][x] = true;
        var touchesTop = y == 0;
        var sum = 0.0;
        while (queue.isNotEmpty) {
          final p = queue.removeLast();
          points.add(p);
          sum += score[p.y][p.x];
          if (p.y == 0) touchesTop = true;
          for (final n in _neighbors(p.x, p.y, w, h)) {
            if (!visited[n.y][n.x] && mask[n.y][n.x]) {
              visited[n.y][n.x] = true;
              queue.add(n);
            }
          }
        }
        final compScore = touchesTop ? points.length * (0.7 + sum / points.length) : 0.0;
        if (compScore > bestScore) {
          bestScore = compScore;
          best = points;
        }
      }
    }
    for (final p in best) {
      kept[p.y][p.x] = true;
    }
    return kept;
  }

  static List<List<bool>> _morphClose(List<List<bool>> mask) =>
      _erode(_dilate(mask));

  static List<List<bool>> _morphOpen(List<List<bool>> mask) =>
      _dilate(_erode(mask));

  static List<List<bool>> _dilate(List<List<bool>> mask) {
    if (mask.isEmpty) return mask;
    final h = mask.length;
    final w = mask.first.length;
    return List.generate(h, (y) {
      return List<bool>.generate(w, (x) {
        for (int ny = y - 1; ny <= y + 1; ny++) {
          for (int nx = x - 1; nx <= x + 1; nx++) {
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (mask[ny][nx]) return true;
          }
        }
        return false;
      });
    });
  }

  static List<List<bool>> _erode(List<List<bool>> mask) {
    if (mask.isEmpty) return mask;
    final h = mask.length;
    final w = mask.first.length;
    return List.generate(h, (y) {
      return List<bool>.generate(w, (x) {
        for (int ny = y - 1; ny <= y + 1; ny++) {
          for (int nx = x - 1; nx <= x + 1; nx++) {
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) return false;
            if (!mask[ny][nx]) return false;
          }
        }
        return true;
      });
    });
  }

  static _Line _leastSquares(List<double> xs, List<double> ys) {
    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = ys.reduce((a, b) => a + b) / ys.length;
    var n = 0.0;
    var d = 0.0;
    for (int i = 0; i < xs.length; i++) {
      final dx = xs[i] - meanX;
      n += dx * (ys[i] - meanY);
      d += dx * dx;
    }
    final slope = d.abs() < 1e-6 ? 0.0 : n / d;
    return _Line(slope, meanY - slope * meanX, xs.length);
  }

  static Iterable<_IntPoint> _neighbors(int x, int y, int w, int h) sync* {
    for (int ny = y - 1; ny <= y + 1; ny++) {
      for (int nx = x - 1; nx <= x + 1; nx++) {
        if (nx == x && ny == y) continue;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        yield _IntPoint(nx, ny);
      }
    }
  }

  static List<List<bool>> _thresholdSkyMask(List<List<double>> score) {
    final h = score.length;
    final w = h == 0 ? 0 : score.first.length;
    return List.generate(h, (y) {
      final yNorm = y / math.max(1, h - 1);
      final th = (0.52 + yNorm * 0.18).clamp(0.50, 0.72);
      return List.generate(w, (x) => score[y][x] >= th);
    });
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

  static bool _isGroundClass(int id) =>
      id == CityscapesClass.terrain ||
      id == CityscapesClass.road ||
      id == CityscapesClass.sidewalk ||
      id == CityscapesClass.vegetation ||
      id == CityscapesClass.building;

  static bool _isObstacleClass(int id) =>
      id == CityscapesClass.building ||
      id == CityscapesClass.wall ||
      id == CityscapesClass.fence ||
      id == CityscapesClass.pole ||
      id == CityscapesClass.trafficLight ||
      id == CityscapesClass.trafficSign;

  static double _computeSkyLikeRatio(SegmentationResult result) {
    final raw = result.classRatio(CityscapesClass.sky).clamp(0.0, 1.0);
    if (result.height <= 0 || result.width <= 0) return raw;
    final topEnd = (result.height * 0.45).floor().clamp(1, result.height);
    var total = 0;
    var skyLike = 0;
    var obstacle = 0;
    for (int y = 0; y < topEnd; y++) {
      for (int x = 0; x < result.width; x++) {
        total++;
        final id = result.classMap[y][x];
        if (id == CityscapesClass.sky || !_isObstacleClass(id)) skyLike++;
        if (_isObstacleClass(id)) obstacle++;
      }
    }
    if (total == 0) return raw;
    final topSignal = (skyLike / total - (obstacle / total) * 0.20).clamp(0.0, 1.0);
    var corrected = math.max(raw, (raw * 0.55 + topSignal * 0.45).clamp(0.0, 1.0));
    if (raw < 0.12 && skyLike / total > 0.22) {
      corrected = math.max(corrected, ((skyLike / total) * 0.85).clamp(0.0, 0.42));
    }
    return corrected;
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
