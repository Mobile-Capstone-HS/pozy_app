import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import 'analyze_best_screen.dart';

class BestCutScreen extends StatelessWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;

  const BestCutScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTopBar(
            title: '베스트 컷 추천',
            onBack: onBack,
          ),
          const SizedBox(height: 20),
          const Text(
            '이미지 분석 진행 중..',
            style: AppTextStyles.title16,
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(
                child: Text(
                  'Evaluating facial expressions & lighting...',
                  style: AppTextStyles.body13,
                ),
              ),
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
          const Text(
            'Top3 Pozy 추천 픽!',
            style: AppTextStyles.title20,
          ),
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
            child: _heroCard(
              'https://images.unsplash.com/photo-1517849845537-4d257902454a?w=900',
              '#1 베스트 컷',
              true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _smallRankCard(
                  'https://images.unsplash.com/photo-1504208434309-cb69f4fe52b0?w=600',
                  '#2',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _smallRankCard(
                  'https://images.unsplash.com/photo-1518770660439-4636190af475?w=600',
                  '#3',
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
  }

  Widget _heroCard(String imageUrl, String tag, bool badgeDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(
            height: 205,
            width: double.infinity,
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: badgeDark ? Colors.black54 : Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  color: badgeDark ? Colors.white : AppColors.primaryText,
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

  Widget _smallRankCard(String imageUrl, String tag) {
    return GestureDetector(
      onTap: () {},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
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
      ),
    );
  }
}