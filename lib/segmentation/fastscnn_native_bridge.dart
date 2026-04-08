import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fastscnn_segmentor.dart';

class FastScnnNativeInitResult {
  final bool ok;
  final int inputWidth;
  final int inputHeight;

  const FastScnnNativeInitResult({
    required this.ok,
    required this.inputWidth,
    required this.inputHeight,
  });
}

class FastScnnNativeBridge {
  static const MethodChannel _methodChannel = MethodChannel(
    'pozy.fastscnn/method',
  );
  static const EventChannel _eventChannel = EventChannel('pozy.fastscnn/event');
  int _yuvRequestCount = 0;
  int _yuvSuccessCount = 0;

  Stream<Map<String, dynamic>> events() {
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{'type': 'unknown'};
    });
  }

  Future<FastScnnNativeInitResult?> initialize({
    String modelAssetPath = 'assets/models/fastscnn_cityscapes_float16.tflite',
    int numThreads = 2,
  }) async {
    final result = await _methodChannel.invokeMethod<dynamic>('initialize', {
      'modelAssetPath': modelAssetPath,
      'numThreads': numThreads,
    });

    if (result is! Map) return null;
    final map = Map<String, dynamic>.from(result);
    return FastScnnNativeInitResult(
      ok: map['ok'] == true,
      inputWidth: (map['inputWidth'] as num?)?.toInt() ?? 0,
      inputHeight: (map['inputHeight'] as num?)?.toInt() ?? 0,
    );
  }

  Future<SegmentationResult?> segment(Uint8List jpegBytes) async {
    final result = await _methodChannel.invokeMethod<dynamic>('segment', {
      'jpegBytes': jpegBytes,
    });
    if (result is! Map) return null;
    return _toSegmentationResult(Map<String, dynamic>.from(result));
  }

  Future<SegmentationResult?> segmentYuv420(
    CameraImage image, {
    required int rotationQuarterTurns,
    required bool mirrorX,
  }) async {
    if (image.planes.length < 3) return null;
    _yuvRequestCount++;
    final y = image.planes[0];
    final u = image.planes[1];
    final v = image.planes[2];

    final result = await _methodChannel.invokeMethod<dynamic>('segmentYuv420', {
      'width': image.width,
      'height': image.height,
      'yPlane': y.bytes,
      'uPlane': u.bytes,
      'vPlane': v.bytes,
      'yRowStride': y.bytesPerRow,
      'uvRowStride': u.bytesPerRow,
      'uvPixelStride': u.bytesPerPixel ?? 1,
      'rotationQuarterTurns': rotationQuarterTurns,
      'mirrorX': mirrorX,
    });
    if (result is! Map) return null;
    final seg = _toSegmentationResult(Map<String, dynamic>.from(result));
    if (seg != null) {
      _yuvSuccessCount++;
      if (_yuvSuccessCount % 15 == 0) {
        debugPrint(
          '[FastSCNN][Bridge] yuv requests=$_yuvRequestCount success=$_yuvSuccessCount '
          'seg=${seg.width}x${seg.height}',
        );
      }
    }
    return seg;
  }

  Future<void> dispose() async {
    await _methodChannel.invokeMethod<void>('dispose');
  }

  SegmentationResult? _toSegmentationResult(Map<String, dynamic> map) {
    if (map['ok'] != true) return null;

    final width = (map['width'] as num?)?.toInt() ?? 0;
    final height = (map['height'] as num?)?.toInt() ?? 0;
    if (width <= 0 || height <= 0) return null;

    final flat = (map['classMapFlat'] as List?)?.cast<num>();
    if (flat == null || flat.length != width * height) return null;

    final classMap = List<List<int>>.generate(
      height,
      (y) => List<int>.generate(width, (x) => flat[y * width + x].toInt()),
    );
    return SegmentationResult(classMap: classMap, height: height, width: width);
  }
}
