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

  Future<Uint8List> preprocessAlampGlobalViewFloat32(
    Uint8List imageBytes, {
    required int width,
    required int height,
    ImageNormalization normalization = ImageNormalization.zeroToOne,
  }) {
    return compute(
      _preprocessAlampGlobalViewFloat32,
      _PreprocessRequest(
        imageBytes: imageBytes,
        width: width,
        height: height,
        normalization: normalization,
      ),
    );
  }

  Future<Uint8List> preprocessAlampAdaptivePatchesFloat32(
    Uint8List imageBytes, {
    required int patchWidth,
    required int patchHeight,
    required int patchCount,
    ImageNormalization normalization = ImageNormalization.zeroToOne,
  }) {
    return compute(
      _preprocessAlampAdaptivePatchesFloat32,
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

  Future<Uint8List> alampGlobalViewFloat32({
    required int width,
    required int height,
    ImageNormalization normalization = ImageNormalization.zeroToOne,
  }) async {
    final key = 'alamp_global_${width}x$height:${normalization.name}';
    final existing = _tensorCache[key];
    if (existing != null) {
      return existing;
    }

    final sw = Stopwatch()..start();
    final buffer = _preprocessDecodedAlampGlobalViewFloat32(
      decoded,
      width: width,
      height: height,
      normalization: normalization,
    );
    sw.stop();
    _tensorCache[key] = buffer;
    _recordTiming('alamp_global_$width', sw.elapsedMilliseconds);
    debugPrint(
      '[AcutPerf] preprocess_alamp_global_ms=${sw.elapsedMilliseconds} '
      'source=${decoded.width}x${decoded.height} target=${width}x$height',
    );
    return buffer;
  }

  Future<Uint8List> alampAdaptivePatchesFloat32({
    required int patchWidth,
    required int patchHeight,
    required int patchCount,
    ImageNormalization normalization = ImageNormalization.zeroToOne,
  }) async {
    final key =
        'alamp_adaptive_patches_${patchWidth}x$patchHeight:$patchCount:${normalization.name}';
    final existing = _tensorCache[key];
    if (existing != null) {
      return existing;
    }

    final sw = Stopwatch()..start();
    final selection = _selectAlampAdaptivePatchBoxes(decoded, patchCount);
    final buffer = _preprocessDecodedPatchBoxesToRgbFloat32(
      decoded,
      boxes: selection.boxes,
      patchWidth: patchWidth,
      patchHeight: patchHeight,
      normalization: normalization,
    );
    sw.stop();
    _tensorCache[key] = buffer;
    _recordTiming('alamp_adaptive_patches', sw.elapsedMilliseconds);
    debugPrint(
      '[AcutPerf] preprocess_alamp_adaptive_patches_ms=${sw.elapsedMilliseconds} '
      'patch_count=$patchCount boxes=${selection.debugLabel}',
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

Uint8List _preprocessAlampGlobalViewFloat32(_PreprocessRequest request) {
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) {
    throw Exception('Cannot decode image bytes.');
  }

  return _preprocessDecodedAlampGlobalViewFloat32(
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

Uint8List _preprocessDecodedAlampGlobalViewFloat32(
  img.Image decoded, {
  required int width,
  required int height,
  required ImageNormalization normalization,
}) {
  // A-LAMP training used aspect-preserving resize with deterministic black pad.
  final scale = math.min(width / decoded.width, height / decoded.height);
  final resizedWidth = math.max(1, (decoded.width * scale).round());
  final resizedHeight = math.max(1, (decoded.height * scale).round());
  final resized = img.copyResize(
    decoded,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: img.Interpolation.linear,
  );
  final offsetX = ((width - resizedWidth) / 2).floor();
  final offsetY = ((height - resizedHeight) / 2).floor();
  final padValue = _normalize(0, normalization);
  final output = Float32List(width * height * 3);
  for (var index = 0; index < output.length; index++) {
    output[index] = padValue;
  }

  for (var y = 0; y < resizedHeight; y++) {
    for (var x = 0; x < resizedWidth; x++) {
      final pixel = resized.getPixel(x, y);
      var cursor = (((y + offsetY) * width) + x + offsetX) * 3;
      output[cursor++] = _normalize(pixel.r, normalization);
      output[cursor++] = _normalize(pixel.g, normalization);
      output[cursor] = _normalize(pixel.b, normalization);
    }
  }

  debugPrint(
    '[AcutPerf] alamp_global_view source=${decoded.width}x${decoded.height} '
    'resized=${resizedWidth}x$resizedHeight target=${width}x$height',
  );
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

Uint8List _preprocessAlampAdaptivePatchesFloat32(
  _PatchBatchPreprocessRequest request,
) {
  final decoded = img.decodeImage(request.imageBytes);
  if (decoded == null) {
    throw Exception('Cannot decode image bytes.');
  }

  final selection = _selectAlampAdaptivePatchBoxes(decoded, request.patchCount);
  debugPrint(
    '[AcutPerf] alamp_adaptive_patch_boxes boxes=${selection.debugLabel}',
  );
  return _preprocessDecodedPatchBoxesToRgbFloat32(
    decoded,
    boxes: selection.boxes,
    patchWidth: request.patchWidth,
    patchHeight: request.patchHeight,
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
  return _preprocessDecodedFixedAnchorPatchBatchToRgbFloat32(
    decoded,
    patchWidth: patchWidth,
    patchHeight: patchHeight,
    patchCount: patchCount,
    normalization: normalization,
  );
}

Uint8List _preprocessDecodedFixedAnchorPatchBatchToRgbFloat32(
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

Uint8List _preprocessDecodedPatchBoxesToRgbFloat32(
  img.Image decoded, {
  required List<_PatchBox> boxes,
  required int patchWidth,
  required int patchHeight,
  required ImageNormalization normalization,
}) {
  final output = Float32List(boxes.length * patchWidth * patchHeight * 3);
  var cursor = 0;

  for (final box in boxes) {
    final cropped = img.copyCrop(
      decoded,
      x: box.x,
      y: box.y,
      width: box.side,
      height: box.side,
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

_PatchSelection _selectAlampAdaptivePatchBoxes(
  img.Image decoded,
  int patchCount,
) {
  final safePatchCount = math.max(1, patchCount);
  final minSide = math.min(decoded.width, decoded.height);
  final candidateSides = <int>{
    (minSide * 0.35).round(),
    (minSide * 0.50).round(),
    (minSide * 0.65).round(),
    (minSide * 0.80).round(),
  }.where((side) => side > 8 && side <= minSide).toList(growable: false);

  final candidates = <_PatchBox>[];
  for (final side in candidateSides) {
    final stride = math.max(1, (side * 0.35).round());
    for (var y = 0; y <= decoded.height - side; y += stride) {
      for (var x = 0; x <= decoded.width - side; x += stride) {
        candidates.add(
          _PatchBox(
            x: x,
            y: y,
            side: side,
            score: _scorePatchCandidate(decoded, x: x, y: y, side: side),
          ),
        );
      }
    }
  }

  candidates.sort((a, b) => b.score.compareTo(a.score));
  final selected = <_PatchBox>[];
  for (final candidate in candidates) {
    final overlaps = selected.any((box) => _iou(box, candidate) > 0.45);
    if (!overlaps) {
      selected.add(candidate);
      if (selected.length == safePatchCount) {
        break;
      }
    }
  }

  if (selected.length < safePatchCount) {
    for (final box in _fallbackPatchBoxes(decoded, safePatchCount)) {
      final overlaps = selected.any(
        (selectedBox) => _iou(selectedBox, box) > 0.65,
      );
      if (!overlaps) {
        selected.add(box);
        if (selected.length == safePatchCount) {
          break;
        }
      }
    }
  }

  while (selected.length < safePatchCount) {
    selected.add(_centerPatchBox(decoded));
  }

  return _PatchSelection(selected.take(safePatchCount).toList(growable: false));
}

double _scorePatchCandidate(
  img.Image decoded, {
  required int x,
  required int y,
  required int side,
}) {
  const samples = 12;
  var count = 0;
  var lumSum = 0.0;
  var lumSqSum = 0.0;
  var rSum = 0.0;
  var gSum = 0.0;
  var bSum = 0.0;
  var rSqSum = 0.0;
  var gSqSum = 0.0;
  var bSqSum = 0.0;
  var edgeSum = 0.0;

  for (var sy = 0; sy < samples; sy++) {
    final py = (y + ((sy + 0.5) * side / samples)).floor().clamp(
      0,
      decoded.height - 1,
    );
    for (var sx = 0; sx < samples; sx++) {
      final px = (x + ((sx + 0.5) * side / samples)).floor().clamp(
        0,
        decoded.width - 1,
      );
      final pixel = decoded.getPixel(px, py);
      final r = pixel.r.toDouble();
      final g = pixel.g.toDouble();
      final b = pixel.b.toDouble();
      final lum = (0.299 * r) + (0.587 * g) + (0.114 * b);

      count++;
      lumSum += lum;
      lumSqSum += lum * lum;
      rSum += r;
      gSum += g;
      bSum += b;
      rSqSum += r * r;
      gSqSum += g * g;
      bSqSum += b * b;

      if (px + 1 < decoded.width && py + 1 < decoded.height) {
        final right = decoded.getPixel(px + 1, py);
        final down = decoded.getPixel(px, py + 1);
        final rightLum =
            (0.299 * right.r) + (0.587 * right.g) + (0.114 * right.b);
        final downLum = (0.299 * down.r) + (0.587 * down.g) + (0.114 * down.b);
        edgeSum += (lum - rightLum).abs() + (lum - downLum).abs();
      }
    }
  }

  if (count == 0) {
    return 0.0;
  }

  final invCount = 1.0 / count;
  final lumVar = math.max(
    0.0,
    (lumSqSum * invCount) - math.pow(lumSum * invCount, 2),
  );
  final rVar = math.max(
    0.0,
    (rSqSum * invCount) - math.pow(rSum * invCount, 2),
  );
  final gVar = math.max(
    0.0,
    (gSqSum * invCount) - math.pow(gSum * invCount, 2),
  );
  final bVar = math.max(
    0.0,
    (bSqSum * invCount) - math.pow(bSum * invCount, 2),
  );
  final colorVar = (rVar + gVar + bVar) / 3.0;
  final centerX = x + (side / 2.0);
  final centerY = y + (side / 2.0);
  final dx = ((centerX / decoded.width) - 0.5).abs();
  final dy = ((centerY / decoded.height) - 0.5).abs();
  final centerPrior = 1.0 - math.min(1.0, math.sqrt((dx * dx) + (dy * dy)));

  return (edgeSum * invCount * 0.45) +
      (math.sqrt(lumVar) * 0.30) +
      (math.sqrt(colorVar) * 0.20) +
      (centerPrior * 8.0);
}

List<_PatchBox> _fallbackPatchBoxes(img.Image decoded, int patchCount) {
  final cropSide = math.max(
    1,
    (math.min(decoded.width, decoded.height) * 0.6).round(),
  );
  return _buildPatchAnchors(patchCount)
      .map((anchor) {
        final cropX = (((decoded.width - cropSide) * anchor.dx).round())
            .clamp(0, math.max(0, decoded.width - cropSide))
            .toInt();
        final cropY = (((decoded.height - cropSide) * anchor.dy).round())
            .clamp(0, math.max(0, decoded.height - cropSide))
            .toInt();
        return _PatchBox(x: cropX, y: cropY, side: cropSide, score: 0.0);
      })
      .toList(growable: false);
}

_PatchBox _centerPatchBox(img.Image decoded) {
  final side = math.max(1, math.min(decoded.width, decoded.height));
  return _PatchBox(
    x: ((decoded.width - side) / 2).round(),
    y: ((decoded.height - side) / 2).round(),
    side: side,
    score: 0.0,
  );
}

double _iou(_PatchBox a, _PatchBox b) {
  final left = math.max(a.x, b.x);
  final top = math.max(a.y, b.y);
  final right = math.min(a.x + a.side, b.x + b.side);
  final bottom = math.min(a.y + a.side, b.y + b.side);
  final intersectionWidth = math.max(0, right - left);
  final intersectionHeight = math.max(0, bottom - top);
  final intersection = intersectionWidth * intersectionHeight;
  if (intersection == 0) {
    return 0.0;
  }
  final union = (a.side * a.side) + (b.side * b.side) - intersection;
  return union <= 0 ? 0.0 : intersection / union;
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

class _PatchBox {
  final int x;
  final int y;
  final int side;
  final double score;

  const _PatchBox({
    required this.x,
    required this.y,
    required this.side,
    required this.score,
  });

  String get debugLabel => '($x,$y,$side,${score.toStringAsFixed(1)})';
}

class _PatchSelection {
  final List<_PatchBox> boxes;

  const _PatchSelection(this.boxes);

  String get debugLabel => boxes.map((box) => box.debugLabel).join(';');
}

double _normalize(num channel, ImageNormalization normalization) {
  switch (normalization) {
    case ImageNormalization.zeroToOne:
      return channel / 255.0;
    case ImageNormalization.minusOneToOne:
      return (channel / 127.5) - 1.0;
  }
}
