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
```

## Environment

```bash
cp .env.example .env
```

Edit `.env`:

```dotenv
GEMINI_API_KEY=your_gemini_api_key_here
```
