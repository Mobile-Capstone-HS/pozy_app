import 'package:flutter/foundation.dart';

abstract final class ExperimentalFeatures {
  static const String gemmaE2bLabel = 'Gemma 4 E2B';
  static const String gemmaE4bLabel = 'Gemma 4 E4B';
  static const String gemmaE2bDeviceModelPath =
      '/data/local/tmp/llm/gemma4_e2b.litertlm';
  static const String gemmaE4bDeviceModelPath =
      '/data/local/tmp/llm/gemma4_e4b.litertlm';

  static const bool enableGemmaExplanationDebug = kDebugMode;
  static const bool preferOnDeviceGemmaExplanation = bool.fromEnvironment(
    'POZY_PREFER_ON_DEVICE_GEMMA_EXPLANATION',
    defaultValue: false,
  );
  static const bool useOnDeviceGemmaVlmExplanation = bool.fromEnvironment(
    'POZY_USE_GEMMA_VLM_EXPLANATION',
    defaultValue: false,
  );
  static const bool useVlmResizedImageInput = bool.fromEnvironment(
    'POZY_USE_VLM_RESIZED_IMAGE_INPUT',
    defaultValue: true,
  );
  static const bool disableGemmaDuringBatchScoring = bool.fromEnvironment(
    'POZY_DISABLE_GEMMA_DURING_BATCH_SCORING',
    defaultValue: true,
  );
  static const bool disableAllExplanationsDuringBatchScoring =
      bool.fromEnvironment(
        'POZY_DISABLE_ALL_EXPLANATIONS_DURING_BATCH_SCORING',
        defaultValue: true,
      );
  static const bool disableKoniqDuringBatchScoring = bool.fromEnvironment(
    'POZY_DISABLE_KONIQ_DURING_BATCH_SCORING',
    defaultValue: false,
  );
  static const bool disableFliveDuringBatchScoring = bool.fromEnvironment(
    'POZY_DISABLE_FLIVE_DURING_BATCH_SCORING',
    defaultValue: false,
  );
  static const bool disableNimaDuringBatchScoring = bool.fromEnvironment(
    'POZY_DISABLE_NIMA_DURING_BATCH_SCORING',
    defaultValue: false,
  );
  static const bool disableRgnetDuringBatchScoring = bool.fromEnvironment(
    'POZY_DISABLE_RGNET_DURING_BATCH_SCORING',
    defaultValue: true,
  );
  static const bool disableAlampDuringBatchScoring = bool.fromEnvironment(
    'POZY_DISABLE_ALAMP_DURING_BATCH_SCORING',
    defaultValue: true,
  );
  static const bool acutVerboseModelLogs = bool.fromEnvironment(
    'POZY_ACUT_VERBOSE_MODEL_LOGS',
    defaultValue: false,
  );
  static const bool useFreshInterpreterPerImageForDebug = bool.fromEnvironment(
    'POZY_USE_FRESH_INTERPRETER_PER_IMAGE_FOR_DEBUG',
    defaultValue: false,
  );
  static const bool gemmaDebugSequentialComparison = true;
  static const String gemmaLiteRtLmModelPath = String.fromEnvironment(
    'POZY_GEMMA_MODEL_PATH',
    defaultValue: gemmaE4bDeviceModelPath,
  );
  static const String gemmaVlmLiteRtLmModelPath = String.fromEnvironment(
    'POZY_GEMMA_VLM_MODEL_PATH',
    defaultValue: gemmaE2bDeviceModelPath,
  );
  static const String gemmaBackendMode = String.fromEnvironment(
    'POZY_GEMMA_BACKEND_MODE',
    defaultValue: 'gpu_preferred',
  );
  static const int gemmaVlmMaxLongSide = int.fromEnvironment(
    'POZY_GEMMA_VLM_MAX_LONG_SIDE',
    defaultValue: 1280,
  );
  static const int gemmaVlmJpegQuality = int.fromEnvironment(
    'POZY_GEMMA_VLM_JPEG_QUALITY',
    defaultValue: 85,
  );
  static const Duration gemmaPreloadTimeout = Duration(seconds: 60);
  static const Duration gemmaGenerationTimeout = Duration(seconds: 60);
}
