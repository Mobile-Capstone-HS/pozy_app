import 'package:flutter/material.dart';

/// 유리 느낌의 반투명 원형 아이콘 버튼. 카메라 화면 상/하단 제어부에서 공용.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double diameter;
  final Color? tint;
  final String? label;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.diameter = 40,
    this.tint,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final bg = tint ?? const Color(0x66333333);
    final iconColor = tint != null ? const Color(0xFF0F172A) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: label != null ? null : diameter,
        height: diameter,
        padding: label != null
            ? const EdgeInsets.symmetric(horizontal: 10)
            : null,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint ?? const Color(0x4DFFFFFF), width: 1),
        ),
        alignment: Alignment.center,
        child: label != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: diameter * 0.42),
                  const SizedBox(width: 4),
                  Text(
                    label!,
                    style: TextStyle(color: iconColor, fontSize: 11),
                  ),
                ],
              )
            : Icon(icon, color: iconColor, size: diameter * 0.45),
      ),
    );
  }
}
