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
      (SilhouetteType.none, Icons.not_interested, '없음'),
      (SilhouetteType.standing, Icons.accessibility_new_rounded, '전신'),
      (SilhouetteType.halfBody, Icons.person_rounded, '상반신'),
      (SilhouetteType.sitting, Icons.airline_seat_recline_normal_rounded, '앉은 자세'),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = item.$1 == selected;
          return _SilhouetteChip(
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
        ? const Color(0xFF38BDF8) // 활성화 시 Cyan 색상
        : Colors.black.withValues(alpha: 0.35);
    final fg = selected ? Colors.black : Colors.white;

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
                ? const Color(0xFF38BDF8)
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
