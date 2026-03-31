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

  const CompositionCandidate({
    required this.id,
    required this.normalizedRect,
    this.smoothedRect,
    required this.targetAspectRatio,
    required this.score,
    required this.label,
  });

  Rect get renderRect => smoothedRect ?? normalizedRect;

  CompositionCandidate copyWith({double? score, Rect? smoothedRect}) {
    return CompositionCandidate(
      id: id,
      normalizedRect: normalizedRect,
      smoothedRect: smoothedRect ?? this.smoothedRect,
      targetAspectRatio: targetAspectRatio,
      score: score ?? this.score,
      label: label,
    );
  }
}
