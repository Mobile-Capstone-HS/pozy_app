import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/enums/composition_mode.dart';
import 'package:pose_camera_app/screens/camera_coach_screen.dart';
import 'package:pose_camera_app/screens/home_screen.dart';
import 'package:pose_camera_app/screens/gallery_screen.dart';

class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
        HomeScreen(onLaunch: _openCameraChooser),
        const GalleryScreen(),
        const _CoachPlaceholderScreen(),
        const _SettingsPlaceholderScreen(),
    ];

    return Scaffold(
      body: pages[_index],
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: _openCameraChooser,
          icon: const Icon(Icons.camera_alt_rounded, color: Colors.white),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Gallery',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Coach',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _openCameraChooser() async {
    final mode = await showModalBottomSheet<CompositionMode>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '카메라 모드 선택',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  '사람은 자동 인식, 음식/사물은 1차 분류 기준으로 동작하게 연결할 거야.',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 18),
                _ModeTile(
                  title: '황금비율',
                  subtitle: '더 드라마틱한 포인트 배치',
                  onTap: () => Navigator.pop(
                    context,
                    CompositionMode.goldenRatio,
                  ),
                ),
                const SizedBox(height: 10),
                _ModeTile(
                  title: '3분할',
                  subtitle: '가장 이해하기 쉬운 기본 구도',
                  onTap: () => Navigator.pop(
                    context,
                    CompositionMode.ruleOfThirds,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || mode == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraCoachScreen(compositionMode: mode),
      ),
    );

    setState(() {});
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F2),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded),
          ],
        ),
      ),
    );
  }
}

class _GalleryPlaceholderScreen extends StatelessWidget {
  const _GalleryPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Gallery 자리',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CoachPlaceholderScreen extends StatelessWidget {
  const _CoachPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Coach 자리',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SettingsPlaceholderScreen extends StatelessWidget {
  const _SettingsPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Settings 자리',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
    );
  }
}