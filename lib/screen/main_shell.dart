import 'dart:typed_data';

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
  Future<Uint8List?>? _pendingEditorFuture;
  int _editorKey = 0;
  bool _loggedFirstBuild = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[MainShell] initState currentIndex=$_currentIndex');
  }

  void goToTab(int index) {
    debugPrint('[MainShell] goToTab index=$index current=$_currentIndex');
    if (index == 2) {
      _openCamera();
      return;
    }

    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
  }

  void openImageInEditor(Future<Uint8List?> future) {
    setState(() {
      _pendingEditorFuture = future;
      _editorKey++;
      _currentIndex = 4;
    });
  }

  Future<void> _openCamera() async {
    debugPrint('[MainShell] _openCamera start');
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
          initialMode: ShootingMode.person,
        ),
      ),
    );
    debugPrint('[MainShell] _openCamera completed');
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return HomeScreen(onMoveTab: goToTab);
      case 1:
        return GalleryScreen(
          onMoveTab: goToTab,
          onOpenInEditor: openImageInEditor,
        );
      case 2:
        return HomeScreen(onMoveTab: goToTab);
      case 3:
        return BestCutScreen(onMoveTab: goToTab);
      case 4:
        final future = _pendingEditorFuture;
        if (future != null) {
          Future.microtask(() {
            if (mounted) {
              setState(() => _pendingEditorFuture = null);
            }
          });
        }
        return EditorScreen(
          key: ValueKey(_editorKey),
          onMoveTab: goToTab,
          initialBytesFuture: future,
        );
      default:
        return HomeScreen(onMoveTab: goToTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedFirstBuild) {
      _loggedFirstBuild = true;
      debugPrint('[MainShell] first build currentIndex=$_currentIndex');
    }
    return Scaffold(
      body: _buildPage(_currentIndex),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onTap: goToTab,
      ),
    );
  }
}
