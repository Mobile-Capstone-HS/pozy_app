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
      (PortraitIntent.single, Icons.person_outline_rounded, '사람'),
      (PortraitIntent.environmental, Icons.landscape_outlined, '환경'),
      (PortraitIntent.group, Icons.groups_outlined, '다중'),
    ];

    final entries = items
        .map(
          (item) => _IntentChip(
            icon: item.$2,
            label: item.$3,
            selected: item.$1 == selected,
            compact: compact,
            onTap: () => onChanged(item.$1),
          ),
        )
        .toList(growable: false);

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF).withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFBFDBFE).withValues(alpha: 0.34),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x160F172A),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                entries[i],
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
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => entries[index],
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
    final bg = selected ? const Color(0xFFBFDBFE) : const Color(0xFFFDFEFF);
    final fg = selected ? const Color(0xFF10367D) : const Color(0xFF1F2937);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: compact ? 34 : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 12,
          vertical: compact ? 7 : 8,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(compact ? 17 : 20),
          border: Border.all(
            color: selected
                ? const Color(0xFF93C5FD)
                : const Color(0xFFE5EEF8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 15 : 16, color: fg),
            SizedBox(width: compact ? 6 : 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: compact ? 10.5 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
