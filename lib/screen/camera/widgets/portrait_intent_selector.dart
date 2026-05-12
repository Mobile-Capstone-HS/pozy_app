import 'package:flutter/material.dart';

import '../../../coaching/portrait/portrait_scene_state.dart';

class PortraitIntentSelector extends StatelessWidget {
  final PortraitIntent selected;
  final ValueChanged<PortraitIntent> onChanged;
  final bool compact;

  const PortraitIntentSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      (PortraitIntent.single, Icons.person_outline, '\uC0AC\uB78C'),
      (
        PortraitIntent.environmental,
        Icons.landscape_outlined,
        '\uD658\uACBD',
      ),
      (PortraitIntent.group, Icons.groups_outlined, '\uB2E4\uC911'),
    ];

    final chips = items.map((item) {
      final isSelected = item.$1 == selected;
      return _IntentChip(
        icon: item.$2,
        label: item.$3,
        selected: isSelected,
        compact: compact,
        onTap: () => onChanged(item.$1),
      );
    }).toList(growable: false);

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.26),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                chips[i],
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => chips[index],
      ),
    );
  }
}

class _IntentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _IntentChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
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
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 11 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(compact ? 14 : 20),
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 14 : 16, color: fg),
            SizedBox(width: compact ? 4 : 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
