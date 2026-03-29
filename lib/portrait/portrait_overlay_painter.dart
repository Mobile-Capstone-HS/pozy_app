/// 인물 모드 시각적 가이드 오버레이
///
/// 카메라 프리뷰 위에 키포인트, 가이드 화살표,
/// 어깨 라인, 삼분할 타겟 등을 그립니다.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'portrait_scene_state.dart';

/// 오버레이에 필요한 포즈/얼굴 데이터
class OverlayData {
  // 키포인트 좌표 (정규화 0~1)
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

  // 코칭 상태
  final CoachingResult coaching;
  final ShotType shotType;

  // 키포인트 신뢰도
  final double eyeConfidence;
  final double shoulderConfidence;

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
  });
}

class PortraitOverlayPainter extends CustomPainter {
  final OverlayData data;

  PortraitOverlayPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    _drawThirdsGrid(canvas, size);
    _drawKeypoints(canvas, size);
    _drawShoulderLine(canvas, size);
    _drawEyeGuide(canvas, size);
    _drawBodyOutline(canvas, size);
  }

  /// 삼분할 그리드 + 교차점 타겟
  void _drawThirdsGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 0.5;

    final dx1 = size.width / 3;
    final dx2 = size.width * 2 / 3;
    final dy1 = size.height / 3;
    final dy2 = size.height * 2 / 3;

    canvas.drawLine(Offset(dx1, 0), Offset(dx1, size.height), gridPaint);
    canvas.drawLine(Offset(dx2, 0), Offset(dx2, size.height), gridPaint);
    canvas.drawLine(Offset(0, dy1), Offset(size.width, dy1), gridPaint);
    canvas.drawLine(Offset(0, dy2), Offset(size.width, dy2), gridPaint);

    // 교차점에 타겟 표시
    final targetPaint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final point in [
      Offset(dx1, dy1),
      Offset(dx2, dy1),
      Offset(dx1, dy2),
      Offset(dx2, dy2),
    ]) {
      canvas.drawCircle(point, 8, targetPaint);
      // 십자 표시
      canvas.drawLine(
        point + const Offset(-12, 0),
        point + const Offset(12, 0),
        targetPaint,
      );
      canvas.drawLine(
        point + const Offset(0, -12),
        point + const Offset(0, 12),
        targetPaint,
      );
    }
  }

  /// 감지된 키포인트 표시
  void _drawKeypoints(Canvas canvas, Size size) {
    final pointPaint = Paint()
      ..color = const Color(0xCC38BDF8) // 하늘색
      ..style = PaintingStyle.fill;

    final smallPointPaint = Paint()
      ..color = const Color(0x9938BDF8)
      ..style = PaintingStyle.fill;

    void drawPoint(Offset? point, {bool isMain = false}) {
      if (point == null) return;
      final pos = Offset(point.dx * size.width, point.dy * size.height);
      canvas.drawCircle(pos, isMain ? 6 : 4, isMain ? pointPaint : smallPointPaint);
    }

    // 눈, 코 (메인 포인트)
    drawPoint(data.leftEye, isMain: true);
    drawPoint(data.rightEye, isMain: true);
    drawPoint(data.nose, isMain: true);

    // 어깨, 팔꿈치, 손목, 엉덩이 (서브 포인트)
    drawPoint(data.leftShoulder);
    drawPoint(data.rightShoulder);
    drawPoint(data.leftElbow);
    drawPoint(data.rightElbow);
    drawPoint(data.leftWrist);
    drawPoint(data.rightWrist);
    drawPoint(data.leftHip);
    drawPoint(data.rightHip);
  }

  /// 어깨 라인 표시 (기울기 시각화)
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

    // 어깨 각도 계산
    final dy = right.dy - left.dy;
    final dx = right.dx - left.dx;
    final angle = math.atan2(dy, dx) * 180 / math.pi;

    // 각도에 따라 색상 변경
    final Color lineColor;
    if (angle.abs() < 3) {
      // 너무 수평 — 주황 (개선 필요)
      lineColor = const Color(0xCCFB923C);
    } else if (angle.abs() < 20) {
      // 적절한 기울기 — 초록
      lineColor = const Color(0xCC4ADE80);
    } else {
      // 너무 기울어짐 — 빨강
      lineColor = const Color(0xCCEF4444);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // 어깨 라인 양쪽으로 약간 연장
    final extend = (right - left) * 0.15;
    canvas.drawLine(left - extend, right + extend, linePaint);

    // 각도 텍스트 표시
    final midPoint = Offset((left.dx + right.dx) / 2, (left.dy + right.dy) / 2);
    _drawText(
      canvas,
      '${angle.toStringAsFixed(1)}°',
      midPoint + const Offset(0, -18),
      lineColor,
      11,
    );
  }

  /// 눈 위치 → 삼분할 라인 가이드
  void _drawEyeGuide(Canvas canvas, Size size) {
    if (data.leftEye == null || data.rightEye == null) return;
    if (data.eyeConfidence < 0.5) return;

    // 눈 중심점
    final eyeMid = Offset(
      (data.leftEye!.dx + data.rightEye!.dx) / 2 * size.width,
      (data.leftEye!.dy + data.rightEye!.dy) / 2 * size.height,
    );

    // 상단 1/3 라인
    final thirdLineY = size.height / 3;

    // 눈과 삼분할 라인의 거리
    final distance = (eyeMid.dy - thirdLineY).abs();
    final deviation = (eyeMid.dy / size.height - 1.0 / 3.0).abs();

    if (deviation < 0.05) {
      // 거의 정확한 위치 — 초록 체크 표시
      final checkPaint = Paint()
        ..color = const Color(0xCC4ADE80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(eyeMid, 16, checkPaint);

      // 체크마크
      final path = Path()
        ..moveTo(eyeMid.dx - 6, eyeMid.dy)
        ..lineTo(eyeMid.dx - 1, eyeMid.dy + 5)
        ..lineTo(eyeMid.dx + 7, eyeMid.dy - 5);
      canvas.drawPath(path, checkPaint);
    } else if (deviation < 0.25) {
      // 유도 화살표 — 눈에서 삼분할 라인 방향으로
      final arrowPaint = Paint()
        ..color = const Color(0xAAFBBF24) // 노란색
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final targetY = thirdLineY;
      final targetPoint = Offset(eyeMid.dx, targetY);

      // 점선 화살표
      final dashLength = 6.0;
      final gapLength = 4.0;
      final direction = targetY < eyeMid.dy ? -1.0 : 1.0;
      var currentY = eyeMid.dy + direction * 20; // 눈에서 약간 떨어진 곳부터

      while ((direction > 0 && currentY < targetY - 10) ||
             (direction < 0 && currentY > targetY + 10)) {
        final endY = currentY + direction * dashLength;
        canvas.drawLine(
          Offset(eyeMid.dx, currentY),
          Offset(eyeMid.dx, endY),
          arrowPaint,
        );
        currentY = endY + direction * gapLength;
      }

      // 화살표 머리
      final arrowTip = Offset(eyeMid.dx, targetY + direction * 5);
      final arrowHeadPaint = Paint()
        ..color = const Color(0xAAFBBF24)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        arrowTip,
        arrowTip + Offset(-8, -direction * 10),
        arrowHeadPaint,
      );
      canvas.drawLine(
        arrowTip,
        arrowTip + Offset(8, -direction * 10),
        arrowHeadPaint,
      );

      // 삼분할 라인에 타겟 강조
      final targetHighlight = Paint()
        ..color = const Color(0x66FBBF24)
        ..strokeWidth = 1.5;

      canvas.drawLine(
        Offset(eyeMid.dx - 30, targetY),
        Offset(eyeMid.dx + 30, targetY),
        targetHighlight,
      );
    }
  }

  /// 몸통 외곽선 (스켈레톤)
  void _drawBodyOutline(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0x4438BDF8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    void drawConnection(Offset? a, Offset? b) {
      if (a == null || b == null) return;
      final posA = Offset(a.dx * size.width, a.dy * size.height);
      final posB = Offset(b.dx * size.width, b.dy * size.height);
      canvas.drawLine(posA, posB, linePaint);
    }

    // 얼굴
    drawConnection(data.leftEye, data.nose);
    drawConnection(data.rightEye, data.nose);

    // 상체
    drawConnection(data.leftShoulder, data.rightShoulder);
    drawConnection(data.leftShoulder, data.leftElbow);
    drawConnection(data.leftElbow, data.leftWrist);
    drawConnection(data.rightShoulder, data.rightElbow);
    drawConnection(data.rightElbow, data.rightWrist);

    // 몸통
    drawConnection(data.leftShoulder, data.leftHip);
    drawConnection(data.rightShoulder, data.rightHip);
    drawConnection(data.leftHip, data.rightHip);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    Color color,
    double fontSize,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      position - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant PortraitOverlayPainter oldDelegate) {
    return true; // 매 프레임 다시 그림
  }
}
