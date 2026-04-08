import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fastscnn_pipeline.dart';
import 'fastscnn_segmentor.dart';

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
  final List<CameraDescription> _cameras = [];

  CameraController? _camera;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  int _cameraIndex = 0;
  int _frameCount = 0;
  bool _isInitialized = false;
  bool _isProcessingFrame = false;
  DateTime _lastInferenceAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 2.0;
  FastScnnFrame? _latestFrame;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await _pipeline.initialize();
    _eventSub = _pipeline.events.listen(widget.onEvent?.call);
    await _initCamera();
    if (!mounted) return;
    setState(() {
      _isInitialized = _camera?.value.isInitialized == true;
    });
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    if (cams.isEmpty) return;
    _cameras
      ..clear()
      ..addAll(cams);

    int index = 0;
    if (widget.startWithBackCamera) {
      final back = _cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      if (back != -1) index = back;
    }
    await _startCamera(index);
  }

  Future<void> _startCamera(int index) async {
    final old = _camera;
    if (old != null) {
      if (old.value.isStreamingImages) {
        await old.stopImageStream();
      }
      await old.dispose();
    }

    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    _minZoom = await controller.getMinZoomLevel();
    _maxZoom = await controller.getMaxZoomLevel();
    _zoom = _zoom.clamp(_minZoom, _maxZoom);
    await controller.setZoomLevel(_zoom);
    await controller.startImageStream(_onImage);
    if (!mounted) {
      await controller.dispose();
      return;
    }

    _cameraIndex = index;
    _camera = controller;
    widget.onZoomChanged?.call(_zoom);
  }

  Future<void> _onImage(CameraImage image) async {
    if (!mounted || _isProcessingFrame || !_pipeline.isInitialized) return;

    _frameCount++;
    if (_frameCount % (widget.frameSkipLevel + 1) != 0) return;

    final now = DateTime.now();
    if (now.difference(_lastInferenceAt).inMilliseconds <
        widget.inferenceIntervalMs) {
      return;
    }
    _lastInferenceAt = now;

    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;

    _isProcessingFrame = true;
    try {
      final orientation =
          camera.value.previewPauseOrientation ??
          camera.value.lockedCaptureOrientation ??
          camera.value.deviceOrientation;
      final inferenceTurns = _orientationToInferenceQuarterTurns(orientation);
      final isFront =
          _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
      final result = await _pipeline.segmentCameraImage(
        image,
        rotationQuarterTurns: inferenceTurns,
        mirrorX: isFront,
      );
      if (result == null || !mounted) return;

      final frame = FastScnnFrame(
        result: result,
        isFrontCamera: isFront,
        orientation: orientation,
        zoomLevel: _zoom,
      );
      _latestFrame = frame;
      widget.onResult?.call(frame);
      if (mounted) setState(() {});
    } finally {
      _isProcessingFrame = false;
    }
  }

  int _orientationToPreviewQuarterTurns(DeviceOrientation orientation) {
    if (orientation == DeviceOrientation.landscapeRight) return 1;
    if (orientation == DeviceOrientation.portraitDown) return 2;
    if (orientation == DeviceOrientation.landscapeLeft) return 3;
    return 0;
  }

  int _orientationToInferenceQuarterTurns(DeviceOrientation orientation) {
    if (orientation == DeviceOrientation.portraitUp) return 3;
    if (orientation == DeviceOrientation.landscapeRight) return 0;
    if (orientation == DeviceOrientation.portraitDown) return 1;
    if (orientation == DeviceOrientation.landscapeLeft) return 2;
    return 0;
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    await _startCamera(next);
    if (mounted) setState(() {});
  }

  Future<void> _setZoom(double zoom) async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    await camera.setZoomLevel(clamped);
    _zoom = clamped;
    widget.onZoomChanged?.call(clamped);
    if (mounted) setState(() {});
  }

  Future<Uint8List?> _captureFrameBytes() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return null;
    if (camera.value.isStreamingImages) {
      await camera.stopImageStream();
    }
    try {
      final file = await camera.takePicture();
      return await file.readAsBytes();
    } finally {
      if (!camera.value.isStreamingImages) {
        await camera.startImageStream(_onImage);
      }
    }
  }

  Future<void> _stop() async {
    final camera = _camera;
    if (camera != null) {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
      await camera.dispose();
      _camera = null;
    }
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
    final camera = _camera;
    if (!_isInitialized || camera == null || !camera.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final orientation =
        camera.value.previewPauseOrientation ??
        camera.value.lockedCaptureOrientation ??
        camera.value.deviceOrientation;
    final quarterTurns = _orientationToPreviewQuarterTurns(orientation);
    final isLandscape =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    final previewAspectRatio = isLandscape
        ? camera.value.aspectRatio
        : (1 / camera.value.aspectRatio);

    Widget previewLayer = camera.buildPreview();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      previewLayer = RotatedBox(
        quarterTurns: quarterTurns,
        child: previewLayer,
      );
    }
    Widget overlayLayer =
        widget.overlayBuilder?.call(context, _latestFrame) ??
        const SizedBox.shrink();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      overlayLayer = RotatedBox(
        quarterTurns: quarterTurns,
        child: overlayLayer,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxWidth / previewAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [previewLayer, overlayLayer],
            ),
          ),
        );
      },
    );
  }
}
