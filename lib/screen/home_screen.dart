import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import '../widget/home_feature_card.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onMoveTab;

  const HomeScreen({super.key, required this.onMoveTab});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = 16.0;
          const topPadding = 10.0;

          final cards = [
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
            HomeFeatureCard(
              icon: Icons.auto_awesome_outlined,
              title: 'Pick your Best',
              description:
                  'Enjoy Pozy to the fullest and surface the strongest frames fast.',
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
          ];

          final header = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTopBar(
                title: 'Pozy',
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
              const Text('당신의 촬영을 보다 가볍게', style: AppTextStyles.title20),
              const SizedBox(height: 4),
              const Text(
                '일상 속 순간들을 Pozy로 더 편하게 기록해보세요.',
                style: AppTextStyles.body13,
              ),
            ],
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              20,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - topPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 18),
                  cards[0],
                  const SizedBox(height: 14),
                  cards[1],
                  const SizedBox(height: 14),
                  cards[2],
                ],
              ),
            ),
          );
        },
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
        border: Border.all(color: AppColors.primaryText.withValues(alpha: 0.4)),
      ),
      child: Center(child: child),
    );
  }
}
