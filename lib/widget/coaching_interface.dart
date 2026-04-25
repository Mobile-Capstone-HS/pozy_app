import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:pose_camera_app/coaching/coaching_result.dart';

/// 각 카메라 모드에서 공통으로 사용하는 코칭 말풍선 위젯.
///
/// 사용 예시:
/// ```dart
/// Positioned(
///   top: 64,
///   right: 12,
///   child: IgnorePointer(
///     child: CoachingSpeechBubble(
///       guidance: '좋아요!',
///       subGuidance: '구도가 안정적입니다',
///       level: CoachingLevel.good,
///     ),
///   ),
/// )
/// ```
class CoachingSpeechBubble extends StatelessWidget {
  final String guidance;
  final String? subGuidance;
  final CoachingLevel level;
  final double? score;
  final DirectionHint directionHint;
  final LightDirection lightDirection;

  const CoachingSpeechBubble({
    super.key,
    required this.guidance,
    required this.subGuidance,
    required this.level,
    this.score,
    this.directionHint = DirectionHint.none,
    this.lightDirection = LightDirection.unknown,
  });

  /// [CoachingResult]로부터 생성하는 팩토리 생성자.
  factory CoachingSpeechBubble.fromResult(
    CoachingResult result, {
    Key? key,
  }) {
    return CoachingSpeechBubble(
      key: key,
      guidance: result.guidance,
      subGuidance: result.subGuidance,
      level: result.level,
      score: result.score,
      directionHint: result.directionHint,
      lightDirection: result.lightDirection,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      CoachingLevel.good => const Color(0xFF4ADE80),
      CoachingLevel.warning => const Color(0xFFFBBF24),
      CoachingLevel.caution => Colors.white,
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: IntrinsicWidth(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: level == CoachingLevel.good
                  ? color
                  : color.withValues(alpha: 0.35),
              width: level == CoachingLevel.good ? 2.0 : 1.5,
            ),
            boxShadow: level == CoachingLevel.good
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 점수 게이지 바
              if (score != null) ...[
                _ScoreGauge(score: score!, level: level),
                const SizedBox(height: 8),
              ],
              // 메인 코칭 텍스트 (방향 힌트 포함)
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (directionHint != DirectionHint.none) ...[
                    _DirectionArrow(hint: directionHint, color: color),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      guidance,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              // 서브 코칭 텍스트
              if (subGuidance != null) ...[
                const SizedBox(height: 4),
                Text(
                  subGuidance!,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
              // 광원 방향 표시
              if (lightDirection != LightDirection.unknown) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: _LightIndicator(direction: lightDirection, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 점수 게이지 바 — 0~100 점을 시각적으로 표시
class _ScoreGauge extends StatelessWidget {
  final double score;
  final CoachingLevel level;

  const _ScoreGauge({required this.score, required this.level});

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0.0, 100.0);
    final ratio = clamped / 100.0;

    // 점수에 따른 게이지 색상
    final gaugeColor = clamped >= 70
        ? const Color(0xFF4ADE80) // 녹색
        : clamped >= 40
            ? const Color(0xFFFBBF24) // 노란색
            : const Color(0xFFEF4444); // 빨간색

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 점수 텍스트
        Text(
          '${clamped.toInt()}점',
          style: TextStyle(
            color: gaugeColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        // 게이지 바
        Container(
          height: 4,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ratio,
            child: Container(
              decoration: BoxDecoration(
                color: gaugeColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 방향 힌트 화살표 아이콘
class _DirectionArrow extends StatelessWidget {
  final DirectionHint hint;
  final Color color;

  const _DirectionArrow({required this.hint, required this.color});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, double angle) = switch (hint) {
      DirectionHint.left => (Icons.arrow_back_rounded, 0.0),
      DirectionHint.right => (Icons.arrow_forward_rounded, 0.0),
      DirectionHint.up => (Icons.arrow_upward_rounded, 0.0),
      DirectionHint.down => (Icons.arrow_downward_rounded, 0.0),
      DirectionHint.back => (Icons.zoom_out_rounded, 0.0),
      DirectionHint.closer => (Icons.zoom_in_rounded, 0.0),
      DirectionHint.none => (Icons.circle, 0.0),
    };

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Transform.rotate(
        angle: angle * math.pi / 180,
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

/// 광원 방향 표시 — 작은 아이콘 + 텍스트
class _LightIndicator extends StatelessWidget {
  final LightDirection direction;
  final Color color;

  const _LightIndicator({required this.direction, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = switch (direction) {
      LightDirection.left => '☀ 왼쪽 광원',
      LightDirection.right => '☀ 오른쪽 광원',
      LightDirection.top => '☀ 상단 광원',
      LightDirection.bottom => '☀ 하단 광원',
      LightDirection.behind => '☀ 역광',
      LightDirection.unknown => '',
    };

    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.withValues(alpha: 0.7),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
