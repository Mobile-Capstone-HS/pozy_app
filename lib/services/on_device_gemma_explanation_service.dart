import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../config/experimental_features.dart';
import 'acut_comment_prompt_builder.dart';
import 'photo_explanation_service.dart';

enum GemmaExplanationMode {
  textOnlyCompactRewrite('text_only_compact_rewrite'),
  visualImageContext('visual_image_context');

  const GemmaExplanationMode(this.id);

  final String id;
}

class OnDeviceGemmaExplanationService implements PhotoExplanationService {
  OnDeviceGemmaExplanationService({
    MethodChannel? channel,
    this.modelPath = ExperimentalFeatures.gemmaLiteRtLmModelPath,
    this.backendMode = ExperimentalFeatures.gemmaBackendMode,
    this.mode = GemmaExplanationMode.textOnlyCompactRewrite,
    Duration? preloadTimeout,
    Duration? generationTimeout,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _preloadTimeout =
           preloadTimeout ?? ExperimentalFeatures.gemmaPreloadTimeout,
       _generationTimeout =
           generationTimeout ?? ExperimentalFeatures.gemmaGenerationTimeout;

  OnDeviceGemmaExplanationService.visual({
    MethodChannel? channel,
    String modelPath = ExperimentalFeatures.gemmaVlmLiteRtLmModelPath,
    String backendMode = ExperimentalFeatures.gemmaBackendMode,
    Duration? preloadTimeout,
    Duration? generationTimeout,
  }) : this(
         channel: channel,
         modelPath: modelPath,
         backendMode: backendMode,
         mode: GemmaExplanationMode.visualImageContext,
         preloadTimeout: preloadTimeout,
         generationTimeout: generationTimeout,
       );

  static const String methodChannelName = _channelName;
  static const String _channelName = 'pozy.gemma_litertlm/method';

  final MethodChannel _channel;
  final String modelPath;
  final String backendMode;
  final GemmaExplanationMode mode;
  final Duration _preloadTimeout;
  final Duration _generationTimeout;

  @override
  String get backendId => mode == GemmaExplanationMode.visualImageContext
      ? 'on_device_gemma_vlm'
      : 'on_device_gemma';

  @override
  String get backendLabel => mode == GemmaExplanationMode.visualImageContext
      ? '온디바이스 Gemma VLM'
      : '온디바이스 Gemma';

  Duration get preloadTimeout => _preloadTimeout;

  Duration get generationTimeout => _generationTimeout;

  Future<Map<String, dynamic>> preloadModel() async {
    if (!_isSupportedPlatform) {
      return {'ok': false, 'model_loaded': false, 'error': 'android_only'};
    }

    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_PRELOAD_START '
      'backend=$backendLabel timeout_seconds=${_preloadTimeout.inSeconds} '
      'model_path=$modelPath backend_mode=$backendMode',
    );

    try {
      final response = await _channel
          .invokeMethod<dynamic>('preloadModel', {
            'modelPath': modelPath,
            'backendMode': backendMode,
          })
          .timeout(_preloadTimeout);
      stopwatch.stop();

      final map = _normalizeMap(response);
      final elapsedMs =
          _toInt(map['elapsed_ms']) ?? stopwatch.elapsedMilliseconds;
      final enriched = {
        ...map,
        'elapsed_ms': elapsedMs,
        'timeout_seconds': _preloadTimeout.inSeconds,
      };
      final error = _cleanString(map['error']);
      final engineConfigMode = _cleanString(map['engine_config_mode']);
      final decodingConfig = _cleanString(map['decoding_config']);
      final backendInfo = _cleanString(map['backend_info']);
      final gpuFallbackUsed = map['gpu_fallback_used'] == true;
      if (error != null || map['ok'] == false) {
        debugPrint(
          '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_PRELOAD_FAILED '
          'backend=$backendLabel elapsed_ms=$elapsedMs '
          'backend_info=${backendInfo ?? '-'} '
          'gpu_fallback_used=$gpuFallbackUsed '
          'engine_config_mode=${engineConfigMode ?? '-'} '
          'decoding_config=${decodingConfig ?? '-'} '
          'error=${error ?? 'unknown_error'}',
        );
      } else {
        debugPrint(
          '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_PRELOAD_SUCCESS '
          'backend=$backendLabel elapsed_ms=$elapsedMs '
          'model_load_time_ms=${_toInt(map['model_load_time_ms']) ?? '-'} '
          'backend_info=${backendInfo ?? '-'} '
          'gpu_fallback_used=$gpuFallbackUsed '
          'engine_config_mode=${engineConfigMode ?? '-'} '
          'decoding_config=${decodingConfig ?? '-'}',
        );
      }
      return enriched;
    } on TimeoutException catch (error) {
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      debugPrint(
        '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_PRELOAD_FAILED '
        'backend=$backendLabel elapsed_ms=$elapsedMs error=$error',
      );
      return {
        'ok': false,
        'model_loaded': false,
        'error': error.toString(),
        'elapsed_ms': elapsedMs,
        'timeout_seconds': _preloadTimeout.inSeconds,
        'engine_config_mode': 'default_safe',
        'backend_request': backendMode,
        'decoding_config': 'default_safe',
      };
    } catch (error) {
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      debugPrint(
        '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_PRELOAD_FAILED '
        'backend=$backendLabel elapsed_ms=$elapsedMs error=$error',
      );
      return {
        'ok': false,
        'model_loaded': false,
        'error': error.toString(),
        'elapsed_ms': elapsedMs,
        'timeout_seconds': _preloadTimeout.inSeconds,
        'engine_config_mode': 'default_safe',
        'backend_request': backendMode,
        'decoding_config': 'default_safe',
      };
    }
  }

  Future<Map<String, dynamic>> checkModelFile() async {
    if (!_isSupportedPlatform) {
      return {'ok': false, 'model_path': modelPath, 'error': 'android_only'};
    }

    final response = await _channel.invokeMethod<dynamic>('checkModelFile', {
      'modelPath': modelPath,
    });
    return _normalizeMap(response);
  }

  Future<Map<String, dynamic>> isModelLoaded() async {
    if (!_isSupportedPlatform) {
      return {'ok': false, 'model_loaded': false, 'error': 'android_only'};
    }

    final response = await _channel.invokeMethod<dynamic>('isModelLoaded');
    return _normalizeMap(response);
  }

  Future<void> disposeModel() async {
    if (!_isSupportedPlatform) {
      return;
    }
    await _channel.invokeMethod<dynamic>('disposeModel');
  }

  @override
  Future<PhotoExplanationResult> explain(
    PhotoExplanationRequest request,
  ) async {
    if (!_isSupportedPlatform) {
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: acutCommentTypeForScore(request.finalScore),
        error: 'android_only_backend',
      );
    }

    if (mode == GemmaExplanationMode.visualImageContext) {
      return _explainVisual(request);
    }

    final promptPayload =
        AcutCommentPromptBuilder.buildCompactOnDeviceGemmaPrompt(
          request,
          modelPath: modelPath,
        );
    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[OnDeviceGemmaExplanationService] ON_DEVICE_GEMMA_PROMPT_MODE '
      'backend=$backendLabel mode=${promptPayload.promptMode} '
      'prompt_chars=${promptPayload.promptChars} '
      'comment_type=${request.defaultCommentType}',
    );
    debugPrint(
      '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_GENERATE_START '
      'backend=$backendLabel timeout_seconds=${_generationTimeout.inSeconds} '
      'model_path=$modelPath backend_mode=$backendMode '
      'file_name=${request.fileName ?? 'selected_image'}',
    );

    try {
      final response = await _channel
          .invokeMethod<dynamic>('generateAcutComment', {
            'inputJson': promptPayload.inputJson,
            'backendMode': backendMode,
          })
          .timeout(_generationTimeout);
      stopwatch.stop();
      final map = _normalizeMap(response);
      final jsonParseSuccess = map['json_parse_success'] == true;
      final parseFailed = map['parse_failed'] == true;
      final fallbackUsed = map['fallback_used'] == true;
      final repaired = map['repaired'] == true;
      final repairReason = _cleanString(map['repair_reason']);
      final parseFailureReason = _cleanString(map['parse_failure_reason']);
      final fallbackReason = _cleanString(map['fallback_reason']);
      final rawPreview = _cleanString(map['raw_output_preview']);
      final error = _cleanString(map['error']);
      final engineConfigMode = _cleanString(map['engine_config_mode']);
      final decodingConfig = _cleanString(map['decoding_config']);
      final backendInfo = _cleanString(map['backend_info']);
      final gpuFallbackUsed = map['gpu_fallback_used'] == true;
      final shortReason = _cleanString(map['short_reason']) ?? '';
      final detailedReason = _cleanString(map['detailed_reason']) ?? '';
      final nativeGenerationMs = _toInt(map['native_generation_time_ms']);
      final outputLength = _toInt(map['output_length']);
      final elapsedMs =
          _toInt(map['total_generation_time_ms']) ??
          stopwatch.elapsedMilliseconds;
      final commentType =
          _cleanString(map['comment_type']) ??
          acutCommentTypeForScore(request.finalScore);

      if (error != null && shortReason.isEmpty && detailedReason.isEmpty) {
        debugPrint(
          '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_GENERATE_FAILED '
          'backend=$backendLabel elapsed_ms=$elapsedMs error=$error',
        );
        debugPrint(
          '[OnDeviceGemmaExplanationService] ON_DEVICE_GEMMA_RESULT '
          'backend=$backendLabel elapsed_ms=$elapsedMs '
          'timeout_seconds=${_generationTimeout.inSeconds} '
          'success=false fallback=$fallbackUsed parse_failed=$parseFailed',
        );
        return PhotoExplanationResult.failure(
          backendId: backendId,
          backendLabel: backendLabel,
          commentType: commentType,
          error: error,
          modelLoadTimeMs: _toInt(map['model_load_time_ms']),
          nativeGenerationTimeMs: nativeGenerationMs,
          outputLength: outputLength,
          totalGenerationTimeMs: elapsedMs,
          timeoutSeconds: _generationTimeout.inSeconds,
          jsonParseSuccess: jsonParseSuccess,
          parseFailed: parseFailed,
          repaired: repaired,
          repairReason: repairReason,
          usedFallback: fallbackUsed,
          fallbackReason: fallbackReason ?? parseFailureReason,
          rawPreview: rawPreview,
          promptMode: promptPayload.promptMode,
          promptChars: promptPayload.promptChars,
          engineConfigMode: engineConfigMode,
          decodingConfig: decodingConfig,
          backendInfo: backendInfo,
          gpuFallbackUsed: gpuFallbackUsed,
        );
      }

      if (parseFailed || fallbackUsed) {
        debugPrint(
          '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_GENERATE_SUCCESS '
          'backend=$backendLabel elapsed_ms=$elapsedMs '
          'parse_failed=$parseFailed fallback_used=$fallbackUsed '
          'parse_failure_reason=${parseFailureReason ?? 'none'} '
          'fallback_reason=${fallbackReason ?? 'none'} '
          'raw_preview=${rawPreview ?? ''}',
        );
      }

      debugPrint(
        '[OnDeviceGemmaExplanationService] ON_DEVICE_GEMMA_RESULT '
        'backend=$backendLabel elapsed_ms=$elapsedMs '
        'timeout_seconds=${_generationTimeout.inSeconds} '
        'success=true fallback=$fallbackUsed parse_failed=$parseFailed',
      );
      debugPrint(
        '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_GENERATE_SUCCESS '
        'backend=$backendLabel elapsed_ms=$elapsedMs json_parse_success=$jsonParseSuccess',
      );
      return PhotoExplanationResult(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: commentType,
        shortReason: shortReason,
        detailedReason: detailedReason,
        comparisonReason: _cleanString(map['comparison_reason']),
        modelLoadTimeMs: _toInt(map['model_load_time_ms']),
        nativeGenerationTimeMs: nativeGenerationMs,
        outputLength: outputLength,
        totalGenerationTimeMs: elapsedMs,
        timeoutSeconds: _generationTimeout.inSeconds,
        jsonParseSuccess: jsonParseSuccess,
        parseFailed: parseFailed,
        repaired: repaired,
        repairReason: repairReason,
        error: error,
        usedFallback: fallbackUsed,
        fallbackReason: fallbackReason ?? parseFailureReason,
        rawPreview: rawPreview,
        promptMode: promptPayload.promptMode,
        promptChars: promptPayload.promptChars,
        engineConfigMode: engineConfigMode,
        decodingConfig: decodingConfig,
        backendInfo: backendInfo,
        gpuFallbackUsed: gpuFallbackUsed,
      );
    } on TimeoutException catch (error) {
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      debugPrint(
        '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_GENERATE_TIMEOUT '
        'backend=$backendLabel elapsed_ms=$elapsedMs error=$error',
      );
      debugPrint(
        '[OnDeviceGemmaExplanationService] ON_DEVICE_GEMMA_RESULT '
        'backend=$backendLabel elapsed_ms=$elapsedMs '
        'timeout_seconds=${_generationTimeout.inSeconds} '
        'success=false fallback=false parse_failed=false',
      );
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: acutCommentTypeForScore(request.finalScore),
        error: error.toString(),
        totalGenerationTimeMs: elapsedMs,
        timeoutSeconds: _generationTimeout.inSeconds,
        promptMode: promptPayload.promptMode,
        promptChars: promptPayload.promptChars,
        engineConfigMode: 'default_safe',
        decodingConfig: 'default_safe',
      );
    } catch (error) {
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      debugPrint(
        '[OnDeviceGemmaExplanationService] GEMMA_FLUTTER_GENERATE_FAILED '
        'backend=$backendLabel elapsed_ms=$elapsedMs error=$error',
      );
      debugPrint(
        '[OnDeviceGemmaExplanationService] ON_DEVICE_GEMMA_RESULT '
        'backend=$backendLabel elapsed_ms=$elapsedMs '
        'timeout_seconds=${_generationTimeout.inSeconds} '
        'success=false fallback=false parse_failed=false',
      );
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: acutCommentTypeForScore(request.finalScore),
        error: error.toString(),
        totalGenerationTimeMs: elapsedMs,
        timeoutSeconds: _generationTimeout.inSeconds,
        promptMode: promptPayload.promptMode,
        promptChars: promptPayload.promptChars,
        engineConfigMode: 'default_safe',
        decodingConfig: 'default_safe',
      );
    }
  }

  Future<String?> _prepareVlmImage(PhotoExplanationRequest request) async {
    if (!ExperimentalFeatures.useVlmResizedImageInput) {
      final path = _cleanString(request.localImagePath);
      if (path == null || !File(path).existsSync()) {
        debugPrint(
            '[OnDeviceGemmaExplanationService] GEMMA_VLM_IMAGE_INPUT status=failed_no_original_path');
        return null;
      }
      debugPrint('[OnDeviceGemmaExplanationService] GEMMA_VLM_IMAGE_INPUT '
          'status=using_original_path '
          'path=$path');
      return path;
    }

    if (request.imageBytes.isEmpty) {
      debugPrint(
          '[OnDeviceGemmaExplanationService] GEMMA_VLM_IMAGE_INPUT status=failed_no_bytes_for_resize');
      return null;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final decoded = await compute(img.decodeImage, request.imageBytes);
      if (decoded == null) {
        debugPrint(
            '[OnDeviceGemmaExplanationService] GEMMA_VLM_IMAGE_INPUT status=failed_decode');
        return null;
      }

      final oriented = img.bakeOrientation(decoded);
      final longSide =
          oriented.width > oriented.height ? oriented.width : oriented.height;

      final needsResize = longSide > ExperimentalFeatures.gemmaVlmMaxLongSide;
      final resized = needsResize
          ? img.copyResize(
              oriented,
              width: oriented.width >= oriented.height
                  ? ExperimentalFeatures.gemmaVlmMaxLongSide
                  : null,
              height: oriented.height > oriented.width
                  ? ExperimentalFeatures.gemmaVlmMaxLongSide
                  : null,
              interpolation: img.Interpolation.average,
            )
          : oriented;

      final dir = Directory('${Directory.systemTemp.path}/acut_vlm_inputs');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeName =
          (request.fileName ?? 'vlm_input_${DateTime.now().millisecondsSinceEpoch}')
              .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final file = File('${dir.path}/$safeName.jpg');

      final jpgBytes = await compute(
          (img.Image image) => img.encodeJpg(
              image, quality: ExperimentalFeatures.gemmaVlmJpegQuality),
          resized);
      await file.writeAsBytes(jpgBytes, flush: true);

      stopwatch.stop();
      debugPrint('[OnDeviceGemmaExplanationService] GEMMA_VLM_IMAGE_INPUT '
          'status=resized_and_saved '
          'original_dims=${oriented.width}x${oriented.height} '
          'resized_dims=${resized.width}x${resized.height} '
          'resized=$needsResize '
          'max_long_side=${ExperimentalFeatures.gemmaVlmMaxLongSide} '
          'jpeg_quality=${ExperimentalFeatures.gemmaVlmJpegQuality} '
          'path=${file.path} '
          'size_bytes=${file.lengthSync()} '
          'prepare_ms=${stopwatch.elapsedMilliseconds}');
      return file.path;
    } catch (e) {
      stopwatch.stop();
      debugPrint('[OnDeviceGemmaExplanationService] GEMMA_VLM_IMAGE_INPUT '
          'status=failed_prepare '
          'error=$e '
          'prepare_ms=${stopwatch.elapsedMilliseconds}');
      return _cleanString(request.localImagePath);
    }
  }

  Future<PhotoExplanationResult> _explainVisual(
    PhotoExplanationRequest request,
  ) async {
    final imagePath = await _prepareVlmImage(request);
    if (imagePath == null) {
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: acutCommentTypeForScore(request.finalScore),
        error: 'missing_or_failed_vlm_image_preparation',
        promptMode: GemmaExplanationMode.visualImageContext.id,
      );
    }

    final promptPayload =
        AcutCommentPromptBuilder.buildVisualOnDeviceGemmaPrompt(
          request,
          modelPath: modelPath,
        );
    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[OnDeviceGemmaExplanationService] ON_DEVICE_GEMMA_PROMPT_MODE '
      'backend=$backendLabel mode=${promptPayload.promptMode} '
      'prompt_chars=${promptPayload.promptChars} '
      'comment_type=${request.defaultCommentType}',
    );
    debugPrint('[OnDeviceGemmaExplanationService] GEMMA_VLM_PROMPT_BEGIN');
    debugPrint(promptPayload.prompt);
    debugPrint('[OnDeviceGemmaExplanationService] GEMMA_VLM_PROMPT_END');
    debugPrint(
      '[OnDeviceGemmaExplanationService] GEMMA_VLM_GENERATE_START '
      'selected_image_path=$imagePath prompt_chars=${promptPayload.promptChars} '
      'backend_mode=$backendMode model_path=$modelPath',
    );
    try {
      final map = await generateAcutVisualComment(
        prompt: promptPayload.prompt,
        imagePath: imagePath,
        defaultCommentType: request.defaultCommentType,
        forceNullComparisonReason:
            request.rank == null || request.totalCount == null,
      );
      stopwatch.stop();
      final elapsedMs =
          _toInt(map['total_ms']) ??
          _toInt(map['elapsed_ms']) ??
          stopwatch.elapsedMilliseconds;
      final result = _resultFromNativeMap(
        request: request,
        map: map,
        promptPayload: promptPayload,
        elapsedMs: elapsedMs,
      );
      debugPrint(
        '[OnDeviceGemmaExplanationService] GEMMA_VLM_GENERATE_RESULT '
        'selected_image_path=$imagePath elapsed_ms=$elapsedMs '
        'image_input_used=${result.imageInputUsed} '
        'success=${result.isSuccessful} fallback=${result.usedFallback} '
        'parse_failed=${result.parseFailed}',
      );
      return result;
    } catch (error) {
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      debugPrint(
        '[OnDeviceGemmaExplanationService] GEMMA_VLM_GENERATE_FAILED '
        'selected_image_path=$imagePath elapsed_ms=$elapsedMs error=$error',
      );
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: acutCommentTypeForScore(request.finalScore),
        error: error.toString(),
        totalGenerationTimeMs: elapsedMs,
        timeoutSeconds: _generationTimeout.inSeconds,
        promptMode: promptPayload.promptMode,
        promptChars: promptPayload.promptChars,
        imagePath: imagePath,
      );
    }
  }

  Future<Map<String, dynamic>> generateRaw(
    PhotoExplanationRequest request,
  ) async {
    if (!_isSupportedPlatform) {
      return {'ok': false, 'error': 'android_only_backend'};
    }

    final promptPayload =
        AcutCommentPromptBuilder.buildCompactOnDeviceGemmaPrompt(
          request,
          modelPath: modelPath,
        );
    final stopwatch = Stopwatch()..start();
    final response = await _channel
        .invokeMethod<dynamic>('generateAcutComment', {
          'inputJson': promptPayload.inputJson,
          'backendMode': backendMode,
        })
        .timeout(_generationTimeout);
    stopwatch.stop();

    final map = _normalizeMap(response);
    return {
      ...map,
      'elapsed_ms':
          _toInt(map['total_generation_time_ms']) ??
          stopwatch.elapsedMilliseconds,
      'timeout_seconds': _generationTimeout.inSeconds,
      'prompt_chars':
          _toInt(map['prompt_chars']) ??
          _toInt(map['promptChars']) ??
          promptPayload.promptChars,
      'prompt_mode':
          _cleanString(map['prompt_mode']) ?? promptPayload.promptMode,
    };
  }

  Future<Map<String, dynamic>> generateAcutVisualComment({
    required String prompt,
    required String imagePath,
    String? defaultCommentType,
    bool forceNullComparisonReason = true,
  }) async {
    if (!_isSupportedPlatform) {
      return {
        'ok': false,
        'image_input_supported': false,
        'image_input_used': false,
        'reason': 'android_only_backend',
        'error': 'android_only_backend',
      };
    }

    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[OnDeviceGemmaExplanationService] GEMMA_VISUAL_PROBE_START '
      'model_path=$modelPath backend_mode=$backendMode '
      'image_path=$imagePath prompt_chars=${prompt.length}',
    );
    try {
      final response = await _channel
          .invokeMethod<dynamic>('generateAcutVisualComment', {
            'prompt': prompt,
            'imagePath': imagePath,
            'modelPath': modelPath,
            'backendMode': backendMode,
            'defaultCommentType': defaultCommentType,
            'forceNullComparisonReason': forceNullComparisonReason,
          })
          .timeout(_generationTimeout);
      stopwatch.stop();
      final map = _normalizeMap(response);
      final enriched = {
        ...map,
        'elapsed_ms': _toInt(map['total_ms']) ?? stopwatch.elapsedMilliseconds,
        'timeout_seconds': _generationTimeout.inSeconds,
      };
      debugPrint(
        '[OnDeviceGemmaExplanationService] GEMMA_VISUAL_PROBE_RESULT '
        'ok=${map['ok']} '
        'image_input_supported=${map['image_input_supported']} '
        'image_input_used=${map['image_input_used']} '
        'elapsed_ms=${enriched['elapsed_ms']} '
        'backend_info=${_cleanString(map['backend_info']) ?? '-'} '
        'error=${_cleanString(map['error']) ?? 'none'}',
      );
      return enriched;
    } on TimeoutException catch (error) {
      stopwatch.stop();
      return {
        'ok': false,
        'image_input_supported': true,
        'image_input_used': false,
        'reason': 'visual_probe_timeout',
        'error': error.toString(),
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'timeout_seconds': _generationTimeout.inSeconds,
      };
    } catch (error) {
      stopwatch.stop();
      return {
        'ok': false,
        'image_input_supported': true,
        'image_input_used': false,
        'reason': 'visual_probe_channel_failed',
        'error': error.toString(),
        'elapsed_ms': stopwatch.elapsedMilliseconds,
        'timeout_seconds': _generationTimeout.inSeconds,
      };
    }
  }

  PhotoExplanationResult _resultFromNativeMap({
    required PhotoExplanationRequest request,
    required Map<String, dynamic> map,
    required OnDeviceGemmaPromptPayload promptPayload,
    required int elapsedMs,
  }) {
    final error = _cleanString(map['error']);
    final shortReason = _cleanString(map['short_reason']) ?? '';
    final detailedReason = _cleanString(map['detailed_reason']) ?? '';
    final commentType =
        _cleanString(map['comment_type']) ??
        acutCommentTypeForScore(request.finalScore);
    final fallbackUsed = map['fallback_used'] == true;
    final parseFailed = map['parse_failed'] == true;
    if (error != null && shortReason.isEmpty && detailedReason.isEmpty) {
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: commentType,
        error: error,
        nativeGenerationTimeMs:
            _toInt(map['native_generation_ms']) ??
            _toInt(map['native_generation_time_ms']),
        outputLength: _toInt(map['output_length']),
        totalGenerationTimeMs: elapsedMs,
        timeoutSeconds: _generationTimeout.inSeconds,
        jsonParseSuccess: map['json_parse_success'] == true,
        parseFailed: parseFailed,
        repaired: map['repaired'] == true,
        repairReason: _cleanString(map['repair_reason']),
        usedFallback: fallbackUsed,
        fallbackReason:
            _cleanString(map['fallback_reason']) ?? _cleanString(map['reason']),
        rawPreview:
            _cleanString(map['raw_preview']) ??
            _cleanString(map['raw_output_preview']),
        promptMode: promptPayload.promptMode,
        promptChars: promptPayload.promptChars,
        backendInfo: _cleanString(map['backend_info']),
        gpuFallbackUsed: map['gpu_fallback_used'] == true,
        imageInputUsed: map['image_input_used'] == true,
      );
    }

    return PhotoExplanationResult(
      backendId: backendId,
      backendLabel: backendLabel,
      commentType: commentType,
      shortReason: shortReason,
      detailedReason: detailedReason,
      comparisonReason: _cleanString(map['comparison_reason']),
      nativeGenerationTimeMs:
          _toInt(map['native_generation_ms']) ??
          _toInt(map['native_generation_time_ms']),
      outputLength: _toInt(map['output_length']),
      totalGenerationTimeMs: elapsedMs,
      timeoutSeconds: _generationTimeout.inSeconds,
      jsonParseSuccess: map['json_parse_success'] == true,
      parseFailed: parseFailed,
      repaired: map['repaired'] == true,
      repairReason: _cleanString(map['repair_reason']),
      error: error,
      usedFallback: fallbackUsed,
      fallbackReason: _cleanString(map['fallback_reason']),
      rawPreview:
          _cleanString(map['raw_preview']) ??
          _cleanString(map['raw_output_preview']),
      promptMode: promptPayload.promptMode,
      promptChars: promptPayload.promptChars,
      backendInfo: _cleanString(map['backend_info']),
      gpuFallbackUsed: map['gpu_fallback_used'] == true,
      imageInputUsed: map['image_input_used'] == true,
      imagePath: _cleanString(map['image_path']),
    );
  }

  bool get _isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Map<String, dynamic> _normalizeMap(dynamic value) {
    if (value is Map) {
      return value.map((key, entry) => MapEntry(key.toString(), entry));
    }
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, entry) => MapEntry(key.toString(), entry));
      }
    }
    return const <String, dynamic>{};
  }

  String? _cleanString(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
