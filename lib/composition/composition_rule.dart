import 'package:flutter/material.dart';

/// 사용자가 선택 가능한 구도 규칙의 종류.
///
/// 풍경 전용 자동 감지인 `CompositionMode`(lib/segmentation/composition_resolver.dart)
/// 와는 별개 개념이다. 이 enum은 인물/객체 모드에서 사용자가 수동 선택하는 구도.
enum CompositionRuleType {
  /// 격자 없음 (기본값).
  none,

  /// 3분할.
  ruleOfThirds,

  /// 황금비 (1:1.618 → 0.382 / 0.618 지점).
  goldenRatio,

  /// 대각선 구도.
  diagonal,

  /// 중앙 정렬 (십자 + 원).
  centerWeighted,
}

/// 사용자 선택형 구도 규칙의 인터페이스.
///
/// 구현체는 세 가지 책임을 가진다:
/// 1. **표시** — [paintOverlay]로 카메라 프리뷰 위에 격자/가이드를 그린다.
/// 2. **평가** — [scoreAlignment]로 피사체 중심이 규칙에 얼마나 맞는지 0~1로 반환.
/// 3. **피드백** — [guidance]로 해당 위치에 대한 한글 안내 문구를 제공.
///
/// 좌표계는 모두 [paintOverlay]에 전달된 bounds를 기준으로 0~1 normalize된 값을 쓴다.
abstract class CompositionRule {
  const CompositionRule();

  CompositionRuleType get type;

  /// UI에 표시되는 한글 라벨 ("3분할", "황금비", ...).
  String get label;

  /// 상단 selector 칩에 쓰일 아이콘.
  IconData get icon;

  /// [bounds] 영역 내부에 규칙 격자/가이드를 그린다.
  void paintOverlay(
    Canvas canvas,
    Rect bounds, {
    required Color color,
    double strokeWidth = 1.0,
  });

  /// 피사체 중심(bounds normalized 0~1 좌표)이 이 규칙에 얼마나 정렬됐는지.
  ///
  /// 1.0 = 완벽 정렬, 0.0 = 매우 멀다.
  double scoreAlignment(Offset subjectCenter, {Size? subjectSize});

  /// 현재 [subjectCenter]에 대한 한글 코칭 안내.
  String guidance(Offset subjectCenter);
}
