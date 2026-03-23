import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import '../widget/home_feature_card.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;

  const HomeScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTopBar(
            title: 'Pozy',
            onBack: onBack,
            trailing: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.soft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_circle_outlined,
                size: 20,
                color: AppColors.primaryText,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '당신의 촬영 경험을 보다 이롭게',
            style: AppTextStyles.title20,
          ),
          const SizedBox(height: 4),
          const Text(
            '상상을 현실로, Pozy를 경험해보세요!',
            style: AppTextStyles.body13,
          ),
          const SizedBox(height: 18),
          HomeFeatureCard(
            icon: Icons.flash_on_outlined,
            title: 'Quick Shoot',
            description:
                'Start capturing high-quality moments instantly with one tap.',
            buttonText: 'Launch',
            onTap: () => onMoveTab(2),
            visual: const _VisualBox(
              child: Icon(
                Icons.camera_alt_outlined,
                size: 54,
                color: AppColors.primaryText,
              ),
            ),
          ),
          const SizedBox(height: 14),
          HomeFeatureCard(
            icon: Icons.photo_library_outlined,
            title: 'Gallery',
            description:
                'View, organize, and manage your entire media library.',
            buttonText: 'Open',
            onTap: () => onMoveTab(1),
            visual: const _VisualBox(
              child: Icon(
                Icons.collections_outlined,
                size: 54,
                color: AppColors.primaryText,
              ),
            ),
          ),
          const SizedBox(height: 14),
          HomeFeatureCard(
            icon: Icons.auto_awesome_outlined,
            title: 'Pick your Best',
            description:
                'Enjoy Pozy to the fullest, suggest the best shots from your bursts.',
            buttonText: 'Try Now',
            onTap: () => onMoveTab(4),
            visual: const _VisualBox(
              child: Icon(
                Icons.edit_outlined,
                size: 54,
                color: AppColors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisualBox extends StatelessWidget {
  final Widget child;

  const _VisualBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryText.withOpacity(0.4),
        ),
      ),
      child: Center(child: child),
    );
  }
}