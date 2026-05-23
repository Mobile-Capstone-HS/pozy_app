import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_litert/flutter_litert.dart';

import '../../model/model_score_detail.dart';
import 'image_preprocessor.dart';

class TopiqMixed112ScoreResult {
  final double normalizedMos;
  final double score100;
  final int preprocessMs;
  final int inferenceMs;
  final int loadMs;
  final int allocateMs;

  const TopiqMixed112ScoreResult({
    required this.normalizedMos,
    required this.score100,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.loadMs,
    required this.allocateMs,
  });
}

class TopiqMixed112TechnicalIqaRunner {
  TopiqMixed112TechnicalIqaRunner({
    ImagePreprocessor? preprocessor,
    this.assetPath = 'assets/models/topiq_lite_mixed112_frozen_fp16.tflite',
  }) : _preprocessor = preprocessor ?? const ImagePreprocessor();

  static const int inputWidth = 384;
  static const int inputHeight = 384;
  static const int inputChannels = 3;
  static const int expectedInputBytes =
      inputWidth * inputHeight * inputChannels * 4;
  static const int expectedOutputBytes = 4;

  final ImagePreprocessor _preprocessor;
  final String assetPath;

  Future<_TopiqMixed112Handle>? _handleFuture;
  Future<void> _tail = Future<void>.value();
  bool _warnedUiPath = false;

  Future<TopiqMixed112ScoreResult> scoreImageBytes(
    Uint8List imageBytes, {
    String? imageIdOrPath,
    AcutImagePreprocessBundle? preprocessBundle,
  }) async {
    _logUiPathWarning();
    await ensureInitialized();

    final preprocessSw = Stopwatch()..start();
    final inputTensor =
        await preprocessBundle?.resizeWithPadRgbFloat32(
          width: inputWidth,
          height: inputHeight,
          normalization: ImageNormalization.rawZeroTo255,
        ) ??
        await _preprocessor.preprocessResizeWithPadToRgbFloat32(
          imageBytes,
          width: inputWidth,
          height: inputHeight,
          normalization: ImageNormalization.rawZeroTo255,
        );
    preprocessSw.stop();

    final preprocessMs = preprocessSw.elapsedMilliseconds;
    debugPrint(
      '[TopiqMixed112] preprocess_ms=$preprocessMs '
      'image_id_path="${_logValue(imageIdOrPath)}" '
      'resize_with_pad=${inputWidth}x$inputHeight '
      'range=0..255 normalize_div255=false',
    );

    return scorePreprocessedTensor(
      inputTensor,
      preprocessMs: preprocessMs,
      imageIdOrPath: imageIdOrPath,
    );
  }

  Future<TopiqMixed112ScoreResult> scorePreprocessedTensor(
    Uint8List inputTensor, {
    int preprocessMs = 0,
    String? imageIdOrPath,
  }) async {
    _validateInputBuffer(inputTensor);
    await ensureInitialized();

    return _synchronized((handle) async {
      final interpreter = handle.interpreter;
      final output = [List<double>.filled(handle.outputElementCount, 0.0)];

      debugPrint(
        '[TopiqMixed112] run_start '
        'input_buffer_bytes=${inputTensor.lengthInBytes}',
      );
      final inferSw = Stopwatch()..start();
      interpreter.run(inputTensor, output);
      inferSw.stop();

      final inferenceMs = inferSw.elapsedMilliseconds;
      final normalizedMos = output.first.first;
      if (!normalizedMos.isFinite ||
          normalizedMos < 0.0 ||
          normalizedMos > 1.0) {
        debugPrint(
          '[TopiqMixed112] invalid_output '
          'normalized_mos=$normalizedMos '
          'image_id_path="${_logValue(imageIdOrPath)}"',
        );
        throw StateError('topiq_mixed112_invalid_output:$normalizedMos');
      }

      final score100 = normalizedMos * 100.0;
      debugPrint('[TopiqMixed112] inference_ms=$inferenceMs');
      debugPrint(
        '[TopiqMixed112] raw_output=${normalizedMos.toStringAsFixed(6)}',
      );
      debugPrint('[TopiqMixed112] score_100=${score100.toStringAsFixed(4)}');

      return TopiqMixed112ScoreResult(
        normalizedMos: normalizedMos,
        score100: score100,
        preprocessMs: preprocessMs,
        inferenceMs: inferenceMs,
        loadMs: handle.loadMs,
        allocateMs: handle.allocateMs,
      );
    });
  }

  Future<void> ensureInitialized() async {
    await _getHandle();
  }

  Future<void> close() async {
    final pending = _handleFuture;
    _handleFuture = null;
    if (pending == null) {
      return;
    }

    final handle = await pending;
    handle.interpreter.close();
  }

  Future<T> _synchronized<T>(
    Future<T> Function(_TopiqMixed112Handle handle) action,
  ) {
    final previous = _tail;
    late final Future<T> next;
    next = previous.then((_) async {
      final handle = await _getHandle();
      return action(handle);
    });
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<_TopiqMixed112Handle> _getHandle() async {
    final pending = _handleFuture ??= _createHandle();
    try {
      return await pending;
    } catch (_) {
      if (identical(_handleFuture, pending)) {
        _handleFuture = null;
      }
      rethrow;
    }
  }

  Future<_TopiqMixed112Handle> _createHandle() async {
    final options = InterpreterOptions()..threads = 2;
    Interpreter? interpreter;

    try {
      debugPrint('[TopiqMixed112] ensure_initialized_start');
      final loadSw = Stopwatch()..start();
      interpreter = await Interpreter.fromAsset(assetPath, options: options);
      loadSw.stop();
      final loadMs = loadSw.elapsedMilliseconds;
      debugPrint('[TopiqMixed112] load_ms=$loadMs');

      _resizeInputIfNeeded(interpreter);

      final allocateSw = Stopwatch()..start();
      interpreter.allocateTensors();
      allocateSw.stop();
      final allocateMs = allocateSw.elapsedMilliseconds;
      debugPrint('[TopiqMixed112] allocate_ms=$allocateMs');

      final inputTensors = interpreter.getInputTensors();
      final outputTensors = interpreter.getOutputTensors();
      if (inputTensors.length != 1) {
        throw StateError(
          'topiq_mixed112_expected_one_input:${inputTensors.length}',
        );
      }
      if (outputTensors.length != 1) {
        throw StateError(
          'topiq_mixed112_expected_one_output:${outputTensors.length}',
        );
      }

      final inputTensor = inputTensors.first;
      final outputTensor = outputTensors.first;
      debugPrint('[TopiqMixed112] input_shape=${inputTensor.shape}');
      debugPrint('[TopiqMixed112] input_type=${inputTensor.type.name}');
      debugPrint('[TopiqMixed112] input_bytes=${inputTensor.numBytes()}');
      debugPrint('[TopiqMixed112] output_shape=${outputTensor.shape}');
      debugPrint('[TopiqMixed112] output_type=${outputTensor.type.name}');
      debugPrint('[TopiqMixed112] output_bytes=${outputTensor.numBytes()}');

      _validateInputTensor(inputTensor);
      final outputElementCount = _validateOutputTensor(outputTensor);

      return _TopiqMixed112Handle(
        interpreter: interpreter,
        outputElementCount: outputElementCount,
        loadMs: loadMs,
        allocateMs: allocateMs,
      );
    } catch (error) {
      interpreter?.close();
      debugPrint('[TopiqMixed112] init_error asset=$assetPath error=$error');
      rethrow;
    }
  }

  void _resizeInputIfNeeded(Interpreter interpreter) {
    final shape = interpreter.getInputTensor(0).shape;
    if (!_shapeCompatible(shape, const [1, inputHeight, inputWidth, 3])) {
      throw StateError('topiq_mixed112_unexpected_input_shape:$shape');
    }

    if (shape.contains(-1)) {
      interpreter.resizeInputTensor(0, const [1, inputHeight, inputWidth, 3]);
      debugPrint(
        '[TopiqMixed112] resized_dynamic_input shape=[1, $inputHeight, $inputWidth, 3]',
      );
    }
  }

  void _validateInputTensor(Tensor tensor) {
    if (tensor.type.name.toLowerCase() != 'float32') {
      throw StateError('topiq_mixed112_input_dtype:${tensor.type.name}');
    }
    if (!_shapeEquals(tensor.shape, const [1, inputHeight, inputWidth, 3])) {
      throw StateError('topiq_mixed112_input_shape:${tensor.shape}');
    }
    final byteCount = tensor.numBytes();
    if (byteCount != expectedInputBytes) {
      throw StateError(
        'TOPIQ input tensor is not allocated or shape mismatch: '
        'input_shape=${tensor.shape} '
        'input_type=${tensor.type.name} '
        'input_bytes=$byteCount '
        'expected_input_bytes=$expectedInputBytes',
      );
    }
  }

  int _validateOutputTensor(Tensor tensor) {
    if (tensor.type.name.toLowerCase() != 'float32') {
      throw StateError('topiq_mixed112_output_dtype:${tensor.type.name}');
    }
    if (!_shapeEquals(tensor.shape, const [1, 1])) {
      throw StateError('topiq_mixed112_output_shape:${tensor.shape}');
    }
    final byteCount = tensor.numBytes();
    if (byteCount != expectedOutputBytes) {
      throw StateError(
        'topiq_mixed112_output_bytes:$byteCount:expected:$expectedOutputBytes',
      );
    }
    final elementCount = byteCount ~/ 4;
    if (elementCount != 1) {
      throw StateError('topiq_mixed112_output_elements:$elementCount');
    }
    return elementCount;
  }

  bool _shapeCompatible(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) {
      return false;
    }
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index] && actual[index] != -1) {
        return false;
      }
    }
    return true;
  }

  bool _shapeEquals(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) {
      return false;
    }
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }

  void _validateInputBuffer(Uint8List inputTensor) {
    if (inputTensor.lengthInBytes != expectedInputBytes) {
      throw ArgumentError(
        'topiq_mixed112_input_bytes:${inputTensor.lengthInBytes}:expected:$expectedInputBytes',
      );
    }
  }

  void _logUiPathWarning() {
    if (_warnedUiPath) {
      return;
    }
    _warnedUiPath = true;
    debugPrint(
      '[TopiqMixed112] production_should_move_topiq_preprocessing_and_inference_off_ui_path',
    );
  }
}

void logTopiqMixed112TechnicalIqaComparison({
  required Iterable<ModelScoreDetail> scoreDetails,
  required double existingCombinedScore,
  required TopiqMixed112ScoreResult mixed112,
  String? imageIdOrPath,
}) {
  final koniq = _findScore(scoreDetails, 'koniq_mobile');
  final flive = _findScore(scoreDetails, 'flive_image_mobile');
  final existingScore100 = existingCombinedScore * 100.0;
  final delta = mixed112.score100 - existingScore100;

  debugPrint(
    '[TechnicalIqaCompare] '
    'image_id_path="${_logValue(imageIdOrPath)}" '
    'koniq_score=${_formatScore100(koniq)} '
    'flive_score=${_formatScore100(flive)} '
    'existing_combined_score=${existingScore100.toStringAsFixed(4)} '
    'mixed112_score=${mixed112.score100.toStringAsFixed(4)} '
    'delta_vs_existing=${delta.toStringAsFixed(4)} '
    'mixed112_inference_ms=${mixed112.inferenceMs} '
    'mixed112_preprocess_ms=${mixed112.preprocessMs}',
  );
}

ModelScoreDetail? _findScore(Iterable<ModelScoreDetail> details, String id) {
  for (final detail in details) {
    if (detail.id == id) {
      return detail;
    }
  }
  return null;
}

String _formatScore100(ModelScoreDetail? detail) {
  if (detail == null) {
    return '-';
  }
  return (detail.normalizedScore * 100.0).toStringAsFixed(4);
}

String _logValue(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    return '-';
  }
  return text.replaceAll('"', "'");
}

class _TopiqMixed112Handle {
  final Interpreter interpreter;
  final int outputElementCount;
  final int loadMs;
  final int allocateMs;

  const _TopiqMixed112Handle({
    required this.interpreter,
    required this.outputElementCount,
    required this.loadMs,
    required this.allocateMs,
  });
}
