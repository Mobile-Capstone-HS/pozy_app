import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/experimental_features.dart';
import '../feature/a_cut/layer/evaluation/hybrid_photo_evaluation_service.dart';
import '../feature/a_cut/layer/evaluation/photo_evaluation_service.dart';
import '../feature/a_cut/model/model_score_detail.dart';
import '../feature/a_cut/model/photo_evaluation_result.dart';
import '../firebase/history_service.dart';
import 'explanation_backend_debug_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

class SinglePhotoEvalScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String? fileName;
  final String? assetId;
  final PhotoEvaluationService? evaluationService;

  const SinglePhotoEvalScreen({
    super.key,
    required this.imageBytes,
    this.fileName,
    this.assetId,
    this.evaluationService,
  });

  @override
  State<SinglePhotoEvalScreen> createState() => _SinglePhotoEvalScreenState();
}

class _SinglePhotoEvalScreenState extends State<SinglePhotoEvalScreen> {
  late final PhotoEvaluationService _evaluationService;

  PhotoEvaluationResult? _result;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _evaluationService =
        widget.evaluationService ?? HybridPhotoEvaluationService();
    _evaluate();
  }

  Future<void> _evaluate() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final result = await _evaluationService.evaluate(
        widget.imageBytes,
        fileName: widget.fileName,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
      HistoryService.instance.saveSingle(
        result: result,
        assetId: widget.assetId,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedResult = _result;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: '사진 평가',
                onBack: () => Navigator.of(context).pop(),
                trailingWidth: 72,
                trailing: _result != null
                    ? GestureDetector(
                        onTap: _evaluate,
                        child: const Text(
                          '재평가',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryText,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('분석 진행: 0/1', style: AppTextStyles.body13),
                        const Spacer(),
                        const Text(
                          '0%',
                          style: TextStyle(
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
                      child: const LinearProgressIndicator(
                        minHeight: 8,
                        value: null,
                        backgroundColor: AppColors.track,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Expanded(
              child: _loading
                  ? _LoadingView(fileName: widget.fileName)
                  : _errorMessage != null
                  ? _ErrorView(message: _errorMessage!, onRetry: _evaluate)
                  : _ResultView(
                      imageBytes: widget.imageBytes,
                      result: displayedResult!,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String? fileName;

  const _LoadingView({this.fileName});

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
              const CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.primaryText,
              ),
              const SizedBox(height: 16),
              const Text(
                '사진을 평가하는 중이에요',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                fileName ?? 'AI가 구도, 밝기, 미적 완성도를 분석하고 있어요.',
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

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.secondaryText,
            ),
            const SizedBox(height: 14),
            Text('평가를 완료하지 못했어요', style: AppTextStyles.title16),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body13,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonDark,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final Uint8List imageBytes;
  final PhotoEvaluationResult result;

  const _ResultView({required this.imageBytes, required this.result});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.memory(imageBytes, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 18),
          _HeadlineCard(result: result),
          const SizedBox(height: 12),
          _MetricOverviewSection(result: result),
          if (result.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ChipSection(
              icon: Icons.check_circle_rounded,
              color: const Color(0xFF16A34A),
              title: '좋았던 포인트',
              chips: result.notes,
            ),
          ],
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ChipSection(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFF59E0B),
              title: '다음 컷에서 보완하기',
              chips: result.warnings,
            ),
          ],
          if (result.usesTechnicalScoreAsFinal) ...[
            const SizedBox(height: 12),
            const _InfoBanner(
              text: '현재 단일 사진 평가는 온디바이스 품질 결과를 중심으로 간단히 요약해 보여줘요.',
            ),
          ],
          if ((result.shortExplanation?.isNotEmpty ?? false) ||
              (result.detailedExplanation?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 16),
            _ExplanationSection(
              shortText: result.shortExplanation,
              detailedText: result.detailedExplanation,
              comparisonText: result.comparisonExplanation,
              backendLabel: result.explanationBackend,
            ),
          ],
          if (ExperimentalFeatures.enableGemmaExplanationDebug) ...[
            const SizedBox(height: 16),
            _ExplanationDebugEntryCard(imageBytes: imageBytes, result: result),
          ],
          if (result.scoreDetails.isNotEmpty) ...[
            const SizedBox(height: 16),
            _AdvancedDetailSection(details: result.scoreDetails.toList()),
          ],
          const SizedBox(height: 16),
          _AestheticEnsembleDebugSection(result: result),
          if (result.modelVersion != null) ...[
            const SizedBox(height: 18),
            Text(
              '결과 소스: ${result.modelVersion}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.lightText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExplanationDebugEntryCard extends StatelessWidget {
  const _ExplanationDebugEntryCard({
    required this.imageBytes,
    required this.result,
  });

  final Uint8List imageBytes;
  final PhotoEvaluationResult result;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExplanationBackendDebugScreen(
              imageBytes: imageBytes,
              result: result,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.card,
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '실험용 설명 백엔드 비교',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Gemini 텍스트 전용, Gemini 이미지+점수, 온디바이스 Gemma를 같은 사진으로 비교해 볼 수 있어요.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '디버그 화면 열기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: Color(0xFF4F46E5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AestheticEnsembleDebugSection extends StatelessWidget {
  final PhotoEvaluationResult result;

  const _AestheticEnsembleDebugSection({required this.result});

  @override
  Widget build(BuildContext context) {
    final weights = result.effectiveAestheticWeights;
    final finalAestheticScore =
        result.finalAestheticScore ?? result.aestheticScore;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '미적 앙상블 디버그',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'NIMA, RGNet, A-Lamp를 각각 실행한 뒤 정규화된 가중합으로 최종 미적 점수를 계산해요.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          _DebugMetaRow(
            label: '파일',
            value: result.fileName ?? 'selected_image',
          ),
          const SizedBox(height: 6),
          _DebugMetaRow(
            label: '가중치',
            value:
                'NIMA ${weights.nimaWeight.toStringAsFixed(1)} / '
                'RGNet ${weights.rgnetWeight.toStringAsFixed(1)} / '
                'A-Lamp ${weights.alampWeight.toStringAsFixed(1)} '
                '(코드 고정)',
          ),
          if (!result.hasAnyAestheticEnsembleScore) ...[
            const SizedBox(height: 12),
            const _DebugBanner(
              text: '이 결과에는 NIMA/RGNet/A-Lamp 개별 점수가 아직 없습니다.',
            ),
          ] else ...[
            const SizedBox(height: 14),
            if (!result.hasAestheticEnsembleScores) ...[
              const _DebugBanner(
                text:
                    '일부 모델 추론이 실패해서 최종 가중합 점수는 보류되었습니다. 아래에서 개별 성공/실패 상태를 확인할 수 있어요.',
              ),
              const SizedBox(height: 12),
            ],
            _EnsembleScoreRow(
              label: 'NIMA',
              score: result.nimaScore,
              weight: weights.nimaWeight,
              accent: const Color(0xFF2563EB),
            ),
            const SizedBox(height: 12),
            _EnsembleScoreRow(
              label: 'RGNet',
              score: result.rgnetScore,
              weight: weights.rgnetWeight,
              accent: const Color(0xFF0F766E),
            ),
            const SizedBox(height: 12),
            _EnsembleScoreRow(
              label: 'A-Lamp',
              score: result.alampScore,
              weight: weights.alampWeight,
              accent: const Color(0xFF7C3AED),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SummaryMetricCard(
                    label: '최종 미적 점수',
                    value: finalAestheticScore == null
                        ? '-'
                        : finalAestheticScore.toStringAsFixed(4),
                    accent: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SummaryMetricCard(
                    label: '현재 종합 점수',
                    value: result.finalScore.toStringAsFixed(4),
                    accent: const Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EnsembleScoreRow extends StatelessWidget {
  final String label;
  final double? score;
  final double weight;
  final Color accent;

  const _EnsembleScoreRow({
    required this.label,
    required this.score,
    required this.weight,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              Text(
                score == null ? '실패' : score!.toStringAsFixed(4),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            score == null
                ? 'score unavailable · weight ${weight.toStringAsFixed(3)}'
                : '${(score! * 100).round()}/100 · weight ${weight.toStringAsFixed(3)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _SummaryMetricCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugMetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _DebugMetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _DebugBanner extends StatelessWidget {
  final String text;

  const _DebugBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  final PhotoEvaluationResult result;

  const _HeadlineCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '단일 사진 평가',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                    ),
                    if (result.fileName != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        result.fileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body13,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _VerdictBadge(level: result.verdictLevel, label: result.verdict),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            result.verdict,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryText,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '종합 ${result.finalPct}점',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            result.primaryHint,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            result.evaluationModeLabel,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricOverviewSection extends StatelessWidget {
  final PhotoEvaluationResult result;

  const _MetricOverviewSection({required this.result});

  @override
  Widget build(BuildContext context) {
    final metrics = <_MetricInfo>[
      _MetricInfo(
        label: '종합',
        value: result.finalPct,
        caption: '대표 요약 점수',
        accent: const Color(0xFF0F172A),
      ),
      _MetricInfo(
        label: '기술',
        value: result.technicalPct,
        caption: '선명도, 노출, 노이즈',
        accent: const Color(0xFF2563EB),
      ),
      if (result.aestheticPct != null)
        _MetricInfo(
          label: '미적',
          value: result.aestheticPct!,
          caption: '선호도 기반 보조 요약',
          accent: const Color(0xFF7C3AED),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: _MetricCard(info: metric),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MetricInfo {
  final String label;
  final int value;
  final String caption;
  final Color accent;

  const _MetricInfo({
    required this.label,
    required this.value,
    required this.caption,
    required this.accent,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricInfo info;

  const _MetricCard({required this.info});

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
            info.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${info.value}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: info.accent,
                  ),
                ),
                const TextSpan(
                  text: ' /100',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: info.value / 100,
              backgroundColor: AppColors.track,
              valueColor: AlwaysStoppedAnimation<Color>(info.accent),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            info.caption,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;

  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFF475569),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedDetailSection extends StatelessWidget {
  final List<ModelScoreDetail> details;

  const _AdvancedDetailSection({required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Text(
            '세부 모델 점수',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
          subtitle: const Text(
            '필요할 때 펼쳐서 확인하기',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
          children: details
              .map((detail) => _ModelDetailTile(detail: detail))
              .toList(),
        ),
      ),
    );
  }
}

class _ModelDetailTile extends StatelessWidget {
  final ModelScoreDetail detail;

  const _ModelDetailTile({required this.detail});

  Color get _accent {
    switch (detail.dimension) {
      case ModelScoreDimension.technical:
        return const Color(0xFF2563EB);
      case ModelScoreDimension.aesthetic:
        return const Color(0xFF7C3AED);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.memory_rounded, size: 18, color: _accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.interpretation,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${detail.normalizedPct}점',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _accent,
                  ),
                ),
                Text(
                  '가중치 ${(detail.weight * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VerdictBadge extends StatelessWidget {
  final VerdictLevel level;
  final String label;

  const _VerdictBadge({required this.level, required this.label});

  Color get _bg {
    switch (level) {
      case VerdictLevel.excellent:
        return const Color(0xFFDCFCE7);
      case VerdictLevel.good:
        return const Color(0xFFDBEAFE);
      case VerdictLevel.average:
        return const Color(0xFFFEF3C7);
      case VerdictLevel.needsWork:
        return const Color(0xFFFEE2E2);
    }
  }

  Color get _fg {
    switch (level) {
      case VerdictLevel.excellent:
        return const Color(0xFF15803D);
      case VerdictLevel.good:
        return const Color(0xFF1D4ED8);
      case VerdictLevel.average:
        return const Color(0xFFB45309);
      case VerdictLevel.needsWork:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _fg),
      ),
    );
  }
}

class _ChipSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> chips;

  const _ChipSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: chips
              .map(
                (text) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ExplanationSection extends StatelessWidget {
  const _ExplanationSection({
    this.shortText,
    this.detailedText,
    this.comparisonText,
    this.backendLabel,
  });

  final String? shortText;
  final String? detailedText;
  final String? comparisonText;
  final String? backendLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: Color(0xFF4F46E5),
              ),
              SizedBox(width: 6),
              Text(
                'AI 상세 분석',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ],
          ),
          if (backendLabel?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              backendLabel!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.secondaryText,
              ),
            ),
          ],
          if (shortText?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              shortText!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
          ],
          if (detailedText?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              detailedText!,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ],
          if (comparisonText?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              comparisonText!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.55,
                fontWeight: FontWeight.w700,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
