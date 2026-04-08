import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:pose_camera_app/segmentation/composition_engine.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/composition_temporal_filter.dart';
import 'package:pose_camera_app/segmentation/fastscnn_segmentor.dart';
import 'package:pose_camera_app/segmentation/fastscnn_view.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';
import 'package:sensors_plus/sensors_plus.dart';

class LandscapeCameraScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;

  const LandscapeCameraScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
  });

  @override
  State<LandscapeCameraScreen> createState() => _LandscapeCameraScreenState();
}

class _LandscapeCameraScreenState extends State<LandscapeCameraScreen> {
  static const List<double> _zoomPresets = [0.5, 1.0, 2.0];

  final FastScnnViewController _controller = FastScnnViewController();
  final CompositionResolver _resolver = const CompositionResolver();
  final CompositionTemporalFilter _temporalFilter = CompositionTemporalFilter();
  final CompositionEngine _compositionEngine = CompositionEngine();

  LandscapeFeatures? _latestFeatures;
  CompositionDecision? _decision;
  double _currentZoom = 1.0;
  double _selectedZoom = 1.0;
  bool _isFrontCamera = false;
  bool _isSaving = false;
  bool _showFlash = false;
  String _guidance = '구도를 분석 중입니다.';
  String _nativeStatus = 'native: waiting';
  double? _preMs;
  double? _infMs;
  double? _postMs;
  double? _totMs;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  double _rollDeg = 0.0;
  DateTime _lastLevelUiAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _startLevelMeter();
  }

  void _startLevelMeter() {
    _accelerometerSub = accelerometerEventStream().listen((event) {
      var rawRoll = math.atan2(event.x, event.y) * 180.0 / math.pi;
      if (rawRoll > 90.0) rawRoll -= 180.0;
      if (rawRoll < -90.0) rawRoll += 180.0;
      final boundedRoll = rawRoll.clamp(-89.0, 89.0);
      final smoothedRoll = _rollDeg * 0.85 + boundedRoll * 0.15;
      final now = DateTime.now();
      final changedEnough = (smoothedRoll - _rollDeg).abs() > 0.15;
      final elapsedEnough = now.difference(_lastLevelUiAt).inMilliseconds > 33;
      if (!mounted || !changedEnough || !elapsedEnough) {
        _rollDeg = smoothedRoll;
        return;
      }
      _lastLevelUiAt = now;
      setState(() {
        _rollDeg = smoothedRoll;
      });
    });
  }

  Future<void> _setZoom(double zoom) async {
    setState(() {
      _selectedZoom = zoom;
    });
    await _controller.setZoomLevel(zoom);
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
        if (!granted) {
          if (mounted) {
            setState(() {
              _isSaving = false;
            });
          }
          return;
        }
      }
      final bytes = await _controller.captureFrame();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to capture frame');
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await Gal.putImageBytes(bytes, name: 'pozy_landscape_$timestamp');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo saved to gallery.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save photo: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _showFlash = true;
        });
        Future<void>.delayed(const Duration(milliseconds: 140), () {
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
    _accelerometerSub?.cancel();
    _controller.stop();
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
            FastScnnView(
              controller: _controller,
              frameSkipLevel: 2,
              inferenceIntervalMs: 220,
              onZoomChanged: (zoom) {
                if (!mounted) return;
                setState(() {
                  _currentZoom = zoom;
                });
              },
              onEvent: (event) {
                if (!mounted) return;
                if (event['type'] == 'perf') {
                  setState(() {
                    _preMs = (event['preprocessMs'] as num?)?.toDouble();
                    _infMs = (event['inferenceMs'] as num?)?.toDouble();
                    _postMs = (event['postprocessMs'] as num?)?.toDouble();
                    _totMs = (event['totalMs'] as num?)?.toDouble();
                    _nativeStatus = 'native: running';
                  });
                } else if (event['type'] == 'status') {
                  setState(() {
                    _nativeStatus = 'native: ${event['state'] ?? 'unknown'}';
                  });
                } else if (event['type'] == 'error') {
                  setState(() {
                    _nativeStatus =
                        'native error: ${event['message'] ?? 'unknown'}';
                  });
                }
              },
              onResult: (frame) {
                final raw = LandscapeAnalyzer.analyzeFeatures(frame.result);
                final smoothed = _temporalFilter.smooth(raw);
                final decision = _temporalFilter.stabilize(
                  _resolver.resolve(smoothed),
                );
                final summary = _compositionEngine.evaluate(
                  features: smoothed,
                  decision: decision,
                );
                if (!mounted) return;
                setState(() {
                  _latestFeatures = smoothed;
                  _decision = decision;
                  _guidance = summary.guideMessage;
                  _isFrontCamera = frame.isFrontCamera;
                  _currentZoom = frame.zoomLevel;
                });
              },
              overlayBuilder: (context, frame) {
                return CustomPaint(
                  painter: _SegmentationDotPainter(result: frame?.result),
                  size: Size.infinite,
                );
              },
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _CompositionOverlayPainter(
                  decision: _decision,
                ),
                size: Size.infinite,
              ),
            ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: widget.onBack,
                  ),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 290),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${_isFrontCamera ? 'Front' : 'Back'} | ${_currentZoom.toStringAsFixed(1)}x',
                            ),
                            if (_totMs != null)
                              Text(
                                'ms | pre:${_preMs?.toStringAsFixed(1) ?? '-'} '
                                'inf:${_infMs?.toStringAsFixed(1) ?? '-'} '
                                'post:${_postMs?.toStringAsFixed(1) ?? '-'} '
                                'tot:${_totMs?.toStringAsFixed(1) ?? '-'}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white70,
                                ),
                              ),
                            Text(
                              _nativeStatus,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Colors.white70,
                              ),
                            ),
                            if (_latestFeatures != null)
                              Text(
                                'sky=${_latestFeatures!.skyRatio.toStringAsFixed(2)} '
                                'horizon=${_latestFeatures!.horizonPosition?.toStringAsFixed(2) ?? '-'} '
                                'hConf=${_latestFeatures!.horizonConfidence.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white70,
                                ),
                              ),
                            Text(_guidance),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 56,
              left: 16,
              right: 16,
              child: Center(
                child: Container(
                  width: 246,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 208,
                        height: 66,
                        child: CustomPaint(
                          painter: _LevelGaugePainter(rollDeg: _rollDeg),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _rollDeg.abs() <= 2.0
                            ? '수평'
                            : '${_rollDeg > 0 ? '+' : ''}${_rollDeg.toStringAsFixed(1)}°',
                        style: TextStyle(
                          color: _rollDeg.abs() <= 2.0
                              ? const Color(0xFF86EFAC)
                              : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 40,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _zoomPresets
                          .map(
                            (zoom) => _ZoomPill(
                              label:
                                  '${zoom.toStringAsFixed(zoom == zoom.truncateToDouble() ? 0 : 1)}x',
                              selected: (_selectedZoom - zoom).abs() < 0.05,
                              onTap: () => _setZoom(zoom),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _GlassIconButton(
                        icon: Icons.photo_library_outlined,
                        onTap: () => widget.onMoveTab(1),
                        diameter: 48,
                      ),
                      const SizedBox(width: 48),
                      GestureDetector(
                        onTap: _captureAndSavePhoto,
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white70, width: 3),
                            color: Colors.white12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                      _GlassIconButton(
                        icon: Icons.cameraswitch_rounded,
                        onTap: _controller.switchCamera,
                        diameter: 48,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_showFlash)
              Positioned.fill(
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.55)),
              ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double diameter;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.diameter = 40,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: diameter,
        height: diameter,
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

class _LevelGaugePainter extends CustomPainter {
  final double rollDeg;

  const _LevelGaugePainter({required this.rollDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final levelOk = rollDeg.abs() <= 2.0;
    final accentColor = levelOk
        ? const Color(0xFF86EFAC)
        : const Color(0xFFFBBF24);

    final baselinePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(14, center.dy),
      Offset(size.width - 14, center.dy),
      baselinePaint,
    );

    final outerRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white54;
    canvas.drawCircle(center, 13, outerRingPaint);

    final dynamicBarPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final angle = -rollDeg * math.pi / 180.0;
    final barHalfLen = (size.width - 54) / 2;
    final dx = math.cos(angle) * barHalfLen;
    final dy = math.sin(angle) * barHalfLen;
    canvas.drawLine(
      Offset(center.dx - dx, center.dy - dy),
      Offset(center.dx + dx, center.dy + dy),
      dynamicBarPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LevelGaugePainter oldDelegate) {
    return (oldDelegate.rollDeg - rollDeg).abs() > 0.05;
  }
}

class _CompositionOverlayPainter extends CustomPainter {
  final CompositionDecision? decision;

  const _CompositionOverlayPainter({
    required this.decision,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final d = decision;
    if (d == null || d.compositionMode == CompositionMode.none) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final dx1 = size.width / 3;
    final dx2 = size.width * 2 / 3;
    final dy1 = size.height / 3;
    final dy2 = size.height * 2 / 3;
    canvas.drawLine(Offset(dx1, 0), Offset(dx1, size.height), gridPaint);
    canvas.drawLine(Offset(dx2, 0), Offset(dx2, size.height), gridPaint);
    canvas.drawLine(Offset(0, dy1), Offset(size.width, dy1), gridPaint);
    canvas.drawLine(Offset(0, dy2), Offset(size.width, dy2), gridPaint);
  }

  @override
  bool shouldRepaint(covariant _CompositionOverlayPainter oldDelegate) {
    return oldDelegate.decision != decision;
  }
}

class _SegmentationDotPainter extends CustomPainter {
  final SegmentationResult? result;

  const _SegmentationDotPainter({required this.result});

  @override
  void paint(Canvas canvas, Size size) {
    final seg = result;
    if (seg == null || seg.height == 0 || seg.width == 0) return;

    final strideX = math.max(1, (seg.width / 24).round());
    final strideY = math.max(1, (seg.height / 14).round());
    final baseRadius = math.max(
      1.9,
      math.min(size.width, size.height) * 0.0052,
    );
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int y = 0; y < seg.height; y += strideY) {
      final row = seg.classMap[y];
      for (int x = 0; x < seg.width; x += strideX) {
        final color = _classColor(row[x]);
        if (color == null) continue;
        fillPaint.color = color;
        final center = Offset(
          ((x + 0.5) / seg.width) * size.width,
          ((y + 0.5) / seg.height) * size.height,
        );
        canvas.drawCircle(center, baseRadius, fillPaint);
      }
    }
  }

  Color? _classColor(int classId) {
    if (classId == CityscapesClass.sky) return const Color(0x884DB8FF);
    if (classId == CityscapesClass.vegetation) return const Color(0x8862D26F);
    if (classId == CityscapesClass.terrain) return const Color(0x88E2A15D);
    if (classId == CityscapesClass.road) return const Color(0x887A7A7A);
    if (classId == CityscapesClass.building) return const Color(0x889C7B6A);
    return null;
  }

  @override
  bool shouldRepaint(covariant _SegmentationDotPainter oldDelegate) {
    return oldDelegate.result != result;
  }
}
