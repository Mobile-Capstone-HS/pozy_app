import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home'),
      _NavItem(icon: Icons.image_outlined, activeIcon: Icons.image, label: 'Gallery'),
      _NavItem(icon: Icons.camera_alt_outlined, activeIcon: Icons.camera_alt, label: 'Camera'),
      _NavItem(icon: Icons.content_cut_outlined, activeIcon: Icons.content_cut, label: 'Best Cut'),
      _NavItem(icon: Icons.auto_awesome_outlined, activeIcon: Icons.auto_awesome, label: 'Editor'),
    ];

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final isCompact = constraints.maxWidth < 360 || textScale > 1.1;
          final bottomPadding = MediaQuery.paddingOf(context).bottom > 0
              ? 10.0
              : (isCompact ? 10.0 : 14.0);

          return Container(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 6 : 8,
              isCompact ? 6 : 8,
              isCompact ? 6 : 8,
              bottomPadding,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              children: List.generate(items.length, (index) {
                final selected = currentIndex == index;
                final item = items[index];
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
                        children: [
                          Icon(
                            selected ? item.activeIcon : item.icon,
                            size: isCompact ? 20 : 22,
                            color: color,
                          ),
                          SizedBox(height: isCompact ? 3 : 4),
                          Text(
                            item.label,
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
              }),
            ),
          );
        },
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
