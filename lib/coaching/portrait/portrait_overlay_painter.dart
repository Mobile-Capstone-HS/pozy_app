/// 인물 모드 시각적 가이드 오버레이 v2
///
/// 카메라 프리뷰 위에 키포인트, 가이드 화살표,
/// 어깨 라인, 삼분할 타겟 등을 그립니다.
///
/// v2 개선:
/// - 키포인트: 글로우 효과 + 외곽 링
/// - 스켈레톤: 그라데이션 + 부드러운 선
/// - 어깨 라인: 두께 변화 + 배경 그림자
/// - 삼분할 가이드: 더 세련된 타겟
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'portrait_scene_state.dart';

/// 오버레이에 필요한 포즈/얼굴 데이터
class OverlayData {
  final Offset? leftEye;
  final Offset? rightEye;
  final Offset? nose;
  final Offset? leftShoulder;
  final Offset? rightShoulder;
  final Offset? leftElbow;
  final Offset? rightElbow;
  final Offset? leftWrist;
  final Offset? rightWrist;
  final Offset? leftHip;
  final Offset? rightHip;

  final CoachingResult coaching;
  final ShotType shotType;
  final double eyeConfidence;
  final double shoulderConfidence;
  final Rect? faceGuideRect;
  final double? targetEyeLineY;
  final double? targetHeadroomTop;

  const OverlayData({
    this.leftEye,
    this.rightEye,
    this.nose,
    this.leftShoulder,
    this.rightShoulder,
    this.leftElbow,
    this.rightElbow,
    this.leftWrist,
    this.rightWrist,
    this.leftHip,
    this.rightHip,
    required this.coaching,
    this.shotType = ShotType.unknown,
    this.eyeConfidence = 0.0,
    this.shoulderConfidence = 0.0,
    this.faceGuideRect,
    this.targetEyeLineY,
    this.targetHeadroomTop,
  });
}

// ─── 색상 팔레트 ──────────────────────────────────────

class _Colors {
  static const cyan = Color(0xFF38BDF8);
  static const cyanGlow = Color(0x5538BDF8);
  static const cyanSoft = Color(0x8838BDF8);
  static const green = Color(0xFF4ADE80);
  static const greenSoft = Color(0xAA4ADE80);
  static const orange = Color(0xFFFB923C);
  static const red = Color(0xFFEF4444);
  static const yellow = Color(0xFFFBBF24);
  static const yellowSoft = Color(0xAAFBBF24);
  static const white = Color(0x33FFFFFF);
  static const whiteMed = Color(0x55FFFFFF);
}

class PortraitOverlayPainter extends CustomPainter {
  final OverlayData data;

  PortraitOverlayPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    _drawThirdsGrid(canvas, size);
    _drawFaceGuide(canvas, size);
    _drawBodyOutline(canvas, size);
    _drawKeypoints(canvas, size);
    _drawShoulderLine(canvas, size);
    _drawEyeGuide(canvas, size);
  }

  // ─── 삼분할 그리드 ────────────────────────────────

  void _drawThirdsGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = _Colors.white
      ..strokeWidth = 0.5;

    final dx1 = size.width / 3;
    final dx2 = size.width * 2 / 3;
    final dy1 = size.height / 3;
    final dy2 = size.height * 2 / 3;

    canvas.drawLine(Offset(dx1, 0), Offset(dx1, size.height), gridPaint);
    canvas.drawLine(Offset(dx2, 0), Offset(dx2, size.height), gridPaint);
    canvas.drawLine(Offset(0, dy1), Offset(size.width, dy1), gridPaint);
    canvas.drawLine(Offset(0, dy2), Offset(size.width, dy2), gridPaint);

    // 교차점 타겟 (미니멀한 +)
    final targetPaint = Paint()
      ..color = _Colors.whiteMed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    for (final pt in [
      Offset(dx1, dy1), Offset(dx2, dy1),
      Offset(dx1, dy2), Offset(dx2, dy2),
    ]) {
      canvas.drawLine(pt + const Offset(-10, 0), pt + const Offset(10, 0), targetPaint);
      canvas.drawLine(pt + const Offset(0, -10), pt + const Offset(0, 10), targetPaint);
    }
  }

  // ─── 키포인트 (글로우 + 링) ───────────────────────

  void _drawKeypoints(Canvas canvas, Size size) {
    // 메인 포인트 (눈, 코) — 큰 글로우
    _drawGlowPoint(canvas, size, data.nose, radius: 5, isMain: true);
    _drawGlowPoint(canvas, size, data.leftEye, radius: 5, isMain: true);
    _drawGlowPoint(canvas, size, data.rightEye, radius: 5, isMain: true);

    // 서브 포인트 (어깨~엉덩이) — 작은 글로우
    for (final pt in [
      data.leftShoulder, data.rightShoulder,
      data.leftElbow, data.rightElbow,
      data.leftWrist, data.rightWrist,
      data.leftHip, data.rightHip,
    ]) {
      _drawGlowPoint(canvas, size, pt, radius: 3.5, isMain: false);
    }
  }

  void _drawGlowPoint(Canvas canvas, Size size, Offset? point, {
    required double radius,
    required bool isMain,
  }) {
    if (point == null) return;
    final pos = Offset(point.dx * size.width, point.dy * size.height);

    // 글로우 (블러 효과)
    canvas.drawCircle(
      pos, radius + 4,
      Paint()
        ..color = isMain ? _Colors.cyanGlow : const Color(0x3338BDF8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 외곽 링
    canvas.drawCircle(
      pos, radius + 1.5,
      Paint()
        ..color = isMain ? _Colors.cyanSoft : const Color(0x5538BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 중심 점
    canvas.drawCircle(
      pos, radius,
      Paint()
        ..color = isMain ? _Colors.cyan : _Colors.cyanSoft
        ..style = PaintingStyle.fill,
    );
  }

  // ─── 어깨 라인 (그림자 + 두께 변화) ──────────────

  void _drawShoulderLine(Canvas canvas, Size size) {
    if (data.leftShoulder == null || data.rightShoulder == null) return;
    if (data.shoulderConfidence < 0.5) return;

    final left = Offset(
      data.leftShoulder!.dx * size.width,
      data.leftShoulder!.dy * size.height,
    );
    final right = Offset(
      data.rightShoulder!.dx * size.width,
      data.rightShoulder!.dy * size.height,
    );

    final dy = right.dy - left.dy;
    final dx = right.dx - left.dx;
    final angle = math.atan2(dy, dx) * 180 / math.pi;

    final Color lineColor;
    final String label;
    if (angle.abs() < 3) {
      lineColor = _Colors.orange;
      label = '${angle.toStringAsFixed(1)}°';
    } else if (angle.abs() < 25) {
      lineColor = _Colors.green;
      label = '${angle.toStringAsFixed(1)}° ✓';
    } else {
      lineColor = _Colors.red;
      label = '${angle.toStringAsFixed(1)}°';
    }

    final extend = (right - left) * 0.12;

    // 그림자
    canvas.drawLine(
      left - extend, right + extend,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );

    // 메인 라인
    canvas.drawLine(
      left - extend, right + extend,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // 양 끝 점
    for (final pt in [left, right]) {
      canvas.drawCircle(pt, 4, Paint()..color = lineColor);
    }

    // 각도 라벨
    final mid = Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2);
    _drawLabel(canvas, label, mid + const Offset(0, -20), lineColor);
  }

  // ─── 눈 → 삼분할 가이드 ──────────────────────────

  void _drawEyeGuide(Canvas canvas, Size size) {
    if (data.leftEye == null || data.rightEye == null) return;
    if (data.eyeConfidence < 0.5) return;

    final eyeMid = Offset(
      (data.leftEye!.dx + data.rightEye!.dx) / 2 * size.width,
      (data.leftEye!.dy + data.rightEye!.dy) / 2 * size.height,
    );

    final thirdLineY = size.height / 3;
    final deviation = (eyeMid.dy / size.height - 1.0 / 3.0).abs();

    if (deviation < 0.05) {
      // 정확한 위치 — 초록 체크
      _drawCheckMark(canvas, eyeMid);
    } else if (deviation < 0.25) {
      // 유도 화살표
      _drawGuideArrow(canvas, eyeMid, thirdLineY);
    }
  }

  void _drawFaceGuide(Canvas canvas, Size size) {
    final rect = data.faceGuideRect;
    if (rect != null) {
      final r = Rect.fromLTWH(
        rect.left * size.width,
        rect.top * size.height,
        rect.width * size.width,
        rect.height * size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()
          ..color = const Color(0x2238BDF8)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()
          ..color = _Colors.cyanSoft
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    final eyeLineY = data.targetEyeLineY;
    if (eyeLineY != null) {
      final y = eyeLineY * size.height;
      canvas.drawLine(
        Offset(size.width * 0.12, y),
        Offset(size.width * 0.88, y),
        Paint()
          ..color = const Color(0x4438BDF8)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    final headroomTop = data.targetHeadroomTop;
    if (headroomTop != null) {
      final y = headroomTop * size.height;
      canvas.drawLine(
        Offset(size.width * 0.2, y),
        Offset(size.width * 0.8, y),
        Paint()
          ..color = const Color(0x33FFFFFF)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawCheckMark(Canvas canvas, Offset center) {
    // 글로우 원
    canvas.drawCircle(
      center, 18,
      Paint()
        ..color = const Color(0x334ADE80)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 외곽 원
    canvas.drawCircle(
      center, 14,
      Paint()
        ..color = _Colors.greenSoft
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // 체크마크
    final path = Path()
      ..moveTo(center.dx - 5, center.dy + 1)
      ..lineTo(center.dx - 1, center.dy + 5)
      ..lineTo(center.dx + 7, center.dy - 5);
    canvas.drawPath(
      path,
      Paint()
        ..color = _Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawGuideArrow(Canvas canvas, Offset eyeMid, double targetY) {
    final direction = targetY < eyeMid.dy ? -1.0 : 1.0;

    final arrowPaint = Paint()
      ..color = _Colors.yellowSoft
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 점선 그리기
    const dashLen = 5.0;
    const gapLen = 4.0;
    var currentY = eyeMid.dy + direction * 22;

    while ((direction > 0 && currentY < targetY - 12) ||
           (direction < 0 && currentY > targetY + 12)) {
      final endY = currentY + direction * dashLen;
      canvas.drawLine(
        Offset(eyeMid.dx, currentY),
        Offset(eyeMid.dx, endY),
        arrowPaint,
      );
      currentY = endY + direction * gapLen;
    }

    // 화살표 머리
    final tipY = targetY + direction * 6;
    final headPaint = Paint()
      ..color = _Colors.yellow
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(eyeMid.dx, tipY),
      Offset(eyeMid.dx - 7, tipY - direction * 9),
      headPaint,
    );
    canvas.drawLine(
      Offset(eyeMid.dx, tipY),
      Offset(eyeMid.dx + 7, tipY - direction * 9),
      headPaint,
    );

    // 삼분할 라인 하이라이트
    canvas.drawLine(
      Offset(eyeMid.dx - 25, targetY),
      Offset(eyeMid.dx + 25, targetY),
      Paint()
        ..color = const Color(0x55FBBF24)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  // ─── 스켈레톤 (그라데이션 선) ─────────────────────

  void _drawBodyOutline(Canvas canvas, Size size) {
    // 그림자 레이어
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // 메인 라인
    final linePaint = Paint()
      ..color = const Color(0x6638BDF8)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    void drawBone(Offset? a, Offset? b) {
      if (a == null || b == null) return;
      final posA = Offset(a.dx * size.width, a.dy * size.height);
      final posB = Offset(b.dx * size.width, b.dy * size.height);
      canvas.drawLine(posA, posB, shadowPaint);
      canvas.drawLine(posA, posB, linePaint);
    }

    // 얼굴
    drawBone(data.leftEye, data.nose);
    drawBone(data.rightEye, data.nose);

    // 상체
    drawBone(data.leftShoulder, data.rightShoulder);
    drawBone(data.leftShoulder, data.leftElbow);
    drawBone(data.leftElbow, data.leftWrist);
    drawBone(data.rightShoulder, data.rightElbow);
    drawBone(data.rightElbow, data.rightWrist);

    // 몸통
    drawBone(data.leftShoulder, data.leftHip);
    drawBone(data.rightShoulder, data.rightHip);
    drawBone(data.leftHip, data.rightHip);
  }

  // ─── 라벨 헬퍼 ───────────────────────────────────

  void _drawLabel(
    Canvas canvas, String text, Offset position, Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 6),
            Shadow(color: Colors.black, blurRadius: 3),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 배경
    final rect = Rect.fromCenter(
      center: position,
      width: tp.width + 12,
      height: tp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    tp.paint(canvas, position - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant PortraitOverlayPainter oldDelegate) => true;
}
