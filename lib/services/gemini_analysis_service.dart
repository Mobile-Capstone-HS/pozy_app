import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../feature/a_cut/layer/evaluation/photo_evaluation_service.dart';
import '../feature/a_cut/model/photo_evaluation_result.dart';

class GeminiPhotoEvaluationService implements PhotoEvaluationService {
  static String get _apiKey {
    final runtimeKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (runtimeKey.isNotEmpty) return runtimeKey;
    return const String.fromEnvironment('GEMINI_API_KEY');
  }

  static const _model = 'gemini-3-pro-image-preview';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

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
        modelVersion: _model,
      );
    } catch (e) {
      debugPrint('[GeminiPhotoEvaluationService] 에러 발생: $e');
      rethrow;
    }
  }
}
