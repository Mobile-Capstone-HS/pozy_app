import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/enums/scene_type.dart';

class SceneSelector extends StatelessWidget {
  const SceneSelector({
    super.key,
    required this.manualScene,
    required this.resolvedScene,
    required this.onChanged,
  });

  final SceneType manualScene;
  final SceneType resolvedScene;
  final ValueChanged<SceneType> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [SceneType.person, SceneType.food, SceneType.object];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: items.map((scene) {
          final isSelected = manualScene == scene;
          final isAutoActive = resolvedScene == SceneType.person && scene == SceneType.person;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => onChanged(scene),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scene.accentColor.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? scene.accentColor.withValues(alpha: 0.7)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(scene.icon, size: 18, color: isSelected ? scene.accentColor : Colors.white70),
                      const SizedBox(height: 6),
                      Text(
                        scene.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAutoActive ? 'AUTO' : (isSelected ? 'MANUAL' : ''),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isAutoActive ? Colors.greenAccent : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
