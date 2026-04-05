import 'package:flutter/material.dart';

import '../models/composition_candidate.dart';

/// Prevents the active composition candidate from jittering between frames.
///
/// Strategy:
/// - A new candidate is only promoted if it beats the current one by at
///   least [scoreHysteresis] AND holds the top position for [holdFrames]
///   consecutive frames.
/// - The rendered rect is linearly interpolated toward the target each frame
///   using [smoothAlpha] (EMA).
class CompositionStabilizer {
  final double scoreHysteresis;
  final double smoothAlpha;
  final int holdFrames;

  CompositionStabilizer({
    this.scoreHysteresis = 0.08,
    this.smoothAlpha = 0.20,
    this.holdFrames = 4,
  });

  CompositionCandidate? _activeCandidate;
  Rect? _smoothedRect;
  String? _pendingId;
  int _holdCounter = 0;

  /// Returns the stabilized active candidate with [smoothedRect] set for
  /// smooth rendering, or null if [rankedCandidates] is empty.
  CompositionCandidate? stabilize(List<CompositionCandidate> rankedCandidates) {
    if (rankedCandidates.isEmpty) {
      _activeCandidate = null;
      _smoothedRect = null;
      _pendingId = null;
      _holdCounter = 0;
      return null;
    }

    final best = rankedCandidates.first;

    if (_activeCandidate == null) {
      // First frame: accept immediately.
      _activeCandidate = best;
      _smoothedRect = best.normalizedRect;
      _pendingId = null;
      _holdCounter = 0;
      return _withSmoothedRect(_activeCandidate!);
    }

    final scoreGap = best.score - _activeCandidate!.score;
    final isSame = best.id == _activeCandidate!.id;

    if (!isSame && scoreGap >= scoreHysteresis) {
      // Candidate wants to switch – start or continue hold timer.
      if (_pendingId == best.id) {
        _holdCounter++;
      } else {
        _pendingId = best.id;
        _holdCounter = 1;
      }
      if (_holdCounter >= holdFrames) {
        _activeCandidate = best;
        _pendingId = null;
        _holdCounter = 0;
      }
    } else {
      // Same candidate or not significantly better – reset pending.
      _pendingId = null;
      _holdCounter = 0;
    }

    // Smooth the rendering rect toward the active candidate's target rect.
    _smoothedRect = _lerp(_smoothedRect!, _activeCandidate!.normalizedRect);

    return _withSmoothedRect(_activeCandidate!);
  }

  Rect _lerp(Rect prev, Rect target) {
    return Rect.fromLTRB(
      prev.left + (target.left - prev.left) * smoothAlpha,
      prev.top + (target.top - prev.top) * smoothAlpha,
      prev.right + (target.right - prev.right) * smoothAlpha,
      prev.bottom + (target.bottom - prev.bottom) * smoothAlpha,
    );
  }

  CompositionCandidate _withSmoothedRect(CompositionCandidate candidate) {
    return candidate.copyWith(smoothedRect: _smoothedRect);
  }

  void reset() {
    _activeCandidate = null;
    _smoothedRect = null;
    _pendingId = null;
    _holdCounter = 0;
  }
}
