import 'package:flutter/foundation.dart';

class PhotoExplanationRequest {
  const PhotoExplanationRequest({
    required this.imageBytes,
    required this.technicalScore,
    required this.finalScore,
    this.aestheticScore,
    this.rank,
    this.totalCount,
    this.fileName,
  });

  final Uint8List imageBytes;
  final double technicalScore;
  final double finalScore;
  final double? aestheticScore;
  final int? rank;
  final int? totalCount;
  final String? fileName;

  Map<String, dynamic> toDebugJson() => {
    'technical_score': technicalScore,
    'aesthetic_score': aestheticScore,
    'final_score': finalScore,
    'rank': rank,
    'total_count': totalCount,
    'file_name': fileName,
  };
}

String acutCommentTypeForScore(double score) {
  if (score >= 0.80) {
    return 'strong_pick';
  }
  if (score >= 0.60) {
    return 'candidate_keep';
  }
  return 'retry_recommended';
}

class PhotoExplanationResult {
  const PhotoExplanationResult({
    required this.backendId,
    required this.backendLabel,
    required this.commentType,
    required this.shortReason,
    required this.detailedReason,
    this.comparisonReason,
    this.eyeState,
    this.eyeStateReason,
    this.modelLoadTimeMs,
    this.totalGenerationTimeMs,
    this.jsonParseSuccess = false,
    this.error,
    this.usedFallback = false,
    this.rawResponse,
  });

  factory PhotoExplanationResult.failure({
    required String backendId,
    required String backendLabel,
    required String commentType,
    required String error,
    int? modelLoadTimeMs,
    int? totalGenerationTimeMs,
    bool jsonParseSuccess = false,
    String? rawResponse,
  }) {
    return PhotoExplanationResult(
      backendId: backendId,
      backendLabel: backendLabel,
      commentType: commentType,
      shortReason: '',
      detailedReason: '',
      modelLoadTimeMs: modelLoadTimeMs,
      totalGenerationTimeMs: totalGenerationTimeMs,
      jsonParseSuccess: jsonParseSuccess,
      error: error,
      rawResponse: rawResponse,
    );
  }

  final String backendId;
  final String backendLabel;
  final String commentType;
  final String shortReason;
  final String detailedReason;
  final String? comparisonReason;
  final String? eyeState;
  final String? eyeStateReason;
  final int? modelLoadTimeMs;
  final int? totalGenerationTimeMs;
  final bool jsonParseSuccess;
  final String? error;
  final bool usedFallback;
  final String? rawResponse;

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
    Object? eyeState = _sentinel,
    Object? eyeStateReason = _sentinel,
    Object? modelLoadTimeMs = _sentinel,
    Object? totalGenerationTimeMs = _sentinel,
    bool? jsonParseSuccess,
    Object? error = _sentinel,
    bool? usedFallback,
    Object? rawResponse = _sentinel,
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
      eyeState: eyeState == _sentinel ? this.eyeState : eyeState as String?,
      eyeStateReason: eyeStateReason == _sentinel
          ? this.eyeStateReason
          : eyeStateReason as String?,
      modelLoadTimeMs: modelLoadTimeMs == _sentinel
          ? this.modelLoadTimeMs
          : modelLoadTimeMs as int?,
      totalGenerationTimeMs: totalGenerationTimeMs == _sentinel
          ? this.totalGenerationTimeMs
          : totalGenerationTimeMs as int?,
      jsonParseSuccess: jsonParseSuccess ?? this.jsonParseSuccess,
      error: error == _sentinel ? this.error : error as String?,
      usedFallback: usedFallback ?? this.usedFallback,
      rawResponse: rawResponse == _sentinel
          ? this.rawResponse
          : rawResponse as String?,
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
      'strong_pick' => '전반적인 품질과 인상 점수가 안정적이라 대표 컷 후보로 좋아요.',
      'candidate_keep' => '무난하게 활용 가능한 컷이지만 더 좋은 후보가 있을 수 있어요.',
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
          usedFallback: service.backendId != primary.backendId,
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
