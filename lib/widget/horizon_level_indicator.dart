import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 화면 중앙에 표시되는 수평선.
class HorizonLevelIndicator extends StatelessWidget {
  final double tiltDeg;
  final bool isLevel;

  const HorizonLevelIndicator({
    super.key,
    required this.tiltDeg,
    required this.isLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tiltDeg * math.pi / 180.0,
      child: Container(
        width: 120,
        height: 1,
        color: isLevel ? const Color(0xFFFBBF24) : Colors.white,
      ),
    );
  }
}
