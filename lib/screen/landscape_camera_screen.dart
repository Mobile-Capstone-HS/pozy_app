import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/composition_temporal_filter.dart';
import 'package:pose_camera_app/segmentation/fastscnn_segmentor.dart';
import 'package:pose_camera_app/segmentation/fastscnn_view.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class LandscapeCameraScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;

  const LandscapeCameraScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
  });

  @override
  State<LandscapeCameraScreen> createState() => _LandscapeCameraScreenState();
}

class _LandscapeCameraScreenState extends State<LandscapeCameraScreen> {
  final FastScnnViewController _controller = FastScnnViewController();
  final CompositionResolver _resolver = const CompositionResolver();
  final CompositionTemporalFilter _temporalFilter = CompositionTemporalFilter();

  CompositionDecision? _decision;

  @override
  void dispose() {
    _controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          FastScnnView(
            controller: _controller,
            frameSkipLevel: 2,
            inferenceIntervalMs: 220,
            onResult: (frame) {
              final raw = LandscapeAnalyzer.analyzeFeatures(frame.result);
              final smoothed = _temporalFilter.smooth(raw);
              final decision = _temporalFilter.stabilize(
                _resolver.resolve(smoothed),
              );
              if (!mounted) return;
              setState(() {
                _decision = decision;
              });
            },
            overlayBuilder: (context, frame) {
              return CustomPaint(
                painter: _SegmentationDotPainter(result: frame?.result),
                size: Size.infinite,
              );
            },
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _CompositionOverlayPainter(decision: _decision),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompositionOverlayPainter extends CustomPainter {
  final CompositionDecision? decision;

  const _CompositionOverlayPainter({required this.decision});

  @override
  void paint(Canvas canvas, Size size) {
    final d = decision;
    if (d == null || d.compositionMode == CompositionMode.none) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final dx1 = size.width / 3;
    final dx2 = size.width * 2 / 3;
    final dy1 = size.height / 3;
    final dy2 = size.height * 2 / 3;
    canvas.drawLine(Offset(dx1, 0), Offset(dx1, size.height), gridPaint);
    canvas.drawLine(Offset(dx2, 0), Offset(dx2, size.height), gridPaint);
    canvas.drawLine(Offset(0, dy1), Offset(size.width, dy1), gridPaint);
    canvas.drawLine(Offset(0, dy2), Offset(size.width, dy2), gridPaint);
  }

  @override
  bool shouldRepaint(covariant _CompositionOverlayPainter oldDelegate) {
    return oldDelegate.decision != decision;
  }
}

class _SegmentationDotPainter extends CustomPainter {
  final SegmentationResult? result;

  const _SegmentationDotPainter({required this.result});

  @override
  void paint(Canvas canvas, Size size) {
    final seg = result;
    if (seg == null || seg.height == 0 || seg.width == 0) return;

    final strideX = math.max(1, (seg.width / 24).round());
    final strideY = math.max(1, (seg.height / 14).round());
    final baseRadius = math.max(
      1.9,
      math.min(size.width, size.height) * 0.0052,
    );
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int y = 0; y < seg.height; y += strideY) {
      final row = seg.classMap[y];
      for (int x = 0; x < seg.width; x += strideX) {
        final color = _classColor(row[x]);
        if (color == null) continue;
        fillPaint.color = color;
        final center = Offset(
          ((x + 0.5) / seg.width) * size.width,
          ((y + 0.5) / seg.height) * size.height,
        );
        canvas.drawCircle(center, baseRadius, fillPaint);
      }
    }
  }

  Color? _classColor(int classId) {
    if (classId == CityscapesClass.sky) return const Color(0x884DB8FF);
    if (classId == CityscapesClass.vegetation) return const Color(0x8862D26F);
    if (classId == CityscapesClass.terrain) return const Color(0x88E2A15D);
    if (classId == CityscapesClass.road) return const Color(0x887A7A7A);
    if (classId == CityscapesClass.building) return const Color(0x889C7B6A);
    return null;
  }

  @override
  bool shouldRepaint(covariant _SegmentationDotPainter oldDelegate) {
    return oldDelegate.result != result;
  }
}
