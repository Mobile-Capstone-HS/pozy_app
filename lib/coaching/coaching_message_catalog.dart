import 'coaching_result.dart';

enum ObjectCoachingSignal {
  noSubject,
  clippedSubject,
  tooClose,
  tiltStrong,
  tiltMild,
  blur,
  dark,
  overexposed,
  backlight,
  smallSubject,
  ruleImbalance,
  leftImbalance,
  rightImbalance,
  tightFraming,
  shootReady,
  goodEnough,
  neutral,
}

class CoachingMessageSpec {
  final String guidance;
  final String? subGuidance;
  final CoachingLevel level;
  final DirectionHint directionHint;
  final LightDirection lightDirection;

  const CoachingMessageSpec({
    required this.guidance,
    required this.level,
    this.subGuidance,
    this.directionHint = DirectionHint.none,
    this.lightDirection = LightDirection.unknown,
  });
}

class CoachingMessageCatalog {
  const CoachingMessageCatalog._();

  static CoachingMessageSpec object(
    ObjectCoachingSignal signal, {
    LightDirection lightDirection = LightDirection.unknown,
    String? ruleLabel,
    String? ruleGuidance,
  }) {
    switch (signal) {
      case ObjectCoachingSignal.noSubject:
        return const CoachingMessageSpec(
          guidance: '피사체를 화면 안에 담아보세요',
          subGuidance: '인식되면 밝기, 수평, 구도를 기준으로 코칭할게요',
          level: CoachingLevel.caution,
        );
      case ObjectCoachingSignal.clippedSubject:
        return const CoachingMessageSpec(
          guidance: '피사체가 화면에서 잘리고 있어요',
          subGuidance: '피사체 전체가 보이도록 조금 뒤로 가거나 프레임 안쪽으로 옮겨보세요',
          level: CoachingLevel.warning,
          directionHint: DirectionHint.back,
        );
      case ObjectCoachingSignal.tooClose:
        return const CoachingMessageSpec(
          guidance: '고정한 피사체가 너무 가까워요',
          subGuidance: '피사체가 답답하지 않게 보이도록 조금 뒤로 가서 여백을 만들어보세요',
          level: CoachingLevel.caution,
          directionHint: DirectionHint.back,
        );
      case ObjectCoachingSignal.tiltStrong:
        return const CoachingMessageSpec(
          guidance: '화면이 많이 기울어졌어요',
          subGuidance: '수평을 맞춘 뒤 다시 담아보세요',
          level: CoachingLevel.warning,
        );
      case ObjectCoachingSignal.tiltMild:
        return const CoachingMessageSpec(
          guidance: '조금만 수평을 맞춰보세요',
          subGuidance: '기울기를 줄이면 사진이 더 안정적으로 보여요',
          level: CoachingLevel.caution,
        );
      case ObjectCoachingSignal.blur:
        return const CoachingMessageSpec(
          guidance: '화면이 흐릿해요',
          subGuidance: '잠시 멈추고 초점과 흔들림을 확인해보세요',
          level: CoachingLevel.warning,
        );
      case ObjectCoachingSignal.dark:
        return CoachingMessageSpec(
          guidance: '장면이 어두워요',
          subGuidance: lightDirection == LightDirection.behind
              ? '역광에서는 빛을 등지고 촬영해보세요'
              : '조명을 켜거나 더 밝은 곳으로 이동해보세요',
          level: CoachingLevel.warning,
          lightDirection: lightDirection,
        );
      case ObjectCoachingSignal.overexposed:
        return CoachingMessageSpec(
          guidance: '빛이 너무 강해요',
          subGuidance: _lightSubGuidance(lightDirection, '각도나 위치를 조금 바꿔보세요'),
          level: CoachingLevel.warning,
          lightDirection: lightDirection,
        );
      case ObjectCoachingSignal.backlight:
        return const CoachingMessageSpec(
          guidance: '역광이 감지됐어요',
          subGuidance: '빛이 뒤에서 들어오고 있어요. 방향을 조금 바꿔보세요',
          level: CoachingLevel.warning,
          lightDirection: LightDirection.behind,
        );
      case ObjectCoachingSignal.smallSubject:
        return const CoachingMessageSpec(
          guidance: '조금 더 가까이 담아도 좋아요',
          subGuidance: '피사체가 더 또렷하게 보여요',
          level: CoachingLevel.caution,
          directionHint: DirectionHint.closer,
        );
      case ObjectCoachingSignal.ruleImbalance:
        return CoachingMessageSpec(
          guidance: '${ruleLabel ?? '선택한'} 구도에 맞춰보세요',
          subGuidance: ruleGuidance,
          level: CoachingLevel.caution,
        );
      case ObjectCoachingSignal.leftImbalance:
        return const CoachingMessageSpec(
          guidance: '구도가 왼쪽으로 치우쳐 있어요',
          subGuidance: '카메라를 조금 오른쪽으로 옮겨보세요',
          level: CoachingLevel.caution,
          directionHint: DirectionHint.right,
        );
      case ObjectCoachingSignal.rightImbalance:
        return const CoachingMessageSpec(
          guidance: '구도가 오른쪽으로 치우쳐 있어요',
          subGuidance: '카메라를 조금 왼쪽으로 옮겨보세요',
          level: CoachingLevel.caution,
          directionHint: DirectionHint.left,
        );
      case ObjectCoachingSignal.tightFraming:
        return const CoachingMessageSpec(
          guidance: '조금 더 넓게 담아도 좋아요',
          subGuidance: '여백이 생기면 장면이 더 편안해 보여요',
          level: CoachingLevel.caution,
          directionHint: DirectionHint.back,
        );
      case ObjectCoachingSignal.shootReady:
        return const CoachingMessageSpec(
          guidance: '지금 찍기 좋아요',
          subGuidance: '현재 구도가 안정적이에요',
          level: CoachingLevel.good,
        );
      case ObjectCoachingSignal.goodEnough:
        return const CoachingMessageSpec(
          guidance: '지금 찍어도 좋아요',
          subGuidance: '현재 장면이 비교적 안정적이에요',
          level: CoachingLevel.good,
        );
      case ObjectCoachingSignal.neutral:
        return const CoachingMessageSpec(
          guidance: '현재 장면이 무난해요',
          subGuidance: '원하는 느낌에 맞게 각도만 조금 조정해보세요',
          level: CoachingLevel.caution,
        );
    }
  }

  static String _lightSubGuidance(LightDirection dir, String fallback) {
    return switch (dir) {
      LightDirection.left ||
      LightDirection.right ||
      LightDirection.top => fallback,
      LightDirection.behind => '뒤쪽 빛을 피해서 방향을 조금 바꿔보세요',
      _ => fallback,
    };
  }
}
