import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class CompositionTemporalFilter {
  final double alpha;
  final int requiredConsecutiveFrames;

  LandscapeFeatures? _smoothed;
  CompositionMode? _stableMode;
  CompositionDecision? _stableDecision;
  CompositionMode? _pendingMode;
  int _pendingCount = 0;

  CompositionTemporalFilter({
    this.alpha = 0.25,
    this.requiredConsecutiveFrames = 2,
  });

  void reset() {
    _smoothed = null;
    _stableMode = null;
    _stableDecision = null;
    _pendingMode = null;
    _pendingCount = 0;
  }

  LandscapeFeatures smooth(LandscapeFeatures raw) {
    final prev = _smoothed;
    if (prev == null) {
      _smoothed = raw;
      return raw;
    }

    double ema(double p, double c) => p * (1 - alpha) + c * alpha;

    final smoothed = raw.copyWith(
      skyRatio: ema(prev.skyRatio, raw.skyRatio),
      skyOnlyRatio: ema(prev.skyOnlyRatio, raw.skyOnlyRatio),
      topOpenAreaRatio: ema(prev.topOpenAreaRatio, raw.topOpenAreaRatio),
      vegRatio: ema(prev.vegRatio, raw.vegRatio),
      terrainRatio: ema(prev.terrainRatio, raw.terrainRatio),
      roadRatio: ema(prev.roadRatio, raw.roadRatio),
      buildingRatio: ema(prev.buildingRatio, raw.buildingRatio),
      waterRatio: ema(prev.waterRatio, raw.waterRatio),
      openness: ema(prev.openness, raw.openness),
      landscapeConfidence: ema(
        prev.landscapeConfidence,
        raw.landscapeConfidence,
      ),
      horizonConfidence: ema(prev.horizonConfidence, raw.horizonConfidence),
      horizonStability: ema(prev.horizonStability, raw.horizonStability),
      vegLeftRatio: ema(prev.vegLeftRatio, raw.vegLeftRatio),
      vegRightRatio: ema(prev.vegRightRatio, raw.vegRightRatio),
      foregroundRatio: ema(prev.foregroundRatio, raw.foregroundRatio),
      horizonTiltDeg: raw.horizonTiltDeg,
      horizonPosition: raw.horizonPosition,
      horizonThirdDistance: raw.horizonThirdDistance,
      horizonDetected: raw.horizonDetected,
      horizonType: raw.horizonType,
      horizonSource: raw.horizonSource,
      horizonValidity: raw.horizonValidity,
      tiltDirection: raw.tiltDirection,
      boundaryPoints: raw.boundaryPoints,
    );

    _smoothed = smoothed;
    return smoothed;
  }

  CompositionDecision stabilize(CompositionDecision candidate) {
    final stable = _stableDecision;
    if (stable == null) {
      _stableMode = candidate.compositionMode;
      _stableDecision = candidate;
      return candidate;
    }

    if (candidate.compositionMode == _stableMode) {
      _pendingMode = null;
      _pendingCount = 0;
      _stableDecision = candidate;
      return candidate;
    }

    if (_pendingMode != candidate.compositionMode) {
      _pendingMode = candidate.compositionMode;
      _pendingCount = 1;
      return stable;
    }

    _pendingCount++;
    if (_pendingCount >= requiredConsecutiveFrames && candidate.confidence >= 0.35) {
      _stableMode = candidate.compositionMode;
      _stableDecision = candidate;
      _pendingMode = null;
      _pendingCount = 0;
      return candidate;
    }

    return stable;
  }
}
