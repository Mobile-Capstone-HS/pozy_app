enum ModelScoreDimension { technical, aesthetic }

class ModelScoreDetail {
  final String id;
  final String label;
  final ModelScoreDimension dimension;
  final double rawScore;
  final double normalizedScore;
  final double weight;
  final String interpretation;

  const ModelScoreDetail({
    required this.id,
    required this.label,
    required this.dimension,
    required this.rawScore,
    required this.normalizedScore,
    required this.weight,
    required this.interpretation,
  });

  factory ModelScoreDetail.fromJson(Map<String, dynamic> json) {
    return ModelScoreDetail(
      id: json['id'] as String,
      label: json['label'] as String,
      dimension: ModelScoreDimension.values.byName(json['dimension'] as String),
      rawScore: (json['raw_score'] as num).toDouble(),
      normalizedScore: (json['normalized_score'] as num).toDouble(),
      weight: (json['weight'] as num).toDouble(),
      interpretation: json['interpretation'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'dimension': dimension.name,
        'raw_score': rawScore,
        'normalized_score': normalizedScore,
        'weight': weight,
        'interpretation': interpretation,
      };

  int get normalizedPct => (normalizedScore * 100).round();

  double get weightedContribution => normalizedScore * weight;
}
