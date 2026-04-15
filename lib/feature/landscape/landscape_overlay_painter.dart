import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pose_camera_app/composition/composition_rule.dart';
import 'package:pose_camera_app/composition/composition_rule_registry.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/fastscnn_segmentor.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class LandscapeCompositionOverlayPainter extends CustomPainter {
  final CompositionDecision? decision;
  final LandscapeOverlayAdvice advice;
  final double? leadingEntryX;
  final double? leadingTargetX;

  const LandscapeCompositionOverlayPainter({
    required this.decision,
    this.advice = const LandscapeOverlayAdvice.none(),
    this.leadingEntryX,
    this.leadingTargetX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final thirdsRule =
        CompositionRuleRegistry.of(CompositionRuleType.ruleOfThirds);
    thirdsRule.paintOverlay(
      canvas,
      bounds,
      color: const Color(0x33FFFFFF),
      strokeWidth: 1.0,
    );

    if (advice.showHorizonGuide && advice.targetHorizonY != null) {
      final guideY = size.height * advice.targetHorizonY!;
      final guidePaint = Paint()
        ..color = _guideColorForState(advice.overlayState)
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, guideY), Offset(size.width, guideY), guidePaint);
    }

    if (leadingEntryX != null && leadingTargetX != null) {
      final start = Offset(
        size.width * leadingEntryX!,
        size.height * 0.92,
      );
      final end = Offset(
        size.width * leadingTargetX!,
        size.height * 0.32,
      );
      final linePaint = Paint()
        ..color = const Color(0xAA7DD3FC)
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      final anchorPaint = Paint()..color = const Color(0xCC7DD3FC);

      canvas.drawLine(start, end, linePaint);
      canvas.drawCircle(start, 5.0, anchorPaint);
      canvas.drawCircle(end, 4.2, anchorPaint);
    }
  }

  Color _guideColorForState(OverlayGuidanceState state) {
    switch (state) {
      case OverlayGuidanceState.aligned:
        return const Color(0xAA76E39B);
      case OverlayGuidanceState.adjustUp:
      case OverlayGuidanceState.adjustDown:
        return const Color(0xAAFFD76A);
      case OverlayGuidanceState.unstable:
      case OverlayGuidanceState.searching:
        return const Color(0x88FFFFFF);
      case OverlayGuidanceState.hidden:
        return const Color(0x00FFFFFF);
    }
  }

  @override
  bool shouldRepaint(covariant LandscapeCompositionOverlayPainter oldDelegate) {
    return oldDelegate.decision != decision ||
        oldDelegate.advice != advice ||
        oldDelegate.leadingEntryX != leadingEntryX ||
        oldDelegate.leadingTargetX != leadingTargetX;
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
