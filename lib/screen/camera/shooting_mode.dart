/// 카메라 촬영 모드.
///
/// 인물/객체 모드에서는 사용자가 구도(rule-of-thirds, golden ratio 등)를
/// 직접 선택해 오버레이와 코칭에 반영한다. 풍경 모드는 자동 감지 로직
/// (CompositionResolver)에 맡긴다.
enum ShootingMode {
  person('인물'),
  object('객체'),
  landscape('풍경');

  final String label;
  const ShootingMode(this.label);
}
