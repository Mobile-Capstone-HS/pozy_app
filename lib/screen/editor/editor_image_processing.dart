import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int editorExportMaxDimension = 3072;
const int editorPreviewMaxDimension = 1600;

Map<String, dynamic> prepareEditorBuffers(Uint8List rawBytes) {
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) {
    throw Exception('이미지를 해석할 수 없습니다.');
  }

  final normalized = img.bakeOrientation(decoded);
  final exportBase = resizeImageToMaxDimension(
    normalized,
    editorExportMaxDimension,
  );
  final sourceBytes = Uint8List.fromList(
    img.encodeJpg(exportBase, quality: 92),
  );

  final previewBase = resizeImageToMaxDimension(
    exportBase,
    editorPreviewMaxDimension,
  );

  final previewBytes = Uint8List.fromList(
    img.encodeJpg(previewBase, quality: 92),
  );

  return {
    'source': sourceBytes,
    'preview': previewBytes,
    'aspectRatio': normalized.width / normalized.height,
  };
}

Uint8List renderAdjustedJpg(Map<String, dynamic> request) {
  final bytes = request['bytes'] as Uint8List;
  final brightness = (request['brightness'] as num).toDouble();
  final contrast = (request['contrast'] as num).toDouble();
  final saturation = (request['saturation'] as num).toDouble();
  final warmth = (request['warmth'] as num).toDouble();
  final fade = (request['fade'] as num).toDouble();
  final sharpness = (request['sharpness'] as num).toDouble();

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('이미지를 해석할 수 없습니다.');
  }

  var edited = applyEditorAdjustments(
    decoded,
    brightness: brightness,
    contrast: contrast,
    saturation: saturation,
    warmth: warmth,
    fade: fade,
  );

  if (sharpness != 0) {
    edited = applySharpness(edited, sharpness);
  }

  return Uint8List.fromList(img.encodeJpg(edited, quality: 90));
}

img.Image applyEditorAdjustments(
  img.Image source, {
  required double brightness,
  required double contrast,
  required double saturation,
  required double warmth,
  required double fade,
}) {
  final output = img.Image.from(source);

  final brightnessOffset = brightness * 2.2;
  final contrastScaled = contrast.clamp(-99.0, 99.0) * 2.55;
  final contrastFactor =
      (259 * (contrastScaled + 255)) / (255 * (259 - contrastScaled));
  final saturationFactor = 1 + (saturation / 100);
  final warmthFactor = warmth / 100;
  final fadeFactor = fade / 100;

  for (int y = 0; y < output.height; y++) {
    for (int x = 0; x < output.width; x++) {
      final pixel = output.getPixel(x, y);

      double r = pixel.r.toDouble();
      double g = pixel.g.toDouble();
      double b = pixel.b.toDouble();
      final int a = pixel.a.toInt();

      r += brightnessOffset;
      g += brightnessOffset;
      b += brightnessOffset;

      r = contrastFactor * (r - 128) + 128;
      g = contrastFactor * (g - 128) + 128;
      b = contrastFactor * (b - 128) + 128;

      final luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
      r = luminance + ((r - luminance) * saturationFactor);
      g = luminance + ((g - luminance) * saturationFactor);
      b = luminance + ((b - luminance) * saturationFactor);

      r += 30 * warmthFactor;
      g += 8 * warmthFactor;
      b -= 30 * warmthFactor;

      if (fadeFactor >= 0) {
        r = (r * (1 - (fadeFactor * 0.18))) + (255 * fadeFactor * 0.10);
        g = (g * (1 - (fadeFactor * 0.16))) + (255 * fadeFactor * 0.08);
        b = (b * (1 - (fadeFactor * 0.14))) + (255 * fadeFactor * 0.06);
      } else {
        final deepen = fadeFactor.abs();
        r = (r * (1 + (deepen * 0.16))) - (255 * deepen * 0.08);
        g = (g * (1 + (deepen * 0.15))) - (255 * deepen * 0.07);
        b = (b * (1 + (deepen * 0.14))) - (255 * deepen * 0.06);
      }

      output.setPixelRgba(
        x,
        y,
        clampChannel(r),
        clampChannel(g),
        clampChannel(b),
        a,
      );
    }
  }

  return output;
}

int clampChannel(double value) {
  if (value.isNaN) return 0;
  if (value < 0) return 0;
  if (value > 255) return 255;
  return value.round();
}

img.Image applySharpness(img.Image source, double sharpness) {
  if (sharpness > 0) {
    final amount = sharpness / 100 * 1.5;
    final blurred = img.gaussianBlur(img.Image.from(source), radius: 2);
    final output = img.Image.from(source);

    for (int y = 0; y < output.height; y++) {
      for (int x = 0; x < output.width; x++) {
        final orig = source.getPixel(x, y);
        final blur = blurred.getPixel(x, y);

        output.setPixelRgba(
          x,
          y,
          clampChannel(orig.r + amount * (orig.r - blur.r)),
          clampChannel(orig.g + amount * (orig.g - blur.g)),
          clampChannel(orig.b + amount * (orig.b - blur.b)),
          orig.a.toInt(),
        );
      }
    }
    return output;
  } else {
    final radius = (sharpness.abs() / 100 * 5).round().clamp(1, 5);
    return img.gaussianBlur(source, radius: radius);
  }
}

img.Image resizeImageToMaxDimension(img.Image source, int maxDimension) {
  final longestSide = source.width >= source.height
      ? source.width
      : source.height;

  if (longestSide <= maxDimension) {
    return source;
  }

  if (source.width >= source.height) {
    return img.copyResize(source, width: maxDimension);
  }

  return img.copyResize(source, height: maxDimension);
}

Uint8List rotateImage90(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('이미지를 해석할 수 없습니다.');
  }
  final rotated = img.copyRotate(decoded, angle: 90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
}

Uint8List flipImageHorizontal(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('이미지를 해석할 수 없습니다.');
  }
  final flipped = img.flipHorizontal(decoded);
  return Uint8List.fromList(img.encodeJpg(flipped, quality: 92));
}
