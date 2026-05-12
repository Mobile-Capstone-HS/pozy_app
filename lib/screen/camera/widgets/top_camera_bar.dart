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
  final Widget? trailing;

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
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth <= 360;
        final badgeMaxWidth = constraints.maxWidth * (isNarrow ? 0.48 : 0.56);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GlassIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: onBack,
              diameter: 36,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: badge == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: badgeMaxWidth),
                        child: badge!,
                      ),
                    ),
            ),
            if (timerSeconds > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Text(
                  '${timerSeconds}s',
                  style: const TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (trailing != null) ...[
              if (timerSeconds > 0) const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: trailing!,
              ),
            ],
          ],
        );
      },
    );
  }
}
