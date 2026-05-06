import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

String _resolveApiKey() {
  final runtimeKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  if (runtimeKey.isNotEmpty) return runtimeKey;
  return const String.fromEnvironment('GEMINI_API_KEY');
}

const _kGeminiModel = 'gemini-3-pro-image-preview';
const _kBaseUrl =
    'https://generativelanguage.googleapis.com/v1beta/models/$_kGeminiModel:generateContent';

// ---------------------------------------------------------------------------
// Explanation-only Gemini service.
// Receives pre-computed scores from the on-device pipeline and generates
// structured explanation text. Scores are NOT re-computed here.
// ---------------------------------------------------------------------------

/// Structured explanation returned by [GeminiExplanationService].
class GeminiExplanation {
  const GeminiExplanation({
    this.commentType,
    required this.shortReason,
    required this.detailedReason,
    this.comparisonReason,
  });

  final String? commentType;

  /// One-sentence summary (map: short_reason).
  final String shortReason;

  /// Multi-sentence expert analysis (map: detailed_reason).
  final String detailedReason;

  /// Comparison context — only populated when rank is provided (map: comparison_reason).
  final String? comparisonReason;
}

/// Calls Gemini with the image and pre-computed scores to generate a
/// human-readable explanation.  Does NOT produce or modify scores.
class GeminiExplanationService {
  static String get _apiKey => _resolveApiKey();
  static const _baseUrl = _kBaseUrl;

  /// [rank] and [totalCount] are optional. When provided, Gemini can
  /// generate a [GeminiExplanation.comparisonReason].
  Future<GeminiExplanation?> explain({
    required Uint8List imageBytes,
    required double technicalScore,
    required double finalScore,
    double? aestheticScore,
    int? rank,
    int? totalCount,
  }) async {
    try {
      final prompt = _buildPrompt(
        technicalScore: technicalScore,
        aestheticScore: aestheticScore,
        finalScore: finalScore,
        rank: rank,
        totalCount: totalCount,
      );

      return await explainFromPrompt(prompt: prompt, imageBytes: imageBytes);
    } catch (e) {
      debugPrint('[GeminiExplanationService] 에러 발생: $e');
      return null;
    }
  }

  Future<GeminiExplanation?> explainFromPrompt({
    required String prompt,
    Uint8List? imageBytes,
  }) async {
    final parts = <Map<String, dynamic>>[
      {'text': prompt},
    ];
    if (imageBytes != null && imageBytes.isNotEmpty) {
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': base64Encode(imageBytes),
        },
      });
    }

    final body = jsonEncode({
      'contents': [
        {'parts': parts},
      ],
      'generationConfig': {
        'responseModalities': ['TEXT'],
      },
    });

    final response = await http.post(
      Uri.parse('$_baseUrl?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      debugPrint('[GeminiExplanationService] API 오류: ${response.statusCode}');
      return null;
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = json['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final contentParts = (content?['parts'] as List<dynamic>?) ?? [];
    var rawText = '';
    for (final part in contentParts) {
      if ((part as Map).containsKey('text')) rawText += part['text'];
    }

    rawText = _stripMarkdownFence(rawText);
    final parsed = jsonDecode(rawText) as Map<String, dynamic>;

    final shortReason = (parsed['short_reason'] as String? ?? '').trim();
    final detailedReason = (parsed['detailed_reason'] as String? ?? '').trim();
    final comparisonReason = (parsed['comparison_reason'] as String?)?.trim();
    final commentType = (parsed['comment_type'] as String?)?.trim();

    if (shortReason.isEmpty && detailedReason.isEmpty) return null;

    return GeminiExplanation(
      commentType: commentType?.isNotEmpty == true ? commentType : null,
      shortReason: shortReason,
      detailedReason: detailedReason,
      comparisonReason: comparisonReason?.isNotEmpty == true
          ? comparisonReason
          : null,
    );
  }

  String _stripMarkdownFence(String rawText) {
    var normalized = rawText.trim();
    if (normalized.startsWith('```json')) {
      normalized = normalized.substring(7);
    } else if (normalized.startsWith('```')) {
      normalized = normalized.substring(3);
    }
    if (normalized.endsWith('```')) {
      normalized = normalized.substring(0, normalized.length - 3);
    }
    return normalized.trim();
  }

  String _buildPrompt({
    required double technicalScore,
    required double finalScore,
    double? aestheticScore,
    int? rank,
    int? totalCount,
  }) {
    final techPct = (technicalScore * 100).round();
    final finalPct = (finalScore * 100).round();

    // Build score lines without embedded newlines so template layout is stable.
    final scoreLines = [
      '- 기술 점수 (초점·노출·선예도): $techPct/100',
      if (aestheticScore != null)
        '- 미적 점수 (구도·색감·분위기): ${(aestheticScore * 100).round()}/100',
      '- 종합 점수: $finalPct/100',
      if (rank != null && totalCount != null) '- 순위: $rank위 / 전체 $totalCount장',
    ];

    return '''
아래 사진에는 이미 계산된 품질 점수가 제공됩니다.
당신의 역할은 점수를 다시 계산하는 것이 아니라, 입력 점수와 일관된 설명을 생성하는 것입니다.
점수를 새로 계산, 수정, 보정, 재해석하지 마세요.
제공된 점수와 일관된 설명만 작성하세요.

[이미 계산된 점수 — 수정 불가]
${scoreLines.join('\n')}

마크다운 없이 JSON만 출력하세요:
{
  "short_reason": "<이 사진의 핵심 특성 한 문장>",
  "detailed_reason": "<위 점수와 일관된 조명·구도·색감·피사체 분석 3~4문장>",
  "comparison_reason": ${rank != null ? '"<다른 컷 대비 강점·약점 한 문장>"' : 'null'}
}''';
  }
}
