import 'dart:typed_data';

import '../../model/model_score_detail.dart';
import '../../model/tflite_model_metadata.dart';
import 'image_preprocessor.dart';
import 'tflite_model_metadata_loader.dart';

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
  final String inputDtype;
  final String colorFormat;
  final String tensorLayout;

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
    this.inputDtype = 'float32',
    this.colorFormat = 'RGB',
    this.tensorLayout = 'NHWC',
  });

  String get metadataAssetPath =>
      TfliteModelMetadataLoader.instance.metadataAssetPathForModel(assetPath);

  ResolvedAestheticModelConfig resolve({
    TfliteModelMetadataLoadResult? metadataResult,
  }) {
    final metadata = metadataResult?.metadata;
    final resolutionNotes = <String>[];

    if (metadataResult?.warning != null) {
      resolutionNotes.add(metadataResult!.warning!);
    }

    final resolvedNormalization = _resolveNormalization(metadata);
    if (metadata != null && resolvedNormalization == null) {
      resolutionNotes.add('Unsupported normalization in metadata. Using preset fallback.');
    }

    final resolvedOutputType = _resolveOutputType(metadata);
    if (metadata != null && resolvedOutputType == null) {
      resolutionNotes.add('Unsupported output interpretation in metadata. Using preset fallback.');
    }

    final resolvedColorFormat = _resolveColorFormat(metadata, resolutionNotes);
    final resolvedTensorLayout = _resolveTensorLayout(metadata, resolutionNotes);
    final resolvedDtype = _resolveDtype(metadata, resolutionNotes);

    return ResolvedAestheticModelConfig(
      id: id,
      label: label,
      assetPath: assetPath,
      metadataAssetPath: metadataAssetPath,
      dimension: dimension,
      inputWidth: metadata?.inputWidth ?? inputWidth,
      inputHeight: metadata?.inputHeight ?? inputHeight,
      expectedOutputLength: metadata?.outputElementCount ?? expectedOutputLength,
      normalization: resolvedNormalization ?? normalization,
      outputType: resolvedOutputType ?? outputType,
      weight: weight,
      useFlexDelegate: metadata?.requiresSelectTfOps ?? useFlexDelegate,
      inputDtype: resolvedDtype,
      colorFormat: resolvedColorFormat,
      tensorLayout: resolvedTensorLayout,
      metadata: metadata,
      metadataBacked: metadata != null,
      resolutionNotes: resolutionNotes,
      scoreInterpretation: _resolveScoreInterpretation(
        metadata: metadata,
        outputType: resolvedOutputType ?? outputType,
      ),
    );
  }

  ImageNormalization? _resolveNormalization(TfliteModelMetadata? metadata) {
    if (metadata == null) {
      return null;
    }

    final hint = [
      metadata.input.normalization,
      metadata.output.postprocess,
      metadata.output.interpretation,
    ].whereType<String>().join(' ').toLowerCase();

    if (hint.contains('/255') || hint.contains('/ 255')) {
      return ImageNormalization.zeroToOne;
    }
    if (hint.contains('127.5') || hint.contains('-1.0') || hint.contains('[-1')) {
      return ImageNormalization.minusOneToOne;
    }
    return null;
  }

  AestheticModelOutputType? _resolveOutputType(TfliteModelMetadata? metadata) {
    if (metadata == null) {
      return null;
    }

    final hint = [
      metadata.preset,
      metadata.task,
      metadata.output.summary,
      metadata.output.interpretation,
      metadata.output.postprocess,
    ].whereType<String>().join(' ').toLowerCase();

    if (hint.contains('distribution') ||
        hint.contains('mean score') ||
        hint.contains('weighted mean') ||
        metadata.outputElementCount == 10) {
      return AestheticModelOutputType.distribution;
    }

    if (hint.contains('/100') ||
        hint.contains('/ 100') ||
        hint.contains('mos-like') ||
        hint.contains('raw mos')) {
      return AestheticModelOutputType.scalarPercent;
    }

    if (hint.contains('sigmoid') ||
        hint.contains('[0,1]') ||
        hint.contains('[0, 1]') ||
        hint.contains('unit interval')) {
      return AestheticModelOutputType.scalarUnitInterval;
    }

    final preset = metadata.preset?.toLowerCase();
    if (preset == null) {
      return null;
    }
    if (preset.contains('koniq') || preset.contains('flive')) {
      return AestheticModelOutputType.scalarPercent;
    }
    if (preset.contains('aadb')) {
      return AestheticModelOutputType.scalarUnitInterval;
    }
    if (preset.contains('nima')) {
      return AestheticModelOutputType.distribution;
    }
    return null;
  }

  String _resolveColorFormat(
    TfliteModelMetadata? metadata,
    List<String> resolutionNotes,
  ) {
    final value = metadata?.input.colorFormat?.toUpperCase();
    if (value == null || value.isEmpty) {
      return colorFormat;
    }
    if (value == 'RGB') {
      return value;
    }
    resolutionNotes.add('Unsupported color format "$value". Using $colorFormat fallback.');
    return colorFormat;
  }

  String _resolveTensorLayout(
    TfliteModelMetadata? metadata,
    List<String> resolutionNotes,
  ) {
    final value = metadata?.input.tensorLayout?.toUpperCase();
    if (value == null || value.isEmpty) {
      return tensorLayout;
    }
    if (value == 'NHWC') {
      return value;
    }
    resolutionNotes.add('Unsupported tensor layout "$value". Using $tensorLayout fallback.');
    return tensorLayout;
  }

  String _resolveDtype(
    TfliteModelMetadata? metadata,
    List<String> resolutionNotes,
  ) {
    final value = metadata?.input.dtype?.toLowerCase();
    if (value == null || value.isEmpty) {
      return inputDtype;
    }
    if (value == 'float32') {
      return value;
    }
    resolutionNotes.add('Unsupported input dtype "$value". Using $inputDtype fallback.');
    return inputDtype;
  }

  String _resolveScoreInterpretation({
    required TfliteModelMetadata? metadata,
    required AestheticModelOutputType outputType,
  }) {
    final metadataPostprocess = metadata?.output.postprocess?.trim();
    if (metadataPostprocess != null && metadataPostprocess.isNotEmpty) {
      return 'metadata: $metadataPostprocess';
    }

    final metadataInterpretation = metadata?.output.interpretation?.trim();
    if (metadataInterpretation != null && metadataInterpretation.isNotEmpty) {
      return 'metadata: $metadataInterpretation';
    }

    final fallback = switch (outputType) {
      AestheticModelOutputType.scalarPercent => 'clip(raw_score / 100.0, 0, 1)',
      AestheticModelOutputType.scalarUnitInterval => 'sigmoid output in [0,1]',
      AestheticModelOutputType.distribution =>
        'distribution mean -> normalize from 1-10 into [0,1]',
    };
    return metadata == null ? 'preset fallback: $fallback' : fallback;
  }
}

class ResolvedAestheticModelConfig {
  final String id;
  final String label;
  final String assetPath;
  final String metadataAssetPath;
  final ModelScoreDimension dimension;
  final int inputWidth;
  final int inputHeight;
  final int expectedOutputLength;
  final ImageNormalization normalization;
  final AestheticModelOutputType outputType;
  final double weight;
  final bool useFlexDelegate;
  final String inputDtype;
  final String colorFormat;
  final String tensorLayout;
  final TfliteModelMetadata? metadata;
  final bool metadataBacked;
  final List<String> resolutionNotes;
  final String scoreInterpretation;

  const ResolvedAestheticModelConfig({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.metadataAssetPath,
    required this.dimension,
    required this.inputWidth,
    required this.inputHeight,
    required this.expectedOutputLength,
    required this.normalization,
    required this.outputType,
    required this.weight,
    required this.useFlexDelegate,
    required this.inputDtype,
    required this.colorFormat,
    required this.tensorLayout,
    required this.metadata,
    required this.metadataBacked,
    required this.resolutionNotes,
    required this.scoreInterpretation,
  });

  String get preprocessCacheKey =>
      '$inputWidth:$inputHeight:${normalization.name}:$inputDtype:$colorFormat:$tensorLayout';

  String get displayLabel => label;

  String get displayInterpretation {
    if (resolutionNotes.isEmpty) {
      return scoreInterpretation;
    }
    return '$scoreInterpretation (${resolutionNotes.join(' | ')})';
  }

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
