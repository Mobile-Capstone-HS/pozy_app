import 'dart:async';
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
  static const ThumbnailSize _detailExplanationImageSize = ThumbnailSize(
    384,
    384,
  );

  final ImageScoreService _scoreService = OnDeviceImageScoreService(
    evaluationService: OnDevicePhotoEvaluationService(),
  );
  final PhotoExplanationService _explanationService =
      GeminiImageScoresPhotoExplanationService();

  MultiPhotoRankingResult _ranking = const MultiPhotoRankingResult.empty();
  final Map<String, _AcutExplanationState> _explanationCache = {};

  bool _isScoring = false;
  bool _isSavingHistory = false;
  bool _isHistorySaved = false;
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
        _isSavingHistory = false;
        _isHistorySaved = false;
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
      _isSavingHistory = false;
      _isHistorySaved = false;
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
  }

  bool get _canSaveHistory =>
      !_isScoring &&
      !_isSavingHistory &&
      !_isHistorySaved &&
      _ranking.successCount > 0;

  Future<void> _saveCurrentHistory() async {
    if (!_canSaveHistory) return;
    setState(() {
      _isSavingHistory = true;
    });

    try {
      await HistoryService.instance.saveACut(ranking: _ranking);
      if (!mounted) return;
      setState(() {
        _isHistorySaved = true;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기록 저장에 실패했어요. 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingHistory = false;
        });
      }
    }
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

    try {
      final bytes = await scored.asset.thumbnailDataWithSize(
        _detailExplanationImageSize,
      );
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

      if (!mounted) return;
      setState(() {
        _explanationCache[scored.asset.id] = result.isSuccessful
            ? _AcutExplanationState(result: result)
            : _AcutExplanationState(error: result.error ?? '설명을 생성하지 못했습니다.');
      });
    } catch (error) {
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

  ScoredPhotoResult get _primarySingleResult {
    return _ranking.bestShot ??
        (_ranking.rankedItems.isNotEmpty
            ? _ranking.rankedItems.first
            : _ranking.items.first);
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
                title: '',
                leadingIcon: Icons.home_rounded,
                onLeadingTap: _returnToBestCutMain,
                trailingWidth: 96,
                trailing: _HistorySaveButton(
                  enabled: _canSaveHistory,
                  saving: _isSavingHistory,
                  saved: _isHistorySaved,
                  onTap: _saveCurrentHistory,
                ),
              ),
            ),
            if (_isScoring) ...[
              const SizedBox(height: 8),
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
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 4),
            Expanded(child: _buildResultBody(showInitialLoading)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultBody(bool showInitialLoading) {
    if (widget.selectedAssets.isEmpty) {
      return const _RankingStateCard(
        icon: Icons.photo_library_outlined,
        title: '선택된 사진이 없어요',
        description: '갤러리에서 사진을 2장 이상 선택하면 베스트컷 랭킹을 볼 수 있어요.',
      );
    }
    if (showInitialLoading || _isScoring) {
      return _RankingStateCard(
        icon: Icons.auto_awesome_rounded,
        title: widget.selectedAssets.length == 1
            ? '사진을 분석하는 중이에요'
            : '추천 순위를 준비하는 중이에요',
        description: widget.selectedAssets.length == 1
            ? '구도, 노출, 선명도, 분위기 점수를 정리하고 있어요.'
            : 'BEST와 추천 후보를 먼저 보여드릴 수 있도록 사진을 순위 중심으로 정리하고 있어요.',
        loading: true,
      );
    }
    if (_ranking.items.isEmpty) {
      return const _RankingStateCard(
        icon: Icons.content_cut_rounded,
        title: '표시할 랭킹이 아직 없어요',
        description: '다시 시도하면 베스트컷 추천 결과를 만들 수 있어요.',
      );
    }
    if (widget.selectedAssets.length == 1) {
      final result = _primarySingleResult;
      return _SinglePhotoResultContent(
        result: result,
        explanationState: _explanationCache[result.asset.id],
        onRequestAi: result.status == ScoreStatus.success
            ? () => _requestDetailExplanation(result)
            : null,
      );
    }
    return _BestCutResultContent(ranking: _ranking, onTap: _openImageViewer);
  }
}

class _BestCutResultContent extends StatelessWidget {
  final MultiPhotoRankingResult ranking;
  final ValueChanged<ScoredPhotoResult> onTap;

  const _BestCutResultContent({required this.ranking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final best = ranking.bestShot;
    final bestId = best?.asset.id;
    final recommended = ranking.recommendedPicks
        .where((result) => result.asset.id != bestId)
        .toList(growable: false);
    final fallbackCandidates = ranking.topPicks
        .where((result) => result.asset.id != bestId)
        .toList(growable: false);
    final candidateResults = recommended.isNotEmpty
        ? recommended
        : fallbackCandidates;
    final candidateIds = {
      ?bestId,
      for (final result in candidateResults) result.asset.id,
    };
    final missedResults = ranking.rankedItems
        .where(
          (result) =>
              result.acutLabel == '아쉬움' &&
              !candidateIds.contains(result.asset.id),
        )
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      children: [
        _SummaryHeader(ranking: ranking),
        if (best != null) ...[
          const SizedBox(height: 10),
          _BestCutLeadCard(result: best, onTap: () => onTap(best)),
        ],
        if (ranking.failureCount > 0 || ranking.pendingCount > 0) ...[
          const SizedBox(height: 12),
          _RankingNoticeCard(ranking: ranking),
        ],
        const SizedBox(height: 16),
        _CandidateGridSection(
          title: '추천 후보',
          results: candidateResults,
          onTap: onTap,
        ),
        const SizedBox(height: 20),
        _CompactResultGridSection(
          title: '아쉬운 컷',
          results: missedResults,
          onTap: onTap,
        ),
      ],
    );
  }
}

class _SinglePhotoResultContent extends StatelessWidget {
  final ScoredPhotoResult result;
  final _AcutExplanationState? explanationState;
  final VoidCallback? onRequestAi;

  const _SinglePhotoResultContent({
    required this.result,
    required this.explanationState,
    required this.onRequestAi,
  });

  @override
  Widget build(BuildContext context) {
    final evaluation = result.evaluation;
    if (evaluation == null) {
      final failed = result.status == ScoreStatus.failed;
      return _RankingStateCard(
        icon: Icons.error_outline_rounded,
        title: failed ? '사진 분석에 실패했어요' : '분석 결과를 준비하지 못했어요',
        description: result.errorMessage ?? '사진을 다시 선택해서 분석해 보세요.',
      );
    }

    final aiAnalysis = _formatAiAnalysis(explanationState?.result);
    final error = explanationState?.error;
    final loading = explanationState?.loading == true;
    final metrics = _SingleMetricData.fromEvaluation(evaluation);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
      children: [
        const _SingleSummaryHeader(),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 1.35,
            child: FutureBuilder<Uint8List?>(
              future: result.asset.thumbnailDataWithSize(
                const ThumbnailSize(1100, 1100),
              ),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return Container(
                    color: const Color(0xFFEDEFF3),
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.lightText,
                    ),
                  );
                }
                return Image.memory(bytes, fit: BoxFit.cover);
              },
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          result.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '분석 점수 결과',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 14),
              for (final metric in metrics) ...[
                _SingleScoreBar(metric: metric),
                if (metric != metrics.last) const SizedBox(height: 13),
              ],
            ],
          ),
        ),
        if (aiAnalysis.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F6FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD8E9FF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy_rounded,
                      size: 16,
                      color: Color(0xFF1B5FD1),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Pozy AI 한줄평',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B5FD1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  aiAnalysis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 14),
          Text(
            error,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB42318),
            ),
          ),
        ],
        if (aiAnalysis.isEmpty) ...[
          const SizedBox(height: 14),
          _AiAnalysisButton(loading: loading, onPressed: onRequestAi),
        ],
      ],
    );
  }
}

String _formatAiAnalysis(PhotoExplanationResult? result) {
  if (result == null || !result.isSuccessful) return '';
  final detailed = result.detailedReason.trim();
  final short = result.shortReason.trim();
  final source = detailed.isNotEmpty ? detailed : short;
  if (source.isEmpty) return '';

  final sentences = source
      .split(RegExp(r'(?:\.\s+|\n+)'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .take(5)
      .toList();
  if (sentences.length <= 1) return source;
  return sentences.map((line) => '• $line').join('\n');
}

class _SingleMetricData {
  final String label;
  final double value;
  final Color color;

  const _SingleMetricData({
    required this.label,
    required this.value,
    required this.color,
  });

  static List<_SingleMetricData> fromEvaluation(
    PhotoEvaluationResult evaluation,
  ) {
    final aestheticScore =
        evaluation.finalAestheticScore ?? evaluation.aestheticScore;
    final technical = evaluation.technicalScore.clamp(0.0, 1.0).toDouble();
    final aesthetic = aestheticScore?.clamp(0.0, 1.0).toDouble();

    return [
      _SingleMetricData(
        label: '종합',
        value: evaluation.finalScore.clamp(0.0, 1.0).toDouble(),
        color: const Color(0xFF3182F6),
      ),
      _SingleMetricData(
        label: '기술',
        value: technical,
        color: const Color(0xFF14B8A6),
      ),
      if (aesthetic != null)
        _SingleMetricData(
          label: '미적',
          value: aesthetic,
          color: const Color(0xFFF59E0B),
        ),
    ];
  }
}

class _SingleSummaryHeader extends StatelessWidget {
  const _SingleSummaryHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5BA8FB), Color(0xFF1B5FD1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3182F6).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'Pozy 분석 결과',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '선택한 사진의 분석 결과를 한 눈에 확인해보세요.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiAnalysisButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onPressed;

  const _AiAnalysisButton({required this.loading, required this.onPressed});

  static const _loadingMessages = [
    'Pozy AI가 분석하고 있어요',
    '사진 속 요소를 확인하고 있어요',
    '조금만 기다려주세요',
    '최대 30초까지 걸릴 수 있어요',
  ];

  @override
  Widget build(BuildContext context) {
    return _AnimatedAiAnalysisButton(loading: loading, onPressed: onPressed);
  }
}

class _HistorySaveButton extends StatelessWidget {
  final bool enabled;
  final bool saving;
  final bool saved;
  final VoidCallback onTap;

  const _HistorySaveButton({
    required this.enabled,
    required this.saving,
    required this.saved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = saved
        ? const Color(0xFF3182F6)
        : enabled
        ? AppColors.primaryText
        : AppColors.lightText;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (saving)
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF3182F6),
              ),
            )
          else if (saved)
            const Icon(
              Icons.check_circle_rounded,
              size: 15,
              color: Color(0xFF3182F6),
            ),
          if (saving || saved) const SizedBox(width: 4),
          Text(
            saving
                ? '저장 중'
                : saved
                ? '저장됨'
                : '결과 저장',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedAiAnalysisButton extends StatefulWidget {
  final bool loading;
  final VoidCallback? onPressed;

  const _AnimatedAiAnalysisButton({
    required this.loading,
    required this.onPressed,
  });

  @override
  State<_AnimatedAiAnalysisButton> createState() =>
      _AnimatedAiAnalysisButtonState();
}

class _AnimatedAiAnalysisButtonState extends State<_AnimatedAiAnalysisButton> {
  Timer? _timer;
  int _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _AnimatedAiAnalysisButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) {
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (!widget.loading) {
      _messageIndex = 0;
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        _messageIndex =
            (_messageIndex + 1) % _AiAnalysisButton._loadingMessages.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading || widget.onPressed == null;
    final label = widget.loading
        ? _AiAnalysisButton._loadingMessages[_messageIndex]
        : 'Pozy AI 한줄평 보기';
    return Opacity(
      opacity: disabled ? 0.72 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFE8F4FF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: disabled ? null : widget.onPressed,
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF3182F6),
                      ),
                    )
                  else
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: Color(0xFF3182F6),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3182F6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SingleScoreBar extends StatelessWidget {
  final _SingleMetricData metric;

  const _SingleScoreBar({required this.metric});

  @override
  Widget build(BuildContext context) {
    final pct = (metric.value * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            '${metric.label}:',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: metric.value,
              backgroundColor: metric.color.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(metric.color),
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
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  final MultiPhotoRankingResult ranking;

  const _SummaryHeader({required this.ranking});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5BA8FB), Color(0xFF1B5FD1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3182F6).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 17,
              ),
              const SizedBox(width: 8),
              const Text(
                'Pozy 분석 결과',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ranking.displaySummary,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 4), // 간격을 6에서 4로 줄여 더 밀착시킴
          Text(
            '상세 분석 보기를 통해 자세한 분석 결과를 확인해 보세요.',
            style: TextStyle(
              fontSize: 12, // 요약 텍스트와 동일하게 12로 변경
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.76),
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

class _BestCutLeadCard extends StatelessWidget {
  final ScoredPhotoResult result;
  final VoidCallback onTap;

  const _BestCutLeadCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: double.infinity,
              height: 190,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: result.asset.thumbnailDataWithSize(
                      const ThumbnailSize(760, 760),
                    ),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return Container(
                          color: const Color(0xFFEDEFF3),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.lightText,
                            size: 28,
                          ),
                        );
                      }
                      return Image.memory(bytes, fit: BoxFit.cover);
                    },
                  ),
                  const Positioned(
                    left: 10,
                    top: 10,
                    child: _ResultBadge(label: '#1'),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    result.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const _DetailPill(compact: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  final bool compact;

  const _DetailPill({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.fromLTRB(9, 0, 7, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '상세 분석 보기',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3182F6),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.chevron_right_rounded,
            size: 15,
            color: Color(0xFF3182F6),
          ),
        ],
      ),
    );
  }
}

class _CandidateGridSection extends StatelessWidget {
  final String title;
  final List<ScoredPhotoResult> results;
  final ValueChanged<ScoredPhotoResult> onTap;

  const _CandidateGridSection({
    required this.title,
    required this.results,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return _EmptyResultSection(title: title);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, count: results.length),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 12,
            childAspectRatio: 0.88,
          ),
          itemBuilder: (context, index) {
            final result = results[index];
            return _ResultPhotoCard(
              result: result,
              imageSize: const ThumbnailSize(560, 560),
              onTap: () => onTap(result),
            );
          },
        ),
      ],
    );
  }
}

class _CompactResultGridSection extends StatelessWidget {
  final String title;
  final List<ScoredPhotoResult> results;
  final ValueChanged<ScoredPhotoResult> onTap;

  const _CompactResultGridSection({
    required this.title,
    required this.results,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return _EmptyResultSection(title: title);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, count: results.length),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 9,
            mainAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, index) {
            final result = results[index];
            return _ResultPhotoCard(
              result: result,
              imageSize: const ThumbnailSize(420, 420),
              compact: true,
              onTap: () => onTap(result),
            );
          },
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count장',
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

class _ResultPhotoCard extends StatelessWidget {
  final ScoredPhotoResult result;
  final ThumbnailSize imageSize;
  final VoidCallback onTap;
  final bool compact;

  const _ResultPhotoCard({
    required this.result,
    required this.imageSize,
    required this.onTap,
    this.compact = false,
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
                    future: result.asset.thumbnailDataWithSize(imageSize),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return Container(
                          color: const Color(0xFFEDEFF3),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.lightText,
                          ),
                        );
                      }
                      return Image.memory(bytes, fit: BoxFit.cover);
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
          const SizedBox(height: 7),
          Text(
            result.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          _DetailPill(compact: compact),
        ],
      ),
    );
  }
}

class _EmptyResultSection extends StatelessWidget {
  final String title;

  const _EmptyResultSection({required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, count: 0),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8ECF3)),
          ),
          child: Text(
            '$title 결과가 없어요.',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final String label;

  const _ResultBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3BF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFE08A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEAB308).withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7A5B00),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
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
                fontWeight: FontWeight.w800,
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

class _BestCutImageViewer extends StatelessWidget {
  final ScoredPhotoResult result;
  final _AcutExplanationState? explanationState;
  final Future<void> Function()? onRequestDetail;

  const _BestCutImageViewer({
    required this.result,
    this.explanationState,
    this.onRequestDetail,
  });

  @override
  Widget build(BuildContext context) {
    final evaluation = result.evaluation!;
    final current = explanationState;
    final loading = current?.loading == true;
    final error = current?.error;
    final aiAnalysis = _formatAiAnalysis(current?.result);
    final metrics = _SingleMetricData.fromEvaluation(evaluation);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AspectRatio(
                        aspectRatio: 1.35,
                        child: FutureBuilder<Uint8List?>(
                          future: result.asset.thumbnailDataWithSize(
                            const ThumbnailSize(1100, 1100),
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
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      result.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: AppShadows.card,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '분석 점수 결과',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryText,
                            ),
                          ),
                          const SizedBox(height: 14),
                          for (final metric in metrics) ...[
                            _SingleScoreBar(metric: metric),
                            if (metric != metrics.last)
                              const SizedBox(height: 13),
                          ],
                        ],
                      ),
                    ),
                    if (aiAnalysis.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F6FF),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFD8E9FF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.smart_toy_rounded,
                                  size: 16,
                                  color: Color(0xFF1B5FD1),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Pozy AI 한줄평',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1B5FD1),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              aiAnalysis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.55,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        error,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB42318),
                        ),
                      ),
                    ],
                    if (aiAnalysis.isEmpty) ...[
                      const SizedBox(height: 14),
                      _AiAnalysisButton(
                        loading: loading,
                        onPressed: onRequestDetail,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
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
    if (result.status == ScoreStatus.failed) return '?ㅽ뙣';
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
