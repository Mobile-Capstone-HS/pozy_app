class AestheticScoreComparisonResult {
  final String? fileName;
  final AestheticModelComparisonRun baselineRun;
  final AestheticModelComparisonRun candidateRun;

  const AestheticScoreComparisonResult({
    this.fileName,
    required this.baselineRun,
    required this.candidateRun,
  });

  double? get scoreDelta {
    final baselineScore = baselineRun.score;
    final candidateScore = candidateRun.score;
    if (baselineScore == null || candidateScore == null) {
      return null;
    }
    return candidateScore - baselineScore;
  }
}

class AestheticModelComparisonRun {
  final String modelId;
  final String displayName;
  final String assetPath;
  final String metadataAssetPath;
  final String interpretation;
  final bool metadataBacked;
  final bool isDefaultModel;
  final bool inferenceSucceeded;
  final double? score;
  final String? errorMessage;

  const AestheticModelComparisonRun({
    required this.modelId,
    required this.displayName,
    required this.assetPath,
    required this.metadataAssetPath,
    required this.interpretation,
    required this.metadataBacked,
    required this.isDefaultModel,
    required this.inferenceSucceeded,
    this.score,
    this.errorMessage,
  });

  int? get scorePct {
    final value = score;
    if (value == null) {
      return null;
    }
    return (value * 100).round();
  }

  String get assetFileName => assetPath.split('/').last;

  String get metadataFileName => metadataAssetPath.split('/').last;
}
