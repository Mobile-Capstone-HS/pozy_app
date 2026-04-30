import 'dart:convert';

import 'photo_explanation_service.dart';

class AcutCommentPromptBuilder {
  static const String promptVersion = 'production_v2';

  static String buildProductionV2(
    PhotoExplanationRequest request, {
    required bool includeImageContext,
  }) {
    final scoreLines = <String>[
      '- technical_score: ${(request.technicalScore * 100).round()}/100',
      if (request.aestheticScore != null)
        '- aesthetic_score: ${(request.aestheticScore! * 100).round()}/100',
      '- final_score: ${(request.finalScore * 100).round()}/100',
      if (request.rank != null && request.totalCount != null)
        '- rank: ${request.rank}/${request.totalCount}',
      if (request.fileName != null) '- file_name: ${request.fileName}',
    ];
    final comparisonRule = request.rank != null && request.totalCount != null
        ? '"<같은 세트 안에서의 상대적 강점/약점 한 문장>"'
        : 'null';

    return '''
당신은 사진 A-cut 추천 앱의 설명 작성기입니다.
아래에는 이미 계산된 점수가 제공됩니다.
당신의 역할은 점수를 다시 계산하는 것이 아니라, 주어진 점수와${includeImageContext ? ' 사진 내용' : ' 입력 맥락'}에 일관된 설명을 작성하는 것입니다.
점수를 새로 계산, 수정, 보정하거나 과장하지 마세요.
답변은 반드시 한국어 JSON 한 개만 출력하세요. 마크다운, 코드펜스, 부가 설명은 금지합니다.

[입력 점수 - 수정 불가]
${scoreLines.join('\n')}

[출력 규칙]
- comment_type:
  - final_score >= 80 이면 "strong_pick"
  - 60 <= final_score < 80 이면 "candidate_keep"
  - final_score < 60 이면 "retry_recommended"
- short_reason: 한 문장
- detailed_reason: 2~4문장, 기술/미적 점수와 일관되게
- comparison_reason: 순위 정보가 있을 때만 작성, 없으면 null
- 사진에 보이지 않는 내용은 단정하지 마세요.
- 점수와 모순되는 칭찬이나 비판은 금지합니다.

출력 JSON 스키마:
{
  "comment_type": "<strong_pick|candidate_keep|retry_recommended>",
  "short_reason": "<핵심 한 문장>",
  "detailed_reason": "<세부 설명 2~4문장>",
  "comparison_reason": $comparisonRule
}''';
  }

  static String buildGemmaInputJson(
    PhotoExplanationRequest request, {
    required String modelPath,
  }) {
    return jsonEncode({
      'model_path': modelPath,
      'prompt_version': promptVersion,
      'default_comment_type': acutCommentTypeForScore(request.finalScore),
      'prompt': buildProductionV2(request, includeImageContext: false),
      'request': request.toDebugJson(),
    });
  }
}
