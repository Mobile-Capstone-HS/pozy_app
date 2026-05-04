import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

import '../../../../config/experimental_features.dart';
import '../../model/multi_photo_ranking_result.dart';
import '../../model/photo_type_mode.dart';
import '../../model/scored_photo_result.dart';
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
    final total = assets.length;
    final working = <ScoredPhotoResult>[];

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

      try {
        final originBytes = await current.asset.originBytes;
        if (originBytes == null || originBytes.isEmpty) {
          throw Exception('Cannot read image bytes.');
        }
        final vlmImagePath = ExperimentalFeatures.useOnDeviceGemmaVlmExplanation
            ? await _prepareVlmImagePath(
                asset: current.asset,
                imageBytes: originBytes,
              )
            : null;

        final evaluation = await _evaluationService.evaluate(
          originBytes,
          fileName: current.fileName,
          localImagePath: vlmImagePath,
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

      done += 1;
      onProgress(
        _rankingService.rank(results: working, topPercent: topPercent),
        done,
        total,
      );
    }
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
