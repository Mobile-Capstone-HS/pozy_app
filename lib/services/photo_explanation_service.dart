import 'package:flutter/foundation.dart';

class PhotoExplanationRequest {
  const PhotoExplanationRequest({
    required this.imageBytes,
    required this.technicalScore,
    required this.finalScore,
    this.aestheticScore,
    this.finalAestheticScore,
    this.rank,
    this.totalCount,
    this.fileName,
    this.localImagePath,
    this.verdict,
    this.usesTechnicalScoreAsFinal,
    this.primaryHint,
    this.qualitySummary,
  });

  final Uint8List imageBytes;
  final double technicalScore;
  final double finalScore;
  final double? aestheticScore;
  final double? finalAestheticScore;
  final int? rank;
  final int? totalCount;
  final String? fileName;
  final String? localImagePath;
  final String? verdict;
  final bool? usesTechnicalScoreAsFinal;
  final String? primaryHint;
  final String? qualitySummary;

  String get defaultCommentType => acutCommentTypeForScore(finalScore);

  String get selectionState => switch (defaultCommentType) {
    'selected_explanation' => 'selected',
    'near_miss_feedback' => 'near_miss',
    _ => 'rejected',
  };

  int get technicalPct => (technicalScore * 100).round();

  int get finalPct => (finalScore * 100).round();

  int? get aestheticPct {
    final score = finalAestheticScore ?? aestheticScore;
    if (score == null) {
      return null;
    }
    return (score * 100).round();
  }

  Map<String, dynamic> toDebugJson() => {
    'technical_score': technicalScore,
    'aesthetic_score': aestheticScore,
    'final_aesthetic_score': finalAestheticScore,
    'final_score': finalScore,
    'rank': rank,
    'total_count': totalCount,
    'file_name': fileName,
    'local_image_path': localImagePath,
    'verdict': verdict,
    'uses_technical_score_as_final': usesTechnicalScoreAsFinal,
    'primary_hint': primaryHint,
    'quality_summary': qualitySummary,
    'selection_state': selectionState,
    'comment_type': defaultCommentType,
  };
}

String acutCommentTypeForScore(double score) {
  if (score >= 0.80) {
    return 'selected_explanation';
  }
  if (score >= 0.60) {
    return 'near_miss_feedback';
  }
  return 'rejection_reason';
}

class PhotoExplanationResult {
  const PhotoExplanationResult({
    required this.backendId,
    required this.backendLabel,
    required this.commentType,
    required this.shortReason,
    required this.detailedReason,
    this.comparisonReason,
    this.modelLoadTimeMs,
    this.nativeGenerationTimeMs,
    this.outputLength,
    this.totalGenerationTimeMs,
    this.timeoutSeconds,
    this.jsonParseSuccess = false,
    this.parseFailed = false,
    this.repaired = false,
    this.repairReason,
    this.error,
    this.usedFallback = false,
    this.fallbackReason,
    this.rawPreview,
    this.rawResponse,
    this.promptMode,
    this.promptChars,
    this.engineConfigMode,
    this.decodingConfig,
    this.backendInfo,
    this.gpuFallbackUsed = false,
    this.imageInputUsed = false,
    this.imagePath,
    this.imageFileSizeBytes,
  });

  factory PhotoExplanationResult.failure({
    required String backendId,
    required String backendLabel,
    required String commentType,
    required String error,
    int? modelLoadTimeMs,
    int? nativeGenerationTimeMs,
    int? outputLength,
    int? totalGenerationTimeMs,
    int? timeoutSeconds,
    bool jsonParseSuccess = false,
    bool parseFailed = false,
    bool repaired = false,
    String? repairReason,
    bool usedFallback = false,
    String? fallbackReason,
    String? rawPreview,
    String? rawResponse,
    String? promptMode,
    int? promptChars,
    String? engineConfigMode,
    String? decodingConfig,
    String? backendInfo,
    bool gpuFallbackUsed = false,
    bool imageInputUsed = false,
    String? imagePath,
    int? imageFileSizeBytes,
  }) {
    return PhotoExplanationResult(
      backendId: backendId,
      backendLabel: backendLabel,
      commentType: commentType,
      shortReason: '',
      detailedReason: '',
      modelLoadTimeMs: modelLoadTimeMs,
      nativeGenerationTimeMs: nativeGenerationTimeMs,
      outputLength: outputLength,
      totalGenerationTimeMs: totalGenerationTimeMs,
      timeoutSeconds: timeoutSeconds,
      jsonParseSuccess: jsonParseSuccess,
      parseFailed: parseFailed,
      repaired: repaired,
      repairReason: repairReason,
      error: error,
      usedFallback: usedFallback,
      fallbackReason: fallbackReason,
      rawPreview: rawPreview,
      rawResponse: rawResponse,
      promptMode: promptMode,
      promptChars: promptChars,
      engineConfigMode: engineConfigMode,
      decodingConfig: decodingConfig,
      backendInfo: backendInfo,
      gpuFallbackUsed: gpuFallbackUsed,
      imageInputUsed: imageInputUsed,
      imagePath: imagePath,
      imageFileSizeBytes: imageFileSizeBytes,
    );
  }

  final String backendId;
  final String backendLabel;
  final String commentType;
  final String shortReason;
  final String detailedReason;
  final String? comparisonReason;
  final int? modelLoadTimeMs;
  final int? nativeGenerationTimeMs;
  final int? outputLength;
  final int? totalGenerationTimeMs;
  final int? timeoutSeconds;
  final bool jsonParseSuccess;
  final bool parseFailed;
  final bool repaired;
  final String? repairReason;
  final String? error;
  final bool usedFallback;
  final String? fallbackReason;
  final String? rawPreview;
  final String? rawResponse;
  final String? promptMode;
  final int? promptChars;
  final String? engineConfigMode;
  final String? decodingConfig;
  final String? backendInfo;
  final bool gpuFallbackUsed;
  final bool imageInputUsed;
  final String? imagePath;
  final int? imageFileSizeBytes;

  bool get hasContent =>
      shortReason.trim().isNotEmpty || detailedReason.trim().isNotEmpty;

  bool get isSuccessful => error == null && hasContent;

  PhotoExplanationResult copyWith({
    String? backendId,
    String? backendLabel,
    String? commentType,
    String? shortReason,
    String? detailedReason,
    Object? comparisonReason = _sentinel,
    Object? modelLoadTimeMs = _sentinel,
    Object? nativeGenerationTimeMs = _sentinel,
    Object? outputLength = _sentinel,
    Object? totalGenerationTimeMs = _sentinel,
    Object? timeoutSeconds = _sentinel,
    bool? jsonParseSuccess,
    bool? parseFailed,
    bool? repaired,
    Object? repairReason = _sentinel,
    Object? error = _sentinel,
    bool? usedFallback,
    Object? fallbackReason = _sentinel,
    Object? rawPreview = _sentinel,
    Object? rawResponse = _sentinel,
    Object? promptMode = _sentinel,
    Object? promptChars = _sentinel,
    Object? engineConfigMode = _sentinel,
    Object? decodingConfig = _sentinel,
    Object? backendInfo = _sentinel,
    bool? gpuFallbackUsed,
    bool? imageInputUsed,
    Object? imagePath = _sentinel,
    Object? imageFileSizeBytes = _sentinel,
  }) {
    return PhotoExplanationResult(
      backendId: backendId ?? this.backendId,
      backendLabel: backendLabel ?? this.backendLabel,
      commentType: commentType ?? this.commentType,
      shortReason: shortReason ?? this.shortReason,
      detailedReason: detailedReason ?? this.detailedReason,
      comparisonReason: comparisonReason == _sentinel
          ? this.comparisonReason
          : comparisonReason as String?,
      modelLoadTimeMs: modelLoadTimeMs == _sentinel
          ? this.modelLoadTimeMs
          : modelLoadTimeMs as int?,
      nativeGenerationTimeMs: nativeGenerationTimeMs == _sentinel
          ? this.nativeGenerationTimeMs
          : nativeGenerationTimeMs as int?,
      outputLength: outputLength == _sentinel
          ? this.outputLength
          : outputLength as int?,
      totalGenerationTimeMs: totalGenerationTimeMs == _sentinel
          ? this.totalGenerationTimeMs
          : totalGenerationTimeMs as int?,
      timeoutSeconds: timeoutSeconds == _sentinel
          ? this.timeoutSeconds
          : timeoutSeconds as int?,
      jsonParseSuccess: jsonParseSuccess ?? this.jsonParseSuccess,
      parseFailed: parseFailed ?? this.parseFailed,
      repaired: repaired ?? this.repaired,
      repairReason: repairReason == _sentinel
          ? this.repairReason
          : repairReason as String?,
      error: error == _sentinel ? this.error : error as String?,
      usedFallback: usedFallback ?? this.usedFallback,
      fallbackReason: fallbackReason == _sentinel
          ? this.fallbackReason
          : fallbackReason as String?,
      rawPreview: rawPreview == _sentinel
          ? this.rawPreview
          : rawPreview as String?,
      rawResponse: rawResponse == _sentinel
          ? this.rawResponse
          : rawResponse as String?,
      promptMode: promptMode == _sentinel
          ? this.promptMode
          : promptMode as String?,
      promptChars: promptChars == _sentinel
          ? this.promptChars
          : promptChars as int?,
      engineConfigMode: engineConfigMode == _sentinel
          ? this.engineConfigMode
          : engineConfigMode as String?,
      decodingConfig: decodingConfig == _sentinel
          ? this.decodingConfig
          : decodingConfig as String?,
      backendInfo: backendInfo == _sentinel
          ? this.backendInfo
          : backendInfo as String?,
      gpuFallbackUsed: gpuFallbackUsed ?? this.gpuFallbackUsed,
      imageInputUsed: imageInputUsed ?? this.imageInputUsed,
      imagePath: imagePath == _sentinel ? this.imagePath : imagePath as String?,
      imageFileSizeBytes: imageFileSizeBytes == _sentinel
          ? this.imageFileSizeBytes
          : imageFileSizeBytes as int?,
    );
  }

  static const Object _sentinel = Object();
}

abstract class PhotoExplanationService {
  String get backendId;
  String get backendLabel;

  Future<PhotoExplanationResult> explain(PhotoExplanationRequest request);
}

class TemplatePhotoExplanationService implements PhotoExplanationService {
  const TemplatePhotoExplanationService();

  @override
  String get backendId => 'template_fallback';

  @override
  String get backendLabel => '템플릿 폴백';

  @override
  Future<PhotoExplanationResult> explain(
    PhotoExplanationRequest request,
  ) async {
    final finalPct = (request.finalScore * 100).round();
    final technicalPct = (request.technicalScore * 100).round();
    final aestheticPct = request.aestheticScore == null
        ? null
        : (request.aestheticScore! * 100).round();
    final commentType = acutCommentTypeForScore(request.finalScore);

    final shortReason = switch (commentType) {
      'selected_explanation' => '전반적인 품질과 인상 점수가 안정적이라 대표 컷 후보로 좋아요.',
      'near_miss_feedback' => '무난하게 활용 가능한 컷이지만 더 좋은 후보가 있을 수 있어요.',
      _ => '기술 또는 미적 완성도가 아쉬워서 재촬영 후보로 보는 편이 안전해요.',
    };

    final detailParts = <String>[
      '기술 점수는 $technicalPct점으로 초점과 노출 안정성을 중심으로 반영했어요.',
      if (aestheticPct != null) '미적 점수는 $aestheticPct점으로 구도와 전체 분위기를 함께 반영했어요.',
      '현재 종합 점수는 $finalPct점이에요.',
    ];
    final comparisonReason = request.rank != null && request.totalCount != null
        ? '현재 컷은 ${request.rank}위로, 같은 묶음 안에서 상대적인 완성도를 기준으로 정리했어요.'
        : null;

    return PhotoExplanationResult(
      backendId: backendId,
      backendLabel: backendLabel,
      commentType: commentType,
      shortReason: shortReason,
      detailedReason: detailParts.join(' '),
      comparisonReason: comparisonReason,
      jsonParseSuccess: true,
      totalGenerationTimeMs: 0,
    );
  }
}

class FallbackPhotoExplanationService implements PhotoExplanationService {
  FallbackPhotoExplanationService({
    required this.primary,
    this.fallbacks = const [],
    this.backendId = 'fallback_chain',
    this.backendLabel = '설명 백엔드 체인',
  });

  final PhotoExplanationService primary;
  final List<PhotoExplanationService> fallbacks;

  @override
  final String backendId;

  @override
  final String backendLabel;

  @override
  Future<PhotoExplanationResult> explain(
    PhotoExplanationRequest request,
  ) async {
    PhotoExplanationResult? lastFailure;

    for (final service in [primary, ...fallbacks]) {
      final result = await service.explain(request);
      if (result.isSuccessful) {
        return result.copyWith(
          usedFallback:
              result.usedFallback || service.backendId != primary.backendId,
        );
      }
      lastFailure = result;
      debugPrint(
        '[FallbackPhotoExplanationService] ${service.backendId} failed: ${result.error}',
      );
    }

    return lastFailure ??
        PhotoExplanationResult.failure(
          backendId: backendId,
          backendLabel: backendLabel,
          commentType: acutCommentTypeForScore(request.finalScore),
          error: 'all_explanation_backends_failed',
        );
  }
}
