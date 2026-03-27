import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  static String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  static const _model = 'gemini-3-pro-image-preview';
  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  Future<Uint8List?> editImage({
    required Uint8List imageBytes,
    required String prompt,
  }) async {
    debugPrint('[GeminiService] editImage 시작');
    debugPrint('[GeminiService] 프롬프트: $prompt');
    debugPrint('[GeminiService] 이미지 크기: ${imageBytes.lengthInBytes} bytes');

    final base64Image = base64Encode(imageBytes);
    debugPrint('[GeminiService] base64 인코딩 완료: ${base64Image.length} chars');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
            },
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
      },
    });

    debugPrint('[GeminiService] 요청 body 크기: ${body.length} chars');
    debugPrint('[GeminiService] API 호출 중... URL: $_baseUrl');

    final response = await http.post(
      Uri.parse('$_baseUrl?key=$_apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    debugPrint('[GeminiService] 응답 statusCode: ${response.statusCode}');
    debugPrint(
      '[GeminiService] 응답 body (앞 1000자): ${response.body.length > 1000 ? response.body.substring(0, 1000) : response.body}',
    );

    if (response.statusCode != 200) {
      debugPrint('[GeminiService] 오류 응답 전체: ${response.body}');
      throw Exception('Gemini API 오류: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('[GeminiService] 응답 JSON 최상위 키: ${json.keys.toList()}');

    final candidates = json['candidates'] as List<dynamic>?;
    debugPrint('[GeminiService] candidates 수: ${candidates?.length ?? 0}');

    if (candidates == null || candidates.isEmpty) {
      debugPrint('[GeminiService] candidates 없음 → null 반환');
      return null;
    }

    debugPrint(
      '[GeminiService] candidates[0] 키: ${(candidates[0] as Map).keys.toList()}',
    );

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    debugPrint('[GeminiService] content: $content');

    final parts = (content?['parts'] as List<dynamic>?) ?? [];
    debugPrint('[GeminiService] parts 수: ${parts.length}');

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i] as Map<String, dynamic>;
      debugPrint('[GeminiService] parts[$i] 키: ${part.keys.toList()}');

      if (part.containsKey('text')) {
        debugPrint('[GeminiService] parts[$i] text: ${part['text']}');
      }

      final inlineData = (part['inline_data'] ?? part['inlineData'])
          as Map<String, dynamic>?;
      if (inlineData != null) {
        final mimeType = inlineData['mime_type'] ?? inlineData['mimeType'];
        debugPrint(
          '[GeminiService] parts[$i] inlineData mimeType: $mimeType',
        );
        final data = inlineData['data'] as String?;
        debugPrint(
          '[GeminiService] parts[$i] inlineData data 길이: ${data?.length ?? 0}',
        );
        if (data != null) {
          final decoded = base64Decode(data);
          debugPrint(
            '[GeminiService] 이미지 디코딩 성공: ${decoded.lengthInBytes} bytes',
          );
          return decoded;
        }
      }
    }

    debugPrint('[GeminiService] 이미지 파트를 찾지 못함 → null 반환');
    return null;
  }
}
