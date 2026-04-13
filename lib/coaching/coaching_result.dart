enum CoachingLevel { good, caution, warning }

class CoachingResult {
  final String guidance;
  final CoachingLevel level;
  final String? subGuidance;

  const CoachingResult({
    required this.guidance,
    required this.level,
    this.subGuidance,
  });
}
