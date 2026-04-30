import 'package:flutter/foundation.dart';

import 'acut_comment_prompt_builder.dart';
import 'gemini_analysis_service.dart';
import 'photo_explanation_service.dart';

class GeminiImageScoresPhotoExplanationService
    implements PhotoExplanationService {
  GeminiImageScoresPhotoExplanationService({
    GeminiExplanationService? geminiService,
    this.useLegacyGeminiPrompt = false,
  }) : _geminiService = geminiService ?? GeminiExplanationService();

  final GeminiExplanationService _geminiService;
  final bool useLegacyGeminiPrompt;

  @override
  String get backendId => useLegacyGeminiPrompt
      ? 'gemini_api_image_scores_legacy'
      : 'gemini_api_image_scores';

  @override
  String get backendLabel => 'Gemini API 이미지+점수';

  @override
  Future<PhotoExplanationResult> explain(
    PhotoExplanationRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final explanation = useLegacyGeminiPrompt
          ? await _geminiService.explain(
              imageBytes: request.imageBytes,
              technicalScore: request.technicalScore,
              aestheticScore: request.aestheticScore,
              finalScore: request.finalScore,
              rank: request.rank,
              totalCount: request.totalCount,
            )
          : await _geminiService.explainFromPrompt(
              prompt: AcutCommentPromptBuilder.buildProductionV2(
                request,
                includeImageContext: true,
              ),
              imageBytes: request.imageBytes,
            );
      stopwatch.stop();

      if (explanation == null) {
        return PhotoExplanationResult.failure(
          backendId: backendId,
          backendLabel: backendLabel,
          commentType: acutCommentTypeForScore(request.finalScore),
          error: 'gemini_response_empty',
          totalGenerationTimeMs: stopwatch.elapsedMilliseconds,
        );
      }

      return PhotoExplanationResult(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType:
            explanation.commentType ??
            acutCommentTypeForScore(request.finalScore),
        shortReason: explanation.shortReason,
        detailedReason: explanation.detailedReason,
        comparisonReason: explanation.comparisonReason,
        eyeState: explanation.eyeState,
        eyeStateReason: explanation.eyeStateReason,
        jsonParseSuccess: true,
        totalGenerationTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      stopwatch.stop();
      debugPrint('[GeminiImageScoresPhotoExplanationService] failed: $error');
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: acutCommentTypeForScore(request.finalScore),
        error: error.toString(),
        totalGenerationTimeMs: stopwatch.elapsedMilliseconds,
      );
    }
  }
}

class GeminiTextOnlyPhotoExplanationService implements PhotoExplanationService {
  GeminiTextOnlyPhotoExplanationService({
    GeminiExplanationService? geminiService,
  }) : _geminiService = geminiService ?? GeminiExplanationService();

  final GeminiExplanationService _geminiService;

  @override
  String get backendId => 'gemini_api_text_only';

  @override
  String get backendLabel => 'Gemini API 텍스트 전용';

  @override
  Future<PhotoExplanationResult> explain(
    PhotoExplanationRequest request,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final explanation = await _geminiService.explainFromPrompt(
        prompt: AcutCommentPromptBuilder.buildProductionV2(
          request,
          includeImageContext: false,
        ),
      );
      stopwatch.stop();

      if (explanation == null) {
        return PhotoExplanationResult.failure(
          backendId: backendId,
          backendLabel: backendLabel,
          commentType: acutCommentTypeForScore(request.finalScore),
          error: 'gemini_response_empty',
          totalGenerationTimeMs: stopwatch.elapsedMilliseconds,
        );
      }

      return PhotoExplanationResult(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType:
            explanation.commentType ??
            acutCommentTypeForScore(request.finalScore),
        shortReason: explanation.shortReason,
        detailedReason: explanation.detailedReason,
        comparisonReason: explanation.comparisonReason,
        jsonParseSuccess: true,
        totalGenerationTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      stopwatch.stop();
      debugPrint('[GeminiTextOnlyPhotoExplanationService] failed: $error');
      return PhotoExplanationResult.failure(
        backendId: backendId,
        backendLabel: backendLabel,
        commentType: acutCommentTypeForScore(request.finalScore),
        error: error.toString(),
        totalGenerationTimeMs: stopwatch.elapsedMilliseconds,
      );
    }
  }
}
