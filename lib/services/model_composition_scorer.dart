import 'dart:typed_data';

import 'package:flutter/material.dart' show Rect, Size;

import '../models/composition_candidate.dart';
import 'composition_model_runner.dart';
import 'composition_scorer.dart';

/// Composition scorer that fuses AADB model scores with the heuristic baseline.
///
/// ### Scoring strategy — Option A (model primary, heuristic as stabilising fallback)
///
/// When model scores are cached from the previous inference cycle:
/// ```
///   finalScore = 0.7 × modelScore + 0.3 × heuristicScore
/// ```
/// When the model is unavailable or has not yet produced scores:
/// ```
///   finalScore = heuristicScore  (pure heuristic fallback)
/// ```
///
/// **Rationale for Option A over Option B (equal blend):**
/// The AADB model is trained on human aesthetic judgements and directly
/// measures composition quality.  A 0.7 weight gives it primacy while the
/// 0.3 heuristic component prevents degenerate model outliers from surfacing
/// (e.g., a crop that scores high aesthetically but excludes the subject).
/// The weights are constructor-configurable if a different balance is needed.
///
/// ### Threading model
/// [score] is **synchronous** — it returns immediately using the model scores
/// cached from the previous [updateModelScores] call.  [updateModelScores] is
/// **async** and is fired from the camera screen as a background operation on
/// each composition throttle tick.  The detection pipeline is never blocked.
///
/// ### Performance
/// Only the top [topKForModel] heuristic candidates are sent to the model.
/// Default is 3 out of 25.  This reduces per-tick inference from 25 to 3
/// forward passes, making it practical at the 200 ms throttle interval.
class ModelCompositionScorer implements CompositionScorerBase {
  ModelCompositionScorer({
    CompositionModelRunner? modelRunner,
    HeuristicCompositionScorer? heuristicScorer,
    this.modelWeight = 0.7,
    this.heuristicWeight = 0.3,
    this.topKForModel = 3,
  })  : _runner = modelRunner ?? CompositionModelRunner(),
        _heuristic = heuristicScorer ?? const HeuristicCompositionScorer();

  final CompositionModelRunner _runner;
  final HeuristicCompositionScorer _heuristic;

  /// Weight applied to the AADB model score in the fused result.
  final double modelWeight;

  /// Weight applied to the heuristic score in the fused result.
  final double heuristicWeight;

  /// Number of top heuristic candidates to re-rank with the model per cycle.
  final int topKForModel;

  // ── Internal async state ─────────────────────────────────────────────────

  /// Model scores from the most recent [updateModelScores] call.
  /// Key: candidate.id, Value: AADB score in [0, 1].
  final Map<String, double> _cachedModelScores = {};

  bool _isInferring = false;
  bool _modelEverSucceeded = false;
  int _lastInferenceMs = 0;

  // ── Public read-only accessors for debug overlay ────────────────────────

  /// True when model inference has succeeded at least once and the model file
  /// is still available.
  bool get isUsingModel => _modelEverSucceeded && _runner.isAvailable;

  /// True while an async [updateModelScores] call is in flight.
  bool get isInferring => _isInferring;

  /// Wall-clock duration of the last [updateModelScores] call in milliseconds.
  int get lastInferenceMs => _lastInferenceMs;

  /// One-line debug string describing the current scorer state.
  String get debugSummary {
    if (!_runner.isAvailable) {
      return '[scorer: heuristic-only — model unavailable]';
    }
    if (!_modelEverSucceeded) {
      return '[scorer: heuristic-only — model loading]';
    }
    final mode = _isInferring ? 'inferring…' : 'model+heuristic';
    return '[scorer: $mode | top$topKForModel | ${_lastInferenceMs}ms]';
  }

  // ── CompositionScorerBase — synchronous ──────────────────────────────────

  @override
  List<CompositionCandidate> score({
    required List<CompositionCandidate> candidates,
    required Rect? subjectNormalized,
    required Size previewSize,
  }) {
    // 1. Always run the heuristic as the baseline.
    final heuristicRanked = _heuristic.score(
      candidates: candidates,
      subjectNormalized: subjectNormalized,
      previewSize: previewSize,
    );

    // 2. If no cached model scores, return pure heuristic.
    if (_cachedModelScores.isEmpty || !_runner.isAvailable) {
      return heuristicRanked;
    }

    // 3. Fuse model scores with heuristic scores where available.
    final fused = heuristicRanked.map((c) {
      final modelScore = _cachedModelScores[c.id];
      if (modelScore == null) return c; // no model data for this id → keep heuristic
      final fusedScore =
          (modelWeight * modelScore + heuristicWeight * c.score).clamp(0.0, 1.0);
      return c.copyWith(score: fusedScore);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return fused;
  }

  // ── Async model inference — fire-and-forget ──────────────────────────────

  /// Score the top-[topKForModel] heuristic candidates with the AADB model.
  ///
  /// Call this fire-and-forget from the camera screen after the heuristic
  /// scoring pass.  Updated scores will be used on the **next** [score] call.
  ///
  /// [frameBytes]:    raw JPEG/bytes from [YOLOViewController.captureFrame].
  /// [heuristicTop]:  pre-ranked candidate list (heuristic order, best first).
  /// [frameSize]:     pixel dimensions of the captured frame; pass [Size.zero]
  ///                  to let [CompositionModelRunner] read the decoded size.
  Future<void> updateModelScores({
    required Uint8List frameBytes,
    required List<CompositionCandidate> heuristicTop,
    required Size frameSize,
  }) async {
    // Skip if another inference is already running or model is gone.
    if (_isInferring || !_runner.isAvailable) return;

    final toScore = heuristicTop.take(topKForModel).toList();
    if (toScore.isEmpty) return;

    _isInferring = true;
    final sw = Stopwatch()..start();

    for (final candidate in toScore) {
      final score = await _runner.scoreCandidate(
        frameBytes: frameBytes,
        normalizedRect: candidate.normalizedRect,
        frameSize: frameSize,
      );
      if (score != null) {
        _cachedModelScores[candidate.id] = score;
        _modelEverSucceeded = true;
      }
    }

    sw.stop();
    _lastInferenceMs = sw.elapsedMilliseconds;
    _isInferring = false;
  }

  /// Clear all cached model scores and reset inference state.
  /// Call when composition mode is turned off.
  void reset() {
    _cachedModelScores.clear();
    _isInferring = false;
  }
}
