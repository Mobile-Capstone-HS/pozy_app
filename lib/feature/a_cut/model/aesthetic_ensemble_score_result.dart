import 'model_score_detail.dart';
import 'aesthetic_ensemble_weights.dart';

class AestheticEnsembleScoreResult {
  final double? nimaScore;
  final double? rgnetScore;
  final double? alampScore;
  final double? finalAestheticScore;
  final AestheticEnsembleWeights weights;
  final List<ModelScoreDetail> scoreDetails;
  final List<String> warnings;
  final String modelVersion;

  const AestheticEnsembleScoreResult({
    required this.nimaScore,
    required this.rgnetScore,
    required this.alampScore,
    required this.finalAestheticScore,
    required this.weights,
    this.scoreDetails = const [],
    this.warnings = const [],
    required this.modelVersion,
  });

  bool get hasCompleteScores =>
      nimaScore != null && rgnetScore != null && alampScore != null;
}
