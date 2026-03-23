import 'dart:io';

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:pose_camera_app/core/enums/scene_type.dart';
import 'package:pose_camera_app/core/models/classification_result.dart';

class SceneClassifierService {
  SceneClassifierService()
      : _imageLabeler = ImageLabeler(
          options: ImageLabelerOptions(confidenceThreshold: 0.55),
        );

  final ImageLabeler _imageLabeler;

  static const List<String> _foodKeywords = [
    'food',
    'dish',
    'meal',
    'drink',
    'beverage',
    'dessert',
    'fruit',
    'vegetable',
    'bread',
    'cake',
    'pizza',
    'burger',
    'pasta',
    'salad',
    'coffee',
    'tea',
    'plate',
    'bowl',
    'cuisine',
  ];

  Future<ClassificationResult> classifyFile(File file) async {
    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final labels = await _imageLabeler.processImage(inputImage);

      if (labels.isEmpty) {
        return ClassificationResult.unknown(source: 'mlkit');
      }

      final sorted = [...labels]
        ..sort((a, b) => b.confidence.compareTo(a.confidence));

      final preview = sorted
          .take(5)
          .map(
            (label) =>
                '${label.label} ${(label.confidence * 100).toStringAsFixed(0)}%',
          )
          .toList();

      for (final label in sorted) {
        final raw = label.label.toLowerCase();
        final isFood = _foodKeywords.any((keyword) => raw.contains(keyword));

        if (isFood) {
          return ClassificationResult(
            scene: SceneType.food,
            confidence: label.confidence,
            labels: preview,
            source: 'mlkit',
          );
        }
      }

      return ClassificationResult(
        scene: SceneType.object,
        confidence: sorted.first.confidence,
        labels: preview,
        source: 'mlkit',
      );
    } catch (_) {
      return ClassificationResult.unknown(source: 'mlkit-error');
    } finally {
      try {
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _imageLabeler.close();
  }
}