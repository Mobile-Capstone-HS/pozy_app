import 'dart:convert';

import 'photo_explanation_service.dart';

class OnDeviceGemmaPromptPayload {
  const OnDeviceGemmaPromptPayload({
    required this.promptVersion,
    required this.promptMode,
    required this.prompt,
    required this.promptChars,
    required this.facts,
    required this.inputJson,
  });

  final String promptVersion;
  final String promptMode;
  final String prompt;
  final int promptChars;
  final Map<String, dynamic> facts;
  final String inputJson;
}

class AcutCommentPromptBuilder {
  static const String promptVersion = 'production_v2';
  static const String compactGemmaPromptVersion =
      'production_v2_compact_rewrite';
  static const String compactGemmaPromptMode = 'compact_rewrite';
  static const String visualGemmaPromptVersion = 'production_v2_gemma_vlm';
  static const String visualGemmaPromptMode = 'visual_image_context';

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
  - final_score >= 80 이면 "selected_explanation"
  - 60 <= final_score < 80 이면 "near_miss_feedback"
  - final_score < 60 이면 "rejection_reason"
- short_reason: 한 문장
- detailed_reason: 2~4문장, 기술/미적 점수와 일관되게
- comparison_reason: 순위 정보가 있을 때만 작성, 없으면 null
- 사진에 보이지 않는 내용은 단정하지 마세요.
- 점수와 모순되는 칭찬이나 비판은 금지합니다.

출력 JSON 스키마:
{
  "comment_type": "<selected_explanation|near_miss_feedback|rejection_reason>",
  "short_reason": "<핵심 한 문장>",
  "detailed_reason": "<세부 설명 2~4문장>",
  "comparison_reason": $comparisonRule
}''';
  }

  static OnDeviceGemmaPromptPayload buildCompactOnDeviceGemmaPrompt(
    PhotoExplanationRequest request, {
    required String modelPath,
  }) {
    final facts = _buildCompactFacts(request);
    final prompt = _buildCompactGemmaPromptText(facts);
    final inputJson = jsonEncode({
      'model_path': modelPath,
      'prompt_version': compactGemmaPromptVersion,
      'prompt_mode': compactGemmaPromptMode,
      'default_comment_type': request.defaultCommentType,
      'prompt': prompt,
      'prompt_chars': prompt.length,
      'facts': facts,
      'request': request.toDebugJson(),
    });

    return OnDeviceGemmaPromptPayload(
      promptVersion: compactGemmaPromptVersion,
      promptMode: compactGemmaPromptMode,
      prompt: prompt,
      promptChars: prompt.length,
      facts: facts,
      inputJson: inputJson,
    );
  }

  static OnDeviceGemmaPromptPayload buildVisualOnDeviceGemmaPrompt(
    PhotoExplanationRequest request, {
    required String modelPath,
  }) {
    final scoreLines = _buildScoreLines(request);
    final comparisonRule = request.rank != null && request.totalCount != null
        ? '"<같은 세트 안에서의 상대적 강점/약점 한 문장>"'
        : 'null';
    final prompt =
        '''당신은 사진 A-cut 추천 앱의 설명 작성기입니다.
먼저 이미지를 관찰하고, 그 다음 점수와 일치하는 설명을 작성하세요.
점수는 앱이 이미 계산한 값이므로 수정하거나 다시 계산하지 마세요.

가장 중요한 규칙:
점수 단어만 반복하지 마세요.
"기술 품질이 안정적", "미적 요소가 부족", "개선의 여지" 같은 일반 문장은 금지합니다.
반드시 사진에서 실제로 보이는 구체 요소를 최소 2개 이상 언급하세요.

먼저 내부적으로 다음을 확인하세요.
- 주요 피사체가 무엇인지
- 피사체가 화면 어디에 있는지
- 초점/흔들림/노출 상태가 어떤지
- 배경이 단순한지 복잡한지
- 구도가 안정적인지, 기울어짐/반전/잘림이 있는지
- 색감이나 빛이 사진 분위기에 어떤 영향을 주는지

단, 출력 JSON에는 observation 필드를 만들지 마세요.
위 관찰을 바탕으로 short_reason과 detailed_reason 안에 자연스럽게 녹여 쓰세요.

[입력 점수 - 수정 불가]
${scoreLines.join('\n')}

[판정 규칙]
- final_score >= 80 이면 comment_type은 "selected_explanation"
- 60 <= final_score < 80 이면 comment_type은 "near_miss_feedback"
- final_score < 60 이면 comment_type은 "rejection_reason"

[작성 규칙]
- 답변은 반드시 한국어 JSON 한 개만 출력하세요.
- 마크다운, 코드블록, JSON 밖 설명은 금지합니다.
- short_reason은 사진에서 보이는 핵심 특징을 포함한 한 문장으로 작성하세요.
- detailed_reason은 정확히 2문장으로 작성하세요.
- 첫 번째 문장은 사진에서 보이는 기술적 근거를 작성하세요.
  예: 피사체 초점, 노출, 선명도, 흔들림, 노이즈, 얼굴/주요 피사체 포착 상태.
- 두 번째 문장은 사진에서 보이는 미적 근거와 보완 방향을 작성하세요.
  예: 구도, 배경 복잡도, 시선 집중도, 색감, 빛, 기울어짐, 반전, 잘림.
- near_miss_feedback이면 두 번째 문장에 보완 방향을 포함하세요.
- 사진에 보이지 않는 내용은 단정하지 마세요.
- 점수와 모순되는 칭찬이나 비판은 금지합니다.
- comparison_reason은 순위/비교 정보가 없으면 null로 출력하세요.
- 같은 표현을 반복하지 마세요.

[금지 문장]
아래 표현은 단독으로 사용하지 마세요.
- "전반적인 기술 품질은 안정적입니다"
- "미적 요소에서 개선의 여지가 있습니다"
- "더 좋은 결과물을 만들 수 있습니다"
- "기본 완성도는 있습니다"
- "선예도와 전반적인 기술 품질은 안정적입니다"

출력 JSON 스키마:
{
  "comment_type": "<selected_explanation|near_miss_feedback|rejection_reason>",
  "short_reason": "<사진에서 보이는 핵심 특징과 판정 한 문장>",
  "detailed_reason": "<기술적 관찰 1문장 + 미적 관찰/보완 1문장>",
  "comparison_reason": $comparisonRule
}
''';

    final facts = _buildCompactFacts(request);
    final inputJson = jsonEncode({
      'model_path': modelPath,
      'prompt_version': visualGemmaPromptVersion,
      'prompt_mode': visualGemmaPromptMode,
      'default_comment_type': request.defaultCommentType,
      'prompt': prompt,
      'prompt_chars': prompt.length,
      'facts': facts,
      'request': request.toDebugJson(),
    });

    return OnDeviceGemmaPromptPayload(
      promptVersion: visualGemmaPromptVersion,
      promptMode: visualGemmaPromptMode,
      prompt: prompt,
      promptChars: prompt.length,
      facts: facts,
      inputJson: inputJson,
    );
  }

  static String buildGemmaInputJson(
    PhotoExplanationRequest request, {
    required String modelPath,
  }) {
    return buildCompactOnDeviceGemmaPrompt(
      request,
      modelPath: modelPath,
    ).inputJson;
  }

  static Map<String, dynamic> _buildCompactFacts(
    PhotoExplanationRequest request,
  ) {
    final commentType = request.defaultCommentType;
    final aestheticPct = request.aestheticPct;
    final verdict = _cleanFactText(request.verdict);
    final hint = _cleanFactText(request.primaryHint);
    final qualitySummary = _cleanFactText(request.qualitySummary);
    final facts = <String, dynamic>{
      'comment_type': commentType,
      'selection_state': request.selectionState,
      'final_score': request.finalPct,
      'technical_score': request.technicalPct,
      'core_reasons': _buildReasonFacts(request, commentType),
    };

    if (aestheticPct != null) {
      facts['aesthetic_score'] = aestheticPct;
    }
    if (verdict != null) {
      facts['verdict'] = verdict;
    }
    if (request.usesTechnicalScoreAsFinal == true) {
      facts['evaluation_mode'] = 'technical_fallback';
    }
    if (hint != null) {
      facts['hint'] = hint;
    }
    if (qualitySummary != null) {
      facts['quality_summary'] = qualitySummary;
    }

    return facts;
  }

  static List<String> _buildScoreLines(PhotoExplanationRequest request) {
    return <String>[
      '- final_score: ${request.finalPct}/100',
      '- technical_score: ${request.technicalPct}/100',
      if (request.aestheticPct != null)
        '- aesthetic_score: ${request.aestheticPct}/100',
      '- selection_state: ${request.selectionState}',
      if (request.rank != null && request.totalCount != null)
        '- rank: ${request.rank}/${request.totalCount}',
      if (request.fileName != null) '- file_name: ${request.fileName}',
      if (_cleanFactText(request.verdict) != null)
        '- verdict: ${_cleanFactText(request.verdict)}',
      if (_cleanFactText(request.primaryHint) != null)
        '- hint: ${_cleanFactText(request.primaryHint)}',
      if (_cleanFactText(request.qualitySummary) != null)
        '- quality_summary: ${_cleanFactText(request.qualitySummary)}',
    ];
  }

  static List<String> _buildReasonFacts(
    PhotoExplanationRequest request,
    String commentType,
  ) {
    final reasons = <String>[
      switch (commentType) {
        'selected_explanation' => 'A-cut으로 선택할 만큼 전체 완성도가 높음',
        'rejection_reason' => '선택 후보로 보기 어려운 약점이 큼',
        _ => '기본 완성도는 있으나 A-cut으로 확정할 핵심 강점이 약함',
      },
    ];

    final technicalScore = request.technicalScore;
    final aestheticScore =
        request.finalAestheticScore ?? request.aestheticScore;
    if (_isNormalizedScore(technicalScore) &&
        (aestheticScore == null || _isNormalizedScore(aestheticScore))) {
      if (aestheticScore == null) {
        if (technicalScore >= 0.75) {
          reasons.add('기술 품질은 전반적으로 안정적임');
        } else if (technicalScore < 0.60) {
          reasons.add('기술 품질에서 분명한 아쉬움이 있음');
        }
      } else if (technicalScore >= 0.75 && aestheticScore >= 0.75) {
        reasons.add('기술 품질과 미적 구성이 모두 안정적임');
      } else if (technicalScore >= 0.75 && aestheticScore < 0.60) {
        reasons.add('기술 품질은 안정적이지만 미적 완성도가 약함');
      } else if (technicalScore < 0.60 && aestheticScore >= 0.75) {
        reasons.add('미적 인상은 괜찮지만 기술 품질이 아쉬움');
      } else if (technicalScore < 0.60 && aestheticScore < 0.60) {
        reasons.add('기술 품질과 미적 완성도 모두 약함');
      } else {
        reasons.add('기술 품질과 미적 인상은 대체로 무난함');
      }
    }

    if (request.usesTechnicalScoreAsFinal == true) {
      reasons.add('현재 평가는 기술 점수 중심으로 계산됨');
    }

    return reasons.take(3).toList(growable: false);
  }

  static String _buildCompactGemmaPromptText(Map<String, dynamic> facts) {
    return '''
facts는 앱이 이미 계산한 결과다. 너는 이미지를 보지 않는다.
facts 밖의 내용을 invent하지 마라.
아래 facts를 바탕으로 한국어 JSON 한 개만 출력하라.
- comment_type은 facts.comment_type 그대로 사용
- short_reason: 한국어 1문장, 35자 이내
- detailed_reason: 한국어 1문장, 80자 이내
- comparison_reason: null
- JSON 외 문장 금지
- 마크다운 코드블록 금지
- 같은 문장 반복 금지
- 과장 금지
- facts에 없는 이미지 내용 언급 금지
facts=${jsonEncode(facts)}
출력형식={"comment_type":"selected_explanation | near_miss_feedback | rejection_reason","short_reason":"...","detailed_reason":"...","comparison_reason":null}''';
  }

  static String? _cleanFactText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.length <= 80 ? trimmed : trimmed.substring(0, 80);
  }

  static bool _isNormalizedScore(double value) => value >= 0.0 && value <= 1.0;
}
