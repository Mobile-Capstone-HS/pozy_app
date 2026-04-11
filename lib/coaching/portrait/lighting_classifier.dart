/// 조명 방향 분류기
///
/// lighting_model.tflite를 사용해서
/// 얼굴 이미지의 조명 방향을 판단합니다.
/// 3클래스: normal_light / side_light / back_light
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';

import 'portrait_scene_state.dart';

class LightingClassifier {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// 모델과 라벨 파일을 로드합니다.
  Future<void> load() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/lighting_model.tflite',
      );
      final labelData = await rootBundle.loadString(
        'assets/models/lighting_labels.txt',
      );
      _labels = labelData.trim().split('\n').map((s) => s.trim()).toList();

      _isLoaded = true;
      debugPrint('조명 분류기 로드 완료: $_labels');
    } catch (e, st) {
      debugPrint('[LIGHT_LOAD_ERROR] $e');
      debugPrint('[LIGHT_LOAD_ERROR] $st');
      _isLoaded = false;
    }
  }

  /// 얼굴 크롭 이미지(RGB 바이트)로 조명 방향을 판단합니다.
  ///
  /// [facePixels] - 224x224x3 크기의 RGB 픽셀 데이터
  /// 반환: (LightingCondition, confidence)
  ({LightingCondition condition, double confidence}) classify(
    Float32List facePixels,
  ) {
    if (!_isLoaded || _interpreter == null) {
      return (condition: LightingCondition.unknown, confidence: 0.0);
    }

    try {
      // 입력: [1, 224, 224, 3]
      final inputBytes = facePixels.buffer.asUint8List();

      // 출력: [1, 3]
      final outputBytes = Uint8List(_labels.length * 4);

      _interpreter!.run(inputBytes, outputBytes.buffer);

      // 가장 높은 확률의 클래스 찾기
      final probabilities = outputBytes.buffer.asFloat32List();
      int maxIndex = 0;
      double maxProb = 0;
      for (int i = 0; i < probabilities.length; i++) {
        if (probabilities[i] > maxProb) {
          maxProb = probabilities[i];
          maxIndex = i;
        }
      }

      final label = _labels[maxIndex];
      final condition = _labelToCondition(label);

      return (condition: condition, confidence: maxProb);
    } catch (e) {
      debugPrint('조명 분류 에러: $e');
      return (condition: LightingCondition.unknown, confidence: 0.0);
    }
  }

  /// 카메라 프레임에서 얼굴 영역을 크롭해서 분류용 입력을 만듭니다.
  ///
  /// [imageBytes] - 전체 프레임의 Y채널 (밝기) 바이트
  /// [imageWidth], [imageHeight] - 프레임 크기
  /// [faceLeft], [faceTop], [faceWidth], [faceHeight] - 얼굴 영역 (정규화 0~1)
  Float32List? prepareFaceCrop({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
    required double faceLeft,
    required double faceTop,
    required double faceWidth,
    required double faceHeight,
  }) {
    try {
      // 정규화 좌표를 픽셀 좌표로 변환
      final x = (faceLeft * imageWidth).round().clamp(0, imageWidth - 1);
      final y = (faceTop * imageHeight).round().clamp(0, imageHeight - 1);
      final w = (faceWidth * imageWidth).round().clamp(1, imageWidth - x);
      final h = (faceHeight * imageHeight).round().clamp(1, imageHeight - y);

      // 224x224 크기의 Float32List (RGB 3채널)
      final result = Float32List(224 * 224 * 3);

      for (int ty = 0; ty < 224; ty++) {
        for (int tx = 0; tx < 224; tx++) {
          // 소스 좌표 계산 (단순 리사이즈)
          final sx = x + (tx * w ~/ 224);
          final sy = y + (ty * h ~/ 224);

          final srcIdx = sy * imageWidth + sx;
          if (srcIdx >= 0 && srcIdx < imageBytes.length) {
            final brightness = imageBytes[srcIdx].toDouble();
            final dstIdx = (ty * 224 + tx) * 3;
            // 흑백이므로 RGB 동일하게
            result[dstIdx] = brightness;
            result[dstIdx + 1] = brightness;
            result[dstIdx + 2] = brightness;
          }
        }
      }

      return result;
    } catch (e) {
      debugPrint('얼굴 크롭 에러: $e');
      return null;
    }
  }

  LightingCondition _labelToCondition(String label) {
    switch (label) {
      case 'front_light':
        return LightingCondition.normal;
      case 'short_light':
        return LightingCondition.short;
      case 'side_light':
        return LightingCondition.side;
      case 'rim_light':
        return LightingCondition.rim;
      case 'back_light':
        return LightingCondition.back;
      default:
        return LightingCondition.unknown;
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}
