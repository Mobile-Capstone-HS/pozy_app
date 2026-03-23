import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/models/overlay_state.dart' as coach;
import 'package:pose_camera_app/features/composition/composition_policy.dart';

class CompositionPainter extends CustomPainter {
  const CompositionPainter({
    required this.policy,
    required this.overlayState,
  });

  final CompositionPolicy policy;
  final coach.OverlayState overlayState;

  @override
  void paint(Canvas canvas, Size size) {
    policy.paintGuide(canvas, size);

    if (overlayState.boundingBox != null) {
      final boxShadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2;

      final boxPaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRect(overlayState.boundingBox!, boxShadowPaint);
      canvas.drawRect(overlayState.boundingBox!, boxPaint);
    }

    final accent = overlayState.isPerfect
        ? Colors.greenAccent
        : overlayState.alignmentLevel == 'near'
            ? const Color(0xFFFFE082)
            : policy.accentColor;

    if (overlayState.subjectPosition != null && overlayState.targetPosition != null) {
      final linePaint = Paint()
        ..color = accent.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = overlayState.isPerfect ? 3.2 : 2.4;

      final guideGlowPaint = Paint()
        ..color = accent.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = overlayState.isPerfect ? 8 : 6;

      final subjectPaint = Paint()
        ..color = overlayState.isPerfect
            ? Colors.greenAccent
            : overlayState.alignmentLevel == 'near'
                ? const Color(0xFFFFE082)
                : Colors.redAccent
        ..style = PaintingStyle.fill;

      final targetOuter = Paint()
        ..color = accent.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7;

      final targetInner = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6;

      canvas.drawLine(
        overlayState.subjectPosition!,
        overlayState.targetPosition!,
        guideGlowPaint,
      );
      canvas.drawLine(
        overlayState.subjectPosition!,
        overlayState.targetPosition!,
        linePaint,
      );

      canvas.drawCircle(
        overlayState.targetPosition!,
        18,
        targetOuter,
      );
      canvas.drawCircle(
        overlayState.targetPosition!,
        10,
        targetInner,
      );

      canvas.drawCircle(
        overlayState.subjectPosition!,
        overlayState.isPerfect ? 10 : 8,
        subjectPaint,
      );
    } else if (overlayState.targetPosition != null) {
      final targetOuter = Paint()
        ..color = policy.accentColor.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7;

      final targetInner = Paint()
        ..color = policy.accentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6;

      canvas.drawCircle(overlayState.targetPosition!, 18, targetOuter);
      canvas.drawCircle(overlayState.targetPosition!, 10, targetInner);
    }
  }

  @override
  bool shouldRepaint(covariant CompositionPainter oldDelegate) {
    return oldDelegate.policy.runtimeType != policy.runtimeType ||
        oldDelegate.overlayState != overlayState;
  }
}