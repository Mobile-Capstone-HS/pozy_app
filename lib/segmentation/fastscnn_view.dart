import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import 'fastscnn_pipeline.dart';
import 'fastscnn_segmentor.dart';

const String _cameraOnlyModelPath = 'assets/models/__camera_only__.tflite';

class FastScnnFrame {
  final SegmentationResult result;
  final bool isFrontCamera;
  final DeviceOrientation orientation;
  final double zoomLevel;

  const FastScnnFrame({
    required this.result,
    required this.isFrontCamera,
    required this.orientation,
    required this.zoomLevel,
  });
}

class FastScnnViewController {
  _FastScnnViewState? _state;

  void _attach(_FastScnnViewState state) => _state = state;

  void _detach(_FastScnnViewState state) {
    if (_state == state) _state = null;
  }

  Future<void> switchCamera() async => _state?._switchCamera();

  Future<void> setZoomLevel(double zoom) async => _state?._setZoom(zoom);

  Future<Uint8List?> captureFrame() async => _state?._captureFrameBytes();

  Future<void> stop() async => _state?._stop();
}

class FastScnnView extends StatefulWidget {
  final FastScnnViewController? controller;
  final ValueChanged<FastScnnFrame>? onResult;
  final ValueChanged<Map<String, dynamic>>? onEvent;
  final ValueChanged<double>? onZoomChanged;
  final int frameSkipLevel;
  final int inferenceIntervalMs;
  final bool startWithBackCamera;
  final Widget Function(BuildContext context, FastScnnFrame? frame)?
  overlayBuilder;

  const FastScnnView({
    super.key,
    this.controller,
    this.onResult,
    this.onEvent,
    this.onZoomChanged,
    this.frameSkipLevel = 2,
    this.inferenceIntervalMs = 260,
    this.startWithBackCamera = true,
    this.overlayBuilder,
  });

  @override
  State<FastScnnView> createState() => _FastScnnViewState();
}

class _FastScnnViewState extends State<FastScnnView> {
  final FastScnnPipeline _pipeline = FastScnnPipeline();
  final YOLOViewController _cameraController = YOLOViewController();

  StreamSubscription<Map<String, dynamic>>? _eventSub;
  bool _isPipelineReady = false;
  bool _isProcessingFrame = false;
  bool _isFrontCamera = false;
  double _zoom = 1.0;
  DateTime _lastInferenceAt = DateTime.fromMillisecondsSinceEpoch(0);
  FastScnnFrame? _latestFrame;

  YOLOStreamingConfig get _streamingConfig => YOLOStreamingConfig.custom(
    includeDetections: false,
    includeClassifications: false,
    includeProcessingTimeMs: false,
    includeFps: false,
    includeMasks: false,
    includePoses: false,
    includeOBB: false,
    includeOriginalImage: true,
    throttleInterval: Duration(milliseconds: widget.inferenceIntervalMs),
    skipFrames: widget.frameSkipLevel,
  );

  @override
  void initState() {
    super.initState();
    _isFrontCamera = !widget.startWithBackCamera;
    widget.controller?._attach(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await _pipeline.initialize();
    _eventSub = _pipeline.events.listen(widget.onEvent?.call);
    if (!mounted) return;
    setState(() {
      _isPipelineReady = _pipeline.isInitialized;
    });
  }

  Future<void> _handleStreamingData(Map<String, dynamic> data) async {
    if (!mounted || !_isPipelineReady || _isProcessingFrame) return;

    final originalImage = data['originalImage'];
    if (originalImage is! Uint8List || originalImage.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastInferenceAt).inMilliseconds <
        widget.inferenceIntervalMs) {
      return;
    }
    _lastInferenceAt = now;

    _isProcessingFrame = true;
    try {
      final result = await _pipeline.segment(originalImage);
      if (result == null || !mounted) return;

      final frame = FastScnnFrame(
        result: result,
        isFrontCamera: _isFrontCamera,
        orientation: DeviceOrientation.portraitUp,
        zoomLevel: _zoom,
      );
      _latestFrame = frame;
      widget.onResult?.call(frame);
      if (mounted) setState(() {});
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _switchCamera() async {
    await _cameraController.switchCamera();
    if (!mounted) return;
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  Future<void> _setZoom(double zoom) async {
    await _cameraController.setZoomLevel(zoom);
    if (!mounted) return;
    setState(() {
      _zoom = zoom;
    });
  }

  Future<Uint8List?> _captureFrameBytes() async {
    return _cameraController.captureFrame();
  }

  Future<void> _stop() async {
    await _cameraController.stop();
  }

  @override
  void didUpdateWidget(covariant FastScnnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _eventSub?.cancel();
    unawaited(_stop());
    unawaited(_pipeline.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlay =
        widget.overlayBuilder?.call(context, _latestFrame) ??
        const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        YOLOView(
          key: ValueKey<String>(
            'fastscnn_camera_${_isFrontCamera ? 'front' : 'back'}',
          ),
          controller: _cameraController,
          modelPath: _cameraOnlyModelPath,
          task: YOLOTask.detect,
          useGpu: true,
          showNativeUI: false,
          showOverlays: false,
          streamingConfig: _streamingConfig,
          lensFacing: _isFrontCamera ? LensFacing.front : LensFacing.back,
          onStreamingData: (data) {
            unawaited(_handleStreamingData(data));
          },
          onZoomChanged: (zoomLevel) {
            if (!mounted) return;
            setState(() {
              _zoom = zoomLevel;
            });
            widget.onZoomChanged?.call(zoomLevel);
          },
        ),
        overlay,
        if (!_isPipelineReady)
          const ColoredBox(
            color: Color(0x44000000),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
