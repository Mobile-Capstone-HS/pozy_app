import 'dart:collection';
import 'dart:math' as math;

import 'composition_guide_resolver.dart';
import 'composition_resolver.dart';
import 'composition_summary.dart';
import 'landscape_analyzer.dart';

class CompositionEngine {
  static const int kGuideHistorySize = 5;
  static const int kGuideMinVotesToConfirm = 3;
  static const int kGuideMinHoldFrames = 3;
  static const int kGuideMessageCooldownMs = 600;
  static const double kHorizonAdjustDistance = 0.18;

  final CompositionGuideResolver _guideResolver;
  final ListQueue<CompositionGuideState> _guideHistory =
      ListQueue<CompositionGuideState>();

  CompositionGuideState? _stableState;
  String _stableMessage = '좋아요, 지금 구도로 촬영해보세요';
  DateTime _lastStateChangedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _stateHoldFrames = 0;

  CompositionEngine({
    CompositionGuideResolver guideResolver = const CompositionGuideResolver(),
  }) : _guideResolver = guideResolver;

  void reset() {
    _guideHistory.clear();
    _stableState = null;
    _stableMessage = '좋아요, 지금 구도로 촬영해보세요';
    _lastStateChangedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _stateHoldFrames = 0;
  }

  CompositionSummary evaluate({
    required LandscapeFeatures features,
    required CompositionDecision decision,
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    final skyRatio = features.skyOnlyRatio.clamp(0.0, 1.0);
    final groundRatio = _computeGroundRatio(features);

    final horizonY = features.horizonPosition;
    final horizonValid = horizonY != null &&
        features.horizonConfidence >= 0.22 &&
        features.horizonValidity != HorizonValidity.invalid &&
        features.horizonStability >= 0.18 &&
        horizonY >= 0.10 &&
        horizonY <= 0.90;
    final distanceToUpperThird =
        horizonY == null ? 1.0 : (horizonY - (1 / 3)).abs();
    final distanceToLowerThird =
        horizonY == null ? 1.0 : (horizonY - (2 / 3)).abs();
    final bestHorizonThirdDistance =
        math.min(distanceToUpperThird, distanceToLowerThird);

    final horizonScore = horizonValid
        ? (1.0 - (bestHorizonThirdDistance / 0.33)).clamp(0.0, 1.0)
        : 0.35;
    final ratioScore = _computeRatioScore(skyRatio);
    final thirdsScore = (0.7 * horizonScore + 0.3 * ratioScore).clamp(0.0, 1.0);
    final compositionQualityScore =
        (0.45 * horizonScore + 0.30 * ratioScore + 0.25 * thirdsScore)
            .clamp(0.0, 1.0);

    final candidateGuide = _guideResolver.resolve(
      CompositionGuideInput(
        features: features,
        decision: decision,
        leadingScore: 0.0,
        horizonScore: horizonScore,
        ratioScore: ratioScore,
        thirdsScore: thirdsScore,
        compositionQualityScore: compositionQualityScore,
        horizonYNorm: horizonY,
        bestHorizonThirdDistance: bestHorizonThirdDistance,
        skyRatio: skyRatio,
        groundRatio: groundRatio,
        vanishingOffsetX: 0.0,
        leadingAligned: false,
        horizonValid: horizonValid,
        horizonNeedsAdjust:
            horizonValid && bestHorizonThirdDistance > kHorizonAdjustDistance,
        ratioNeedsAdjust: _ratioNeedsAdjust(skyRatio),
      ),
    );

    final stabilizedGuide = _stabilizeGuide(candidateGuide, ts);

    return CompositionSummary(
      leadingAligned: false,
      leadingTemplateType: decision.overlayType,
      leadingScore: 0.0,
      leadingStabilityScore: 0.0,
      vanishingPointXNorm: null,
      vanishingPointYNorm: null,
      vanishingOffsetX: 0.0,
      vanishingOffsetY: 0.0,
      skyRatio: skyRatio,
      groundRatio: groundRatio,
      horizonYNorm: horizonY,
      distanceToUpperThird: distanceToUpperThird,
      distanceToLowerThird: distanceToLowerThird,
      bestHorizonThirdDistance: bestHorizonThirdDistance,
      vanishingPointThirdDistance: 1.0,
      compositionQualityScore: compositionQualityScore,
      guideState: stabilizedGuide.state,
      guideMessage: stabilizedGuide.message,
      compositionMode: decision.compositionMode,
    );
  }

  double _computeGroundRatio(LandscapeFeatures f) {
    return (f.terrainRatio +
            f.roadRatio +
            f.vegRatio +
            f.buildingRatio +
            f.waterRatio)
        .clamp(0.0, 1.0);
  }

  bool _ratioNeedsAdjust(double skyRatio) {
    if (skyRatio < CompositionGuideResolver.kSkyRatioGuideMin) return false;
    return skyRatio < CompositionGuideResolver.kRatioLowThreshold ||
        skyRatio > CompositionGuideResolver.kRatioHighThreshold;
  }

  double _computeRatioScore(double skyRatio) {
    if (skyRatio < CompositionGuideResolver.kSkyRatioGuideMin) {
      return 0.5;
    }
    final upper =
        (1.0 - ((skyRatio - (1.0 / 3.0)).abs() / 0.33)).clamp(0.0, 1.0);
    final lower =
        (1.0 - ((skyRatio - (2.0 / 3.0)).abs() / 0.34)).clamp(0.0, 1.0);
    return math.max(upper, lower);
  }

  CompositionGuideResult _stabilizeGuide(
    CompositionGuideResult candidate,
    DateTime now,
  ) {
    _guideHistory.addLast(candidate.state);
    while (_guideHistory.length > kGuideHistorySize) {
      _guideHistory.removeFirst();
    }

    final majority = _majorityState() ?? candidate.state;
    final majorityVotes = _guideHistory.where((e) => e == majority).length;

    if (_stableState == null) {
      _stableState = majority;
      _stableMessage = candidate.message;
      _lastStateChangedAt = now;
      _stateHoldFrames = 0;
      return CompositionGuideResult(state: _stableState!, message: _stableMessage);
    }

    if (majority == _stableState) {
      _stateHoldFrames++;
      return CompositionGuideResult(state: _stableState!, message: _stableMessage);
    }

    final inCooldown =
        now.difference(_lastStateChangedAt).inMilliseconds < kGuideMessageCooldownMs;
    final canSwitch = majorityVotes >= kGuideMinVotesToConfirm &&
        _stateHoldFrames >= kGuideMinHoldFrames &&
        !inCooldown;

    if (canSwitch) {
      _stableState = majority;
      _stableMessage = candidate.message;
      _lastStateChangedAt = now;
      _stateHoldFrames = 0;
    } else {
      _stateHoldFrames++;
    }

    return CompositionGuideResult(state: _stableState!, message: _stableMessage);
  }

  CompositionGuideState? _majorityState() {
    if (_guideHistory.isEmpty) return null;
    final counts = <CompositionGuideState, int>{};
    for (final state in _guideHistory) {
      counts[state] = (counts[state] ?? 0) + 1;
    }
    CompositionGuideState? best;
    var bestCount = -1;
    counts.forEach((key, value) {
      if (value > bestCount) {
        best = key;
        bestCount = value;
      }
    });
    return best;
  }
}
