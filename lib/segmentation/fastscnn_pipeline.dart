import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fastscnn_native_bridge.dart';
import 'fastscnn_segmentor.dart';

class FastScnnPipeline {
  final FastScnnNativeBridge _nativeBridge = FastScnnNativeBridge();

  bool _isInitialized = false;
  bool _isBusy = false;
  final bool _useNative = defaultTargetPlatform == TargetPlatform.android;

  bool get isInitialized => _isInitialized;
  bool get isBusy => _isBusy;
  bool get usingNative => _useNative;
  Stream<Map<String, dynamic>> get events => _nativeBridge.events();

  Future<void> initialize() async {
    if (_isInitialized) return;

    if (!_useNative) {
      debugPrint('[FastSCNN] Native path is only supported on Android.');
      _isInitialized = false;
      return;
    }

    try {
      final init = await _nativeBridge.initialize();
      _isInitialized = init?.ok == true;
      debugPrint(
        '[FastSCNN][Pipeline] initialize ok=$_isInitialized '
        'input=${init?.inputWidth ?? 0}x${init?.inputHeight ?? 0} '
        'native=$_useNative',
      );
    } on MissingPluginException {
      _isInitialized = false;
      debugPrint('[FastSCNN][Pipeline] initialize missing plugin');
    } catch (_) {
      _isInitialized = false;
      debugPrint('[FastSCNN][Pipeline] initialize failed');
    }
  }

  Future<SegmentationResult?> segment(Uint8List imageBytes) async {
    if (!_isInitialized || _isBusy || !_useNative) {
      debugPrint(
        '[FastSCNN][Pipeline] skip segment '
        'initialized=$_isInitialized busy=$_isBusy native=$_useNative',
      );
      return null;
    }
    _isBusy = true;
    try {
      final result = await _nativeBridge.segment(imageBytes);
      debugPrint(
        '[FastSCNN][Pipeline] segment result='
        '${result == null ? 'null' : '${result.width}x${result.height}'} '
        'bytes=${imageBytes.length}',
      );
      return result;
    } finally {
      _isBusy = false;
    }
  }

  Future<SegmentationResult?> segmentCameraImage(
    CameraImage image, {
    required int rotationQuarterTurns,
    required bool mirrorX,
  }) async {
    if (!_isInitialized || _isBusy || !_useNative) {
      debugPrint(
        '[FastSCNN][Pipeline] skip segmentCameraImage '
        'initialized=$_isInitialized busy=$_isBusy native=$_useNative',
      );
      return null;
    }
    _isBusy = true;
    try {
      final result = await _nativeBridge.segmentYuv420(
        image,
        rotationQuarterTurns: rotationQuarterTurns,
        mirrorX: mirrorX,
      );
      debugPrint(
        '[FastSCNN][Pipeline] segmentCameraImage result='
        '${result == null ? 'null' : '${result.width}x${result.height}'} '
        'source=${image.width}x${image.height}',
      );
      return result;
    } finally {
      _isBusy = false;
    }
  }

  Future<void> dispose() async {
    if (_useNative) {
      try {
        await _nativeBridge.dispose();
      } catch (_) {}
    }
    _isInitialized = false;
  }
}
