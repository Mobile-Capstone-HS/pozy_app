import 'package:flutter/material.dart';

import 'glass_icon_button.dart';

class TopCameraBar extends StatelessWidget {
  final VoidCallback onBack;
  final Widget? toolBar;
  final Widget? trailing;

  const TopCameraBar({
    super.key,
    required this.onBack,
    this.toolBar,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: onBack,
          diameter: 36,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailing != null) trailing!,
                  if (toolBar != null) ...[
                    if (trailing != null) const SizedBox(width: 6),
                    toolBar!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
