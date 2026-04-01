import 'dart:typed_data';

import '../../model/model_score_detail.dart';
import 'aesthetic_model_contract.dart';
import 'image_preprocessor.dart';
import 'tflite_interpreter_manager.dart';

class TflitePhotoScoreSummary {
  final double technicalScore;
  final double? aestheticScore;
  final double finalScore;
  final List<ModelScoreDetail> scoreDetails;
  final List<String> warnings;
  final bool usesTechnicalScoreAsFinal;
  final String modelVersion;

  const TflitePhotoScoreSummary({
    required this.technicalScore,
    required this.aestheticScore,
    required this.finalScore,
    required this.scoreDetails,
    required this.warnings,
    required this.usesTechnicalScoreAsFinal,
    required this.modelVersion,
  });
}

class TfliteAestheticService {
  TfliteAestheticService({
    TfliteInterpreterManager? interpreterManager,
    ImagePreprocessor? preprocessor,
    List<AestheticModelContract>? technicalModels,
    List<AestheticModelContract>? aestheticModels,
  }) : _interpreterManager =
           interpreterManager ?? TfliteInterpreterManager.instance,
       _preprocessor = preprocessor ?? const ImagePreprocessor(),
       _technicalModels = technicalModels ?? defaultTechnicalModelContracts,
       _aestheticModels = aestheticModels ?? const [];

  final TfliteInterpreterManager _interpreterManager;
  final ImagePreprocessor _preprocessor;
  final List<AestheticModelContract> _technicalModels;
  final List<AestheticModelContract> _aestheticModels;

  Future<TflitePhotoScoreSummary> evaluate(Uint8List imageBytes) async {
    final inputCache = <String, Future<Uint8List>>{};
    final scoreDetails = <ModelScoreDetail>[];
    final warnings = <String>[];

    for (final contract in [..._technicalModels, ..._aestheticModels]) {
      try {
        final detail = await _runContract(
          imageBytes,
          contract,
          inputCache: inputCache,
        );
        scoreDetails.add(detail);
      } catch (_) {
        warnings.add('${contract.label} 모델을 실행하지 못했습니다.');
      }
    }

    final technicalDetails = scoreDetails
        .where((detail) => detail.dimension == ModelScoreDimension.technical)
        .toList(growable: false);
    final aestheticDetails = scoreDetails
        .where((detail) => detail.dimension == ModelScoreDimension.aesthetic)
        .toList(growable: false);

    if (technicalDetails.isEmpty) {
      throw Exception('No technical quality model could be executed.');
    }

    final technicalScore = _blend(technicalDetails);
    final aestheticScore =
        aestheticDetails.isEmpty ? null : _blend(aestheticDetails);
    final usesTechnicalScoreAsFinal = aestheticScore == null;
    final finalScore = aestheticScore == null
        ? technicalScore
        : ((technicalScore * 0.5) + (aestheticScore * 0.5))
            .clamp(0.0, 1.0)
            .toDouble();

    return TflitePhotoScoreSummary(
      technicalScore: technicalScore,
      aestheticScore: aestheticScore,
      finalScore: finalScore,
      scoreDetails: scoreDetails,
      warnings: warnings,
      usesTechnicalScoreAsFinal: usesTechnicalScoreAsFinal,
      modelVersion: scoreDetails.map((detail) => detail.id).join('+'),
    );
  }

  Future<ModelScoreDetail> _runContract(
    Uint8List imageBytes,
    AestheticModelContract contract, {
    required Map<String, Future<Uint8List>> inputCache,
  }) async {
    final interpreter = await _interpreterManager.getInterpreter(
      contract.assetPath,
      useFlexDelegate: contract.useFlexDelegate,
    );

    final preprocessed = await inputCache.putIfAbsent(
      contract.preprocessCacheKey,
      () => _preprocessor.preprocessToRgbFloat32(
        imageBytes,
        width: contract.inputWidth,
        height: contract.inputHeight,
        normalization: contract.normalization,
      ),
    );

    final inputShape = interpreter.getInputTensor(0).shape;
    if (inputShape.length != 4 ||
        inputShape[1] != contract.inputHeight ||
        inputShape[2] != contract.inputWidth ||
        inputShape[3] != 3) {
      throw Exception('Unexpected input shape for ${contract.id}: $inputShape');
    }

    final outputTensor = interpreter.getOutputTensor(0);
    final outputBytes = Uint8List(outputTensor.numElements() * 4);
    interpreter.run(preprocessed, outputBytes.buffer);

    final outputValues = outputBytes.buffer.asFloat32List();
    if (outputValues.length < contract.expectedOutputLength) {
      throw Exception(
        'Unexpected output length for ${contract.id}: ${outputValues.length}',
      );
    }

    return ModelScoreDetail(
      id: contract.id,
      label: contract.label,
      dimension: contract.dimension,
      rawScore: contract.readRawScore(outputValues),
      normalizedScore: contract.normalizeOutput(outputValues),
      weight: contract.weight,
      interpretation: _interpretationFor(contract),
    );
  }

  double _blend(List<ModelScoreDetail> details) {
    final totalWeight = details.fold<double>(
      0.0,
      (sum, detail) => sum + detail.weight,
    );

    if (totalWeight <= 0) {
      return details.first.normalizedScore;
    }

    final weightedSum = details.fold<double>(
      0.0,
      (sum, detail) => sum + detail.weightedContribution,
    );

    return (weightedSum / totalWeight).clamp(0.0, 1.0).toDouble();
  }

  String _interpretationFor(AestheticModelContract contract) {
    switch (contract.outputType) {
      case AestheticModelOutputType.scalarPercent:
        return 'raw / 100 -> [0,1]';
      case AestheticModelOutputType.scalarUnitInterval:
        return 'sigmoid output in [0,1]';
      case AestheticModelOutputType.distribution:
        return 'distribution mean -> [0,1]';
    }
  }
}
