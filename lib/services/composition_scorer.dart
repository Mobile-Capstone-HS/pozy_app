import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/composition_candidate.dart';

/// Heuristic composition scorer.
///
/// Scores each [CompositionCandidate] on a [0,1] scale and returns the list
/// sorted descending by score.
///
/// ### Score components (weights sum to 1.0)
/// | Component             | Weight | Description                                 |
/// |-----------------------|--------|---------------------------------------------|
/// | Subject containment   | 0.30   | Is the subject fully inside the crop?       |
/// | Thirds placement      | 0.25   | Is the subject near a thirds intersection?  |
/// | Margin balance        | 0.15   | Is there adequate margin on all four sides? |
/// | Visual center balance | 0.15   | Is the subject reasonably centred in crop?  |
/// | Crop coverage         | 0.15   | Reward larger crops (more context captured) |
///
/// ### Future replacement point
/// Replace [_scoreCandidate] (or inject a scorer function) with a learned
/// aesthetic / technical / composition model once training data is available.
class CompositionScorer {
  const CompositionScorer();

  /// Returns [candidates] with updated scores, sorted best-first.
  List<CompositionCandidate> score({
    required List<CompositionCandidate> candidates,
    required Rect? subjectNormalized,
    required Size previewSize,
  }) {
    final scored = candidates
        .map((c) => c.copyWith(
              score: _scoreCandidate(c, subjectNormalized),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  double _scoreCandidate(CompositionCandidate candidate, Rect? subject) {
    final r = candidate.normalizedRect;
    double score = 0.0;

    // --- Crop coverage (0.15) -----------------------------------
    final cropArea = r.width * r.height;
    score += 0.15 * cropArea.clamp(0.0, 1.0);

    // --- Margin balance (0.15) ----------------------------------
    // Reward crops that leave a minimum margin on every edge.
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
      // Partial credit proportional to intersection / subject area.
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
    // Subject centre relative to the crop rect, in [0,1] crop space.
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
        // Full score when distance < 5 % of crop size.
        bestThirds = math.max(bestThirds, (1.0 - dist * 3.0).clamp(0.0, 1.0));
      }
      score += 0.25 * bestThirds;
    }

    // --- Visual centre balance (0.15) ---------------------------
    // Small bonus for horizontal alignment between subject and crop centre.
    final horizOffset = (subject.center.dx - r.center.dx).abs();
    final centreScore = (1.0 - horizOffset * 4.0).clamp(0.0, 1.0);
    score += 0.15 * centreScore;

    return score.clamp(0.0, 1.0);
  }
}
