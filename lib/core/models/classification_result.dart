import 'package:pose_camera_app/core/enums/scene_type.dart';

class ClassificationResult {
  const ClassificationResult({
    required this.scene,
    required this.confidence,
    required this.labels,
    required this.source,
  });

  final SceneType scene;
  final double confidence;
  final List<String> labels;
  final String source;

  factory ClassificationResult.unknown({String source = 'none'}) {
    return ClassificationResult(
      scene: SceneType.unknown,
      confidence: 0,
      labels: const [],
      source: source,
    );
  }

  String get labelPreview {
    if (labels.isEmpty) return '라벨 없음';
    return labels.take(3).join(', ');
  }
}
