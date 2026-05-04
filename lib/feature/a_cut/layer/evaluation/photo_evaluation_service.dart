import 'dart:math' as math;
import 'dart:typed_data';

import '../../model/aesthetic_ensemble_score_result.dart';
import '../../model/model_score_detail.dart';
import '../../model/photo_evaluation_result.dart';
import '../../model/aesthetic_ensemble_weights.dart';
import '../inference/aesthetic_model_contract.dart';
import '../inference/tflite_aesthetic_service.dart';
import 'aesthetic_ensemble_scoring_service.dart';

abstract class PhotoEvaluationService {
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
    String? localImagePath,
  });
}

class MockPhotoEvaluationService implements PhotoEvaluationService {
  const MockPhotoEvaluationService();

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
    String? localImagePath,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final seed = imageBytes.fold<int>(0, (acc, byte) => acc ^ byte);
    final rng = math.Random(seed);
    final technical = 0.45 + (rng.nextDouble() * 0.45);
    final finalScore = technical;

    return PhotoEvaluationResult.fromScores(
      finalScore: finalScore,
      technicalScore: technical,
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
      usesTechnicalScoreAsFinal: true,
    );
  }
}

class OnDevicePhotoEvaluationService implements PhotoEvaluationService {
  OnDevicePhotoEvaluationService({
    TfliteAestheticService? technicalTfliteService,
    AestheticEnsembleScoringService? aestheticEnsembleService,
    AestheticEnsembleWeights? defaultAestheticWeights,
  }) : _technicalTfliteService =
           technicalTfliteService ??
           TfliteAestheticService(
             technicalModels: defaultTechnicalModelContracts,
             aestheticModels: const [],
           ),
       _aestheticEnsembleService =
           aestheticEnsembleService ?? AestheticEnsembleScoringService(),
       _defaultAestheticWeights =
           defaultAestheticWeights ?? AestheticEnsembleWeights.defaults;

  final TfliteAestheticService _technicalTfliteService;
  final AestheticEnsembleScoringService _aestheticEnsembleService;
  final AestheticEnsembleWeights _defaultAestheticWeights;

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
    String? localImagePath,
  }) async {
    final technicalSummary = await _technicalTfliteService.evaluate(imageBytes);
    AestheticEnsembleScoreResult? aestheticSummary;
    final warnings = <String>[];

    try {
      aestheticSummary = await _aestheticEnsembleService.evaluate(
        imageBytes,
        weights: _defaultAestheticWeights,
      );
    } catch (error) {
      warnings.add('미적 앙상블 모델을 실행하지 못했습니다: $error');
    }

    if (aestheticSummary != null) {
      warnings.addAll(aestheticSummary.warnings);
    }

    final aestheticScore = aestheticSummary?.finalAestheticScore;
    final usesTechnicalScoreAsFinal = aestheticScore == null;
    final finalScore = usesTechnicalScoreAsFinal
        ? technicalSummary.technicalScore
        : ((technicalSummary.technicalScore * 0.5) + (aestheticScore * 0.5))
              .clamp(0.0, 1.0)
              .toDouble();
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

    return PhotoEvaluationResult.fromScores(
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
