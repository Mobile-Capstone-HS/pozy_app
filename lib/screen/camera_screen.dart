import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import '../coaching/coaching_result.dart';
import '../coaching/pixel_analysis_service.dart';
import '../coaching/object_coaching_engine.dart';
import '../coaching/vlm_composition_service.dart';
import '../subject_detection.dart'
    show detectModelPath, detectionConfidenceThreshold;
import '../subject_selector.dart';

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
  final _cameraController = YOLOViewController();
  final _subjectSelector = const SubjectSelector(
    wSize: 0.35,
    wCenter: 0.25,
    wClass: 0.2,
    wConfidence: 0.1,
    wSaliency: 0.1,
    threshold: 0.3,
  );
  final _objectCoachingEngine = ObjectCoachingEngine();
  final _pixelService = PixelAnalysisService();
  final _vlmService = VlmCompositionService();

  List<double> _zoomPresets = [1.0, 2.0];
  Size _previewSize = Size.zero;
  String _guidance = '구도를 잡는 중...';
  String? _subGuidance;
  CoachingLevel _coachingLevel = CoachingLevel.caution;
  ShootingMode _shootingMode = ShootingMode.object;
  _TrackedSubject? _currentMainSubject;
  _TrackedSubject? _pendingSubject;
  Offset? _tapNorm;
  double _selectedZoom = 1.0;
  bool _isFrontCamera = false;
  bool _isSaving = false;
  bool _showFlash = false;
  bool _torchOn = false;
  Offset? _focusPoint;
  bool _showFocusIndicator = false;
  int _timerSeconds = 0;
  int _countdown = 0;
  double _tiltX = 0.0;
  CoachingResult _nimaResult = const CoachingResult(
    guidance: '구도를 잡는 중...',
    level: CoachingLevel.caution,
  );
  bool _isAnalyzing = false;
  bool _isVlmRefining = false;
  bool _lastPixelWasBad = false;
  Timer? _countdownTimer;
  Timer? _nimaTimer;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _cameraController.restartCamera();
      await _cameraController.setZoomLevel(_selectedZoom);
      await _configureZoomPresets();
    });
    _startTiltMonitoring();
    _nimaTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _runPixelAnalysis();
    });
  }

  void _startTiltMonitoring() {
    try {
      _accelerometerSub =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.normalInterval,
          ).listen((event) {
            _tiltX = (_tiltX * 0.85) + (event.x * 0.15);
          });
    } catch (_) {}
  }

  Future<void> _configureZoomPresets() async {
    double minZoom = 1.0;
    for (int i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      minZoom = await _cameraController.getMinZoomLevel();
      if (minZoom < 1.0) break;
    }
    final next = minZoom < 1.0 ? [minZoom, 1.0, 2.0] : [1.0, 2.0];
    if (next.length == _zoomPresets.length &&
        next.indexed.every((e) => (e.$2 - _zoomPresets[e.$1]).abs() < 0.001)) {
      return;
    }
    setState(() => _zoomPresets = next);
  }

  Future<void> _runPixelAnalysis() async {
    if (_isAnalyzing || !mounted || _isSaving) return;
    _isAnalyzing = true;
    try {
      final bytes = await _cameraController.captureFrame();
      if (bytes == null || bytes.isEmpty || !mounted) return;
      final pixelResult = await _pixelService.analyze(bytes);
      if (!mounted) return;
      if (pixelResult != null) {
        // 밝기 문제 → 직접 표시, VLM 불필요
        _lastPixelWasBad = true;
        setState(() => _nimaResult = pixelResult);
      } else {
        // 밝기 정상 → 직전에 밝기 경고 표시 중이었으면 초기화 후 VLM 호출
        if (_lastPixelWasBad) {
          setState(() => _nimaResult = const CoachingResult(
            guidance: '구도를 잡는 중...',
            level: CoachingLevel.caution,
          ));
        }
        _lastPixelWasBad = false;
        _runVlmGuidance(bytes);
      }
    } finally {
      _isAnalyzing = false;
    }
  }

  Future<void> _runVlmGuidance(List<int> bytes) async {
    if (_isVlmRefining || !mounted) return;
    _isVlmRefining = true;
    try {
      final refined = await _vlmService.refine(bytes);
      if (refined == null || !mounted) return;
      final isGood = refined.guidance.contains('이 정도면');
      setState(() {
        _nimaResult = CoachingResult(
          guidance: refined.guidance,
          level: isGood ? CoachingLevel.good : CoachingLevel.caution,
          subGuidance: refined.subGuidance.isEmpty ? null : refined.subGuidance,
        );
      });
    } finally {
      _isVlmRefining = false;
    }
  }

  SubjectSelectionResult _selectMainSubject(List<YOLOResult> results) {
    return _subjectSelector.selectMainSubject(
      detections: results
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
          .toList(),
      imageSize: _previewSize == Size.zero
          ? MediaQuery.sizeOf(context)
          : _previewSize,
    );
  }

  List<YOLOResult> _filterResultsForMode(List<YOLOResult> results) {
    switch (_shootingMode) {
      case ShootingMode.person:
        return results
            .where((r) => r.className.toLowerCase() == 'person')
            .toList();
      case ShootingMode.object:
        return results
            .where((r) => r.className.toLowerCase() != 'person')
            .toList();
      case ShootingMode.landscape:
        return results;
    }
  }

  void _handleDetections(List<YOLOResult> results) {
    if (!mounted) return;
    final filtered = _filterResultsForMode(results);
    final selection = _selectMainSubject(filtered);
    _TrackedSubject? currentMain;

    if (_tapNorm != null && filtered.isNotEmpty) {
      final tap = _tapNorm!;
      YOLOResult? best;
      double bestDist = double.infinity;
      for (final result in filtered) {
        final box = result.normalizedBox;
        final cx = (box.left + box.right) / 2;
        final cy = (box.top + box.bottom) / 2;
        final dist =
            ((cx - tap.dx) * (cx - tap.dx)) + ((cy - tap.dy) * (cy - tap.dy));
        if (dist < bestDist) {
          bestDist = dist;
          best = result;
        }
      }
      if (best != null && bestDist <= 0.25 * 0.25) {
        currentMain = _TrackedSubject(
          normalizedBox: Rect.fromLTRB(
            best.normalizedBox.left,
            best.normalizedBox.top,
            best.normalizedBox.right,
            best.normalizedBox.bottom,
          ),
        );
      }
    }

    if (currentMain == null) {
      final mainId = selection.best?.detection.id;
      if (mainId != null) {
        final result = filtered[mainId];
        currentMain = _TrackedSubject(
          normalizedBox: Rect.fromLTRB(
            result.normalizedBox.left,
            result.normalizedBox.top,
            result.normalizedBox.right,
            result.normalizedBox.bottom,
          ),
        );
      }
    }

    if (currentMain != null && _pendingSubject != null) {
      _currentMainSubject = currentMain;
    } else if (currentMain == null) {
      _currentMainSubject = null;
    }
    _pendingSubject = currentMain;

    final priority = _isFrontCamera
        ? _objectCoachingEngine.evaluateTiltOnly(tiltX: _tiltX)
        : _objectCoachingEngine.evaluateZoomAndTilt(
            _currentMainSubject?.normalizedBox,
            tiltX: _tiltX,
          );
    final CoachingResult coaching;
    if (priority == null) {
      coaching = _nimaResult;
    } else if (priority.level == CoachingLevel.warning) {
      coaching = priority;
    } else {
      // priority is caution — VLM warning이 있으면 VLM 우선
      coaching = _nimaResult.level == CoachingLevel.warning
          ? _nimaResult
          : priority;
    }
    if (coaching.guidance != _guidance ||
        coaching.subGuidance != _subGuidance ||
        coaching.level != _coachingLevel) {
      setState(() {
        _guidance = coaching.guidance;
        _subGuidance = coaching.subGuidance;
        _coachingLevel = coaching.level;
      });
    }
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
      _selectedZoom = 1.0;
      _guidance = '구도를 잡는 중...';
      _subGuidance = null;
      _coachingLevel = CoachingLevel.caution;
      _currentMainSubject = null;
      _pendingSubject = null;
      _tapNorm = null;
      _focusPoint = null;
      _showFocusIndicator = false;
    });
    await _cameraController.setZoomLevel(1.0);
  }

  void _onModeChanged(ShootingMode mode) {
    setState(() {
      _shootingMode = mode;
      _guidance = '구도를 잡는 중...';
      _subGuidance = null;
      _coachingLevel = CoachingLevel.caution;
      _currentMainSubject = null;
      _pendingSubject = null;
      _tapNorm = null;
    });
  }

  void _onTapFocus(Offset localPosition) {
    if (_previewSize == Size.zero) return;
    final nx = (localPosition.dx / _previewSize.width).clamp(0.0, 1.0);
    final ny = (localPosition.dy / _previewSize.height).clamp(0.0, 1.0);
    _cameraController.setFocusPoint(nx, ny);
    setState(() {
      _focusPoint = localPosition;
      _showFocusIndicator = true;
      _tapNorm = Offset(nx, ny);
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showFocusIndicator = false);
    });
  }

  void _toggleTorch() => setState(() => _torchOn = !_torchOn);
  void _cycleTimer() {
    const options = [0, 3, 10];
    final idx = options.indexOf(_timerSeconds);
    setState(() => _timerSeconds = options[(idx + 1) % options.length]);
  }

  Future<void> _captureAndSavePhoto() async {
    if (_isSaving || _countdown > 0) return;
    if (_timerSeconds > 0) {
      setState(() => _countdown = _timerSeconds);
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        setState(() => _countdown--);
        if (_countdown <= 0) {
          timer.cancel();
          _doCapture();
        }
      });
      return;
    }
    await _doCapture();
  }

  Future<void> _doCapture() async {
    if (!mounted) return;
    final hasAccess = await Gal.hasAccess();
    if (!hasAccess && !await Gal.requestAccess()) return;
    setState(() => _isSaving = true);
    try {
      if (_torchOn && !_isFrontCamera) {
        await _cameraController.setTorchMode(true);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      final bytes = await _cameraController.captureHighRes();
      if (_torchOn && !_isFrontCamera) {
        await _cameraController.setTorchMode(false);
      }
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to capture camera frame.');
      }
      if (mounted) {
        setState(() {
          _isSaving = false;
          _showFlash = true;
        });
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showFlash = false);
        });
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      Gal.putImageBytes(bytes, name: 'pozy_$timestamp').then((_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('사진을 갤러리에 저장했어요.')));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('촬영에 실패했어요: $e')));
      }
    }
  }

  @override
  void dispose() {
    _accelerometerSub?.cancel();
    _countdownTimer?.cancel();
    _nimaTimer?.cancel();
    _cameraController.stop();
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
            LayoutBuilder(
              builder: (context, constraints) {
                _previewSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
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
                  onZoomChanged: null,
                );
              },
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
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) => _onTapFocus(details.localPosition),
            ),
            if (_showFocusIndicator && _focusPoint != null)
              Positioned(
                left: _focusPoint!.dx - 30,
                top: _focusPoint!.dy - 30,
                child: IgnorePointer(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 64,
              right: 12,
              child: IgnorePointer(
                child: _CoachingSpeechBubble(
                  guidance: _guidance,
                  subGuidance: _subGuidance,
                  level: _coachingLevel,
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: _TopCameraBar(
                onBack: widget.onBack,
                torchOn: _torchOn,
                onToggleTorch: _isFrontCamera ? null : _toggleTorch,
                timerSeconds: _timerSeconds,
                onCycleTimer: _cycleTimer,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: _BottomCameraControls(
                zoomPresets: _zoomPresets,
                selectedZoom: _selectedZoom,
                isSaving: _isSaving,
                shootingMode: _shootingMode,
                coachingLevel: _coachingLevel,
                onSelectZoom: _setZoom,
                onGallery: () => widget.onMoveTab(1),
                onCapture: _captureAndSavePhoto,
                onFlipCamera: _switchCamera,
                onModeChanged: _onModeChanged,
              ),
            ),
            if (_countdown > 0)
              Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 120,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (_showFlash) Container(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _TopCameraBar extends StatelessWidget {
  final VoidCallback onBack;
  final bool torchOn;
  final VoidCallback? onToggleTorch;
  final int timerSeconds;
  final VoidCallback onCycleTimer;
  const _TopCameraBar({
    required this.onBack,
    required this.torchOn,
    required this.onToggleTorch,
    required this.timerSeconds,
    required this.onCycleTimer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
        const Spacer(),
        if (onToggleTorch != null) ...[
          _GlassIconButton(
            icon: torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            onTap: onToggleTorch!,
            tint: torchOn ? const Color(0xFFFBBF24) : null,
          ),
          const SizedBox(width: 8),
        ],
        _GlassIconButton(
          icon: Icons.timer_outlined,
          onTap: onCycleTimer,
          tint: timerSeconds > 0 ? const Color(0xFF38BDF8) : null,
          label: timerSeconds > 0 ? '${timerSeconds}s' : null,
        ),
      ],
    );
  }
}

class _BottomCameraControls extends StatelessWidget {
  final List<double> zoomPresets;
  final double selectedZoom;
  final bool isSaving;
  final ShootingMode shootingMode;
  final CoachingLevel coachingLevel;
  final ValueChanged<double> onSelectZoom;
  final VoidCallback onGallery;
  final Future<void> Function() onCapture;
  final Future<void> Function() onFlipCamera;
  final ValueChanged<ShootingMode> onModeChanged;
  const _BottomCameraControls({
    required this.zoomPresets,
    required this.selectedZoom,
    required this.isSaving,
    required this.shootingMode,
    required this.coachingLevel,
    required this.onSelectZoom,
    required this.onGallery,
    required this.onCapture,
    required this.onFlipCamera,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeSwitcher(selected: shootingMode, onChanged: onModeChanged),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: zoomPresets
              .map(
                (zoom) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _ZoomPill(
                    label:
                        '${zoom.toStringAsFixed(zoom == zoom.truncateToDouble() ? 0 : 1)}x',
                    selected: (selectedZoom - zoom).abs() < 0.05,
                    onTap: () => onSelectZoom(zoom),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GlassIconButton(
              icon: Icons.photo_library_outlined,
              onTap: onGallery,
              diameter: 48,
            ),
            const SizedBox(width: 48),
            _CaptureButton(
              isSaving: isSaving,
              isShootReady: coachingLevel == CoachingLevel.good,
              onCapture: onCapture,
            ),
            const SizedBox(width: 48),
            _GlassIconButton(
              icon: Icons.flip_camera_ios_outlined,
              onTap: onFlipCamera,
              diameter: 48,
            ),
          ],
        ),
      ],
    );
  }
}

class _CoachingSpeechBubble extends StatelessWidget {
  final String guidance;
  final String? subGuidance;
  final CoachingLevel level;
  const _CoachingSpeechBubble({
    required this.guidance,
    required this.subGuidance,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      CoachingLevel.good => const Color(0xFF4ADE80),
      CoachingLevel.warning => const Color(0xFFFBBF24),
      CoachingLevel.caution => Colors.white,
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: level == CoachingLevel.good
              ? color
              : color.withValues(alpha: 0.35),
          width: level == CoachingLevel.good ? 2.0 : 1.5,
        ),
        boxShadow: level == CoachingLevel.good
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            guidance,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (subGuidance != null) ...[
            const SizedBox(height: 4),
            Text(
              subGuidance!,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptureButton extends StatefulWidget {
  final bool isSaving;
  final bool isShootReady;
  final Future<void> Function() onCapture;
  const _CaptureButton({
    required this.isSaving,
    required this.isShootReady,
    required this.onCapture,
  });

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isSaving ? null : widget.onCapture,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          final glow = widget.isShootReady ? _pulseAnim.value : 0.0;
          return Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: widget.isShootReady
                  ? const Color(0xFF4ADE80)
                  : Colors.white,
              shape: BoxShape.circle,
              boxShadow: widget.isShootReady
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4ADE80).withValues(
                          alpha: 0.35 + glow * 0.45,
                        ),
                        blurRadius: 12 + glow * 20,
                        spreadRadius: 2 + glow * 8,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: widget.isSaving
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0x1A333333),
                          width: 2,
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  final ShootingMode selected;
  final ValueChanged<ShootingMode> onChanged;
  const _ModeSwitcher({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ShootingMode.values
            .map(
              (mode) => GestureDetector(
                onTap: () => onChanged(mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: selected == mode ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      color: selected == mode
                          ? const Color(0xFF333333)
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double diameter;
  final Color? tint;
  final String? label;
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.diameter = 40,
    this.tint,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final bg = tint ?? const Color(0x66333333);
    final iconColor = tint != null ? const Color(0xFF0F172A) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: label != null ? null : diameter,
        height: diameter,
        padding: label != null
            ? const EdgeInsets.symmetric(horizontal: 10)
            : null,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint ?? const Color(0x4DFFFFFF), width: 1),
        ),
        alignment: Alignment.center,
        child: label != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: diameter * 0.42),
                  const SizedBox(width: 4),
                  Text(
                    label!,
                    style: TextStyle(color: iconColor, fontSize: 11),
                  ),
                ],
              )
            : Icon(icon, color: iconColor, size: diameter * 0.45),
      ),
    );
  }
}

class _ZoomPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ZoomPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF333333) : Colors.white,
            fontSize: selected ? 11 : 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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

class _TrackedSubject {
  final Rect normalizedBox;
  const _TrackedSubject({required this.normalizedBox});
}
