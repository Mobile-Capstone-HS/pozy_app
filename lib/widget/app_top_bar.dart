import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;
  final double trailingWidth;

  const AppTopBar({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
    this.trailingWidth = 36,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: AppColors.primaryText,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ),
          SizedBox(
            width: trailingWidth,
            height: 36,
            child: trailing ?? const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
