import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../composition/composition_rule.dart';
import '../../../composition/composition_rule_registry.dart';
import '../../../coaching/portrait/silhouette_shapes.dart';
import 'silhouette_selector.dart';

enum _Tab { rule, silhouette }

/// 카메라 상단에 표시되는 구도 규칙 선택 칩 리스트.
///
/// 인물/객체 모드에서만 노출. 풍경 모드는 자동 감지 사용.
class CompositionRuleSelector extends StatefulWidget {
  final CompositionRuleType selected;
  final ValueChanged<CompositionRuleType> onChanged;
  final ValueChanged<bool>? onExpandedChanged;

  final bool showSilhouetteTab;
  final SilhouetteType? selectedSilhouette;
  final ValueChanged<SilhouetteType>? onSilhouetteChanged;

  const CompositionRuleSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.onExpandedChanged,
    this.showSilhouetteTab = false,
    this.selectedSilhouette,
    this.onSilhouetteChanged,
  });

  @override
  State<CompositionRuleSelector> createState() =>
      _CompositionRuleSelectorState();
}

class _CompositionRuleSelectorState extends State<CompositionRuleSelector> {
  bool _isExpanded = false;
  _Tab _currentTab = _Tab.rule;

  Widget _buildTabButton(String title, _Tab tab) {
    final isSelected = _currentTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = tab),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 2.0,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildRuleList() {
    return ListView.separated(
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
    );
  }

  Widget _buildSilhouetteList() {
    return SilhouetteSelector(
      selected: widget.selectedSilhouette ?? SilhouetteType.none,
      onChanged: widget.onSilhouetteChanged ?? (_) {},
    );
  }

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
              setState(() {
                _isExpanded = true;
                if (!widget.showSilhouetteTab && _currentTab == _Tab.silhouette) {
                  _currentTab = _Tab.rule;
                }
              });
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
                  if (widget.showSilhouetteTab) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTabButton('구도', _Tab.rule),
                        const SizedBox(width: 16),
                        _buildTabButton('실루엣', _Tab.silhouette),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    height: 40,
                    child: _currentTab == _Tab.rule || !widget.showSilhouetteTab
                        ? _buildRuleList()
                        : _buildSilhouetteList(),
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

