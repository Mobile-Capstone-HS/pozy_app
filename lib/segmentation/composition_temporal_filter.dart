import 'dart:math' as math;

import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class CompositionTemporalFilter {
  final double alpha;
  final int requiredConsecutiveFrames;
  final int specializedRequiredConsecutiveFrames;
  final double switchConfidenceMin;
  final double switchConfidenceDeltaMin;
  final double specializedSwitchConfidenceMin;
  final double specializedSwitchConfidenceDeltaMin;
  final double featureChangeThreshold;
  final int specializedLockFrames;

  LandscapeFeatures? _smoothed;
  LandscapeFeatures? _stableFeatures;
  CompositionMode? _stableMode;
  CompositionDecision? _stableDecision;
  CompositionMode? _pendingMode;
  int _pendingCount = 0;
  int _specializedLockRemaining = 0;

  CompositionTemporalFilter({
    this.alpha = 0.25,
    this.requiredConsecutiveFrames = 3,
    this.specializedRequiredConsecutiveFrames = 4,
    this.switchConfidenceMin = 0.40,
    this.switchConfidenceDeltaMin = 0.10,
    this.specializedSwitchConfidenceMin = 0.50,
    this.specializedSwitchConfidenceDeltaMin = 0.14,
    this.featureChangeThreshold = 0.12,
    this.specializedLockFrames = 5,
  });

  void reset() {
    _smoothed = null;
    _stableFeatures = null;
    _stableMode = null;
    _stableDecision = null;
    _pendingMode = null;
    _pendingCount = 0;
    _specializedLockRemaining = 0;
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

  CompositionDecision stabilize(
    CompositionDecision candidate,
    LandscapeFeatures features,
  ) {
    if (_specializedLockRemaining > 0) {
      _specializedLockRemaining--;
    }

    final stable = _stableDecision;
    if (stable == null) {
      _stableFeatures = features;
      _stableMode = candidate.compositionMode;
      _stableDecision = candidate;
      if (_isSpecialized(candidate)) {
        _specializedLockRemaining = specializedLockFrames;
      }
      return candidate;
    }

    if (candidate.compositionMode == _stableMode) {
      _pendingMode = null;
      _pendingCount = 0;
      _stableFeatures = features;
      _stableDecision = candidate;
      if (_isSpecialized(candidate)) {
        _specializedLockRemaining = specializedLockFrames;
      }
      return candidate;
    }

    final stableFeatures = _stableFeatures;
    final confidenceDelta = candidate.confidence - stable.confidence;
    final featureDelta = stableFeatures == null
        ? 1.0
        : _featureDelta(stableFeatures, features);
    final hasMeaningfulSceneChange =
        featureDelta >= featureChangeThreshold ||
        confidenceDelta >= (switchConfidenceDeltaMin * 1.6);
    final involvesSpecialized =
        _isSpecialized(stable) || _isSpecialized(candidate);
    final requiredFrames = involvesSpecialized
        ? specializedRequiredConsecutiveFrames
        : requiredConsecutiveFrames;
    final minConfidence = involvesSpecialized
        ? math.max(switchConfidenceMin, specializedSwitchConfidenceMin)
        : switchConfidenceMin;
    final minConfidenceDelta = involvesSpecialized
        ? math.max(switchConfidenceDeltaMin, specializedSwitchConfidenceDeltaMin)
        : switchConfidenceDeltaMin;
    final minFeatureDelta = involvesSpecialized
        ? featureChangeThreshold * 1.15
        : featureChangeThreshold;
    final hasStrongLandscapeBase = _hasStrongLandscapeBase(features, candidate);
    final isLockedSpecializedSwitch = involvesSpecialized &&
        _specializedLockRemaining > 0 &&
        candidate.compositionMode != _stableMode;

    if (_isSpecialized(candidate) && !hasStrongLandscapeBase) {
      _pendingMode = null;
      _pendingCount = 0;
      return stable;
    }

    if (isLockedSpecializedSwitch &&
        (confidenceDelta < (minConfidenceDelta * 1.5) ||
            featureDelta < (minFeatureDelta * 1.5))) {
      _pendingMode = null;
      _pendingCount = 0;
      return stable;
    }

    if (candidate.confidence < minConfidence ||
        confidenceDelta < minConfidenceDelta ||
        (!hasMeaningfulSceneChange && featureDelta < minFeatureDelta)) {
      _pendingMode = null;
      _pendingCount = 0;
      return stable;
    }

    if (_pendingMode != candidate.compositionMode) {
      _pendingMode = candidate.compositionMode;
      _pendingCount = 1;
      return stable;
    }

    _pendingCount++;
    if (_pendingCount >= requiredFrames && candidate.confidence >= minConfidence) {
      _stableFeatures = features;
      _stableMode = candidate.compositionMode;
      _stableDecision = candidate;
      _pendingMode = null;
      _pendingCount = 0;
      _specializedLockRemaining =
          _isSpecialized(candidate) ? specializedLockFrames : 0;
      return candidate;
    }

    return stable;
  }

  double _featureDelta(LandscapeFeatures a, LandscapeFeatures b) {
    double delta(double x, double y) => (x - y).abs();

    final values = <double>[
      delta(a.landscapeConfidence, b.landscapeConfidence),
      delta(a.skyOnlyRatio, b.skyOnlyRatio),
      delta(a.topOpenAreaRatio, b.topOpenAreaRatio),
      delta(a.horizonConfidence, b.horizonConfidence),
      delta(a.horizonStability, b.horizonStability),
      delta(a.roadRatio, b.roadRatio),
      delta(a.buildingRatio, b.buildingRatio),
      delta(a.vegRatio + a.terrainRatio, b.vegRatio + b.terrainRatio),
      delta(a.leadingConfidence, b.leadingConfidence),
      delta(a.leadingLineStrength, b.leadingLineStrength),
      delta(a.foregroundRatio, b.foregroundRatio),
    ];

    final sum = values.reduce((x, y) => x + y);
    return sum / values.length;
  }

  bool _isSpecialized(CompositionDecision decision) {
    return decision.compositionMode == CompositionMode.horizon ||
        decision.overlayType == 'leading_center';
  }

  bool _hasStrongLandscapeBase(
    LandscapeFeatures features,
    CompositionDecision candidate,
  ) {
    final naturalCoverage = features.vegRatio + features.terrainRatio;
    final urbanCoverage = features.roadRatio + features.buildingRatio;
    final horizonBase =
        features.horizonDetected && features.horizonConfidence >= 0.26;
    final skyBase = features.skyOnlyRatio >= 0.06;
    final structuredOutdoorBase =
        naturalCoverage >= 0.30 ||
        (features.foregroundRatio >= 0.12 && naturalCoverage >= 0.22) ||
        urbanCoverage >= 0.24;

    if (candidate.compositionMode == CompositionMode.horizon) {
      return features.landscapeConfidence >= 0.42 ||
          horizonBase ||
          skyBase ||
          structuredOutdoorBase;
    }

    if (candidate.overlayType == 'leading_center') {
      return features.landscapeConfidence >= 0.44 ||
          structuredOutdoorBase ||
          (naturalCoverage >= 0.26 && features.foregroundRatio >= 0.10) ||
          (features.roadRatio >= 0.12 && features.buildingRatio >= 0.10);
    }

    return true;
  }
}
