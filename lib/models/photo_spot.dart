import 'package:flutter/material.dart';

enum SpotCategory { all, cherry, autumn, sunrise, sunset, night, snow }

extension SpotCategoryExt on SpotCategory {
  String get label {
    const labels = {
      SpotCategory.all: '전체',
      SpotCategory.cherry: '벚꽃',
      SpotCategory.autumn: '단풍',
      SpotCategory.sunrise: '일출',
      SpotCategory.sunset: '일몰',
      SpotCategory.night: '야경',
      SpotCategory.snow: '설경',
    };
    return labels[this]!;
  }

  String get emoji {
    const emojis = {
      SpotCategory.all: '📍',
      SpotCategory.cherry: '🌸',
      SpotCategory.autumn: '🍁',
      SpotCategory.sunrise: '🌅',
      SpotCategory.sunset: '🌇',
      SpotCategory.night: '🌃',
      SpotCategory.snow: '❄️',
    };
    return emojis[this]!;
  }

  Color get color {
    const colors = {
      SpotCategory.all: Color(0xFF81D4FA),
      SpotCategory.cherry: Color(0xFFF06292),
      SpotCategory.autumn: Color(0xFFFF7043),
      SpotCategory.sunrise: Color(0xFFFFCA28),
      SpotCategory.sunset: Color(0xFFFF8F00),
      SpotCategory.night: Color(0xFF5C6BC0),
      SpotCategory.snow: Color(0xFF80DEEA),
    };
    return colors[this]!;
  }
}
