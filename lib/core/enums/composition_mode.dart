import 'package:flutter/material.dart';

enum CompositionMode { goldenRatio, ruleOfThirds }

extension CompositionModeX on CompositionMode {
  String get title {
    switch (this) {
      case CompositionMode.goldenRatio:
        return '황금비율';
      case CompositionMode.ruleOfThirds:
        return '3분할';
    }
  }

  String get shortLabel {
    switch (this) {
      case CompositionMode.goldenRatio:
        return 'GOLDEN';
      case CompositionMode.ruleOfThirds:
        return 'THIRDS';
    }
  }

  Color get accentColor {
    switch (this) {
      case CompositionMode.goldenRatio:
        return const Color(0xFFFFD54F);
      case CompositionMode.ruleOfThirds:
        return const Color(0xFF4FC3F7);
    }
  }
}
