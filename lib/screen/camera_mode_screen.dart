import 'package:flutter/material.dart';

import 'camera_screen.dart';
import 'landscape_camera_screen.dart';

enum _CameraModeTab { portrait, landscape }

class CameraModeScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;

  const CameraModeScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
  });

  @override
  State<CameraModeScreen> createState() => _CameraModeScreenState();
}

class _CameraModeScreenState extends State<CameraModeScreen> {
  _CameraModeTab _mode = _CameraModeTab.portrait;
  _CameraModeTab? _activeMode = _CameraModeTab.portrait;
  bool _switching = false;

  Future<void> _switchMode(_CameraModeTab mode) async {
    if (_mode == mode || _switching) return;
    setState(() {
      _switching = true;
      _activeMode = null; // unmount current camera view first
    });
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _activeMode = mode;
      _switching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _activeMode == null
              ? const SizedBox.expand()
              : (_activeMode == _CameraModeTab.portrait
                ? CameraScreen(
                    key: const ValueKey<String>('portrait_camera'),
                    onMoveTab: widget.onMoveTab,
                    onBack: widget.onBack,
                  )
                : LandscapeCameraScreen(
                    key: const ValueKey<String>('landscape_camera'),
                    onMoveTab: widget.onMoveTab,
                    onBack: widget.onBack,
                  )),
          Positioned(
            left: 0,
            right: 0,
            bottom: 84 + bottomInset,
            child: Center(
              child: _ModeSwitcher(
                selected: _mode,
                onChanged: _switchMode,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  final _CameraModeTab selected;
  final ValueChanged<_CameraModeTab> onChanged;

  const _ModeSwitcher({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChip(
            label: '인물',
            selected: selected == _CameraModeTab.portrait,
            onTap: () => onChanged(_CameraModeTab.portrait),
          ),
          const SizedBox(width: 4),
          _ModeChip(
            label: '풍경',
            selected: selected == _CameraModeTab.landscape,
            onTap: () => onChanged(_CameraModeTab.landscape),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
