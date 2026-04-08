import 'model_score_detail.dart';

class PhotoEvaluationResult {
  final double finalScore;
  final double technicalScore;
  final double? aestheticScore;
  final String verdict;
  final List<String> notes;
  final List<String> warnings;
  final List<ModelScoreDetail> scoreDetails;
  final String? modelVersion;
  final String? fileName;
  final bool usesTechnicalScoreAsFinal;

  const PhotoEvaluationResult({
    required this.finalScore,
    required this.technicalScore,
    required this.verdict,
    this.aestheticScore,
    this.notes = const [],
    this.warnings = const [],
    this.scoreDetails = const [],
    this.modelVersion,
    this.fileName,
    this.usesTechnicalScoreAsFinal = false,
  });

  factory PhotoEvaluationResult.fromJson(Map<String, dynamic> json) {
    return PhotoEvaluationResult(
      finalScore: (json['final_score'] as num).toDouble(),
      technicalScore: (json['technical_score'] as num).toDouble(),
      aestheticScore: (json['aesthetic_score'] as num?)?.toDouble(),
      verdict: json['verdict'] as String,
      notes: (json['notes'] as List<dynamic>?)?.cast<String>() ?? const [],
      warnings:
          (json['warnings'] as List<dynamic>?)?.cast<String>() ?? const [],
      scoreDetails:
          (json['score_details'] as List<dynamic>?)
              ?.map(
                (entry) => ModelScoreDetail.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .toList() ??
          const [],
      modelVersion: json['model_version'] as String?,
      fileName: json['file_name'] as String?,
      usesTechnicalScoreAsFinal:
          json['uses_technical_score_as_final'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'final_score': finalScore,
        'technical_score': technicalScore,
        if (aestheticScore != null) 'aesthetic_score': aestheticScore,
        'verdict': verdict,
        'notes': notes,
        'warnings': warnings,
        'score_details': scoreDetails.map((detail) => detail.toJson()).toList(),
        if (modelVersion != null) 'model_version': modelVersion,
        if (fileName != null) 'file_name': fileName,
        'uses_technical_score_as_final': usesTechnicalScoreAsFinal,
      };

  factory PhotoEvaluationResult.fromScores({
    required double finalScore,
    required double technicalScore,
    double? aestheticScore,
    List<String> notes = const [],
    List<String> warnings = const [],
    List<ModelScoreDetail> scoreDetails = const [],
    String? modelVersion,
    String? fileName,
    bool usesTechnicalScoreAsFinal = false,
  }) {
    final normalizedFinal = finalScore.clamp(0.0, 1.0).toDouble();
    final normalizedTechnical = technicalScore.clamp(0.0, 1.0).toDouble();
    final normalizedAesthetic =
        (aestheticScore?.clamp(0.0, 1.0) as num?)?.toDouble();

    return PhotoEvaluationResult(
      finalScore: normalizedFinal,
      technicalScore: normalizedTechnical,
      aestheticScore: normalizedAesthetic,
      verdict: _verdictFor(normalizedFinal),
      notes: notes,
      warnings: warnings,
      scoreDetails: scoreDetails,
      modelVersion: modelVersion,
      fileName: fileName,
      usesTechnicalScoreAsFinal: usesTechnicalScoreAsFinal,
    );
  }

  int get finalPct => (finalScore * 100).round();

  int get technicalPct => (technicalScore * 100).round();

  bool get hasAestheticScore => aestheticScore != null;

  int? get aestheticPct {
    final score = aestheticScore;
    if (score == null) {
      return null;
    }
    return (score * 100).round();
  }

  Iterable<ModelScoreDetail> get technicalDetails =>
      scoreDetails.where(
        (detail) => detail.dimension == ModelScoreDimension.technical,
      );

  Iterable<ModelScoreDetail> get aestheticDetails =>
      scoreDetails.where(
        (detail) => detail.dimension == ModelScoreDimension.aesthetic,
      );

  String get qualitySummary {
    switch (verdictLevel) {
      case VerdictLevel.excellent:
        return '대표 컷으로 바로 써도 좋을 만큼 완성도가 높아요.';
      case VerdictLevel.good:
        return '후보 컷으로 올리기 좋은 안정적인 결과예요.';
      case VerdictLevel.average:
        return '무난한 결과지만 더 좋은 컷이 있을 수 있어요.';
      case VerdictLevel.needsWork:
        return '조금만 다시 촬영하면 더 좋아질 수 있어요.';
    }
  }

  String get primaryHint {
    if (notes.isNotEmpty) {
      return notes.first;
    }
    if (warnings.isNotEmpty) {
      return warnings.first;
    }
    return qualitySummary;
  }

  String get evaluationModeLabel {
    if (usesTechnicalScoreAsFinal) {
      return '현재는 온디바이스 품질 평가를 중심으로 요약해요.';
    }
    return '품질과 미적 선호를 함께 반영한 요약 결과예요.';
  }

  VerdictLevel get verdictLevel {
    if (finalScore >= 0.85) return VerdictLevel.excellent;
    if (finalScore >= 0.70) return VerdictLevel.good;
    if (finalScore >= 0.50) return VerdictLevel.average;
    return VerdictLevel.needsWork;
  }

  static String _verdictFor(double score) {
    if (score >= 0.85) return '매우 좋음';
    if (score >= 0.70) return '좋음';
    if (score >= 0.50) return '보통';
    return '아쉬움';
  }
}

enum VerdictLevel { excellent, good, average, needsWork }
