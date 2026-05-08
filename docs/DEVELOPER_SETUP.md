# Developer Setup

## Flutter

```bash
flutter pub get
flutter analyze
```

## Android Kotlin Compile

```bash
cd android
JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.18/libexec/openjdk.jdk/Contents/Home ./gradlew :app:compileDebugKotlin
cd ..
```

## Android Device

```bash
adb devices
adb shell ls -lh /data/local/tmp/llm
```

## Environment

```bash
cp .env.example .env
```

Edit `.env`:

```dotenv
GEMINI_API_KEY=your_gemini_api_key_here
```

## Gemma Models

Model files are not stored in Git. Push them to the Android device:

```bash
./scripts/push_gemma_model.sh R3CWA0602GK ~/Downloads/gemma4_e2b.litertlm
./scripts/push_gemma_model.sh R3CWA0602GK ~/Downloads/gemma4_e4b.litertlm
adb -s R3CWA0602GK shell ls -lh /data/local/tmp/llm
```

Expected paths:

- `/data/local/tmp/llm/gemma4_e2b.litertlm`
- `/data/local/tmp/llm/gemma4_e4b.litertlm`

## Optional Gemma VLM Run

```bash
flutter run \
  --dart-define=POZY_PREFER_ON_DEVICE_GEMMA_EXPLANATION=true \
  --dart-define=POZY_USE_GEMMA_VLM_EXPLANATION=true \
  --dart-define=POZY_GEMMA_VLM_MODEL_PATH=/data/local/tmp/llm/gemma4_e2b.litertlm \
  --dart-define=POZY_GEMMA_BACKEND_MODE=gpu_preferred
```
