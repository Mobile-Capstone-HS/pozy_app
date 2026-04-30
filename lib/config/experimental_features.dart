import 'package:flutter/foundation.dart';

abstract final class ExperimentalFeatures {
  static const bool enableGemmaExplanationDebug = kDebugMode;
  static const bool preferOnDeviceGemmaExplanation = false;
  static const String gemmaLiteRtLmModelPath = String.fromEnvironment(
    'POZY_GEMMA_MODEL_PATH',
    defaultValue: '/data/local/tmp/llm/gemma4_e4b.litertlm',
  );
  static const Duration gemmaGenerationTimeout = Duration(seconds: 15);
}
