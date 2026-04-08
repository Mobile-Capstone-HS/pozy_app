import 'package:flutter/material.dart';

import '../widget/app_bottom_nav.dart';
import 'best_cut_screen.dart';
import 'camera_mode_screen.dart';
import 'editor_screen.dart';
import 'gallery_screen.dart';
import 'home_screen.dart';
import 'landscape_image_test_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  void goToTab(int index) {
    if (index == 2) {
      _openCameraModeSelector();
      return;
    }

    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _openCameraModeSelector() async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('카메라 모드'),
                subtitle: const Text('인물 / 풍경 모드 전환'),
                onTap: () => Navigator.of(context).pop('camera_mode'),
              ),
              ListTile(
                leading: const Icon(Icons.image_search_outlined),
                title: const Text('테스트 모드'),
                subtitle: const Text('assets/images/image.png'),
                onTap: () => Navigator.of(context).pop('test_mode'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || mode == null) return;
    if (mode == 'test_mode') {
      await _openLandscapeImageTestScreen();
      return;
    }
    await _openCameraModeScreen();
  }

  Future<void> _openCameraModeScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CameraModeScreen(
          onMoveTab: (index) {
            Navigator.of(context).pop();
            if (index != 2) {
              goToTab(index);
            }
          },
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _openLandscapeImageTestScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LandscapeImageTestScreen(
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return HomeScreen(onMoveTab: goToTab);
      case 1:
        return GalleryScreen(onMoveTab: goToTab);
      case 2:
        return HomeScreen(onMoveTab: goToTab);
      case 3:
        return BestCutScreen(onMoveTab: goToTab);
      case 4:
        return EditorScreen(onMoveTab: goToTab);
      default:
        return HomeScreen(onMoveTab: goToTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildPage(_currentIndex),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTap: goToTab,
      ),
    );
  }
}
