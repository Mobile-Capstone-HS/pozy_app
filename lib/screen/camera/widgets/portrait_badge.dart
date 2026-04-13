import 'package:flutter/material.dart';

/// 인물 모드임을 나타내는 상단 배지. "인물 | Front/Back | 1.0x" 형태.
/// `TopCameraBar.badge` 슬롯에 주입해 사용.
class PortraitBadge extends StatelessWidget {
  final bool isFrontCamera;
  final double currentZoom;

  const PortraitBadge({
    super.key,
    required this.isFrontCamera,
    required this.currentZoom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}
