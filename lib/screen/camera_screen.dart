import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import '../portrait/portrait_mode_handler.dart';
import '../portrait/portrait_overlay_painter.dart';
import '../portrait/portrait_scene_state.dart';
import '../subject_detection.dart'
    show detectModelPath, detectionConfidenceThreshold;
import '../subject_selector.dart';

const String poseModelPath = 'yolov8n-pose_float16.tflite';
const double poseConfidenceThreshold = 0.2;

class CameraScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;

  const CameraScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const List<double> _zoomPresets = [0.5, 1.0, 2.0];

  final YOLOViewController _cameraController = YOLOViewController();
  final SubjectSelector _subjectSelector = const SubjectSelector(
    wSize: 0.35,
    wCenter: 0.25,
    wClass: 0.2,
    wConfidence: 0.1,
    wSaliency: 0.1,
    threshold: 0.3,
  );
  final PortraitModeHandler _portraitHandler = PortraitModeHandler();

  final List<_DetectionBox> _detections = [];

  Size _previewSize = Size.zero;
  int _detectedCount = 0;
  int _personCount = 0;
  int _objectCount = 0;
  String _guidance = 'Scene is balanced';
  String? _mainSubjectLabel;
  _TrackedSubject? _currentMainSubject;
  _TrackedSubject? _lockedSubject;
  double _currentZoom = 1.0;
  double _selectedZoom = 1.0;
  bool _isFrontCamera = false;
  bool _isSaving = false;
  bool _showFlash = false;

  // ─── 인물 모드 UI 상태 ─────────────────────────────
  bool _isPortraitMode = false;

  CoachingResult _currentCoaching = const CoachingResult(
    message: '카메라를 사람에게 향해주세요',
    priority: CoachingPriority.critical,
    confidence: 1.0,
  );

  OverlayData _overlayData = OverlayData(
    coaching: const CoachingResult(
      message: '',
      priority: CoachingPriority.critical,
      confidence: 0.0,
    ),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_portraitHandler.init());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _cameraController.restartCamera();
      await _cameraController.setZoomLevel(_selectedZoom);
    });
  }

  // ─── 모드 전환 ───────────────────────────────────────
  void _togglePortraitMode() {
    setState(() {
      _isPortraitMode = !_isPortraitMode;
      _detections.clear();
      _detectedCount = 0;
      _personCount = 0;
      _objectCount = 0;
      _guidance = _isPortraitMode ? '' : 'Scene is balanced';
      _mainSubjectLabel = null;
      _currentMainSubject = null;
      _lockedSubject = null;
      _currentCoaching = const CoachingResult(
        message: '카메라를 사람에게 향해주세요',
        priority: CoachingPriority.critical,
        confidence: 1.0,
      );
      _overlayData = OverlayData(
        coaching: const CoachingResult(
          message: '',
          priority: CoachingPriority.critical,
          confidence: 0.0,
        ),
      );
      _portraitHandler.reset();
    });
  }

  // ─── 좌표 / 유틸리티 ──────────────────────────────────
  Rect _toPreviewRect(Rect normalizedBox, Size previewSize) {
    return Rect.fromLTRB(
      (normalizedBox.left * previewSize.width).clamp(0.0, previewSize.width),
      (normalizedBox.top * previewSize.height).clamp(0.0, previewSize.height),
      (normalizedBox.right * previewSize.width).clamp(0.0, previewSize.width),
      (normalizedBox.bottom * previewSize.height).clamp(0.0, previewSize.height),
    );
  }

  SubjectSelectionResult _selectMainSubject(
    List<YOLOResult> results,
    Size previewSize,
  ) {
    final detections = results
        .asMap()
        .entries
        .map(
          (entry) => SubjectDetection(
            id: entry.key,
            normalizedBox: Rect.fromLTRB(
              entry.value.normalizedBox.left,
              entry.value.normalizedBox.top,
              entry.value.normalizedBox.right,
              entry.value.normalizedBox.bottom,
            ),
            className: entry.value.className,
            confidence: entry.value.confidence,
          ),
        )
        .toList();

    return _subjectSelector.selectMainSubject(
      detections: detections,
      imageSize: previewSize,
    );
  }

  _TrackedSubject? _subjectFromResult(YOLOResult result, Size previewSize) {
    final rect = _toPreviewRect(result.normalizedBox, previewSize);
    return _TrackedSubject(
      className: result.className,
      normalizedBox: Rect.fromLTRB(
        result.normalizedBox.left,
        result.normalizedBox.top,
        result.normalizedBox.right,
        result.normalizedBox.bottom,
      ),
      rect: rect,
      confidence: result.confidence,
    );
  }

  int? _matchLockedSubject(List<YOLOResult> results) {
    final locked = _lockedSubject;
    if (locked == null || results.isEmpty) return null;

    int? bestIndex;
    double bestScore = 0;

    for (final entry in results.asMap().entries) {
      final result = entry.value;
      final sameClass =
          result.className.toLowerCase() == locked.className.toLowerCase();
      final iou = _intersectionOverUnion(
        locked.normalizedBox,
        Rect.fromLTRB(
          result.normalizedBox.left, result.normalizedBox.top,
          result.normalizedBox.right, result.normalizedBox.bottom,
        ),
      );
      final centerDistance = (
        Offset(result.normalizedBox.center.dx, result.normalizedBox.center.dy) -
        Offset(locked.normalizedBox.center.dx, locked.normalizedBox.center.dy)
      ).distance;
      final distanceScore = (1 - (centerDistance / 0.45)).clamp(0.0, 1.0);
      final classScore = sameClass ? 1.0 : 0.0;
      final score = (classScore * 0.45) + (iou * 0.35) + (distanceScore * 0.20);

      if (score > bestScore) {
        bestScore = score;
        bestIndex = entry.key;
      }
    }

    return bestScore < 0.35 ? null : bestIndex;
  }

  double _intersectionOverUnion(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;
    return unionArea <= 0 ? 0 : intersectionArea / unionArea;
  }

  void _toggleSubjectLock() {
    setState(() {
      if (_lockedSubject != null) {
        _lockedSubject = null;
        return;
      }
      if (_currentMainSubject != null) {
        _lockedSubject = _currentMainSubject;
      }
    });
  }

  // ─── 인물 모드: 포즈 결과 처리 (handler에 위임) ────────────
  CoachingResult? _prevCoaching;
  int _prevPersonCount = -1;

  void _handlePoseDetections(List<YOLOResult> results) {
    if (!mounted) return;

    _portraitHandler.isFrontCamera = _isFrontCamera;
    final analysis = _portraitHandler.processResults(
      results,
      captureFrame: () => _cameraController.captureFrame(),
    );

    // 오버레이는 항상 업데이트 (키포인트 위치 변경)
    _overlayData = analysis.overlayData;

    // 코칭 메시지나 personCount가 바뀌었을 때만 전체 setState
    final coachingChanged = _prevCoaching?.message != analysis.coaching.message ||
        _prevCoaching?.priority != analysis.coaching.priority;
    final countChanged = _prevPersonCount != analysis.personCount;

    if (coachingChanged || countChanged) {
      _prevCoaching = analysis.coaching;
      _prevPersonCount = analysis.personCount;

      final previewSize = _previewSize == Size.zero
          ? MediaQuery.sizeOf(context)
          : _previewSize;

      setState(() {
        _detectedCount = analysis.personCount;
        _personCount = analysis.personCount;
        _objectCount = 0;
        _currentCoaching = analysis.coaching;
        _detections.clear();

        if (analysis.hasPersonStable) {
          final persons = results
              .where((r) => r.className.toLowerCase() == 'person')
              .toList();
          if (persons.isNotEmpty) {
            final main = persons.reduce((a, b) {
              final aa = a.normalizedBox.width * a.normalizedBox.height;
              final ab = b.normalizedBox.width * b.normalizedBox.height;
              return aa >= ab ? a : b;
            });
            _detections.add(_DetectionBox(
              rect: _toPreviewRect(
                Rect.fromLTRB(
                  main.normalizedBox.left, main.normalizedBox.top,
                  main.normalizedBox.right, main.normalizedBox.bottom,
                ),
                previewSize,
              ),
              className: 'person',
              confidence: main.confidence,
              isMainSubject: true,
            ));
          }
        }
      });
    } else {
      // 코칭 안 바뀌면 오버레이만 리페인트 (가벼움)
      setState(() {});
    }
  }

  // ─── 일반 모드: 탐지 결과 처리 ──────────────────────────
  void _handleDetections(List<YOLOResult> results) {
    if (!mounted) return;

    final previewSize = _previewSize == Size.zero
        ? MediaQuery.sizeOf(context)
        : _previewSize;
    final selection = _selectMainSubject(results, previewSize);
    final lockedIndex = _matchLockedSubject(results);
    final mainId = _lockedSubject != null
        ? lockedIndex
        : selection.best?.detection.id;
    final currentMain = mainId == null
        ? null
        : _subjectFromResult(results[mainId], previewSize);
    final visibleResults = _lockedSubject != null
        ? (mainId == null ? <YOLOResult>[] : <YOLOResult>[results[mainId]])
        : results;

    setState(() {
      _detectedCount = visibleResults.length;
      _personCount = visibleResults
          .where((result) => result.className.toLowerCase() == 'person')
          .length;
      _objectCount = visibleResults.length - _personCount;
      _guidance = _lockedSubject != null
          ? (currentMain == null ? '고정한 피사체를 찾는 중이에요.' : '피사체 고정 중')
          : selection.guidance;
      _mainSubjectLabel = _lockedSubject != null
          ? (currentMain?.className ?? _lockedSubject?.className)
          : selection.best?.detection.className;
      _currentMainSubject = currentMain;
      if (_lockedSubject != null && currentMain != null) {
        _lockedSubject = currentMain;
      }

      _detections
        ..clear()
        ..addAll(
          visibleResults.asMap().entries.map(
            (entry) => _DetectionBox(
              rect: _lockedSubject != null
                  ? (currentMain?.rect ??
                        _toPreviewRect(entry.value.normalizedBox, previewSize))
                  : _toPreviewRect(entry.value.normalizedBox, previewSize),
              className: entry.value.className,
              confidence: entry.value.confidence,
              isMainSubject: _lockedSubject != null ? true : entry.key == mainId,
            ),
          ),
        );
    });
  }

  Future<void> _setZoom(double zoomLevel) async {
    setState(() {
      _selectedZoom = zoomLevel;
    });
    await _cameraController.setZoomLevel(zoomLevel);
  }

  Future<void> _switchCamera() async {
    await _cameraController.switchCamera();
    if (!mounted) return;

    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _currentZoom = 1.0;
      _selectedZoom = 1.0;
      _detections.clear();
      _detectedCount = 0;
      _personCount = 0;
      _objectCount = 0;
      _guidance = _isPortraitMode ? '' : 'Scene is balanced';
      _mainSubjectLabel = null;
      _currentMainSubject = null;
      _lockedSubject = null;
    });

    await _cameraController.setZoomLevel(1.0);
  }

  Future<void> _captureAndSavePhoto() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) return;
      }

      final bytes = await _cameraController.captureFrame();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to capture camera frame.');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await Gal.putImageBytes(bytes, name: 'pozy_$timestamp');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo saved to gallery.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save photo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _showFlash = true;
        });
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          setState(() {
            _showFlash = false;
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController.stop();
    _portraitHandler.dispose();
    super.dispose();
  }

  // ─── UI ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                _previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                return YOLOView(
                  key: ValueKey('yolo_${_isPortraitMode ? 'pose' : 'detect'}'),
                  controller: _cameraController,
                  modelPath: _isPortraitMode ? poseModelPath : detectModelPath,
                  task: _isPortraitMode ? YOLOTask.pose : YOLOTask.detect,
                  useGpu: true,
                  showNativeUI: false,
                  showOverlays: false,
                  confidenceThreshold: _isPortraitMode
                      ? poseConfidenceThreshold
                      : detectionConfidenceThreshold,
                  streamingConfig: const YOLOStreamingConfig.withPoses(),
                  lensFacing: LensFacing.back,
                  onResult: _isPortraitMode
                      ? _handlePoseDetections
                      : _handleDetections,
                  onZoomChanged: (zoomLevel) {
                    if (!mounted) return;
                    setState(() { _currentZoom = zoomLevel; });
                  },
                );
              },
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x4D000000), Color(0x00000000), Color(0x00000000), Color(0x66000000)],
                    stops: [0, 0.2, 0.8, 1],
                  ),
                ),
              ),
            ),
            if (_isPortraitMode)
              IgnorePointer(
                child: CustomPaint(
                  painter: PortraitOverlayPainter(data: _overlayData),
                  size: Size.infinite,
                ),
              )
            else
              IgnorePointer(
                child: CustomPaint(painter: _ThirdsGridPainter(), size: Size.infinite),
              ),
            if (!_isPortraitMode)
              IgnorePointer(
                child: CustomPaint(
                  painter: _CameraDetectionPainter(detections: _detections),
                  size: Size.infinite,
                ),
              ),
            if (_isPortraitMode) _buildCoachingOverlay(),
            Positioned(
              top: 8, left: 16, right: 16,
              child: _isPortraitMode
                  ? _buildPortraitTopBar()
                  : _TopCameraBar(
                      onBack: widget.onBack,
                      detectedCount: _detectedCount,
                      personCount: _personCount,
                      objectCount: _objectCount,
                      guidance: _guidance,
                      mainSubjectLabel: _mainSubjectLabel,
                      isFrontCamera: _isFrontCamera,
                      currentZoom: _currentZoom,
                      isLocked: _lockedSubject != null,
                      canLock: _currentMainSubject != null,
                      onToggleLock: _toggleSubjectLock,
                    ),
            ),
            Positioned(
              left: 16, right: 16,
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: _BottomCameraControls(
                zoomPresets: _zoomPresets,
                selectedZoom: _selectedZoom,
                isSaving: _isSaving,
                onSelectZoom: _setZoom,
                onGallery: () => widget.onMoveTab(1),
                onCapture: _captureAndSavePhoto,
                onFlipCamera: _switchCamera,
                isPortraitMode: _isPortraitMode,
                onTogglePortraitMode: _togglePortraitMode,
                shotTypeLabel: _isPortraitMode ? _shotTypeLabel() : null,
              ),
            ),
            if (_showFlash) Container(color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ─── 인물 모드 코칭 오버레이 ────────────────────────────
  Widget _buildCoachingOverlay() {
    final isPerfect = _currentCoaching.priority == CoachingPriority.perfect;
    final isCritical = _currentCoaching.priority == CoachingPriority.critical;
    final isComposition = _currentCoaching.priority == CoachingPriority.composition;

    // 상태별 그라데이션 배경
    final bgGradient = isPerfect
        ? const LinearGradient(colors: [Color(0xCC16A34A), Color(0xCC22C55E)])
        : isCritical
            ? const LinearGradient(colors: [Color(0xCCDC2626), Color(0xCCEF4444)])
            : isComposition
                ? const LinearGradient(colors: [Color(0xCCD97706), Color(0xCCF59E0B)])
                : const LinearGradient(colors: [Color(0xCC2563EB), Color(0xCC3B82F6)]);

    // 상태별 아이콘
    final icon = isPerfect
        ? Icons.check_circle_rounded
        : isCritical
            ? Icons.error_rounded
            : isComposition
                ? Icons.tune_rounded
                : Icons.lightbulb_outline_rounded;

    final lighting = _portraitHandler.lastLighting;
    final lightConf = _portraitHandler.lastLightingConf;

    return Positioned(
      top: 60, left: 16, right: 16,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.3),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Column(
          key: ValueKey('${_portraitHandler.stableMessage}_${lighting.name}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 코칭 메시지 카드
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                gradient: bgGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _portraitHandler.stableMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 조명 뱃지
            if (lighting != LightingCondition.unknown && lightConf > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _portraitHandler.lightingBadgeColor(lighting).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wb_sunny_rounded,
                          color: _portraitHandler.lightingBadgeColor(lighting), size: 13),
                        const SizedBox(width: 5),
                        Text(
                          '${_portraitHandler.lightingLabel(lighting)} (${(lightConf * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                            color: _portraitHandler.lightingBadgeColor(lighting),
                            fontSize: 11, fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortraitTopBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: widget.onBack),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person, color: Colors.amber, size: 18),
              const SizedBox(width: 6),
              const Text('인물', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text(
                '${_isFrontCamera ? 'Front' : 'Back'} | ${_currentZoom.toStringAsFixed(1)}x',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _shotTypeLabel() {
    if (_currentCoaching.priority == CoachingPriority.critical) return '';
    switch (_overlayData.shotType) {
      case ShotType.extremeCloseUp: return '익스트림 클로즈업';
      case ShotType.closeUp: return '클로즈업';
      case ShotType.upperBody: return '상반신';
      case ShotType.kneeShot: return '무릎샷';
      case ShotType.fullBody: return '전신';
      case ShotType.environmental: return '환경 포트레이트';
      default: return '인물 코칭 활성';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 위젯: 상단 카메라 바 (일반 모드)
// ═══════════════════════════════════════════════════════════════
class _TopCameraBar extends StatelessWidget {
  final VoidCallback onBack;
  final int detectedCount;
  final int personCount;
  final int objectCount;
  final String guidance;
  final String? mainSubjectLabel;
  final bool isFrontCamera;
  final double currentZoom;
  final bool isLocked;
  final bool canLock;
  final VoidCallback onToggleLock;

  const _TopCameraBar({
    required this.onBack, required this.detectedCount, required this.personCount,
    required this.objectCount, required this.guidance, required this.mainSubjectLabel,
    required this.isFrontCamera, required this.currentZoom, required this.isLocked,
    required this.canLock, required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
        const Spacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${isFrontCamera ? 'Front' : 'Back'} | ${currentZoom.toStringAsFixed(1)}x'),
                  Text('Total: $detectedCount  Person: $personCount  Object: $objectCount'),
                  Text(mainSubjectLabel == null ? guidance : 'Main: $mainSubjectLabel'),
                  if (mainSubjectLabel != null) Text(guidance),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: canLock || isLocked ? onToggleLock : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isLocked ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: isLocked ? const Color(0xFF38BDF8) : Colors.white24),
                        ),
                        child: Text(
                          isLocked ? '고정 해제' : '피사체 고정',
                          style: TextStyle(
                            color: isLocked ? const Color(0xFF0F172A) : (canLock ? Colors.white : Colors.white54),
                            fontSize: 11, fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 위젯: 하단 카메라 컨트롤 (삼성 카메라 스타일)
// ═══════════════════════════════════════════════════════════════
class _BottomCameraControls extends StatefulWidget {
  final List<double> zoomPresets;
  final double selectedZoom;
  final bool isSaving;
  final ValueChanged<double> onSelectZoom;
  final VoidCallback onGallery;
  final Future<void> Function() onCapture;
  final Future<void> Function() onFlipCamera;
  final bool isPortraitMode;
  final VoidCallback onTogglePortraitMode;
  final String? shotTypeLabel;

  const _BottomCameraControls({
    required this.zoomPresets, required this.selectedZoom, required this.isSaving,
    required this.onSelectZoom, required this.onGallery, required this.onCapture,
    required this.onFlipCamera, required this.isPortraitMode,
    required this.onTogglePortraitMode, this.shotTypeLabel,
  });

  @override
  State<_BottomCameraControls> createState() => _BottomCameraControlsState();
}

class _BottomCameraControlsState extends State<_BottomCameraControls> {
  static const List<String> _modes = ['일반', '인물'];
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.isPortraitMode ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant _BottomCameraControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIndex = widget.isPortraitMode ? 1 : 0;
    if (_selectedIndex != newIndex) {
      _selectedIndex = newIndex;
    }
  }

  void _onModeTap(int index) {
    if (index == _selectedIndex) return;
    setState(() { _selectedIndex = index; });
    widget.onTogglePortraitMode();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 샷 타입 라벨 (인물 모드일 때)
        if (widget.isPortraitMode && widget.shotTypeLabel != null && widget.shotTypeLabel!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(widget.shotTypeLabel!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ),

        // 줌 프리셋
        Container(
          height: 40, padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: widget.zoomPresets.map((zoom) => _ZoomPill(
              label: '${zoom.toStringAsFixed(zoom == zoom.truncateToDouble() ? 0 : 1)}x',
              selected: (widget.selectedZoom - zoom).abs() < 0.05,
              onTap: () => widget.onSelectZoom(zoom),
            )).toList(),
          ),
        ),
        const SizedBox(height: 20),

        // ─── 삼성 스타일 모드 탭 (스와이프 가능) ─────────
        SizedBox(
          height: 36,
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;
              if (details.primaryVelocity! < -200 && _selectedIndex < _modes.length - 1) {
                _onModeTap(_selectedIndex + 1);
              } else if (details.primaryVelocity! > 200 && _selectedIndex > 0) {
                _onModeTap(_selectedIndex - 1);
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_modes.length, (i) {
                final selected = i == _selectedIndex;
                return GestureDetector(
                  onTap: () => _onModeTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _modes[i],
                          style: TextStyle(
                            color: selected ? const Color(0xFFFFC107) : Colors.white54,
                            fontSize: selected ? 14 : 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: selected ? 6 : 0,
                          height: selected ? 6 : 0,
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFFFC107) : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 촬영 버튼 + 갤러리 + 카메라 전환
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GlassIconButton(icon: Icons.photo_library_outlined, onTap: widget.onGallery, diameter: 48),
            const SizedBox(width: 48),
            GestureDetector(
              onTap: widget.isSaving ? null : widget.onCapture,
              child: Container(
                width: 80, height: 80,
                decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8))],
                ),
                child: Center(
                  child: widget.isSaving
                      ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF333333)))
                      : Container(width: 64, height: 64, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x1A333333), width: 2))),
                ),
              ),
            ),
            const SizedBox(width: 48),
            _GlassIconButton(icon: Icons.flip_camera_ios_outlined, onTap: widget.onFlipCamera, diameter: 48),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 공용 위젯
// ═══════════════════════════════════════════════════════════════

class _GlassIconButton extends StatelessWidget {
  final IconData icon; final VoidCallback onTap; final double diameter;
  const _GlassIconButton({required this.icon, required this.onTap, this.diameter = 40});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(999),
      child: Container(
        width: diameter, height: diameter,
        decoration: BoxDecoration(color: const Color(0x66333333), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0x4DFFFFFF), width: 1)),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: diameter * 0.45),
      ),
    );
  }
}

class _ZoomPill extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _ZoomPill({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: selected ? 40 : 34, height: selected ? 32 : 28, alignment: Alignment.center,
        decoration: BoxDecoration(color: selected ? Colors.white : const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(color: selected ? const Color(0xFF333333) : Colors.white, fontSize: selected ? 11 : 10, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _ThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x33FFFFFF)..strokeWidth = 1;
    final dx1 = size.width / 3, dx2 = size.width * 2 / 3;
    final dy1 = size.height / 3, dy2 = size.height * 2 / 3;
    canvas.drawLine(Offset(dx1, 0), Offset(dx1, size.height), paint);
    canvas.drawLine(Offset(dx2, 0), Offset(dx2, size.height), paint);
    canvas.drawLine(Offset(0, dy1), Offset(size.width, dy1), paint);
    canvas.drawLine(Offset(0, dy2), Offset(size.width, dy2), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DetectionBox {
  final Rect rect; final String className; final double confidence; final bool isMainSubject;
  const _DetectionBox({required this.rect, required this.className, required this.confidence, required this.isMainSubject});
  bool get isPerson => className.toLowerCase() == 'person';
}

class _TrackedSubject {
  final String className; final Rect normalizedBox; final Rect rect; final double confidence;
  const _TrackedSubject({required this.className, required this.normalizedBox, required this.rect, required this.confidence});
}

class _CameraDetectionPainter extends CustomPainter {
  final List<_DetectionBox> detections;
  const _CameraDetectionPainter({required this.detections});
  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final accent = detection.isMainSubject ? const Color(0xFF38BDF8)
          : detection.isPerson ? const Color(0xFF4ADE80) : const Color(0xFFFB923C);
      final rect = Rect.fromLTRB(
        detection.rect.left.clamp(0.0, size.width), detection.rect.top.clamp(0.0, size.height),
        detection.rect.right.clamp(0.0, size.width), detection.rect.bottom.clamp(0.0, size.height),
      );
      canvas.drawRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.55)..style = PaintingStyle.stroke..strokeWidth = detection.isMainSubject ? 4 : 3);
      canvas.drawRect(rect, Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = detection.isMainSubject ? 3 : 2);
      final label = '${detection.className} ${(detection.confidence * 100).toStringAsFixed(1)}%';
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: accent, fontSize: detection.isMainSubject ? 13 : 12, fontWeight: FontWeight.w700, shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, (rect.top - 20).clamp(0.0, size.height - 20)));
    }
  }
  @override
  bool shouldRepaint(covariant _CameraDetectionPainter oldDelegate) => oldDelegate.detections != detections;
}
