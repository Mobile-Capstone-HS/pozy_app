# 적용 메모

이번 패치는 아래 3가지를 같이 넣은 버전이야.

1. **PERFECT UX 보강**
   - PERFECT 상태를 약 0.9초 유지
   - 타깃 점 탭으로 구도 포인트 고정
   - 위/아래/왼쪽/오른쪽 이동 힌트 추가

2. **사람 / 음식 / 사물 구분 구조**
   - 사람: 기존 YOLO pose 자동 추적
   - 음식/사물: `google_mlkit_image_labeling` 기반 1차 분류
   - 음식/사물은 아직 위치 박스까지는 안 잡고, 선택한 타깃 점에 메인 피사체 중심을 맞추는 방식

3. **UI 방향 전환**
   - 흰 배경의 Home / Gallery / Camera 구조
   - 앱 내부 저장 캡처 갤러리 화면 추가

## pubspec.yaml에 추가할 의존성

```yaml
dependencies:
  path_provider: ^2.1.4
  google_mlkit_image_labeling: any
```

`any`는 네 환경에서 `flutter pub add google_mlkit_image_labeling`로 실제 호환 버전을 받는 용도로 적어둔 거야.

## 적용 순서

1. 이 패치 안의 `lib` 폴더 파일로 덮어쓰기
2. `pubspec.yaml`에 위 의존성 추가
3. `flutter pub get`
4. JDK 17 설정 유지한 상태로 `flutter run`

## 현재 한계

- 음식/사물은 **분류는 되지만 위치 추적은 아직 없음**
- 그래서 사람 모드처럼 `PERFECT`를 정확히 계산하지는 못함
- 정밀한 음식/사물 위치 추적은 다음 단계에서 detector 또는 classifier+detector 조합이 더 필요함
