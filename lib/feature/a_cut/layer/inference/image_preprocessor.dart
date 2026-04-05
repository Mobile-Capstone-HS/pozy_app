import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum ImageNormalization { zeroToOne, minusOneToOne }

class ImagePreprocessor {
  const ImagePreprocessor();

  Future<Uint8List> preprocessToRgbFloat32(
    Uint8List imageBytes, {
    required int width,
    required int height,
    ImageNormalization normalization = ImageNormalization.zeroToOne,
  }) {
    return compute(
      _preprocessToRgbFloat32,
      _PreprocessRequest(
        imageBytes: imageBytes,
        width: width,
        height: height,
        normalization: normalization,
      ),
    );
  }
}

class _PreprocessRequest {
  final Uint8List imageBytes;
  final int width;
  final int height;
  final ImageNormalization normalization;

  const _PreprocessRequest({
    required this.imageBytes,
    required this.width,
    required this.height,
    required this.normalization,
  });
}

Uint8List _preprocessToRgbFloat32(_PreprocessRequest request) {
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) {
    throw Exception('Cannot decode image bytes.');
  }

  final resized = img.copyResize(
    decoded,
    width: request.width,
    height: request.height,
    interpolation: img.Interpolation.linear,
  );

  final output = Float32List(request.width * request.height * 3);
  var cursor = 0;

  for (var y = 0; y < request.height; y++) {
    for (var x = 0; x < request.width; x++) {
      final pixel = resized.getPixel(x, y);
      output[cursor++] = _normalize(pixel.r, request.normalization);
      output[cursor++] = _normalize(pixel.g, request.normalization);
      output[cursor++] = _normalize(pixel.b, request.normalization);
    }
  }

  return output.buffer.asUint8List();
}

double _normalize(num channel, ImageNormalization normalization) {
  switch (normalization) {
    case ImageNormalization.zeroToOne:
      return channel / 255.0;
    case ImageNormalization.minusOneToOne:
      return (channel / 127.5) - 1.0;
  }
}
