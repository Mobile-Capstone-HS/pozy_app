import 'package:flutter/material.dart';

import 'glass_icon_button.dart';

/// 인물 모드 전용 상단 바. 뒤로가기 + 인물 뱃지(카메라 방향/줌 표시).
class PortraitTopBar extends StatelessWidget {
  final VoidCallback onBack;
  final bool isFrontCamera;
  final double currentZoom;

  const PortraitTopBar({
    super.key,
    required this.onBack,
    required this.isFrontCamera,
    required this.currentZoom,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: onBack,
        ),
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
              const Text(
                '인물',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${isFrontCamera ? 'Front' : 'Back'} | ${currentZoom.toStringAsFixed(1)}x',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
