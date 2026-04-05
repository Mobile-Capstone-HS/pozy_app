import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../model/tflite_model_metadata.dart';

class TfliteModelMetadataLoadResult {
  final String metadataAssetPath;
  final TfliteModelMetadata? metadata;
  final String? warning;

  const TfliteModelMetadataLoadResult({
    required this.metadataAssetPath,
    this.metadata,
    this.warning,
  });

  bool get hasMetadata => metadata != null;
}

class TfliteModelMetadataLoader {
  TfliteModelMetadataLoader._();

  static final TfliteModelMetadataLoader instance =
      TfliteModelMetadataLoader._();

  final Map<String, Future<TfliteModelMetadataLoadResult>> _cache = {};

  Future<TfliteModelMetadataLoadResult> loadForModelAsset(
    String modelAssetPath,
  ) {
    final metadataAssetPath = metadataAssetPathForModel(modelAssetPath);
    return _cache.putIfAbsent(
      metadataAssetPath,
      () => _load(metadataAssetPath),
    );
  }

  String metadataAssetPathForModel(String modelAssetPath) {
    if (modelAssetPath.endsWith('.tflite')) {
      return modelAssetPath.replaceFirst(
        RegExp(r'\.tflite$'),
        '.metadata.json',
      );
    }
    return '$modelAssetPath.metadata.json';
  }

  Future<TfliteModelMetadataLoadResult> _load(String metadataAssetPath) async {
    try {
      final jsonString = await rootBundle.loadString(metadataAssetPath);
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return TfliteModelMetadataLoadResult(
          metadataAssetPath: metadataAssetPath,
          warning: 'Metadata is not a JSON object.',
        );
      }

      return TfliteModelMetadataLoadResult(
        metadataAssetPath: metadataAssetPath,
        metadata: TfliteModelMetadata.fromJson(
          decoded,
          metadataAssetPath: metadataAssetPath,
        ),
      );
    } on FlutterError {
      return TfliteModelMetadataLoadResult(
        metadataAssetPath: metadataAssetPath,
        warning: 'Metadata asset not found.',
      );
    } on FormatException catch (error) {
      return TfliteModelMetadataLoadResult(
        metadataAssetPath: metadataAssetPath,
        warning: 'Metadata JSON parse failed: ${error.message}',
      );
    } catch (error) {
      return TfliteModelMetadataLoadResult(
        metadataAssetPath: metadataAssetPath,
        warning: 'Metadata load failed: $error',
      );
    }
  }
}
