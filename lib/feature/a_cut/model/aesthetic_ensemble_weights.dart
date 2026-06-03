class AestheticEnsembleWeights {
  static const double _defaultNimaWeight = 0.40;
  static const double _defaultRgnetWeight = 0.45;
  static const double _defaultAlampWeight = 0.15;
  static const double _defaultIcaaWeight = 0.00;

  static const AestheticEnsembleWeights defaults = AestheticEnsembleWeights._(
    nimaWeight: _defaultNimaWeight,
    rgnetWeight: _defaultRgnetWeight,
    alampWeight: _defaultAlampWeight,
    icaaWeight: _defaultIcaaWeight,
  );

  final double nimaWeight;
  final double rgnetWeight;
  final double alampWeight;
  final double icaaWeight;

  factory AestheticEnsembleWeights({
    double nimaWeight = _defaultNimaWeight,
    double rgnetWeight = _defaultRgnetWeight,
    double alampWeight = _defaultAlampWeight,
    double icaaWeight = _defaultIcaaWeight,
  }) {
    return _normalize(
      nimaWeight: nimaWeight,
      rgnetWeight: rgnetWeight,
      alampWeight: alampWeight,
      icaaWeight: icaaWeight,
    );
  }

  const AestheticEnsembleWeights._({
    required this.nimaWeight,
    required this.rgnetWeight,
    required this.alampWeight,
    required this.icaaWeight,
  });

  factory AestheticEnsembleWeights.fromJson(Map<String, dynamic> json) {
    return AestheticEnsembleWeights(
      nimaWeight: _readDouble(json['nima_weight']) ?? _defaultNimaWeight,
      rgnetWeight: _readDouble(json['rgnet_weight']) ?? _defaultRgnetWeight,
      alampWeight: _readDouble(json['alamp_weight']) ?? _defaultAlampWeight,
      icaaWeight: _readDouble(json['icaa_weight']) ?? _defaultIcaaWeight,
    );
  }

  Map<String, dynamic> toJson() => {
    'nima_weight': nimaWeight,
    'rgnet_weight': rgnetWeight,
    'alamp_weight': alampWeight,
    'icaa_weight': icaaWeight,
  };

  AestheticEnsembleWeights copyWith({
    double? nimaWeight,
    double? rgnetWeight,
    double? alampWeight,
    double? icaaWeight,
  }) {
    return AestheticEnsembleWeights(
      nimaWeight: nimaWeight ?? this.nimaWeight,
      rgnetWeight: rgnetWeight ?? this.rgnetWeight,
      alampWeight: alampWeight ?? this.alampWeight,
      icaaWeight: icaaWeight ?? this.icaaWeight,
    );
  }

  double get sum => nimaWeight + rgnetWeight + alampWeight + icaaWeight;

  double weightedScore({
    required double nimaScore,
    required double rgnetScore,
    required double alampScore,
    required double icaaScore,
  }) {
    return ((nimaScore * nimaWeight) +
            (rgnetScore * rgnetWeight) +
            (alampScore * alampWeight) +
            (icaaScore * icaaWeight))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static AestheticEnsembleWeights _normalize({
    required double nimaWeight,
    required double rgnetWeight,
    required double alampWeight,
    required double icaaWeight,
  }) {
    final safeNima = _sanitize(nimaWeight);
    final safeRgnet = _sanitize(rgnetWeight);
    final safeAlamp = _sanitize(alampWeight);
    final safeIcaa = _sanitize(icaaWeight);
    final total = safeNima + safeRgnet + safeAlamp + safeIcaa;

    if (total <= 0) {
      return defaults;
    }

    return AestheticEnsembleWeights._(
      nimaWeight: safeNima / total,
      rgnetWeight: safeRgnet / total,
      alampWeight: safeAlamp / total,
      icaaWeight: safeIcaa / total,
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
