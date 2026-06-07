import 'package:flutter/foundation.dart';

import '../../model/aesthetic_ensemble_score_result.dart';
import '../../model/aesthetic_ensemble_weights.dart';
import '../../model/model_score_detail.dart';
import '../inference/aesthetic_model_contract.dart';
import '../inference/acut_perf.dart';
import '../inference/image_preprocessor.dart';
import '../inference/tflite_aesthetic_service.dart';

class AestheticEnsembleScoringService {
  // Calibration constants for Ensemble V2 (audited 2026-06-03)
  static const _nimaSlope = 0.8126;
  static const _nimaIntercept = 1.4492;
  static const _rgnetSlope = 0.0899;
  static const _rgnetIntercept = 4.8656;
  static const _alampSlope = 0.1637;
  static const _alampIntercept = 4.6493;

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
    String? debugImageLabel,
    AcutImagePreprocessBundle? preprocessBundle,
    Map<String, Future<Uint8List>>? sharedInputCache,
  }) async {
    final totalSw = AcutAestheticTimingDebug.start();
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
          debugImageLabel: debugImageLabel,
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
    final rgnetRun = runs[rgnetPilResizeAadbContract.id];
    final alampRun = runs[mobileAlampV2Contract.id];
    final aggregationSw = AcutAestheticTimingDebug.start();

    final normalizedWeights = AestheticEnsembleWeights(
      nimaWeight: effectiveWeights.nimaWeight,
      rgnetWeight: effectiveWeights.rgnetWeight,
      alampWeight: effectiveWeights.alampWeight,
    );

    final nimaNorm = nimaRun?.detail.normalizedScore;
    final rgnetNorm = rgnetRun?.detail.normalizedScore;
    final alampNorm = alampRun?.detail.normalizedScore;

    // --- Ensemble V2 Calibration Logic ---
    double? nimaCalib;
    if (nimaNorm != null) {
      final raw10 = nimaNorm * 9.0 + 1.0;
      nimaCalib = raw10 * _nimaSlope + _nimaIntercept;
      if (kDebugMode || kProfileMode) {
        debugPrint(
          '[AcutAestheticEnsembleV2] NIMA: norm=${nimaNorm.toStringAsFixed(4)} '
          'raw10=${raw10.toStringAsFixed(4)} calib=${nimaCalib.toStringAsFixed(4)}',
        );
      }
    }

    double? rgnetCalib;
    if (rgnetNorm != null) {
      final raw10 = rgnetNorm * 10.0;
      rgnetCalib = raw10 * _rgnetSlope + _rgnetIntercept;
      if (kDebugMode || kProfileMode) {
        debugPrint(
          '[AcutAestheticEnsembleV2] RGNet: norm=${rgnetNorm.toStringAsFixed(4)} '
          'raw10=${raw10.toStringAsFixed(4)} calib=${rgnetCalib.toStringAsFixed(4)}',
        );
      }
    }

    double? alampCalib;
    if (alampNorm != null) {
      final raw10 = alampNorm * 10.0;
      alampCalib = raw10 * _alampSlope + _alampIntercept;
      if (kDebugMode || kProfileMode) {
        debugPrint(
          '[AcutAestheticEnsembleV2] A-LAMP: norm=${alampNorm.toStringAsFixed(4)} '
          'raw10=${raw10.toStringAsFixed(4)} calib=${alampCalib.toStringAsFixed(4)}',
        );
      }
    }

    // --- Ensemble V5 Uncalibrated Logic (Production: Product Gold Selected) ---
    double? finalAestheticScore;
    if (nimaNorm != null || rgnetNorm != null || alampNorm != null) {
      var weightSum = 0.0;
      var scoreSum = 0.0;

      if (nimaNorm != null) {
        weightSum += normalizedWeights.nimaWeight;
        scoreSum += nimaNorm * normalizedWeights.nimaWeight;
      }
      if (rgnetNorm != null) {
        weightSum += normalizedWeights.rgnetWeight;
        scoreSum += rgnetNorm * normalizedWeights.rgnetWeight;
      }
      if (alampNorm != null) {
        weightSum += normalizedWeights.alampWeight;
        scoreSum += alampNorm * normalizedWeights.alampWeight;
      }

      if (weightSum > 0.0) {
        finalAestheticScore = (scoreSum / weightSum).clamp(0.0, 1.0);

        if (kDebugMode || kProfileMode) {
          debugPrint(
            '[AcutAestheticEnsembleV5] Production (Product Gold Selected 0.40/0.45/0.15): '
            'nimaNorm=${nimaNorm?.toStringAsFixed(4) ?? 'N/A'} '
            'rgnetNorm=${rgnetNorm?.toStringAsFixed(4) ?? 'N/A'} '
            'alampNorm=${alampNorm?.toStringAsFixed(4) ?? 'N/A'} | '
            'finalNorm=${finalAestheticScore.toStringAsFixed(4)} | '
            'weights ${normalizedWeights.nimaWeight.toStringAsFixed(2)}/'
            '${normalizedWeights.rgnetWeight.toStringAsFixed(2)}/'
            '${normalizedWeights.alampWeight.toStringAsFixed(2)}',
          );
        }
      }
    }

    // --- Ensemble V2 Calibration Logic (Debug Only) ---
    double? calibratedCandidate;
    if (nimaCalib != null || rgnetCalib != null || alampCalib != null) {
      var weightSum = 0.0;
      var scoreSum = 0.0;

      if (nimaCalib != null) {
        weightSum += normalizedWeights.nimaWeight;
        scoreSum += nimaCalib * normalizedWeights.nimaWeight;
      }
      if (rgnetCalib != null) {
        weightSum += normalizedWeights.rgnetWeight;
        scoreSum += rgnetCalib * normalizedWeights.rgnetWeight;
      }
      if (alampCalib != null) {
        weightSum += normalizedWeights.alampWeight;
        scoreSum += alampCalib * normalizedWeights.alampWeight;
      }

      if (weightSum > 0.0) {
        final calibratedEnsemble10 = scoreSum / weightSum;
        // Map back to 0..1
        calibratedCandidate = ((calibratedEnsemble10 - 1.0) / 9.0).clamp(
          0.0,
          1.0,
        );

        if (kDebugMode || kProfileMode) {
          debugPrint(
            '[AcutAestheticEnsembleV2] Calibrated Candidate: ensemble10=${calibratedEnsemble10.toStringAsFixed(4)} '
            'norm=${calibratedCandidate.toStringAsFixed(4)}',
          );

          // [AcutAestheticCompare] Debug comparison for ranking candidates
          if (nimaNorm != null && rgnetNorm != null && alampNorm != null) {
            // 1. newUncalibrated (NIMA 0.37, RGNet 0.41, A-LAMP 0.22)
            final newUncal =
                (nimaNorm * 0.37) + (rgnetNorm * 0.41) + (alampNorm * 0.22);
            // 2. alampHeavy (NIMA 0.25, RGNet 0.30, A-LAMP 0.45)
            final alampHeavy =
                (nimaNorm * 0.25) + (rgnetNorm * 0.30) + (alampNorm * 0.45);
            // 3. nimaHeavy (NIMA 0.50, RGNet 0.30, A-LAMP 0.20)
            final nimaHeavy =
                (nimaNorm * 0.50) + (rgnetNorm * 0.30) + (alampNorm * 0.20);
            // 4. rgnetHeavy (NIMA 0.20, RGNet 0.55, A-LAMP 0.25)
            final rgnetHeavy =
                (nimaNorm * 0.20) + (rgnetNorm * 0.55) + (alampNorm * 0.25);
            // 5. productGoldSelected (NIMA 0.40, RGNet 0.45, A-LAMP 0.15)
            final productGoldSelected =
                (nimaNorm * 0.40) + (rgnetNorm * 0.45) + (alampNorm * 0.15);

            debugPrint(
              '[AcutAestheticCompare] norms nima=${nimaNorm.toStringAsFixed(4)} '
              'rgnet=${rgnetNorm.toStringAsFixed(4)} alamp=${alampNorm.toStringAsFixed(4)} | '
              'newUncal=${newUncal.toStringAsFixed(4)} '
              'calibCandidate=${calibratedCandidate.toStringAsFixed(4)} alampHeavy=${alampHeavy.toStringAsFixed(4)} '
              'nimaHeavy=${nimaHeavy.toStringAsFixed(4)} rgnetHeavy=${rgnetHeavy.toStringAsFixed(4)} '
              'productGoldSelected=${productGoldSelected.toStringAsFixed(4)}',
            );
          }
        }
      }
    }

    if (finalAestheticScore == null) {
      final missing = <String>[
        if (nimaNorm == null) 'nima',
        if (rgnetNorm == null) 'rgnet',
        if (alampNorm == null) 'alamp',
      ];
      debugPrint(
        '[AestheticEnsembleScoringService] missingComponents=$missing',
      );
      debugPrint(
        '[AestheticEnsembleScoringService] effectiveWeights=nima:${normalizedWeights.nimaWeight}, rgnet:${normalizedWeights.rgnetWeight}, alamp:${normalizedWeights.alampWeight}',
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

    final result = AestheticEnsembleScoreResult(
      nimaScore: nimaNorm,
      rgnetScore: rgnetNorm,
      alampScore: alampNorm,
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
    AcutAestheticTimingDebug.logElapsed(
      stopwatch: aggregationSw,
      imageLabel: debugImageLabel,
      imageIndex: imageIndex,
      modelId: 'aesthetic_ensemble',
      phase: 'final_aesthetic_aggregation',
      fields: <String, Object?>{'component_count': runs.length},
    );
    AcutAestheticTimingDebug.logElapsed(
      stopwatch: totalSw,
      imageLabel: debugImageLabel,
      imageIndex: imageIndex,
      modelId: 'aesthetic_ensemble',
      phase: 'total_aesthetic_scoring',
      fields: <String, Object?>{
        'component_count': runs.length,
        'warning_count': warnings.length,
      },
    );

    return result;
  }

  ModelScoreDetail _detailWithWeight(ModelScoreDetail detail, double weight) {
    return detail.copyWith(weight: weight);
  }
}
