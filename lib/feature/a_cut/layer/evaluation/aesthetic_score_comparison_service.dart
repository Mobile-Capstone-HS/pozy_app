import 'package:flutter/foundation.dart';

import '../../model/aesthetic_score_comparison_result.dart';
import '../inference/aesthetic_model_contract.dart';
import '../inference/tflite_aesthetic_service.dart';

class AestheticScoreComparisonService {
  AestheticScoreComparisonService({
    TfliteAestheticService? tfliteService,
    AestheticModelContract? baselineModel,
    AestheticModelContract? candidateModel,
  }) : _tfliteService = tfliteService ?? TfliteAestheticService(),
       _baselineModel = baselineModel ?? stage5StudentAadbBaselineContract,
       _candidateModel = candidateModel ?? conservativeStudentAadbContract;

  final TfliteAestheticService _tfliteService;
  final AestheticModelContract _baselineModel;
  final AestheticModelContract _candidateModel;

  Future<AestheticScoreComparisonResult> compare(
    Uint8List imageBytes, {
    String? fileName,
  }) async {
    final baselineRun = await _runModel(
      imageBytes,
      _baselineModel,
      fileName: fileName,
      isDefaultModel: true,
    );
    final candidateRun = await _runModel(
      imageBytes,
      _candidateModel,
      fileName: fileName,
      isDefaultModel: false,
    );

    return AestheticScoreComparisonResult(
      fileName: fileName,
      baselineRun: baselineRun,
      candidateRun: candidateRun,
    );
  }

  Future<AestheticModelComparisonRun> _runModel(
    Uint8List imageBytes,
    AestheticModelContract contract, {
    required bool isDefaultModel,
    String? fileName,
  }) async {
    debugPrint(
      '[AestheticScoreComparisonService] Running ${contract.id} '
      '(${contract.assetPath}) on ${fileName ?? 'selected_image'}',
    );

    try {
      final run = await _tfliteService.evaluateSingleModel(imageBytes, contract);
      debugPrint(
        '[AestheticScoreComparisonService] ${run.model.id} '
        'score=${run.detail.normalizedScore.toStringAsFixed(4)}',
      );

      return AestheticModelComparisonRun(
        modelId: run.model.id,
        displayName: run.model.displayLabel,
        assetPath: run.model.assetPath,
        metadataAssetPath: run.model.metadataAssetPath,
        interpretation: run.model.displayInterpretation,
        metadataBacked: run.model.metadataBacked,
        isDefaultModel: isDefaultModel,
        inferenceSucceeded: true,
        score: run.detail.normalizedScore,
      );
    } catch (error) {
      debugPrint(
        '[AestheticScoreComparisonService] ${contract.id} failed: $error',
      );

      return AestheticModelComparisonRun(
        modelId: contract.id,
        displayName: contract.label,
        assetPath: contract.assetPath,
        metadataAssetPath: contract.metadataAssetPath,
        interpretation: 'inference_failed',
        metadataBacked: false,
        isDefaultModel: isDefaultModel,
        inferenceSucceeded: false,
        errorMessage: error.toString(),
      );
    }
  }
}
