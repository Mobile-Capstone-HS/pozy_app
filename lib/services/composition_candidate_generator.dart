import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/composition_candidate.dart';

/// Generates multiple candidate crop rectangles for a given frame.
///
/// All rects are in normalized [0,1] preview space.
/// Candidates cover 5 aspect ratios × 5 placement strategies = 25 candidates.
///
/// Replace or extend [generate] to feed subject detection results from ML
/// models in the future.
class CompositionCandidateGenerator {
  /// Canonical fallback subject used when no detection is available.
  ///
  /// Exposed as a constant so the calling site (e.g. [_CameraScreenState]) can
  /// resolve the effective subject ONCE and pass the same rect to both the
  /// generator and the scorer, keeping their assumptions consistent.
  static const Rect kNoSubjectFallback = Rect.fromLTWH(0.30, 0.20, 0.40, 0.60);
  static const List<_AspectConfig> _aspects = [
    _AspectConfig(ratio: 1.0, label: '1:1'),
    _AspectConfig(ratio: 4 / 3, label: '4:3'),
    _AspectConfig(ratio: 16 / 9, label: '16:9'),
    _AspectConfig(ratio: 3 / 4, label: '3:4'),
    _AspectConfig(ratio: 9 / 16, label: '9:16'),
  ];

  /// [previewSize] – pixel dimensions of the camera preview widget.
  /// [subjectNormalized] – normalized [0,1] bounding box of the main subject.
  ///   If null, a center-biased fallback box is used so the demo runs without
  ///   detection results.
  List<CompositionCandidate> generate({
    required Size previewSize,
    Rect? subjectNormalized,
  }) {
    final previewAspect =
        previewSize.width / previewSize.height.clamp(1.0, double.infinity);

    // Fallback: assume subject is roughly centred if detection is unavailable.
    // Callers that care about consistency should resolve this themselves using
    // [kNoSubjectFallback] and pass it explicitly as [subjectNormalized].
    final subject = subjectNormalized ?? kNoSubjectFallback;

    final candidates = <CompositionCandidate>[];

    for (final aspect in _aspects) {
      final size = _cropNormSize(previewAspect, aspect.ratio);
      final nw = size.width;
      final nh = size.height;

      final scx = subject.center.dx;
      final scy = subject.center.dy;

      // 1. Center crop: crop centered in the preview.
      candidates.add(CompositionCandidate(
        id: '${aspect.label}_center',
        normalizedRect: _clamp(Rect.fromLTWH((1 - nw) / 2, (1 - nh) / 2, nw, nh)),
        targetAspectRatio: aspect.ratio,
        score: 0,
        label: '${aspect.label} Center',
      ));

      // 2. Subject-centered crop: crop centered on the detected subject.
      candidates.add(CompositionCandidate(
        id: '${aspect.label}_subject',
        normalizedRect: _clamp(Rect.fromLTWH(scx - nw / 2, scy - nh / 2, nw, nh)),
        targetAspectRatio: aspect.ratio,
        score: 0,
        label: '${aspect.label} SubjCenter',
      ));

      // 3. Thirds TL: subject near top-left thirds intersection inside crop.
      //    Crop positioned so subject lands at (nw/3, nh/3) within the frame.
      candidates.add(CompositionCandidate(
        id: '${aspect.label}_thirds_tl',
        normalizedRect: _clamp(Rect.fromLTWH(scx - nw / 3, scy - nh / 3, nw, nh)),
        targetAspectRatio: aspect.ratio,
        score: 0,
        label: '${aspect.label} ThirdsTL',
      ));

      // 4. Thirds TR: subject near top-right thirds intersection inside crop.
      candidates.add(CompositionCandidate(
        id: '${aspect.label}_thirds_tr',
        normalizedRect: _clamp(Rect.fromLTWH(scx - 2 * nw / 3, scy - nh / 3, nw, nh)),
        targetAspectRatio: aspect.ratio,
        score: 0,
        label: '${aspect.label} ThirdsTR',
      ));

      // 5. Subject-contained: smallest crop that fits the subject + margin,
      //    expanded to the target aspect ratio.
      const margin = 0.08;
      final sl = subject.left - margin;
      final st = subject.top - margin;
      final sr = subject.right + margin;
      final sb = subject.bottom + margin;
      final boxW = sr - sl;
      final boxH = sb - st;
      double cw, ch;
      if (boxW / math.max(boxH, 0.001) > aspect.ratio) {
        cw = boxW;
        ch = cw / aspect.ratio;
      } else {
        ch = boxH;
        cw = ch * aspect.ratio;
      }
      cw = math.min(cw, 1.0);
      ch = math.min(ch, 1.0);
      candidates.add(CompositionCandidate(
        id: '${aspect.label}_contained',
        normalizedRect: _clamp(Rect.fromLTWH(scx - cw / 2, scy - ch / 2, cw, ch)),
        targetAspectRatio: aspect.ratio,
        score: 0,
        label: '${aspect.label} Contained',
      ));
    }

    return candidates;
  }

  /// Computes normalized crop dimensions for the given preview and target
  /// pixel aspect ratios, targeting ~85 % of preview area.
  static Size _cropNormSize(double previewAspect, double cropAspect) {
    // nw/nh must equal cropAspect/previewAspect in normalized space.
    final normAspect = cropAspect / previewAspect;
    var nh = math.sqrt(0.85 / normAspect);
    var nw = nh * normAspect;
    if (nw > 1.0) {
      nw = 1.0;
      nh = 1.0 / normAspect;
    }
    if (nh > 1.0) {
      nh = 1.0;
      nw = normAspect;
    }
    return Size(nw.clamp(0.05, 1.0).toDouble(), nh.clamp(0.05, 1.0).toDouble());
  }

  static Rect _clamp(Rect rect) {
    final w = rect.width.clamp(0.0, 1.0).toDouble();
    final h = rect.height.clamp(0.0, 1.0).toDouble();
    final left = rect.left.clamp(0.0, math.max(0.0, 1.0 - w)).toDouble();
    final top = rect.top.clamp(0.0, math.max(0.0, 1.0 - h)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }
}

class _AspectConfig {
  final double ratio;
  final String label;

  const _AspectConfig({required this.ratio, required this.label});
}
