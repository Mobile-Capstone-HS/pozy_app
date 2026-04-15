import 'package:flutter/material.dart';

import '../shooting_mode.dart';

/// 하단의 인물/객체/풍경 모드 전환 탭.
class ModeSwitcher extends StatelessWidget {
  static const _availableModes = [
    ShootingMode.person,
    ShootingMode.object,
    ShootingMode.landscape,
  ];

  final ShootingMode selected;
  final ValueChanged<ShootingMode> onChanged;

  const ModeSwitcher({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: _availableModes.map((mode) {
          final isSelected = selected == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(mode),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mode.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isSelected ? 18 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
