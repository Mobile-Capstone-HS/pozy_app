enum CoachingLevel { good, caution, warning }

enum ShootingMode { person, landscape, object }

extension ShootingModeLabel on ShootingMode {
  String get label {
    switch (this) {
      case ShootingMode.person:
        return '인물';
      case ShootingMode.landscape:
        return '풍경';
      case ShootingMode.object:
        return '사물';
    }
  }
}

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
