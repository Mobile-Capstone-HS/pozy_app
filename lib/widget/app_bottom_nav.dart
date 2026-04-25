import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onShutter;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onShutter,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final isCompact = MediaQuery.sizeOf(context).width < 360 || textScale > 1.1;
    final hasSystemNav = MediaQuery.paddingOf(context).bottom > 0;
    final bottomPadding = hasSystemNav ? 4.0 : (isCompact ? 10.0 : 14.0);

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 6 : 8,
          isCompact ? 4 : 6,
          isCompact ? 6 : 8,
          bottomPadding,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(0, Icons.home_outlined, Icons.home, 'Home', currentIndex, onTap, isCompact),
                  _navItem(1, Icons.image_outlined, Icons.image, 'Gallery', currentIndex, onTap, isCompact),
                ],
              ),
            ),
            _StaticShutterButton(onTap: onShutter, isCompact: isCompact),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _navItem(3, Icons.content_cut_outlined, Icons.content_cut, 'Best Cut', currentIndex, onTap, isCompact),
                  _navItem(4, Icons.auto_awesome_outlined, Icons.auto_awesome, 'Editor', currentIndex, onTap, isCompact),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _navItem(
  int index,
  IconData icon,
  IconData activeIcon,
  String label,
  int currentIndex,
  ValueChanged<int> onTap,
  bool isCompact,
) {
  final selected = currentIndex == index;
  final color = selected ? Colors.black : const Color(0xFFB8C0CC);
  return Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onTap(index),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 2 : 4,
          vertical: 4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? activeIcon : icon,
              size: isCompact ? 20 : 22,
              color: color,
            ),
            SizedBox(height: isCompact ? 3 : 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.nav11.copyWith(
                color: color,
                fontSize: isCompact ? 10 : 11,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// 다른 탭에서 보이는 정적 셔터 버튼 (깜빡임 없음)
class _StaticShutterButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isCompact;

  const _StaticShutterButton({required this.onTap, required this.isCompact});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        height: 72,
        child: Center(
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF29B6F6), width: 2.5),
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

