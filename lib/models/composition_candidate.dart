import 'package:flutter/material.dart';

/// A candidate composition crop rectangle with scoring information.
///
/// [normalizedRect] is the target crop rect in [0,1] normalized preview space.
/// [smoothedRect]   is the interpolated version used for rendering (set by
///                  [CompositionStabilizer]).
/// [renderRect]     returns smoothedRect if available, otherwise normalizedRect.
class CompositionCandidate {
  final String id;
  final Rect normalizedRect;
  final Rect? smoothedRect;
  final double targetAspectRatio;
  final double score;
  final String label;

  /// How well the subject is aligned with this composition, from 0.0 to 1.0.
  /// Set by the composition pipeline, used by the painter for visual feedback.
  final double alignmentScore;

  const CompositionCandidate({
    required this.id,
    required this.normalizedRect,
    this.smoothedRect,
    required this.targetAspectRatio,
    required this.score,
    required this.label,
    this.alignmentScore = 0.0,
  });

  Rect get renderRect => smoothedRect ?? normalizedRect;

  CompositionCandidate copyWith({
    Rect? normalizedRect,
    double? score,
    Rect? smoothedRect,
    double? alignmentScore,
  }) {
    return CompositionCandidate(
      id: id,
      normalizedRect: normalizedRect ?? this.normalizedRect,
      smoothedRect: smoothedRect ?? this.smoothedRect,
      targetAspectRatio: targetAspectRatio,
      score: score ?? this.score,
      label: label,
      alignmentScore: alignmentScore ?? this.alignmentScore,
    );
  }
}
