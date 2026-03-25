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
}
