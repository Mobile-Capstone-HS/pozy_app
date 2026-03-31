import 'package:flutter/material.dart';

import '../models/composition_candidate.dart';

/// Paints an AR-style composition overlay on the camera preview.
///
/// Visual elements:
/// - Dimming outside the active crop rect
/// - Gold border with corner brackets
/// - Rule-of-thirds grid inside the crop
/// - Optional debug info (candidate label + score)
/// - Optional debug view of runner-up candidates
/// - Optional level guide line (placeholder – no IMU integration yet)
class CompositionOverlayPainter extends CustomPainter {
  final CompositionCandidate? activeCandidate;
  final List<CompositionCandidate>? allCandidates;
  final bool showDebug;
  final bool showLevelGuide;

  static const Color _gold = Color(0xFFFFD700);
  static const Color _goldFaint = Color(0x50FFD700);
  static const Color _dimColor = Color(0x66000000);

  const CompositionOverlayPainter({
    required this.activeCandidate,
    this.allCandidates,
    this.showDebug = false,
    this.showLevelGuide = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final active = activeCandidate;
    if (active == null) return;

    final rn = active.renderRect;
    final px = Rect.fromLTRB(
      rn.left * size.width,
      rn.top * size.height,
      rn.right * size.width,
      rn.bottom * size.height,
    );

    // Debug: runner-up candidates (drawn first so active is on top).
    if (showDebug) {
      _drawRunnerUps(canvas, size, allCandidates);
    }

    // Dimming regions outside the active crop.
    _drawDimming(canvas, size, px);

    // Active crop border.
    _drawCropBorder(canvas, px);

    // Corner bracket marks.
    _drawCornerBrackets(canvas, px);

    // Rule-of-thirds grid inside the crop.
    _drawThirdsGrid(canvas, px);

    // Debug: label + score.
    if (showDebug) {
      _drawDebugLabel(canvas, px, active);
    }

    // Level guide.
    if (showLevelGuide) {
      _drawLevelGuide(canvas, size);
    }
  }

  void _drawDimming(Canvas canvas, Size size, Rect crop) {
    final paint = Paint()..color = _dimColor;
    // Top strip.
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, crop.top), paint);
    // Bottom strip.
    canvas.drawRect(
        Rect.fromLTRB(0, crop.bottom, size.width, size.height), paint);
    // Left strip.
    canvas.drawRect(
        Rect.fromLTRB(0, crop.top, crop.left, crop.bottom), paint);
    // Right strip.
    canvas.drawRect(
        Rect.fromLTRB(crop.right, crop.top, size.width, crop.bottom), paint);
  }

  void _drawCropBorder(Canvas canvas, Rect rect) {
    // Soft shadow stroke behind the accent.
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0x80000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    // Gold accent stroke.
    canvas.drawRect(
      rect,
      Paint()
        ..color = _gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.square;

    const len = 18.0;

    // Top-left
    canvas.drawLine(
        Offset(rect.left, rect.top + len), Offset(rect.left, rect.top), paint);
    canvas.drawLine(
        Offset(rect.left, rect.top), Offset(rect.left + len, rect.top), paint);
    // Top-right
    canvas.drawLine(Offset(rect.right - len, rect.top),
        Offset(rect.right, rect.top), paint);
    canvas.drawLine(Offset(rect.right, rect.top),
        Offset(rect.right, rect.top + len), paint);
    // Bottom-left
    canvas.drawLine(Offset(rect.left, rect.bottom - len),
        Offset(rect.left, rect.bottom), paint);
    canvas.drawLine(Offset(rect.left, rect.bottom),
        Offset(rect.left + len, rect.bottom), paint);
    // Bottom-right
    canvas.drawLine(Offset(rect.right - len, rect.bottom),
        Offset(rect.right, rect.bottom), paint);
    canvas.drawLine(Offset(rect.right, rect.bottom),
        Offset(rect.right, rect.bottom - len), paint);
  }

  void _drawThirdsGrid(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = _goldFaint
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

  void _drawDebugLabel(Canvas canvas, Rect rect, CompositionCandidate c) {
    final text =
        '${c.label}  ${(c.score * 100).toStringAsFixed(0)}%';
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _gold,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, Offset(rect.left + 4, (rect.bottom + 4).clamp(0, double.infinity)));
  }

  void _drawRunnerUps(
      Canvas canvas, Size size, List<CompositionCandidate>? all) {
    if (all == null) return;
    final paint = Paint()
      ..color = const Color(0x28FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Draw up to 4 runner-up candidates (skip the best one).
    for (final c in all.skip(1).take(4)) {
      final r = c.normalizedRect;
      canvas.drawRect(
        Rect.fromLTRB(
          r.left * size.width,
          r.top * size.height,
          r.right * size.width,
          r.bottom * size.height,
        ),
        paint,
      );
    }
  }

  void _drawLevelGuide(Canvas canvas, Size size) {
    // Placeholder: a subtle horizon line through the vertical midpoint.
    final cy = size.height / 2;
    final paint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(size.width * 0.38, cy), Offset(size.width * 0.62, cy), paint);
    // Centre dot.
    canvas.drawCircle(
      Offset(size.width / 2, cy),
      3,
      Paint()..color = const Color(0xAAFFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant CompositionOverlayPainter old) {
    return old.activeCandidate != activeCandidate || old.showDebug != showDebug;
  }
}
