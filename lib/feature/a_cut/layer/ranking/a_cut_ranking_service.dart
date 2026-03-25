import '../../model/scored_photo_result.dart';

class ACutRankingService {
  const ACutRankingService();

  List<ScoredPhotoResult> rank({
    required List<ScoredPhotoResult> results,
    required double topPercent,
  }) {
    if (results.isEmpty) {
      return const [];
    }

    final successItems =
        results
            .where(
              (result) =>
                  result.status == ScoreStatus.success &&
                  result.finalScore != null,
            )
            .toList()
          ..sort((a, b) => b.finalScore!.compareTo(a.finalScore!));

    final cutCount = successItems.isEmpty
        ? 0
        : _resolveCutCount(total: successItems.length, topPercent: topPercent);

    final rankedById = <String, ScoredPhotoResult>{};
    for (var i = 0; i < successItems.length; i++) {
      final item = successItems[i];
      rankedById[item.asset.id] = item.copyWith(
        rank: i + 1,
        isACut: i < cutCount,
      );
    }

    final pendingItems = <ScoredPhotoResult>[];
    final failedItems = <ScoredPhotoResult>[];
    for (final item in results) {
      final ranked = rankedById[item.asset.id];
      if (ranked != null) {
        continue;
      }
      if (item.status == ScoreStatus.failed) {
        failedItems.add(item.copyWith(rank: null, isACut: false));
      } else {
        pendingItems.add(item.copyWith(rank: null, isACut: false));
      }
    }

    return [
      ...successItems.map((item) => rankedById[item.asset.id]!),
      ...pendingItems,
      ...failedItems,
    ];
  }

  int _resolveCutCount({required int total, required double topPercent}) {
    final clamped = topPercent.clamp(0.1, 1.0);
    final raw = (total * clamped).ceil();
    return raw < 1 ? 1 : raw;
  }
}
