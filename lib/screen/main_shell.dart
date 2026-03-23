import 'package:flutter/material.dart';
import '../widget/app_bottom_nav.dart';
import 'best_cut_screen.dart';
import 'camera_screen.dart';
import 'editor_screen.dart';
import 'gallery_screen.dart';
import 'home_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final List<int> _history = [];

  void goToTab(int index) {
    if (index == 2) {
      _openCameraScreen();
      return;
    }

    if (index == _currentIndex) return;

    _history.add(_currentIndex);
    setState(() {
      _currentIndex = index;
    });
  }

  void goBackTab() {
    if (_history.isNotEmpty) {
      final previous = _history.removeLast();
      setState(() {
        _currentIndex = previous;
      });
    } else if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
      });
    }
  }

  Future<void> _openCameraScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CameraScreen(
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

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return HomeScreen(
          onMoveTab: goToTab,
          onBack: goBackTab,
        );
      case 1:
        return GalleryScreen(
          onMoveTab: goToTab,
          onBack: goBackTab,
        );
      case 2:
        return HomeScreen(
          onMoveTab: goToTab,
          onBack: goBackTab,
        );
      case 3:
        return BestCutScreen(
          onMoveTab: goToTab,
          onBack: goBackTab,
        );
      case 4:
        return EditorScreen(
          onMoveTab: goToTab,
          onBack: goBackTab,
        );
      default:
        return HomeScreen(
          onMoveTab: goToTab,
          onBack: goBackTab,
        );
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
