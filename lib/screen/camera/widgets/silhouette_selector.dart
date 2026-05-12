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

    return LayoutBuilder(
      builder: (context, constraints) {
        final chipWidth = (constraints.maxWidth - 6) / 2;

        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items.map((item) {
            return SizedBox(
              width: chipWidth,
              child: _SilhouetteChip(
                icon: item.$2,
                label: item.$3,
                selected: item.$1 == selected,
                onTap: () => onChanged(item.$1),
              ),
            );
          }).toList(),
        );
      },
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF93C5FD)
                : const Color(0xFFE5EEF8),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
