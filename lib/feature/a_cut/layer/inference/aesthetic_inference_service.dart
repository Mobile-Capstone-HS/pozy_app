import 'dart:typed_data';

import 'image_preprocessor.dart';
import 'tflite_interpreter_manager.dart';

class InferenceOutput {
  final List<double> distribution;

  const InferenceOutput({required this.distribution});

  double get meanScore {
    var score = 0.0;
    for (var i = 0; i < distribution.length; i++) {
      score += (i + 1) * distribution[i];
    }
    return score;
  }
}

abstract class PhotoInferenceService {
  Future<InferenceOutput> run(Uint8List imageBytes);
}

class NimaAestheticInferenceService implements PhotoInferenceService {
  NimaAestheticInferenceService({
    required this.modelAssetPath,
    TfliteInterpreterManager? interpreterManager,
    ImagePreprocessor? preprocessor,
  }) : _interpreterManager =
           interpreterManager ?? TfliteInterpreterManager.instance,
       _preprocessor = preprocessor ?? const ImagePreprocessor();

  final String modelAssetPath;
  final TfliteInterpreterManager _interpreterManager;
  final ImagePreprocessor _preprocessor;

  @override
  Future<InferenceOutput> run(Uint8List imageBytes) async {
    final interpreter = await _interpreterManager.getInterpreter(
      modelAssetPath,
      useFlexDelegate: true,
    );

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);

    final inputShape = inputTensor.shape;
    if (inputShape.length != 4) {
      throw Exception('Unexpected input shape: $inputShape');
    }

    final inputHeight = inputShape[1];
    final inputWidth = inputShape[2];

    final preprocessedBytes = await _preprocessor.preprocessToNimaInput(
      imageBytes,
      width: inputWidth,
      height: inputHeight,
    );

    final outputByteLength = outputTensor.numElements() * 4;
    final outputBytes = Uint8List(outputByteLength);

    interpreter.run(preprocessedBytes, outputBytes.buffer);

    final outputFloats = outputBytes.buffer.asFloat32List();
    if (outputFloats.length < 10) {
      throw Exception(
        'Model output is smaller than 10 bins: ${outputFloats.length}',
      );
    }

    return InferenceOutput(
      distribution: List<double>.generate(10, (index) => outputFloats[index]),
    );
  }
}
