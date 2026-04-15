import 'package:flutter/material.dart';

import '../../../composition/composition_rule.dart';
import '../../../composition/composition_rule_registry.dart';

/// 카메라 상단에 표시되는 구도 규칙 선택 칩 리스트.
///
/// 인물/객체 모드에서만 노출. 풍경 모드는 자동 감지 사용.
class CompositionRuleSelector extends StatelessWidget {
  final CompositionRuleType selected;
  final ValueChanged<CompositionRuleType> onChanged;

  const CompositionRuleSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: CompositionRuleRegistry.ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = CompositionRuleRegistry.ordered[index];
          final rule = CompositionRuleRegistry.of(type);
          final isSelected = type == selected;
          return _RuleChip(
            label: rule.label,
            icon: rule.icon,
            selected: isSelected,
            onTap: () => onChanged(type),
          );
        },
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RuleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? Colors.white.withValues(alpha: 0.85)
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
                ? Colors.white
                : Colors.white.withValues(alpha: 0.25),
            width: 1.0,
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
