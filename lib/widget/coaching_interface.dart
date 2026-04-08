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

  const CoachingSpeechBubble({
    super.key,
    required this.guidance,
    required this.subGuidance,
    required this.level,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      CoachingLevel.good => const Color(0xFF4ADE80),
      CoachingLevel.warning => const Color(0xFFFBBF24),
      CoachingLevel.caution => Colors.white,
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            guidance,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
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
        ],
      ),
    );
  }
}
