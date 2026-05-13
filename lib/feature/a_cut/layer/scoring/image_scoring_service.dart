import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

import '../../../../config/experimental_features.dart';
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
  static const _analysisImageSize = ThumbnailSize(960, 960);

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
    final disableExplanations =
        ExperimentalFeatures.disableAllExplanationsDuringBatchScoring;
    final disableGemma = ExperimentalFeatures.disableGemmaDuringBatchScoring;

    debugPrint('[AcutPerf] batch_start image_count=$total');
    debugPrint(
      '[AcutPerf] explanation_batch_disabled=$disableExplanations '
      'gemma_batch_disabled=$disableGemma',
    );
    if (!disableExplanations) {
      debugPrint('[AcutPerf] ERROR explanation_called_during_batch_scoring');
    }

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
        final analysisBytes = await _readAnalysisBytes(current.asset);
        if (analysisBytes == null || analysisBytes.isEmpty) {
          throw Exception('Cannot read analysis image bytes.');
        }
        final vlmImagePath =
            ExperimentalFeatures.useOnDeviceGemmaVlmExplanation && !disableGemma
            ? await _prepareVlmImagePath(
                asset: current.asset,
                imageBytes: analysisBytes,
              )
            : null;

        final evaluation = await _evaluationService.evaluate(
          analysisBytes,
          fileName: current.fileName,
          localImagePath: vlmImagePath,
          skipExplanation: disableExplanations,
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
        'skip_explanation=$disableExplanations',
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

  Future<Uint8List?> _readAnalysisBytes(AssetEntity asset) async {
    try {
      final resized = await asset.thumbnailDataWithSize(_analysisImageSize);
      if (resized != null && resized.isNotEmpty) {
        debugPrint(
          '[AcutPerf] analysis_image_resized asset_id=${asset.id} '
          'bytes=${resized.length}',
        );
        return resized;
      }
    } catch (error) {
      debugPrint(
        '[AcutPerf] analysis_image_resized_failed asset_id=${asset.id} '
        'error=$error',
      );
    }

    debugPrint('[AcutPerf] analysis_image_unavailable asset_id=${asset.id}');
    return null;
  }

  Future<String> _resolveFilename(AssetEntity asset, int index) async {
    final title = await asset.titleAsync;
    if (title.trim().isNotEmpty) {
      return title;
    }
    return 'photo_${index + 1}';
  }

  Future<String?> _prepareVlmImagePath({
    required AssetEntity asset,
    required List<int> imageBytes,
  }) async {
    if (!ExperimentalFeatures.useVlmResizedImageInput) {
      final file = await asset.file;
      final path = file?.path;
      debugPrint(
        '[AcutVlmInput] original path used asset_id=${asset.id} '
        'path=${path ?? '-'} exists=${file?.existsSync() ?? false} '
        'size_bytes=${file?.existsSync() == true ? file!.lengthSync() : -1}',
      );
      return path;
    }

    try {
      final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
      if (decoded == null) {
        debugPrint('[AcutVlmInput] decode failed asset_id=${asset.id}');
        return null;
      }
      final oriented = img.bakeOrientation(decoded);
      final maxLongSide = ExperimentalFeatures.gemmaVlmMaxLongSide;
      final longSide = oriented.width > oriented.height
          ? oriented.width
          : oriented.height;
      final resized = longSide > maxLongSide
          ? img.copyResize(
              oriented,
              width: oriented.width >= oriented.height ? maxLongSide : null,
              height: oriented.height > oriented.width ? maxLongSide : null,
              interpolation: img.Interpolation.average,
            )
          : oriented;
      final dir = Directory('${Directory.systemTemp.path}/acut_vlm_inputs');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeId = asset.id.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      final file = File('${dir.path}/${safeId}_vlm.jpg');
      final encoded = img.encodeJpg(
        resized,
        quality: ExperimentalFeatures.gemmaVlmJpegQuality,
      );
      await file.writeAsBytes(encoded, flush: true);
      debugPrint(
        '[AcutVlmInput] resized cache path=${file.path} '
        'asset_id=${asset.id} source_bytes=${imageBytes.length} '
        'size=${resized.width}x${resized.height} '
        'file_size_bytes=${await file.length()}',
      );
      return file.path;
    } catch (error) {
      debugPrint(
        '[AcutVlmInput] prepare failed asset_id=${asset.id} error=$error',
      );
      return null;
    }
  }
}
