import 'package:flutter/material.dart';

import '../../../coaching/portrait/silhouette_shapes.dart';

class SilhouetteSelector extends StatelessWidget {
  final SilhouetteType selected;
  final ValueChanged<SilhouetteType> onChanged;

  const SilhouetteSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      (SilhouetteType.none, Icons.not_interested_rounded, '없음'),
      (SilhouetteType.standing, Icons.accessibility_new_rounded, '전신'),
      (SilhouetteType.halfBody, Icons.person_rounded, '상반신'),
      (
        SilhouetteType.sitting,
        Icons.airline_seat_recline_normal_rounded,
        '앉은 자세',
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _SilhouetteChip(
              icon: items[i].$2,
              label: items[i].$3,
              selected: items[i].$1 == selected,
              onTap: () => onChanged(items[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

class _SilhouetteChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SilhouetteChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? const Color(0xFFBFDBFE).withValues(alpha: 0.78)
        : const Color(0xFFF8FBFF);
    final fg = selected ? const Color(0xFF1D4ED8) : const Color(0xFF111827);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected
                ? const Color(0xFF93C5FD)
                : const Color(0xFFE5EEF8),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
