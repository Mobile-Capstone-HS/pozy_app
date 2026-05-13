import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/model/photo_evaluation_result.dart';
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
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: _kDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _kGrey100),
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
        _Card(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailThumbnail(assetId: entry.assetId ?? entry.bestAssetId),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                        _InfoPill(label: eval.verdict, strong: true),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _evaluationFactPills(eval),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Text(
                          '원본 사진 보기',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _kBlue,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _kBlue,
                        ),
                      ],
                    ),
                  ],
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
                      .map(
                        (c) => _Chip(label: c, color: const Color(0xFFF59E0B)),
                      )
                      .toList(),
                ),
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

    final sorted = [...items]
      ..sort((a, b) {
        if (a.rank == null && b.rank == null) return 0;
        if (a.rank == null) return 1;
        if (b.rank == null) return -1;
        return a.rank!.compareTo(b.rank!);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _Card(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardTitle(title: '순위별 결과'),
              const SizedBox(height: 12),
              for (int i = 0; i < sorted.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
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

    return GestureDetector(
      onTap: onOpenPhoto,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: item.isBestShot
              ? _kBlue.withValues(alpha: 0.06)
              : _kGrey100.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.isBestShot
                ? _kBlue.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _DetailThumbnail(assetId: item.assetId, size: 48),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _RankBadge(label: _rankLabel, color: _rankColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _kDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (eval != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        ..._compactScoreBadges(eval),
                        if (item.isACut && !item.isBestShot)
                          const _ScoreBadge(
                            icon: Icons.check_rounded,
                            label: 'A컷',
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 20, color: _kGrey400),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _RankBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 공통 위젯
// ─────────────────────────────────────────────────────────────

List<Widget> _compactScoreBadges(PhotoEvaluationResult eval) {
  return [
    _ScoreBadge(icon: Icons.star_rounded, label: '종합 ${eval.finalPct}'),
    _ScoreBadge(icon: Icons.tune_rounded, label: '기술 ${eval.technicalPct}'),
    if (eval.aestheticPct != null)
      _ScoreBadge(
        icon: Icons.auto_awesome_rounded,
        label: '미적 ${eval.aestheticPct}',
      ),
  ];
}

List<Widget> _evaluationFactPills(
  PhotoEvaluationResult eval, {
  bool compact = false,
}) {
  final pills = <Widget>[
    _InfoPill(label: '종합 ${eval.finalPct}점', strong: true),
    _InfoPill(label: '기술 ${eval.technicalPct}점'),
  ];

  final aestheticPct = eval.aestheticPct;
  if (aestheticPct != null) {
    pills.add(_InfoPill(label: '미적 $aestheticPct점'));
  }

  if (!compact) {
    final nimaPct = eval.nimaPct;
    final rgnetPct = eval.rgnetPct;
    final alampPct = eval.alampPct;
    if (nimaPct != null) pills.add(_InfoPill(label: 'NIMA $nimaPct점'));
    if (rgnetPct != null) pills.add(_InfoPill(label: 'RGNet $rgnetPct점'));
    if (alampPct != null) pills.add(_InfoPill(label: 'ALAMP $alampPct점'));
  }

  final details = eval.scoreDetails.take(compact ? 1 : 2);
  for (final detail in details) {
    pills.add(_InfoPill(label: '${detail.label} ${detail.normalizedPct}점'));
  }

  pills.add(_InfoPill(label: eval.verdict));
  return pills;
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 22,
            offset: const Offset(0, 8),
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

  const _PhotoLink({required this.label, required this.onTap});

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
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _kDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailThumbnail extends StatelessWidget {
  final String? assetId;
  final double size;

  const _DetailThumbnail({required this.assetId, this.size = 104});

  Future<Uint8List?> _loadThumbnail() async {
    final id = assetId;
    if (id == null || id.isEmpty) return null;

    final asset = await AssetEntity.fromId(id);
    if (asset == null) return null;

    return asset.thumbnailDataWithSize(const ThumbnailSize(240, 240));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size <= 56 ? 12 : 20),
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<Uint8List?>(
          future: _loadThumbnail(),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null) {
              return Image.memory(bytes, fit: BoxFit.cover);
            }

            return Container(
              color: _kGrey100,
              child: const Icon(
                Icons.photo_outlined,
                size: 24,
                color: _kGrey400,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final bool strong;

  const _InfoPill({required this.label, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: strong ? _kBlue.withValues(alpha: 0.10) : _kGrey100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: strong ? _kBlue : _kGrey600,
          ),
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ScoreBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 23,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kGrey100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _kGrey600),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _kGrey600,
            ),
          ),
        ],
      ),
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
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _kGrey600,
            ),
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

  const _AssetPreviewScreen({required this.asset, required this.title});

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
                          Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 42,
                          ),
                          SizedBox(height: 12),
                          Text(
                            '사진을 불러오지 못했어요.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.memory(snapshot.data!, fit: BoxFit.contain),
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
                          Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
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
