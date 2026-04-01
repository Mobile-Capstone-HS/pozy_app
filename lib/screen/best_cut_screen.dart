import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

class BestCutScreen extends StatelessWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback? onBack;

  const BestCutScreen({super.key, required this.onMoveTab, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTopBar(title: '베스트 컷', onBack: onBack),
            const SizedBox(height: 22),
            const Text('여러 장 중 가장 좋은 컷을 빠르게 고르세요', style: AppTextStyles.title20),
            const SizedBox(height: 6),
            const Text(
              '현재 데모는 KonIQ와 FLIVE-image를 온디바이스에서 실행해 사진을 정렬하고, 베스트 샷과 A컷 후보를 바로 보여줍니다.',
              style: AppTextStyles.body13,
            ),
            const SizedBox(height: 18),
            const _FeatureCard(
              title: 'A컷 랭킹',
              subtitle: '여러 장 선택 -> 자동 순위화 -> 베스트 샷 강조',
              icon: Icons.content_cut_rounded,
            ),
            const SizedBox(height: 12),
            const _FeatureCard(
              title: '단일 사진 평가',
              subtitle: '촬영 직후 또는 갤러리 1장 선택 후 바로 점수 확인',
              icon: Icons.auto_awesome_rounded,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => onMoveTab(1),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text(
                  '갤러리에서 A컷 고르기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryText,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => onMoveTab(2),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text(
                  '촬영 후 바로 평가하기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
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
                    '현재 추천 흐름',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryText,
                    ),
                  ),
                  SizedBox(height: 10),
                  _StepRow(
                    index: 1,
                    text: '카메라에서 촬영하면 저장 직후 “사진 평가하기”로 이동할 수 있습니다.',
                  ),
                  SizedBox(height: 8),
                  _StepRow(
                    index: 2,
                    text: '갤러리에서 1장을 선택하면 단일 평가, 여러 장을 선택하면 A컷 분석이 가능합니다.',
                  ),
                  SizedBox(height: 8),
                  _StepRow(
                    index: 3,
                    text: 'A컷 결과 화면에서는 BEST SHOT 강조와 상세 점수 확인이 가능합니다.',
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

class _FeatureCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.soft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primaryText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.title16),
                const SizedBox(height: 4),
                Text(subtitle, style: AppTextStyles.body13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final String text;

  const _StepRow({
    required this.index,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.primaryText,
            shape: BoxShape.circle,
          ),
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
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppTextStyles.body13)),
      ],
    );
  }
}
