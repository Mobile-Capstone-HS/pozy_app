import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';

import 'detect.dart' as detect;
import 'services/photo_service.dart';

class FigmaCameraScreen extends StatefulWidget {
  const FigmaCameraScreen({super.key});

  @override
  State<FigmaCameraScreen> createState() => _FigmaCameraScreenState();
}

class _FigmaCameraScreenState extends State<FigmaCameraScreen> {
  int _detectedCount = 0;
  final List<_DetectionBox> _detections = [];
  Size _previewSize = Size.zero;
  final YOLOViewController _yoloController = YOLOViewController();
  final PhotoService _photoService = PhotoService();
  bool _isSaving = false;

  bool get _cameraReady => detect.cameras.isNotEmpty;

  Rect _toPreviewRect(YOLOResult result, Size previewSize) {
    return Rect.fromLTRB(
      (result.normalizedBox.left * previewSize.width).clamp(0, previewSize.width),
      (result.normalizedBox.top * previewSize.height).clamp(0, previewSize.height),
      (result.normalizedBox.right * previewSize.width)
          .clamp(0, previewSize.width),
      (result.normalizedBox.bottom * previewSize.height)
          .clamp(0, previewSize.height),
    );
  }

  void _onYoloResult(List<YOLOResult> results) {
    final previewSize = _previewSize == Size.zero
        ? MediaQuery.sizeOf(context)
        : _previewSize;

    if (!mounted) return;
    setState(() {
      _detectedCount = results.length;
      _detections
        ..clear()
        ..addAll(
          results.map(
            (result) => _DetectionBox(
              rect: _toPreviewRect(result, previewSize),
              className: result.className,
              confidence: result.confidence,
            ),
          ),
        );
    });
  }

  Future<void> _captureAndSavePhoto() async {
    if (_isSaving) return;
    if (!_cameraReady) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final bytes = await _yoloController.captureFrame();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to capture camera frame.');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final xFile = XFile.fromData(
        bytes,
        name: 'CAPTURE_$timestamp.jpg',
        mimeType: 'image/jpeg',
      );

      final savedPath = await _photoService.savePhoto(xFile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '사진이 저장되었습니다.\n$savedPath',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errorType = e.runtimeType.toString();
      final errorMessage = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '저장에 실패했습니다. [$errorType]\n$errorMessage',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  void dispose() {
    _yoloController.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_cameraReady)
              LayoutBuilder(
                builder: (context, constraints) {
                  _previewSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );

                  return YOLOView(
                    controller: _yoloController,
                    modelPath: 'yolov8n_float16.tflite',
                    task: YOLOTask.detect,
                    useGpu: false,
                    streamingConfig: const YOLOStreamingConfig.minimal(),
                    showOverlays: false,
                    onResult: _onYoloResult,
                  );
                },
              )
            else
              const Center(
                child: Text(
                  'Camera is not initialized.',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x4D000000),
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x66000000),
                    ],
                    stops: [0, 0.2, 0.8, 1],
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _ThirdsGridPainter(),
                size: Size.infinite,
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _CameraDetectionPainter(detections: _detections),
                size: Size.infinite,
              ),
            ),
            _TopCameraBar(
              onBack: () => Navigator.of(context).pop(),
              detectedCount: _detectedCount,
              lensDirection:
                  _cameraReady ? detect.cameras.first.lensDirection : null,
            ),
            _BottomCameraControls(
              onCapture: _captureAndSavePhoto,
              onFlipCamera: _yoloController.switchCamera,
              isSaving: _isSaving,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopCameraBar extends StatelessWidget {
  const _TopCameraBar({
    required this.onBack,
    required this.detectedCount,
    required this.lensDirection,
  });

  final VoidCallback onBack;
  final int detectedCount;
  final CameraLensDirection? lensDirection;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      top: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CircleIconButton(
            onTap: onBack,
            iconPath: 'assets/figma/camera_icons/back.svg',
            iconSize: 14,
          ),
          Row(
            children: [
              if (lensDirection != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x66333333),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${lensDirection!.name} | $_detectedText',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0x66333333),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: const [
                    _CircleIconButton(
                      iconPath: 'assets/figma/camera_icons/mode_expand.svg',
                      iconSize: 18,
                    ),
                    _CircleIconButton(
                      iconPath: 'assets/figma/camera_icons/timer.svg',
                      iconSize: 20,
                    ),
                    _CircleIconButton(
                      iconPath: 'assets/figma/camera_icons/flash.svg',
                      iconSize: 18,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _detectedText => 'det: $detectedCount';
}

class _BottomCameraControls extends StatelessWidget {
  const _BottomCameraControls({
    required this.onCapture,
    required this.onFlipCamera,
    required this.isSaving,
  });

  final Future<void> Function() onCapture;
  final Future<void> Function() onFlipCamera;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24 + bottomInset,
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0x66333333),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                _ZoomPill(label: '0.5x'),
                _ZoomPill(label: '1x', selected: true),
                _ZoomPill(label: '2x'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CircleIconButton(
                iconPath: 'assets/figma/camera_icons/gallery.svg',
                iconSize: 18,
                diameter: 48,
                blurred: true,
              ),
              const SizedBox(width: 48),
              GestureDetector(
                onTap: isSaving ? null : onCapture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: isSaving
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Color(0xFF333333),
                            ),
                          )
                        : Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0x1A333333),
                                width: 2,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 48),
              _CircleIconButton(
                onTap: onFlipCamera,
                iconPath: 'assets/figma/camera_icons/flip.svg',
                iconSize: 24,
                diameter: 48,
                blurred: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoomPill extends StatelessWidget {
  const _ZoomPill({
    required this.label,
    this.selected = false,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: selected ? 32 : 28,
      height: selected ? 32 : 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Colors.white : const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF333333) : Colors.white,
          fontSize: selected ? 11 : 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    this.onTap,
    required this.iconPath,
    required this.iconSize,
    this.diameter = 40,
    this.blurred = false,
  });

  final VoidCallback? onTap;
  final String iconPath;
  final double iconSize;
  final double diameter;
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: blurred ? const Color(0x66333333) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: blurred
            ? Border.all(color: const Color(0x4DFFFFFF), width: 1)
            : null,
      ),
      alignment: Alignment.center,
      child: SvgPicture.asset(
        iconPath,
        width: iconSize,
        height: iconSize,
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: child,
    );
  }
}

class _ThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;

    final dx1 = size.width / 3;
    final dx2 = size.width * 2 / 3;
    final dy1 = size.height / 3;
    final dy2 = size.height * 2 / 3;

    canvas.drawLine(Offset(dx1, 0), Offset(dx1, size.height), paint);
    canvas.drawLine(Offset(dx2, 0), Offset(dx2, size.height), paint);
    canvas.drawLine(Offset(0, dy1), Offset(size.width, dy1), paint);
    canvas.drawLine(Offset(0, dy2), Offset(size.width, dy2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DetectionBox {
  const _DetectionBox({
    required this.rect,
    required this.className,
    required this.confidence,
  });

  final Rect rect;
  final String className;
  final double confidence;

  bool get isPerson => className.toLowerCase() == 'person';
}

class _CameraDetectionPainter extends CustomPainter {
  const _CameraDetectionPainter({required this.detections});

  final List<_DetectionBox> detections;

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final accent = detection.isPerson
          ? const Color(0xFF4ADE80)
          : const Color(0xFFFB923C);

      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      final boxPaint = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final rect = Rect.fromLTRB(
        detection.rect.left.clamp(0, size.width),
        detection.rect.top.clamp(0, size.height),
        detection.rect.right.clamp(0, size.width),
        detection.rect.bottom.clamp(0, size.height),
      );

      canvas.drawRect(rect, shadowPaint);
      canvas.drawRect(rect, boxPaint);

      final label =
          '${detection.className} ${(detection.confidence * 100).toStringAsFixed(1)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          rect.left,
          (rect.top - 20).clamp(0, size.height - 20),
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CameraDetectionPainter oldDelegate) =>
      oldDelegate.detections != detections;
}
