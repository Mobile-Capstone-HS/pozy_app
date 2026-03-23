import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AnalyzeBestScreen extends StatelessWidget {
  const AnalyzeBestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new, size: 20),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          '',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 215,
                      width: double.infinity,
                      child: Image.network(
                        'https://images.unsplash.com/photo-1517849845537-4d257902454a?w=1000',
                        fit: BoxFit.cover,
                      ),
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
                        child: const Text(
                          '#1 베스트 컷',
                          style: TextStyle(
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
              const SizedBox(height: 20),
              const Text('│ Pozy 분석 리포트', style: AppTextStyles.title20),
              const SizedBox(height: 14),
              const _ReportCard(
                title: '구도 (Composition)',
                score: 95,
                description: '삼분할 법칙에 맞춰 완벽하게 위치해 있습니다.',
              ),
              const SizedBox(height: 12),
              const _ReportCard(
                title: '밝기 (Brightness)',
                score: 88,
                description: '자연스러운 채광이 피사체를 돋보이게 합니다.',
              ),
              const SizedBox(height: 12),
              const _PassCard(),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.buttonDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.download_outlined),
                  label: const Text(
                    '이어서 편집하기 (Edit Photo)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.soft,
                    foregroundColor: AppColors.primaryText,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.refresh),
                  label: const Text(
                    '다른 사진 분석하기 (Analyze Others)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final int score;
  final String description;

  const _ReportCard({
    required this.title,
    required this.score,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view_rounded, size: 18, color: AppColors.primaryText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: AppTextStyles.title16),
              ),
              Text(
                '$score',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const Text(
                '/100',
                style: TextStyle(fontSize: 12, color: AppColors.lightText),
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
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryText),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(description, style: AppTextStyles.body13),
          ),
        ],
      ),
    );
  }
}

class _PassCard extends StatelessWidget {
  const _PassCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.visibility_outlined, size: 18, color: AppColors.primaryText),
              SizedBox(width: 8),
              Expanded(child: Text('눈감음 여부 (Eye Detection)', style: AppTextStyles.title16)),
              Text(
                'PASS',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.pass,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              minHeight: 8,
              value: 1,
              backgroundColor: AppColors.track,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.pass),
            ),
          ),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '모든 피사체가 눈을 뜨고 있습니다.',
              style: AppTextStyles.body13,
            ),
          ),
        ],
      ),
    );
  }
}