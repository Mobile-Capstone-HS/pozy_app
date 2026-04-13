import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/fastscnn_segmentor.dart';

class LandscapeCompositionOverlayPainter extends CustomPainter {
  final CompositionDecision? decision;

  const LandscapeCompositionOverlayPainter({required this.decision});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1.0
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
  bool shouldRepaint(covariant LandscapeCompositionOverlayPainter oldDelegate) {
    return oldDelegate.decision != decision;
  }
}

class LandscapeSegmentationDotPainter extends CustomPainter {
  final SegmentationResult? result;

  const LandscapeSegmentationDotPainter({required this.result});

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
  bool shouldRepaint(covariant LandscapeSegmentationDotPainter oldDelegate) {
    return oldDelegate.result != result;
  }
}
