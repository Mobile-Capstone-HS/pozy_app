import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onLeadingTap;
  final Widget? trailing;
  final double trailingWidth;
  final IconData leadingIcon;

  const AppTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.onLeadingTap,
    this.trailing,
    this.trailingWidth = 36,
    this.leadingIcon = Icons.menu_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        final effectiveLeadingTap = onLeadingTap ?? onBack;
        final sideButtonSize = isCompact ? 34.0 : 36.0;
        final requestedTrailingWidth = trailing != null
            ? trailingWidth
            : sideButtonSize;
        final maxSideSlotWidth = constraints.maxWidth * 0.28;
        final sideSlotWidth = requestedTrailingWidth > sideButtonSize
            ? requestedTrailingWidth
            : sideButtonSize;
        final resolvedSideSlotWidth = sideSlotWidth > maxSideSlotWidth
            ? maxSideSlotWidth
            : sideSlotWidth;

        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: isCompact ? 48 : 52),
          child: Row(
            children: [
              SizedBox(
                width: resolvedSideSlotWidth,
                height: sideButtonSize,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _LeadingButton(
                    icon: leadingIcon,
                    size: sideButtonSize,
                    iconSize: isCompact ? 20 : 22,
                    onTap: effectiveLeadingTap,
                  ),
                ),
              ),
              SizedBox(width: isCompact ? 8 : 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isCompact ? 16 : 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              SizedBox(width: isCompact ? 8 : 12),
              SizedBox(
                width: resolvedSideSlotWidth,
                height: sideButtonSize,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: trailing ?? const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LeadingButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback? onTap;

  const _LeadingButton({
    required this.icon,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: size,
      height: size,
      child: Icon(icon, size: iconSize, color: AppColors.primaryText),
    );

    if (onTap == null) {
      return child;
    }

    return GestureDetector(onTap: onTap, child: child);
  }
}
