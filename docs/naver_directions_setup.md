# Naver Directions Secure Setup

앱에는 NAVER Directions 키를 넣지 않고, Firebase Functions가 Secret Manager를 통해 대신 호출합니다.

## 1. Functions 의존성 설치

```bash
cd functions
npm install
```

## 2. Firebase 로그인 및 프로젝트 선택

```bash
firebase login
firebase use pozy-ec935
```

## 3. 시크릿 등록

```bash
firebase functions:secrets:set NAVER_DIRECTIONS_API_KEY_ID
firebase functions:secrets:set NAVER_DIRECTIONS_API_KEY
```

## 4. Functions 배포

```bash
firebase deploy --only functions
```

## 5. Flutter 의존성 반영

```bash
flutter pub get
```

## 동작 구조

1. 앱이 현재 위치와 목적지 좌표를 Firebase Callable Function `getDrivingRoute`로 보냅니다.
2. Functions가 Secret Manager에 저장된 NAVER 키로 Directions 5 API를 호출합니다.
3. 앱은 응답받은 실제 도로 경로 좌표, 거리, 소요시간, 안내 문구를 지도에 표시합니다.

## 참고

- Functions 리전은 `asia-northeast3`(Seoul)로 설정되어 있습니다.
- 앱은 이미 Firebase 익명 로그인을 수행하므로 callable 호출 시 기본 인증이 함께 전달됩니다.
- NAVER Directions는 차량 기준 경로 API입니다.
