import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

import '../../../../config/experimental_features.dart';
import '../../model/model_score_detail.dart';
import 'aesthetic_model_contract.dart';
import 'image_preprocessor.dart';
import 'tflite_interpreter_manager.dart';
import 'tflite_model_metadata_loader.dart';

class AcutPerfMetrics {
  static int totalPreprocessMs = 0;
  static int totalInferenceMs = 0;
  static int totalAlampMs = 0;
  static int totalKoniqMs = 0;
  static int totalFliveMs = 0;
  static int totalNimaMs = 0;
  static int totalRgnetMs = 0;

  static void reset() {
    totalPreprocessMs = 0;
    totalInferenceMs = 0;
    totalAlampMs = 0;
    totalKoniqMs = 0;
    totalFliveMs = 0;
    totalNimaMs = 0;
    totalRgnetMs = 0;
  }
}

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

class TfliteSingleModelRun {
  final ResolvedAestheticModelConfig model;
  final ModelScoreDetail detail;

  const TfliteSingleModelRun({required this.model, required this.detail});
}

class TfliteAestheticService {
  TfliteAestheticService({
    TfliteInterpreterManager? interpreterManager,
    TfliteModelMetadataLoader? metadataLoader,
    ImagePreprocessor? preprocessor,
    List<AestheticModelContract>? technicalModels,
    List<AestheticModelContract>? aestheticModels,
  }) : _interpreterManager =
           interpreterManager ?? TfliteInterpreterManager.instance,
       _metadataLoader = metadataLoader ?? TfliteModelMetadataLoader.instance,
       _preprocessor = preprocessor ?? const ImagePreprocessor(),
       _technicalModels = technicalModels ?? defaultTechnicalModelContracts,
       _aestheticModels = aestheticModels ?? const [];

  final TfliteInterpreterManager _interpreterManager;
  final TfliteModelMetadataLoader _metadataLoader;
  final ImagePreprocessor _preprocessor;
  final List<AestheticModelContract> _technicalModels;
  final List<AestheticModelContract> _aestheticModels;

  Future<TfliteSingleModelRun> evaluateSingleModel(
    Uint8List imageBytes,
    AestheticModelContract contract, {
    int? imageIndex,
    AcutImagePreprocessBundle? bundle,
    AcutImagePreprocessBundle? preprocessBundle,
    Map<String, Future<Uint8List>>? inputCache,
  }) async {
    final resolvedConfig = await _resolveContract(contract);
    if (_isModelDisabledForBatch(resolvedConfig, imageIndex)) {
      return TfliteSingleModelRun(
        model: resolvedConfig,
        detail: _debugFallbackDetail(resolvedConfig),
      );
    }
    final detail = await _runContractWithRetry(
      imageBytes,
      resolvedConfig,
      inputCache: inputCache ?? <String, Future<Uint8List>>{},
      imageIndex: imageIndex,
      bundle: bundle ?? preprocessBundle,
    );

    return TfliteSingleModelRun(model: resolvedConfig, detail: detail);
  }

  Future<TflitePhotoScoreSummary> evaluate(
    Uint8List imageBytes, {
    int? imageIndex,
    AcutImagePreprocessBundle? bundle,
    AcutImagePreprocessBundle? preprocessBundle,
    Map<String, Future<Uint8List>>? sharedInputCache,
  }) async {
    final inputCache = sharedInputCache ?? <String, Future<Uint8List>>{};
    final effectiveBundle = bundle ?? preprocessBundle;
    final scoreDetails = <ModelScoreDetail>[];
    final warnings = <String>[];
    final resolvedConfigs = <ResolvedAestheticModelConfig>[];

    for (final contract in [..._technicalModels, ..._aestheticModels]) {
      final resolvedConfig = await _resolveContract(contract);
      resolvedConfigs.add(resolvedConfig);

      try {
        if (_isModelDisabledForBatch(resolvedConfig, imageIndex)) {
          scoreDetails.add(_debugFallbackDetail(resolvedConfig));
          continue;
        }
        final detail = await _runContractWithRetry(
          imageBytes,
          resolvedConfig,
          inputCache: inputCache,
          imageIndex: imageIndex,
          bundle: effectiveBundle,
        );
        scoreDetails.add(detail);
      } catch (error) {
        warnings.add('${resolvedConfig.displayLabel} 모델을 실행하지 못했습니다.');
        debugPrint(
          '[AcutPerf] model_error image_index=${imageIndex ?? '-'} '
          'model=${resolvedConfig.id} error=$error',
        );
        if (resolvedConfig.id == 'nima_mobile') {
          debugPrint('[AcutPerf] NIMA_ONLY_ERROR error=$error');
          debugPrint(
            '[AcutPerf] nima_summary ok=false path=${resolvedConfig.assetPath} outputMode=distribution_10 normalized=null error=$error',
          );
        }
        if (_shouldRetryInterpreter(resolvedConfig)) {
          await _evictInterpreterFor(resolvedConfig);
        }
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
    final aestheticScore = aestheticDetails.isEmpty
        ? null
        : _blend(aestheticDetails);
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
      modelVersion: resolvedConfigs
          .where(
            (config) => scoreDetails.any((detail) => detail.id == config.id),
          )
          .map(
            (config) =>
                config.metadataBacked ? config.id : '${config.id}_fallback',
          )
          .join('+'),
    );
  }

  Future<ResolvedAestheticModelConfig> _resolveContract(
    AestheticModelContract contract,
  ) async {
    final metadataResult = await _metadataLoader.loadMetadataAsset(
      contract.metadataAssetPath,
    );
    final resolved = contract.resolve(metadataResult: metadataResult);
    if (contract.id == 'nima_mobile' ||
        contract.id == 'rgnet_pil_resize_aadb' ||
        contract.id == 'topiq_lite_mixed112') {
      debugPrint(
        '[TfliteAestheticService] model_resolved '
        'id=${resolved.id} '
        'assetPath=${resolved.assetPath} '
        'metadataPath=${resolved.metadataAssetPath} '
        'metadataBacked=${resolved.metadataBacked} '
        'resizeMode=${resolved.resizeMode.name} '
        'normalization=${resolved.normalization.name} '
        'metadataWarning=${metadataResult.warning ?? 'none'}',
      );
    }
    return resolved;
  }

  Future<ModelScoreDetail> _runContractWithRetry(
    Uint8List imageBytes,
    ResolvedAestheticModelConfig contract, {
    required Map<String, Future<Uint8List>> inputCache,
    int? imageIndex,
    AcutImagePreprocessBundle? bundle,
  }) async {
    try {
      return await _runContract(
        imageBytes,
        contract,
        inputCache: inputCache,
        imageIndex: imageIndex,
        bundle: bundle,
      );
    } catch (error, stackTrace) {
      if (!_shouldRetryInterpreter(contract)) {
        Error.throwWithStackTrace(error, stackTrace);
      }

      debugPrint(
        '[AcutPerf] model_retry_evict image_index=${imageIndex ?? '-'} '
        'model=${contract.id} assetPath=${contract.assetPath} error=$error',
      );
      await _evictInterpreterFor(contract);

      try {
        final detail = await _runContract(
          imageBytes,
          contract,
          inputCache: inputCache,
          imageIndex: imageIndex,
          bundle: bundle,
        );
        debugPrint(
          '[AcutPerf] model_retry_ok image_index=${imageIndex ?? '-'} '
          'model=${contract.id}',
        );
        return detail;
      } catch (retryError, retryStackTrace) {
        debugPrint(
          '[AcutPerf] model_retry_failed image_index=${imageIndex ?? '-'} '
          'model=${contract.id} error=$retryError',
        );
        await _evictInterpreterFor(contract);
        Error.throwWithStackTrace(retryError, retryStackTrace);
      }
    }
  }

  bool _shouldRetryInterpreter(ResolvedAestheticModelConfig contract) {
    return contract.id == 'nima_mobile' ||
        contract.id == 'rgnet_pil_resize_aadb';
  }

  Future<void> _evictInterpreterFor(ResolvedAestheticModelConfig contract) {
    return _interpreterManager.evict(
      contract.assetPath,
      useFlexDelegate: contract.useFlexDelegate,
    );
  }

  Future<ModelScoreDetail> _runContract(
    Uint8List imageBytes,
    ResolvedAestheticModelConfig contract, {
    required Map<String, Future<Uint8List>> inputCache,
    int? imageIndex,
    AcutImagePreprocessBundle? bundle,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint(
      '[AcutPerf] model_start image_index=${imageIndex ?? '-'} '
      'model=${contract.id} '
      'assetPath=${contract.assetPath} '
      'metadataPath=${contract.metadataAssetPath}',
    );
    return _interpreterManager
        .withInterpreter(
          contract.assetPath,
          useFlexDelegate: contract.useFlexDelegate,
          action: (interpreter, descriptor) async {
            if (contract.inputDtype != 'float32') {
              throw Exception(
                'Unsupported input dtype: ${contract.inputDtype}',
              );
            }
            if (contract.colorFormat != 'RGB') {
              throw Exception(
                'Unsupported color format: ${contract.colorFormat}',
              );
            }
            if (contract.tensorLayout != 'NHWC') {
              throw Exception(
                'Unsupported tensor layout: ${contract.tensorLayout}',
              );
            }

            switch (contract.executionMode) {
              case AestheticModelExecutionMode.tensor:
                return _runTensorContract(
                  imageBytes,
                  contract,
                  interpreter: interpreter,
                  descriptor: descriptor,
                  inputCache: inputCache,
                  bundle: bundle,
                );
              case AestheticModelExecutionMode.signature:
                return _runSignatureContract(
                  imageBytes,
                  contract,
                  interpreter: interpreter,
                  descriptor: descriptor,
                  inputCache: inputCache,
                  bundle: bundle,
                );
            }
          },
        )
        .then(
          (detail) {
            sw.stop();
            debugPrint(
              '[AcutPerf] model_done image_index=${imageIndex ?? '-'} '
              'model=${contract.id} inference_ms=${sw.elapsedMilliseconds}',
            );
            return detail;
          },
          onError: (Object error, StackTrace stackTrace) {
            sw.stop();
            debugPrint(
              '[AcutPerf] model_error image_index=${imageIndex ?? '-'} '
              'model=${contract.id} error=$error',
            );
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
  }

  Future<ModelScoreDetail> _runTensorContract(
    Uint8List imageBytes,
    ResolvedAestheticModelConfig contract, {
    required Interpreter interpreter,
    required TfliteModelDescriptor descriptor,
    required Map<String, Future<Uint8List>> inputCache,
    AcutImagePreprocessBundle? bundle,
  }) async {
    if (contract.id == 'nima_mobile') {
      debugPrint('[AcutPerf] NIMA_ONLY_START file=...');
      debugPrint('[AcutPerf] NIMA_ONLY_ASSET path=${contract.assetPath}');

      const expectedInputShape = [1, 224, 224, 3];
      const expectedOutputShape = [1, 10];
      final inputDescriptor = _primaryInputDescriptor(descriptor, contract);
      final outputDescriptor = _primaryOutputDescriptor(descriptor, contract);
      final inputShape = inputDescriptor?.shape;
      final outputShape = outputDescriptor?.shape;
      final inputType = inputDescriptor?.type;
      final outputType = outputDescriptor?.type;
      final sanitizedInputShape = _sanitizeNimaInputShape(inputShape);
      final sanitizedOutputShape = _sanitizeNimaOutputShape(outputShape);
      debugPrint(
        '[AcutPerf] NIMA_TENSORS_CACHED '
        'inputShape=${inputShape ?? 'unavailable'} '
        'inputType=${inputType ?? 'unavailable'} '
        'outputShape=${outputShape ?? 'unavailable'} '
        'outputType=${outputType ?? 'unavailable'}',
      );
      debugPrint(
        '[AcutPerf] NIMA_TENSORS_EXPECTED '
        'inputShape=$expectedInputShape outputShape=$expectedOutputShape',
      );

      if (!listEquals(sanitizedInputShape, expectedInputShape)) {
        throw Exception(
          'NIMA input shape mismatch. Expected $expectedInputShape, got $inputShape sanitized=$sanitizedInputShape',
        );
      }
      if (!listEquals(sanitizedOutputShape, expectedOutputShape)) {
        throw Exception(
          'NIMA output shape mismatch. Expected $expectedOutputShape, got $outputShape sanitized=$sanitizedOutputShape',
        );
      }
      if (!_isFloat32Type(inputType)) {
        throw Exception(
          'NIMA input type mismatch. Expected float32, got $inputType',
        );
      }
      if (!_isFloat32Type(outputType)) {
        throw Exception(
          'NIMA output type mismatch. Expected float32, got $outputType',
        );
      }

      const inputWidth = 224;
      const inputHeight = 224;
      const expectedBytes = 602112;
      final cacheKey =
          'nima:0:$inputWidth:$inputHeight:${contract.normalization.name}:'
          '${contract.inputDtype}:${contract.colorFormat}:${contract.tensorLayout}';

      final preSw = Stopwatch()..start();
      final preprocessed = await inputCache.putIfAbsent(
        cacheKey,
        () =>
            bundle?.rgbFloat32(
              width: inputWidth,
              height: inputHeight,
              normalization: contract.normalization,
            ) ??
            _preprocessor.preprocessToRgbFloat32(
              imageBytes,
              width: inputWidth,
              height: inputHeight,
              normalization: contract.normalization,
            ),
      );
      preSw.stop();
      final int pMs = preSw.elapsedMilliseconds;
      AcutPerfMetrics.totalPreprocessMs += pMs;
      debugPrint(
        '[AcutPerf] preprocess_${inputWidth}_ms=$pMs model=${contract.id}',
      );

      if (preprocessed.lengthInBytes != expectedBytes) {
        debugPrint(
          '[AcutPerf] NIMA_MATCH_ERROR error="Input buffer size mismatch. '
          'Expected $expectedBytes, got ${preprocessed.lengthInBytes}"',
        );
        throw Exception('NIMA input buffer size mismatch');
      }

      if (ExperimentalFeatures.verboseModelLogs) {
        debugPrint(
          '[AcutPerf] NIMA_ONLY_INPUT_BUFFER '
          'runtimeType=${preprocessed.runtimeType} '
          'length=${preprocessed.length} bytes=${preprocessed.lengthInBytes}',
        );
      }

      debugPrint('[AcutPerf] NIMA_ONLY_PATH tensor_plain');
      final output = [List<double>.filled(10, 0.0)];
      debugPrint(
        '[AcutPerf] NIMA_OUTPUT_ALLOC type=${output.runtimeType} shape=[1,10]',
      );

      final inferSw = Stopwatch()..start();
      interpreter.run(preprocessed, output);
      inferSw.stop();
      final int iMs = inferSw.elapsedMilliseconds;
      AcutPerfMetrics.totalInferenceMs += iMs;

      if (ExperimentalFeatures.verboseModelLogs) {
        debugPrint(
          '[AcutPerf] NIMA_OUTPUT_AFTER_RUN '
          'type=${output.runtimeType} outer_len=${output.length} '
          'inner_type=${output.isNotEmpty ? output[0].runtimeType : "none"} '
          'inner_len=${output.isNotEmpty ? output[0].length : 0}',
        );
      }

      final probs = _extractNimaProbabilities(output);
      debugPrint(
        '[AcutPerf] NIMA_ONLY_DONE elapsed_ms=${inferSw.elapsedMilliseconds}',
      );
      debugPrint(
        '[AcutPerf] model_inference_only_ms=$iMs model=${contract.id}',
      );

      final int totalMs = pMs + iMs;
      debugPrint(
        '[AcutPerf] model_total_with_preprocess_ms=$totalMs model=${contract.id}',
      );
      AcutPerfMetrics.totalNimaMs += totalMs;

      return _parseNimaDistribution10(contract, probs);
    }

    if (contract.id == 'rgnet_pil_resize_aadb') {
      return _runRgnetPilResizeTensorContract(
        imageBytes,
        contract,
        interpreter: interpreter,
        descriptor: descriptor,
        inputCache: inputCache,
        bundle: bundle,
      );
    }

    final inputDescriptors = descriptor.inputTensors;
    if (inputDescriptors.isEmpty) {
      throw Exception('No input tensors found for ${contract.id}.');
    }

    final preparedInputs = <Uint8List>[];
    final resolvedInputShapes = <List<int>>[];
    var preprocessMs = 0;

    for (var index = 0; index < inputDescriptors.length; index++) {
      final inputDescriptor = inputDescriptors[index];
      if (!_isFloat32Type(inputDescriptor.type)) {
        throw Exception(
          'Input type mismatch for ${contract.id} tensor#$index. '
          'Expected float32, got ${inputDescriptor.type}',
        );
      }

      final inputShape = _sanitizeRgbInputShape(
        inputDescriptor.shape,
        contract,
      );
      if (inputShape.length != 4 || inputShape[3] != 3) {
        throw Exception(
          'Unsupported input shape for ${contract.id} '
          'tensor#$index: ${inputDescriptor.shape}',
        );
      }

      final runtimeHeight = inputShape[1];
      final runtimeWidth = inputShape[2];
      final expectedBytes = runtimeHeight * runtimeWidth * 3 * 4;
      final cacheKey =
          '$index:$runtimeWidth:$runtimeHeight:${contract.normalization.name}:'
          '${contract.resizeMode.name}:'
          '${contract.inputDtype}:${contract.colorFormat}:${contract.tensorLayout}';

      final preSw = Stopwatch()..start();

      final preprocessed = await inputCache.putIfAbsent(
        cacheKey,
        () => _preprocessTensorInput(
          imageBytes,
          width: runtimeWidth,
          height: runtimeHeight,
          normalization: contract.normalization,
          resizeMode: contract.resizeMode,
          bundle: bundle,
        ),
      );
      preSw.stop();
      final pMs = preSw.elapsedMilliseconds;
      preprocessMs += pMs;
      AcutPerfMetrics.totalPreprocessMs += pMs;
      debugPrint(
        '[AcutPerf] preprocess_${runtimeWidth}_ms=$pMs model=${contract.id} '
        'resize_mode=${contract.resizeMode.name}',
      );

      if (preprocessed.lengthInBytes != expectedBytes) {
        throw Exception(
          'Input buffer size mismatch. Expected $expectedBytes, got ${preprocessed.lengthInBytes}',
        );
      }

      preparedInputs.add(preprocessed);
      resolvedInputShapes.add(inputShape);
    }

    if (preparedInputs.length > 1) {
      debugPrint(
        '[TfliteAestheticService] ${contract.id} has ${preparedInputs.length} '
        'input tensors. Reusing the source image for each input tensor.',
      );
    }

    final outputDescriptors = descriptor.outputTensors;
    final outputBuffers = <int, ByteBuffer>{};
    if (outputDescriptors.isEmpty) {
      throw Exception('No output tensors found for ${contract.id}.');
    }

    for (var index = 0; index < outputDescriptors.length; index++) {
      final outputDescriptor = outputDescriptors[index];
      if (!_isFloat32Type(outputDescriptor.type)) {
        throw Exception(
          'Output type mismatch for ${contract.id} tensor#$index. '
          'Expected float32, got ${outputDescriptor.type}',
        );
      }
      var elementCount = outputDescriptor.elementCount;
      if (elementCount <= 0) {
        elementCount = contract.expectedOutputLength;
      }
      outputBuffers[index] = Uint8List(elementCount * 4).buffer;
    }

    final inferSw = Stopwatch()..start();
    if (preparedInputs.length == 1 && outputBuffers.length == 1) {
      interpreter.run(preparedInputs.first, outputBuffers[0]!);
    } else {
      interpreter.runForMultipleInputs(preparedInputs, {
        for (final entry in outputBuffers.entries) entry.key: entry.value,
      });
    }
    inferSw.stop();

    final iMs = inferSw.elapsedMilliseconds;
    AcutPerfMetrics.totalInferenceMs += iMs;
    debugPrint('[AcutPerf] model_inference_only_ms=$iMs model=${contract.id}');

    final int totalMs = preprocessMs + iMs;
    debugPrint(
      '[AcutPerf] model_total_with_preprocess_ms=$totalMs model=${contract.id}',
    );

    if (contract.id == 'koniq_mobile') {
      AcutPerfMetrics.totalKoniqMs += totalMs;
    } else if (contract.id == 'flive_image_mobile') {
      AcutPerfMetrics.totalFliveMs += totalMs;
    } else if (contract.id == 'rgnet_pil_resize_aadb') {
      AcutPerfMetrics.totalRgnetMs += totalMs;
    }

    final primaryOutputTensor = outputDescriptors.first;
    final outputBuffer = outputBuffers[0]!;
    final runtimeOutputElementCount = primaryOutputTensor.elementCount > 0
        ? primaryOutputTensor.elementCount
        : contract.expectedOutputLength;
    final outputValues = outputBuffer.asFloat32List(
      0,
      math.min(
        outputBuffer.lengthInBytes ~/ 4,
        math.max(1, runtimeOutputElementCount),
      ),
    );
    if (outputValues.isEmpty) {
      throw Exception('No output values found for ${contract.id}.');
    }

    final runtimeOutputType = _resolveRuntimeOutputType(
      contract.outputType,
      outputValues.length,
    );
    final runtimeContract = contract.withRuntimeOverrides(
      inputWidth:
          resolvedInputShapes.first.length >= 3 &&
              resolvedInputShapes.first[2] > 0
          ? resolvedInputShapes.first[2]
          : contract.inputWidth,
      inputHeight:
          resolvedInputShapes.first.length >= 2 &&
              resolvedInputShapes.first[1] > 0
          ? resolvedInputShapes.first[1]
          : contract.inputHeight,
      expectedOutputLength: outputValues.length,
      outputType: runtimeOutputType,
    );

    final rawScore = runtimeContract.readRawScore(outputValues);
    final normalizedScore = runtimeContract.normalizeOutput(outputValues);
    final rawPreview = outputValues
        .take(10)
        .map((value) => value.toStringAsFixed(4))
        .join(', ');

    debugPrint(
      '[TfliteAestheticService] ${contract.id} '
      'rawOutput=[$rawPreview] '
      'rawScore=${rawScore.toStringAsFixed(4)} '
      'normalized=${normalizedScore.toStringAsFixed(4)}',
    );

    return ModelScoreDetail(
      id: runtimeContract.id,
      label: runtimeContract.displayLabel,
      dimension: runtimeContract.dimension,
      rawScore: rawScore,
      normalizedScore: normalizedScore,
      weight: runtimeContract.weight,
      interpretation: runtimeContract.displayInterpretation,
    );
  }

  Future<ModelScoreDetail> _runRgnetPilResizeTensorContract(
    Uint8List imageBytes,
    ResolvedAestheticModelConfig contract, {
    required Interpreter interpreter,
    required TfliteModelDescriptor descriptor,
    required Map<String, Future<Uint8List>> inputCache,
    AcutImagePreprocessBundle? bundle,
  }) async {
    final inputDescriptor = _primaryInputDescriptor(descriptor, contract);
    final outputDescriptor = _primaryOutputDescriptor(descriptor, contract);
    if (inputDescriptor == null || outputDescriptor == null) {
      throw Exception('RGNet model missing input or output tensors');
    }

    final inputShape = inputDescriptor.shape;
    final outputShape = outputDescriptor.shape;
    final inputType = inputDescriptor.type;
    final outputType = outputDescriptor.type;
    const expectedInputShape = [1, 256, 256, 3];
    const expectedOutputShape = [1, 1];
    debugPrint(
      '[AcutPerf] RGNET_TENSORS_CACHED '
      'inputShape=$inputShape inputType=$inputType '
      'outputShape=$outputShape outputType=$outputType',
    );

    if (!listEquals(inputShape, expectedInputShape)) {
      throw Exception(
        'RGNet input shape mismatch. Expected $expectedInputShape, got $inputShape',
      );
    }
    if (!listEquals(outputShape, expectedOutputShape)) {
      throw Exception(
        'RGNet output shape mismatch. Expected $expectedOutputShape, got $outputShape',
      );
    }
    if (inputType.toLowerCase() != 'float32') {
      throw Exception(
        'RGNet input type mismatch. Expected float32, got $inputType',
      );
    }
    if (outputType.toLowerCase() != 'float32') {
      throw Exception(
        'RGNet output type mismatch. Expected float32, got $outputType',
      );
    }

    const inputWidth = 256;
    const inputHeight = 256;
    const expectedBytes = inputWidth * inputHeight * 3 * 4;
    final cacheKey =
        'rgnet_pil_resize:0:$inputWidth:$inputHeight:${contract.normalization.name}:'
        '${contract.inputDtype}:${contract.colorFormat}:${contract.tensorLayout}';

    final preSw = Stopwatch()..start();
    final preprocessed = await inputCache.putIfAbsent(
      cacheKey,
      () =>
          bundle?.rgbFloat32(
            width: inputWidth,
            height: inputHeight,
            normalization: contract.normalization,
          ) ??
          _preprocessor.preprocessToRgbFloat32(
            imageBytes,
            width: inputWidth,
            height: inputHeight,
            normalization: contract.normalization,
          ),
    );
    preSw.stop();
    final pMs = preSw.elapsedMilliseconds;
    AcutPerfMetrics.totalPreprocessMs += pMs;
    debugPrint(
      '[AcutPerf] preprocess_${inputWidth}_ms=$pMs model=${contract.id}',
    );

    if (preprocessed.lengthInBytes != expectedBytes) {
      throw Exception(
        'RGNet input buffer size mismatch. Expected $expectedBytes, got ${preprocessed.lengthInBytes}',
      );
    }

    final output = List.generate(1, (_) => List<double>.filled(1, 0.0));
    debugPrint(
      '[AcutPerf] rgnet_output_alloc model=${contract.id} '
      'outputShape=$outputShape outputType=$outputType '
      'outputBufferType=${output.runtimeType}',
    );

    final inferSw = Stopwatch()..start();
    interpreter.run(preprocessed, output);
    inferSw.stop();
    final iMs = inferSw.elapsedMilliseconds;
    AcutPerfMetrics.totalInferenceMs += iMs;
    AcutPerfMetrics.totalRgnetMs += pMs + iMs;

    final rawValue = output.first.first;
    final outputValues = Float32List.fromList([rawValue]);
    final rawScore = contract.readRawScore(outputValues);
    final normalizedScore = contract.normalizeOutput(outputValues);

    debugPrint('[AcutPerf] model_inference_only_ms=$iMs model=${contract.id}');
    debugPrint(
      '[AcutPerf] model_total_with_preprocess_ms=${pMs + iMs} model=${contract.id}',
    );
    debugPrint(
      '[TfliteAestheticService] ${contract.id} '
      'outputBufferType=${output.runtimeType} '
      'rawOutput=[${rawValue.toStringAsFixed(4)}] '
      'rawScore=${rawScore.toStringAsFixed(4)} '
      'normalized=${normalizedScore.toStringAsFixed(4)}',
    );

    return ModelScoreDetail(
      id: contract.id,
      label: contract.displayLabel,
      dimension: contract.dimension,
      rawScore: rawScore,
      normalizedScore: normalizedScore,
      weight: contract.weight,
      interpretation: contract.displayInterpretation,
    );
  }

  TfliteTensorDescriptor? _primaryInputDescriptor(
    TfliteModelDescriptor descriptor,
    ResolvedAestheticModelConfig contract,
  ) {
    if (descriptor.inputTensors.isEmpty) {
      debugPrint(
        '[AcutPerf] cached_input_descriptor_missing model=${contract.id} '
        'assetPath=${descriptor.assetPath}',
      );
      return null;
    }
    return descriptor.inputTensors.first;
  }

  TfliteTensorDescriptor? _primaryOutputDescriptor(
    TfliteModelDescriptor descriptor,
    ResolvedAestheticModelConfig contract,
  ) {
    if (descriptor.outputTensors.isEmpty) {
      debugPrint(
        '[AcutPerf] cached_output_descriptor_missing model=${contract.id} '
        'assetPath=${descriptor.assetPath}',
      );
      return null;
    }
    return descriptor.outputTensors.first;
  }

  bool _isFloat32Type(String? type) {
    return type?.toLowerCase() == 'float32';
  }

  List<int> _sanitizeRgbInputShape(
    List<int> shape,
    ResolvedAestheticModelConfig contract,
  ) {
    if (shape.length != 4) {
      return [1, contract.inputHeight, contract.inputWidth, 3];
    }
    final batch = shape[0] <= 0 ? 1 : shape[0];
    final height = shape[1] <= 0 ? contract.inputHeight : shape[1];
    final width = shape[2] <= 0 ? contract.inputWidth : shape[2];
    final channels = shape[3] <= 0 ? 3 : shape[3];
    return [batch, height, width, channels];
  }

  List<int> _sanitizeNimaInputShape(List<int>? shape) {
    if (shape == null || shape.length != 4) {
      return const [1, 224, 224, 3];
    }
    final batch = shape[0] <= 0 ? 1 : shape[0];
    final height = shape[1] <= 0 ? 224 : shape[1];
    final width = shape[2] <= 0 ? 224 : shape[2];
    final channels = shape[3] <= 0 ? 3 : shape[3];
    return [batch, height, width, channels];
  }

  List<int> _sanitizeNimaOutputShape(List<int>? shape) {
    if (shape == null || shape.length != 2) {
      return const [1, 10];
    }
    final batch = shape[0] <= 0 ? 1 : shape[0];
    final bins = shape[1] <= 0 ? 10 : shape[1];
    return [batch, bins];
  }

  Future<Uint8List> _preprocessTensorInput(
    Uint8List imageBytes, {
    required int width,
    required int height,
    required ImageNormalization normalization,
    required AestheticModelResizeMode resizeMode,
    required AcutImagePreprocessBundle? bundle,
  }) {
    switch (resizeMode) {
      case AestheticModelResizeMode.resize:
        return bundle?.rgbFloat32(
              width: width,
              height: height,
              normalization: normalization,
            ) ??
            _preprocessor.preprocessToRgbFloat32(
              imageBytes,
              width: width,
              height: height,
              normalization: normalization,
            );
      case AestheticModelResizeMode.resizeWithPad:
        return bundle?.resizeWithPadRgbFloat32(
              width: width,
              height: height,
              normalization: normalization,
            ) ??
            _preprocessor.preprocessResizeWithPadToRgbFloat32(
              imageBytes,
              width: width,
              height: height,
              normalization: normalization,
            );
    }
  }

  List<double> _extractNimaProbabilities(dynamic output) {
    if (output == null) {
      debugPrint('[AcutPerf] NIMA_OUTPUT_EMPTY');
      throw Exception('NIMA_OUTPUT_EMPTY');
    }

    if (output is List) {
      if (output.isEmpty) {
        debugPrint('[AcutPerf] NIMA_OUTPUT_EMPTY');
        throw Exception('NIMA_OUTPUT_EMPTY');
      }
      final first = output[0];
      if (first == null) {
        debugPrint('[AcutPerf] NIMA_OUTPUT_ROW_EMPTY');
        throw Exception('NIMA_OUTPUT_ROW_EMPTY');
      }
      if (first is List) {
        if (first.isEmpty) {
          debugPrint('[AcutPerf] NIMA_OUTPUT_ROW_EMPTY');
          throw Exception('NIMA_OUTPUT_ROW_EMPTY');
        }
        if (first.length != 10) {
          debugPrint(
            '[AcutPerf] NIMA_OUTPUT_LENGTH_MISMATCH len=${first.length}',
          );
          throw Exception('NIMA_OUTPUT_LENGTH_MISMATCH len=${first.length}');
        }
        return first.map((e) => (e as num).toDouble()).toList();
      } else if (first is num) {
        if (output.length != 10) {
          debugPrint(
            '[AcutPerf] NIMA_OUTPUT_LENGTH_MISMATCH len=${output.length}',
          );
          throw Exception('NIMA_OUTPUT_LENGTH_MISMATCH len=${output.length}');
        }
        return output.map((e) => (e as num).toDouble()).toList();
      }
    }

    debugPrint(
      '[AcutPerf] NIMA_OUTPUT_UNEXPECTED_TYPE type=${output.runtimeType}',
    );
    throw Exception('NIMA_OUTPUT_UNEXPECTED_TYPE type=${output.runtimeType}');
  }

  ModelScoreDetail _parseNimaDistribution10(
    ResolvedAestheticModelConfig contract,
    List<double> outputValues,
  ) {
    if (outputValues.length != 10) {
      debugPrint(
        '[AcutPerf] NIMA_ONLY_ERROR error=unexpected_output_length '
        'length=${outputValues.length}',
      );
      throw Exception('nima_unexpected_output_length:${outputValues.length}');
    }

    var rawScore = 0.0;
    var distributionSum = 0.0;
    for (var index = 0; index < outputValues.length; index++) {
      distributionSum += outputValues[index];
      rawScore += outputValues[index] * (index + 1);
    }
    final normalized = ((rawScore - 1.0) / 9.0).clamp(0.0, 1.0).toDouble();
    final probs = outputValues
        .map((value) => value.toStringAsFixed(4))
        .join(', ');

    debugPrint('[AcutPerf] NIMA_ONLY_OUTPUT probs=[$probs]');
    debugPrint(
      '[AcutPerf] NIMA_ONLY_SCORE distributionSum=$distributionSum '
      'rawScore=$rawScore normalized=$normalized',
    );
    debugPrint(
      '[AcutPerf] nima_summary ok=true path=${contract.assetPath} outputMode=distribution_10 normalized=$normalized error=null',
    );
    if (ExperimentalFeatures.verboseModelLogs) {
      debugPrint('[AcutPerf] NIMA_ONLY_OUTPUT probs=[$probs]');
      debugPrint(
        '[AcutPerf] NIMA_ONLY_SCORE distributionSum=$distributionSum '
        'rawScore=$rawScore normalized=$normalized',
      );
      debugPrint(
        '[AcutPerf] nima_summary ok=true path=${contract.assetPath} outputMode=distribution_10 normalized=$normalized error=null',
      );
    }

    return ModelScoreDetail(
      id: contract.id,
      label: contract.displayLabel,
      dimension: contract.dimension,
      rawScore: rawScore,
      normalizedScore: normalized,
      weight: contract.weight,
      interpretation: 'NIMA 10-bin distribution mean -> [0,1]',
    );
  }

  Future<ModelScoreDetail> _runSignatureContract(
    Uint8List imageBytes,
    ResolvedAestheticModelConfig contract, {
    required Interpreter interpreter,
    required TfliteModelDescriptor descriptor,
    required Map<String, Future<Uint8List>> inputCache,
    AcutImagePreprocessBundle? bundle,
  }) async {
    if (descriptor.signatures.isEmpty) {
      throw Exception('No signature runners found for ${contract.id}.');
    }

    final signatureKey =
        contract.signatureKey ?? descriptor.signatureKeys.first;
    final signatureDescriptor = descriptor.signatures[signatureKey];
    if (signatureDescriptor == null) {
      throw Exception(
        'Signature "$signatureKey" was not found for ${contract.id}. '
        'Available signatures: ${descriptor.signatureKeys.join(', ')}',
      );
    }

    final runner = interpreter.getSignatureRunner(signatureKey);
    try {
      final inputNames = signatureDescriptor.inputNames;
      final outputNames = signatureDescriptor.outputNames;
      if (inputNames.isEmpty || outputNames.isEmpty) {
        throw Exception(
          'Signature "$signatureKey" is missing inputs or outputs '
          'for ${contract.id}.',
        );
      }

      final preparedInputs = await _prepareSignatureInputs(
        imageBytes,
        contract,
        signature: signatureDescriptor,
        inputNames: inputNames,
        inputCache: inputCache,
        bundle: bundle,
      );

      debugPrint(
        '[TfliteAestheticService] ${contract.id} '
        'signature=$signatureKey '
        'inputNames=${inputNames.join(', ')} '
        'outputNames=${outputNames.join(', ')}',
      );
      debugPrint(
        '[TfliteAestheticService] ${contract.id} '
        'signatureInputs=${preparedInputs.debugDescriptions.join(', ')}',
      );

      final outputName = outputNames.first;
      final outputDescriptor = signatureDescriptor.output(outputName);
      final outputElementCount = math.max(
        1,
        outputDescriptor.elementCount > 0
            ? outputDescriptor.elementCount
            : contract.expectedOutputLength,
      );
      final outputBuffer = Uint8List(outputElementCount * 4).buffer;

      final inferSw = Stopwatch()..start();
      runner.run(
        {
          for (final entry in preparedInputs.buffers.entries)
            entry.key: entry.value,
        },
        {outputName: outputBuffer},
      );
      inferSw.stop();

      final iMs = inferSw.elapsedMilliseconds;
      AcutPerfMetrics.totalInferenceMs += iMs;
      debugPrint(
        '[AcutPerf] model_inference_only_ms=$iMs model=${contract.id}',
      );
      final totalMs = preparedInputs.preprocessMs + iMs;
      debugPrint(
        '[AcutPerf] model_total_with_preprocess_ms=$totalMs model=${contract.id}',
      );
      if (contract.id == 'mobile_alamp_v2') {
        AcutPerfMetrics.totalAlampMs += totalMs;
      }

      final outputValues = outputBuffer.asFloat32List(0, outputElementCount);
      final runtimeOutputType = _resolveRuntimeOutputType(
        contract.outputType,
        outputValues.length,
      );
      final runtimeContract = contract.withRuntimeOverrides(
        inputWidth: preparedInputs.inputWidth,
        inputHeight: preparedInputs.inputHeight,
        expectedOutputLength: outputValues.length,
        outputType: runtimeOutputType,
      );

      final rawScore = runtimeContract.readRawScore(outputValues);
      final normalizedScore = runtimeContract.normalizeOutput(outputValues);
      final rawPreview = outputValues
          .take(10)
          .map((value) => value.toStringAsFixed(4))
          .join(', ');

      debugPrint(
        '[TfliteAestheticService] ${contract.id} '
        'outputBytes=${outputDescriptor.byteCount} '
        'rawOutput=[$rawPreview] '
        'rawScore=${rawScore.toStringAsFixed(4)} '
        'normalized=${normalizedScore.toStringAsFixed(4)}',
      );

      return ModelScoreDetail(
        id: runtimeContract.id,
        label: runtimeContract.displayLabel,
        dimension: runtimeContract.dimension,
        rawScore: rawScore,
        normalizedScore: normalizedScore,
        weight: runtimeContract.weight,
        interpretation:
            '${runtimeContract.displayInterpretation} '
            '(signature=$signatureKey)',
      );
    } finally {
      runner.close();
    }
  }

  Future<_SignatureInputBundle> _prepareSignatureInputs(
    Uint8List imageBytes,
    ResolvedAestheticModelConfig contract, {
    required TfliteSignatureDescriptor signature,
    required List<String> inputNames,
    required Map<String, Future<Uint8List>> inputCache,
    AcutImagePreprocessBundle? bundle,
  }) async {
    switch (contract.id) {
      case 'mobile_alamp_v2':
        return _prepareAlampInputs(
          imageBytes,
          contract,
          signature: signature,
          inputNames: inputNames,
          inputCache: inputCache,
          bundle: bundle,
        );
    }

    throw Exception(
      'Signature execution is not configured for ${contract.id}.',
    );
  }

  Future<_SignatureInputBundle> _prepareAlampInputs(
    Uint8List imageBytes,
    ResolvedAestheticModelConfig contract, {
    required TfliteSignatureDescriptor signature,
    required List<String> inputNames,
    required Map<String, Future<Uint8List>> inputCache,
    AcutImagePreprocessBundle? bundle,
  }) async {
    final patchInputName = _findInputName(
      inputNames,
      contains: 'patch',
      fallback: inputNames.length > 1 ? inputNames[1] : inputNames.first,
    );
    final globalInputName = _findInputNameByAny(
      inputNames,
      containsAny: const ['full', 'global', 'image'],
      fallback: inputNames.first,
      exclude: {patchInputName},
    );

    if (globalInputName == patchInputName) {
      throw Exception(
        'A-Lamp requires separate global_view and patches inputs. '
        'Found: ${inputNames.join(', ')}',
      );
    }

    final globalSide =
        _deriveSquareRgbInputSize(signature.input(globalInputName).byteCount) ??
        contract.inputWidth;
    final patchSpec = _inferPatchInputSpec(
      signature.input(patchInputName).byteCount,
      preferredPatchSide: globalSide,
    );

    final globalCacheKey =
        'signature:alamp_global:$globalInputName:$globalSide:$globalSide:${contract.normalization.name}';
    final patchesCacheKey =
        'signature:alamp_adaptive:$patchInputName:${patchSpec.patchWidth}:${patchSpec.patchHeight}:'
        '${patchSpec.patchCount}:${contract.normalization.name}';

    final preSw = Stopwatch()..start();
    final globalBuffer = await inputCache.putIfAbsent(
      globalCacheKey,
      () => contract.id == 'mobile_alamp_v2'
          ? bundle?.rgbFloat32(
                  width: globalSide,
                  height: globalSide,
                  normalization: contract.normalization,
                ) ??
                _preprocessor.preprocessToRgbFloat32(
                  imageBytes,
                  width: globalSide,
                  height: globalSide,
                  normalization: contract.normalization,
                )
          : bundle?.alampGlobalViewFloat32(
                  width: globalSide,
                  height: globalSide,
                  normalization: contract.normalization,
                ) ??
                _preprocessor.preprocessAlampGlobalViewFloat32(
                  imageBytes,
                  width: globalSide,
                  height: globalSide,
                  normalization: contract.normalization,
                ),
    );
    final patchBuffer = await inputCache.putIfAbsent(
      patchesCacheKey,
      () =>
          bundle?.alampAdaptivePatchesFloat32(
            patchWidth: patchSpec.patchWidth,
            patchHeight: patchSpec.patchHeight,
            patchCount: patchSpec.patchCount,
            normalization: contract.normalization,
          ) ??
          _preprocessor.preprocessAlampAdaptivePatchesFloat32(
            imageBytes,
            patchWidth: patchSpec.patchWidth,
            patchHeight: patchSpec.patchHeight,
            patchCount: patchSpec.patchCount,
            normalization: contract.normalization,
          ),
    );
    preSw.stop();
    final pMs = preSw.elapsedMilliseconds;
    AcutPerfMetrics.totalPreprocessMs += pMs;
    debugPrint(
      '[AcutPerf] preprocess_alamp_signature_ms=$pMs model=${contract.id} '
      'global=${globalSide}x$globalSide patches=${patchSpec.patchCount}x'
      '${patchSpec.patchWidth}x${patchSpec.patchHeight}',
    );
    debugPrint(
      '[AcutPerf] alamp_input_bytes global=${globalBuffer.lengthInBytes} '
      'patches=${patchBuffer.lengthInBytes}',
    );

    return _SignatureInputBundle(
      buffers: {globalInputName: globalBuffer, patchInputName: patchBuffer},
      debugDescriptions: [
        '$globalInputName=[1, $globalSide, $globalSide, 3]',
        '$patchInputName='
            '[1, ${patchSpec.patchCount}, ${patchSpec.patchHeight}, ${patchSpec.patchWidth}, 3]',
      ],
      inputWidth: globalSide,
      inputHeight: globalSide,
      preprocessMs: pMs,
    );
  }

  String _findInputName(
    List<String> inputNames, {
    required String contains,
    required String fallback,
  }) {
    final lowered = contains.toLowerCase();
    for (final inputName in inputNames) {
      if (inputName.toLowerCase().contains(lowered)) {
        return inputName;
      }
    }
    return fallback;
  }

  String _findInputNameByAny(
    List<String> inputNames, {
    required List<String> containsAny,
    required String fallback,
    Set<String> exclude = const {},
  }) {
    for (final fragment in containsAny) {
      final lowered = fragment.toLowerCase();
      for (final inputName in inputNames) {
        if (exclude.contains(inputName)) {
          continue;
        }
        if (inputName.toLowerCase().contains(lowered)) {
          return inputName;
        }
      }
    }
    if (!exclude.contains(fallback)) {
      return fallback;
    }
    for (final inputName in inputNames) {
      if (!exclude.contains(inputName)) {
        return inputName;
      }
    }
    return fallback;
  }

  int? _deriveSquareRgbInputSize(int byteCount) {
    if (byteCount <= 0 || byteCount % (3 * 4) != 0) {
      return null;
    }

    final pixelCount = byteCount ~/ (3 * 4);
    final side = math.sqrt(pixelCount).round();
    if (side * side == pixelCount) {
      return side;
    }
    return null;
  }

  _PatchInputSpec _inferPatchInputSpec(
    int byteCount, {
    required int preferredPatchSide,
  }) {
    final candidateSides = <int>{
      preferredPatchSide,
      256,
      224,
      192,
      160,
      128,
      112,
      96,
      84,
      80,
      75,
      64,
    };

    for (final side in candidateSides) {
      if (side <= 0) {
        continue;
      }

      final bytesPerPatch = side * side * 3 * 4;
      if (bytesPerPatch <= 0 || byteCount % bytesPerPatch != 0) {
        continue;
      }

      final patchCount = byteCount ~/ bytesPerPatch;
      if (patchCount >= 1 && patchCount <= 32) {
        return _PatchInputSpec(
          patchWidth: side,
          patchHeight: side,
          patchCount: patchCount,
        );
      }
    }

    throw Exception(
      'Unable to infer A-Lamp patch input layout from $byteCount bytes.',
    );
  }

  AestheticModelOutputType _resolveRuntimeOutputType(
    AestheticModelOutputType fallback,
    int outputLength,
  ) {
    if (outputLength == 10) {
      return AestheticModelOutputType.distribution;
    }
    return fallback;
  }

  bool _isModelDisabledForBatch(
    ResolvedAestheticModelConfig contract,
    int? imageIndex,
  ) {
    if (imageIndex == null) {
      return false;
    }

    final disabled = switch (contract.id) {
      'koniq_mobile' => ExperimentalFeatures.disableKoniqDuringBatchScoring,
      'flive_image_mobile' =>
        ExperimentalFeatures.disableFliveDuringBatchScoring,
      'nima_mobile' ||
      'icaa_color_aesthetic' ||
      'mobile_alamp_v2' ||
      'rgnet_pil_resize_aadb' => false,
      _ => false,
    };

    if (disabled) {
      debugPrint(
        '[AcutPerf] model_skipped image_index=$imageIndex '
        'model=${contract.id} reason=debug_flag',
      );
    }
    return disabled;
  }

  ModelScoreDetail _debugFallbackDetail(ResolvedAestheticModelConfig contract) {
    return ModelScoreDetail(
      id: '${contract.id}_debug_skipped',
      label: '${contract.displayLabel} (debug skipped)',
      dimension: contract.dimension,
      rawScore: 0.5,
      normalizedScore: 0.5,
      weight: contract.weight,
      interpretation:
          '${contract.displayInterpretation} (debug fallback because model was skipped)',
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
}

class _SignatureInputBundle {
  final Map<String, Uint8List> buffers;
  final List<String> debugDescriptions;
  final int inputWidth;
  final int inputHeight;
  final int preprocessMs;

  const _SignatureInputBundle({
    required this.buffers,
    required this.debugDescriptions,
    required this.inputWidth,
    required this.inputHeight,
    required this.preprocessMs,
  });
}

class _PatchInputSpec {
  final int patchWidth;
  final int patchHeight;
  final int patchCount;

  const _PatchInputSpec({
    required this.patchWidth,
    required this.patchHeight,
    required this.patchCount,
  });
}
