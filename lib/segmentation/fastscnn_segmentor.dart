/// Cityscapes 19개 클래스 ID 상수
abstract final class CityscapesClass {
  static const int road = 0;
  static const int sidewalk = 1;
  static const int building = 2;
  static const int wall = 3;
  static const int fence = 4;
  static const int pole = 5;
  static const int trafficLight = 6;
  static const int trafficSign = 7;
  static const int vegetation = 8;
  static const int terrain = 9;
  static const int sky = 10;
  static const int person = 11;
  static const int rider = 12;
  static const int car = 13;
  static const int truck = 14;
  static const int bus = 15;
  static const int train = 16;
  static const int motorcycle = 17;
  static const int bicycle = 18;
  static const int totalClasses = 19;
}

/// FastSCNN 추론 결과
class SegmentationResult {
  /// [height][width] 형태의 클래스 ID 맵
  final List<List<int>> classMap;
  final int height;
  final int width;

  const SegmentationResult({
    required this.classMap,
    required this.height,
    required this.width,
  });

  /// 특정 클래스가 화면 전체에서 몇 픽셀인지 계산합니다.
  int countClass(int classId) {
    int count = 0;
    for (final row in classMap) {
      for (final id in row) {
        if (id == classId) count++;
      }
    }
    return count;
  }

  /// 특정 클래스의 전체 화면 점유율(0.0~1.0)을 계산합니다.
  double classRatio(int classId) {
    final total = height * width;
    if (total == 0) return 0;
    return countClass(classId) / total;
  }

  /// 특정 행 구간(rowStart~rowEnd)에서 클래스 점유율을 계산합니다.
  double classRatioInRows(int classId, int rowStart, int rowEnd) {
    final clampedStart = rowStart.clamp(0, height);
    final clampedEnd = rowEnd.clamp(0, height);
    final total = (clampedEnd - clampedStart) * width;
    if (total == 0) return 0;

    int count = 0;
    for (int y = clampedStart; y < clampedEnd; y++) {
      for (final id in classMap[y]) {
        if (id == classId) count++;
      }
    }
    return count / total;
  }

  /// 특정 열 구간(colStart~colEnd)에서 클래스 점유율을 계산합니다.
  double classRatioInCols(int classId, int colStart, int colEnd) {
    final clampedStart = colStart.clamp(0, width);
    final clampedEnd = colEnd.clamp(0, width);
    final total = height * (clampedEnd - clampedStart);
    if (total == 0) return 0;

    int count = 0;
    for (final row in classMap) {
      for (int x = clampedStart; x < clampedEnd; x++) {
        if (row[x] == classId) count++;
      }
    }
    return count / total;
  }
}
