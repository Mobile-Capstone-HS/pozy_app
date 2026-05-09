import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../model/multi_photo_ranking_result.dart';
import '../../model/photo_type_mode.dart';
import '../../model/scored_photo_result.dart';
import '../inference/acut_perf.dart';
import '../evaluation/photo_evaluation_service.dart';
import '../ranking/a_cut_ranking_service.dart';

abstract class ImageScoreService {
  Future<void> scoreAssets({
    required List<AssetEntity> assets,
    required PhotoTypeMode photoTypeMode,
    required double topPercent,
    required void Function(
      MultiPhotoRankingResult snapshot,
      int done,
      int total,
    )
    onProgress,
  });
}

class OnDeviceImageScoreService implements ImageScoreService {
  OnDeviceImageScoreService({
    PhotoEvaluationService? evaluationService,
    ACutRankingService? rankingService,
  }) : _evaluationService =
           evaluationService ?? OnDevicePhotoEvaluationService(),
       _rankingService = rankingService ?? const ACutRankingService();

  final PhotoEvaluationService _evaluationService;
  final ACutRankingService _rankingService;

  @override
  Future<void> scoreAssets({
    required List<AssetEntity> assets,
    required PhotoTypeMode photoTypeMode,
    required double topPercent,
    required void Function(
      MultiPhotoRankingResult snapshot,
      int done,
      int total,
    )
    onProgress,
  }) async {
    final batchSw = Stopwatch()..start();
    AcutPerfCollector.reset();
    final total = assets.length;
    final working = <ScoredPhotoResult>[];

    debugPrint('[AcutPerf] batch_start image_count=$total');
    debugPrint('[AcutPerf] explanation_batch_disabled=true');

    for (var index = 0; index < assets.length; index++) {
      final asset = assets[index];
      final name = await _resolveFilename(asset, index);
      working.add(
        ScoredPhotoResult(
          asset: asset,
          fileName: name,
          selectedIndex: index,
          status: ScoreStatus.pending,
          photoTypeMode: photoTypeMode,
        ),
      );
    }

    onProgress(
      _rankingService.rank(results: working, topPercent: topPercent),
      0,
      total,
    );

    var done = 0;
    for (var index = 0; index < working.length; index++) {
      final current = working[index];
      final imageSw = Stopwatch()..start();
      final oneBasedIndex = index + 1;
      debugPrint(
        '[AcutPerf] batch_image_start index=$oneBasedIndex/$total '
        'file="${current.fileName}"',
      );

      try {
        final originBytes = await current.asset.originBytes;
        if (originBytes == null || originBytes.isEmpty) {
          throw Exception('Cannot read image bytes.');
        }
        final evaluation = await _evaluationService.evaluate(
          originBytes,
          fileName: current.fileName,
          skipExplanation: true,
          batchImageIndex: oneBasedIndex,
        );

        working[index] = current.copyWith(
          status: ScoreStatus.success,
          evaluation: evaluation,
          clearErrorMessage: true,
        );
      } catch (error) {
        working[index] = current.copyWith(
          status: ScoreStatus.failed,
          errorMessage: error.toString(),
          clearEvaluation: true,
        );
      }
      imageSw.stop();
      AcutPerfCollector.recordImage();
      debugPrint(
        '[AcutPerf] batch_image_done index=$oneBasedIndex/$total '
        'total_ms=${imageSw.elapsedMilliseconds} '
        'skip_explanation=true',
      );

      done += 1;
      onProgress(
        _rankingService.rank(results: working, topPercent: topPercent),
        done,
        total,
      );
    }
    batchSw.stop();
    final avgMs = total == 0 ? 0 : batchSw.elapsedMilliseconds / total;
    debugPrint(
      '[AcutPerf] batch_done total_ms=${batchSw.elapsedMilliseconds} '
      'avg_ms=${avgMs.toStringAsFixed(1)}',
    );
    debugPrint(
      AcutPerfCollector.snapshot().batchSummary(
        totalImages: total,
        totalMs: batchSw.elapsedMilliseconds,
        avgMs: avgMs.toDouble(),
      ),
    );
  }

  Future<String> _resolveFilename(AssetEntity asset, int index) async {
    final title = await asset.titleAsync;
    if (title.trim().isNotEmpty) {
      return title;
    }
    return 'photo_${index + 1}';
  }
}
