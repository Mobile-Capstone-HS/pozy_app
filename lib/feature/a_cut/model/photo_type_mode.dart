enum PhotoTypeMode { portrait, snap, auto }

extension PhotoTypeModeX on PhotoTypeMode {
  String get label {
    switch (this) {
      case PhotoTypeMode.portrait:
        return '인물';
      case PhotoTypeMode.snap:
        return '스냅';
      case PhotoTypeMode.auto:
        return '자동';
    }
  }

  /// Aesthetic 점수 가중치 (wA)
  double get aestheticWeight {
    switch (this) {
      case PhotoTypeMode.portrait:
        return 0.65;
      case PhotoTypeMode.snap:
        return 0.70;
      case PhotoTypeMode.auto:
        return 0.60;
    }
  }

  /// Technical 점수 가중치 (wT)
  double get technicalWeight {
    switch (this) {
      case PhotoTypeMode.portrait:
        return 0.35;
      case PhotoTypeMode.snap:
        return 0.30;
      case PhotoTypeMode.auto:
        return 0.40;
    }
  }
}
