import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImagePreprocessor {
  const ImagePreprocessor();

  Future<Uint8List> preprocessToNimaInput(
    Uint8List imageBytes, {
    required int width,
    required int height,
  }) {
    return compute(
      _preprocessForNima,
      _PreprocessRequest(imageBytes: imageBytes, width: width, height: height),
    );
  }
}

class _PreprocessRequest {
  final Uint8List imageBytes;
  final int width;
  final int height;

  const _PreprocessRequest({
    required this.imageBytes,
    required this.width,
    required this.height,
  });
}

Uint8List _preprocessForNima(_PreprocessRequest request) {
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) {
    throw Exception('Cannot decode image bytes.');
  }

  final resized = img.copyResize(
    decoded,
    width: request.width,
    height: request.height,
    interpolation: img.Interpolation.average,
  );

  final total = request.width * request.height * 3;
  final output = Float32List(total);

  var cursor = 0;
  for (var y = 0; y < request.height; y++) {
    for (var x = 0; x < request.width; x++) {
      final pixel = resized.getPixel(x, y);
      output[cursor++] = (pixel.r / 127.5) - 1.0;
      output[cursor++] = (pixel.g / 127.5) - 1.0;
      output[cursor++] = (pixel.b / 127.5) - 1.0;
    }
  }

  return output.buffer.asUint8List();
}
