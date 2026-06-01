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
    if (modelId == 'mobile_alamp_v2') {
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
    final alampMs = modelMs('mobile_alamp_v2');
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
        'total_rgnet_ms=${modelMs('rgnet_pil_resize_aadb')} '
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

abstract final class AcutAestheticTimingDebug {
  static bool get enabled =>
      ExperimentalFeatures.enableAcutAestheticTimingDebug;

  static Stopwatch? start() {
    if (!enabled) {
      return null;
    }
    return Stopwatch()..start();
  }

  static void logElapsed({
    required Stopwatch? stopwatch,
    required String modelId,
    required String phase,
    String? imageLabel,
    int? imageIndex,
    String? tensorShape,
    String? imageDimensions,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    if (stopwatch == null) {
      return;
    }
    if (stopwatch.isRunning) {
      stopwatch.stop();
    }
    log(
      modelId: modelId,
      phase: phase,
      elapsedMs: stopwatch.elapsedMilliseconds,
      imageLabel: imageLabel,
      imageIndex: imageIndex,
      tensorShape: tensorShape,
      imageDimensions: imageDimensions,
      fields: fields,
    );
  }

  static void log({
    required String modelId,
    required String phase,
    required int elapsedMs,
    String? imageLabel,
    int? imageIndex,
    String? tensorShape,
    String? imageDimensions,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    if (!enabled) {
      return;
    }

    final buffer = StringBuffer('[AcutAestheticTiming] ')
      ..write('image_index=${imageIndex ?? '-'} ')
      ..write('image="${_escape(imageLabel ?? 'unknown')}" ')
      ..write('model_id=$modelId ')
      ..write('phase=$phase ')
      ..write('elapsedMs=$elapsedMs');

    if (tensorShape != null) {
      buffer.write(' tensor_shape=$tensorShape');
    }
    if (imageDimensions != null) {
      buffer.write(' image_dimensions=$imageDimensions');
    }
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) {
        continue;
      }
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(_formatValue(value));
    }

    debugPrint(buffer.toString());
  }

  static String _formatValue(Object value) {
    if (value is String) {
      return '"${_escape(value)}"';
    }
    return value.toString();
  }

  static String _escape(String value) {
    return value.replaceAll('"', r'\"');
  }
}

abstract final class AcutAestheticParityDebug {
  static bool get enabled =>
      ExperimentalFeatures.enableAcutAestheticParityDebug;

  static Stopwatch? start() {
    if (!enabled) {
      return null;
    }
    return Stopwatch()..start();
  }

  static int? stopElapsedMs(Stopwatch? stopwatch) {
    if (stopwatch == null) {
      return null;
    }
    if (stopwatch.isRunning) {
      stopwatch.stop();
    }
    return stopwatch.elapsedMilliseconds;
  }

  static void log({
    required String? imageLabel,
    required int? imageIndex,
    required double? nimaScore,
    required double? rgnetScore,
    required double? alampScore,
    required double? icaaScore,
    required double? finalAestheticScore,
    double? technicalScore,
    int? elapsedTotalAestheticMs,
    List<String> modelErrors = const <String>[],
    String? error,
  }) {
    if (!enabled) {
      return;
    }

    final buffer = StringBuffer('[AcutAestheticParity] ')
      ..write('image_index=${imageIndex ?? '-'} ')
      ..write('image="${_escape(imageLabel ?? 'unknown')}" ')
      ..write('nima_score=${_score(nimaScore)} ')
      ..write('rgnet_score=${_score(rgnetScore)} ')
      ..write('alamp_score=${_score(alampScore)} ')
      ..write('icaa_score=${_score(icaaScore)} ')
      ..write('final_aesthetic_score=${_score(finalAestheticScore)}');

    if (technicalScore != null) {
      buffer.write(' technical_score=${_score(technicalScore)}');
    }
    if (elapsedTotalAestheticMs != null) {
      buffer.write(' elapsed_total_aesthetic_ms=$elapsedTotalAestheticMs');
    }
    if (modelErrors.isNotEmpty) {
      buffer
        ..write(' model_error_count=${modelErrors.length}')
        ..write(' model_errors="${_escape(modelErrors.join(' | '))}"');
    }
    if (error != null && error.isNotEmpty) {
      buffer.write(' error="${_escape(error)}"');
    }

    debugPrint(buffer.toString());
  }

  static String _score(double? value) {
    if (value == null) {
      return 'null';
    }
    if (value.isNaN) {
      return 'nan';
    }
    if (value.isInfinite) {
      return value.isNegative ? '-inf' : 'inf';
    }
    return value.toStringAsFixed(6);
  }

  static String _escape(String value) {
    return value.replaceAll('"', r'\"');
  }
}
