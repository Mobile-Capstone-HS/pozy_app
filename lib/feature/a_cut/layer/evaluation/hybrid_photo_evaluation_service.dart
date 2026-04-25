import 'package:flutter/foundation.dart';

import '../../../../services/gemini_analysis_service.dart';
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
/// To swap Gemini for VILA-full later:
///   - Implement a class with the same return type as [GeminiExplanationService.explain]
///   - Inject it via the [explainer] constructor parameter.
class HybridPhotoEvaluationService implements PhotoEvaluationService {
  HybridPhotoEvaluationService({
    OnDevicePhotoEvaluationService? scorer,
    GeminiExplanationService? explainer,
  }) : _scorer = scorer ?? OnDevicePhotoEvaluationService(),
       _explainer = explainer ?? GeminiExplanationService();

  final OnDevicePhotoEvaluationService _scorer;
  final GeminiExplanationService _explainer;

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
  }) async {
    // Step 1: deterministic on-device scores.
    final scored = await _scorer.evaluate(imageBytes, fileName: fileName);

    // Step 2: Gemini explanation — non-fatal if it fails.
    try {
      final explanation = await _explainer.explain(
        imageBytes: imageBytes,
        technicalScore: scored.technicalScore,
        aestheticScore: scored.aestheticScore,
        finalScore: scored.finalScore,
      );

      if (explanation != null) {
        return scored.copyWith(
          shortExplanation: explanation.shortReason,
          detailedExplanation: explanation.detailedReason,
          eyeState: explanation.eyeState,
          eyeStateReason: explanation.eyeStateReason,
        );
      }
    } catch (e) {
      debugPrint('[HybridPhotoEvaluationService] Gemini explanation failed: $e');
    }

    return scored;
  }
}
