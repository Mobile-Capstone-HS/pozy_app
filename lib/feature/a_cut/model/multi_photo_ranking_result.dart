import 'scored_photo_result.dart';

class MultiPhotoRankingResult {
  final List<ScoredPhotoResult> items;
  final double topPercent;

  const MultiPhotoRankingResult({
    required this.items,
    required this.topPercent,
  });

  const MultiPhotoRankingResult.empty()
      : items = const [],
        topPercent = 0.0;

  ScoredPhotoResult? get bestShot {
    for (final item in items) {
      if (item.status == ScoreStatus.success && item.rank == 1) {
        return item;
      }
    }
    return null;
  }

  int get successCount =>
      items.where((item) => item.status == ScoreStatus.success).length;

  int get failureCount =>
      items.where((item) => item.status == ScoreStatus.failed).length;

  int get aCutCount => items.where((item) => item.isACut).length;

  bool get hasBestShot => bestShot != null;
}
