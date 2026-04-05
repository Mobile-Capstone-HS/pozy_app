import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import 'best_cut_gallery_screen.dart';

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
            const Text(
              '실시간 구도 코칭은 그대로, 촬영 후에는 베스트 컷 추천까지',
              style: AppTextStyles.title20,
            ),
            const SizedBox(height: 6),
            const Text(
              '이 화면은 점수 자체보다 어떤 사진을 먼저 고를지 보여주는 데 집중합니다. 한 장은 간단 평가, 여러 장은 A컷 랭킹으로 이어져요.',
              style: AppTextStyles.body13,
            ),
            const SizedBox(height: 18),
            const _FeatureCard(
              title: '여러 장 A컷 랭킹',
              subtitle: 'BEST, Top 3, 추천 컷 중심으로 빠르게 비교',
              icon: Icons.content_cut_rounded,
            ),
            const SizedBox(height: 12),
            const _FeatureCard(
              title: '한 장 빠른 평가',
              subtitle: '촬영 직후 또는 갤러리 1장 선택 후 바로 확인',
              icon: Icons.auto_awesome_rounded,
            ),
            const SizedBox(height: 12),
            const _FeatureCard(
              title: '카메라 코칭 유지',
              subtitle: '실시간 구도 가이드는 기존 카메라 흐름 그대로 사용',
              icon: Icons.camera_alt_outlined,
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
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BestCutGalleryScreen(),
                  ),
                ),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text(
                  '갤러리에서 여러 장 랭킹하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                  '카메라에서 한 장 평가하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                    '추천 흐름',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryText,
                    ),
                  ),
                  SizedBox(height: 10),
                  _StepRow(
                    index: 1,
                    text: '카메라에서 촬영하면 저장 직후 “이 사진 평가하기”로 단일 사진 평가를 시작할 수 있습니다.',
                  ),
                  SizedBox(height: 8),
                  _StepRow(
                    index: 2,
                    text: '갤러리에서 1장을 선택하면 단일 평가, 2장 이상 선택하면 A컷 랭킹으로 연결됩니다.',
                  ),
                  SizedBox(height: 8),
                  _StepRow(
                    index: 3,
                    text: 'A컷 결과 화면에서는 BEST 1장, Top 3, 추천 컷 순서를 우선적으로 보여줍니다.',
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
