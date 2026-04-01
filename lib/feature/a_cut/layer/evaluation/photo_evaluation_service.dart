import 'dart:math' as math;
import 'dart:typed_data';

import '../../model/model_score_detail.dart';
import '../../model/photo_evaluation_result.dart';
import '../inference/tflite_aesthetic_service.dart';

abstract class PhotoEvaluationService {
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
  });
}

class MockPhotoEvaluationService implements PhotoEvaluationService {
  const MockPhotoEvaluationService();

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
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
    TfliteAestheticService? tfliteService,
  }) : _tfliteService = tfliteService ?? TfliteAestheticService();

  final TfliteAestheticService _tfliteService;

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
  }) async {
    final summary = await _tfliteService.evaluate(imageBytes);
    final notes = _buildNotes(summary);
    final warnings = _buildWarnings(summary);

    return PhotoEvaluationResult.fromScores(
      finalScore: summary.finalScore,
      technicalScore: summary.technicalScore,
      aestheticScore: summary.aestheticScore,
      notes: notes,
      warnings: warnings,
      scoreDetails: summary.scoreDetails,
      modelVersion: summary.modelVersion,
      fileName: fileName,
      usesTechnicalScoreAsFinal: summary.usesTechnicalScoreAsFinal,
    );
  }

  List<String> _buildNotes(TflitePhotoScoreSummary summary) {
    final notes = <String>[];
    final koniq = _detail(summary, 'koniq_mobile');
    final flive = _detail(summary, 'flive_image_mobile');

    if (summary.technicalScore >= 0.75) {
      notes.add('선예도와 전반적인 기술 품질이 안정적입니다.');
    } else if (summary.technicalScore >= 0.60) {
      notes.add('기술 품질이 전반적으로 양호합니다.');
    }

    if (koniq != null && koniq.normalizedScore >= 0.72) {
      notes.add('KonIQ 기준 디테일 보존 상태가 좋습니다.');
    }

    if (flive != null && flive.normalizedScore >= 0.72) {
      notes.add('FLIVE-image 기준 흐림과 노이즈 위험이 낮습니다.');
    }

    if (summary.aestheticScore != null && summary.aestheticScore! >= 0.70) {
      notes.add('미적 선호도 모델에서도 긍정적인 결과를 보였습니다.');
    }

    return notes.take(3).toList(growable: false);
  }

  List<String> _buildWarnings(TflitePhotoScoreSummary summary) {
    final warnings = <String>[];
    final koniq = _detail(summary, 'koniq_mobile');
    final flive = _detail(summary, 'flive_image_mobile');

    if (summary.technicalScore < 0.45) {
      warnings.add('흔들림, 노출, 초점 상태를 다시 확인해보세요.');
    } else if (summary.technicalScore < 0.60) {
      warnings.add('약간의 품질 저하가 감지되어 재촬영 여지가 있습니다.');
    }

    if (koniq != null && koniq.normalizedScore < 0.45) {
      warnings.add('KonIQ 점수가 낮아 디테일 손실이 있을 수 있습니다.');
    }

    if (flive != null && flive.normalizedScore < 0.45) {
      warnings.add('FLIVE-image 점수가 낮아 노이즈나 블러 영향이 있을 수 있습니다.');
    }

    warnings.addAll(summary.warnings);
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
