import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// VLM 전송용 이미지 압축 (compute isolate에서 실행)
Uint8List _resizeForVlm(Uint8List jpegBytes) {
  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) return jpegBytes;
  final resized = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: 640)
      : img.copyResize(decoded, height: 640);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}

/// Gemini REST API 기반 구도 분석 서비스.
/// 피사체 종류와 무관하게 사진 전체의 품질을 코칭.
class VlmCompositionService {
  static const _apiKey = 'REMOVED_API_KEY';
  static const _model = 'gemini-2.5-flash-lite';
  static const _url =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey';

  /// 뷰파인더 프레임을 보고 구도 개선 안내를 요청.
  /// 반환값: null이면 기존 코칭 텍스트 유지.
  Future<({String guidance, String subGuidance})?> refine(
    List<int> jpegBytes,
  ) async {
    final prompt = '''
당신은 사진을 잘 찍는 친구입니다. 지금 이 뷰파인더 화면을 보고 딱 하나만 짚어주세요.

★ 중요한 전제:
- "피사체"라는 단어를 절대 사용하지 마세요
- 모든 안내는 카메라를 어떻게 움직일지, 또는 화면에서 무엇이 문제인지로만 표현하세요
- 사용자가 지금 당장 5초 안에 따라할 수 있는 것만 안내하세요

★ 아래 기준으로 판단하세요 (우선순위 순):

1. 프레이밍과 크기
   - 담으려는 대상이 화면 한쪽으로 심하게 치우쳐 있는가
   - 대상이 너무 작아 존재감이 없는가
   - 너무 가까워서 전체 형태가 잘리는가

2. 수평
   - 화면이 눈에 띄게 기울어져 있는가

3. 엣지 — 매우 엄격하게 판단 (아래 조건 모두 충족 시에만)
   - 화면 가장자리에 명백히 의도치 않은 신체 일부(손·팔·머리)나 큰 물체가 잘려 있는가
   - 배경이 복잡하거나 자연스러운 장면의 일부라면 엣지로 판단하지 말 것
   - 애매하면 엣지 지적 하지 말 것

4. 노출 (밝기) — 아주 명백할 때만
   - 화면 전체가 거의 보이지 않을 정도로 어두운가 → "플래시를 켜고 찍어보세요"
   - 역광으로 중심부가 완전히 어두운가 → "플래시를 켜면 더 밝게 찍혀요"
   - 화면 대부분이 하얗게 날아가는가 → "조금 더 밝은 곳으로 이동해보세요"
   ※ 조금 어둡거나 애매한 경우는 밝기 지적 하지 말 것
   ※ 빛의 방향, 측면광, 창가 이동 같은 안내는 하지 마세요 (실시간 대응 불가)

★ 판단 원칙:
- 명확한 문제(프레이밍·수평·엣지·밝기)가 없으면 → "이 정도면 찍어봐도 좋아요!" + subGuidance에 작은 팁
- 눈에 띄는 문제가 하나라도 있으면 → 그것만 짚어주세요
- "이 정도면 찍어봐도 좋아요!"를 쓸 때도 subGuidance에는 반드시 작은 개선 팁을 적어주세요 (없으면 "지금 바로 찍어보세요 📸")

★ 금지 규칙:
- "피사체", "구도를 조정", "앵글 변경" 같은 모호한 말 절대 금지
- guidance 20자 이내

★ 좋은 예시:
- guidance: "이 정도면 찍어봐도 좋아요!" / subGuidance: "위쪽 여백을 조금 더 주면 완벽해요"
- guidance: "이 정도면 찍어봐도 좋아요!" / subGuidance: "플래시 켜면 더 선명하게 나와요"
- guidance: "플래시를 켜고 찍어보세요" / subGuidance: "전체적으로 좀 어둡게 나오고 있어요"
- guidance: "카메라를 왼쪽으로 틀어보세요" / subGuidance: "화면 오른쪽에 너무 치우쳐 있어요"
- guidance: "조금 더 가까이 다가가볼까요?" / subGuidance: "화면 속 대상이 너무 작아요"
- guidance: "한 발 뒤로 물러나볼까요?" / subGuidance: "너무 가까워서 전체가 잘리고 있어요"

JSON으로만 응답 (다른 텍스트 없이):
{"guidance":"핵심 메시지(20자 이내)","subGuidance":"구체적 이유나 방법(30자 이내)"}
''';

    final smallBytes = await compute(
      _resizeForVlm,
      Uint8List.fromList(jpegBytes),
    );

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inlineData': {
                'mimeType': 'image/jpeg',
                'data': base64Encode(smallBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'thinkingConfig': {'thinkingBudget': 0},
      },
    });

    try {
      final response = await http
          .post(
            Uri.parse(_url),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[VLM refine] HTTP ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      String text = '';
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'] as Map?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          text = (parts[0]['text'] as String?) ?? '';
        }
      }
      debugPrint('[VLM refine] raw: $text');

      final match = RegExp(r'\{[^}]+\}').firstMatch(text);
      if (match == null) return null;
      final map = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final guidance = map['guidance'] as String?;
      final subGuidance = map['subGuidance'] as String?;
      if (guidance == null) return null;
      return (guidance: guidance, subGuidance: subGuidance ?? '');
    } catch (e) {
      debugPrint('[VLM refine] exception: $e');
      return null;
    }
  }
}
