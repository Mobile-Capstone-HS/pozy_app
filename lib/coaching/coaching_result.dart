enum CoachingLevel { good, caution, warning }

/// 코칭 시 피사체 이동 방향 힌트
enum DirectionHint {
  none,
  left,
  right,
  up,
  down,
  back, // 뒤로 물러나기
  closer, // 가까이 다가가기
}

/// 광원(빛) 방향 — 피사체 기준 어느 쪽에서 오는지
enum LightDirection {
  unknown,
  left,
  right,
  top,
  bottom,
  behind, // 역광
}

class CoachingResult {
  final String guidance;
  final CoachingLevel level;
  final String? subGuidance;

  /// 0~100 점수. null이면 점수 표시하지 않음.
  final double? score;

  /// 카메라를 어느 쪽으로 움직이면 좋을지 방향 힌트
  final DirectionHint directionHint;

  /// 감지된 광원 방향
  final LightDirection lightDirection;

  const CoachingResult({
    required this.guidance,
    required this.level,
    this.subGuidance,
    this.score,
    this.directionHint = DirectionHint.none,
    this.lightDirection = LightDirection.unknown,
  });
}
