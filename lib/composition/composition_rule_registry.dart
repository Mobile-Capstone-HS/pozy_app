import 'composition_rule.dart';
import 'rules/center_weighted_rule.dart';
import 'rules/diagonal_rule.dart';
import 'rules/golden_ratio_rule.dart';
import 'rules/none_rule.dart';
import 'rules/rule_of_thirds.dart';

/// [CompositionRuleType] → [CompositionRule] 인스턴스 조회.
///
/// 모든 rule은 const 싱글톤으로 유지된다. 사용처에서 `CompositionRuleRegistry.of(type)`
/// 로 가져와 쓴다.
abstract final class CompositionRuleRegistry {
  static const _instances = <CompositionRuleType, CompositionRule>{
    CompositionRuleType.none: NoneRule(),
    CompositionRuleType.ruleOfThirds: RuleOfThirds(),
    CompositionRuleType.goldenRatio: GoldenRatioRule(),
    CompositionRuleType.diagonal: DiagonalRule(),
    CompositionRuleType.centerWeighted: CenterWeightedRule(),
  };

  /// 모든 규칙을 순회할 때 사용할 enum 순서. UI selector의 표시 순서와 동일.
  static const ordered = <CompositionRuleType>[
    CompositionRuleType.none,
    CompositionRuleType.ruleOfThirds,
    CompositionRuleType.goldenRatio,
    CompositionRuleType.diagonal,
    CompositionRuleType.centerWeighted,
  ];

  /// 지정된 타입의 규칙 인스턴스를 반환.
  static CompositionRule of(CompositionRuleType type) {
    return _instances[type]!;
  }
}
