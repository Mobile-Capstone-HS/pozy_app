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
    } on MissingPluginException {
      _isInitialized = false;
    } catch (_) {
      _isInitialized = false;
    }
  }

  Future<SegmentationResult?> segment(Uint8List imageBytes) async {
    if (!_isInitialized || _isBusy || !_useNative) return null;
    _isBusy = true;
    try {
      return await _nativeBridge.segment(imageBytes);
    } finally {
      _isBusy = false;
    }
  }

  Future<SegmentationResult?> segmentCameraImage(
    CameraImage image, {
    required int rotationQuarterTurns,
    required bool mirrorX,
  }) async {
    if (!_isInitialized || _isBusy || !_useNative) return null;
    _isBusy = true;
    try {
      return await _nativeBridge.segmentYuv420(
        image,
        rotationQuarterTurns: rotationQuarterTurns,
        mirrorX: mirrorX,
      );
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
