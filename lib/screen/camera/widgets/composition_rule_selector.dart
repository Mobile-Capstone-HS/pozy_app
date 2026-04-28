import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../composition/composition_rule.dart';
import '../../../composition/composition_rule_registry.dart';

/// 카메라 상단에 표시되는 구도 규칙 선택 칩 리스트.
///
/// 인물/객체 모드에서만 노출. 풍경 모드는 자동 감지 사용.
class CompositionRuleSelector extends StatefulWidget {
  final CompositionRuleType selected;
  final ValueChanged<CompositionRuleType> onChanged;
  final ValueChanged<bool>? onExpandedChanged;

  const CompositionRuleSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.onExpandedChanged,
  });

  @override
  State<CompositionRuleSelector> createState() =>
      _CompositionRuleSelectorState();
}

class _CompositionRuleSelectorState extends State<CompositionRuleSelector> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final glassDecoration = BoxDecoration(
      color: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.25),
        width: 1.0,
      ),
    );

    if (!_isExpanded) {
      return Align(
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: () {
              setState(() => _isExpanded = true);
              widget.onExpandedChanged?.call(true);
            },
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 32,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              decoration: glassDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() => _isExpanded = false);
                      widget.onExpandedChanged?.call(false);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
                      child: const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: CompositionRuleRegistry.ordered.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final type = CompositionRuleRegistry.ordered[index];
                        final rule = CompositionRuleRegistry.of(type);
                        final isSelected = type == widget.selected;
                        return _RuleChip(
                          label: rule.label,
                          icon: rule.icon,
                          selected: isSelected,
                          onTap: () {
                            widget.onChanged(type);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
