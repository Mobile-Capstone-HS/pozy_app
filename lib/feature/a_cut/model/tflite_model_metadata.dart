class TfliteModelMetadata {
  final String? metadataAssetPath;
  final String? preset;
  final String? displayName;
  final String? task;
  final TfliteModelInputMetadata input;
  final TfliteModelOutputMetadata output;
  final TfliteModelExportMetadata? export;
  final TfliteModelIoMetadata? exportModelIo;

  const TfliteModelMetadata({
    required this.input,
    required this.output,
    this.metadataAssetPath,
    this.preset,
    this.displayName,
    this.task,
    this.export,
    this.exportModelIo,
  });

  factory TfliteModelMetadata.fromJson(
    Map<String, dynamic> json, {
    String? metadataAssetPath,
  }) {
    return TfliteModelMetadata(
      metadataAssetPath: metadataAssetPath,
      preset: _readString(json['preset']),
      displayName: _readString(json['display_name']),
      task: _readString(json['task']),
      input: TfliteModelInputMetadata.fromJson(
        _readJsonMap(json['input']),
      ),
      output: TfliteModelOutputMetadata.fromJson(
        _readJsonMap(json['output']),
      ),
      export: json['export'] is Map
          ? TfliteModelExportMetadata.fromJson(_readJsonMap(json['export']))
          : null,
      exportModelIo: json['export_model_io'] is Map
          ? TfliteModelIoMetadata.fromJson(_readJsonMap(json['export_model_io']))
          : null,
    );
  }

  String get effectiveName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    final presetName = preset?.trim();
    if (presetName != null && presetName.isNotEmpty) {
      return presetName;
    }
    return metadataAssetPath ?? 'Unknown model';
  }

  int? get inputWidth => input.imageWidth ?? exportModelIo?.firstInputWidth;

  int? get inputHeight => input.imageHeight ?? exportModelIo?.firstInputHeight;

  int? get outputElementCount =>
      output.elementCount ?? exportModelIo?.firstOutputElementCount;

  bool? get requiresSelectTfOps => export?.requiresSelectTfOps;
}

class TfliteModelInputMetadata {
  final List<int>? imageSize;
  final String? dtype;
  final String? colorFormat;
  final String? tensorLayout;
  final String? normalization;

  const TfliteModelInputMetadata({
    this.imageSize,
    this.dtype,
    this.colorFormat,
    this.tensorLayout,
    this.normalization,
  });

  factory TfliteModelInputMetadata.fromJson(Map<String, dynamic> json) {
    return TfliteModelInputMetadata(
      imageSize: _readIntList(json['image_size']),
      dtype: _readString(json['dtype']),
      colorFormat: _readString(json['color_format']),
      tensorLayout: _readString(json['tensor_layout']),
      normalization: _readString(json['normalization']),
    );
  }

  int? get imageWidth => imageSize != null && imageSize!.length >= 2
      ? imageSize![0]
      : null;

  int? get imageHeight => imageSize != null && imageSize!.length >= 2
      ? imageSize![1]
      : null;
}

class TfliteModelOutputMetadata {
  final List<int?>? shape;
  final String? summary;
  final String? interpretation;
  final String? postprocess;

  const TfliteModelOutputMetadata({
    this.shape,
    this.summary,
    this.interpretation,
    this.postprocess,
  });

  factory TfliteModelOutputMetadata.fromJson(Map<String, dynamic> json) {
    return TfliteModelOutputMetadata(
      shape: _readNullableIntList(json['shape']),
      summary: _readString(json['summary']),
      interpretation: _readString(json['interpretation']),
      postprocess: _readString(json['postprocess']),
    );
  }

  int? get elementCount => _shapeElementCount(shape);

  String get combinedHints {
    return [
      summary,
      interpretation,
      postprocess,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
  }
}

class TfliteModelExportMetadata {
  final bool? requiresSelectTfOps;
  final String? tflitePath;

  const TfliteModelExportMetadata({
    this.requiresSelectTfOps,
    this.tflitePath,
  });

  factory TfliteModelExportMetadata.fromJson(Map<String, dynamic> json) {
    return TfliteModelExportMetadata(
      requiresSelectTfOps: json['requires_select_tf_ops'] as bool?,
      tflitePath: _readString(json['tflite_path']),
    );
  }
}

class TfliteModelIoMetadata {
  final List<TfliteTensorSpec> inputs;
  final List<TfliteTensorSpec> outputs;

  const TfliteModelIoMetadata({
    this.inputs = const [],
    this.outputs = const [],
  });

  factory TfliteModelIoMetadata.fromJson(Map<String, dynamic> json) {
    return TfliteModelIoMetadata(
      inputs: _readTensorSpecs(json['inputs']),
      outputs: _readTensorSpecs(json['outputs']),
    );
  }

  int? get firstInputWidth => inputs.isEmpty ? null : inputs.first.width;

  int? get firstInputHeight => inputs.isEmpty ? null : inputs.first.height;

  int? get firstOutputElementCount =>
      outputs.isEmpty ? null : outputs.first.elementCount;
}

class TfliteTensorSpec {
  final String? name;
  final List<int?>? shape;
  final String? dtype;

  const TfliteTensorSpec({
    this.name,
    this.shape,
    this.dtype,
  });

  factory TfliteTensorSpec.fromJson(Map<String, dynamic> json) {
    return TfliteTensorSpec(
      name: _readString(json['name']),
      shape: _readNullableIntList(json['shape']),
      dtype: _readString(json['dtype']),
    );
  }

  int? get width {
    if (shape == null || shape!.length < 4) {
      return null;
    }
    return shape![2];
  }

  int? get height {
    if (shape == null || shape!.length < 4) {
      return null;
    }
    return shape![1];
  }

  int? get elementCount => _shapeElementCount(shape);
}

String? _readString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, dynamic> _readJsonMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, entryValue) => MapEntry(key.toString(), entryValue),
    );
  }
  return const <String, dynamic>{};
}

List<int>? _readIntList(Object? value) {
  if (value is! List) {
    return null;
  }

  final parsed = <int>[];
  for (final item in value) {
    if (item is int) {
      parsed.add(item);
      continue;
    }
    if (item is num) {
      parsed.add(item.toInt());
      continue;
    }
    return null;
  }
  return parsed;
}

List<int?>? _readNullableIntList(Object? value) {
  if (value is! List) {
    return null;
  }

  final parsed = <int?>[];
  for (final item in value) {
    if (item == null) {
      parsed.add(null);
      continue;
    }
    if (item is int) {
      parsed.add(item);
      continue;
    }
    if (item is num) {
      parsed.add(item.toInt());
      continue;
    }
    return null;
  }
  return parsed;
}

List<TfliteTensorSpec> _readTensorSpecs(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map>()
      .map((entry) => TfliteTensorSpec.fromJson(_readJsonMap(entry)))
      .toList(growable: false);
}

int? _shapeElementCount(List<int?>? shape) {
  if (shape == null || shape.isEmpty) {
    return null;
  }

  final dims = shape.whereType<int>().where((value) => value > 0).toList();
  if (dims.isEmpty) {
    return null;
  }

  if (dims.length == 1) {
    return dims.first;
  }

  final withoutBatch = dims.skip(1).toList();
  final effective = withoutBatch.isEmpty ? dims : withoutBatch;

  var total = 1;
  for (final dim in effective) {
    total *= dim;
  }
  return total;
}
