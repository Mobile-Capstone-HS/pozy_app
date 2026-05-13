import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../coaching/portrait/silhouette_shapes.dart';
import '../../../composition/composition_rule.dart';
import '../../../composition/composition_rule_registry.dart';
import 'silhouette_selector.dart';

enum _Tab { rule, silhouette }

class CompositionRuleSelector extends StatefulWidget {
  final CompositionRuleType selected;
  final ValueChanged<CompositionRuleType> onChanged;
  final ValueChanged<bool>? onExpandedChanged;
  final bool showSilhouetteTab;
  final SilhouetteType? selectedSilhouette;
  final ValueChanged<SilhouetteType>? onSilhouetteChanged;
  final bool initiallyExpanded;

  const CompositionRuleSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.onExpandedChanged,
    this.showSilhouetteTab = false,
    this.selectedSilhouette,
    this.onSilhouetteChanged,
    this.initiallyExpanded = false,
  });

  @override
  State<CompositionRuleSelector> createState() =>
      _CompositionRuleSelectorState();
}

class _CompositionRuleSelectorState extends State<CompositionRuleSelector> {
  bool _isExpanded = false;
  _Tab _currentTab = _Tab.rule;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  String _tabTitle(_Tab tab) {
    switch (tab) {
      case _Tab.rule:
        return '구도';
      case _Tab.silhouette:
        return '포즈';
    }
  }

  String _silhouetteLabel(SilhouetteType type) {
    switch (type) {
      case SilhouetteType.none:
        return '없음';
      case SilhouetteType.standing:
        return '전신';
      case SilhouetteType.halfBody:
        return '상반신';
      case SilhouetteType.sitting:
        return '앉은 자세';
    }
  }

  void _expand() {
    setState(() {
      _isExpanded = true;
      if (!widget.showSilhouetteTab && _currentTab == _Tab.silhouette) {
        _currentTab = _Tab.rule;
      }
    });
    widget.onExpandedChanged?.call(true);
  }

  void _collapse() {
    setState(() => _isExpanded = false);
    widget.onExpandedChanged?.call(false);
  }

  Widget _buildSummaryPill() {
    final ruleLabel = CompositionRuleRegistry.of(widget.selected).label;
    final silhouette = widget.selectedSilhouette ?? SilhouetteType.none;
    final summary = widget.showSilhouetteTab
        ? '$ruleLabel · ${_silhouetteLabel(silhouette)}'
        : ruleLabel;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _expand,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 12,
                color: Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: Color(0xFF6B7280),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(_Tab tab) {
    final isSelected = _currentTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = tab),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFBFDBFE).withValues(alpha: 0.72)
              : const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF93C5FD)
                : const Color(0xFFE5EEF8),
          ),
        ),
        child: Text(
          _tabTitle(tab),
          style: TextStyle(
            color:
                isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF6B7280),
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildRuleOptions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in CompositionRuleRegistry.ordered) ...[
            if (type != CompositionRuleRegistry.ordered.first)
              const SizedBox(width: 6),
            _RuleChip(
              label: CompositionRuleRegistry.of(type).label,
              icon: CompositionRuleRegistry.of(type).icon,
              selected: type == widget.selected,
              onTap: () => widget.onChanged(type),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = widget.showSilhouetteTab ? _currentTab : _Tab.rule;

    if (!_isExpanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _buildSummaryPill(),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.16),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.showSilhouetteTab) ...[
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTabButton(_Tab.rule),
                              const SizedBox(width: 6),
                              _buildTabButton(_Tab.silhouette),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _collapse,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF6B7280),
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ] else
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _collapse,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF6B7280),
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                if (!widget.showSilhouetteTab) const SizedBox(height: 4),
                if (activeTab == _Tab.rule)
                  _buildRuleOptions()
                else
                  SilhouetteSelector(
                    selected: widget.selectedSilhouette ?? SilhouetteType.none,
                    onChanged: widget.onSilhouetteChanged ?? (_) {},
                  ),
              ],
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
