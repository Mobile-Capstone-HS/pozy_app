import 'dart:math' as math;

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

  Future<Uint8List> preprocessPatchBatchToRgbFloat32(
    Uint8List imageBytes, {
    required int patchWidth,
    required int patchHeight,
    required int patchCount,
    ImageNormalization normalization = ImageNormalization.zeroToOne,
  }) {
    return compute(
      _preprocessPatchBatchToRgbFloat32,
      _PatchBatchPreprocessRequest(
        imageBytes: imageBytes,
        patchWidth: patchWidth,
        patchHeight: patchHeight,
        patchCount: patchCount,
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

class _PatchBatchPreprocessRequest {
  final Uint8List imageBytes;
  final int patchWidth;
  final int patchHeight;
  final int patchCount;
  final ImageNormalization normalization;

  const _PatchBatchPreprocessRequest({
    required this.imageBytes,
    required this.patchWidth,
    required this.patchHeight,
    required this.patchCount,
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

Uint8List _preprocessPatchBatchToRgbFloat32(
  _PatchBatchPreprocessRequest request,
) {
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) {
    throw Exception('Cannot decode image bytes.');
  }

  final patchCount = request.patchCount < 1 ? 1 : request.patchCount;
  final cropSide = math.max(
    1,
    (math.min(decoded.width, decoded.height) * 0.6).round(),
  );
  final anchors = _buildPatchAnchors(patchCount);
  final output = Float32List(
    patchCount * request.patchWidth * request.patchHeight * 3,
  );
  var cursor = 0;

  for (final anchor in anchors) {
    final cropX = (((decoded.width - cropSide) * anchor.dx).round())
        .clamp(0, math.max(0, decoded.width - cropSide))
        .toInt();
    final cropY = (((decoded.height - cropSide) * anchor.dy).round())
        .clamp(0, math.max(0, decoded.height - cropSide))
        .toInt();

    final cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: math.min(cropSide, decoded.width),
      height: math.min(cropSide, decoded.height),
    );
    final resized = img.copyResize(
      cropped,
      width: request.patchWidth,
      height: request.patchHeight,
      interpolation: img.Interpolation.linear,
    );

    for (var y = 0; y < request.patchHeight; y++) {
      for (var x = 0; x < request.patchWidth; x++) {
        final pixel = resized.getPixel(x, y);
        output[cursor++] = _normalize(pixel.r, request.normalization);
        output[cursor++] = _normalize(pixel.g, request.normalization);
        output[cursor++] = _normalize(pixel.b, request.normalization);
      }
    }
  }

  return output.buffer.asUint8List();
}

List<_Anchor> _buildPatchAnchors(int patchCount) {
  const canonical = <_Anchor>[
    _Anchor(0.0, 0.0),
    _Anchor(1.0, 0.0),
    _Anchor(0.5, 0.5),
    _Anchor(0.0, 1.0),
    _Anchor(1.0, 1.0),
    _Anchor(0.5, 0.0),
    _Anchor(0.0, 0.5),
    _Anchor(1.0, 0.5),
    _Anchor(0.5, 1.0),
  ];

  if (patchCount <= canonical.length) {
    return canonical.take(patchCount).toList(growable: false);
  }

  final anchors = canonical.toList(growable: true);
  while (anchors.length < patchCount) {
    anchors.add(const _Anchor(0.5, 0.5));
  }
  return anchors;
}

class _Anchor {
  final double dx;
  final double dy;

  const _Anchor(this.dx, this.dy);
}

double _normalize(num channel, ImageNormalization normalization) {
  switch (normalization) {
    case ImageNormalization.zeroToOne:
      return channel / 255.0;
    case ImageNormalization.minusOneToOne:
      return (channel / 127.5) - 1.0;
  }
}
