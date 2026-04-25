class AestheticEnsembleWeights {
  static const double _defaultNimaWeight = 0.10;
  static const double _defaultRgnetWeight = 0.50;
  static const double _defaultAlampWeight = 0.40;

  static const AestheticEnsembleWeights defaults = AestheticEnsembleWeights._(
    nimaWeight: _defaultNimaWeight,
    rgnetWeight: _defaultRgnetWeight,
    alampWeight: _defaultAlampWeight,
  );

  final double nimaWeight;
  final double rgnetWeight;
  final double alampWeight;

  factory AestheticEnsembleWeights({
    double nimaWeight = _defaultNimaWeight,
    double rgnetWeight = _defaultRgnetWeight,
    double alampWeight = _defaultAlampWeight,
  }) {
    return _normalize(
      nimaWeight: nimaWeight,
      rgnetWeight: rgnetWeight,
      alampWeight: alampWeight,
    );
  }

  const AestheticEnsembleWeights._({
    required this.nimaWeight,
    required this.rgnetWeight,
    required this.alampWeight,
  });

  factory AestheticEnsembleWeights.fromJson(Map<String, dynamic> json) {
    return AestheticEnsembleWeights(
      nimaWeight: _readDouble(json['nima_weight']) ?? _defaultNimaWeight,
      rgnetWeight: _readDouble(json['rgnet_weight']) ?? _defaultRgnetWeight,
      alampWeight: _readDouble(json['alamp_weight']) ?? _defaultAlampWeight,
    );
  }

  Map<String, dynamic> toJson() => {
        'nima_weight': nimaWeight,
        'rgnet_weight': rgnetWeight,
        'alamp_weight': alampWeight,
      };

  AestheticEnsembleWeights copyWith({
    double? nimaWeight,
    double? rgnetWeight,
    double? alampWeight,
  }) {
    return AestheticEnsembleWeights(
      nimaWeight: nimaWeight ?? this.nimaWeight,
      rgnetWeight: rgnetWeight ?? this.rgnetWeight,
      alampWeight: alampWeight ?? this.alampWeight,
    );
  }

  double get sum => nimaWeight + rgnetWeight + alampWeight;

  double weightedScore({
    required double nimaScore,
    required double rgnetScore,
    required double alampScore,
  }) {
    return ((nimaScore * nimaWeight) +
            (rgnetScore * rgnetWeight) +
            (alampScore * alampWeight))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static AestheticEnsembleWeights _normalize({
    required double nimaWeight,
    required double rgnetWeight,
    required double alampWeight,
  }) {
    final safeNima = _sanitize(nimaWeight);
    final safeRgnet = _sanitize(rgnetWeight);
    final safeAlamp = _sanitize(alampWeight);
    final total = safeNima + safeRgnet + safeAlamp;

    if (total <= 0) {
      return defaults;
    }

    return AestheticEnsembleWeights._(
      nimaWeight: safeNima / total,
      rgnetWeight: safeRgnet / total,
      alampWeight: safeAlamp / total,
    );
  }

  static double _sanitize(double value) {
    if (!value.isFinite || value.isNaN || value.isNegative) {
      return 0.0;
    }
    return value;
  }

  static double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }
}
