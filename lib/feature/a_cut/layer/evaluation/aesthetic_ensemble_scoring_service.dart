import 'package:flutter/foundation.dart';

import '../../model/aesthetic_ensemble_score_result.dart';
import '../../model/aesthetic_ensemble_weights.dart';
import '../../model/model_score_detail.dart';
import '../inference/aesthetic_model_contract.dart';
import '../inference/image_preprocessor.dart';
import '../inference/tflite_aesthetic_service.dart';

class AestheticEnsembleScoringService {
  AestheticEnsembleScoringService({
    TfliteAestheticService? modelRunner,
    List<AestheticModelContract>? models,
    AestheticEnsembleWeights? defaultWeights,
  }) : _modelRunner =
           modelRunner ??
           TfliteAestheticService(
             technicalModels: const [],
             aestheticModels: const [],
           ),
       _models = models ?? activeAestheticEnsembleContracts,
       _defaultWeights = defaultWeights ?? AestheticEnsembleWeights.defaults;

  final TfliteAestheticService _modelRunner;
  final List<AestheticModelContract> _models;
  final AestheticEnsembleWeights _defaultWeights;

  Future<AestheticEnsembleScoreResult> evaluate(
    Uint8List imageBytes, {
    AestheticEnsembleWeights? weights,
    int? imageIndex,
    AcutImagePreprocessBundle? preprocessBundle,
    Map<String, Future<Uint8List>>? sharedInputCache,
  }) async {
    final effectiveWeights = weights ?? _defaultWeights;
    final inputCache = sharedInputCache ?? <String, Future<Uint8List>>{};
    final runs = <String, TfliteSingleModelRun>{};
    final warnings = <String>[];

    for (final model in _models) {
      try {
        final run = await _modelRunner.evaluateSingleModel(
          imageBytes,
          model,
          imageIndex: imageIndex,
          preprocessBundle: preprocessBundle,
          inputCache: inputCache,
        );
        runs[model.id] = run;
      } catch (error) {
        final warning = '${model.label} 모델을 실행하지 못했습니다: $error';
        warnings.add(warning);
        debugPrint('[AestheticEnsembleScoringService] $warning');
      }
    }

    final nimaRun = runs[nimaMobileContract.id];
    final rgnetRun = runs[rgnetAadbGpuContract.id];
    final alampRun = runs[alampAadbGpuContract.id];

    final normalizedWeights = AestheticEnsembleWeights(
      nimaWeight: effectiveWeights.nimaWeight,
      rgnetWeight: effectiveWeights.rgnetWeight,
      alampWeight: effectiveWeights.alampWeight,
    );

    final nimaScore = nimaRun?.detail.normalizedScore;
    final rgnetScore = rgnetRun?.detail.normalizedScore;
    final alampScore = alampRun?.detail.normalizedScore;

    double? finalAestheticScore;

    if (nimaScore != null && rgnetScore != null && alampScore != null) {
      finalAestheticScore = normalizedWeights.weightedScore(
        nimaScore: nimaScore,
        rgnetScore: rgnetScore,
        alampScore: alampScore,
      );
    } else if (nimaScore != null || rgnetScore != null || alampScore != null) {
      var weightSum = 0.0;
      var scoreSum = 0.0;
      if (nimaScore != null) {
        weightSum += normalizedWeights.nimaWeight;
        scoreSum += nimaScore * normalizedWeights.nimaWeight;
      }
      if (rgnetScore != null) {
        weightSum += normalizedWeights.rgnetWeight;
        scoreSum += rgnetScore * normalizedWeights.rgnetWeight;
      }
      if (alampScore != null) {
        weightSum += normalizedWeights.alampWeight;
        scoreSum += alampScore * normalizedWeights.alampWeight;
      }
      if (weightSum > 0.0) {
        finalAestheticScore = scoreSum / weightSum;
      }
      final missing = <String>[
        if (nimaScore == null) 'nima',
        if (rgnetScore == null) 'rgnet',
        if (alampScore == null) 'alamp',
      ];
      debugPrint(
        '[AestheticEnsembleScoringService] missingComponents=$missing',
      );
      debugPrint(
        '[AestheticEnsembleScoringService] effectiveWeights=nima:${normalizedWeights.nimaWeight}, rgnet:${normalizedWeights.rgnetWeight}, alamp:${normalizedWeights.alampWeight}',
      );
      debugPrint(
        '[AestheticEnsembleScoringService] finalWeightedScore=$finalAestheticScore',
      );
      debugPrint('[AestheticEnsembleScoringService] degraded=true');
    }

    debugPrint(
      '[AestheticEnsembleScoringService] weights='
      'nima=${normalizedWeights.nimaWeight.toStringAsFixed(4)}, '
      'rgnet=${normalizedWeights.rgnetWeight.toStringAsFixed(4)}, '
      'alamp=${normalizedWeights.alampWeight.toStringAsFixed(4)}',
    );
    debugPrint(
      '[AestheticEnsembleScoringService] finalWeightedScore='
      '${finalAestheticScore?.toStringAsFixed(4) ?? 'unavailable'}',
    );

    return AestheticEnsembleScoreResult(
      nimaScore: nimaScore,
      rgnetScore: rgnetScore,
      alampScore: alampScore,
      finalAestheticScore: finalAestheticScore,
      weights: normalizedWeights,
      scoreDetails: [
        if (nimaRun != null)
          _detailWithWeight(nimaRun.detail, normalizedWeights.nimaWeight),
        if (rgnetRun != null)
          _detailWithWeight(rgnetRun.detail, normalizedWeights.rgnetWeight),
        if (alampRun != null)
          _detailWithWeight(alampRun.detail, normalizedWeights.alampWeight),
      ],
      warnings: warnings,
      modelVersion: [
        if (nimaRun != null) nimaRun.model.id,
        if (rgnetRun != null) rgnetRun.model.id,
        if (alampRun != null) alampRun.model.id,
      ].join('+'),
    );
  }

  ModelScoreDetail _detailWithWeight(ModelScoreDetail detail, double weight) {
    return detail.copyWith(weight: weight);
  }
}
