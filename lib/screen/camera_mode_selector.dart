import 'package:flutter/material.dart';

import '../golden.dart' show GoldenRatioScreen;
import '../third.dart' show RuleOfThirdsScreen;
import 'camera_screen.dart';

/// 카메라 탭 진입 시 첫 번째로 보이는 모드 선택 화면.
///
/// - 황금비율  → [GoldenRatioScreen]
/// - 3분할법   → [RuleOfThirdsScreen]
/// - 일반 카메라 → [CameraScreen]
///
/// MainShell 이 modal route 로 push 하며,
/// 각 모드 화면은 자체 close 버튼으로 pop 한다.
class CameraModeSelectorScreen extends StatelessWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;

  const CameraModeSelectorScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
  });

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 상단 바 ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: onBack,
                  ),
                  const Text(
                    '카메라 모드',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '원하는 구도 코칭 모드를 선택하세요',
                style: TextStyle(
                  color: Color(0xFF8D97A7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 28),
            // ── 모드 카드 ────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _ModeCard(
                      icon: Icons.auto_awesome,
                      gradientColors: const [Color(0xFFFFD700), Color(0xFFFF8C00)],
                      title: '황금비율',
                      subtitle: '1:1.618 — 피보나치 나선 기반 구도 코칭',
                      onTap: () => _push(context, const GoldenRatioScreen()),
                    ),
                    const SizedBox(height: 16),
                    _ModeCard(
                      icon: Icons.grid_on,
                      gradientColors: const [Color(0xFF00D4FF), Color(0xFF0099FF)],
                      title: '3분할법',
                      subtitle: '삼등분 격자 — 고전적 사진 구도의 기본',
                      onTap: () => _push(context, const RuleOfThirdsScreen()),
                    ),
                    const SizedBox(height: 16),
                    _ModeCard(
                      icon: Icons.camera_alt_outlined,
                      gradientColors: const [Color(0xFF546E7A), Color(0xFF37474F)],
                      title: '일반 카메라',
                      subtitle: 'YOLO 피사체 감지 — 실시간 피사체 트래킹',
                      onTap: () => _push(
                        context,
                        CameraScreen(
                          onMoveTab: (index) {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                            if (index != 2) onMoveTab(index);
                          },
                          onBack: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.first.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF8D97A7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.35),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
