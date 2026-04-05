import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/composition_candidate.dart';
import '../models/tracked_subject.dart';

/// The readiness state of the current composition.
enum ReadinessState {
  /// No clear subject or recommendation.
  guide,

  /// A recommendation is active, but alignment is low.
  almost,

  /// The subject is well-aligned with the active recommendation.
  good,
}

/// Contains the calculated feedback for the current frame.
class FeedbackResult {
  final ReadinessState state;
  final double alignmentScore;
  final bool isShutterReady;

  const FeedbackResult({
    required this.state,
    required this.alignmentScore,
    required this.isShutterReady,
  });

  static const FeedbackResult guide = FeedbackResult(
    state: ReadinessState.guide,
    alignmentScore: 0.0,
    isShutterReady: false,
  );
}

/// Calculates and stabilizes feedback on composition quality.
class CompositionFeedbackService {
  final double goodThreshold;
  final int goodHoldFrames;

  ReadinessState _currentState = ReadinessState.guide;
  int _goodFrameCounter = 0;

  CompositionFeedbackService({
    this.goodThreshold = 0.85,
    this.goodHoldFrames = 3,
  });

  FeedbackResult calculateFeedback({
    required CompositionCandidate? activeCandidate,
    required TrackedSubject? subject,
  }) {
    if (activeCandidate == null || subject == null) {
      _currentState = ReadinessState.guide;
      _goodFrameCounter = 0;
      return FeedbackResult.guide;
    }

    final alignmentScore = _calculateAlignmentScore(activeCandidate, subject.normalizedBox);
    _updateState(alignmentScore);

    return FeedbackResult(
      state: _currentState,
      alignmentScore: alignmentScore,
      isShutterReady: _currentState == ReadinessState.good,
    );
  }

  void _updateState(double alignmentScore) {
    if (alignmentScore >= goodThreshold) {
      _goodFrameCounter++;
      if (_goodFrameCounter >= goodHoldFrames) {
        _currentState = ReadinessState.good;
      } else {
        // Stay in 'almost' while counting up to 'good'.
        _currentState = ReadinessState.almost;
      }
    } else {
      _goodFrameCounter = 0;
      // Hysteresis: to leave 'good' state, score must drop significantly.
      if (_currentState == ReadinessState.good && alignmentScore > goodThreshold - 0.1) {
        // Stay in 'good' for a bit longer.
      } else if (alignmentScore > 0.3) {
        _currentState = ReadinessState.almost;
      } else {
        _currentState = ReadinessState.guide;
      }
    }
  }

  double _calculateAlignmentScore(CompositionCandidate candidate, Rect subject) {
    final r = candidate.normalizedRect;
    double score = 0.0;

    // 1. Containment (weight: 0.4)
    final fullyContained = subject.left >= r.left &&
        subject.right <= r.right &&
        subject.top >= r.top &&
        subject.bottom <= r.bottom;
    score += fullyContained ? 0.4 : 0;

    // 2. Center/Thirds Alignment (weight: 0.4)
    if (r.width > 0 && r.height > 0) {
      final sx = (subject.center.dx - r.left) / r.width;
      final sy = (subject.center.dy - r.top) / r.height;
      double alignmentFactor = 0;

      if (candidate.id.contains('thirds')) {
        final List<Offset> thirdsPoints = [];
        if (candidate.id.contains('_tl')) thirdsPoints.add(const Offset(1/3, 1/3));
        if (candidate.id.contains('_tr')) thirdsPoints.add(const Offset(2/3, 1/3));
        // Add bl, br if they exist in the future
        final dist = (Offset(sx, sy) - thirdsPoints.first).distance;
        alignmentFactor = (1.0 - dist * 1.8).clamp(0.0, 1.0);
      } else { // Center or other
        final dist = (Offset(sx, sy) - const Offset(0.5, 0.5)).distance;
        alignmentFactor = (1.0 - dist * 1.5).clamp(0.0, 1.0);
      }
      score += 0.4 * alignmentFactor;
    }

    // 3. Margin / Cutoff Avoidance (weight: 0.2)
    final margin = math.min(
      subject.left - r.left,
      r.right - subject.right,
    );
    // Penalize if horizontal margin is too small (<5% of crop width)
    if (margin < r.width * 0.05) {
      score -= 0.2;
    } else {
      score += 0.2;
    }

    return score.clamp(0.0, 1.0);
  }

  void reset() {
    _currentState = ReadinessState.guide;
    _goodFrameCounter = 0;
  }
}
