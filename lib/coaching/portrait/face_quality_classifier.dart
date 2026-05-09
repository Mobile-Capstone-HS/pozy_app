/// 얼굴 품질 분류기 (더미)
///
/// 실제 TFLite 모델 대신 얼굴 크기와 위치 기반 더미 품질 점수를 반환합니다.
library;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceQualityClassifier {
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _isLoaded = true;
    debugPrint('[FACE_QUALITY] init done');
  }

  List<double> classify(List<Face> faces) {
    final limitedFaces = faces.take(6).toList(growable: false);
    return limitedFaces
        .map((face) {
          final box = face.boundingBox;
          final areaScore = (box.width * box.height / 25000.0).clamp(0.0, 1.0);
          final centerDeviation =
              (box.center.dx - 0.5).abs() + (box.center.dy - 0.4).abs();
          final centerScore = (1.0 - centerDeviation / 1.4).clamp(0.0, 1.0);
          return (0.35 + areaScore * 0.35 + centerScore * 0.3).clamp(0.0, 1.0);
        })
        .toList(growable: false);
  }

  /// 분류기 입력으로 112x112 RGB 바이트 배열 리스트를 받습니다.
  /// 각 Uint8List는 연속된 RGB 바이트 (width*height*3) 여야 합니다.
  List<double> classifyCrops(List<Uint8List> crops, int width, int height) {
    final limited = crops.take(6).toList(growable: false);
    final results = <double>[];
    for (final bytes in limited) {
      if (bytes.length < width * height * 3) {
        results.add(0.0);
        continue;
      }
      double lumSum = 0.0;
      for (int i = 0; i < width * height * 3; i += 3) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        // Rec. 709 luminance
        lumSum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
      }
      final avg = lumSum / (width * height);
      results.add((avg / 255.0).clamp(0.0, 1.0));
    }
    return results;
  }

  void dispose() {}
}
