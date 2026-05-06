import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:pose_camera_app/coaching/coaching_result.dart';
import 'package:pose_camera_app/feature/landscape/landscape_mode_controller.dart';
import 'package:pose_camera_app/feature/landscape/landscape_overlay_painter.dart';
import 'package:pose_camera_app/feature/landscape/landscape_ui_state.dart';
import 'package:pose_camera_app/segmentation/fastscnn_view.dart';
import 'package:pose_camera_app/widget/coaching_interface.dart';

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
  final LandscapeModeController _modeController = LandscapeModeController();

  LandscapeUiState _uiState = const LandscapeUiState.initial();
  bool _isSaving = false;
  bool _showFlash = false;

  @override
  void dispose() {
    _modeController.reset();
    _controller.stop();
    super.dispose();
  }

  Future<void> _setZoom(double zoom) async {
    setState(() {
      _uiState = _uiState.copyWith(selectedZoom: zoom);
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
      if (!hasAccess && !await Gal.requestAccess()) {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
        return;
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
      ).showSnackBar(const SnackBar(content: Text('사진을 갤러리에 저장했어요.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('촬영에 실패했어요: $e')));
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

  void _handleFrame(FastScnnFrame frame) {
    if (!mounted) return;
    setState(() {
      _uiState = _modeController.processFrame(frame, currentState: _uiState);
    });
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
              onResult: _handleFrame,
              onZoomChanged: (zoom) {
                if (!mounted) return;
                setState(() {
                  _uiState = _uiState.copyWith(currentZoom: zoom);
                });
              },
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: LandscapeCompositionOverlayPainter(
                  decision: _uiState.decision,
                  advice: _uiState.overlayAdvice,
                ),
                size: Size.infinite,
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
            Positioned(
              top: 64,
              right: 12,
              child: IgnorePointer(
                child: CoachingSpeechBubble(
                  guidance: _uiState.guidance,
                  subGuidance: _uiState.subGuidance,
                  level: _uiState.coachingLevel,
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: widget.onBack,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      '${_uiState.isFrontCamera ? 'Front' : 'Back'} | ${_uiState.currentZoom.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _zoomPresets
                              .map(
                                (zoom) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: _ZoomPill(
                                    label:
                                        '${zoom.toStringAsFixed(zoom == zoom.truncateToDouble() ? 0 : 1)}x',
                                    selected:
                                        (_uiState.selectedZoom - zoom).abs() <
                                        0.05,
                                    onTap: () => _setZoom(zoom),
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
                              onTap: () => widget.onMoveTab(1),
                              diameter: 48,
                            ),
                            const SizedBox(width: 48),
                            _CaptureButton(
                              isSaving: _isSaving,
                              isShootReady:
                                  _uiState.coachingLevel == CoachingLevel.good,
                              onCapture: _captureAndSavePhoto,
                            ),
                            const SizedBox(width: 48),
                            _GlassIconButton(
                              icon: Icons.flip_camera_ios_outlined,
                              onTap: _controller.switchCamera,
                              diameter: 48,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            if (_showFlash) Container(color: Colors.white),
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
                        color: const Color(
                          0xFF4ADE80,
                        ).withValues(alpha: 0.35 + glow * 0.45),
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
