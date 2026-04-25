import 'package:flutter/material.dart';

import 'glass_icon_button.dart';

/// 카메라 화면 상단의 공용 컨트롤 바.
/// - 왼쪽: 뒤로가기 + (선택) badge 슬롯 (예: 인물 모드 배지)
/// - 오른쪽: ROI 잠금(객체 모드) / 플래시 / 타이머
///
/// 각 우측 기능은 해당 모드에서 의미가 없으면 콜백을 `null`로 두어 숨긴다.
class TopCameraBar extends StatelessWidget {
  final VoidCallback onBack;
  final bool torchOn;
  final VoidCallback? onToggleTorch;
  final int timerSeconds;
  final VoidCallback onCycleTimer;
  final bool isDrawingRoi;
  final bool isRoiLocked;
  final VoidCallback? onToggleRoiLock;
  final bool portraitDebugOverlayOn;
  final VoidCallback? onTogglePortraitDebugOverlay;

  /// 뒤로가기 오른쪽에 표시할 배지(예: `PortraitBadge`). 없으면 Spacer만 들어간다.
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
    this.portraitDebugOverlayOn = false,
    this.onTogglePortraitDebugOverlay,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
        if (badge != null) ...[
          const SizedBox(width: 10),
          badge!,
        ],
        const Spacer(),
        if (onToggleRoiLock != null) ...[
          GlassIconButton(
            icon: lockIcon,
            onTap: onToggleRoiLock!,
            tint: lockTint,
          ),
          const SizedBox(width: 8),
        ],
        if (onToggleTorch != null) ...[
          GlassIconButton(
            icon: torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            onTap: onToggleTorch!,
            tint: torchOn ? const Color(0xFFFBBF24) : null,
          ),
          const SizedBox(width: 8),
        ],
        if (onTogglePortraitDebugOverlay != null) ...[
          GlassIconButton(
            icon: portraitDebugOverlayOn
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            onTap: onTogglePortraitDebugOverlay!,
            tint: portraitDebugOverlayOn ? const Color(0xFF38BDF8) : null,
          ),
          const SizedBox(width: 8),
        ],
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
