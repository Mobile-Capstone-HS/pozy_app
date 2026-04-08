import 'dart:typed_data';

import 'package:flutter/material.dart' show Rect, Size;
import 'package:flutter_litert/flutter_litert.dart';

import '../feature/a_cut/layer/inference/tflite_interpreter_manager.dart';
import '../utils/image_crop_utils.dart';

/// Runs the `composition_aadb_gpu` TFLite model on a single candidate crop.
///
/// ### Model contract
/// | Property | Value                              |
/// |----------|------------------------------------|
/// | File     | composition_aadb_gpu.tflite        |
/// | Input    | [1, 224, 224, 3] float32, RGB÷255  |
/// | Output   | [1, 1] float32 scalar in [0, 1]    |
///
/// ### Fallback
/// If the model file cannot be loaded, [isAvailable] is set to `false` and
/// every subsequent call to [scoreCandidate] returns `null` immediately.
/// The caller (typically [ModelCompositionScorer]) then uses heuristic scores.
class CompositionModelRunner {
  CompositionModelRunner({
    this.modelAssetPath =
        'assets/models/composition_aadb_gpu.tflite',
    TfliteInterpreterManager? interpreterManager,
  }) : _manager = interpreterManager ?? TfliteInterpreterManager.instance;

  final String modelAssetPath;
  final TfliteInterpreterManager _manager;

  // Latched to false after the first failed interpreter load so we stop
  // retrying on every throttle tick.
  bool _modelAvailable = true;

  /// Whether the model was loaded successfully at least once.
  bool get isAvailable => _modelAvailable;

  /// Score a single candidate crop extracted from [frameBytes].
  ///
  /// [normalizedRect]: the candidate bounding box in [0,1] preview space.
  /// [frameSize]:      pixel size of the captured frame.  Pass [Size.zero] to
  ///                   let [cropAndPreprocessForAadb] read the decoded dimensions.
  ///
  /// Returns a score in [0, 1] or `null` on any failure.
  Future<double?> scoreCandidate({
    required Uint8List frameBytes,
    required Rect normalizedRect,
    Size frameSize = Size.zero,
  }) async {
    if (!_modelAvailable) return null;

    try {
      // ── Step 1: crop + preprocess in background isolate ─────────────────
      final input = await cropAndPreprocessForAadb(
        frameBytes,
        normalizedRect: normalizedRect,
        frameSize: frameSize,
      );
      if (input == null) return null;

      // ── Step 2: get cached interpreter (standard model, no Flex ops) ─────
      final Interpreter interpreter;
      try {
        interpreter = await _manager.getInterpreter(
          modelAssetPath,
          useFlexDelegate: false,
        );
      } catch (_) {
        // Model file not found or interpreter init failed → disable.
        _modelAvailable = false;
        return null;
      }

      // ── Step 3: run inference ────────────────────────────────────────────
      // Pack Float32List as Uint8List for the flutter_litert API.
      final inputBytes = input.buffer.asUint8List();
      final outputElements = interpreter.getOutputTensor(0).numElements();
      final outputBytes = Uint8List(outputElements * 4); // 4 bytes per float32

      interpreter.run(inputBytes, outputBytes.buffer);

      final score = outputBytes.buffer.asFloat32List()[0];
      return score.clamp(0.0, 1.0);
    } catch (_) {
      // Inference error — disable model to avoid repeated failures.
      _modelAvailable = false;
      return null;
    }
  }
}
