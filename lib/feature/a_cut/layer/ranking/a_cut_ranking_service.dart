import '../../model/multi_photo_ranking_result.dart';
import '../../model/scored_photo_result.dart';

class ACutRankingService {
  const ACutRankingService();

  MultiPhotoRankingResult rank({
    required List<ScoredPhotoResult> results,
    required double topPercent,
  }) {
    if (results.isEmpty) {
      return const MultiPhotoRankingResult.empty();
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

    final clampedTopPercent = topPercent.clamp(0.1, 1.0).toDouble();
    final cutCount = successItems.isEmpty
        ? 0
        : _resolveCutCount(total: successItems.length, topPercent: clampedTopPercent);

    final rankedById = <String, ScoredPhotoResult>{};
    for (var index = 0; index < successItems.length; index++) {
      final item = successItems[index];
      rankedById[item.asset.id] = item.copyWith(
        rank: index + 1,
        isACut: index < cutCount,
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

    return MultiPhotoRankingResult(
      items: [
        ...successItems.map((item) => rankedById[item.asset.id]!),
        ...pendingItems,
        ...failedItems,
      ],
      topPercent: clampedTopPercent,
    );
  }

  int _resolveCutCount({required int total, required double topPercent}) {
    final raw = (total * topPercent).ceil();
    return raw < 1 ? 1 : raw;
  }
}
