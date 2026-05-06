import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'acut_perf.dart';

enum ImageNormalization { zeroToOne, minusOneToOne }

class ImagePreprocessor {
  const ImagePreprocessor();

  Future<AcutImagePreprocessBundle> createBundle(Uint8List imageBytes) async {
    final sw = Stopwatch()..start();
    final decoded = img.decodeImage(imageBytes);
    sw.stop();
    if (decoded == null) {
      throw Exception('Cannot decode image bytes.');
    }
    final bundle = AcutImagePreprocessBundle._(
      sourceBytes: imageBytes,
      decoded: decoded,
      sourceWidth: decoded.width,
      sourceHeight: decoded.height,
      decodeMs: sw.elapsedMilliseconds,
    );
    AcutPerfCollector.recordPreprocess(sw.elapsedMilliseconds);
    debugPrint(
      '[AcutPerf] preprocess_decode_ms=${sw.elapsedMilliseconds} '
      'source=${decoded.width}x${decoded.height}',
    );
    return bundle;
  }

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

class AcutImagePreprocessBundle {
  final Uint8List sourceBytes;
  final img.Image decoded;
  final int sourceWidth;
  final int sourceHeight;
  final int decodeMs;

  final Map<String, Uint8List> _tensorCache = <String, Uint8List>{};
  final Map<String, int> _timings = <String, int>{};

  AcutImagePreprocessBundle._({
    required this.sourceBytes,
    required this.decoded,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.decodeMs,
  }) {
    _timings['decode'] = decodeMs;
  }

  int get preprocessTotalMs =>
      _timings.values.fold<int>(0, (sum, value) => sum + value);

  Future<Uint8List> rgbFloat32({
    required int width,
    required int height,
    ImageNormalization normalization = ImageNormalization.zeroToOne,
  }) async {
    final key = 'rgb_${width}x$height:${normalization.name}';
    final existing = _tensorCache[key];
    if (existing != null) {
      return existing;
    }

    final sw = Stopwatch()..start();
    final buffer = _preprocessDecodedToRgbFloat32(
      decoded,
      width: width,
      height: height,
      normalization: normalization,
    );
    sw.stop();
    _tensorCache[key] = buffer;
    _recordTiming('rgb_$width', sw.elapsedMilliseconds);
    debugPrint('[AcutPerf] preprocess_${width}_ms=${sw.elapsedMilliseconds}');
    return buffer;
  }

  Future<Uint8List> alampPatchesFloat32({
    required int patchWidth,
    required int patchHeight,
    required int patchCount,
    ImageNormalization normalization = ImageNormalization.zeroToOne,
  }) async {
    final key =
        'alamp_patches_${patchWidth}x$patchHeight:$patchCount:${normalization.name}';
    final existing = _tensorCache[key];
    if (existing != null) {
      return existing;
    }

    final sw = Stopwatch()..start();
    final buffer = _preprocessDecodedPatchBatchToRgbFloat32(
      decoded,
      patchWidth: patchWidth,
      patchHeight: patchHeight,
      patchCount: patchCount,
      normalization: normalization,
    );
    sw.stop();
    _tensorCache[key] = buffer;
    _recordTiming('alamp_patches', sw.elapsedMilliseconds);
    debugPrint(
      '[AcutPerf] preprocess_alamp_patches_ms=${sw.elapsedMilliseconds}',
    );
    return buffer;
  }

  void logTotal() {
    debugPrint('[AcutPerf] preprocess_total_ms=$preprocessTotalMs');
  }

  void _recordTiming(String key, int ms) {
    _timings[key] = (_timings[key] ?? 0) + ms;
    AcutPerfCollector.recordPreprocess(ms);
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

  return _preprocessDecodedToRgbFloat32(
    decoded,
    width: request.width,
    height: request.height,
    normalization: request.normalization,
  );
}

Uint8List _preprocessDecodedToRgbFloat32(
  img.Image decoded, {
  required int width,
  required int height,
  required ImageNormalization normalization,
}) {
  final resized = img.copyResize(
    decoded,
    width: width,
    height: height,
    interpolation: img.Interpolation.linear,
  );

  final output = Float32List(width * height * 3);
  var cursor = 0;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = resized.getPixel(x, y);
      output[cursor++] = _normalize(pixel.r, normalization);
      output[cursor++] = _normalize(pixel.g, normalization);
      output[cursor++] = _normalize(pixel.b, normalization);
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

  return _preprocessDecodedPatchBatchToRgbFloat32(
    decoded,
    patchWidth: request.patchWidth,
    patchHeight: request.patchHeight,
    patchCount: request.patchCount,
    normalization: request.normalization,
  );
}

Uint8List _preprocessDecodedPatchBatchToRgbFloat32(
  img.Image decoded, {
  required int patchWidth,
  required int patchHeight,
  required int patchCount,
  required ImageNormalization normalization,
}) {
  final safePatchCount = patchCount < 1 ? 1 : patchCount;
  final cropSide = math.max(
    1,
    (math.min(decoded.width, decoded.height) * 0.6).round(),
  );
  final anchors = _buildPatchAnchors(safePatchCount);
  final output = Float32List(safePatchCount * patchWidth * patchHeight * 3);
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
      width: patchWidth,
      height: patchHeight,
      interpolation: img.Interpolation.linear,
    );

    for (var y = 0; y < patchHeight; y++) {
      for (var x = 0; x < patchWidth; x++) {
        final pixel = resized.getPixel(x, y);
        output[cursor++] = _normalize(pixel.r, normalization);
        output[cursor++] = _normalize(pixel.g, normalization);
        output[cursor++] = _normalize(pixel.b, normalization);
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
