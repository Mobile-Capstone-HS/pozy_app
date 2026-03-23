import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import 'subject_selector.dart';

List<CameraDescription> cameras = [];

class _DetectionBox {
  final Rect rect;
  final String className;
  final double confidence;

  const _DetectionBox({
    required this.rect,
    required this.className,
    required this.confidence,
  });

  bool get isPerson => className.toLowerCase() == 'person';
}

class DetectPainter extends CustomPainter {
  final List<_DetectionBox> detections;

  DetectPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final accent = detection.isPerson
          ? Colors.greenAccent
          : Colors.orangeAccent;

      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      final boxPaint = Paint()
        ..color = accent.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawRect(detection.rect, shadowPaint);
      canvas.drawRect(detection.rect, boxPaint);

      final confidenceText = '${(detection.confidence * 100).toStringAsFixed(1)}%';
      final label = '${detection.className} $confidenceText';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          detection.rect.left,
          (detection.rect.top - 20).clamp(0, size.height - 20),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DetectPainter oldDelegate) =>
      oldDelegate.detections != detections;
}

class DetectScreen extends StatefulWidget {
  const DetectScreen({super.key});

  @override
  State<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends State<DetectScreen> {
  final List<_DetectionBox> _detections = [];
  final SubjectSelector _selector = const SubjectSelector(
    wSize: 0.35,
    wCenter: 0.25,
    wClass: 0.2,
    wConfidence: 0.1,
    wSaliency: 0.1,
    threshold: 0.3,
  );
  int _personCount = 0;
  int _objectCount = 0;
  String _guidance = 'Scene is balanced';
  Size _previewSize = Size.zero;

  Rect _toPreviewRect(YOLOResult result, Size previewSize) {
    return Rect.fromLTRB(
      (result.normalizedBox.left * previewSize.width).clamp(0, previewSize.width),
      (result.normalizedBox.top * previewSize.height)
          .clamp(0, previewSize.height),
      (result.normalizedBox.right * previewSize.width).clamp(0, previewSize.width),
      (result.normalizedBox.bottom * previewSize.height)
          .clamp(0, previewSize.height),
    );
  }

  void _handleDetections(List<YOLOResult> results) {
    final previewSize = _previewSize == Size.zero
        ? MediaQuery.of(context).size
        : _previewSize;
    final candidates = results
        .asMap()
        .entries
        .map(
          (entry) => SubjectDetection(
            id: entry.key,
            normalizedBox: Rect.fromLTRB(
              entry.value.normalizedBox.left,
              entry.value.normalizedBox.top,
              entry.value.normalizedBox.right,
              entry.value.normalizedBox.bottom,
            ),
            className: entry.value.className,
            confidence: entry.value.confidence,
          ),
        )
        .toList();
    final selection = _selector.selectMainSubject(
      detections: candidates,
      imageSize: previewSize,
    );

    if (!mounted) return;
    setState(() {
      _detections
        ..clear();
      _guidance = selection.guidance;

      if (selection.best != null) {
        final index = selection.best!.detection.id;
        if (index < 0 || index >= results.length) {
          _personCount = 0;
          _objectCount = 0;
          return;
        }
        final source = results[index];
        final mainRect = _toPreviewRect(source, previewSize);
        final main = _DetectionBox(
          rect: mainRect,
          className: source.className,
          confidence: source.confidence,
        );
        _detections.add(main);
        _personCount = main.isPerson ? 1 : 0;
        _objectCount = main.isPerson ? 0 : 1;
      } else {
        _personCount = 0;
        _objectCount = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _previewSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      YOLOView(
                        modelPath: 'yolov8n_float16.tflite',
                        task: YOLOTask.detect,
                        useGpu: false,
                        streamingConfig: const YOLOStreamingConfig.minimal(),
                        showOverlays: true,
                        onResult: _handleDetections,
                      ),
                      CustomPaint(
                        painter: DetectPainter(detections: _detections),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Total: ${_detections.length}  Person: $_personCount  Object: $_objectCount\n$_guidance',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
