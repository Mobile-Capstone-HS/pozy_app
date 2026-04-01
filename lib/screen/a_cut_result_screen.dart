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

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: 'A컷 결과',
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
              child: _ranking.items.isEmpty
                  ? const Center(
                      child: Text('선택된 사진이 없습니다.', style: AppTextStyles.body14),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                      children: [
                        _SummaryHeader(
                          ranking: _ranking,
                          totalSelected: widget.selectedAssets.length,
                        ),
                        if (_ranking.bestShot != null) ...[
                          const SizedBox(height: 14),
                          _BestShotHighlight(
                            result: _ranking.bestShot!,
                            onTap: () => _openDetail(context, _ranking.bestShot!),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const Text(
                          '전체 결과',
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

  const _SummaryHeader({
    required this.ranking,
    required this.totalSelected,
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
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '온디바이스 A컷 랭킹',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'KonIQ + FLIVE-image 점수로 베스트 샷을 정렬했습니다.',
                  style: AppTextStyles.body13,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'A컷 ${ranking.aCutCount}장',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$totalSelected장 중 ${ranking.successCount}장 분석 완료',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
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
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              child: AspectRatio(
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
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryText,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'BEST SHOT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '#${result.rank}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    result.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '종합 ${evaluation.finalPct}점 · 기술 ${evaluation.technicalPct}점',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
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

class _ResultCard extends StatelessWidget {
  final ScoredPhotoResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final isSuccess = result.status == ScoreStatus.success;
    final isFailed = result.status == ScoreStatus.failed;
    final evaluation = result.evaluation;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 84,
              height: 84,
              child: FutureBuilder<Uint8List?>(
                future: result.asset.thumbnailDataWithSize(
                  const ThumbnailSize(280, 280),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        result.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    if (result.isBestShot) ...[
                      _Pill(
                        label: 'BEST',
                        background: const Color(0xFF0F172A),
                        foreground: Colors.white,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (result.isACut)
                      const _Pill(
                        label: 'A컷',
                        background: AppColors.primaryText,
                        foreground: Colors.white,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (isSuccess && evaluation != null) ...[
                  Text(
                    '종합 ${evaluation.finalPct}점  |  기술 ${evaluation.technicalPct}점  |  순위 #${result.rank}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    evaluation.scoreDetails
                        .map(
                          (detail) => '${detail.label} ${detail.normalizedPct}점',
                        )
                        .join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
                if (isFailed)
                  Text(
                    '실패: ${result.errorMessage ?? '알 수 없는 오류'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                if (!isSuccess && !isFailed)
                  const Text(
                    '점수 계산 중...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
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
