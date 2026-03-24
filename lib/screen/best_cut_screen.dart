import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import 'analyze_best_screen.dart';

class BestCutScreen extends StatelessWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback? onBack;

  const BestCutScreen({super.key, required this.onMoveTab, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isCompact = width < 360;
          final horizontalPadding = isCompact ? 16.0 : 20.0;
          final heroHeight = (width * 0.58).clamp(180.0, 220.0);
          final smallCardHeight = (width * 0.34).clamp(112.0, 140.0);
          final useVerticalRanks = width < 340;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              10,
              horizontalPadding,
              20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTopBar(title: '베스트 컷 추천', onBack: onBack),
                const SizedBox(height: 20),
                const Text('이미지 분석 진행 중...', style: AppTextStyles.title16),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Expanded(
                      child: Text(
                        '표정과 조명을 분석하고 있어요...',
                        style: AppTextStyles.body13,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      '84%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(
                    minHeight: 8,
                    value: 0.84,
                    backgroundColor: AppColors.track,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryText,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                const Text('Top3 Pozy 추천 픽!', style: AppTextStyles.title20),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AnalyzeBestScreen(),
                      ),
                    );
                  },
                  child: _HeroCard(tag: '#1 베스트 컷', height: heroHeight),
                ),
                const SizedBox(height: 12),
                if (useVerticalRanks)
                  Column(
                    children: [
                      _SmallRankCard(
                        tag: '#2',
                        height: smallCardHeight,
                        child: const _SolidBlueArt(),
                      ),
                      const SizedBox(height: 12),
                      _SmallRankCard(
                        tag: '#3',
                        height: smallCardHeight,
                        child: const _SolidGreenArt(),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _SmallRankCard(
                          tag: '#2',
                          height: smallCardHeight,
                          child: const _SolidBlueArt(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SmallRankCard(
                          tag: '#3',
                          height: smallCardHeight,
                          child: const _SolidGreenArt(),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 26),
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
                    onPressed: () {},
                    icon: const Icon(Icons.refresh),
                    label: const Text(
                      '초기화하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
                    onPressed: () => onMoveTab(4),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text(
                      '편집하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String tag;
  final double height;

  const _HeroCard({required this.tag, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: const _SolidHeroArt(),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '자연스러운 표정과 좋은 조명',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallRankCard extends StatelessWidget {
  final String tag;
  final double height;
  final Widget child;

  const _SmallRankCard({
    required this.tag,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(height: height, width: double.infinity, child: child),
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolidHeroArt extends StatelessWidget {
  const _SolidHeroArt();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFB7185), Color(0xFFF59E0B), Color(0xFF38BDF8)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 20,
            top: 24,
            child: Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          Positioned(
            right: 24,
            top: 34,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 42,
            right: 42,
            bottom: 28,
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolidBlueArt extends StatelessWidget {
  const _SolidBlueArt();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C81), Color(0xFF38BDF8)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 14,
            right: 14,
            bottom: 16,
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 22,
            top: 18,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: 26,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SolidGreenArt extends StatelessWidget {
  const _SolidGreenArt();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16A34A), Color(0xFFFACC15)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 18,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 16,
            child: Container(
              width: 76,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            left: 14,
            bottom: 14,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.46),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
