import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../firebase/history_service.dart';
import 'history_detail_screen.dart';

const _kBg = Color(0xFFF7F8FB);
const _kBlue = Color(0xFF3182F6);
const _kDark = Color(0xFF191F28);
const _kGrey600 = Color(0xFF6B7684);
const _kGrey400 = Color(0xFFB0B8C1);
const _kGrey100 = Color(0xFFF2F4F6);
const _kDelete = Color(0xFF455468);
const _kDeleteConfirm = Color(0xFF24364F);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Set<String> _selected = {};
  late final Stream<List<HistoryEntry>> _historyStream;
  DateTime? _selectedDate;
  bool _selectMode = false;

  bool get _hasSelection => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _historyStream = HistoryService.instance.watchHistory();
  }

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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showModalBottomSheet<DateTime?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CalendarSheet(
        initialDate: _selectedDate ?? now,
        selectedDate: _selectedDate,
      ),
    );
    if (picked == null) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _selected.clear();
      _selectMode = false;
    });
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
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
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kDeleteConfirm,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _selectMode
                            ? _cancelSelect
                            : () => Navigator.of(context).pop(),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            _selectMode
                                ? Icons.close_rounded
                                : Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: _kDark,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _DateFilterChip(
                        selectedDate: _selectedDate,
                        onClear:
                            _selectedDate == null ? null : _clearDateFilter,
                      ),
                      const Spacer(),
                      _HeaderActionButton(
                        icon: Icons.calendar_month_rounded,
                        onTap: _pickDate,
                        color: _kBlue,
                      ),
                      const SizedBox(width: 8),
                      _HeaderActionButton(
                        icon: _selectMode
                            ? Icons.delete_rounded
                            : Icons.delete_outline_rounded,
                        onTap: _selectMode
                            ? (_hasSelection ? _deleteSelected : null)
                            : _enterSelectMode,
                        color: _selectMode && _hasSelection
                            ? _kDeleteConfirm
                            : _kDelete,
                        backgroundColor: _selectMode && _hasSelection
                            ? _kDeleteConfirm.withValues(alpha: 0.12)
                            : Colors.white,
                        borderColor: const Color(0xFFE5E8EF),
                      ),
                    ],
                  ),
                  if (_selectMode) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _hasSelection
                            ? '${_selected.length}개 선택됨'
                            : '삭제할 기록을 선택하세요',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _kGrey600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── 리스트 ──
            Expanded(
              child: StreamBuilder<List<HistoryEntry>>(
                stream: _historyStream,
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

                  final visibleItems = items
                      .where(_matchesSelectedDate)
                      .toList()
                    ..sort((a, b) => b.analyzedAt.compareTo(a.analyzedAt));

                  if (visibleItems.isEmpty) {
                    return _EmptyState(
                      title: '선택한 날짜의 기록이 없어요',
                      message: '다른 날짜를 선택하거나 전체 기간으로 돌아가 보세요.',
                      icon: Icons.event_busy_rounded,
                    );
                  }

                  return Stack(
                    children: [
                      ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          2,
                          16,
                          _selectMode ? 96 : 24,
                        ),
                        itemCount: visibleItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final entry = visibleItems[index];
                          return _HistoryTile(
                            entry: entry,
                            selected: _selected.contains(entry.id),
                            selectMode: _selectMode,
                            onTap: () => _onCardTap(entry),
                          );
                        },
                      ),
                      if (_selectMode)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: _SelectionBar(
                            selectedCount: _selected.length,
                            onCancel: _cancelSelect,
                            onDelete: _hasSelection ? _deleteSelected : null,
                          ),
                        ),
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

  bool _matchesSelectedDate(HistoryEntry entry) {
    final selected = _selectedDate;
    if (selected == null) return true;
    final analyzed = entry.analyzedAt;
    return analyzed.year == selected.year &&
        analyzed.month == selected.month &&
        analyzed.day == selected.day;
  }

  void _onCardTap(HistoryEntry e) {
    if (_selectMode) {
      _toggleSelect(e.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => HistoryDetailScreen(entry: e)),
      );
    }
  }

}

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final Color? backgroundColor;
  final Color? borderColor;

  const _HeaderActionButton({
    required this.icon,
    required this.onTap,
    required this.color,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: backgroundColor ?? color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(13),
          border: borderColor == null ? null : Border.all(color: borderColor!),
        ),
        child: Icon(icon, size: 19, color: color),
      ),
    );
  }
}

class _DateFilterChip extends StatelessWidget {
  final DateTime? selectedDate;
  final VoidCallback? onClear;

  const _DateFilterChip({required this.selectedDate, required this.onClear});

  String get _label {
    final date = selectedDate;
    if (date == null) return '전체 기간';
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E8EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_rounded, size: 15, color: _kBlue),
          const SizedBox(width: 7),
          Text(
            _label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kDark,
            ),
          ),
          if (onClear != null)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close_rounded,
                  size: 17,
                  color: _kGrey400,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime? selectedDate;

  const _CalendarSheet({required this.initialDate, required this.selectedDate});

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late DateTime _visibleMonth;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
    );
    _selected = widget.selectedDate;
  }

  void _moveMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final leading = firstDay.weekday % 7;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: _kGrey100,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${_visibleMonth.year}년 ${_visibleMonth.month}월',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _kDark,
                  ),
                ),
                const Spacer(),
                _MonthButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _moveMonth(-1),
                ),
                const SizedBox(width: 6),
                _MonthButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _moveMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final label in ['일', '월', '화', '수', '목', '금', '토'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _kGrey400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: totalCells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemBuilder: (context, index) {
                final day = index - leading + 1;
                if (day < 1 || day > daysInMonth) {
                  return const SizedBox.shrink();
                }

                final date = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month,
                  day,
                );
                final isSelected =
                    _selected != null && _sameDay(_selected!, date);
                final isToday = _sameDay(today, date);

                return GestureDetector(
                  onTap: () => setState(() => _selected = date),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _kBlue
                          : isToday
                          ? _kBlue.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? Colors.white
                            : isToday
                            ? _kBlue
                            : _kDark,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '취소',
                    style: TextStyle(
                      color: _kGrey600,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(DateTime.now()),
                  child: const Text(
                    '오늘',
                    style: TextStyle(
                      color: _kBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  child: const Text('적용'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MonthButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _kGrey100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: _kDark),
      ),
    );
  }
}

// ── 히스토리 타일 ──
class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final bool selected;
  final bool selectMode;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.entry,
    required this.selected,
    required this.selectMode,
    required this.onTap,
  });

  String get _title {
    final name = entry.bestFileName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return entry.type == HistoryType.acut ? 'BEST 컷' : '분석한 사진';
  }

  String get _countLabel => '총 ${entry.photoCount}장 분석';

  String get _dateTimeLabel {
    final d = entry.analyzedAt;
    return '${d.month}.${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  int? get _score {
    if (entry.type == HistoryType.single) {
      return entry.evaluation?.finalPct;
    }
    for (final item in entry.rankedItems) {
      if (item.isBestShot && item.evaluation != null) {
        return item.evaluation!.finalPct;
      }
    }
    for (final item in entry.rankedItems) {
      if (item.rank == 1 && item.evaluation != null) {
        return item.evaluation!.finalPct;
      }
    }
    return null;
  }

  String? get _thumbnailAssetId => entry.type == HistoryType.acut
      ? entry.bestAssetId
      : entry.assetId ?? entry.bestAssetId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _kBlue.withValues(alpha: 0.035) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _kBlue.withValues(alpha: 0.45)
                : const Color(0xFFE8ECF3),
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                _HistoryThumbnail(assetId: _thumbnailAssetId),
                if (selectMode)
                  Positioned(
                    left: 5,
                    top: 5,
                    child: _SelectionDot(selected: selected),
                  ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _kDark,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      _MetaText(_countLabel),
                      const _MetaDot(),
                      _MetaText(_dateTimeLabel),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _ScorePill(score: _score),
          ],
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  final String text;

  const _MetaText(this.text);

  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: 0,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _kGrey600,
        ),
      ),
    );
  }
}

class _MetaDot extends StatelessWidget {
  const _MetaDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: _kGrey400.withValues(alpha: 0.75),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  final int? score;

  const _ScorePill({required this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        score == null ? '종합 -' : '종합 $score점',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: _kBlue,
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  final bool selected;

  const _SelectionDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? _kBlue : Colors.transparent,
        border: Border.all(color: selected ? _kBlue : _kGrey400, width: 1.5),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _HistoryThumbnail extends StatefulWidget {
  final String? assetId;

  const _HistoryThumbnail({required this.assetId});

  @override
  State<_HistoryThumbnail> createState() => _HistoryThumbnailState();
}

class _HistoryThumbnailState extends State<_HistoryThumbnail> {
  late Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant _HistoryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
      _thumbnailFuture = _loadThumbnail();
    }
  }

  Future<Uint8List?> _loadThumbnail() async {
    final id = widget.assetId;
    if (id == null || id.isEmpty) return null;

    final asset = await AssetEntity.fromId(id);
    if (asset == null) return null;

    return asset.thumbnailDataWithSize(const ThumbnailSize(180, 180));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 58,
        height: 58,
        child: FutureBuilder<Uint8List?>(
          future: _thumbnailFuture,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null) {
              return Image.memory(bytes, fit: BoxFit.cover);
            }

            return Container(
              color: _kGrey100,
              child: const Icon(
                Icons.photo_outlined,
                size: 22,
                color: _kGrey400,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  const _SelectionBar({
    required this.selectedCount,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGrey100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCancel,
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.close_rounded, color: _kGrey600, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              selectedCount > 0 ? '$selectedCount개 선택됨' : '삭제할 기록 선택',
              style: const TextStyle(
                color: _kDark,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: onDelete == null
                    ? _kDelete.withValues(alpha: 0.08)
                    : _kDeleteConfirm,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.delete_rounded,
                    size: 18,
                    color: onDelete == null
                        ? _kDelete.withValues(alpha: 0.35)
                        : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '삭제',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: onDelete == null
                          ? _kDelete.withValues(alpha: 0.35)
                          : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 빈 상태 ──
class _EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _EmptyState({
    this.title = '아직 분석 기록이 없어요',
    this.message = '갤러리에서 사진을 선택하거나\n카메라로 촬영 후 분석하면 기록이 쌓여요.',
    this.icon = Icons.history_rounded,
  });

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
              child: Icon(
                icon,
                size: 32,
                color: _kGrey400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _kDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
