import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'editor_types.dart';

class FilterPreset {
  final String name;
  final IconData icon;
  final Map<EditorAdjustment, double> values;

  const FilterPreset({
    required this.name,
    required this.icon,
    required this.values,
  });
}

const List<FilterPreset> editorPresets = [
  FilterPreset(
    name: '원본',
    icon: Icons.tune,
    values: {
      EditorAdjustment.brightness: 0,
      EditorAdjustment.contrast: 0,
      EditorAdjustment.saturation: 0,
      EditorAdjustment.warmth: 0,
      EditorAdjustment.fade: 0,
      EditorAdjustment.sharpness: 0,
    },
  ),
  FilterPreset(
    name: '차분한',
    icon: Icons.spa_outlined,
    values: {
      EditorAdjustment.brightness: -5,
      EditorAdjustment.contrast: -10,
      EditorAdjustment.saturation: -20,
      EditorAdjustment.warmth: 5,
      EditorAdjustment.fade: 30,
      EditorAdjustment.sharpness: -10,
    },
  ),
  FilterPreset(
    name: '필름',
    icon: Icons.camera_roll_outlined,
    values: {
      EditorAdjustment.brightness: -8,
      EditorAdjustment.contrast: 15,
      EditorAdjustment.saturation: -15,
      EditorAdjustment.warmth: 10,
      EditorAdjustment.fade: 40,
      EditorAdjustment.sharpness: -5,
    },
  ),
  FilterPreset(
    name: '선명',
    icon: Icons.hdr_strong_outlined,
    values: {
      EditorAdjustment.brightness: 5,
      EditorAdjustment.contrast: 20,
      EditorAdjustment.saturation: 35,
      EditorAdjustment.warmth: 0,
      EditorAdjustment.fade: -10,
      EditorAdjustment.sharpness: 25,
    },
  ),
  FilterPreset(
    name: '따뜻한',
    icon: Icons.wb_sunny_outlined,
    values: {
      EditorAdjustment.brightness: 8,
      EditorAdjustment.contrast: 5,
      EditorAdjustment.saturation: 10,
      EditorAdjustment.warmth: 40,
      EditorAdjustment.fade: 10,
      EditorAdjustment.sharpness: 0,
    },
  ),
  FilterPreset(
    name: '시원한',
    icon: Icons.ac_unit_outlined,
    values: {
      EditorAdjustment.brightness: 0,
      EditorAdjustment.contrast: 10,
      EditorAdjustment.saturation: 5,
      EditorAdjustment.warmth: -35,
      EditorAdjustment.fade: 5,
      EditorAdjustment.sharpness: 10,
    },
  ),
  FilterPreset(
    name: '모노',
    icon: Icons.filter_b_and_w_outlined,
    values: {
      EditorAdjustment.brightness: 5,
      EditorAdjustment.contrast: 15,
      EditorAdjustment.saturation: -100,
      EditorAdjustment.warmth: 0,
      EditorAdjustment.fade: 15,
      EditorAdjustment.sharpness: 10,
    },
  ),
];

class PresetStrip extends StatelessWidget {
  final FilterPreset? activePreset;
  final ValueChanged<FilterPreset> onSelect;

  const PresetStrip({
    super.key,
    required this.activePreset,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: editorPresets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final preset = editorPresets[index];
          final selected = activePreset == preset;

          return GestureDetector(
            onTap: () => onSelect(preset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF191F28) : const Color(0xFFF2F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    preset.icon,
                    size: 14,
                    color: selected ? Colors.white : const Color(0xFF191F28),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF191F28),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
