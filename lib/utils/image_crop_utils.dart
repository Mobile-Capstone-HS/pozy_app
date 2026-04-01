import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Rect, Size;
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────────────────────
// AADB model crop + preprocess
// ─────────────────────────────────────────────────────────────────────────────

/// Crops [normalizedRect] from [frameBytes], resizes to [targetSize]×[targetSize],
/// and returns a packed Float32List of RGB values in [0, 1] (÷255).
///
/// This matches the composition_aadb_gpu model's expected input:
///   shape  [1, 224, 224, 3]
///   dtype  float32
///   range  [0, 1]  (divide by 255, NOT the NIMA ÷127.5 - 1 convention)
///
/// [frameSize]: pixel dimensions of the decoded camera frame.  Pass [Size.zero]
/// to use the actual decoded image size (recommended when the exact capture
/// resolution is unknown).
///
/// Returns `null` if [frameBytes] cannot be decoded or the crop is degenerate.
///
/// Runs entirely in a background isolate via [compute] — safe to call from the
/// detection callback without blocking the main thread.
Future<Float32List?> cropAndPreprocessForAadb(
  Uint8List frameBytes, {
  required Rect normalizedRect,
  Size frameSize = Size.zero,
  int targetSize = 224,
}) {
  return compute(
    _cropAndPreprocess,
    _CropRequest(
      frameBytes: frameBytes,
      cropLeft: normalizedRect.left,
      cropTop: normalizedRect.top,
      cropRight: normalizedRect.right,
      cropBottom: normalizedRect.bottom,
      frameWidth: frameSize.width.round(),
      frameHeight: frameSize.height.round(),
      targetSize: targetSize,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate payload (must be a plain Dart class — no Flutter objects)
// ─────────────────────────────────────────────────────────────────────────────

class _CropRequest {
  final Uint8List frameBytes;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;
  final int frameWidth;
  final int frameHeight;
  final int targetSize;

  const _CropRequest({
    required this.frameBytes,
    required this.cropLeft,
    required this.cropTop,
    required this.cropRight,
    required this.cropBottom,
    required this.frameWidth,
    required this.frameHeight,
    required this.targetSize,
  });
}

// Top-level function required by compute().
Float32List? _cropAndPreprocess(_CropRequest req) {
  final decoded = img.decodeImage(req.frameBytes);
  if (decoded == null) return null;

  // Use the actual decoded image dimensions when caller passed Size.zero.
  final imgW = req.frameWidth > 0 ? req.frameWidth : decoded.width;
  final imgH = req.frameHeight > 0 ? req.frameHeight : decoded.height;

  // Map normalised [0,1] rect → pixel rect on the decoded frame.
  //
  // Coordinate system assumption: YOLO normalises detection boxes to the same
  // frame that captureFrame() returns.  If the captured JPEG is rotated
  // relative to the preview, crops may be misaligned and this function will
  // need a rotation step.  The assumption is valid for most YOLO integrations
  // where inference and capture share the same camera pipeline.
  final px = (req.cropLeft * imgW).clamp(0.0, (imgW - 1).toDouble()).round();
  final py = (req.cropTop * imgH).clamp(0.0, (imgH - 1).toDouble()).round();
  final pw = ((req.cropRight - req.cropLeft) * imgW)
      .clamp(1.0, (imgW - px).toDouble())
      .round();
  final ph = ((req.cropBottom - req.cropTop) * imgH)
      .clamp(1.0, (imgH - py).toDouble())
      .round();

  final cropped = img.copyCrop(decoded, x: px, y: py, width: pw, height: ph);
  final resized = img.copyResize(
    cropped,
    width: req.targetSize,
    height: req.targetSize,
    interpolation: img.Interpolation.linear,
  );

  final total = req.targetSize * req.targetSize * 3;
  final output = Float32List(total);
  var cursor = 0;

  for (var y = 0; y < req.targetSize; y++) {
    for (var x = 0; x < req.targetSize; x++) {
      final pixel = resized.getPixel(x, y);
      // AADB normalisation: divide by 255.0 (NOT the NIMA ÷127.5−1 formula).
      output[cursor++] = pixel.r / 255.0;
      output[cursor++] = pixel.g / 255.0;
      output[cursor++] = pixel.b / 255.0;
    }
  }

  return output;
}
