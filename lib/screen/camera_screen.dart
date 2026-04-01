import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';

import '../feature/a_cut/layer/evaluation/photo_evaluation_service.dart';
import '../models/composition_candidate.dart';
import '../models/tracked_subject.dart';
import '../services/composition_candidate_generator.dart';
import '../services/composition_feedback_service.dart';
import '../services/composition_stabilizer.dart';
import '../services/model_composition_scorer.dart';
import '../services/level_provider.dart'
    show LevelProviderBase, StubLevelProvider;
import '../subject_detection.dart'
    show detectModelPath, detectionConfidenceThreshold;
import '../subject_selector.dart';
import '../widget/composition_overlay_painter.dart';
import 'single_photo_eval_screen.dart';

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
  final SubjectSelector _subjectSelector = const SubjectSelector();
  final List<_DetectionBox> _detections = [];

  Size _previewSize = Size.zero;
  int _detectedCount = 0;
  String? _mainSubjectLabel;
  TrackedSubject? _currentMainSubject;
  TrackedSubject? _lockedSubject;
  double _currentZoom = 1.0;
  double _selectedZoom = 1.0;
  bool _isFrontCamera = false;
  bool _isSaving = false;
  bool _showFlash = false;

  // ── Composition ─────────────────────────────────────────────────────────────
  bool _showCompDebug = false;
  CompositionCandidate? _activeCompositionCandidate;
  FeedbackResult _feedbackResult = FeedbackResult.guide;

  final CompositionCandidateGenerator _candidateGenerator =
      CompositionCandidateGenerator();
  // ModelCompositionScorer fuses AADB model scores with heuristic geometry
  // scores.  It falls back to pure heuristic if the model file is absent.
  final ModelCompositionScorer _scorer = ModelCompositionScorer();
  final CompositionStabilizer _stabilizer = CompositionStabilizer();
  final CompositionFeedbackService _feedbackService = CompositionFeedbackService();
  final LevelProviderBase _levelProvider = const StubLevelProvider();

  static const _kCompositionInterval = Duration(milliseconds: 200);
  static const _kSubjectLossGracePeriod = Duration(milliseconds: 500);
  DateTime? _lastCompositionTime;
  DateTime? _lastSubjectTime;
  List<CompositionCandidate> _cachedRankedCandidates = [];
  Rect? _smoothedRenderRect;

  final Stopwatch _compStopwatch = Stopwatch();
  int _lastCompTimeMs = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _cameraController.restartCamera();
      await _cameraController.setZoomLevel(_selectedZoom);
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // │ Detections & Composition Pipeline                                       │
  // ───────────────────────────────────────────────────────────────────────────

  void _handleDetections(List<YOLOResult> results) {
    if (!mounted) return;
    final now = DateTime.now();
    _compStopwatch.reset();
    _compStopwatch.start();

    final previewSize =
        _previewSize == Size.zero ? MediaQuery.sizeOf(context) : _previewSize;
    final selection = _selectMainSubject(results, previewSize);
    final lockedIndex = _matchLockedSubject(results);
    final mainId =
        _lockedSubject != null ? lockedIndex : selection.best?.detection.id;
    final currentMain =
        mainId == null ? null : _subjectFromResult(results[mainId], previewSize);

    if (currentMain != null) {
      _lastSubjectTime = now;
    }

    CompositionCandidate? newActiveCandidate;
    final bool hasLiveSubject = _lastSubjectTime != null &&
        now.difference(_lastSubjectTime!) < _kSubjectLossGracePeriod;

    if (hasLiveSubject && currentMain != null) {
      final subjectBox = currentMain.normalizedBox;

      // 1. STABILIZE CANDIDATE ID: Throttle candidate re-evaluation.
      if (_lastCompositionTime == null ||
          now.difference(_lastCompositionTime!) >= _kCompositionInterval) {
        _lastCompositionTime = now;
        final candidates = _candidateGenerator.generate(
          previewSize: previewSize,
          subjectNormalized: subjectBox,
        );
        // Synchronous: returns heuristic scores fused with cached model scores.
        _cachedRankedCandidates = _scorer.score(
          candidates: candidates,
          subjectNormalized: subjectBox,
          previewSize: previewSize,
        );
        // Async fire-and-forget: captures current frame and runs AADB model on
        // top-K candidates.  Updated scores are used on the next throttle tick.
        _scheduleModelUpdate(previewSize);
      }

      final stableBest = _stabilizer.stabilize(_cachedRankedCandidates);
      if (stableBest != null) {
        // 2. RETARGET: Update box position to follow subject.
        final retargeted = _retargetCandidate(stableBest, subjectBox);
        
        // 3. SMOOTH: Apply EMA smoothing for rendering.
        if (_smoothedRenderRect == null) {
          _smoothedRenderRect = retargeted.normalizedRect;
        } else {
          _smoothedRenderRect =
              _lerp(_smoothedRenderRect!, retargeted.normalizedRect, 0.25);
        }
        newActiveCandidate = retargeted.copyWith(smoothedRect: _smoothedRenderRect);
      }
    } else {
      // No subject or grace period expired.
      _stabilizer.reset();
      _feedbackService.reset();
      _scorer.reset();
      _cachedRankedCandidates = [];
      _smoothedRenderRect = null;
      newActiveCandidate = null;
    }

    // 4. CALCULATE FEEDBACK: Determine alignment and readiness.
    final feedback = _feedbackService.calculateFeedback(
        activeCandidate: newActiveCandidate, subject: currentMain);

    _compStopwatch.stop();

    setState(() {
      _detectedCount = results.length;
      _mainSubjectLabel =
          _lockedSubject?.className ?? selection.best?.detection.className;
      _currentMainSubject = currentMain;
      if (_lockedSubject != null && currentMain != null) {
        _lockedSubject = currentMain;
      }

      _detections.clear();
      _detections.addAll(
        results
            .asMap()
            .entries
            .map((e) => _DetectionBox.fromYolo(e.value, previewSize, e.key == mainId)),
      );

      _activeCompositionCandidate = newActiveCandidate;
      _feedbackResult = feedback;
      _lastCompTimeMs = _compStopwatch.elapsedMilliseconds;
    });
  }

  // ── Model inference fire-and-forget ────────────────────────────────────────

  /// Captures the current camera frame and asks [_scorer] to update its
  /// internal model scores asynchronously.
  ///
  /// This is called once per composition throttle tick.  It never blocks
  /// [_handleDetections] — any exception is silently swallowed and the scorer
  /// continues in heuristic-only mode.
  Future<void> _scheduleModelUpdate(Size previewSize) async {
    if (_scorer.isInferring) return; // previous inference still running — skip
    final Uint8List? frameBytes;
    try {
      frameBytes = await _cameraController.captureFrame();
    } catch (_) {
      return; // capture failed — skip this tick
    }
    if (frameBytes == null || frameBytes.isEmpty || !mounted) return;
    // Fire-and-forget: errors inside updateModelScores are handled gracefully.
    unawaited(_scorer.updateModelScores(
      frameBytes: frameBytes,
      heuristicTop: _cachedRankedCandidates,
      frameSize: previewSize,
    ));
  }

  CompositionCandidate _retargetCandidate(
      CompositionCandidate candidate, Rect subject) {
    final scx = subject.center.dx;
    final scy = subject.center.dy;
    final nw = candidate.normalizedRect.width;
    final nh = candidate.normalizedRect.height;
    Rect newRect;

    if (candidate.id.endsWith('_center')) {
      newRect = Rect.fromLTWH((1 - nw) / 2, (1 - nh) / 2, nw, nh);
    } else if (candidate.id.endsWith('_subject')) {
      newRect = Rect.fromLTWH(scx - nw / 2, scy - nh / 2, nw, nh);
    } else if (candidate.id.endsWith('_thirds_tl')) {
      newRect = Rect.fromLTWH(scx - nw / 3, scy - nh / 3, nw, nh);
    } else if (candidate.id.endsWith('_thirds_tr')) {
      newRect = Rect.fromLTWH(scx - 2 * nw / 3, scy - nh / 3, nw, nh);
    } else if (candidate.id.endsWith('_contained')) {
      newRect = Rect.fromLTWH(scx - nw / 2, scy - nh / 2, nw, nh);
    } else {
      newRect = candidate.normalizedRect;
    }

    return candidate.copyWith(normalizedRect: _clamp(newRect));
  }

  Rect _lerp(Rect prev, Rect target, double alpha) {
    return Rect.fromLTRB(
      prev.left + (target.left - prev.left) * alpha,
      prev.top + (target.top - prev.top) * alpha,
      prev.right + (target.right - prev.right) * alpha,
      prev.bottom + (target.bottom - prev.bottom) * alpha,
    );
  }
  
  Rect _clamp(Rect rect) {
    final w = rect.width.clamp(0.0, 1.0).toDouble();
    final h = rect.height.clamp(0.0, 1.0).toDouble();
    final left = rect.left.clamp(0.0, math.max(0.0, 1.0 - w)).toDouble();
    final top = rect.top.clamp(0.0, math.max(0.0, 1.0 - h)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
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
            LayoutBuilder(
              builder: (context, constraints) {
                _previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                return YOLOView(
                  controller: _cameraController,
                  modelPath: detectModelPath,
                  task: YOLOTask.detect,
                  useGpu: false,
                  showNativeUI: false,
                  showOverlays: false,
                  confidenceThreshold: detectionConfidenceThreshold,
                  streamingConfig: const YOLOStreamingConfig.minimal(),
                  lensFacing: LensFacing.back,
                  onResult: _handleDetections,
                  onZoomChanged: (z) => setState(() => _currentZoom = z),
                );
              },
            ),
            const IgnorePointer(child: _GradientOverlay()),
            IgnorePointer(child: CustomPaint(painter: _ThirdsGridPainter(), size: Size.infinite)),
            IgnorePointer(child: CustomPaint(painter: _CameraDetectionPainter(detections: _detections), size: Size.infinite)),
            IgnorePointer(
              child: CustomPaint(
                painter: CompositionOverlayPainter(
                  activeCandidate: _activeCompositionCandidate,
                  feedback: _feedbackResult,
                  showDebug: _showCompDebug,
                  tiltAngle: _levelProvider.isLevel() ? _levelProvider.tiltAngle : null,
                  scorerDebug: _showCompDebug ? _scorer.debugSummary : null,
                ),
                size: Size.infinite,
              ),
            ),
            Positioned(
              top: 8, left: 16, right: 16,
              child: _TopCameraBar(
                onBack: widget.onBack,
                detectedCount: _detectedCount,
                mainSubjectLabel: _mainSubjectLabel,
                isFrontCamera: _isFrontCamera,
                currentZoom: _currentZoom,
                isLocked: _lockedSubject != null,
                canLock: _currentMainSubject != null,
                onToggleLock: _toggleSubjectLock,
                showCompDebug: _showCompDebug,
                onToggleCompDebug: () => setState(() => _showCompDebug = !_showCompDebug),
                lastCompTimeMs: _lastCompTimeMs,
              ),
            ),
            Positioned(
              left: 16, right: 16, bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: _BottomCameraControls(
                zoomPresets: _zoomPresets,
                selectedZoom: _selectedZoom,
                isSaving: _isSaving,
                onSelectZoom: _setZoom,
                onGallery: () => widget.onMoveTab(1),
                onCapture: _captureAndSavePhoto,
                onFlipCamera: _switchCamera,
              ),
            ),
            if (_showFlash) Container(color: Colors.white),
          ],
        ),
      ),
    );
  }

  SubjectSelectionResult _selectMainSubject(List<YOLOResult> results, Size previewSize) {
    final detections = results.asMap().entries.map((entry) => SubjectDetection(
            id: entry.key,
            normalizedBox: Rect.fromLTRB(
              entry.value.normalizedBox.left, entry.value.normalizedBox.top,
              entry.value.normalizedBox.right, entry.value.normalizedBox.bottom),
            className: entry.value.className,
            confidence: entry.value.confidence,
          ),
        ).toList();
    return _subjectSelector.selectMainSubject(detections: detections, imageSize: previewSize);
  }

  TrackedSubject? _subjectFromResult(YOLOResult result, Size previewSize) {
    final normalizedRect = Rect.fromLTRB(
        result.normalizedBox.left, result.normalizedBox.top,
        result.normalizedBox.right, result.normalizedBox.bottom);
    final rect = _toPreviewRect(normalizedRect, previewSize);
    return TrackedSubject(
      className: result.className,
      normalizedBox: normalizedRect,
      rect: rect,
      confidence: result.confidence,
    );
  }

  Rect _toPreviewRect(Rect normalizedBox, Size previewSize) {
    return Rect.fromLTRB(
      (normalizedBox.left * previewSize.width).clamp(0.0, previewSize.width),
      (normalizedBox.top * previewSize.height).clamp(0.0, previewSize.height),
      (normalizedBox.right * previewSize.width).clamp(0.0, previewSize.width),
      (normalizedBox.bottom * previewSize.height).clamp(0.0, previewSize.height),
    );
  }
  
  int? _matchLockedSubject(List<YOLOResult> results) {
    final locked = _lockedSubject;
    if (locked == null || results.isEmpty) return null;
    int? bestIndex;
    double bestScore = 0;
    for (final entry in results.asMap().entries) {
      final result = entry.value;
      final sameClass = result.className.toLowerCase() == locked.className.toLowerCase();
      final normalizedBox = result.normalizedBox;
      final rect = Rect.fromLTRB(normalizedBox.left, normalizedBox.top, normalizedBox.right, normalizedBox.bottom);
      final iou = _intersectionOverUnion(locked.normalizedBox, rect);
      final centerDistance = (result.normalizedBox.center - locked.normalizedBox.center).distance;
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
    if (intersection.isEmpty) return 0.0;
    final unionArea = (a.width * a.height) + (b.width * b.height) - (intersection.width * intersection.height);
    return unionArea <= 0 ? 0.0 : (intersection.width * intersection.height) / unionArea;
  }

  void _toggleSubjectLock() {
    setState(() => _lockedSubject = _lockedSubject == null ? _currentMainSubject : null);
  }

  Future<void> _setZoom(double zoomLevel) async {
    setState(() => _selectedZoom = zoomLevel);
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
      _mainSubjectLabel = null;
      _currentMainSubject = null;
      _lockedSubject = null;
    });
    await _cameraController.setZoomLevel(1.0);
  }

  Future<void> _captureAndSavePhoto() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    Uint8List? capturedBytes;
    String? savedFileName;

    try {
      final hasAccess = await Gal.hasAccess() || await Gal.requestAccess();
      if (!hasAccess) return;
      final bytes = await _cameraController.captureFrame();
      if (bytes == null || bytes.isEmpty) throw Exception('Failed to capture frame.');
      capturedBytes = bytes;
      savedFileName = 'pozy_${DateTime.now().millisecondsSinceEpoch}';
      await Gal.putImageBytes(bytes, name: savedFileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        setState(() => _showFlash = true);
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showFlash = false);
        });
      }
    }

    // ── Post-capture: offer single-photo evaluation ─────────────────────────
    if (capturedBytes != null && mounted) {
      _showPostCaptureSheet(capturedBytes, savedFileName);
    }
  }

  void _showPostCaptureSheet(Uint8List bytes, String? fileName) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PostCaptureSheet(
        onEvaluate: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SinglePhotoEvalScreen(
                imageBytes: bytes,
                fileName: fileName,
                evaluationService: OnDevicePhotoEvaluationService(),
              ),
            ),
          );
        },
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.stop();
    super.dispose();
  }
}

class _TopCameraBar extends StatelessWidget {
  final VoidCallback onBack;
  final int detectedCount;
  final String? mainSubjectLabel;
  final bool isFrontCamera;
  final double currentZoom;
  final bool isLocked;
  final bool canLock;
  final VoidCallback onToggleLock;
  final bool showCompDebug;
  final VoidCallback onToggleCompDebug;
  final int lastCompTimeMs;

  const _TopCameraBar({
    required this.onBack, required this.detectedCount,
    required this.mainSubjectLabel, required this.isFrontCamera,
    required this.currentZoom, required this.isLocked, required this.canLock,
    required this.onToggleLock, required this.showCompDebug,
    required this.onToggleCompDebug, required this.lastCompTimeMs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onToggleCompDebug,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: showCompDebug ? const Color(0xCCFFD700) : const Color(0x66333333),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: showCompDebug ? const Color(0xFFFFD700) : const Color(0x4DFFFFFF), width: 1),
          ),
          alignment: Alignment.center,
          child: Icon(showCompDebug ? Icons.grid_on_outlined : Icons.crop_square_rounded,
              color: showCompDebug ? Colors.black : Colors.white, size: 18),
        ),
      ),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(115),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.35),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${isFrontCamera ? 'Front' : 'Back'} | ${currentZoom.toStringAsFixed(1)}x | ${lastCompTimeMs}ms'),
            Text('Detections: $detectedCount'),
            if (mainSubjectLabel != null) Text('Main: $mainSubjectLabel'),
            if (showCompDebug && canLock)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: GestureDetector(
                  onTap: canLock || isLocked ? onToggleLock : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isLocked ? const Color(0xFF38BDF8) : Colors.white.withAlpha(26),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: isLocked ? const Color(0xFF38BDF8) : Colors.white24),
                    ),
                    child: Text(isLocked ? 'Unlock Subject' : 'Lock Subject',
                        style: TextStyle(color: isLocked ? const Color(0xFF0F172A) : (canLock ? Colors.white : Colors.white54),
                        fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double diameter;

  const _GlassIconButton({required this.icon, required this.onTap, this.diameter = 40});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: diameter, height: diameter,
        decoration: BoxDecoration(
          color: const Color(0x66333333),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x4DFFFFFF), width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: diameter * 0.45),
      ),
    );
  }
}

class _BottomCameraControls extends StatelessWidget {
  final List<double> zoomPresets;
  final double selectedZoom;
  final bool isSaving;
  final ValueChanged<double> onSelectZoom;
  final VoidCallback onGallery;
  final Future<void> Function() onCapture;
  final Future<void> Function() onFlipCamera;

  const _BottomCameraControls({
    required this.zoomPresets, required this.selectedZoom, required this.isSaving,
    required this.onSelectZoom, required this.onGallery, required this.onCapture,
    required this.onFlipCamera,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 40,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(115),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: zoomPresets.map((zoom) => _ZoomPill(
                label: '${zoom.toStringAsFixed(zoom == zoom.truncateToDouble() ? 0 : 1)}x',
                selected: (selectedZoom - zoom).abs() < 0.05,
                onTap: () => onSelectZoom(zoom),
              )).toList(),
        ),
      ),
      const SizedBox(height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _GlassIconButton(icon: Icons.photo_library_outlined, onTap: onGallery, diameter: 48),
        const SizedBox(width: 48),
        GestureDetector(
          onTap: isSaving ? null : onCapture,
          child: Container(
            width: 80, height: 80,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8))
            ]),
            child: Center(
              child: isSaving
                  ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF333333)))
                  : Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x1A333333), width: 2)),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 48),
        _GlassIconButton(icon: Icons.flip_camera_ios_outlined, onTap: onFlipCamera, diameter: 48),
      ]),
    ]);
  }
}

class _ZoomPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ZoomPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: selected ? 40 : 34,
        height: selected ? 32 : 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: TextStyle(color: selected ? const Color(0xFF333333) : Colors.white, fontSize: selected ? 11 : 10, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _GradientOverlay extends StatelessWidget {
  const _GradientOverlay();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x4D000000), Color(0x00000000), Color(0x00000000), Color(0x66000000)],
          stops: [0, 0.2, 0.8, 1],
        ),
      ),
    );
  }
}

class _ThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x33FFFFFF)..strokeWidth = 1;
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
  final Rect rect;
  final String className;
  final double confidence;
  final bool isMainSubject;

  const _DetectionBox({ required this.rect, required this.className, required this.confidence, required this.isMainSubject });

  factory _DetectionBox.fromYolo(YOLOResult result, Size previewSize, bool isMain) {
    final normalizedRect = Rect.fromLTRB(
        result.normalizedBox.left, result.normalizedBox.top,
        result.normalizedBox.right, result.normalizedBox.bottom);
    return _DetectionBox(rect: _toPreviewRect(normalizedRect, previewSize), className: result.className, confidence: result.confidence, isMainSubject: isMain);
  }

  static Rect _toPreviewRect(Rect normalizedBox, Size previewSize) {
    return Rect.fromLTRB(
      (normalizedBox.left * previewSize.width).clamp(0.0, previewSize.width),
      (normalizedBox.top * previewSize.height).clamp(0.0, previewSize.height),
      (normalizedBox.right * previewSize.width).clamp(0.0, previewSize.width),
      (normalizedBox.bottom * previewSize.height).clamp(0.0, previewSize.height),
    );
  }
}

class _CameraDetectionPainter extends CustomPainter {
  final List<_DetectionBox> detections;
  const _CameraDetectionPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final accent = detection.isMainSubject ? const Color(0xFF38BDF8) : const Color(0xFFFB923C);
      final rect = detection.rect;
      canvas.drawRect(rect, Paint()..color = Colors.black.withAlpha(140)..style = PaintingStyle.stroke..strokeWidth = detection.isMainSubject ? 4 : 3);
      canvas.drawRect(rect, Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = detection.isMainSubject ? 3 : 2);
    }
  }

  @override
  bool shouldRepaint(covariant _CameraDetectionPainter oldDelegate) => oldDelegate.detections != detections;
}

// ─────────────────────────────────────────────────────────────────────────────
// Post-capture bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Appears after a photo is saved, giving the user the option to evaluate it.
class _PostCaptureSheet extends StatelessWidget {
  final VoidCallback onEvaluate;
  final VoidCallback onDismiss;

  const _PostCaptureSheet({
    required this.onEvaluate,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Text(
            '사진이 저장되었습니다',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'AI가 이 사진의 미적 품질을 평가해드릴 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: onEvaluate,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text(
                '사진 평가하기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: onDismiss,
              child: const Text(
                '나중에',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
