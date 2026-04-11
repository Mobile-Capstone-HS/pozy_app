import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/model/photo_evaluation_result.dart';
import '../firebase/history_service.dart';
import '../theme/app_colors.dart';
import '../widget/app_top_bar.dart';

const _kBlue = Color(0xFF64B5F6);

class HistoryDetailScreen extends StatelessWidget {
  final HistoryEntry entry;

  const HistoryDetailScreen({super.key, required this.entry});

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
                title: entry.typeLabel,
                leadingIcon: Icons.arrow_back_ios_new_rounded,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
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
}

Future<void> _openHistoryPhoto(
  BuildContext context, {
  required String? assetId,
  required String fileName,
}) async {
  if (assetId == null || assetId.isEmpty) {
    _showHistoryPhotoMessage(context, '이 기록에는 원본 사진 연결 정보가 없어요.');
    return;
  }

  final permission = await PhotoManager.requestPermissionExtend();
  if (!context.mounted) return;

  if (!permission.isAuth && !permission.hasAccess) {
    _showHistoryPhotoMessage(context, '원본 사진을 보려면 사진 보관함 접근 권한이 필요해요.');
    return;
  }

  final asset = await AssetEntity.fromId(assetId);
  if (!context.mounted) return;

  if (asset == null) {
    _showHistoryPhotoMessage(
      context,
      '원본 사진을 찾을 수 없어요. 삭제되었거나 접근 가능한 범위에서 제외되었을 수 있어요.',
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _HistoryAssetPreviewScreen(asset: asset, title: fileName),
    ),
  );
}

void _showHistoryPhotoMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ── 단일 평가 디테일 ──────────────────────────────────────
class _SingleDetail extends StatelessWidget {
  final HistoryEntry entry;

  const _SingleDetail({required this.entry});

  @override
  Widget build(BuildContext context) {
    final eval = entry.evaluation;

    if (eval == null) {
      return const _NoDataState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        _DateChip(date: entry.analyzedAt),
        const SizedBox(height: 14),
        _ScoreCard(
          fileName: eval.fileName ?? entry.bestFileName ?? '사진',
          onOpenPhoto: () => _openHistoryPhoto(
            context,
            assetId: entry.assetId ?? entry.bestAssetId,
            fileName: eval.fileName ?? entry.bestFileName ?? '사진',
          ),
          eval: eval,
        ),
        const SizedBox(height: 14),
        if (eval.notes.isNotEmpty) _ChipSection(title: '평가 노트', chips: eval.notes, color: AppColors.primaryText),
        if (eval.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ChipSection(title: '주의 사항', chips: eval.warnings, color: Colors.orange),
        ],
        if (eval.scoreDetails.isNotEmpty) ...[
          const SizedBox(height: 14),
          _ScoreDetailSection(eval: eval),
        ],
      ],
    );
  }
}

// ── A컷 랭킹 디테일 ───────────────────────────────────────
class _ACutDetail extends StatelessWidget {
  final HistoryEntry entry;

  const _ACutDetail({required this.entry});

  @override
  Widget build(BuildContext context) {
    final items = entry.rankedItems;

    if (items.isEmpty) {
      return const _NoDataState();
    }

    final sorted = [...items]..sort((a, b) {
        if (a.rank == null && b.rank == null) return 0;
        if (a.rank == null) return 1;
        if (b.rank == null) return -1;
        return a.rank!.compareTo(b.rank!);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        _DateChip(date: entry.analyzedAt),
        const SizedBox(height: 6),
        _ACutSummaryCard(entry: entry),
        const SizedBox(height: 14),
        const _SectionTitle(title: '순위별 결과'),
        const SizedBox(height: 10),
        ...sorted.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RankedItemCard(
                item: item,
                onOpenPhoto: () => _openHistoryPhoto(
                  context,
                  assetId: item.assetId,
                  fileName: item.fileName,
                ),
              ),
            )),
      ],
    );
  }
}

// ── A컷 요약 카드 ─────────────────────────────────────────
class _ACutSummaryCard extends StatelessWidget {
  final HistoryEntry entry;

  const _ACutSummaryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [_shadow],
      ),
      child: Row(
        children: [
          _StatBox(label: '분석 사진', value: '${entry.photoCount}장'),
          _divider,
          _StatBox(
            label: 'Best',
            value: entry.bestFileName != null
                ? entry.bestFileName!.length > 12
                    ? '${entry.bestFileName!.substring(0, 12)}…'
                    : entry.bestFileName!
                : '-',
          ),
          _divider,
          _StatBox(
            label: '최고 점수',
            value: entry.bestScore != null
                ? '${(entry.bestScore! * 100).round()}점'
                : '-',
          ),
          _divider,
          _StatBox(label: '모드', value: entry.mode ?? '자동'),
        ],
      ),
    );
  }

  Widget get _divider => Container(
        width: 1, height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: const Color(0xFFF0F0F0),
      );
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              )),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondaryText,
              )),
        ],
      ),
    );
  }
}

// ── 순위 아이템 카드 ──────────────────────────────────────
class _RankedItemCard extends StatelessWidget {
  final HistoryRankedItem item;
  final VoidCallback onOpenPhoto;

  const _RankedItemCard({required this.item, required this.onOpenPhoto});

  Color get _rankColor {
    if (item.isBestShot) return const Color(0xFF111827);
    if (item.rank != null && item.rank! <= 3) return const Color(0xFF2563EB);
    if (item.isACut) return const Color(0xFF0F766E);
    return const Color(0xFF64748B);
  }

  String get _rankLabel {
    if (item.isBestShot) return 'BEST';
    if (item.rank != null) return '#${item.rank}';
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final eval = item.evaluation;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [_shadow],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _rankColor,
              borderRadius: BorderRadius.circular(999),
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
                _HistoryPhotoLink(
                  label: item.fileName,
                  onTap: onOpenPhoto,
                  compact: true,
                ),
                if (eval != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    eval.primaryHint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
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
      ),
    );
  }
}

// ── 점수 카드 (단일 평가) ─────────────────────────────────
class _ScoreCard extends StatelessWidget {
  final String fileName;
  final VoidCallback onOpenPhoto;
  final PhotoEvaluationResult eval;

  const _ScoreCard({
    required this.fileName,
    required this.onOpenPhoto,
    required this.eval,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [_shadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _HistoryPhotoLink(
                  label: fileName,
                  onTap: onOpenPhoto,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  eval.verdict,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ScoreBar(label: '종합 점수', pct: eval.finalPct),
          const SizedBox(height: 8),
          _ScoreBar(label: '기술 점수', pct: eval.technicalPct),
          if (eval.hasAestheticScore) ...[
            const SizedBox(height: 8),
            _ScoreBar(label: '미적 점수', pct: eval.aestheticPct!),
          ],
          const SizedBox(height: 12),
          Text(
            eval.qualitySummary,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryPhotoLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const _HistoryPhotoLink({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: compact ? 14 : 16,
      fontWeight: FontWeight.w800,
      color: _kBlue,
      decoration: TextDecoration.underline,
      decorationColor: _kBlue.withValues(alpha: 0.55),
    );

    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: pct / 100,
              backgroundColor: const Color(0xFFF0F0F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                pct >= 70 ? _kBlue : pct >= 50 ? Colors.orange : Colors.red,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$pct점',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
          ),
        ),
      ],
    );
  }
}

// ── 칩 섹션 ──────────────────────────────────────────────
class _ChipSection extends StatelessWidget {
  final String title;
  final List<String> chips;
  final Color color;

  const _ChipSection({required this.title, required this.chips, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips
              .map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ── 점수 디테일 섹션 ──────────────────────────────────────
class _ScoreDetailSection extends StatelessWidget {
  final PhotoEvaluationResult eval;

  const _ScoreDetailSection({required this.eval});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: '세부 점수'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [_shadow],
          ),
          child: Column(
            children: eval.scoreDetails.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ScoreBar(label: d.label, pct: d.normalizedPct),
            )).toList(),
          ),
        ),
      ],
    );
  }
}

// ── 공통 위젯들 ───────────────────────────────────────────
class _DateChip extends StatelessWidget {
  final DateTime date;

  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    final label =
        '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        const Icon(Icons.access_time_rounded, size: 13, color: AppColors.lightText),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.lightText,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryText,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }
}

class _NoDataState extends StatelessWidget {
  const _NoDataState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '저장된 결과 데이터가 없어요.',
        style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
      ),
    );
  }
}

class _HistoryAssetPreviewScreen extends StatelessWidget {
  final AssetEntity asset;
  final String title;

  const _HistoryAssetPreviewScreen({
    required this.asset,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: FutureBuilder<Uint8List?>(
                future: asset.originBytes,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator(
                      color: Colors.white70,
                      strokeWidth: 2.4,
                    );
                  }

                  if (snapshot.data == null) {
                    return const Column(
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
                    );
                  }

                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                  );
                },
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
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
          ],
        ),
      ),
    );
  }
}

final _shadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.04),
  blurRadius: 8,
  offset: const Offset(0, 2),
);
