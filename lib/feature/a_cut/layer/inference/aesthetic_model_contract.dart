import 'dart:typed_data';

import '../../model/model_score_detail.dart';
import 'image_preprocessor.dart';

enum AestheticModelOutputType { scalarPercent, scalarUnitInterval, distribution }

class AestheticModelContract {
  final String id;
  final String label;
  final String assetPath;
  final ModelScoreDimension dimension;
  final int inputWidth;
  final int inputHeight;
  final int expectedOutputLength;
  final ImageNormalization normalization;
  final AestheticModelOutputType outputType;
  final double weight;
  final bool useFlexDelegate;

  const AestheticModelContract({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.dimension,
    required this.inputWidth,
    required this.inputHeight,
    required this.expectedOutputLength,
    required this.normalization,
    required this.outputType,
    required this.weight,
    this.useFlexDelegate = false,
  });

  String get preprocessCacheKey =>
      '$inputWidth:$inputHeight:${normalization.name}';

  double readRawScore(Float32List values) {
    switch (outputType) {
      case AestheticModelOutputType.scalarPercent:
      case AestheticModelOutputType.scalarUnitInterval:
        return values.first;
      case AestheticModelOutputType.distribution:
        var weightedMean = 0.0;
        for (var index = 0; index < values.length; index++) {
          weightedMean += values[index] * (index + 1);
        }
        return weightedMean;
    }
  }

  double normalizeOutput(Float32List values) {
    final rawScore = readRawScore(values);
    switch (outputType) {
      case AestheticModelOutputType.scalarPercent:
        return (rawScore / 100.0).clamp(0.0, 1.0).toDouble();
      case AestheticModelOutputType.scalarUnitInterval:
        return rawScore.clamp(0.0, 1.0).toDouble();
      case AestheticModelOutputType.distribution:
        return ((rawScore - 1.0) / 9.0).clamp(0.0, 1.0).toDouble();
    }
  }
}

const AestheticModelContract koniqMobileContract = AestheticModelContract(
  id: 'koniq_mobile',
  label: 'KonIQ',
  assetPath: 'assets/models/koniq_mobile.tflite',
  dimension: ModelScoreDimension.technical,
  inputWidth: 224,
  inputHeight: 224,
  expectedOutputLength: 1,
  normalization: ImageNormalization.zeroToOne,
  outputType: AestheticModelOutputType.scalarPercent,
  weight: 0.6,
);

const AestheticModelContract fliveImageMobileContract = AestheticModelContract(
  id: 'flive_image_mobile',
  label: 'FLIVE-image',
  assetPath: 'assets/models/flive_image_mobile.tflite',
  dimension: ModelScoreDimension.technical,
  inputWidth: 224,
  inputHeight: 224,
  expectedOutputLength: 1,
  normalization: ImageNormalization.zeroToOne,
  outputType: AestheticModelOutputType.scalarPercent,
  weight: 0.4,
);

const AestheticModelContract aadbMobileContract = AestheticModelContract(
  id: 'aadb_mobile',
  label: 'AADB',
  assetPath: 'assets/models/aadb_mobile.tflite',
  dimension: ModelScoreDimension.aesthetic,
  inputWidth: 224,
  inputHeight: 224,
  expectedOutputLength: 1,
  normalization: ImageNormalization.zeroToOne,
  outputType: AestheticModelOutputType.scalarUnitInterval,
  weight: 1.0,
);

const AestheticModelContract nimaMobileContract = AestheticModelContract(
  id: 'nima_mobile',
  label: 'NIMA',
  assetPath: 'assets/models/nima_mobile.tflite',
  dimension: ModelScoreDimension.aesthetic,
  inputWidth: 224,
  inputHeight: 224,
  expectedOutputLength: 10,
  normalization: ImageNormalization.zeroToOne,
  outputType: AestheticModelOutputType.distribution,
  weight: 1.0,
);

const List<AestheticModelContract> defaultTechnicalModelContracts = [
  koniqMobileContract,
  fliveImageMobileContract,
];

const List<AestheticModelContract> futureAestheticModelContracts = [
  aadbMobileContract,
  nimaMobileContract,
];
