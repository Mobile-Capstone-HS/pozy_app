import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정', style: TextStyle(fontFamily: 'Pretendard', fontSize: 18, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF6F7FB),
      body: ListView(
        children: [
          _buildSettingsItem(
            context,
            icon: Icons.article_outlined,
            title: '서비스 이용약관',
            onTap: () => _showTermsDialog(context, '서비스 이용약관', _getTermsOfService()),
          ),
          const Divider(height: 1, color: Colors.transparent),
          _buildSettingsItem(
            context,
            icon: Icons.privacy_tip_outlined,
            title: '개인정보 처리방침',
            onTap: () => _showTermsDialog(context, '개인정보 처리방침', _getPrivacyPolicy()),
          ),
          const Divider(height: 1, color: Colors.transparent),
          _buildSettingsItem(
            context,
            icon: Icons.location_on_outlined,
            title: '위치기반서비스 이용약관',
            onTap: () => _showTermsDialog(context, '위치기반서비스 이용약관', _getLocationTerms()),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem(BuildContext context, {required IconData icon, required String title, required VoidCallback onTap}) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        leading: Icon(icon, color: Colors.grey.shade700),
        title: Text(
          title,
          style: const TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showTermsDialog(BuildContext context, String title, String content) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(title, style: const TextStyle(fontFamily: 'Pretendard', fontSize: 18, fontWeight: FontWeight.w600)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Text(
            content,
            style: const TextStyle(fontFamily: 'Pretendard', fontSize: 14, color: Colors.black87, height: 1.6),
          ),
        ),
      ),
    ));
  }

  String _getTermsOfService() {
    return '''[ POZY 서비스 이용약관 ]

제1조 (목적)
본 약관은 POZY 앱(이하 "서비스") 내의 AI 사진 코칭 및 제반 기능 이용에 관하여 사용자와 회사 간의 권리, 의무를 규정함을 목적으로 합니다.

제2조 (서비스의 내용)
서비스는 사용자에게 맞춤형 주변 관광지 정보, AI 기반의 구도 코칭 및 기타 사진 관련 부가 기능을 제공합니다.

제3조 (AI 서비스 이용 및 면책조항)
1. 외부 서버 전송 알림: 
서비스 내 AI 코칭 및 베스트 컷 분석 등의 기능을 제공하기 위해, 기기에서 촬영된 이미지가 일시적으로 외부 서버(Google Gemini API 등)로 전송되어 분석 목적에 사용될 수 있습니다.
2. 결과물에 대한 책임 한계: 
AI 모델이 제공하는 사진 코칭 조언, 구도 평가, 임의의 자동 편집 기능 등의 결과물은 완벽하지 않거나 오류가 있을 수 있습니다. 해당 결과물을 신뢰하여 발생하는 판단이나 문제에 대한 서비의 법적 책임은 모두 면책되며, 이에 대한 모든 책임은 사용자에게 귀속됩니다.

제4조 (이용자의 의무)
이용자는 서비스를 불법적인 목적으로 사용하여서는 안 되며, 다른 사람의 권리를 직간접적으로 향유 및 활용 및 침해하지 않아야 합니다.''';
  }

  String _getPrivacyPolicy() {
    return '''[ POZY 개인정보 처리방침 ]

1. 수집하는 개인정보 항목
- 이메일 주소 (Firebase 사용자 로그인 시)
- 위치 정보 (GPS 좌표)
- 촬영된 이미지 데이터 (앱 내 카메라 캡처 및 갤러리)

2. 수집 및 이용 목적
- 이메일 주소: 회원 식별 
- 위치 정보: 사용자 맞춤형 관광지 추천
- 이미지 데이터: AI 기반 사진 구도 코칭 및 이미지 내용 편집, 프레임 매칭

3. 개인정보의 보관 및 파기 절차
원칙적으로 수집된 개인정보 및 이미지는 분석 완료 후 즉시 삭제되며 별도로 서버에 보존, 보관하지 않습니다. 기기에 캐시된 데이터나 사용자의 회원가입 식별 정보의 경우, 사용자가 서비스 탈퇴 또는 삭제 요청 시 지체 없이 파기됩니다.

4. 제3자 제공 및 위탁 (Firebase & Google 등)
보다 안정적이고 고품질의 서비스를 위해 다음의 제3자에게 데이터를 위탁/제공하고 있습니다.
- 위탁 대상: Google Cloud (Firebase), Google (Gemini API)
- 위탁 목적: 데이터 저장 인프라 유지, AI 분석 처리

5. 권한 거부에 대한 안내 사항
사용자는 애플리케이션 권한 제어 설정에서 카메라, 위치정보 등의 필수 및 선택 권한을 철회할 수 있습니다. 단, 정상적인 기능 활용에 무리가 있을 수 있습니다.''';
  }

  String _getLocationTerms() {
    return '''[ POZY 위치기반서비스 이용약관 ]

제1조 (목적)
본 약관은 POZY 앱이 제공하는 위치기반서비스(GPS, Tour API 연동 등)와 관련하여, 위치정보의 보호 및 이용 등에 관한 책임과 권리를 규정함을 목적으로 합니다.

제2조 (위치정보 수집 및 처리)
1. 회사는 이용자의 스마트폰 등 단말기에서 제공하는 위치정보(GPS) 데이터를 실시간으로 수집합니다.
2. 수집된 정보는 현재 위치를 기점으로 관광 정보와 사진 촬영 스팟 추천을 조회하는 것에만 사용됩니다.

제3조 (서비스 이용 목적)
본 위치기반서비스의 주된 목적은 "현재 위치 기반 주변 관광지 정보 제공 및 가장 가까운 스팟 안내 제공" 입니다.

제4조 (위치정보의 보유 기간 및 파기)
회사는 위치정보보호법 등 관련 법령의 규정에 의거하여, 서비스 제공 목적 달성 시(사용자의 앱 세션 종료 시점)까지 단말기 및 메모리에만 유지하며, 그 이후 지체 없이 즉시 파기합니다.''';
  }
}
