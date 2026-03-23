import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/enums/scene_type.dart';
import 'package:pose_camera_app/widgets/scene_selector.dart';

class CameraBottomBar extends StatelessWidget {
  const CameraBottomBar({
    super.key,
    required this.selectedMode,
    required this.modes,
    required this.onModeSelected,
    required this.onCapture,
    required this.manualScene,
    required this.resolvedScene,
    required this.onSceneChanged,
  });

  final String selectedMode;
  final List<String> modes;
  final ValueChanged<String> onModeSelected;
  final VoidCallback onCapture;
  final SceneType manualScene;
  final SceneType resolvedScene;
  final ValueChanged<SceneType> onSceneChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.42),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SceneSelector(
            manualScene: manualScene,
            resolvedScene: resolvedScene,
            onChanged: onSceneChanged,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: modes.map((mode) {
                final isSelected = mode == selectedMode;
                return GestureDetector(
                  onTap: () => onModeSelected(mode),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      child: Text(
                        mode,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFFFFD54F)
                              : Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.image_outlined, color: Colors.white70),
                ),
                GestureDetector(
                  onTap: onCapture,
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3.5),
                    ),
                    child: Center(
                      child: Container(
                        width: 63,
                        height: 63,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
