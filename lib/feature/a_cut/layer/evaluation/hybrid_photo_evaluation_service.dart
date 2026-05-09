import 'package:flutter/foundation.dart';

import '../../../../services/gemini_photo_explanation_services.dart';
import '../../../../services/photo_explanation_service.dart';
import '../../model/photo_evaluation_result.dart';
import 'photo_evaluation_service.dart';

/// Combines on-device TFLite scoring with Gemini-based explanation.
///
/// Flow:
///   1. [OnDevicePhotoEvaluationService] runs KonIQ + FLIVE (technical) and
///      the NIMA + RGNet + A-Lamp aesthetic ensemble locally.
///   2. [GeminiExplanationService] receives the image together with those
///      pre-computed scores and returns structured explanation text only.
///   3. The two results are merged via [PhotoEvaluationResult.copyWith].
///
/// If Gemini is unavailable the method still returns a valid result with
/// scores but without explanation fields.
///
/// To swap explanation backends later, implement [PhotoExplanationService] and
/// inject it via the [explainer] constructor parameter.
class HybridPhotoEvaluationService implements PhotoEvaluationService {
  HybridPhotoEvaluationService({
    OnDevicePhotoEvaluationService? scorer,
    PhotoExplanationService? explainer,
  }) : _scorer = scorer ?? OnDevicePhotoEvaluationService(),
       _explainer = explainer ?? _defaultExplainer();

  final OnDevicePhotoEvaluationService _scorer;
  final PhotoExplanationService _explainer;

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
    String? localImagePath,
    bool skipExplanation = false,
    int? batchImageIndex,
  }) async {
    final totalSw = Stopwatch()..start();
    final scoreSw = Stopwatch()..start();

    // Step 1: deterministic on-device scores.
    final scored = await _scorer.evaluate(
      imageBytes,
      fileName: fileName,
      batchImageIndex: batchImageIndex,
    );
    scoreSw.stop();

    if (skipExplanation) {
      totalSw.stop();
      debugPrint(
        '[AcutPerf] image="${fileName ?? 'unknown'}" '
        'total_image_ms=${totalSw.elapsedMilliseconds} '
        'scoring_ms=${scoreSw.elapsedMilliseconds} '
        'explanation_ms=0 skipped_explanation=true',
      );
      return scored;
    }

    // Step 2: explanation backend — non-fatal if it fails.
    final explSw = Stopwatch()..start();
    try {
      final explanation = await _explainer.explain(
        PhotoExplanationRequest(
          imageBytes: imageBytes,
          fileName: fileName,
          localImagePath: localImagePath,
          technicalScore: scored.technicalScore,
          aestheticScore: scored.aestheticScore,
          finalAestheticScore: scored.finalAestheticScore,
          finalScore: scored.finalScore,
          verdict: scored.verdict,
          usesTechnicalScoreAsFinal: scored.usesTechnicalScoreAsFinal,
          primaryHint: scored.primaryHint,
          qualitySummary: scored.qualitySummary,
        ),
      );
      explSw.stop();
      totalSw.stop();
      debugPrint(
        '[AcutPerf] image="${fileName ?? 'unknown'}" total_image_ms=${totalSw.elapsedMilliseconds} scoring_ms=${scoreSw.elapsedMilliseconds} explanation_ms=${explSw.elapsedMilliseconds} expl_backend=${explanation.backendId}',
      );

      if (explanation.isSuccessful) {
        return scored.copyWith(
          shortExplanation: explanation.shortReason,
          detailedExplanation: explanation.detailedReason,
          comparisonExplanation: explanation.comparisonReason,
          explanationBackend: explanation.backendLabel,
        );
      }
    } catch (e) {
      debugPrint(
        '[HybridPhotoEvaluationService] explanation backend failed: $e',
      );
      explSw.stop();
      totalSw.stop();
      debugPrint(
        '[AcutPerf] image="${fileName ?? 'unknown'}" total_image_ms=${totalSw.elapsedMilliseconds} scoring_ms=${scoreSw.elapsedMilliseconds} explanation_ms=${explSw.elapsedMilliseconds} error="$e"',
      );
    }

    return scored;
  }

  static PhotoExplanationService _defaultExplainer() {
    return FallbackPhotoExplanationService(
      primary: GeminiImageScoresPhotoExplanationService(
        useLegacyGeminiPrompt: true,
      ),
      fallbacks: const [TemplatePhotoExplanationService()],
      backendId: 'gemini_template_chain',
      backendLabel: 'Gemini -> Template',
    );
  }
}
