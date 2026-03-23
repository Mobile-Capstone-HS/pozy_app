import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';

const String detectModelPath = 'yolo11n.tflite';
const double detectionConfidenceThreshold = 0.1;

YOLOStreamingConfig get detectionStreamingConfig =>
    YOLOStreamingConfig.highPerformance(inferenceFrequency: 20);

enum SubjectCategory {
  person,
  food,
  animal,
  plant,
  vehicle,
  electronics,
  object,
}

extension SubjectCategoryX on SubjectCategory {
  String get label {
    switch (this) {
      case SubjectCategory.person:
        return 'Person';
      case SubjectCategory.food:
        return 'Food';
      case SubjectCategory.animal:
        return 'Animal';
      case SubjectCategory.plant:
        return 'Plant';
      case SubjectCategory.vehicle:
        return 'Vehicle';
      case SubjectCategory.electronics:
        return 'Electronics';
      case SubjectCategory.object:
        return 'Object';
    }
  }

  Color get color {
    switch (this) {
      case SubjectCategory.person:
        return Colors.cyanAccent;
      case SubjectCategory.food:
        return Colors.orangeAccent;
      case SubjectCategory.animal:
        return Colors.lightGreenAccent;
      case SubjectCategory.plant:
        return Colors.greenAccent;
      case SubjectCategory.vehicle:
        return Colors.lightBlueAccent;
      case SubjectCategory.electronics:
        return Colors.pinkAccent;
      case SubjectCategory.object:
        return Colors.amberAccent;
    }
  }
}

class SubjectTarget {
  final math.Point<int> focusPoint;
  final Rect boundingBox;
  final String rawLabel;
  final SubjectCategory category;
  final double confidence;

  const SubjectTarget({
    required this.focusPoint,
    required this.boundingBox,
    required this.rawLabel,
    required this.category,
    required this.confidence,
  });

  String get displayLabel => '${category.label} ${(confidence * 100).toStringAsFixed(0)}%';
  Color get accentColor => category.color;
}

class _ScoredDetection {
  final YOLOResult result;
  final Rect boundingBox;
  final SubjectCategory primaryCategory;
  final double detectionScore;

  const _ScoredDetection({
    required this.result,
    required this.boundingBox,
    required this.primaryCategory,
    required this.detectionScore,
  });
}

class _FrameAnalysisResult {
  final Map<SubjectCategory, double> categoryScores;
  final List<_ScoredDetection> detections;

  const _FrameAnalysisResult({
    required this.categoryScores,
    required this.detections,
  });
}

class SubjectCategorySmoother {
  final double alpha;
  final double switchMargin;

  final Map<SubjectCategory, double> _emaScores = {
    for (final category in SubjectCategory.values) category: 0.0,
  };

  SubjectCategory? _stableCategory;

  SubjectCategorySmoother({
    this.alpha = 0.35,
    this.switchMargin = 1.15,
  });

  SubjectCategory update(Map<SubjectCategory, double> currentScores) {
    for (final category in SubjectCategory.values) {
      final previous = _emaScores[category] ?? 0.0;
      final current = currentScores[category] ?? 0.0;
      _emaScores[category] = previous * (1 - alpha) + current * alpha;
    }

    final bestEntry = _emaScores.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );

    if (_stableCategory == null) {
      _stableCategory = bestEntry.key;
      return _stableCategory!;
    }

    final previousStableScore = _emaScores[_stableCategory!] ?? 0.0;

    if (bestEntry.key != _stableCategory &&
        bestEntry.value < previousStableScore * switchMargin) {
      return _stableCategory!;
    }

    _stableCategory = bestEntry.key;
    return _stableCategory!;
  }

  void reset() {
    for (final category in SubjectCategory.values) {
      _emaScores[category] = 0.0;
    }
    _stableCategory = null;
  }
}

final SubjectCategorySmoother subjectCategorySmoother =
    SubjectCategorySmoother(alpha: 0.35, switchMargin: 1.15);

SubjectTarget? selectSubjectTarget(
  List<YOLOResult> results,
  Size screenSize,
) {
  final analysis = _analyzeFrame(results, screenSize);
  if (analysis == null) return null;

  final stableCategory =
      subjectCategorySmoother.update(analysis.categoryScores);

  final representativeCandidates = analysis.detections.where((d) {
    if (d.primaryCategory != stableCategory) return false;

    final area =
        d.result.normalizedBox.width * d.result.normalizedBox.height;

    if (area < _minAreaForRepresentativeBox(d.primaryCategory)) {
      return false;
    }

    final centerX = d.boundingBox.center.dx / screenSize.width;
    final centerY = d.boundingBox.center.dy / screenSize.height;

    if (centerX < 0.05 ||
        centerX > 0.95 ||
        centerY < 0.05 ||
        centerY > 0.95) {
      return false;
    }

    return true;
  }).toList();

  if (representativeCandidates.isEmpty) {
    final fallbackCandidates = analysis.detections.where((d) {
      final area =
          d.result.normalizedBox.width * d.result.normalizedBox.height;
      if (area < 0.005) return false;

      final centerX = d.boundingBox.center.dx / screenSize.width;
      final centerY = d.boundingBox.center.dy / screenSize.height;

      if (centerX < 0.03 ||
          centerX > 0.97 ||
          centerY < 0.03 ||
          centerY > 0.97) {
        return false;
      }

      return true;
    }).toList()
      ..sort((a, b) => b.detectionScore.compareTo(a.detectionScore));

    if (fallbackCandidates.isNotEmpty) {
      final best = fallbackCandidates.first;
      return SubjectTarget(
        focusPoint: math.Point<int>(
          best.boundingBox.center.dx.round(),
          best.boundingBox.center.dy.round(),
        ),
        boundingBox: best.boundingBox,
        rawLabel: best.result.className,
        category: best.primaryCategory,
        confidence: best.result.confidence,
      );
    }

    final allSorted = analysis.detections.toList()
      ..sort((a, b) => b.detectionScore.compareTo(a.detectionScore));

    if (allSorted.isEmpty) return null;

    final best = allSorted.first;
    return SubjectTarget(
      focusPoint: math.Point<int>(
        best.boundingBox.center.dx.round(),
        best.boundingBox.center.dy.round(),
      ),
      boundingBox: best.boundingBox,
      rawLabel: best.result.className,
      category: best.primaryCategory,
      confidence: best.result.confidence,
    );
  }

  representativeCandidates.sort((a, b) {
    return b.detectionScore.compareTo(a.detectionScore);
  });

  final best = representativeCandidates.first;

  return SubjectTarget(
    focusPoint: math.Point<int>(
      best.boundingBox.center.dx.round(),
      best.boundingBox.center.dy.round(),
    ),
    boundingBox: best.boundingBox,
    rawLabel: best.result.className,
    category: stableCategory,
    confidence: best.result.confidence,
  );
}

_FrameAnalysisResult? _analyzeFrame(
  List<YOLOResult> results,
  Size screenSize,
) {
  if (results.isEmpty) return null;

  final scoredDetections = <_ScoredDetection>[];
  final categoryScores = {
    for (final category in SubjectCategory.values) category: 0.0,
  };

  for (final result in results) {
    if (result.confidence < detectionConfidenceThreshold) continue;

    final boundingBox = Rect.fromLTRB(
      result.normalizedBox.left * screenSize.width,
      result.normalizedBox.top * screenSize.height,
      result.normalizedBox.right * screenSize.width,
      result.normalizedBox.bottom * screenSize.height,
    );

    final baseScore = _computeBaseDetectionScore(
      result: result,
      boundingBox: boundingBox,
      screenSize: screenSize,
    );

    if (baseScore <= 0) continue;

    final primaryCategory = _primaryCategoryOf(result.className);
    final contributions = _categoryContribution(result.className);

    scoredDetections.add(
      _ScoredDetection(
        result: result,
        boundingBox: boundingBox,
        primaryCategory: primaryCategory,
        detectionScore: baseScore,
      ),
    );

    contributions.forEach((category, weight) {
      categoryScores[category] =
          categoryScores[category]! + (baseScore * weight);
    });
  }

  if (scoredDetections.isEmpty) return null;

  return _FrameAnalysisResult(
    categoryScores: categoryScores,
    detections: scoredDetections,
  );
}

double _computeBaseDetectionScore({
  required YOLOResult result,
  required Rect boundingBox,
  required Size screenSize,
}) {
  final areaNorm = result.normalizedBox.width * result.normalizedBox.height;

  if (areaNorm < 0.003) return 0.0;

  final centerX = boundingBox.center.dx / screenSize.width;
  final centerY = boundingBox.center.dy / screenSize.height;

  final dx = centerX - 0.5;
  final dy = centerY - 0.5;
  final distanceFromCenter = math.sqrt(dx * dx + dy * dy);

  final centerWeight = (1.0 - distanceFromCenter).clamp(0.0, 1.0);

  final edgePenalty =
      (centerX < 0.03 || centerX > 0.97 || centerY < 0.03 || centerY > 0.97)
          ? 0.55
          : 1.0;

  final areaWeight = math.sqrt(areaNorm);

  return result.confidence *
      areaWeight *
      (0.35 + 1.25 * centerWeight) *
      edgePenalty;
}

double _minAreaForRepresentativeBox(SubjectCategory category) {
  switch (category) {
    case SubjectCategory.person:
      return 0.005;
    case SubjectCategory.food:
      return 0.004;
    case SubjectCategory.animal:
      return 0.005;
    case SubjectCategory.plant:
      return 0.005;
    case SubjectCategory.vehicle:
      return 0.006;
    case SubjectCategory.electronics:
      return 0.005;
    case SubjectCategory.object:
      return 0.005;
  }
}

SubjectCategory _primaryCategoryOf(String className) {
  final normalized = className.trim().toLowerCase();

  const directFoodClasses = {
    'apple',
    'banana',
    'broccoli',
    'cake',
    'carrot',
    'donut',
    'hot dog',
    'orange',
    'pizza',
    'sandwich',
  };

  const animalClasses = {
    'bear',
    'bird',
    'cat',
    'cow',
    'dog',
    'elephant',
    'giraffe',
    'horse',
    'sheep',
    'zebra',
  };

  const vehicleClasses = {
    'airplane',
    'bicycle',
    'boat',
    'bus',
    'car',
    'motorcycle',
    'train',
    'truck',
  };

  const electronicsClasses = {
    'cell phone',
    'keyboard',
    'laptop',
    'microwave',
    'mouse',
    'oven',
    'refrigerator',
    'remote',
    'toaster',
    'tv',
  };

  if (normalized == 'person') return SubjectCategory.person;
  if (directFoodClasses.contains(normalized)) return SubjectCategory.food;
  if (animalClasses.contains(normalized)) return SubjectCategory.animal;
  if (vehicleClasses.contains(normalized)) return SubjectCategory.vehicle;
  if (electronicsClasses.contains(normalized)) return SubjectCategory.electronics;
  if (normalized == 'potted plant') return SubjectCategory.plant;
  return SubjectCategory.object;
}

Map<SubjectCategory, double> _categoryContribution(String className) {
  final normalized = className.trim().toLowerCase();

  switch (normalized) {
    case 'person':
      return {SubjectCategory.person: 1.0};

    case 'apple':
    case 'banana':
    case 'broccoli':
    case 'cake':
    case 'carrot':
    case 'donut':
    case 'hot dog':
    case 'orange':
    case 'pizza':
    case 'sandwich':
      return {SubjectCategory.food: 1.0};

    case 'bowl':
    case 'cup':
    case 'fork':
    case 'knife':
    case 'spoon':
    case 'wine glass':
      return {
        SubjectCategory.food: 0.55,
        SubjectCategory.object: 0.45,
      };

    case 'bottle':
      return {
        SubjectCategory.food: 0.35,
        SubjectCategory.object: 0.65,
      };

    case 'dining table':
      return {
        SubjectCategory.food: 0.35,
        SubjectCategory.object: 0.80,
      };

    case 'bear':
    case 'bird':
    case 'cat':
    case 'cow':
    case 'dog':
    case 'elephant':
    case 'giraffe':
    case 'horse':
    case 'sheep':
    case 'zebra':
      return {SubjectCategory.animal: 1.0};

    case 'potted plant':
      return {SubjectCategory.plant: 1.0};

    case 'airplane':
    case 'bicycle':
    case 'boat':
    case 'bus':
    case 'car':
    case 'motorcycle':
    case 'train':
    case 'truck':
      return {SubjectCategory.vehicle: 1.0};

    case 'cell phone':
    case 'keyboard':
    case 'laptop':
    case 'microwave':
    case 'mouse':
    case 'oven':
    case 'refrigerator':
    case 'remote':
    case 'toaster':
    case 'tv':
      return {
        SubjectCategory.electronics: 1.0,
        SubjectCategory.object: 0.25,
      };

    default:
      return {SubjectCategory.object: 1.0};
  }
}
