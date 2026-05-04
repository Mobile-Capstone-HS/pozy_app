import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class AnalyzeRequest {
  final List<int> jpegBytes;
  final List<double>? unionRoi; // [left, top, right, bottom] normalized

  const AnalyzeRequest({
    required this.jpegBytes,
    required this.unionRoi,
  });
}

/// 광원 방향 — 이미지 분석 결과용 (int로 전달)
/// 0=unknown, 1=left, 2=right, 3=top, 4=bottom, 5=behind
class ObjectImageMetrics {
  final double brightness;
  final double subjectBrightness;
  final double backgroundBrightness;
  final double globalBlurScore;
  final double subjectBlurScore;
  final double highlightRatio;
  final double shadowRatio;
  final double subjectHighlightRatio;
  final double subjectShadowRatio;

  /// 광원 방향 (0~5, LightDirection 인덱스와 대응)
  final int lightDirectionIndex;

  const ObjectImageMetrics({
    required this.brightness,
    required this.subjectBrightness,
    required this.backgroundBrightness,
    required this.globalBlurScore,
    required this.subjectBlurScore,
    required this.highlightRatio,
    required this.shadowRatio,
    required this.subjectHighlightRatio,
    required this.subjectShadowRatio,
    this.lightDirectionIndex = 0,
  });
}

Future<ObjectImageMetrics> analyzeObjectImage(AnalyzeRequest request) {
  return compute(_analyzeIsolate, request);
}

ObjectImageMetrics _analyzeIsolate(AnalyzeRequest request) {
  final decoded = img.decodeImage(Uint8List.fromList(request.jpegBytes));

  if (decoded == null) {
    return const ObjectImageMetrics(
      brightness: 0.5,
      subjectBrightness: 0.5,
      backgroundBrightness: 0.5,
      globalBlurScore: 999,
      subjectBlurScore: 999,
      highlightRatio: 0,
      shadowRatio: 0,
      subjectHighlightRatio: 0,
      subjectShadowRatio: 0,
    );
  }

  final small = img.copyResize(decoded, width: 160, height: 120);
  final roi = _normalizeRoi(request.unionRoi);

  final brightness = _computeBrightness(small, null);
  final subjectBrightness = _computeBrightness(small, roi);
  final backgroundBrightness = _computeBackgroundBrightness(small, roi);

  final globalBlurScore = _computeLaplacianVariance(small, null);
  final subjectBlurScore = _computeLaplacianVariance(small, roi);

  final highlightRatio = _computeHighlightRatio(small, roi);
  final shadowRatio = _computeShadowRatio(small, roi);
  final subjectHighlightRatio = _computeHighlightRatio(small, roi, subjectOnly: true);
  final subjectShadowRatio = _computeShadowRatio(small, roi, subjectOnly: true);

  final lightDir = _estimateLightDirection(small, roi);

  return ObjectImageMetrics(
    brightness: brightness,
    subjectBrightness: subjectBrightness,
    backgroundBrightness: backgroundBrightness,
    globalBlurScore: globalBlurScore,
    subjectBlurScore: subjectBlurScore,
    highlightRatio: highlightRatio,
    shadowRatio: shadowRatio,
    subjectHighlightRatio: subjectHighlightRatio,
    subjectShadowRatio: subjectShadowRatio,
    lightDirectionIndex: lightDir,
  );
}

List<double>? _normalizeRoi(List<double>? roi) {
  if (roi == null || roi.length != 4) return null;

  final left = (roi[0] - 0.04).clamp(0.0, 1.0);
  final top = (roi[1] - 0.04).clamp(0.0, 1.0);
  final right = (roi[2] + 0.04).clamp(0.0, 1.0);
  final bottom = (roi[3] + 0.04).clamp(0.0, 1.0);

  if (right <= left || bottom <= top) return null;
  return [left, top, right, bottom];
}

double _computeBrightness(img.Image image, List<double>? roi) {
  final bounds = _roiBounds(image, roi);

  double sum = 0;
  int count = 0;

  for (int y = bounds.top; y < bounds.bottom; y++) {
    for (int x = bounds.left; x < bounds.right; x++) {
      sum += _luma(image.getPixel(x, y));
      count++;
    }
  }

  if (count == 0) return 0.5;
  return (sum / count / 255.0).clamp(0.0, 1.0);
}

double _computeBackgroundBrightness(img.Image image, List<double>? roi) {
  if (roi == null) {
    return _computeBrightness(image, null);
  }

  final bounds = _roiBounds(image, roi);
  double sum = 0;
  int count = 0;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final inRoi =
          x >= bounds.left && x < bounds.right && y >= bounds.top && y < bounds.bottom;
      if (inRoi) continue;

      sum += _luma(image.getPixel(x, y));
      count++;
    }
  }

  if (count == 0) return _computeBrightness(image, null);
  return (sum / count / 255.0).clamp(0.0, 1.0);
}

double _computeHighlightRatio(
  img.Image image,
  List<double>? roi, {
  bool subjectOnly = false,
}) {
  final bounds = _roiBounds(image, roi);
  int brightCount = 0;
  int count = 0;

  final startY = subjectOnly ? bounds.top : 0;
  final endY = subjectOnly ? bounds.bottom : image.height;
  final startX = subjectOnly ? bounds.left : 0;
  final endX = subjectOnly ? bounds.right : image.width;

  for (int y = startY; y < endY; y++) {
    for (int x = startX; x < endX; x++) {
      final l = _luma(image.getPixel(x, y));
      if (l >= 235.0) brightCount++;
      count++;
    }
  }

  if (count == 0) return 0;
  return (brightCount / count).clamp(0.0, 1.0);
}

double _computeShadowRatio(
  img.Image image,
  List<double>? roi, {
  bool subjectOnly = false,
}) {
  final bounds = _roiBounds(image, roi);
  int darkCount = 0;
  int count = 0;

  final startY = subjectOnly ? bounds.top : 0;
  final endY = subjectOnly ? bounds.bottom : image.height;
  final startX = subjectOnly ? bounds.left : 0;
  final endX = subjectOnly ? bounds.right : image.width;

  for (int y = startY; y < endY; y++) {
    for (int x = startX; x < endX; x++) {
      final l = _luma(image.getPixel(x, y));
      if (l <= 35.0) darkCount++;
      count++;
    }
  }

  if (count == 0) return 0;
  return (darkCount / count).clamp(0.0, 1.0);
}

double _computeLaplacianVariance(img.Image image, List<double>? roi) {
  final w = image.width;
  final h = image.height;
  final gray = _buildGrayCache(image);
  final bounds = _roiBounds(image, roi, inset: 1);

  double sum = 0;
  double sumSq = 0;
  int count = 0;

  for (int y = bounds.top; y < bounds.bottom; y++) {
    for (int x = bounds.left; x < bounds.right; x++) {
      if (x <= 0 || x >= w - 1 || y <= 0 || y >= h - 1) continue;

      final c = gray[y * w + x];
      final n = gray[(y - 1) * w + x];
      final s = gray[(y + 1) * w + x];
      final e = gray[y * w + (x + 1)];
      final ww = gray[y * w + (x - 1)];

      final lap = n + s + e + ww - 4.0 * c;
      sum += lap;
      sumSq += lap * lap;
      count++;
    }
  }

  if (count == 0) return 999.0;
  final mean = sum / count;
  return (sumSq / count) - (mean * mean);
}

class _Bounds {
  final int left;
  final int top;
  final int right;
  final int bottom;

  const _Bounds(this.left, this.top, this.right, this.bottom);
}

_Bounds _roiBounds(img.Image image, List<double>? roi, {int inset = 0}) {
  if (roi == null) {
    return _Bounds(
      inset,
      inset,
      image.width - inset,
      image.height - inset,
    );
  }

  final left =
      (roi[0] * image.width).floor().clamp(inset, image.width - inset - 1);
  final top =
      (roi[1] * image.height).floor().clamp(inset, image.height - inset - 1);
  final right =
      (roi[2] * image.width).ceil().clamp(inset + 1, image.width - inset);
  final bottom =
      (roi[3] * image.height).ceil().clamp(inset + 1, image.height - inset);

  return _Bounds(left, top, right, bottom);
}

List<double> _buildGrayCache(img.Image image) {
  final w = image.width;
  final h = image.height;

  return List<double>.generate(
    w * h,
    (i) => _luma(image.getPixel(i % w, i ~/ w)),
  );
}

double _luma(img.Pixel pixel) =>
    0.299 * pixel.r.toDouble() +
    0.587 * pixel.g.toDouble() +
    0.114 * pixel.b.toDouble();

/// 이미지를 4분면(왼/오/위/아래)으로 나눠 평균 밝기를 비교해 광원 방향을 추정한다.
/// 역광은 피사체(ROI) 밝기가 배경보다 현저히 낮을 때 판정.
/// 반환값: 0=unknown, 1=left, 2=right, 3=top, 4=bottom, 5=behind
int _estimateLightDirection(img.Image image, List<double>? roi) {
  final w = image.width;
  final h = image.height;
  final midX = w ~/ 2;
  final midY = h ~/ 2;

  double sumLeft = 0, sumRight = 0, sumTop = 0, sumBottom = 0;
  int cntLeft = 0, cntRight = 0, cntTop = 0, cntBottom = 0;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final l = _luma(image.getPixel(x, y));
      if (x < midX) {
        sumLeft += l;
        cntLeft++;
      } else {
        sumRight += l;
        cntRight++;
      }
      if (y < midY) {
        sumTop += l;
        cntTop++;
      } else {
        sumBottom += l;
        cntBottom++;
      }
    }
  }

  if (cntLeft == 0 || cntRight == 0 || cntTop == 0 || cntBottom == 0) return 0;

  final avgLeft = sumLeft / cntLeft;
  final avgRight = sumRight / cntRight;
  final avgTop = sumTop / cntTop;
  final avgBottom = sumBottom / cntBottom;

  // 역광 판정: ROI가 있고 피사체가 배경보다 많이 어두우면 역광
  if (roi != null) {
    final bounds = _roiBounds(image, roi);
    double subjectSum = 0;
    int subjectCnt = 0;
    double bgSum = 0;
    int bgCnt = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final l = _luma(image.getPixel(x, y));
        final inRoi = x >= bounds.left && x < bounds.right &&
            y >= bounds.top && y < bounds.bottom;
        if (inRoi) {
          subjectSum += l;
          subjectCnt++;
        } else {
          bgSum += l;
          bgCnt++;
        }
      }
    }
    if (subjectCnt > 0 && bgCnt > 0) {
      final subjectAvg = subjectSum / subjectCnt;
      final bgAvg = bgSum / bgCnt;
      // 배경이 충분히 밝고 피사체와 차이가 클 때 역광
      if (bgAvg > 150 && (bgAvg - subjectAvg) > 50) return 5; // behind
    }
  }

  // 방향별 밝기 차이 — 가장 밝은 쪽이 광원 방향
  const threshold = 20.0; // 최소 차이
  final hDiff = avgRight - avgLeft; // 양수면 오른쪽이 밝음
  final vDiff = avgBottom - avgTop; // 양수면 아래가 밝음

  final absH = hDiff.abs();
  final absV = vDiff.abs();

  if (absH < threshold && absV < threshold) return 0; // unknown

  if (absH >= absV) {
    return hDiff > 0 ? 2 : 1; // right : left
  } else {
    return vDiff > 0 ? 4 : 3; // bottom : top
  }
}

