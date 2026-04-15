import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../feature/a_cut/layer/evaluation/photo_evaluation_service.dart';
import '../feature/a_cut/model/photo_evaluation_result.dart';

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
// Legacy: full Gemini evaluation (scores + explanation in one call).
// Kept for reference; not wired into the main A-cut flow any more.
// Use HybridPhotoEvaluationService instead.
// ---------------------------------------------------------------------------
class GeminiPhotoEvaluationService implements PhotoEvaluationService {
  static String get _apiKey => _resolveApiKey();

  static const _baseUrl = _kBaseUrl;

  static const _prompt = '''
당신은 전문 사진 평론가입니다. 사진의 구도, 노출, 색감, 피사체 등을 종합적으로 분석하고 다음 JSON 형식으로 응답을 주세요. 마크다운 기호 없이 오직 JSON 텍스트만 출력해야 합니다.
{
  "final_score": <0.0~1.0 사이의 종합 평가 점수. 매우 엄격하게 평가할 것>,
  "technical_score": <0.0~1.0 사이의 기술적 완성도 (초점, 노출 등) 점수>,
  "aesthetic_score": <0.0~1.0 사이의 미적 아름다움 점수>,
  "verdict": "<'매우 좋음', '좋음', '보통', '아쉬움' 중 하나>",
  "notes": ["<사진의 좋은 점 짧게 요약 1>", "<사진의 좋은 점 짧게 요약 2>"],
  "warnings": ["<아쉬운 점 요약 1>", "<아쉬운 점 요약 2>"],
  "detailed_explanation": "<해당 점수를 준 구체적이고 전문적인 이유, 조명/구도/색감/피사체 등에 대한 3~4문장 분량의 상세한 피드백 전문>"
}
''';

  @override
  Future<PhotoEvaluationResult> evaluate(
    Uint8List imageBytes, {
    String? fileName,
  }) async {
    try {
      final base64Image = base64Encode(imageBytes);

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _prompt},
              {
                'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
              },
            ],
          },
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
        throw Exception('Gemini API 오류: ${response.statusCode} ${response.body}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Gemini가 결과를 반환하지 않았습니다.');
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = (content?['parts'] as List<dynamic>?) ?? [];
      String generatedText = '';
      for (final part in parts) {
        if ((part as Map).containsKey('text')) {
          generatedText += part['text'];
        }
      }

      String rawJson = generatedText.trim();
      if (rawJson.startsWith('```json')) {
        rawJson = rawJson.substring(7);
      } else if (rawJson.startsWith('```')) {
        rawJson = rawJson.substring(3);
      }
      if (rawJson.endsWith('```')) {
        rawJson = rawJson.substring(0, rawJson.length - 3);
      }
      rawJson = rawJson.trim();

      final parsed = jsonDecode(rawJson) as Map<String, dynamic>;

      return PhotoEvaluationResult.fromScores(
        finalScore: (parsed['final_score'] as num).toDouble(),
        technicalScore: (parsed['technical_score'] as num).toDouble(),
        aestheticScore: (parsed['aesthetic_score'] as num?)?.toDouble(),
        notes: (parsed['notes'] as List<dynamic>?)?.cast<String>() ?? [],
        warnings: (parsed['warnings'] as List<dynamic>?)?.cast<String>() ?? [],
        detailedExplanation: parsed['detailed_explanation'] as String?,
        fileName: fileName,
        modelVersion: _kGeminiModel,
      );
    } catch (e) {
      debugPrint('[GeminiPhotoEvaluationService] 에러 발생: $e');
      rethrow;
    }
  }
}

// ---------------------------------------------------------------------------
// New: explanation-only Gemini service.
// Receives pre-computed scores from the on-device pipeline and generates
// structured explanation text. Scores are NOT re-computed here.
// ---------------------------------------------------------------------------

/// Structured explanation returned by [GeminiExplanationService].
class GeminiExplanation {
  const GeminiExplanation({
    required this.shortReason,
    required this.detailedReason,
    this.comparisonReason,
  });

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

      final base64Image = base64Encode(imageBytes);
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Image,
                },
              },
            ],
          },
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
        debugPrint(
          '[GeminiExplanationService] API 오류: ${response.statusCode}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = (content?['parts'] as List<dynamic>?) ?? [];
      var rawText = '';
      for (final part in parts) {
        if ((part as Map).containsKey('text')) rawText += part['text'];
      }

      // Strip optional markdown fences
      rawText = rawText.trim();
      if (rawText.startsWith('```json')) {
        rawText = rawText.substring(7);
      } else if (rawText.startsWith('```')) {
        rawText = rawText.substring(3);
      }
      if (rawText.endsWith('```')) {
        rawText = rawText.substring(0, rawText.length - 3);
      }
      rawText = rawText.trim();

      final parsed = jsonDecode(rawText) as Map<String, dynamic>;

      final shortReason = parsed['short_reason'] as String? ?? '';
      final detailedReason = parsed['detailed_reason'] as String? ?? '';
      final comparisonReason = parsed['comparison_reason'] as String?;

      if (shortReason.isEmpty && detailedReason.isEmpty) return null;

      return GeminiExplanation(
        shortReason: shortReason,
        detailedReason: detailedReason,
        comparisonReason:
            (comparisonReason?.isNotEmpty ?? false) ? comparisonReason : null,
      );
    } catch (e) {
      debugPrint('[GeminiExplanationService] 에러 발생: $e');
      return null;
    }
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
    final aestheticLine = aestheticScore != null
        ? '- 미적 점수 (구도·색감·분위기): ${(aestheticScore * 100).round()}/100\n'
        : '';
    final rankLine = (rank != null && totalCount != null)
        ? '- 순위: $rank위 / 전체 $totalCount장\n'
        : '';

    return '''
당신은 전문 사진 평론가입니다.
아래의 기술적 분석 점수를 참고하여, 첨부된 사진에 대한 전문적인 설명을 한국어로 작성해주세요.

[분석 점수]
- 기술 점수 (초점·노출·선예도): $techPct/100
$aestheticLine- 종합 점수: $finalPct/100
$rankLine
마크다운 기호 없이 다음 JSON 형식으로만 응답해주세요:
{
  "short_reason": "<한 문장으로 이 사진의 핵심 특성 요약>",
  "detailed_reason": "<조명·구도·색감·피사체에 대한 3~4문장 전문 분석. 위의 점수와 일관성을 유지할 것>",
  "comparison_reason": ${rank != null ? '"<다른 컷들과 비교했을 때의 강점·약점 한 문장>"' : 'null'}
}''';
  }
}
