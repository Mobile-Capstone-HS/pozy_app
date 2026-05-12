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
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isNarrow = availableWidth <= 360;
        final sideActionGap = ((availableWidth - 80 - 48 - 48) / 4)
            .clamp(isNarrow ? 14.0 : 18.0, 40.0)
            .toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shotTypeLabel != null && shotTypeLabel!.isNotEmpty) ...[
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: availableWidth * 0.44),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    shotTypeLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: 0.84,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: zoomPresets
                            .map(
                              (zoom) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
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
                    ),
                  ),
                  SizedBox(height: isNarrow ? 14 : 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GlassIconButton(
                        icon: Icons.photo_library_outlined,
                        onTap: onGallery,
                        diameter: 48,
                      ),
                      SizedBox(width: sideActionGap),
                      CaptureButton(
                        isSaving: isSaving,
                        isShootReady: isShootReady,
                        onCapture: onCapture,
                      ),
                      SizedBox(width: sideActionGap),
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
            SizedBox(height: isNarrow ? 12 : 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 20 : 30),
              child: ModeSwitcher(
                selected: shootingMode,
                onChanged: onModeChanged,
              ),
            ),
            SizedBox(height: isNarrow ? 10 : 8),
          ],
        );
      },
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
