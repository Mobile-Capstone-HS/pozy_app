import 'package:flutter/material.dart';

import 'glass_icon_button.dart';

class TopCameraBar extends StatelessWidget {
  final VoidCallback onBack;
  final bool torchOn;
  final VoidCallback? onToggleTorch;
  final int timerSeconds;
  final VoidCallback onCycleTimer;
  final bool isDrawingRoi;
  final bool isRoiLocked;
  final VoidCallback? onToggleRoiLock;
  final Widget? badge;

  const TopCameraBar({
    super.key,
    required this.onBack,
    required this.torchOn,
    required this.onToggleTorch,
    required this.timerSeconds,
    required this.onCycleTimer,
    required this.isDrawingRoi,
    required this.isRoiLocked,
    required this.onToggleRoiLock,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final lockIcon = isRoiLocked
        ? Icons.lock_rounded
        : isDrawingRoi
        ? Icons.close_rounded
        : Icons.center_focus_weak_rounded;
    final lockTint = isRoiLocked
        ? const Color(0xFF38BDF8)
        : isDrawingRoi
        ? const Color(0xFFFBBF24)
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
        if (badge != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.58),
                child: badge!,
              ),
            ),
          ),
        ] else
          const Spacer(),
        if (onToggleRoiLock != null) ...[
          const SizedBox(width: 10),
          GlassIconButton(
            icon: lockIcon,
            onTap: onToggleRoiLock!,
            tint: lockTint,
          ),
        ],
        if (onToggleTorch != null) ...[
          const SizedBox(width: 8),
          GlassIconButton(
            icon: torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            onTap: onToggleTorch!,
            tint: torchOn ? const Color(0xFFFBBF24) : null,
          ),
        ],
        const SizedBox(width: 8),
        GlassIconButton(
          icon: Icons.timer_outlined,
          onTap: onCycleTimer,
          tint: timerSeconds > 0 ? const Color(0xFF38BDF8) : null,
          label: timerSeconds > 0 ? '${timerSeconds}s' : null,
        ),
      ],
    );
  }
}
