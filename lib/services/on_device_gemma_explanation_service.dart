import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/experimental_features.dart';
import 'acut_comment_prompt_builder.dart';
import 'photo_explanation_service.dart';

class OnDeviceGemmaExplanationService implements PhotoExplanationService {
  OnDeviceGemmaExplanationService({
    MethodChannel? channel,
    this.modelPath = ExperimentalFeatures.gemmaLiteRtLmModelPath,
    Duration? timeout,
  }) : _channel = channel ?? const MethodChannel(_channelName),
       _timeout = timeout ?? ExperimentalFeatures.gemmaGenerationTimeout;

  static const String methodChannelName = _channelName;
  static const String _channelName = 'pozy.gemma_litertlm/method';

  final MethodChannel _channel;
  final String modelPath;
  final Duration _timeout;

  @override
  String get backendId => 'on_device_gemma';

  @override
  String get backendLabel => '온디바이스 Gemma';

  Future<Map<String, dynamic>> preloadModel() async {
    if (!_isSupportedPlatform) {
      return {'ok': false, 'model_loaded': false, 'error': 'android_only'};
    }

    final response = await _channel.invokeMethod<dynamic>('preloadModel', {
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

    final inputJson = AcutCommentPromptBuilder.buildGemmaInputJson(
      request,
      modelPath: modelPath,
    );

    try {
      final response = await _channel
          .invokeMethod<dynamic>('generateAcutComment', {
            'inputJson': inputJson,
          })
          .timeout(_timeout);
      final map = _normalizeMap(response);
      final jsonParseSuccess = map['json_parse_success'] == true;
      final error = _cleanString(map['error']);
      final shortReason = _cleanString(map['short_reason']) ?? '';
      final detailedReason = _cleanString(map['detailed_reason']) ?? '';
      final commentType =
          _cleanString(map['comment_type']) ??
          acutCommentTypeForScore(request.finalScore);

      if (error != null && shortReason.isEmpty && detailedReason.isEmpty) {
        return PhotoExplanationResult.failure(
          backendId: backendId,
          backendLabel: backendLabel,
          commentType: commentType,
          error: error,
          modelLoadTimeMs: _toInt(map['model_load_time_ms']),
          totalGenerationTimeMs: _toInt(map['total_generation_time_ms']),
          jsonParseSuccess: jsonParseSuccess,
          rawResponse: _cleanString(map['raw_text']),
        );
      }

      return PhotoExplanationResult(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: commentType,
        shortReason: shortReason,
        detailedReason: detailedReason,
        comparisonReason: _cleanString(map['comparison_reason']),
        modelLoadTimeMs: _toInt(map['model_load_time_ms']),
        totalGenerationTimeMs: _toInt(map['total_generation_time_ms']),
        jsonParseSuccess: jsonParseSuccess,
        error: error,
        rawResponse: _cleanString(map['raw_text']),
      );
    } catch (error) {
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: acutCommentTypeForScore(request.finalScore),
        error: error.toString(),
      );
    }
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
