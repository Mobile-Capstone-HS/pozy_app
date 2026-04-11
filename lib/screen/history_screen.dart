import 'package:flutter/material.dart';

import '../firebase/history_service.dart';
import '../theme/app_colors.dart';
import '../widget/app_top_bar.dart';
import 'history_detail_screen.dart';

const _kBlue = Color(0xFF64B5F6);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Set<String> _selected = {};
  bool _selectMode = false;

  bool get _hasSelection => _selected.isNotEmpty;

  void _enterSelectMode() {
    setState(() {
      _selected.clear();
      _selectMode = true;
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _cancelSelect() {
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    if (!_hasSelection) return;

    final ids = List<String>.from(_selected);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('기록 삭제', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('선택한 ${ids.length}개의 기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final id in ids) {
      await HistoryService.instance.delete(id);
    }
    _cancelSelect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: _selectMode
                    ? (_hasSelection ? '${_selected.length}개 선택됨' : '삭제할 기록 선택')
                    : '분석 히스토리',
                leadingIcon:
                    _selectMode ? Icons.close_rounded : Icons.arrow_back_ios_new_rounded,
                onLeadingTap:
                    _selectMode ? _cancelSelect : () => Navigator.of(context).pop(),
                trailing: _TopBarIconButton(
                  icon: _selectMode ? Icons.delete_rounded : Icons.delete_outline_rounded,
                  onTap: _selectMode
                      ? (_hasSelection ? _deleteSelected : null)
                      : _enterSelectMode,
                  foregroundColor: Colors.red,
                  backgroundColor: Colors.red.withValues(
                    alpha: _selectMode
                        ? (_hasSelection ? 0.12 : 0.05)
                        : 0.08,
                  ),
                  borderColor:
                      _selectMode && !_hasSelection ? Colors.red.withValues(alpha: 0.08) : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<HistoryEntry>>(
                stream: HistoryService.instance.watchHistory(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: _kBlue,
                      ),
                    );
                  }

                  final items = snapshot.data ?? [];

                  if (items.isEmpty) {
                    return const _EmptyState();
                  }

                  final pinned = items.where((e) => e.pinned).toList();
                  final rest = items.where((e) => !e.pinned).toList();

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        _SectionLabel(label: '고정됨', icon: Icons.push_pin_rounded),
                        const SizedBox(height: 8),
                        ...pinned.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _HistoryCard(
                                entry: e,
                                selected: _selected.contains(e.id),
                                selectMode: _selectMode,
                                onTap: () => _selectMode
                                    ? _toggleSelect(e.id)
                                    : Navigator.of(context).push(MaterialPageRoute<void>(
                                        builder: (_) => HistoryDetailScreen(entry: e),
                                      )),
                                onPin: () => HistoryService.instance.togglePin(e.id, e.pinned),
                              ),
                            )),
                        const SizedBox(height: 4),
                      ],
                      if (rest.isNotEmpty) ...[
                        _SectionLabel(label: '전체 기록', icon: Icons.history_rounded),
                        const SizedBox(height: 8),
                        ...rest.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _HistoryCard(
                                entry: e,
                                selected: _selected.contains(e.id),
                                selectMode: _selectMode,
                                onTap: () => _selectMode
                                    ? _toggleSelect(e.id)
                                    : Navigator.of(context).push(MaterialPageRoute<void>(
                                        builder: (_) => HistoryDetailScreen(entry: e),
                                      )),
                                onPin: () => HistoryService.instance.togglePin(e.id, e.pinned),
                              ),
                            )),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color? borderColor;

  const _TopBarIconButton({
    required this.icon,
    required this.onTap,
    required this.foregroundColor,
    required this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: borderColor == null ? null : Border.all(color: borderColor!),
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null
              ? foregroundColor.withValues(alpha: 0.35)
              : foregroundColor,
        ),
      ),
    );
  }
}

// ── 섹션 라벨 ─────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.secondaryText),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

// ── 빈 상태 ───────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _kBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history_rounded, size: 34, color: _kBlue),
            ),
            const SizedBox(height: 20),
            const Text(
              '아직 분석 기록이 없어요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '갤러리에서 사진을 선택하거나\n카메라로 촬영 후 분석하면 기록이 쌓여요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 히스토리 카드 ─────────────────────────────────────────
class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onPin;

  const _HistoryCard({
    required this.entry,
    required this.selected,
    required this.selectMode,
    required this.onTap,
    required this.onPin,
  });

  IconData get _icon => entry.type == HistoryType.acut
      ? Icons.content_cut_rounded
      : Icons.auto_awesome_rounded;

  String get _dateLabel {
    final d = entry.analyzedAt;
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? _kBlue.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _kBlue : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _kBlue : Colors.transparent,
                    border: Border.all(
                      color: selected ? _kBlue : AppColors.lightText,
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _kBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, color: _kBlue, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.typeLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                      if (entry.pinned) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.push_pin_rounded, size: 13, color: _kBlue),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (!selectMode) ...[
              GestureDetector(
                onTap: onPin,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    entry.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 18,
                    color: entry.pinned ? _kBlue : AppColors.lightText,
                  ),
                ),
              ),
              const SizedBox(width: 2),
            ],
            Text(
              _dateLabel,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.lightText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
