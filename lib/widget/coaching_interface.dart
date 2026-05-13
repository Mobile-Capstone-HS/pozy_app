import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:pose_camera_app/coaching/coaching_result.dart';

class CoachingSpeechBubble extends StatelessWidget {
  final String guidance;
  final String? subGuidance;
  final CoachingLevel level;
  final double? score;
  final DirectionHint directionHint;
  final LightDirection lightDirection;
  final double? maxWidth;

  const CoachingSpeechBubble({
    super.key,
    required this.guidance,
    required this.subGuidance,
    required this.level,
    this.score,
    this.directionHint = DirectionHint.none,
    this.lightDirection = LightDirection.unknown,
    this.maxWidth,
  });

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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final accent = switch (level) {
      CoachingLevel.good => const Color(0xFF22C55E),
      CoachingLevel.warning => const Color(0xFFFBBF24),
      CoachingLevel.caution => const Color(0xFFBFDBFE),
    };
    final borderColor = switch (level) {
      CoachingLevel.good => accent.withValues(alpha: 0.78),
      CoachingLevel.warning => accent.withValues(alpha: 0.82),
      CoachingLevel.caution => accent.withValues(alpha: 0.42),
    };
    final resolvedMaxWidth = maxWidth ?? math.min(screenWidth * 0.58, 280.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: resolvedMaxWidth),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 2,
              bottom: 2,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (score != null) ...[
                    _ScoreGauge(score: score!, accent: accent),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(top: 5),
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.28),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      if (directionHint != DirectionHint.none) ...[
                        const SizedBox(width: 6),
                        _DirectionArrow(hint: directionHint, color: accent),
                      ],
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          guidance,
                          textAlign: TextAlign.right,
                          softWrap: true,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.98),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subGuidance != null && subGuidance!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subGuidance!,
                      textAlign: TextAlign.right,
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (lightDirection != LightDirection.unknown) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _LightIndicator(
                        direction: lightDirection,
                        accent: accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreGauge extends StatelessWidget {
  final double score;
  final Color accent;

  const _ScoreGauge({required this.score, required this.accent});

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0.0, 100.0);
    final ratio = clamped / 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${clamped.toInt()}점',
          style: TextStyle(
            color: accent,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          height: 3,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ratio,
            child: Container(
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DirectionArrow extends StatelessWidget {
  final DirectionHint hint;
  final Color color;

  const _DirectionArrow({required this.hint, required this.color});

  @override
  Widget build(BuildContext context) {
    final icon = switch (hint) {
      DirectionHint.left => Icons.arrow_back_rounded,
      DirectionHint.right => Icons.arrow_forward_rounded,
      DirectionHint.up => Icons.arrow_upward_rounded,
      DirectionHint.down => Icons.arrow_downward_rounded,
      DirectionHint.back => Icons.zoom_out_rounded,
      DirectionHint.closer => Icons.zoom_in_rounded,
      DirectionHint.none => Icons.circle,
    };

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color, size: 13),
    );
  }
}

class _LightIndicator extends StatelessWidget {
  final LightDirection direction;
  final Color accent;

  const _LightIndicator({required this.direction, required this.accent});

  @override
  Widget build(BuildContext context) {
    final label = switch (direction) {
      LightDirection.left => '왼쪽 빛',
      LightDirection.right => '오른쪽 빛',
      LightDirection.top => '위쪽 빛',
      LightDirection.bottom => '아래쪽 빛',
      LightDirection.behind => '역광',
      LightDirection.unknown => '',
    };

    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.76),
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
