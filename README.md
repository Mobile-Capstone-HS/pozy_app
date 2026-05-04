# Pozy App

Flutter 기반 사진 촬영, 구도 코칭, A-cut 추천 앱입니다. 기본 앱은 온디바이스 포즈/사진 평가와 Gemini API 기반 설명 생성을 사용하며, Gemma LiteRT-LM 텍스트/VLM 설명은 별도 실험 플래그와 Android 기기 내 모델 파일이 있을 때만 동작합니다.

## Project Overview

- 실시간 카메라 구도 코칭
- 갤러리 사진 A-cut 평가
- 기술/미적/구도 점수 기반 설명 생성
- 선택적으로 Gemma LiteRT-LM 온디바이스 텍스트/VLM 설명 probe
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

## Gemma LiteRT Model Setup

대용량 `.litertlm` 모델 파일은 GitHub에 저장하지 않습니다. 팀에서 승인한 배포 경로나 Google AI Edge/LiteRT-LM 모델 배포 경로에서 모델 파일을 수동으로 받은 뒤 Android 기기로 push하세요.

기본 Android device path:

- Gemma 4 E2B: `/data/local/tmp/llm/gemma4_e2b.litertlm`
- Gemma 4 E4B: `/data/local/tmp/llm/gemma4_e4b.litertlm`

헬퍼 스크립트:

```bash
./scripts/push_gemma_model.sh R3CWA0602GK ~/Downloads/gemma4_e2b.litertlm
./scripts/push_gemma_model.sh R3CWA0602GK ~/Downloads/gemma4_e4b.litertlm
```

수동 명령:

```bash
adb -s R3CWA0602GK shell mkdir -p /data/local/tmp/llm
adb -s R3CWA0602GK push ~/Downloads/gemma4_e2b.litertlm /data/local/tmp/llm/gemma4_e2b.litertlm
adb -s R3CWA0602GK shell ls -lh /data/local/tmp/llm
```

Gemma/VLM 실험 플래그 예시:

```bash
flutter run \
  --dart-define=POZY_PREFER_ON_DEVICE_GEMMA_EXPLANATION=true \
  --dart-define=POZY_USE_GEMMA_VLM_EXPLANATION=true \
  --dart-define=POZY_GEMMA_VLM_MODEL_PATH=/data/local/tmp/llm/gemma4_e2b.litertlm \
  --dart-define=POZY_GEMMA_BACKEND_MODE=gpu_preferred
```

기본 production 동작에서는 Gemma 설명 경로가 강제로 켜지지 않습니다. 모델 파일이 없어도 일반 Flutter 빌드는 가능해야 합니다.

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

## Debug Screens

설명 백엔드 디버그 화면에서 다음을 확인할 수 있습니다.

- Gemma model file check
- Gemma preload
- Generate once
- Gemma Vision Probe
- Gemini text-only, Gemini image+scores, Gemma text/VLM 비교
- `backend_info`, `gpu_fallback_used`, `image_input_used`, `model_path`, `file_exists`, timing, JSON parse/repair/fallback 상태

모델 파일이 없으면 debug screen은 `model file missing`, expected path, setup command를 표시하고 Gemma 실행 버튼을 비활성화합니다.

## Contact Sheet And Generated Outputs

`src/tools/generate_acut_contact_sheets.py`는 A-cut 후보 이미지를 compact multi-scale contact sheet로 만드는 개발 도구입니다. 생성물은 `outputs/` 아래에 두고 Git에 올리지 않습니다.

```bash
python3 -m src.tools.generate_acut_contact_sheets \
  --input-topk <topk_csv_or_json> \
  --output-dir outputs/acut_contact_sheets \
  --top-k 5
```

Android 기기로 contact sheet를 복사해 VLM probe에 쓸 수 있습니다.

```bash
adb -s R3CWA0602GK shell mkdir -p /data/local/tmp/acut_contact_sheets
adb -s R3CWA0602GK push <contact_sheet.jpg> /data/local/tmp/acut_contact_sheets/test_contact_sheet.jpg
```

## Troubleshooting

- `model file missing`: `./scripts/push_gemma_model.sh <device_id> <local_model.litertlm>`로 모델을 기기에 복사하세요.
- `backend_info=CPU`: GPU backend를 요청했지만 기기/드라이버/모델 조건에 따라 CPU로 동작할 수 있습니다.
- `gpu_fallback_used=true`: GPU 초기화 실패나 미지원으로 fallback이 발생한 상태입니다. logcat에서 `GemmaLiteRtLm` 로그를 확인하세요.
- Gemini API key missing: `.env`에 `GEMINI_API_KEY`가 있는지 확인하세요.
- Android device not found: `adb devices`로 연결 상태와 USB 디버깅 권한을 확인하세요.
- macOS zsh 환경에서 Flutter/Dart 명령이 SDK cache 접근 오류를 내면, Flutter SDK 권한과 경로를 확인하세요.

Logcat 예시:

```bash
adb -s R3CWA0602GK logcat | grep -E "GEMMA_VLM_GENERATE|GEMMA_VISUAL|GemmaLiteRtLm|AcutVlmInput|ACutResultScreen"
```

## Security Note

- `.env`, API 키, keystore, `local.properties`, 대용량 모델 파일은 Git에 커밋하지 않습니다.
- Firebase `google-services.json`과 `firebase_options.dart`의 API key는 Firebase 클라이언트 설정값입니다. 공개 repo에서는 Firebase Console에서 도메인/앱 제한, App Check, 보안 규칙을 반드시 확인하세요.
