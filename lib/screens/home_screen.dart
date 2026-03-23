import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.onLaunch,
  });

  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.menu_rounded),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Pozy',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '당신의 촬영 경험을\n보다 이롭게',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '사람은 자동으로 추적하고, 음식/사물은 나중에 분류 로직을 붙일 수 있게 구조를 정리한 버전이야.',
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: Colors.black.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 22),
            _ActionCard(
              icon: Icons.bolt_rounded,
              title: 'Quick Shoot',
              description: '현재 프레임을 빠르게 확인하고 카메라 모드로 바로 들어가.',
              buttonLabel: 'Launch',
              onTap: onLaunch,
            ),
            const SizedBox(height: 14),
            _ActionCard(
              icon: Icons.photo_library_outlined,
              title: 'Gallery',
              description: '촬영 결과를 나중에 이 영역에서 다시 볼 수 있게 연결할 거야.',
              buttonLabel: 'Open',
              onTap: () {},
            ),
            const SizedBox(height: 14),
            _ActionCard(
              icon: Icons.tips_and_updates_outlined,
              title: 'Pick your Best',
              description: '베스트컷 추천은 아직 자리만 잡아둔 상태야.',
              buttonLabel: 'Try now',
              onTap: onLaunch,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Colors.black.withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F1EA),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: onTap,
                  child: Text(buttonLabel),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFFF6F6F2),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Icon(
                icon,
                size: 42,
                color: Colors.black.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}