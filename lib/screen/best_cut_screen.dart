import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'best_cut_gallery_screen.dart';

const _kBlue = Color(0xFF64B5F6);

class BestCutScreen extends StatelessWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback? onBack;

  const BestCutScreen({super.key, required this.onMoveTab, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          final gap = ((h - 460) / 8).clamp(4.0, 16.0);
          final featurePad = ((h - 460) / 22).clamp(4.0, 10.0);
          final btnHeight = h < 620 ? 42.0 : 48.0;
          final lineH = ((h - 400) / 8).clamp(16.0, 32.0);

          return Padding(
            padding: EdgeInsets.fromLTRB(22, gap * 1.5, 22, gap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 헤더 ────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _kBlue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '실시간 구도 코칭은 그대로,\n촬영 후엔 베스트 컷 추천까지',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryText,
                          height: 1.35,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                const Text(
                  '한 장은 간단 평가, 여러 장은 A컷 랭킹으로 이어져요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryText,
                    height: 1.4,
                  ),
                ),

                SizedBox(height: gap),

                // ── 특징 목록 ──────────────────────────────
                _FeatureRow(
                  icon: Icons.content_cut_rounded,
                  title: '여러 장 A컷 랭킹',
                  subtitle: 'BEST, Top 3, 추천 컷 중심으로 빠르게 비교',
                  vertPad: featurePad,
                ),
                const Divider(height: 1, color: Color(0xFFF0F0F0)),
                _FeatureRow(
                  icon: Icons.auto_awesome_rounded,
                  title: '한 장 빠른 평가',
                  subtitle: '촬영 직후 또는 갤러리 1장 선택 후 바로 확인',
                  vertPad: featurePad,
                ),
                const Divider(height: 1, color: Color(0xFFF0F0F0)),
                _FeatureRow(
                  icon: Icons.camera_alt_outlined,
                  title: '카메라 코칭 유지',
                  subtitle: '실시간 구도 가이드는 기존 카메라 흐름 그대로',
                  vertPad: featurePad,
                ),

                SizedBox(height: gap),

                // ── 버튼 2개 ──────────────────────────────
                _OutlineButton(
                  height: btnHeight,
                  icon: Icons.photo_library_outlined,
                  label: '갤러리에서 여러 장 분석하기',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BestCutGalleryScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _OutlineButton(
                  height: btnHeight,
                  icon: Icons.camera_alt_outlined,
                  label: '카메라로 촬영해 한 장 평가하기',
                  onTap: () => onMoveTab(2),
                ),

                SizedBox(height: gap),

                // ── 추천 흐름 (타임라인) ──────────────────
                const Row(
                  children: [
                    Icon(Icons.route_rounded, color: _kBlue, size: 14),
                    SizedBox(width: 5),
                    Text(
                      '추천 흐름',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: gap * 0.6),
                _TimelineStep(
                  index: 1,
                  text: '카메라 촬영 직후 "이 사진 평가하기"로 단일 평가를 바로 시작할 수 있습니다.',
                  isLast: false,
                  lineHeight: lineH,
                ),
                _TimelineStep(
                  index: 2,
                  text: '갤러리에서 1장 선택 시 단일 평가, 2장 이상 선택 시 A컷 랭킹으로 연결됩니다.',
                  isLast: false,
                  lineHeight: lineH,
                ),
                _TimelineStep(
                  index: 3,
                  text: 'A컷 결과에서 BEST 1장, Top 3, 추천 컷 순서를 우선적으로 보여줍니다.',
                  isLast: true,
                  lineHeight: lineH,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── 특징 행 ──────────────────────────────────────────────
class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double vertPad;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.vertPad = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertPad),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: _kBlue, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    )),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.body13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 아웃라인 버튼 ─────────────────────────────────────────
class _OutlineButton extends StatelessWidget {
  final double height;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlineButton({
    required this.height,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBlue.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primaryText, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 타임라인 단계 ─────────────────────────────────────────
class _TimelineStep extends StatelessWidget {
  final int index;
  final String text;
  final bool isLast;
  final double lineHeight;

  const _TimelineStep({
    required this.index,
    required this.text,
    required this.isLast,
    this.lineHeight = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 1.5,
                  height: lineHeight,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  color: _kBlue.withValues(alpha: 0.25),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText,
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
