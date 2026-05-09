# Pozy App

Flutter 기반 사진 촬영, 구도 코칭, A-cut 추천 앱입니다. Best Cut 평가는 FLIVE, KonIQ, NIMA, RGNet, A-LAMP 온디바이스 모델을 사용하며, 상세 설명은 사용자가 요청할 때 Gemini API로 생성합니다.

## Project Overview

- 실시간 카메라 구도 코칭
- 갤러리 사진 A-cut 평가
- FLIVE/KonIQ 기술 점수와 NIMA/RGNet/A-LAMP 미적 점수 기반 Best Cut 추천
- 사용자 요청 기반 Gemini API 상세 설명 생성
- 선택적으로 A-cut contact sheet 생성 도구 사용

## Prerequisites

- Flutter SDK
- Android Studio와 Android SDK
- JDK 17
- `adb`
- Android 실기기 권장

## Clone And Install

```bash
git clone <repo-url>
cd pozy_app
flutter pub get
```

Android 빌드용 `android/local.properties`는 Flutter/Android Studio가 로컬에서 생성합니다. 이 파일은 Git에 올리지 않습니다.

## Environment Variables

```bash
cp .env.example .env
```

`.env`에 필요한 키를 채웁니다.

```dotenv
GEMINI_API_KEY=your_gemini_api_key_here
```

실제 API 키는 Git에 커밋하지 마세요. `lib/services/gemini_service.dart`와 `lib/services/gemini_analysis_service.dart`는 `.env` 또는 `--dart-define=GEMINI_API_KEY=...`를 통해 키를 읽습니다.

## Running The App

```bash
flutter run
```

Android Kotlin 컴파일 확인:

```bash
cd android
JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.18/libexec/openjdk.jdk/Contents/Home ./gradlew :app:compileDebugKotlin
cd ..
```

## Contact Sheet And Generated Outputs

`src/tools/generate_acut_contact_sheets.py`는 A-cut 후보 이미지를 compact multi-scale contact sheet로 만드는 개발 도구입니다. 생성물은 `outputs/` 아래에 두고 Git에 올리지 않습니다.

```bash
python3 -m src.tools.generate_acut_contact_sheets \
  --input-topk <topk_csv_or_json> \
  --output-dir outputs/acut_contact_sheets \
  --top-k 5
```

Android 기기로 contact sheet를 복사해 개발 검토에 쓸 수 있습니다.

```bash
adb -s R3CWA0602GK shell mkdir -p /data/local/tmp/acut_contact_sheets
adb -s R3CWA0602GK push <contact_sheet.jpg> /data/local/tmp/acut_contact_sheets/test_contact_sheet.jpg
```

## Troubleshooting

- Gemini API key missing: `.env`에 `GEMINI_API_KEY`가 있는지 확인하세요.
- Android device not found: `adb devices`로 연결 상태와 USB 디버깅 권한을 확인하세요.
- macOS zsh 환경에서 Flutter/Dart 명령이 SDK cache 접근 오류를 내면, Flutter SDK 권한과 경로를 확인하세요.

Logcat 예시:

```bash
adb -s R3CWA0602GK logcat | grep -E "AcutPerf|ACutResultScreen"
```

## Security Note

- `.env`, API 키, keystore, `local.properties`, 대용량 모델 파일은 Git에 커밋하지 않습니다.
- Firebase `google-services.json`과 `firebase_options.dart`의 API key는 Firebase 클라이언트 설정값입니다. 공개 repo에서는 Firebase Console에서 도메인/앱 제한, App Check, 보안 규칙을 반드시 확인하세요.
