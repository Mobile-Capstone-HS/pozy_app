import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/photo_spot.dart';

class SpotThemeRule {
  final List<String> queries;
  final List<String> preferredTitleTokens;
  final List<String> verificationTokens;
  final List<String> excludeTokens;

  const SpotThemeRule({
    required this.queries,
    required this.preferredTitleTokens,
    this.verificationTokens = const [],
    this.excludeTokens = const [],
  });

  factory SpotThemeRule.fromJson(Map<String, dynamic> json) {
    return SpotThemeRule(
      queries: _readStrings(json['queries']),
      preferredTitleTokens: _readStrings(json['preferredTitleTokens']),
      verificationTokens: _readStrings(json['verificationTokens']),
      excludeTokens: _readStrings(json['excludeTokens']),
    );
  }

  bool matchesTitle(String title) {
    return preferredTitleTokens.any(title.contains) ||
        queries.any(title.contains);
  }

  bool matchesOverview(String overview) {
    return verificationTokens.any(overview.contains);
  }

  bool excludes(String text) => excludeTokens.any(text.contains);

  static List<String> _readStrings(Object? value) {
    if (value is! List) return const [];
    return value
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }
}

class SpotThemeRuleService {
  static const _assetPath = 'assets/config/spot_theme_rules.json';

  Future<Map<SpotCategory, SpotThemeRule>>? _cache;

  Future<Map<SpotCategory, SpotThemeRule>> loadRules() {
    return _cache ??= _loadRules();
  }

  Future<Map<SpotCategory, SpotThemeRule>> _loadRules() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final rules = <SpotCategory, SpotThemeRule>{};

    for (final entry in decoded.entries) {
      final category = _categoryByName(entry.key);
      if (category == null || entry.value is! Map) continue;
      rules[category] = SpotThemeRule.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return rules;
  }

  SpotCategory? _categoryByName(String name) {
    for (final category in SpotCategory.values) {
      if (category.name == name) return category;
    }
    return null;
  }
}
