import 'package:flutter/material.dart';

enum SceneType { unknown, person, food, object }

extension SceneTypeX on SceneType {
  String get label {
    switch (this) {
      case SceneType.unknown:
        return '미정';
      case SceneType.person:
        return '사람';
      case SceneType.food:
        return '음식';
      case SceneType.object:
        return '사물';
    }
  }

  String get debugLabel {
    switch (this) {
      case SceneType.unknown:
        return 'UNKNOWN';
      case SceneType.person:
        return 'PERSON';
      case SceneType.food:
        return 'FOOD';
      case SceneType.object:
        return 'OBJECT';
    }
  }

  IconData get icon {
    switch (this) {
      case SceneType.unknown:
        return Icons.help_outline_rounded;
      case SceneType.person:
        return Icons.person_rounded;
      case SceneType.food:
        return Icons.restaurant_rounded;
      case SceneType.object:
        return Icons.category_rounded;
    }
  }

  Color get accentColor {
    switch (this) {
      case SceneType.unknown:
        return Colors.white54;
      case SceneType.person:
        return const Color(0xFF00E676);
      case SceneType.food:
        return const Color(0xFFFFB74D);
      case SceneType.object:
        return const Color(0xFFB39DDB);
    }
  }
}
