import 'package:flutter/foundation.dart';

import '../../../../config/experimental_features.dart';

abstract final class AcutPerfCollector {
  static final Map<String, int> _modelTotalMs = <String, int>{};
  static final Map<String, int> _modelInferenceMs = <String, int>{};
  static int _totalPreprocessMs = 0;
  static int _totalAlampMs = 0;
  static int _images = 0;

  static void reset() {
    _modelTotalMs.clear();
    _modelInferenceMs.clear();
    _totalPreprocessMs = 0;
    _totalAlampMs = 0;
    _images = 0;
  }

  static void recordImage() {
    _images += 1;
  }

  static void recordPreprocess(int ms) {
    _totalPreprocessMs += ms;
  }

  static void recordModel({
    required String modelId,
    required int totalMs,
    required int inferenceMs,
  }) {
    _modelTotalMs[modelId] = (_modelTotalMs[modelId] ?? 0) + totalMs;
    _modelInferenceMs[modelId] =
        (_modelInferenceMs[modelId] ?? 0) + inferenceMs;
    if (modelId == 'alamp_aadb_gpu') {
      _totalAlampMs += totalMs;
    }
  }

  static AcutPerfSnapshot snapshot() {
    return AcutPerfSnapshot(
      images: _images,
      totalPreprocessMs: _totalPreprocessMs,
      totalInferenceMs: _modelInferenceMs.values.fold<int>(
        0,
        (sum, value) => sum + value,
      ),
      modelTotalMs: Map<String, int>.unmodifiable(_modelTotalMs),
      totalAlampMs: _totalAlampMs,
    );
  }
}

class AcutPerfSnapshot {
  final int images;
  final int totalPreprocessMs;
  final int totalInferenceMs;
  final Map<String, int> modelTotalMs;
  final int totalAlampMs;

  const AcutPerfSnapshot({
    required this.images,
    required this.totalPreprocessMs,
    required this.totalInferenceMs,
    required this.modelTotalMs,
    required this.totalAlampMs,
  });

  int modelMs(String modelId) => modelTotalMs[modelId] ?? 0;

  String batchSummary({
    required int totalImages,
    required int totalMs,
    required double avgMs,
  }) {
    final alampMs = modelMs('alamp_aadb_gpu');
    final avgAlampMs = images == 0 ? 0.0 : alampMs / images;

    return '[AcutPerf] batch_summary '
        'images=$totalImages '
        'total_ms=$totalMs '
        'avg_ms=${avgMs.toStringAsFixed(1)} '
        'total_preprocess_ms=$totalPreprocessMs '
        'total_inference_ms=$totalInferenceMs '
        'total_alamp_ms=$alampMs '
        'total_koniq_ms=${modelMs('koniq_mobile')} '
        'total_flive_ms=${modelMs('flive_image_mobile')} '
        'total_nima_ms=${modelMs('nima_mobile')} '
        'total_rgnet_ms=${modelMs('rgnet_aadb_gpu')} '
        'avg_alamp_ms=${avgAlampMs.toStringAsFixed(1)}';
  }
}

class AcutModelTiming {
  int inferenceOnlyMs = 0;
}

void acutVerboseModelLog(String message) {
  if (ExperimentalFeatures.acutVerboseModelLogs) {
    debugPrint(message);
  }
}
