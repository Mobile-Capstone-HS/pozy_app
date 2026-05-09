abstract final class ExperimentalFeatures {
  static const bool acutVerboseModelLogs = bool.fromEnvironment(
    'POZY_ACUT_VERBOSE_MODEL_LOGS',
    defaultValue: false,
  );
  static const bool verboseModelLogs = bool.fromEnvironment(
    'POZY_ACUT_VERBOSE_MODEL_LOGS',
    defaultValue: false,
  );
  static const bool useFreshInterpreterPerImageForDebug = bool.fromEnvironment(
    'POZY_USE_FRESH_INTERPRETER_PER_IMAGE_FOR_DEBUG',
    defaultValue: false,
  );
}
