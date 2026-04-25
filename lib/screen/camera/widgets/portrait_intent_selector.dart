import 'package:flutter/material.dart';

import '../../../coaching/portrait/portrait_scene_state.dart';

class PortraitIntentSelector extends StatelessWidget {
  final PortraitIntent selected;
  final ValueChanged<PortraitIntent> onChanged;

  const PortraitIntentSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      (PortraitIntent.single, Icons.person_outline, '1인'),
      (PortraitIntent.environmental, Icons.landscape_outlined, '환경'),
      (PortraitIntent.group, Icons.groups_outlined, '다중'),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = item.$1 == selected;
          return _IntentChip(
            icon: item.$2,
            label: item.$3,
            selected: isSelected,
            onTap: () => onChanged(item.$1),
          );
        },
      ),
    );
  }
}

class _IntentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _IntentChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? const Color(0xFFEAF2FF)
        : Colors.black.withValues(alpha: 0.35);
    final fg = selected ? const Color(0xFF111827) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
