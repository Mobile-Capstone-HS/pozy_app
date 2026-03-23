import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/controllers/camera_coach_controller.dart';
import 'package:pose_camera_app/core/enums/composition_mode.dart';
import 'package:pose_camera_app/core/enums/scene_type.dart';
import 'package:pose_camera_app/core/services/capture_service.dart';
import 'package:pose_camera_app/core/services/scene_classifier_service.dart';
import 'package:pose_camera_app/features/composition/composition_painter.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';

class CameraCoachScreen extends StatefulWidget {
  const CameraCoachScreen({super.key, required this.compositionMode});

  final CompositionMode compositionMode;

  @override
  State<CameraCoachScreen> createState() => _CameraCoachScreenState();
}

class _CameraCoachScreenState extends State<CameraCoachScreen> {
  final GlobalKey _cameraKey = GlobalKey();
  final CaptureService _captureService = CaptureService();
  final SceneClassifierService _sceneClassifier = SceneClassifierService();
  final YOLOViewController _yoloViewController = YOLOViewController();

  late final CameraCoachController _controller;

  Timer? _classificationTimer;
  bool _classificationBusy = false;
  bool _isCapturing = false;
  bool _showFlash = false;

  LensFacing _currentLensFacing = LensFacing.back;

  @override
  void initState() {
    super.initState();
    _controller = CameraCoachController(
      compositionMode: widget.compositionMode,
      initialManualScene: SceneType.object,
    );

    _classificationTimer = Timer.periodic(
      const Duration(milliseconds: 1300),
      (_) => _classifyPreview(),
    );
  }

  @override
  void dispose() {
    _classificationTimer?.cancel();
    _sceneClassifier.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleDetections(List<YOLOResult> results) {
    if (_isCapturing) return;
    _controller.onYoloResults(results, MediaQuery.sizeOf(context));
  }

  Future<void> _switchCamera() async {
    if (_isCapturing) return;

    try {
      await _yoloViewController.switchCamera();

      if (!mounted) return;
      setState(() {
        _currentLensFacing = _currentLensFacing == LensFacing.back
            ? LensFacing.front
            : LensFacing.back;
      });

      _controller.setCameraFacing(
        _currentLensFacing == LensFacing.front,
        MediaQuery.sizeOf(context),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 900),
          content: Text(
            _currentLensFacing == LensFacing.front
                ? '전면 카메라로 전환했어.'
                : '후면 카메라로 전환했어.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('카메라 전환 중 오류가 났어: $e')));
    }
  }

  Future<void> _classifyPreview() async {
    if (!mounted || _classificationBusy || _isCapturing) return;

    _classificationBusy = true;

    try {
      final file = await _captureService.capturePreviewToTempFile(
        repaintBoundaryKey: _cameraKey,
        pixelRatio: 1.3,
      );

      final result = await _sceneClassifier.classifyFile(file);

      if (mounted) {
        _controller.applyClassificationResult(
          result,
          MediaQuery.sizeOf(context),
        );
      }
    } catch (_) {
      // 1차 버전이라 분류 실패는 조용히 무시
    } finally {
      _classificationBusy = false;
    }
  }

  Future<void> _takePhoto() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);
    await Future.delayed(const Duration(milliseconds: 90));

    try {
      await _captureService.captureToGalleryAndAppStorage(
        repaintBoundaryKey: _cameraKey,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진을 저장했어. Gallery 탭에서도 바로 볼 수 있어.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('사진 저장 중 오류가 났어: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _showFlash = true;
        });

        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted) {
            setState(() => _showFlash = false);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final overlay = _controller.overlayState;
          final policy = _controller.compositionPolicy;

          return GestureDetector(
            onTapUp: (details) {
              _controller.setPreferredTarget(details.localPosition, size);
            },
            onLongPress: () {
              _controller.clearPreferredTarget(size);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  key: _cameraKey,
                  child: YOLOView(
                    controller: _yoloViewController,
                    modelPath: 'yolov8n-pose_float16.tflite',
                    task: YOLOTask.pose,
                    useGpu: false,
                    lensFacing: LensFacing.back,
                    streamingConfig: const YOLOStreamingConfig.withPoses(),
                    showOverlays: false,
                    onResult: _handleDetections,
                  ),
                ),
                if (!_isCapturing)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: CompositionPainter(
                        policy: policy,
                        overlayState: overlay,
                      ),
                    ),
                  ),
                if (!_isCapturing)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _CircleIconButton(
                                icon: Icons.close_rounded,
                                onTap: () => Navigator.pop(context),
                              ),
                              const Spacer(),
                              _CameraPill(text: policy.label),
                              const SizedBox(width: 8),
                              _CameraPill(text: overlay.resolvedScene.label),
                              const SizedBox(width: 8),
                              _CameraPill(
                                text: _currentLensFacing == LensFacing.front
                                    ? '전면'
                                    : '후면',
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.topLeft,
                            child: _GuideCard(
                              headline: overlay.headline,
                              detail: overlay.detail,
                              movementHint: overlay.movementHint,
                              score: overlay.score,
                              isPerfect: overlay.isPerfect,
                              alignmentLevel: overlay.alignmentLevel,
                              source: overlay.classificationSource,
                              labels: overlay.labelPreview,
                            ),
                          ),
                          const Spacer(),
                          _SceneChips(
                            manualScene: _controller.manualScene,
                            resolvedScene: overlay.resolvedScene,
                            onChanged: (scene) =>
                                _controller.setManualScene(scene, size),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            overlay.targetLocked
                                ? '타깃 고정됨 · 길게 눌러 해제'
                                : '구도 점을 터치하면 그 포인트로 고정돼',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _CircleIconButton(
                                  icon: Icons.photo_library_outlined,
                                  onTap: () => Navigator.pop(context),
                                ),
                                GestureDetector(
                                  onTap: _takePhoto,
                                  child: Container(
                                    width: 82,
                                    height: 82,
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                    ),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                                _CircleIconButton(
                                  icon: Icons.cameraswitch_rounded,
                                  onTap: _switchCamera,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_showFlash) Container(color: Colors.white),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.headline,
    required this.detail,
    required this.movementHint,
    required this.score,
    required this.isPerfect,
    required this.alignmentLevel,
    required this.source,
    required this.labels,
  });

  final String headline;
  final String detail;
  final String movementHint;
  final double score;
  final bool isPerfect;
  final String alignmentLevel;
  final String source;
  final String labels;

  @override
  Widget build(BuildContext context) {
    final badgeColor = isPerfect
        ? const Color(0xFFB7FF85)
        : alignmentLevel == 'near'
        ? const Color(0xFFFFE082)
        : Colors.white.withValues(alpha: 0.12);

    final badgeTextColor = isPerfect || alignmentLevel == 'near'
        ? Colors.black
        : Colors.white;

    final badgeText = isPerfect
        ? 'PERFECT'
        : alignmentLevel == 'near'
        ? 'ALMOST'
        : 'score ${score.toStringAsFixed(0)}';

    return Container(
      width: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: badgeTextColor,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                source,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            movementHint,
            style: TextStyle(
              color: isPerfect
                  ? const Color(0xFFB7FF85)
                  : alignmentLevel == 'near'
                  ? const Color(0xFFFFE082)
                  : Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            labels,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneChips extends StatelessWidget {
  const _SceneChips({
    required this.manualScene,
    required this.resolvedScene,
    required this.onChanged,
  });

  final SceneType manualScene;
  final SceneType resolvedScene;
  final ValueChanged<SceneType> onChanged;

  @override
  Widget build(BuildContext context) {
    const scenes = [SceneType.person, SceneType.food, SceneType.object];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: scenes.map((scene) {
        final selected = manualScene == scene;
        final autoResolved = resolvedScene == scene;

        return GestureDetector(
          onTap: () => onChanged(scene),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: autoResolved
                    ? const Color(0xFFB7FF85)
                    : Colors.white.withValues(alpha: 0.08),
                width: autoResolved ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  scene.label,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (autoResolved) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.check_circle,
                    size: 15,
                    color: selected ? Colors.black : const Color(0xFFB7FF85),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CameraPill extends StatelessWidget {
  const _CameraPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Ink(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
