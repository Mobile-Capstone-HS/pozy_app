import 'dart:math' as math;

import 'package:flutter/material.dart';

class SubjectDetection {
  final int id;
  final Rect normalizedBox;
  final String className;
  final double confidence;
  final double? saliencyHint;

  const SubjectDetection({
    required this.id,
    required this.normalizedBox,
    required this.className,
    required this.confidence,
    this.saliencyHint,
  });
}

class SubjectScoreBreakdown {
  final SubjectDetection detection;
  final double size;
  final double center;
  final double classPriority;
  final double confidence;
  final double saliency;
  final double totalScore;

  const SubjectScoreBreakdown({
    required this.detection,
    required this.size,
    required this.center,
    required this.classPriority,
    required this.confidence,
    required this.saliency,
    required this.totalScore,
  });
}

enum SelectionMode {
  subject,
  landscape,
}

class SubjectSelectionResult {
  final SelectionMode mode;
  final SubjectScoreBreakdown? best;
  final String guidance;
  final List<SubjectScoreBreakdown> scored;

  const SubjectSelectionResult({
    required this.mode,
    required this.best,
    required this.guidance,
    required this.scored,
  });
}

typedef SaliencyEstimator =
    double Function(SubjectDetection detection, Size imageSize);

class SubjectSelector {
  static const Map<String, double> _classPriorityMap = {
    'person': 1.0,
    'dog': 0.8,
    'cat': 0.7,
    'car': 0.5,
  };

  final double wSize;
  final double wCenter;
  final double wClass;
  final double wConfidence;
  final double wSaliency;
  final double threshold;
  final SaliencyEstimator? saliencyEstimator;

  const SubjectSelector({
    this.wSize = 0.35,
    this.wCenter = 0.25,
    this.wClass = 0.2,
    this.wConfidence = 0.1,
    this.wSaliency = 0.1,
    this.threshold = 0.3,
    this.saliencyEstimator,
  });

  SubjectSelectionResult selectMainSubject({
    required List<SubjectDetection> detections,
    required Size imageSize,
  }) {
    if (detections.isEmpty || imageSize == Size.zero) {
      return SubjectSelectionResult(
        mode: SelectionMode.landscape,
        best: null,
        guidance: _landscapeGuidance(detections, imageSize),
        scored: const [],
      );
    }

    final scored = <SubjectScoreBreakdown>[];

    for (final detection in detections) {
      final sizeMetric = _sizeMetric(detection, imageSize);
      final centerMetric = _centerMetric(detection);
      final classMetric = _classMetric(detection.className);
      final confidenceMetric = detection.confidence.clamp(0.0, 1.0);
      final saliencyMetric = _saliencyMetric(detection, imageSize);
      final total = (wSize * sizeMetric) +
          (wCenter * centerMetric) +
          (wClass * classMetric) +
          (wConfidence * confidenceMetric) +
          (wSaliency * saliencyMetric);

      scored.add(
        SubjectScoreBreakdown(
          detection: detection,
          size: sizeMetric,
          center: centerMetric,
          classPriority: classMetric,
          confidence: confidenceMetric,
          saliency: saliencyMetric,
          totalScore: total,
        ),
      );
    }

    scored.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    final best = scored.first;

    if (best.totalScore < threshold) {
      return SubjectSelectionResult(
        mode: SelectionMode.landscape,
        best: null,
        guidance: _landscapeGuidance(detections, imageSize, scored: scored),
        scored: scored,
      );
    }

    return SubjectSelectionResult(
      mode: SelectionMode.subject,
      best: best,
      guidance: 'Main subject: ${best.detection.className}',
      scored: scored,
    );
  }

  double _sizeMetric(SubjectDetection detection, Size imageSize) {
    final imageArea = imageSize.width * imageSize.height;
    if (imageArea <= 0) {
      return 0;
    }

    final clamped = _clampNormalizedRect(detection.normalizedBox);
    final pixelArea =
        (clamped.width * imageSize.width) * (clamped.height * imageSize.height);
    return (pixelArea / imageArea).clamp(0.0, 1.0);
  }

  double _centerMetric(SubjectDetection detection) {
    final clamped = _clampNormalizedRect(detection.normalizedBox);
    final dx = clamped.center.dx - 0.5;
    final dy = clamped.center.dy - 0.5;
    final dist = math.sqrt(dx * dx + dy * dy);
    const maxDist = 0.7071067811865476;
    return (1 - (dist / maxDist)).clamp(0.0, 1.0);
  }

  double _classMetric(String className) {
    return _classPriorityMap[className.toLowerCase()] ?? 0.3;
  }

  double _saliencyMetric(SubjectDetection detection, Size imageSize) {
    if (detection.saliencyHint != null) {
      return detection.saliencyHint!.clamp(0.0, 1.0);
    }
    if (saliencyEstimator != null) {
      return saliencyEstimator!(detection, imageSize).clamp(0.0, 1.0);
    }
    return 0.5;
  }

  String _landscapeGuidance(
    List<SubjectDetection> detections,
    Size imageSize, {
    List<SubjectScoreBreakdown>? scored,
  }) {
    if (detections.isEmpty || imageSize == Size.zero) {
      return 'Scene is balanced';
    }

    final basis = scored ??
        detections
            .map(
              (detection) => SubjectScoreBreakdown(
                detection: detection,
                size: _sizeMetric(detection, imageSize),
                center: _centerMetric(detection),
                classPriority: _classMetric(detection.className),
                confidence: detection.confidence.clamp(0.0, 1.0),
                saliency: _saliencyMetric(detection, imageSize),
                totalScore: 0,
              ),
            )
            .toList();

    double leftWeight = 0;
    double rightWeight = 0;
    for (final item in basis) {
      final centerX = _clampNormalizedRect(item.detection.normalizedBox).center.dx;
      final baseWeight = (item.size * 0.6) + (item.confidence * 0.4);
      if (centerX < 0.5) {
        leftWeight += baseWeight;
      } else {
        rightWeight += baseWeight;
      }
    }

    final total = leftWeight + rightWeight;
    if (total <= 0) {
      return 'Scene is balanced';
    }

    final diffRatio = (leftWeight - rightWeight).abs() / total;
    if (diffRatio < 0.15) {
      return 'Scene is balanced';
    }

    if (leftWeight > rightWeight) {
      return 'Move subject to the right';
    }
    return 'Move subject to the left';
  }

  Rect _clampNormalizedRect(Rect box) {
    return Rect.fromLTRB(
      box.left.clamp(0.0, 1.0),
      box.top.clamp(0.0, 1.0),
      box.right.clamp(0.0, 1.0),
      box.bottom.clamp(0.0, 1.0),
    );
  }
}
