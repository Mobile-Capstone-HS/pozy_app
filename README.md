<img width="1672" height="941" alt="KakaoTalk_20260604_133424081" src="https://github.com/user-attachments/assets/3dfb0cba-e079-40b5-9af9-1b650b7e4ca3" />

<div align="center">
<h1>📌 AI 기반 스마트 카메라 및 사진 어시스턴트 앱 "Pozy"</h1>
AI 기술을 통해 촬영 코칭부터 베스트컷 선정, 촬영지 추천까지
</div>
  
## 🖼️ 예시 화면

- 실시간 카메라 구도 코칭
- 갤러리 사진 A-cut 평가
- 기술/미적/구도 점수 기반 설명 생성
- 선택적으로 Gemma LiteRT-LM 온디바이스 텍스트/VLM 설명 probe
- 선택적으로 A-cut contact sheet 생성 도구 사용

## 🎯 주요 기능
- <strong>📷 AI 촬영 코칭</strong> : 실시간 객체 인식과 장면 분석을 통해 최적의 구도 가이드 제공

- <strong>⭐ 베스트컷 추천</strong> : 이미지 품질 평가 AI로 여러 사진 중 가장 잘 나온 사진을 자동 추천

- <strong>🗺️ 촬영지 추천</strong> : 지도 기반으로 주변 관광지와 포토스팟을 탐색하고 추천

- <strong>🎨 사진 편집</strong> : 다양한 편집 기능을 통해 촬영한 사진을 손쉽게 보정 가능

## 🛠 Tech Stack

### Frontend

<p>
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
  <img src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white"/>
</p>

### AI

<p>
  <img src="https://img.shields.io/badge/TensorFlow_Lite-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white"/>
  <img src="https://img.shields.io/badge/YOLO-111111?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Google_ML_Kit-4285F4?style=for-the-badge&logo=google&logoColor=white"/>
</p>

### Mobile

<p>
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white"/>
  <img src="https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=apple&logoColor=white"/>
</p>

### API

<p>
  <img src="https://img.shields.io/badge/Google_AI_Studio-4285F4?style=for-the-badge&logo=google&logoColor=white"/>
  <img src="https://img.shields.io/badge/Naver_Map_API-03C75A?style=for-the-badge&logo=naver&logoColor=white"/>
  <img src="https://img.shields.io/badge/Korea_Tourism_API-005BAC?style=for-the-badge"/>
</p>

### Tools

<p>
  <img src="https://img.shields.io/badge/Android_Studio-3DDC84?style=for-the-badge&logo=androidstudio&logoColor=white"/>
  <img src="https://img.shields.io/badge/Xcode-147EFB?style=for-the-badge&logo=xcode&logoColor=white"/>
  <img src="https://img.shields.io/badge/VS_Code-007ACC?style=for-the-badge&logo=visualstudiocode&logoColor=white"/>
  <img src="https://img.shields.io/badge/Firebase_CLI-FFCA28?style=for-the-badge&logo=firebase&logoColor=black"/>
</p>

## 🧱 시스템 구조도
<img width="1494" height="1204" alt="Frame 1 (4)" src="https://github.com/user-attachments/assets/e5019f84-6324-44b3-a4ab-19fee84a6221" />


## 🚀 설치 및 실행 방법
```
# 1. 프로젝트 클론
git clone https://github.com/Pozy-App/pozy.git

# 2. 디렉토리 이동
cd pozy

# 3. 의존성 설치
flutter pub get

# 4. 실행 
flutter run
```
## 👥 Team

| 이름 | 담당 |
|------|------|
| 강승원 | 팀장, UI/UX 설계 및 구현, 카메라 객체모드 설계 및 개발 |
| 김관중 | 이미지 평가 AI 모델 구현 및 파인튜닝 |
| 고명준 | 카메라 풍경모드 설계 및 개발 |
| 서정원 | 카메라 구조 설계 및 리팩토링, 에디터 기능 개발 |
| 이승비 | 카메라 인물모드 설계 및 개발 |

