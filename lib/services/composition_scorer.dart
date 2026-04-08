import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/composition_candidate.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Abstraction layer — swap in a learned scorer without touching the pipeline.
// ─────────────────────────────────────────────────────────────────────────────

/// Strategy interface for composition scoring.
///
/// ### ML integration point
/// Replace [HeuristicCompositionScorer] with a learned model by creating
/// a new subclass:
/// ```dart
/// class AestheticMLScorer extends CompositionScorerBase {
///   final TFLiteModel _model = ...;
///
///   @override
///   List<CompositionCandidate> score({...}) {
///     return candidates
///         .map((c) => c.copyWith(score: _model.infer(c, subjectNormalized)))
///         .toList()
///       ..sort((a, b) => b.score.compareTo(a.score));
///   }
/// }
/// ```
/// Then inject it in [_CameraScreenState]:
/// ```dart
/// final CompositionScorerBase _scorer = AestheticMLScorer();
/// ```
abstract class CompositionScorerBase {
  /// Returns [candidates] with updated scores, sorted best-first.
  List<CompositionCandidate> score({
    required List<CompositionCandidate> candidates,
    required Rect? subjectNormalized,
    required Size previewSize,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Heuristic implementation
// ─────────────────────────────────────────────────────────────────────────────

/// Heuristic composition scorer.
///
/// Scores each [CompositionCandidate] on a [0,1] scale and returns the list
/// sorted descending by score.
///
/// ### Score components (weights sum to 1.0)
/// | Component             | Weight | Description                                    |
/// |-----------------------|--------|------------------------------------------------|
/// | Subject containment   | 0.30   | Is the subject fully inside the crop?          |
/// | Thirds placement      | 0.25   | Is the subject near a thirds intersection?     |
/// | Margin balance        | 0.15   | Is there adequate margin on all four sides?    |
/// | Visual center balance | 0.15   | Is the subject reasonably centred in crop?     |
/// | Crop coverage         | 0.15   | Coverage relative to expected for aspect ratio |
///
/// ### Future replacement
/// Implement [CompositionScorerBase] and inject it in [_CameraScreenState].
class HeuristicCompositionScorer implements CompositionScorerBase {
  const HeuristicCompositionScorer();

  @override
  List<CompositionCandidate> score({
    required List<CompositionCandidate> candidates,
    required Rect? subjectNormalized,
    required Size previewSize,
  }) {
    final previewAspect =
        previewSize.width / previewSize.height.clamp(1.0, double.infinity);
    final scored = candidates
        .map((c) => c.copyWith(
              score: _scoreCandidate(c, subjectNormalized, previewAspect),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  double _scoreCandidate(
      CompositionCandidate candidate, Rect? subject, double previewAspect) {
    final r = candidate.normalizedRect;
    double score = 0.0;

    // --- Crop coverage (0.15) — relative to expected area for this ratio -----
    // Normalise against the natural target area for this aspect ratio so
    // portrait crops are not penalised merely for being narrower on a landscape
    // preview.  A crop that fills its expected 85 % target gets full score.
    final normAspect =
        candidate.targetAspectRatio / previewAspect.clamp(0.001, double.infinity);
    final targetNh = math.sqrt(0.85 / normAspect).clamp(0.0, 1.0);
    final targetNw = (targetNh * normAspect).clamp(0.0, 1.0);
    final expectedArea = (targetNw * targetNh).clamp(0.001, 1.0);
    final cropArea = r.width * r.height;
    score += 0.15 * (cropArea / expectedArea).clamp(0.0, 1.0);

    // --- Margin balance (0.15) ----------------------------------
    final margins = [
      r.left,
      1.0 - r.right,
      r.top,
      1.0 - r.bottom,
    ];
    final minMargin = margins.reduce(math.min);
    // Full reward when min margin >= 5 % of preview.
    score += 0.15 * (minMargin / 0.05).clamp(0.0, 1.0);

    if (subject == null) {
      // No subject: reward crops near the preview centre.
      // Note: in normal flow the caller resolves a fallback subject, so this
      // branch is only reached if the caller explicitly passes null.
      final cx = r.center.dx;
      final cy = r.center.dy;
      final centreScore =
          (1.0 - (cx - 0.5).abs() * 2) * (1.0 - (cy - 0.5).abs() * 2);
      score += 0.70 * centreScore.clamp(0.0, 1.0);
      return score.clamp(0.0, 1.0);
    }

    // --- Subject containment (0.30) ----------------------------
    final fullyContained = subject.left >= r.left &&
        subject.right <= r.right &&
        subject.top >= r.top &&
        subject.bottom <= r.bottom;
    if (fullyContained) {
      score += 0.30;
    } else {
      final intersection = subject.intersect(r);
      if (!intersection.isEmpty) {
        final subjectArea = subject.width * subject.height;
        if (subjectArea > 0) {
          final overlapRatio =
              (intersection.width * intersection.height) / subjectArea;
          score += 0.15 * overlapRatio.clamp(0.0, 1.0);
        }
      }
    }

    // --- Thirds placement (0.25) --------------------------------
    if (r.width > 0 && r.height > 0) {
      final sx = (subject.center.dx - r.left) / r.width;
      final sy = (subject.center.dy - r.top) / r.height;
      const thirdsPoints = [
        Offset(1 / 3, 1 / 3),
        Offset(1 / 3, 2 / 3),
        Offset(2 / 3, 1 / 3),
        Offset(2 / 3, 2 / 3),
      ];
      double bestThirds = 0;
      for (final tp in thirdsPoints) {
        final dist = math.sqrt(
          (sx - tp.dx) * (sx - tp.dx) + (sy - tp.dy) * (sy - tp.dy),
        );
        bestThirds = math.max(bestThirds, (1.0 - dist * 3.0).clamp(0.0, 1.0));
      }
      score += 0.25 * bestThirds;
    }

    // --- Visual centre balance (0.15) ---------------------------
    final horizOffset = (subject.center.dx - r.center.dx).abs();
    final centreScore = (1.0 - horizOffset * 4.0).clamp(0.0, 1.0);
    score += 0.15 * centreScore;

    return score.clamp(0.0, 1.0);
  }
}

/// Backwards-compatible alias so existing usages compile without change.
///
/// Prefer [HeuristicCompositionScorer] for new code.
typedef CompositionScorer = HeuristicCompositionScorer;
