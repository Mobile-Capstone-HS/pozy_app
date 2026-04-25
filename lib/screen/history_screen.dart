import 'package:flutter/material.dart';

import '../firebase/history_service.dart';
import 'history_detail_screen.dart';

const _kBg = Color(0xFFF7F8FB);
const _kBlue = Color(0xFF3182F6);
const _kDark = Color(0xFF191F28);
const _kGrey600 = Color(0xFF6B7684);
const _kGrey400 = Color(0xFFB0B8C1);
const _kGrey100 = Color(0xFFF2F4F6);

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
        title: const Text(
          '기록 삭제',
          style: TextStyle(fontWeight: FontWeight.w800, color: _kDark),
        ),
        content: Text(
          '선택한 ${ids.length}개의 기록을 삭제할까요?',
          style: const TextStyle(color: _kGrey600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: _kGrey600)),
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
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── 헤더 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _selectMode
                        ? _cancelSelect
                        : () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kGrey100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _selectMode
                            ? Icons.close_rounded
                            : Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: _kDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _selectMode
                          ? (_hasSelection
                              ? '${_selected.length}개 선택됨'
                              : '삭제할 기록 선택')
                          : '분석 히스토리',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _kDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _selectMode
                        ? (_hasSelection ? _deleteSelected : null)
                        : _enterSelectMode,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _selectMode && _hasSelection
                            ? Colors.red.withValues(alpha: 0.1)
                            : _kGrey100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _selectMode
                            ? Icons.delete_rounded
                            : Icons.delete_outline_rounded,
                        size: 20,
                        color: _selectMode
                            ? (_hasSelection
                                ? Colors.red
                                : Colors.red.withValues(alpha: 0.35))
                            : _kGrey600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 리스트 ──
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
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        const _SectionLabel(
                          label: '고정됨',
                          icon: Icons.push_pin_rounded,
                        ),
                        const SizedBox(height: 10),
                        _HistoryCardGroup(
                          entries: pinned,
                          selected: _selected,
                          selectMode: _selectMode,
                          onTap: _onCardTap,
                          onPin: _onPin,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (rest.isNotEmpty) ...[
                        const _SectionLabel(
                          label: '전체 기록',
                          icon: Icons.history_rounded,
                        ),
                        const SizedBox(height: 10),
                        _HistoryCardGroup(
                          entries: rest,
                          selected: _selected,
                          selectMode: _selectMode,
                          onTap: _onCardTap,
                          onPin: _onPin,
                        ),
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

  void _onCardTap(HistoryEntry e) {
    if (_selectMode) {
      _toggleSelect(e.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HistoryDetailScreen(entry: e),
        ),
      );
    }
  }

  void _onPin(HistoryEntry e) {
    HistoryService.instance.togglePin(e.id, e.pinned);
  }
}

// ── 섹션 라벨 ──
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _kGrey400),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kGrey600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 카드 그룹 (하나의 흰색 카드 안에 리스트) ──
class _HistoryCardGroup extends StatelessWidget {
  final List<HistoryEntry> entries;
  final Set<String> selected;
  final bool selectMode;
  final ValueChanged<HistoryEntry> onTap;
  final ValueChanged<HistoryEntry> onPin;

  const _HistoryCardGroup({
    required this.entries,
    required this.selected,
    required this.selectMode,
    required this.onTap,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            for (int i = 0; i < entries.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: 68, color: _kGrey100),
              _HistoryTile(
                entry: entries[i],
                selected: selected.contains(entries[i].id),
                selectMode: selectMode,
                onTap: () => onTap(entries[i]),
                onPin: () => onPin(entries[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 히스토리 타일 (카드 내 개별 행) ──
class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;
  final VoidCallback onPin;

  const _HistoryTile({
    required this.entry,
    required this.selected,
    required this.selectMode,
    required this.onTap,
    required this.onPin,
  });

  IconData get _icon => entry.type == HistoryType.acut
      ? Icons.content_cut_rounded
      : Icons.auto_awesome_rounded;

  Color get _iconBg => entry.type == HistoryType.acut
      ? const Color(0xFFEBF4FF)
      : const Color(0xFFFFF4E6);

  Color get _iconColor => entry.type == HistoryType.acut
      ? _kBlue
      : const Color(0xFFF59E0B);

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
        color: selected ? _kBlue.withValues(alpha: 0.06) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 선택 모드 체크박스
            if (selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _kBlue : Colors.transparent,
                    border: Border.all(
                      color: selected ? _kBlue : _kGrey400,
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),

            // 타입 아이콘
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _iconBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_icon, color: _iconColor, size: 20),
            ),
            const SizedBox(width: 14),

            // 텍스트
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.typeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _kDark,
                          ),
                        ),
                      ),
                      if (entry.pinned) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.push_pin_rounded,
                          size: 13,
                          color: _kBlue,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _kGrey600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 핀 + 날짜
            if (!selectMode)
              GestureDetector(
                onTap: onPin,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    entry.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    size: 18,
                    color: entry.pinned ? _kBlue : _kGrey400,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            Text(
              _dateLabel,
              style: const TextStyle(
                fontSize: 12,
                color: _kGrey400,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 빈 상태 ──
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
                color: _kGrey100,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 32,
                color: _kGrey400,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '아직 분석 기록이 없어요',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _kDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '갤러리에서 사진을 선택하거나\n카메라로 촬영 후 분석하면 기록이 쌓여요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: _kGrey600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
