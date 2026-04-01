import 'package:flutter/material.dart';

import '../models/composition_candidate.dart';
import '../services/composition_feedback_service.dart';

/// Paints an AR-style composition overlay on the camera preview.
class CompositionOverlayPainter extends CustomPainter {
  final CompositionCandidate? activeCandidate;
  final FeedbackResult feedback;
  final bool showDebug;
  final double? tiltAngle;

  /// One-line scorer status string from [ModelCompositionScorer.debugSummary].
  /// Rendered below the main debug label when non-null.
  final String? scorerDebug;

  static const Color _guideColor = Color(0x66FFFFFF);
  static const Color _almostColor = Color(0xFFFFD700);
  static const Color _goodColor = Color(0xFF4ADE80);
  static const Color _dimColor = Color(0x66000000);

  const CompositionOverlayPainter({
    required this.activeCandidate,
    required this.feedback,
    this.showDebug = false,
    this.tiltAngle,
    this.scorerDebug,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final active = activeCandidate;

    if (active == null || feedback.state == ReadinessState.guide) {
      _drawGuideState(canvas, size);
    } else {
      final Color feedbackColor;
      double strokeWidth = 2.0;
      switch (feedback.state) {
        case ReadinessState.almost:
          feedbackColor = _almostColor;
          break;
        case ReadinessState.good:
          feedbackColor = _goodColor;
          strokeWidth = 3.0; // Make border thicker when 'good'
          break;
        case ReadinessState.guide:
          feedbackColor = _guideColor;
          break;
      }

      final rn = active.renderRect;
      final px = Rect.fromLTRB(
        rn.left * size.width,
        rn.top * size.height,
        rn.right * size.width,
        rn.bottom * size.height,
      );

      _drawDimming(canvas, size, px);
      _drawCropBorder(canvas, px, feedbackColor, strokeWidth);
      _drawCornerBrackets(canvas, px, feedbackColor, strokeWidth);
      _drawThirdsGrid(canvas, px, feedbackColor.withAlpha(76)); // 0.3 * 255 = 76.5

      if (showDebug) {
        _drawDebugLabel(canvas, px, active, feedback);
        if (scorerDebug != null) {
          _drawScorerDebug(canvas, px, scorerDebug!);
        }
      }
    }

    if (tiltAngle != null) {
      _drawLevelGuide(canvas, size, tiltAngle!);
    }
  }

  void _drawGuideState(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final width = size.width * 0.8;
    final height = width / (3 / 2);
    final rect = Rect.fromCenter(center: center, width: width, height: height);
    final paint = Paint()
      ..color = _guideColor.withAlpha(128) // 0.5 * 255 = 127.5
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(rect, paint);
  }

  void _drawDimming(Canvas canvas, Size size, Rect crop) {
    final paint = Paint()..color = _dimColor;
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, crop.top), paint);
    canvas.drawRect(
        Rect.fromLTRB(0, crop.bottom, size.width, size.height), paint);
    canvas.drawRect(Rect.fromLTRB(0, crop.top, crop.left, crop.bottom), paint);
    canvas.drawRect(
        Rect.fromLTRB(crop.right, crop.top, size.width, crop.bottom), paint);
  }

  void _drawCropBorder(Canvas canvas, Rect rect, Color color, double width) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0x80000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 2,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width + 1.0
      ..strokeCap = StrokeCap.square;
    const len = 18.0;
    canvas.drawLine(
        Offset(rect.left, rect.top + len), Offset(rect.left, rect.top), paint);
    canvas.drawLine(
        Offset(rect.left, rect.top), Offset(rect.left + len, rect.top), paint);
    canvas.drawLine(Offset(rect.right - len, rect.top),
        Offset(rect.right, rect.top), paint);
    canvas.drawLine(Offset(rect.right, rect.top),
        Offset(rect.right, rect.top + len), paint);
    canvas.drawLine(Offset(rect.left, rect.bottom - len),
        Offset(rect.left, rect.bottom), paint);
    canvas.drawLine(Offset(rect.left, rect.bottom),
        Offset(rect.left + len, rect.bottom), paint);
    canvas.drawLine(Offset(rect.right - len, rect.bottom),
        Offset(rect.right, rect.bottom), paint);
    canvas.drawLine(Offset(rect.right, rect.bottom),
        Offset(rect.right, rect.bottom - len), paint);
  }

  void _drawThirdsGrid(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.8;
    final dx1 = rect.left + rect.width / 3;
    final dx2 = rect.left + rect.width * 2 / 3;
    final dy1 = rect.top + rect.height / 3;
    final dy2 = rect.top + rect.height * 2 / 3;
    canvas.drawLine(Offset(dx1, rect.top), Offset(dx1, rect.bottom), paint);
    canvas.drawLine(Offset(dx2, rect.top), Offset(dx2, rect.bottom), paint);
    canvas.drawLine(Offset(rect.left, dy1), Offset(rect.right, dy1), paint);
    canvas.drawLine(Offset(rect.left, dy2), Offset(rect.right, dy2), paint);
  }

  void _drawDebugLabel(
      Canvas canvas, Rect rect, CompositionCandidate c, FeedbackResult feedback) {
    final stateStr = feedback.state.toString().split('.').last;
    final text =
        'Align: ${feedback.alignmentScore.toStringAsFixed(2)} | State: $stateStr | Ready: ${feedback.isShutterReady}';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(rect.left + 4, (rect.bottom + 6).clamp(0, double.infinity)));
  }

  /// Renders the scorer status string (model mode, inference time, fallback).
  void _drawScorerDebug(Canvas canvas, Rect rect, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFFAAFFAA), // green tint — distinct from the main label
          fontSize: 9,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Render one text-height below the main debug label (which sits at rect.bottom + 4).
    tp.paint(canvas,
        Offset(rect.left + 4, (rect.bottom + 16).clamp(0, double.infinity)));
  }

  void _drawLevelGuide(Canvas canvas, Size size, double tilt) {
    final cy = size.height / 2;
    final paint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(size.width * 0.38, cy), Offset(size.width * 0.62, cy), paint);
    canvas.drawCircle(
      Offset(size.width / 2, cy),
      3,
      Paint()..color = const Color(0xAAFFFFFF),
    );
  }
  
  @override
  bool shouldRepaint(covariant CompositionOverlayPainter old) {
    return old.activeCandidate != activeCandidate ||
        old.feedback != feedback ||
        old.showDebug != showDebug ||
        old.tiltAngle != tiltAngle ||
        old.scorerDebug != scorerDebug;
  }
}
