import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/enums/composition_mode.dart';
import 'package:pose_camera_app/core/enums/scene_type.dart';

class CameraTopBar extends StatelessWidget {
  const CameraTopBar({
    super.key,
    required this.compositionMode,
    required this.resolvedScene,
    required this.onClose,
  });

  final CompositionMode compositionMode;
  final SceneType resolvedScene;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.flash_off_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          const Icon(Icons.hdr_auto_rounded, color: Colors.white54, size: 24),
          const Spacer(),
          _InfoPill(
            text: compositionMode.shortLabel,
            color: compositionMode.accentColor,
          ),
          const SizedBox(width: 8),
          _InfoPill(
            text: resolvedScene.debugLabel,
            color: resolvedScene.accentColor,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}
