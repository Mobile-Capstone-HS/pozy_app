import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../feature/a_cut/layer/evaluation/photo_evaluation_service.dart';
import '../feature/a_cut/layer/scoring/image_scoring_service.dart';
import '../feature/a_cut/model/multi_photo_ranking_result.dart';
import '../feature/a_cut/model/photo_evaluation_result.dart';
import '../feature/a_cut/model/photo_type_mode.dart';
import '../feature/a_cut/model/scored_photo_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import 'single_photo_eval_screen.dart';

class ACutResultScreen extends StatefulWidget {
  final List<AssetEntity> selectedAssets;
  final PhotoTypeMode initialPhotoTypeMode;

  const ACutResultScreen({
    super.key,
    required this.selectedAssets,
    required this.initialPhotoTypeMode,
  });

  @override
  State<ACutResultScreen> createState() => _ACutResultScreenState();
}

class _ACutResultScreenState extends State<ACutResultScreen> {
  static const double _defaultTopPercent = 0.2;

  final ImageScoreService _scoreService = OnDeviceImageScoreService();

  MultiPhotoRankingResult _ranking = const MultiPhotoRankingResult.empty();
  PhotoTypeMode _photoTypeMode = PhotoTypeMode.auto;

  bool _isScoring = false;
  int _doneCount = 0;
  int _totalCount = 0;
  int _jobToken = 0;

  @override
  void initState() {
    super.initState();
    _photoTypeMode = widget.initialPhotoTypeMode;
    _startScoring();
  }

  Future<void> _startScoring() async {
    if (widget.selectedAssets.isEmpty) {
      setState(() {
        _isScoring = false;
        _ranking = const MultiPhotoRankingResult.empty();
        _doneCount = 0;
        _totalCount = 0;
      });
      return;
    }

    final currentToken = ++_jobToken;

    setState(() {
      _isScoring = true;
      _doneCount = 0;
      _totalCount = widget.selectedAssets.length;
      _ranking = const MultiPhotoRankingResult.empty();
    });

    await _scoreService.scoreAssets(
      assets: widget.selectedAssets,
      photoTypeMode: _photoTypeMode,
      topPercent: _defaultTopPercent,
      onProgress: (snapshot, done, total) {
        if (!mounted || currentToken != _jobToken) {
          return;
        }
        setState(() {
          _ranking = snapshot;
          _doneCount = done;
          _totalCount = total;
          _isScoring = done < total;
        });
      },
    );

    if (!mounted || currentToken != _jobToken) {
      return;
    }

    setState(() {
      _isScoring = false;
    });
  }

  Future<void> _openDetail(
    BuildContext context,
    ScoredPhotoResult scored,
  ) async {
    if (scored.evaluation == null) return;

    final bytes = await scored.asset.originBytes;
    if (bytes == null || !context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SinglePhotoEvalScreen(
          imageBytes: bytes,
          fileName: scored.fileName,
          evaluationService: _PrecomputedEvalService(scored.evaluation!),
        ),
      ),
    );
  }

  void _changeType(PhotoTypeMode mode) {
    if (_photoTypeMode == mode || _isScoring) {
      return;
    }
    setState(() {
      _photoTypeMode = mode;
    });
    _startScoring();
  }

  @override
  Widget build(BuildContext context) {
    final completed = _totalCount > 0
        ? (_doneCount / _totalCount).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final showInitialLoading =
        _ranking.items.isEmpty && _isScoring && widget.selectedAssets.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: 'A컷 추천',
                onBack: () => Navigator.of(context).pop(),
                trailingWidth: 90,
                trailing: GestureDetector(
                  onTap: _isScoring ? null : _startScoring,
                  child: Text(
                    '재분석',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _isScoring
                          ? AppColors.lightText
                          : AppColors.primaryText,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _PhotoTypeRow(selected: _photoTypeMode, onSelected: _changeType),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '분석 진행: $_doneCount/$_totalCount',
                        style: AppTextStyles.body13,
                      ),
                      const Spacer(),
                      Text(
                        '${(completed * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: completed,
                      backgroundColor: AppColors.track,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: widget.selectedAssets.isEmpty
                  ? const _RankingStateCard(
                      icon: Icons.photo_library_outlined,
                      title: '선택된 사진이 없어요',
                      description: '갤러리에서 사진을 2장 이상 선택하면 A컷 랭킹을 볼 수 있어요.',
                    )
                  : showInitialLoading
                      ? const _RankingStateCard(
                          icon: Icons.auto_awesome_rounded,
                          title: '추천 순위를 준비하는 중이에요',
                          description: 'BEST와 Top 3를 먼저 보여드릴 수 있도록 사진을 순위 중심으로 정리하고 있어요.',
                          loading: true,
                        )
                      : _ranking.items.isEmpty
                          ? const _RankingStateCard(
                              icon: Icons.content_cut_rounded,
                              title: '표시할 랭킹이 아직 없어요',
                              description: '다시 시도하면 A컷 추천 결과를 만들 수 있어요.',
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                              children: [
                                _SummaryHeader(
                                  ranking: _ranking,
                                  totalSelected: widget.selectedAssets.length,
                                  photoTypeMode: _photoTypeMode,
                                ),
                                if (_ranking.bestShot != null) ...[
                                  const SizedBox(height: 14),
                                  _BestShotHighlight(
                                    result: _ranking.bestShot!,
                                    onTap: () => _openDetail(
                                      context,
                                      _ranking.bestShot!,
                                    ),
                                  ),
                                ],
                                if (_ranking.topPicks.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  _TopPickSection(
                                    picks: _ranking.topPicks,
                                    onTap: (result) => _openDetail(context, result),
                                  ),
                                ],
                                if (_ranking.failureCount > 0 ||
                                    _ranking.pendingCount > 0) ...[
                                  const SizedBox(height: 18),
                                  _RankingNoticeCard(ranking: _ranking),
                                ],
                                const SizedBox(height: 18),
                                const Text(
                                  '전체 순위',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryText,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ..._ranking.items.map(
                                  (result) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: GestureDetector(
                                      onTap: result.status == ScoreStatus.success
                                          ? () => _openDetail(context, result)
                                          : null,
                                      child: _ResultCard(result: result),
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

class _SummaryHeader extends StatelessWidget {
  final MultiPhotoRankingResult ranking;
  final int totalSelected;
  final PhotoTypeMode photoTypeMode;

  const _SummaryHeader({
    required this.ranking,
    required this.totalSelected,
    required this.photoTypeMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ranking.displayTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              _ModeBadge(label: photoTypeMode.label),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ranking.displaySummary,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryStatChip(
                label: 'BEST',
                value: ranking.bestShot == null ? '-' : '#1',
              ),
              _SummaryStatChip(
                label: 'Top 3',
                value: '${ranking.topPicks.length}장',
              ),
              _SummaryStatChip(
                label: '추천 컷',
                value: '${ranking.recommendedPicks.length}장',
              ),
              _SummaryStatChip(
                label: '분석 완료',
                value: '${ranking.successCount}/$totalSelected',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            ranking.displaySource,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.lightText,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStatChip extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryStatChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _BestShotHighlight extends StatelessWidget {
  final ScoredPhotoResult result;
  final VoidCallback onTap;

  const _BestShotHighlight({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final evaluation = result.evaluation!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFFACC15), width: 1.5),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: FutureBuilder<Uint8List?>(
                      future: result.asset.thumbnailDataWithSize(
                        const ThumbnailSize(720, 720),
                      ),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data == null) {
                          return Container(
                            color: const Color(0xFFEDEFF3),
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.lightText,
                              size: 36,
                            ),
                          );
                        }
                        return Image.memory(snapshot.data!, fit: BoxFit.cover);
                      },
                    ),
                  ),
                  const Positioned(
                    left: 16,
                    top: 16,
                    child: _HighlightPill(
                      label: 'BEST PICK',
                      background: Color(0xFF111827),
                      foreground: Colors.white,
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 16,
                    child: _HighlightPill(
                      label: result.rankLabel,
                      background: Colors.white,
                      foreground: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '가장 먼저 확인할 추천 컷',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFCA8A04),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    evaluation.primaryHint,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HighlightPill(
                        label: '종합 ${evaluation.finalPct}점',
                        background: const Color(0xFF111827),
                        foreground: Colors.white,
                      ),
                      _HighlightPill(
                        label: evaluation.verdict,
                        background: const Color(0xFFF8FAFC),
                        foreground: AppColors.primaryText,
                      ),
                      _HighlightPill(
                        label: result.recommendationLabel,
                        background: const Color(0xFFFFF7CC),
                        foreground: const Color(0xFF92400E),
                      ),
                    ],
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

class _TopPickSection extends StatelessWidget {
  final List<ScoredPhotoResult> picks;
  final ValueChanged<ScoredPhotoResult> onTap;

  const _TopPickSection({
    required this.picks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top 3 추천 컷',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '상위 추천 컷을 먼저 훑어본 뒤 전체 순위를 확인해 보세요.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 12),
        ...picks.map(
          (result) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => onTap(result),
              child: _ResultCard(result: result, compact: true),
            ),
          ),
        ),
      ],
    );
  }
}

class _RankingNoticeCard extends StatelessWidget {
  final MultiPhotoRankingResult ranking;

  const _RankingNoticeCard({required this.ranking});

  @override
  Widget build(BuildContext context) {
    final messages = <String>[];
    if (ranking.pendingCount > 0) {
      messages.add('아직 분석 중인 사진 ${ranking.pendingCount}장이 있어요.');
    }
    if (ranking.failureCount > 0) {
      messages.add('불러오지 못한 사진 ${ranking.failureCount}장은 순위에서 제외됐어요.');
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: messages
            .map(
              (message) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final ScoredPhotoResult result;
  final bool compact;

  const _ResultCard({
    required this.result,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.status == ScoreStatus.success;
    final isFailed = result.status == ScoreStatus.failed;
    final evaluation = result.evaluation;
    final thumbSize = compact ? 82.0 : 92.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: result.isRecommendedPick
              ? const Color(0xFFE2E8F0)
              : Colors.transparent,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: thumbSize,
                  height: thumbSize,
                  child: FutureBuilder<Uint8List?>(
                    future: result.asset.thumbnailDataWithSize(
                      const ThumbnailSize(320, 320),
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data == null) {
                        return Container(
                          color: const Color(0xFFEDEFF3),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.lightText,
                          ),
                        );
                      }
                      return Image.memory(snapshot.data!, fit: BoxFit.cover);
                    },
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: _RankBadge(result: result),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        result.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HighlightPill(
                      label: result.highlightLabel,
                      background: result.isBestShot
                          ? const Color(0xFF111827)
                          : const Color(0xFFF1F5F9),
                      foreground: result.isBestShot
                          ? Colors.white
                          : AppColors.primaryText,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  result.recommendationLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 4),
                if (isSuccess && evaluation != null) ...[
                  Text(
                    evaluation.primaryHint,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _MetaPill(label: result.rankLabel),
                      _MetaPill(label: evaluation.verdict),
                      if (result.isACut && !result.isTopThree)
                        const _MetaPill(label: 'A컷 후보'),
                      _MetaPill(label: '종합 ${evaluation.finalPct}점'),
                    ],
                  ),
                ],
                if (isFailed)
                  Text(
                    '실패: ${result.errorMessage ?? '알 수 없는 오류'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent,
                    ),
                  ),
                if (!isSuccess && !isFailed)
                  const Text(
                    '추천 순위를 계산 중이에요...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool loading;

  const _RankingStateCard({
    required this.icon,
    required this.title,
    required this.description,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primaryText,
                  ),
                )
              else
                Icon(icon, size: 42, color: AppColors.primaryText),
              if (!loading) const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: AppTextStyles.body13,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _HighlightPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;

  const _MetaPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
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

class _RankBadge extends StatelessWidget {
  final ScoredPhotoResult result;

  const _RankBadge({required this.result});

  Color get _background {
    if (result.isBestShot) return const Color(0xFF111827);
    if (result.isTopThree) return const Color(0xFF2563EB);
    if (result.isACut) return const Color(0xFF0F766E);
    if (result.status == ScoreStatus.failed) return const Color(0xFFDC2626);
    if (result.status == ScoreStatus.pending) return const Color(0xFF64748B);
    return const Color(0xFF334155);
  }

  String get _label {
    if (result.isBestShot) return 'BEST';
    if (result.rank != null) return '${result.rank}위';
    if (result.status == ScoreStatus.failed) return '실패';
    return '대기';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final String label;

  const _ModeBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label 모드',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryText,
        ),
      ),
    );
  }
}

class _PhotoTypeRow extends StatelessWidget {
  final PhotoTypeMode selected;
  final ValueChanged<PhotoTypeMode> onSelected;

  const _PhotoTypeRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: PhotoTypeMode.values.map((mode) {
          final active = selected == mode;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelected(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 38,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFEFEFEF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    child: Text(
                      mode.label,
                      style: TextStyle(
                        color: active ? Colors.white : const Color(0xFF5A5A5A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PrecomputedEvalService implements PhotoEvaluationService {
  final PhotoEvaluationResult _result;

  const _PrecomputedEvalService(this._result);

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
  }) async =>
      _result;
}
