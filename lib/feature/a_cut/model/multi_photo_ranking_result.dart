import 'scored_photo_result.dart';

class MultiPhotoRankingResult {
  final List<ScoredPhotoResult> items;
  final double topPercent;
  final String? rankingLabel;
  final String? rankingSource;
  final String? rankingSummary;

  const MultiPhotoRankingResult({
    required this.items,
    required this.topPercent,
    this.rankingLabel,
    this.rankingSource,
    this.rankingSummary,
  });

  const MultiPhotoRankingResult.empty()
      : items = const [],
        topPercent = 0.0,
        rankingLabel = null,
        rankingSource = null,
        rankingSummary = null;

  List<ScoredPhotoResult> get rankedItems {
    final ranked = items
        .where(
          (item) => item.status == ScoreStatus.success && item.rank != null,
        )
        .toList();
    ranked.sort((a, b) => a.rank!.compareTo(b.rank!));
    return ranked;
  }

  ScoredPhotoResult? get bestShot {
    for (final item in rankedItems) {
      if (item.rank == 1) {
        return item;
      }
    }
    return null;
  }

  List<ScoredPhotoResult> get topPicks =>
      rankedItems.take(3).toList(growable: false);

  List<ScoredPhotoResult> get recommendedPicks {
    final picks = items.where((item) => item.isRecommendedPick).toList();
    picks.sort((a, b) {
      final aRank = a.rank ?? 1 << 30;
      final bRank = b.rank ?? 1 << 30;
      return aRank.compareTo(bRank);
    });
    return picks;
  }

  int get successCount =>
      items.where((item) => item.status == ScoreStatus.success).length;

  int get failureCount =>
      items.where((item) => item.status == ScoreStatus.failed).length;

  int get pendingCount =>
      items.where((item) => item.status == ScoreStatus.pending).length;

  int get aCutCount => items.where((item) => item.isACut).length;

  bool get hasBestShot => bestShot != null;

  String get displayTitle => rankingLabel ?? 'A컷 추천 결과';

  String get displaySource => rankingSource ?? '온디바이스 정렬';

  String get displaySummary {
    final customSummary = rankingSummary;
    if (customSummary != null && customSummary.trim().isNotEmpty) {
      return customSummary;
    }
    if (bestShot != null) {
      return '가장 먼저 볼 BEST 1장과 추천 컷 순위를 정리했어요.';
    }
    if (successCount > 0) {
      return '분석이 끝난 사진부터 추천 순위로 보여드려요.';
    }
    return '사진을 분석해 추천 순위를 만들고 있어요.';
  }
}
