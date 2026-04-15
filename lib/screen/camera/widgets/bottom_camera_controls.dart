import 'package:flutter/material.dart';

import '../shooting_mode.dart';
import 'glass_icon_button.dart';
import 'mode_switcher.dart';
import 'zoom_pill.dart';

/// 카메라 화면 하단 전체 (줌 프리셋 + 갤러리/촬영/전환 + 모드 스위처).
class BottomCameraControls extends StatelessWidget {
  final List<double> zoomPresets;
  final double selectedZoom;
  final bool isSaving;
  final ShootingMode shootingMode;
  final bool isShootReady;
  final String? shotTypeLabel;
  final ValueChanged<double> onSelectZoom;
  final VoidCallback onGallery;
  final Future<void> Function() onCapture;
  final Future<void> Function() onFlipCamera;
  final ValueChanged<ShootingMode> onModeChanged;

  const BottomCameraControls({
    super.key,
    required this.zoomPresets,
    required this.selectedZoom,
    required this.isSaving,
    required this.shootingMode,
    required this.isShootReady,
    required this.shotTypeLabel,
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
        if (shotTypeLabel != null && shotTypeLabel!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              shotTypeLabel!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: zoomPresets
                    .map(
                      (zoom) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ZoomPill(
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
                  GlassIconButton(
                    icon: Icons.photo_library_outlined,
                    onTap: onGallery,
                    diameter: 48,
                  ),
                  const SizedBox(width: 48),
                  CaptureButton(
                    isSaving: isSaving,
                    isShootReady: isShootReady,
                    onCapture: onCapture,
                  ),
                  const SizedBox(width: 48),
                  GlassIconButton(
                    icon: Icons.flip_camera_ios_outlined,
                    onTap: onFlipCamera,
                    diameter: 48,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ModeSwitcher(selected: shootingMode, onChanged: onModeChanged),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// 가운데의 촬영 버튼. `isShootReady`일 때 녹색 펄스 애니메이션.
class CaptureButton extends StatefulWidget {
  final bool isSaving;
  final bool isShootReady;
  final Future<void> Function() onCapture;

  const CaptureButton({
    super.key,
    required this.isSaving,
    required this.isShootReady,
    required this.onCapture,
  });

  @override
  State<CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<CaptureButton>
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
