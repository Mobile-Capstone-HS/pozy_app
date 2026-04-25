import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../firebase/history_service.dart';
import 'main_shell.dart' show galleryIntentNotifier;

const _kBg = Color(0xFFF7F8FB);
const _kBlue = Color(0xFF3182F6);
const _kDark = Color(0xFF191F28);
const _kGrey600 = Color(0xFF6B7684);
const _kGrey400 = Color(0xFFB0B8C1);
const _kGrey100 = Color(0xFFF2F4F6);

class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;

  const HistoryDetailScreen({super.key, required this.entry});

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
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kGrey100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: _kDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      entry.typeLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _kDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  // 날짜 뱃지
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _kGrey100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _formatDate(entry.analyzedAt),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kGrey600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: entry.type == HistoryType.acut
                  ? _ACutDetail(entry: entry)
                  : _SingleDetail(entry: entry),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ── 원본 사진 열기 ──
Future<void> _openHistoryPhoto(
  BuildContext context, {
  required String? assetId,
  required String fileName,
}) async {
  if (assetId == null || assetId.isEmpty) {
    _showMsg(context, '이 기록에는 원본 사진 연결 정보가 없어요.');
    return;
  }

  final permission = await PhotoManager.requestPermissionExtend();
  if (!context.mounted) return;

  if (!permission.isAuth && !permission.hasAccess) {
    _showMsg(context, '원본 사진을 보려면 사진 보관함 접근 권한이 필요해요.');
    return;
  }

  final asset = await AssetEntity.fromId(assetId);
  if (!context.mounted) return;

  if (asset == null) {
    _showMsg(context, '원본 사진을 찾을 수 없어요. 삭제되었거나 접근 범위에서 제외되었을 수 있어요.');
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _AssetPreviewScreen(asset: asset, title: fileName),
    ),
  );
}

void _showMsg(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

// ── 단일 평가 디테일 ──
class _SingleDetail extends StatelessWidget {
  final HistoryEntry entry;

  const _SingleDetail({required this.entry});

  @override
  Widget build(BuildContext context) {
    final eval = entry.evaluation;

    if (eval == null) return const _NoDataState();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // 점수 카드
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _PhotoLink(
                      label: eval.fileName ?? entry.bestFileName ?? '사진',
                      onTap: () => _openHistoryPhoto(
                        context,
                        assetId: entry.assetId ?? entry.bestAssetId,
                        fileName:
                            eval.fileName ?? entry.bestFileName ?? '사진',
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kGrey100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      eval.verdict,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ScoreBar(label: '종합 점수', pct: eval.finalPct),
              const SizedBox(height: 10),
              _ScoreBar(label: '기술 점수', pct: eval.technicalPct),
              if (eval.hasAestheticScore) ...[
                const SizedBox(height: 10),
                _ScoreBar(label: '미적 점수', pct: eval.aestheticPct!),
              ],
              const SizedBox(height: 14),
              Text(
                eval.qualitySummary,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: _kGrey600,
                ),
              ),
            ],
          ),
        ),

        // 평가 노트
        if (eval.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardTitle(title: '평가 노트'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: eval.notes
                      .map((c) => _Chip(label: c, color: _kDark))
                      .toList(),
                ),
              ],
            ),
          ),
        ],

        // 주의 사항
        if (eval.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardTitle(title: '주의 사항'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: eval.warnings
                      .map((c) => _Chip(
                          label: c, color: const Color(0xFFF59E0B)))
                      .toList(),
                ),
              ],
            ),
          ),
        ],

        // 세부 점수
        if (eval.scoreDetails.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardTitle(title: '세부 점수'),
                const SizedBox(height: 14),
                ...eval.scoreDetails.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child:
                          _ScoreBar(label: d.label, pct: d.normalizedPct),
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── A컷 랭킹 디테일 ──
class _ACutDetail extends StatelessWidget {
  final HistoryEntry entry;

  const _ACutDetail({required this.entry});

  @override
  Widget build(BuildContext context) {
    final items = entry.rankedItems;

    if (items.isEmpty) return const _NoDataState();

    final sorted = [...items]..sort((a, b) {
        if (a.rank == null && b.rank == null) return 0;
        if (a.rank == null) return 1;
        if (b.rank == null) return -1;
        return a.rank!.compareTo(b.rank!);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        // 요약 카드
        _Card(
          child: Row(
            children: [
              _StatItem(label: '분석 사진', value: '${entry.photoCount}장'),
              _vertDivider,
              _StatItem(
                label: 'Best',
                value: entry.bestFileName != null
                    ? entry.bestFileName!.length > 10
                        ? '${entry.bestFileName!.substring(0, 10)}...'
                        : entry.bestFileName!
                    : '-',
              ),
              _vertDivider,
              _StatItem(
                label: '최고 점수',
                value: entry.bestScore != null
                    ? '${(entry.bestScore! * 100).round()}점'
                    : '-',
              ),
              _vertDivider,
              _StatItem(label: '모드', value: entry.mode ?? '자동'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 순위 카드 그룹
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardTitle(title: '순위별 결과'),
              const SizedBox(height: 14),
              for (int i = 0; i < sorted.length; i++) ...[
                if (i > 0)
                  const Divider(height: 24, color: _kGrey100),
                _RankedTile(
                  item: sorted[i],
                  onOpenPhoto: () => _openHistoryPhoto(
                    context,
                    assetId: sorted[i].assetId,
                    fileName: sorted[i].fileName,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget get _vertDivider => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: _kGrey100,
      );
}

// ── 통계 아이템 ──
class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _kDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: _kGrey600),
          ),
        ],
      ),
    );
  }
}

// ── 순위 타일 ──
class _RankedTile extends StatelessWidget {
  final HistoryRankedItem item;
  final VoidCallback onOpenPhoto;

  const _RankedTile({required this.item, required this.onOpenPhoto});

  Color get _rankColor {
    if (item.isBestShot) return _kDark;
    if (item.rank != null && item.rank! <= 3) return _kBlue;
    if (item.isACut) return const Color(0xFF0F766E);
    return _kGrey600;
  }

  String get _rankLabel {
    if (item.isBestShot) return 'BEST';
    if (item.rank != null) return '#${item.rank}';
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final eval = item.evaluation;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _rankColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _rankLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PhotoLink(label: item.fileName, onTap: onOpenPhoto, compact: true),
              if (eval != null) ...[
                const SizedBox(height: 6),
                Text(
                  eval.primaryHint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: _kGrey600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill(label: '종합 ${eval.finalPct}점'),
                    _Pill(label: eval.verdict),
                    if (item.isACut && !item.isBestShot)
                      const _Pill(label: 'A컷 후보'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 공통 위젯
// ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String title;

  const _CardTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: _kDark,
      ),
    );
  }
}

class _PhotoLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const _PhotoLink({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w800,
                color: _kBlue,
                decoration: TextDecoration.underline,
                decorationColor: _kBlue.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.photo_library_outlined,
            size: compact ? 15 : 16,
            color: _kBlue,
          ),
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final String label;
  final int pct;

  const _ScoreBar({required this.label, required this.pct});

  Color get _barColor {
    if (pct >= 70) return _kBlue;
    if (pct >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: _kGrey600),
          ),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: _kGrey100,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: pct / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: _barColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            '$pct점',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _kDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kGrey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _kGrey600,
        ),
      ),
    );
  }
}

class _NoDataState extends StatelessWidget {
  const _NoDataState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _kGrey100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.inbox_rounded, size: 28, color: _kGrey400),
          ),
          const SizedBox(height: 14),
          const Text(
            '저장된 결과 데이터가 없어요',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _kGrey600),
          ),
        ],
      ),
    );
  }
}

// ── 사진 미리보기 (메타데이터 + 갤러리 이동) ──
class _AssetPreviewScreen extends StatefulWidget {
  final AssetEntity asset;
  final String title;

  const _AssetPreviewScreen({
    required this.asset,
    required this.title,
  });

  @override
  State<_AssetPreviewScreen> createState() => _AssetPreviewScreenState();
}

class _AssetPreviewScreenState extends State<_AssetPreviewScreen> {
  int _fileSize = 0;

  @override
  void initState() {
    super.initState();
    _loadFileSize();
  }

  Future<void> _loadFileSize() async {
    try {
      final file = await widget.asset.file;
      if (file != null && mounted) {
        final size = await file.length();
        setState(() => _fileSize = size);
      }
    } catch (_) {}
  }

  String get _sizeLabel {
    if (_fileSize <= 0) return '-';
    if (_fileSize >= 1024 * 1024) {
      return '${(_fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (_fileSize >= 1024) {
      return '${(_fileSize / 1024).toStringAsFixed(0)} KB';
    }
    return '$_fileSize B';
  }

  String get _dateLabel {
    final d = widget.asset.createDateTime;
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}  '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _goToGallery() {
    galleryIntentNotifier.value = widget.asset.id;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── 상단 바 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // ── 사진 ──
            Expanded(
              child: FutureBuilder<Uint8List?>(
                future: asset.originBytes,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white70,
                        strokeWidth: 2.4,
                      ),
                    );
                  }

                  if (snapshot.data == null) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined,
                              color: Colors.white54, size: 42),
                          SizedBox(height: 12),
                          Text(
                            '사진을 불러오지 못했어요.',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }

                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child:
                          Image.memory(snapshot.data!, fit: BoxFit.contain),
                    ),
                  );
                },
              ),
            ),

            // ── 메타데이터 + 갤러리 이동 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // 촬영 날짜
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    label: '촬영 날짜',
                    value: _dateLabel,
                  ),
                  const SizedBox(height: 8),
                  // 파일 크기
                  _InfoRow(
                    icon: Icons.save_outlined,
                    label: '파일 크기',
                    value: _sizeLabel,
                  ),
                  const SizedBox(height: 16),

                  // 갤러리에서 보기 버튼
                  GestureDetector(
                    onTap: _goToGallery,
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _kBlue,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library_outlined,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            '갤러리에서 보기',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.white38),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white38,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
