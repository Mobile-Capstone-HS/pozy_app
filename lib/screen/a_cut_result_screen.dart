import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../firebase/history_service.dart';

import '../feature/a_cut/layer/evaluation/photo_evaluation_service.dart';
import '../feature/a_cut/layer/scoring/image_scoring_service.dart';
import '../feature/a_cut/model/multi_photo_ranking_result.dart';
import '../feature/a_cut/model/photo_evaluation_result.dart';
import '../feature/a_cut/model/photo_type_mode.dart';
import '../feature/a_cut/model/scored_photo_result.dart';
import '../services/gemini_photo_explanation_services.dart';
import '../services/photo_explanation_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

class _AcutExplanationState {
  const _AcutExplanationState({this.loading = false, this.result, this.error});

  final bool loading;
  final PhotoExplanationResult? result;
  final String? error;
}

class ACutResultScreen extends StatefulWidget {
  final List<AssetEntity> selectedAssets;

  const ACutResultScreen({super.key, required this.selectedAssets});

  @override
  State<ACutResultScreen> createState() => _ACutResultScreenState();
}

class _ACutResultScreenState extends State<ACutResultScreen> {
  static const double _defaultTopPercent = 0.2;
  static const PhotoTypeMode _defaultPhotoTypeMode = PhotoTypeMode.auto;

  final ImageScoreService _scoreService = OnDeviceImageScoreService(
    evaluationService: OnDevicePhotoEvaluationService(),
  );
  final PhotoExplanationService _explanationService =
      GeminiImageScoresPhotoExplanationService();

  MultiPhotoRankingResult _ranking = const MultiPhotoRankingResult.empty();
  final Map<String, _AcutExplanationState> _explanationCache = {};

  bool _isScoring = false;
  int _doneCount = 0;
  int _totalCount = 0;
  int _jobToken = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('[AcutPerf] bestcut_mode=default');
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
      _explanationCache.clear();
    });

    await _scoreService.scoreAssets(
      assets: widget.selectedAssets,
      photoTypeMode: _defaultPhotoTypeMode,
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

    HistoryService.instance.saveACut(
      ranking: _ranking,
      mode: _defaultPhotoTypeMode.label,
    );
  }

  Future<void> _loadExplanation(ScoredPhotoResult scored) async {
    final evaluation = scored.evaluation;
    if (evaluation == null) return;

    final cached = _explanationCache[scored.asset.id];
    if (cached?.loading == true || cached?.result?.isSuccessful == true) {
      return;
    }

    setState(() {
      _explanationCache[scored.asset.id] = const _AcutExplanationState(
        loading: true,
      );
    });
    debugPrint(
      '[AcutPerf] bestcut_detail_explanation_loading=true file="${scored.fileName}"',
    );

    try {
      final bytes = await scored.asset.originBytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('이미지 파일을 불러오지 못했습니다.');
      }

      final result = await _explanationService.explain(
        PhotoExplanationRequest(
          imageBytes: bytes,
          fileName: scored.fileName,
          technicalScore: evaluation.technicalScore,
          aestheticScore: evaluation.aestheticScore,
          finalAestheticScore: evaluation.finalAestheticScore,
          finalScore: evaluation.finalScore,
          rank: scored.rank,
          totalCount: _ranking.successCount,
          verdict: evaluation.verdict,
          usesTechnicalScoreAsFinal: evaluation.usesTechnicalScoreAsFinal,
          primaryHint: evaluation.primaryHint,
          qualitySummary: evaluation.qualitySummary,
          selectionLabel: evaluation.acutLabel,
        ),
      );

      debugPrint(
        '[AcutPerf] bestcut_detail_explanation_loading=false file="${scored.fileName}" success=${result.isSuccessful}',
      );
      if (!mounted) return;
      setState(() {
        _explanationCache[scored.asset.id] = result.isSuccessful
            ? _AcutExplanationState(result: result)
            : _AcutExplanationState(error: result.error ?? '설명을 생성하지 못했습니다.');
      });
    } catch (error) {
      debugPrint(
        '[AcutPerf] bestcut_detail_explanation_loading=false file="${scored.fileName}" success=false',
      );
      if (!mounted) return;
      setState(() {
        _explanationCache[scored.asset.id] = _AcutExplanationState(
          error: error.toString(),
        );
      });
    }
  }

  Future<void> _requestDetailExplanation(ScoredPhotoResult scored) async {
    debugPrint(
      '[AcutPerf] bestcut_detail_explanation_requested file="${scored.fileName}"',
    );
    await _loadExplanation(scored);
  }

  List<ScoredPhotoResult> _resultsForCategory(String category) {
    return _ranking.rankedItems
        .where((result) => result.acutLabel == category)
        .toList(growable: false);
  }

  void _openImageViewer(ScoredPhotoResult result) {
    final category = result.acutLabel;
    debugPrint(
      '[AcutPerf] bestcut_image_view_open category=$category file="${result.fileName}"',
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          return StatefulBuilder(
            builder: (context, setViewerState) {
              return _BestCutImageViewer(
                result: result,
                explanationState: _explanationCache[result.asset.id],
                onRequestDetail: result.status == ScoreStatus.success
                    ? () async {
                        final future = _requestDetailExplanation(result);
                        setViewerState(() {});
                        await future;
                        if (context.mounted) {
                          setViewerState(() {});
                        }
                      }
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  void _returnToBestCutMain() {
    var popCount = 0;
    Navigator.of(context).popUntil((route) => popCount++ >= 2);
  }

  @override
  Widget build(BuildContext context) {
    final completed = _totalCount > 0
        ? (_doneCount / _totalCount).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final showInitialLoading =
        _ranking.items.isEmpty &&
        _isScoring &&
        widget.selectedAssets.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: 'A컷 추천',
                leadingIcon: Icons.home_rounded,
                onLeadingTap: _returnToBestCutMain,
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
                      description:
                          'BEST와 Top 3를 먼저 보여드릴 수 있도록 사진을 순위 중심으로 정리하고 있어요.',
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
                        ),
                        if (_ranking.failureCount > 0 ||
                            _ranking.pendingCount > 0) ...[
                          const SizedBox(height: 18),
                          _RankingNoticeCard(ranking: _ranking),
                        ],
                        const SizedBox(height: 22),
                        _BestCutSectionGrid(
                          title: '추천',
                          results: _resultsForCategory('추천'),
                          onTap: _openImageViewer,
                        ),
                        const SizedBox(height: 30),
                        _BestCutSectionGrid(
                          title: '아쉬움',
                          results: _resultsForCategory('아쉬움'),
                          onTap: _openImageViewer,
                        ),
                        const SizedBox(height: 30),
                        _BestCutSectionGrid(
                          title: '탈락',
                          results: _resultsForCategory('탈락'),
                          onTap: _openImageViewer,
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

  const _SummaryHeader({required this.ranking, required this.totalSelected});

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
          Text(
            ranking.displayTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryText,
            ),
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

  const _SummaryStatChip({required this.label, required this.value});

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

Color _categoryColor(String category) {
  return switch (category) {
    '추천' => const Color(0xFF0F766E),
    '아쉬움' => const Color(0xFFB45309),
    '탈락' => const Color(0xFF64748B),
    _ => AppColors.primaryText,
  };
}

class _BestCutSectionGrid extends StatelessWidget {
  final String title;
  final List<ScoredPhotoResult> results;
  final ValueChanged<ScoredPhotoResult> onTap;

  const _BestCutSectionGrid({
    required this.title,
    required this.results,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final count = results.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count장',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (results.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppShadows.card,
            ),
            child: Text(
              '$title 결과가 없어요.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.secondaryText,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, index) {
              final result = results[index];
              return _BestCutThumbnailTile(
                result: result,
                category: title,
                onTap: () => onTap(result),
              );
            },
          ),
      ],
    );
  }
}

class _BestCutThumbnailTile extends StatelessWidget {
  final ScoredPhotoResult result;
  final String category;
  final VoidCallback onTap;

  const _BestCutThumbnailTile({
    required this.result,
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: result.asset.thumbnailDataWithSize(
                      const ThumbnailSize(420, 420),
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
                  Positioned(
                    left: 7,
                    top: 7,
                    child: _RankBadge(result: result),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            result.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            category,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _categoryColor(category),
            ),
          ),
        ],
      ),
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

class _BestCutImageViewer extends StatefulWidget {
  final ScoredPhotoResult result;
  final _AcutExplanationState? explanationState;
  final Future<void> Function()? onRequestDetail;

  const _BestCutImageViewer({
    required this.result,
    this.explanationState,
    this.onRequestDetail,
  });

  @override
  State<_BestCutImageViewer> createState() => _BestCutImageViewerState();
}

class _BestCutImageViewerState extends State<_BestCutImageViewer> {
  late Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = widget.result.asset.originBytes;
  }

  @override
  void didUpdateWidget(covariant _BestCutImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.asset.id != widget.result.asset.id) {
      _imageFuture = widget.result.asset.originBytes;
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final evaluation = result.evaluation!;
    final current = widget.explanationState;
    final explanation = current?.result;
    final loading = current?.loading == true;
    final error = current?.error;
    final detailedReason = explanation?.detailedReason.trim() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.primaryText,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      result.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Uint8List?>(
                future: _imageFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryText,
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
                            color: AppColors.lightText,
                            size: 42,
                          ),
                          SizedBox(height: 12),
                          Text(
                            '사진을 불러오지 못했어요.',
                            style: TextStyle(
                              color: AppColors.secondaryText,
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
            _BestCutImageDetailPanel(
              result: result,
              evaluation: evaluation,
              loading: loading,
              explanationLoaded: explanation != null && error == null,
              detailedReason: detailedReason,
              error: error,
              onRequestDetail: widget.onRequestDetail,
            ),
          ],
        ),
      ),
    );
  }
}

class _BestCutImageDetailPanel extends StatelessWidget {
  final ScoredPhotoResult result;
  final PhotoEvaluationResult evaluation;
  final bool loading;
  final bool explanationLoaded;
  final String detailedReason;
  final String? error;
  final Future<void> Function()? onRequestDetail;

  const _BestCutImageDetailPanel({
    required this.result,
    required this.evaluation,
    required this.loading,
    required this.explanationLoaded,
    required this.detailedReason,
    required this.error,
    this.onRequestDetail,
  });

  @override
  Widget build(BuildContext context) {
    final maxPanelHeight = MediaQuery.sizeOf(context).height * 0.46;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxPanelHeight),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HighlightPill(
                    label: evaluation.acutLabel,
                    background: _categoryColor(evaluation.acutLabel),
                    foreground: Colors.white,
                  ),
                  _HighlightPill(
                    label: '종합 ${evaluation.finalPct}점',
                    background: AppColors.soft,
                    foreground: AppColors.primaryText,
                  ),
                  _HighlightPill(
                    label: result.rankLabel,
                    background: AppColors.soft,
                    foreground: AppColors.primaryText,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ScoreSummaryRow(
                label: '기술적 점수',
                pct: evaluation.technicalPct,
                color: const Color(0xFF60A5FA),
              ),
              const SizedBox(height: 10),
              _ScoreSummaryRow(
                label: '미적 점수',
                pct: evaluation.aestheticPct,
                color: const Color(0xFFA78BFA),
              ),
              const SizedBox(height: 16),
              _DetailExplanationButton(
                loading: loading,
                hasLoadedExplanation: explanationLoaded,
                hasError: error != null,
                onPressed: onRequestDetail,
              ),
              if (detailedReason.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    detailedReason,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreSummaryRow extends StatelessWidget {
  final String label;
  final int? pct;
  final Color color;

  const _ScoreSummaryRow({
    required this.label,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final value = pct;
    final widthFactor = value == null
        ? 0.0
        : (value / 100).clamp(0.0, 1.0).toDouble();

    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.track,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 42,
          child: Text(
            value == null ? '-' : '$value점',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailExplanationButton extends StatelessWidget {
  final bool loading;
  final bool hasLoadedExplanation;
  final bool hasError;
  final Future<void> Function()? onPressed;

  const _DetailExplanationButton({
    required this.loading,
    required this.hasLoadedExplanation,
    required this.hasError,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton(
        onPressed: loading || hasLoadedExplanation ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.buttonDark,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.track,
          disabledForegroundColor: AppColors.secondaryText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        child: loading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('상세 설명 생성 중...'),
                ],
              )
            : Text(
                hasError
                    ? '상세 설명 다시 시도'
                    : hasLoadedExplanation
                    ? '상세 설명 완료'
                    : '상세 설명 보기',
              ),
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
