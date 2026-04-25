import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../widget/app_bottom_nav.dart';
import 'best_cut_screen.dart';
import 'camera/shooting_mode.dart';
import 'camera_screen.dart';
import 'editor_screen.dart';
import 'gallery_screen.dart';
import 'home_screen.dart';

/// 히스토리 → 갤러리 탭 이동 시 사용하는 글로벌 notifier.
/// 값을 설정한 뒤 popUntil(first)하면 MainShell이 갤러리 탭으로 전환한다.
final galleryIntentNotifier = ValueNotifier<String?>(null);

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
  String? _pendingGalleryAssetId;
  int _galleryKey = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('[MainShell] initState currentIndex=$_currentIndex');
    galleryIntentNotifier.addListener(_onGalleryIntent);
    // 지도 진입 전 GPS 미리 워밍업 — 권한 있으면 백그라운드에서 위치 획득 시작
    _warmUpLocation();
  }

  @override
  void dispose() {
    galleryIntentNotifier.removeListener(_onGalleryIntent);
    super.dispose();
  }

  void _onGalleryIntent() {
    final assetId = galleryIntentNotifier.value;
    if (assetId != null) {
      galleryIntentNotifier.value = null;
      setState(() {
        _pendingGalleryAssetId = assetId;
        _galleryKey++;
        _currentIndex = 1;
      });
    }
  }

  Future<void> _warmUpLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {}
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
    // 한 프레임 후 소비 완료 — EditorScreen initState에서 이미 캡처됨
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pendingEditorFuture = null;
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
        // focusId를 읽은 뒤 바로 소비 — setState 없이 지워서 재빌드 방지
        final focusId = _pendingGalleryAssetId;
        _pendingGalleryAssetId = null;
        return GalleryScreen(
          key: focusId != null ? ValueKey('gallery_$_galleryKey') : null,
          onMoveTab: goToTab,
          onOpenInEditor: openImageInEditor,
          focusAssetId: focusId,
        );
      case 2:
        return HomeScreen(onMoveTab: goToTab);
      case 3:
        return BestCutScreen(onMoveTab: goToTab);
      case 4:
        final future = _pendingEditorFuture;
        if (future != null) {
          Future.microtask(() {
            if (mounted) setState(() => _pendingEditorFuture = null);
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
      bottomNavigationBar: _currentIndex == 0
          ? null
          : AppBottomNav(
              currentIndex: _currentIndex,
              onTap: goToTab,
              onShutter: _openCamera,
            ),
    );
  }
}
