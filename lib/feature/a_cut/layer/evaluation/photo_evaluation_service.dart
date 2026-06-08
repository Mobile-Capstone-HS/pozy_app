import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../../config/experimental_features.dart';
import '../../model/aesthetic_ensemble_score_result.dart';
import '../../model/aesthetic_ensemble_weights.dart';
import '../../model/model_score_detail.dart';
import '../../model/photo_evaluation_result.dart';
import '../inference/aesthetic_model_contract.dart';
import '../inference/acut_perf.dart';
import '../inference/image_preprocessor.dart';
import '../inference/tflite_aesthetic_service.dart';
import 'aesthetic_ensemble_scoring_service.dart';

abstract class PhotoEvaluationService {
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
    String? localImagePath,
    bool skipExplanation = false,
    int? batchImageIndex,
  });
}

class MockPhotoEvaluationService implements PhotoEvaluationService {
  const MockPhotoEvaluationService();

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
    String? localImagePath,
    bool skipExplanation = false,
    int? batchImageIndex,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final seed = imageBytes.fold<int>(0, (acc, byte) => acc ^ byte);
    final rng = math.Random(seed);
    final technical = 0.45 + (rng.nextDouble() * 0.45);
    final aesthetic = 0.45 + (rng.nextDouble() * 0.45);
    final finalScore = ((technical + aesthetic) / 2).clamp(0.0, 1.0).toDouble();

    return PhotoEvaluationResult.fromScores(
      finalScore: finalScore,
      technicalScore: technical,
      aestheticScore: aesthetic,
      finalAestheticScore: aesthetic,
      notes: const ['Mock 평가 결과입니다.'],
      scoreDetails: [
        ModelScoreDetail(
          id: 'mock_technical',
          label: 'Mock',
          dimension: ModelScoreDimension.technical,
          rawScore: technical * 100,
          normalizedScore: technical,
          weight: 1.0,
          interpretation: 'mock / 100 -> [0,1]',
        ),
      ],
      modelVersion: 'mock_v2',
      fileName: fileName,
      usesTechnicalScoreAsFinal: false,
    );
  }
}

abstract final class AcutTopiqFliveShadowStats {
  static int _count = 0;
  static int _topiqTotalMs = 0;
  static int _fliveTotalMs = 0;
  static int _fliveCount = 0;
  static int _extraTotalMs = 0;
  static double _shadowSum = 0.0;
  static double _productionSum = 0.0;
  static double _absDeltaSum = 0.0;
  static double? _shadowMin;
  static double? _shadowMax;
  static double? _productionMin;
  static double? _productionMax;
  static int _deltaGte15Count = 0;
  static int _deltaGte25Count = 0;
  static int _suspiciousProduction45Shadow65Count = 0;
  static int _suspiciousProduction50Shadow70Count = 0;

  static void reset() {
    _count = 0;
    _topiqTotalMs = 0;
    _fliveTotalMs = 0;
    _fliveCount = 0;
    _extraTotalMs = 0;
    _shadowSum = 0.0;
    _productionSum = 0.0;
    _absDeltaSum = 0.0;
    _shadowMin = null;
    _shadowMax = null;
    _productionMin = null;
    _productionMax = null;
    _deltaGte15Count = 0;
    _deltaGte25Count = 0;
    _suspiciousProduction45Shadow65Count = 0;
    _suspiciousProduction50Shadow70Count = 0;
  }

  static void record({
    required double productionScore100,
    required double shadowScore100,
    required int topiqMs,
    required int? fliveMs,
    required int extraMs,
  }) {
    final absDelta = (shadowScore100 - productionScore100).abs();
    _count += 1;
    _topiqTotalMs += topiqMs;
    if (fliveMs != null) {
      _fliveTotalMs += fliveMs;
      _fliveCount += 1;
    }
    _extraTotalMs += extraMs;
    _shadowSum += shadowScore100;
    _productionSum += productionScore100;
    _absDeltaSum += absDelta;
    _shadowMin = _shadowMin == null
        ? shadowScore100
        : math.min(_shadowMin!, shadowScore100);
    _shadowMax = _shadowMax == null
        ? shadowScore100
        : math.max(_shadowMax!, shadowScore100);
    _productionMin = _productionMin == null
        ? productionScore100
        : math.min(_productionMin!, productionScore100);
    _productionMax = _productionMax == null
        ? productionScore100
        : math.max(_productionMax!, productionScore100);

    if (absDelta >= 15.0) {
      _deltaGte15Count += 1;
    }
    if (absDelta >= 25.0) {
      _deltaGte25Count += 1;
    }
    if (productionScore100 < 45.0 && shadowScore100 > 65.0) {
      _suspiciousProduction45Shadow65Count += 1;
    }
    if (productionScore100 < 50.0 && shadowScore100 > 70.0) {
      _suspiciousProduction50Shadow70Count += 1;
    }
  }

  static void logSummary({required int totalImages}) {
    if (!ExperimentalFeatures.enableTopiqFlive6040Shadow) {
      return;
    }
    if (_count == 0) {
      debugPrint(
        '[AcutTopiqFliveShadowSummary] enabled=true total_images=$totalImages '
        'shadow_count=0',
      );
      return;
    }

    debugPrint(
      '[AcutTopiqFliveShadowSummary] enabled=true '
      'total_images=$totalImages '
      'shadow_count=$_count '
      'avg_topiq_ms=${(_topiqTotalMs / _count).toStringAsFixed(1)} '
      'avg_flive_ms=${_fliveCount == 0 ? 'unavailable' : (_fliveTotalMs / _fliveCount).toStringAsFixed(1)} '
      'avg_extra_ms=${(_extraTotalMs / _count).toStringAsFixed(1)} '
      'shadow_min=${_formatScore(_shadowMin)} '
      'shadow_max=${_formatScore(_shadowMax)} '
      'shadow_mean=${(_shadowSum / _count).toStringAsFixed(2)} '
      'production_min=${_formatScore(_productionMin)} '
      'production_max=${_formatScore(_productionMax)} '
      'production_mean=${(_productionSum / _count).toStringAsFixed(2)} '
      'avg_abs_delta=${(_absDeltaSum / _count).toStringAsFixed(2)} '
      'abs_delta_gte_15=$_deltaGte15Count '
      'abs_delta_gte_25=$_deltaGte25Count '
      'suspicious_production_lt45_shadow_gt65=$_suspiciousProduction45Shadow65Count '
      'suspicious_production_lt50_shadow_gt70=$_suspiciousProduction50Shadow70Count',
    );
  }

  static String _formatScore(double? score) {
    return score == null ? 'unavailable' : score.toStringAsFixed(2);
  }
}

class OnDevicePhotoEvaluationService implements PhotoEvaluationService {
  OnDevicePhotoEvaluationService({
    TfliteAestheticService? technicalTfliteService,
    AestheticEnsembleScoringService? aestheticEnsembleService,
    AestheticEnsembleWeights? defaultAestheticWeights,
    ImagePreprocessor? preprocessor,
  }) : _technicalTfliteService =
           technicalTfliteService ??
           TfliteAestheticService(
             technicalModels: defaultTechnicalModelContracts,
             aestheticModels: const [],
           ),
       _aestheticEnsembleService =
           aestheticEnsembleService ?? AestheticEnsembleScoringService(),
       _defaultAestheticWeights =
           defaultAestheticWeights ?? AestheticEnsembleWeights.defaults,
       _preprocessor = preprocessor ?? const ImagePreprocessor();

  final TfliteAestheticService _technicalTfliteService;
  final AestheticEnsembleScoringService _aestheticEnsembleService;
  final AestheticEnsembleWeights _defaultAestheticWeights;
  final ImagePreprocessor _preprocessor;

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
    String? localImagePath,
    bool skipExplanation = false,
    int? batchImageIndex,
  }) async {
    final totalScoringSw = AcutAestheticTimingDebug.start();
    final preprocessBundle = await _preprocessor.createBundle(
      imageBytes,
      debugImageLabel: fileName,
      imageIndex: batchImageIndex,
    );
    final inputCache = <String, Future<Uint8List>>{};
    final technicalScoringSw = AcutAestheticTimingDebug.start();
    final fliveMsBefore = AcutPerfMetrics.totalFliveMs;
    final technicalSummary = await _technicalTfliteService.evaluate(
      imageBytes,
      imageIndex: batchImageIndex,
      preprocessBundle: preprocessBundle,
      sharedInputCache: inputCache,
    );
    final fliveMsDelta = AcutPerfMetrics.totalFliveMs - fliveMsBefore;
    final fliveMs = fliveMsDelta > 0 ? fliveMsDelta : null;
    _logTimingElapsedUs(
      stopwatch: technicalScoringSw,
      imageLabel: fileName,
      imageIndex: batchImageIndex,
      modelId: 'technical_ensemble',
      phase: 'total_technical_scoring',
      imageDimensions:
          '${preprocessBundle.sourceWidth}x${preprocessBundle.sourceHeight}',
      fields: <String, Object?>{
        'bytes': imageBytes.lengthInBytes,
        'timing_tag': 'AcutTimingTechnicalTotal',
      },
    );
    await _runTopiqFliveShadow(
      imageBytes: imageBytes,
      technicalSummary: technicalSummary,
      productionTechnicalScore: technicalSummary.technicalScore,
      fliveMs: fliveMs,
      fileName: fileName,
      batchImageIndex: batchImageIndex,
      preprocessBundle: preprocessBundle,
      inputCache: inputCache,
    );
    AestheticEnsembleScoreResult? aestheticSummary;
    final warnings = <String>[];
    String? aestheticError;

    final aestheticParitySw = AcutAestheticParityDebug.start();
    try {
      aestheticSummary = await _aestheticEnsembleService.evaluate(
        imageBytes,
        weights: _defaultAestheticWeights,
        imageIndex: batchImageIndex,
        debugImageLabel: fileName,
        preprocessBundle: preprocessBundle,
        sharedInputCache: inputCache,
      );
    } catch (error) {
      aestheticError = error.toString();
      warnings.add('미적 앙상블 모델을 실행하지 못했습니다: $error');
    }
    final aestheticElapsedMs = AcutAestheticParityDebug.stopElapsedMs(
      aestheticParitySw,
    );

    if (aestheticSummary != null) {
      warnings.addAll(aestheticSummary.warnings);
    }

    final modelErrors = warnings.toList(growable: false);
    final aestheticScore = aestheticSummary?.finalAestheticScore;
    if (aestheticScore == null) {
      AcutAestheticParityDebug.log(
        imageLabel: fileName,
        imageIndex: batchImageIndex,
        nimaScore: aestheticSummary?.nimaScore,
        rgnetScore: aestheticSummary?.rgnetScore,
        alampScore: aestheticSummary?.alampScore,
        finalAestheticScore: aestheticScore,
        technicalScore: technicalSummary.technicalScore,
        elapsedTotalAestheticMs: aestheticElapsedMs,
        modelErrors: modelErrors,
        error: aestheticError ?? 'aesthetic_score_unavailable',
      );
      throw StateError('aesthetic_score_unavailable');
    }
    const usesTechnicalScoreAsFinal = false;
    final finalScoreMergeSw = AcutAestheticTimingDebug.start();
    final finalScore = ((technicalSummary.technicalScore + aestheticScore) / 2)
        .clamp(0.0, 1.0)
        .toDouble();
    _logTimingElapsedUs(
      stopwatch: finalScoreMergeSw,
      imageLabel: fileName,
      imageIndex: batchImageIndex,
      modelId: 'score_merge',
      phase: 'final_score_merge',
      fields: <String, Object?>{'timing_tag': 'AcutTimingScoreMerge'},
    );
    final notes = _buildNotes(
      technicalSummary: technicalSummary,
      aestheticScore: aestheticScore,
    );
    warnings.addAll(
      _buildWarnings(
        technicalSummary: technicalSummary,
        aestheticScore: aestheticScore,
      ),
    );

    final result = PhotoEvaluationResult.fromScores(
      finalScore: finalScore,
      technicalScore: technicalSummary.technicalScore,
      aestheticScore: aestheticScore,
      finalAestheticScore: aestheticScore,
      nimaScore: aestheticSummary?.nimaScore,
      rgnetScore: aestheticSummary?.rgnetScore,
      alampScore: aestheticSummary?.alampScore,
      nimaWeight: aestheticSummary?.weights.nimaWeight,
      rgnetWeight: aestheticSummary?.weights.rgnetWeight,
      alampWeight: aestheticSummary?.weights.alampWeight,
      notes: notes,
      warnings: warnings,
      scoreDetails: [
        ...technicalSummary.scoreDetails,
        ...?aestheticSummary?.scoreDetails,
      ],
      modelVersion: [
        technicalSummary.modelVersion,
        if (aestheticSummary != null) aestheticSummary.modelVersion,
      ].where((value) => value.trim().isNotEmpty).join('+'),
      fileName: fileName,
      usesTechnicalScoreAsFinal: usesTechnicalScoreAsFinal,
    );
    _logImageFinalScoreParity(
      result: result,
      technicalSummary: technicalSummary,
      fileName: fileName,
      batchImageIndex: batchImageIndex,
    );
    preprocessBundle.logTotal();
    AcutAestheticTimingDebug.logElapsed(
      stopwatch: totalScoringSw,
      imageLabel: fileName,
      imageIndex: batchImageIndex,
      modelId: 'aesthetic_pipeline',
      phase: 'per_image_total_scoring',
      imageDimensions:
          '${preprocessBundle.sourceWidth}x${preprocessBundle.sourceHeight}',
      fields: <String, Object?>{'bytes': imageBytes.lengthInBytes},
    );
    AcutAestheticParityDebug.log(
      imageLabel: fileName,
      imageIndex: batchImageIndex,
      nimaScore: result.nimaScore,
      rgnetScore: result.rgnetScore,
      alampScore: result.alampScore,
      finalAestheticScore: result.finalAestheticScore,
      technicalScore: result.technicalScore,
      elapsedTotalAestheticMs: aestheticElapsedMs,
      modelErrors: modelErrors,
      error: aestheticError,
    );
    return result;
  }

  Future<void> _runTopiqFliveShadow({
    required Uint8List imageBytes,
    required TflitePhotoScoreSummary technicalSummary,
    required double productionTechnicalScore,
    required int? fliveMs,
    required String? fileName,
    required int? batchImageIndex,
    required AcutImagePreprocessBundle preprocessBundle,
    required Map<String, Future<Uint8List>> inputCache,
  }) async {
    if (!ExperimentalFeatures.enableTopiqFlive6040Shadow) {
      return;
    }

    final fliveDetail = _detail(technicalSummary, fliveImageMobileContract.id);
    if (fliveDetail == null) {
      debugPrint(
        '[AcutTopiqFliveShadow] enabled=true '
        'file="${_escapeAcutParityValue(fileName ?? 'unknown')}" '
        'image_index=${batchImageIndex ?? '-'} '
        'skipped=true reason=flive_detail_unavailable',
      );
      return;
    }

    final extraSw = Stopwatch()..start();
    final topiqSw = Stopwatch()..start();
    try {
      final topiqRun = await _technicalTfliteService.evaluateSingleModel(
        imageBytes,
        topiqLiteMixed112Contract,
        imageIndex: batchImageIndex,
        debugImageLabel: fileName,
        preprocessBundle: preprocessBundle,
        inputCache: inputCache,
      );
      topiqSw.stop();
      extraSw.stop();

      final production100 = productionTechnicalScore * 100.0;
      final topiq100 = topiqRun.detail.normalizedScore * 100.0;
      final flive100 = fliveDetail.normalizedScore * 100.0;
      // Official benchmark selected TOPIQ+FLIVE 60:40 for log-only profiling.
      // Not production replacement. Severe FP cases exist. Production score
      // must remain unchanged.
      final shadow100 = (0.6 * topiq100) + (0.4 * flive100);
      final delta100 = shadow100 - production100;
      final productionUnchanged =
          technicalSummary.technicalScore == productionTechnicalScore;

      AcutTopiqFliveShadowStats.record(
        productionScore100: production100,
        shadowScore100: shadow100,
        topiqMs: topiqSw.elapsedMilliseconds,
        fliveMs: fliveMs,
        extraMs: extraSw.elapsedMilliseconds,
      );

      debugPrint(
        '[AcutTopiqFliveShadow] enabled=true '
        'file="${_escapeAcutParityValue(fileName ?? 'unknown')}" '
        'image_index=${batchImageIndex ?? '-'} '
        'productionTechnical=${production100.toStringAsFixed(2)} '
        'topiq=${topiq100.toStringAsFixed(2)} '
        'flive=${flive100.toStringAsFixed(2)} '
        'shadowTopiqFlive6040=${shadow100.toStringAsFixed(2)} '
        'deltaShadowMinusProduction=${delta100.toStringAsFixed(2)} '
        'topiqMs=${topiqSw.elapsedMilliseconds} '
        'fliveMs=${fliveMs?.toString() ?? 'unavailable'} '
        'extraMs=${extraSw.elapsedMilliseconds} '
        'productionUnchanged=$productionUnchanged',
      );
    } catch (error) {
      if (topiqSw.isRunning) {
        topiqSw.stop();
      }
      if (extraSw.isRunning) {
        extraSw.stop();
      }
      debugPrint(
        '[AcutTopiqFliveShadow] enabled=true '
        'file="${_escapeAcutParityValue(fileName ?? 'unknown')}" '
        'image_index=${batchImageIndex ?? '-'} '
        'skipped=true reason=topiq_error '
        'topiqMs=${topiqSw.elapsedMilliseconds} '
        'extraMs=${extraSw.elapsedMilliseconds} '
        'productionUnchanged=true error="${_escapeAcutParityValue(error.toString())}"',
      );
    }
  }

  List<String> _buildNotes({
    required TflitePhotoScoreSummary technicalSummary,
    required double? aestheticScore,
  }) {
    final notes = <String>[];
    final koniq = _detail(technicalSummary, 'koniq_mobile');
    final flive = _detail(technicalSummary, 'flive_image_mobile');

    if (technicalSummary.technicalScore >= 0.75) {
      notes.add('선예도와 전반적인 기술 품질이 안정적입니다.');
    } else if (technicalSummary.technicalScore >= 0.60) {
      notes.add('기술 품질이 전반적으로 양호합니다.');
    }

    if (koniq != null && koniq.normalizedScore >= 0.72) {
      notes.add('디테일 보존 상태가 좋습니다.');
    }

    if (flive != null && flive.normalizedScore >= 0.72) {
      notes.add('흐림과 노이즈 위험이 낮습니다.');
    }

    if (aestheticScore != null && aestheticScore >= 0.70) {
      notes.add('미적 선호도 모델에서도 긍정적인 결과를 보였습니다.');
    }

    return notes.take(3).toList(growable: false);
  }

  List<String> _buildWarnings({
    required TflitePhotoScoreSummary technicalSummary,
    required double? aestheticScore,
  }) {
    final warnings = <String>[];
    final koniq = _detail(technicalSummary, 'koniq_mobile');
    final flive = _detail(technicalSummary, 'flive_image_mobile');

    if (technicalSummary.technicalScore < 0.45) {
      warnings.add('흔들림, 노출, 초점 상태를 다시 확인해보세요.');
    } else if (technicalSummary.technicalScore < 0.60) {
      warnings.add('약간의 품질 저하가 감지되어 재촬영 여지가 있습니다.');
    }

    if (koniq != null && koniq.normalizedScore < 0.45) {
      warnings.add('디테일 손실이 있을 수 있습니다.');
    }

    if (flive != null && flive.normalizedScore < 0.45) {
      warnings.add('노이즈나 블러 영향이 있을 수 있습니다.');
    }

    if (aestheticScore == null) {
      warnings.add('미적 앙상블 결과가 없어 기술 품질 중심으로 점수를 계산했어요.');
    }

    warnings.addAll(technicalSummary.warnings);
    return warnings.take(4).toList(growable: false);
  }

  ModelScoreDetail? _detail(TflitePhotoScoreSummary summary, String id) {
    for (final detail in summary.scoreDetails) {
      if (detail.id == id) {
        return detail;
      }
    }
    return null;
  }
}

void _logImageFinalScoreParity({
  required PhotoEvaluationResult result,
  required TflitePhotoScoreSummary technicalSummary,
  required String? fileName,
  required int? batchImageIndex,
}) {
  if (!ExperimentalFeatures.enableAcutParityDebug) {
    return;
  }

  debugPrint(
    '[AcutParity] image_final_score '
    'image="${_escapeAcutParityValue(fileName ?? 'unknown')}" '
    'batch_index=${batchImageIndex ?? '-'} '
    'technical_score=${result.technicalScore} '
    'aesthetic_score=${result.aestheticScore ?? '-'} '
    'final_score=${result.finalScore} '
    'koniq=${_detailScore(technicalSummary, 'koniq_mobile') ?? '-'} '
    'flive=${_detailScore(technicalSummary, 'flive_image_mobile') ?? '-'} '
    'nima=${result.nimaScore ?? '-'} '
    'rgnet=${result.rgnetScore ?? '-'} '
    'alamp=${result.alampScore ?? '-'}',
  );
}

double? _detailScore(TflitePhotoScoreSummary summary, String id) {
  for (final detail in summary.scoreDetails) {
    if (detail.id == id) {
      return detail.normalizedScore;
    }
  }
  return null;
}

void _logTimingElapsedUs({
  required Stopwatch? stopwatch,
  required String modelId,
  required String phase,
  String? imageLabel,
  int? imageIndex,
  String? imageDimensions,
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  if (stopwatch == null) {
    return;
  }
  if (stopwatch.isRunning) {
    stopwatch.stop();
  }
  AcutAestheticTimingDebug.log(
    imageLabel: imageLabel,
    imageIndex: imageIndex,
    modelId: modelId,
    phase: phase,
    elapsedMs: stopwatch.elapsedMilliseconds,
    imageDimensions: imageDimensions,
    fields: <String, Object?>{
      'elapsedUs': stopwatch.elapsedMicroseconds,
      ...fields,
    },
  );
}

String _escapeAcutParityValue(String value) {
  return value.replaceAll('"', r'\"');
}
