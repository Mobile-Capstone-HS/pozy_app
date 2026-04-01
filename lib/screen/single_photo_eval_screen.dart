import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../feature/a_cut/layer/evaluation/photo_evaluation_service.dart';
import '../feature/a_cut/model/model_score_detail.dart';
import '../feature/a_cut/model/photo_evaluation_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

class SinglePhotoEvalScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String? fileName;
  final PhotoEvaluationService? evaluationService;

  const SinglePhotoEvalScreen({
    super.key,
    required this.imageBytes,
    this.fileName,
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
        widget.evaluationService ?? OnDevicePhotoEvaluationService();
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
            Expanded(
              child: _loading
                  ? _LoadingView(fileName: widget.fileName)
                  : _errorMessage != null
                  ? _ErrorView(message: _errorMessage!, onRetry: _evaluate)
                  : _ResultView(imageBytes: widget.imageBytes, result: _result!),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primaryText,
          ),
          const SizedBox(height: 20),
          Text('분석 중...', style: AppTextStyles.title16),
          if (fileName != null) ...[
            const SizedBox(height: 6),
            Text(fileName!, style: AppTextStyles.body13),
          ],
        ],
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
            Text('평가 실패', style: AppTextStyles.title16),
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
          _ScoreCard(
            icon: Icons.stars_rounded,
            accent: const Color(0xFF0F172A),
            title: '종합 점수',
            subtitle: 'Final',
            score: result.finalPct,
            description: result.usesTechnicalScoreAsFinal
                ? '현재는 KonIQ + FLIVE-image의 기술 점수를 종합 점수로 사용합니다.'
                : '기술 점수와 미적 점수를 함께 반영한 최종 점수입니다.',
          ),
          const SizedBox(height: 12),
          _ScoreCard(
            icon: Icons.tune_rounded,
            accent: const Color(0xFF2563EB),
            title: '기술 점수',
            subtitle: 'Technical',
            score: result.technicalPct,
            description: '노출, 선예도, 노이즈 가능성을 종합한 온디바이스 품질 점수입니다.',
          ),
          if (result.aestheticPct != null) ...[
            const SizedBox(height: 12),
            _ScoreCard(
              icon: Icons.auto_awesome_rounded,
              accent: const Color(0xFF7C3AED),
              title: '미적 점수',
              subtitle: 'Aesthetic',
              score: result.aestheticPct!,
              description: 'AADB 또는 NIMA 계열 모델이 산출한 미적 선호도 점수입니다.',
            ),
          ],
          if (result.usesTechnicalScoreAsFinal) ...[
            const SizedBox(height: 12),
            const _InfoBanner(
              text: 'metadata.json 없이 모델 계약을 코드에 고정해 사용 중이므로, 현재 종합 점수는 기술 점수 중심으로 동작합니다.',
            ),
          ],
          if (result.scoreDetails.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ModelDetailSection(details: result.scoreDetails.toList()),
          ],
          if (result.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ChipSection(
              icon: Icons.check_circle_rounded,
              color: const Color(0xFF16A34A),
              title: '강점',
              chips: result.notes,
            ),
          ],
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ChipSection(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFF59E0B),
              title: '보완할 점',
              chips: result.warnings,
            ),
          ],
          if (result.modelVersion != null) ...[
            const SizedBox(height: 18),
            Text(
              '모델 조합: ${result.modelVersion}',
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.fileName != null)
                  Text(
                    result.fileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body13,
                  ),
                const SizedBox(height: 6),
                Text(
                  '최종 점수 ${result.finalPct}점',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  result.usesTechnicalScoreAsFinal
                      ? '현재 데모는 KonIQ 60% + FLIVE-image 40% 조합으로 평가합니다.'
                      : '온디바이스 모델 조합으로 사진 품질을 종합 평가했습니다.',
                  style: AppTextStyles.body13,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _VerdictBadge(level: result.verdictLevel, label: result.verdict),
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
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF475569)),
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

class _ModelDetailSection extends StatelessWidget {
  final List<ModelScoreDetail> details;

  const _ModelDetailSection({required this.details});

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
          const Text(
            '모델별 점수',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '각 모델의 정규화 점수와 반영 비율입니다.',
            style: AppTextStyles.body13,
          ),
          const SizedBox(height: 14),
          ...details.map((detail) => _ModelDetailTile(detail: detail)),
        ],
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
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
                  '${detail.normalizedPct}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
                Text(
                  'w ${(detail.weight * 100).round()}%',
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
      case VerdictLevel.good:
        return const Color(0xFFDCFCE7);
      case VerdictLevel.average:
        return const Color(0xFFFEF3C7);
      case VerdictLevel.poor:
        return const Color(0xFFFEE2E2);
    }
  }

  Color get _fg {
    switch (level) {
      case VerdictLevel.good:
        return const Color(0xFF15803D);
      case VerdictLevel.average:
        return const Color(0xFFB45309);
      case VerdictLevel.poor:
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
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: _fg,
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final int score;
  final String description;

  const _ScoreCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.score,
    required this.description,
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
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$score',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                      const TextSpan(
                        text: '/100',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: score / 100,
              backgroundColor: AppColors.track,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
        ],
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
