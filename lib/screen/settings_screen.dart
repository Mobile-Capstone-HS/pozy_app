import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_colors.dart';
import '../widget/app_top_bar.dart';
import 'portrait_asset_test_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: AppTopBar(
                title: '설정',
                leadingIcon: Icons.arrow_back_ios_new_rounded,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
                children: [
                  _SettingsSection(
                    title: '앱 관리',
                    children: [
                      _SettingsTile(
                        icon: Icons.verified_user_outlined,
                        title: '권한 관리',
                        description: '카메라, 사진, 위치 권한 상태를 확인하고 변경할 수 있어요.',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const PermissionManagementScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SettingsSection(
                    title: '약관 및 정책',
                    children: [
                      _SettingsTile(
                        icon: Icons.description_outlined,
                        title: '서비스 이용약관',
                        description: 'Pozy 서비스 이용 조건과 기본 정책을 확인해요.',
                        onTap: () => _showTermsPage(
                          context,
                          '서비스 이용약관',
                          _getTermsOfService(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SettingsTile(
                        icon: Icons.lock_outline_rounded,
                        title: '개인정보 처리방침',
                        description: '수집 정보, 사용 목적, 보관 방식에 대한 안내예요.',
                        onTap: () => _showTermsPage(
                          context,
                          '개인정보 처리방침',
                          _getPrivacyPolicy(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SettingsTile(
                        icon: Icons.location_on_outlined,
                        title: '위치기반서비스 이용약관',
                        description: '위치 정보 사용 범위와 관련 안내를 확인해요.',
                        onTap: () => _showTermsPage(
                          context,
                          '위치기반서비스 이용약관',
                          _getLocationTerms(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SettingsSection(
                    title: '실험실',
                    children: [
                      _SettingsTile(
                        icon: Icons.person_search_outlined,
                        title: '인물 에셋 테스트',
                        description: '샘플 사진에 인물 코칭 로직을 적용해 안내 문구와 비율을 확인해요.',
                        badge: 'Beta',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PortraitAssetTestScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTermsPage(BuildContext context, String title, String content) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF6F8FB),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: AppTopBar(
                    title: title,
                    leadingIcon: Icons.arrow_back_ios_new_rounded,
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE8EDF4)),
                        ),
                        child: Text(
                          content,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            color: AppColors.primaryText,
                            height: 1.65,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getTermsOfService() {
    return '''[ Pozy 서비스 이용약관 ]

제1조 (목적)
본 약관은 Pozy 앱(이하 "서비스")이 제공하는 카메라 촬영, AI 사진 코칭, 사진 평가, 이미지 편집, 갤러리 관리, 관광지 및 촬영 스팟 추천 등 제반 기능 이용과 관련하여 이용자와 서비스 제공자 간의 권리, 의무 및 책임사항을 정하는 것을 목적으로 합니다.

제2조 (서비스의 내용)
서비스는 다음 기능을 제공합니다.
1. 카메라 기반 실시간 촬영, 초점, 줌, 타이머, 플래시 및 저장 기능
2. 인물, 객체, 풍경 촬영을 위한 구도, 수평, 조명, 포즈, 프레이밍 안내
3. 온디바이스 AI 모델을 활용한 피사체 감지, 얼굴 및 자세 분석, 풍경 구도 분석
4. 갤러리 사진 불러오기, 사진 평가, 베스트 컷 추천, 편집 보조 기능
5. 현재 위치 또는 선택 위치를 기반으로 한 주변 관광지, 촬영 스팟, 이동 경로 관련 정보 제공
6. 서비스 품질 개선을 위한 테스트, 디버그, 실험 기능

제3조 (AI 서비스 이용 및 면책조항)
1. 서비스는 온디바이스 AI 모델 및 외부 AI API를 활용하여 사진 분석, 구도 평가, 코칭 문구, 편집 제안, 사진 설명 등을 제공할 수 있습니다.
2. AI 결과는 촬영과 편집을 돕기 위한 참고 정보이며, 항상 정확하거나 완전하거나 이용자의 의도에 부합한다고 보장하지 않습니다.
3. 피사체 감지, 얼굴 분석, 자세 분석, 조명 판단, 미적 점수, 관광지 추천, 이동 경로 안내 등은 기기 상태, 네트워크 상태, 촬영 환경, 모델 성능, 외부 API 응답에 따라 달라질 수 있습니다.
4. 이용자는 AI 결과를 참고자료로 활용해야 하며, 해당 결과를 신뢰하여 발생한 손해나 불이익에 대해 서비스 제공자는 고의 또는 중대한 과실이 없는 한 책임을 지지 않습니다.

제4조 (외부 서비스 및 네트워크 이용)
서비스는 Firebase, Google Cloud, Google Gemini API, 공공 관광 API, 지도 및 경로 API 등 외부 서비스를 사용할 수 있습니다. 외부 서비스의 장애, 정책 변경, 요금 정책, 네트워크 오류, API 응답 오류로 인해 일부 기능이 제한될 수 있습니다.

제5조 (사진 및 콘텐츠 이용)
1. 이용자는 본인이 촬영하거나 사용할 권한이 있는 사진만 서비스에 업로드하거나 분석해야 합니다.
2. 타인의 초상, 저작물, 개인정보가 포함된 사진을 사용할 때에는 관련 권리를 침해하지 않도록 이용자가 책임지고 필요한 동의를 받아야 합니다.
3. 서비스가 제공하는 저장, 편집, 평가, 공유 전 단계의 결과는 이용자의 선택에 따라 사용됩니다.

제6조 (위치기반 기능)
서비스는 주변 관광지 추천, 지도 표시, 경로 안내, 촬영 스팟 탐색 등을 위해 위치정보를 사용할 수 있습니다. 위치정보의 구체적인 처리 기준은 위치기반서비스 이용약관에 따릅니다.

제7조 (이용자의 의무)
이용자는 서비스를 불법적인 목적, 타인의 권리 침해, 허위 정보 생성, 부적절한 콘텐츠 제작, 서비스 장애 유발 등의 목적으로 사용해서는 안 됩니다.

제8조 (서비스 변경 및 중단)
서비스 제공자는 기능 개선, 안정화, 외부 API 변경, 운영상 필요에 따라 서비스의 전부 또는 일부를 변경하거나 중단할 수 있습니다.''';
  }

  String _getPrivacyPolicy() {
    return '''[ Pozy 개인정보 처리방침 ]

1. 수집하는 개인정보 항목
- 계정 정보: 이메일 주소, Firebase 인증 식별자 등 로그인 및 사용자 식별 정보
- 위치 정보: GPS 좌표, 현재 위치 기반 지도 및 주변 스팟 탐색에 필요한 정보
- 이미지 데이터: 앱 내 카메라로 촬영한 사진, 사용자가 갤러리에서 선택한 사진, 편집 또는 평가 대상 이미지
- 사진 분석 정보: 피사체 감지 결과, 구도 평가, 미적 점수, 얼굴 및 자세 분석 결과, 조명 및 수평 상태, 베스트 컷 평가 결과
- 서비스 이용 정보: 앱 화면 이동, 기능 사용 기록, 오류 로그, 모델 실행 상태, 디버그 정보
- 기기 및 앱 정보: OS 버전, 앱 버전, 권한 상태, 네트워크 상태, 성능 및 오류 진단에 필요한 정보

2. 수집 및 이용 목적
- 계정 식별 및 서비스 이용자 관리
- 카메라 촬영, 사진 저장, 갤러리 불러오기, 이미지 편집 기능 제공
- AI 기반 사진 구도 코칭, 인물 포즈 안내, 풍경 분석, 객체 추적, 사진 평가 및 베스트 컷 추천
- 현재 위치 기반 주변 관광지, 촬영 스팟, 지도 및 경로 안내 제공
- 서비스 안정성 개선, 오류 분석, 모델 성능 점검, 기능 품질 향상
- 이용약관 및 개인정보 처리방침에 따른 고지, 문의 응대, 부정 이용 방지

3. 개인정보의 보관 및 파기 절차
서비스는 개인정보를 수집 및 이용 목적 달성에 필요한 기간 동안 보관합니다. 촬영 또는 선택된 이미지는 기능 제공을 위해 기기 내에서 처리되거나, 일부 AI 분석 기능 이용 시 외부 서버로 일시 전송될 수 있습니다. 서버 전송이 필요한 경우 분석 목적 범위에서만 사용하며, 법령 또는 서비스 운영상 필요한 경우를 제외하고 불필요하게 장기간 보관하지 않습니다. 이용자가 서비스 탈퇴 또는 삭제를 요청하는 경우 관련 법령에 따라 보관이 필요한 정보를 제외하고 지체 없이 파기합니다.

4. 제3자 제공 및 위탁 (Firebase & Google 등)
보다 안정적이고 고품질의 서비스를 위해 다음의 제3자에게 데이터를 위탁/제공하고 있습니다.
- 위탁 또는 제공 대상: Google Cloud, Firebase, Google Gemini API, 지도 및 위치 기반 서비스 제공자, 공공 관광 API 제공 기관
- 이용 목적: 인증, 데이터 저장, 서버 인프라 운영, AI 분석 처리, 위치 기반 정보 제공, 오류 분석 및 서비스 품질 개선
- 제공 항목: 기능 수행에 필요한 계정 식별 정보, 이미지 데이터, 분석 요청 데이터, 위치 정보, 오류 및 이용 로그 등

5. 권한 거부에 대한 안내 사항
이용자는 애플리케이션 권한 설정에서 카메라, 사진, 위치정보 등의 권한을 허용하거나 철회할 수 있습니다. 권한을 거부하거나 철회할 경우 카메라 촬영, 사진 저장, 갤러리 불러오기, 현재 위치 기반 추천 등 일부 기능 이용이 제한될 수 있습니다.

6. 이용자의 권리
이용자는 자신의 개인정보에 대해 열람, 정정, 삭제, 처리정지를 요청할 수 있습니다. 서비스 제공자는 관련 법령에 따라 이용자의 요청을 처리합니다.

7. 아동 및 민감정보
서비스는 원칙적으로 민감정보 수집을 목적으로 하지 않습니다. 다만 이용자가 업로드하거나 촬영한 사진에 얼굴, 위치, 사적 공간 등 민감할 수 있는 정보가 포함될 수 있으므로 이용자는 사진 선택 및 공유에 주의해야 합니다.

8. 개인정보 보호 조치
서비스 제공자는 개인정보 보호를 위해 접근 권한 제한, 전송 구간 보호, 불필요한 데이터 최소화, 오류 로그 관리 등 합리적인 보호 조치를 적용합니다.''';
  }

  String _getLocationTerms() {
    return '''[ Pozy 위치기반서비스 이용약관 ]

제1조 (목적)
본 약관은 Pozy 앱이 제공하는 위치기반서비스(GPS, Tour API 연동 등)와 관련하여, 위치정보의 보호 및 이용 등에 관한 책임과 권리를 규정함을 목적으로 합니다.

제2조 (위치정보 수집 및 처리)
1. 회사는 이용자의 스마트폰 등 단말기에서 제공하는 위치정보(GPS) 데이터를 실시간으로 수집합니다.
2. 수집된 정보는 현재 위치를 기점으로 관광 정보, 사진 촬영 스팟 추천, 지도 표시, 경로 안내, 주변 장소 탐색 기능을 제공하기 위해 사용됩니다.
3. 위치정보는 이용자가 위치 권한을 허용한 경우에만 사용되며, 이용자는 언제든지 기기 설정에서 위치 권한을 철회할 수 있습니다.

제3조 (서비스 이용 목적)
본 위치기반서비스의 주된 목적은 현재 위치 기반 주변 관광지 정보 제공, 가까운 촬영 스팟 안내, 지도 표시, 이동 경로 탐색 및 사진 촬영 장소 추천입니다.

제4조 (위치정보의 보유 기간 및 파기)
회사는 위치정보보호법 등 관련 법령의 규정에 의거하여, 위치기반서비스 제공 목적 달성 시까지 위치정보를 이용하며, 목적 달성 후 지체 없이 파기하는 것을 원칙으로 합니다. 단, 법령상 보관 의무가 있거나 이용자의 별도 동의가 있는 경우 해당 기간 동안 보관할 수 있습니다.

제5조 (제3자 서비스 연동)
서비스는 지도, 경로, 관광 정보 제공을 위해 외부 지도 서비스, 공공 관광 API, 경로 탐색 API와 연동될 수 있습니다. 이 과정에서 위치 기반 조회에 필요한 정보가 외부 서비스에 전달될 수 있습니다.

제6조 (이용자의 권리)
이용자는 위치정보 이용에 대한 동의를 철회할 수 있으며, 위치정보 이용 내역 확인 또는 삭제를 요청할 수 있습니다. 위치 권한을 거부하는 경우 위치 기반 추천, 지도 표시, 경로 안내 기능이 제한될 수 있습니다.

제7조 (면책)
위치정보는 단말기, GPS, 네트워크, 지도 데이터, 외부 API 상태에 따라 실제 위치와 다를 수 있습니다. 서비스가 제공하는 관광지, 촬영 스팟, 경로 안내 정보는 참고용이며, 실제 이동 및 방문 여부에 대한 최종 판단과 책임은 이용자에게 있습니다.''';
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.secondaryText,
              height: 1.2,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  static const Color _iconColor = AppColors.blue;

  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE8EDF4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          _SmallBadge(label: badge!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.lightText,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;

  const _SmallBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9FE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF6D28D9),
          height: 1.1,
        ),
      ),
    );
  }
}

class PermissionManagementScreen extends StatefulWidget {
  const PermissionManagementScreen({super.key});

  @override
  State<PermissionManagementScreen> createState() =>
      _PermissionManagementScreenState();
}

class _PermissionManagementScreenState extends State<PermissionManagementScreen>
    with WidgetsBindingObserver {
  bool _loadingPermissions = true;
  late List<_PermissionItemState> _permissions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissions = _buildInitialPermissions();
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
    }
  }

  List<_PermissionItemState> _buildInitialPermissions() {
    return const [
      _PermissionItemState(
        type: _PermissionType.camera,
        title: '카메라',
        description: '실시간 촬영과 구도 분석에 사용해요.',
        icon: Icons.camera_alt_outlined,
      ),
      _PermissionItemState(
        type: _PermissionType.photos,
        title: '사진 및 갤러리',
        description: '사진 불러오기와 촬영 결과 저장에 사용해요.',
        icon: Icons.photo_library_outlined,
      ),
      _PermissionItemState(
        type: _PermissionType.location,
        title: '위치',
        description: '주변 스팟 추천과 지도 기능에 사용해요.',
        icon: Icons.location_on_outlined,
      ),
    ];
  }

  Future<void> _refreshPermissions() async {
    if (mounted) {
      setState(() {
        _loadingPermissions = true;
      });
    }

    final resolved = <_PermissionItemState>[];
    for (final item in _permissions) {
      resolved.add(await _resolvePermission(item));
    }

    if (!mounted) return;
    setState(() {
      _permissions = resolved;
      _loadingPermissions = false;
    });
  }

  Future<_PermissionItemState> _resolvePermission(
    _PermissionItemState item,
  ) async {
    final status = await _permissionForType(item.type).status;
    return item.copyWith(status: status);
  }

  Permission _permissionForType(_PermissionType type) {
    switch (type) {
      case _PermissionType.camera:
        return Permission.camera;
      case _PermissionType.photos:
        return Permission.photos;
      case _PermissionType.location:
        return Permission.locationWhenInUse;
    }
  }

  Future<void> _handlePermissionAction(_PermissionItemState item) async {
    final currentStatus = item.status;
    final nextStatus = await _permissionForType(item.type).request();
    if (!mounted) return;

    setState(() {
      _permissions = _permissions
          .map(
            (current) => current.type == item.type
                ? current.copyWith(status: nextStatus)
                : current,
          )
          .toList();
    });

    if (currentStatus.isGranted || currentStatus.isLimited) {
      _showPermissionMessage('권한 해제는 시스템 설정에서 변경할 수 있어요.');
      return;
    }

    if (nextStatus.isPermanentlyDenied || nextStatus.isRestricted) {
      _showPermissionMessage('권한 팝업을 다시 띄울 수 없어 설정에서 변경해야 해요.');
    }
  }

  void _showPermissionMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(label: '설정 열기', onPressed: openAppSettings),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      controller.close();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: AppTopBar(
                title: '권한 관리',
                leadingIcon: Icons.arrow_back_ios_new_rounded,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                children: [
                  const _PermissionIntro(),
                  const SizedBox(height: 18),
                  for (var i = 0; i < _permissions.length; i++) ...[
                    _PermissionCard(
                      item: _permissions[i],
                      loading: _loadingPermissions,
                      onTap: () => _handlePermissionAction(_permissions[i]),
                    ),
                    if (i != _permissions.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PermissionType { camera, photos, location }

class _PermissionItemState {
  final _PermissionType type;
  final String title;
  final String description;
  final IconData icon;
  final PermissionStatus status;

  const _PermissionItemState({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    this.status = PermissionStatus.denied,
  });

  _PermissionItemState copyWith({PermissionStatus? status}) {
    return _PermissionItemState(
      type: type,
      title: title,
      description: description,
      icon: icon,
      status: status ?? this.status,
    );
  }
}

class _PermissionIntro extends StatelessWidget {
  const _PermissionIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8EDF4)),
      ),
      child: const Row(
        children: [
          Icon(Icons.privacy_tip_outlined, color: AppColors.blue, size: 26),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '필요한 권한만 요청하고, 현재 상태를 바로 확인할 수 있어요.',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final _PermissionItemState item;
  final bool loading;
  final VoidCallback onTap;

  const _PermissionCard({
    required this.item,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGranted = item.status.isGranted || item.status.isLimited;
    final statusText = _statusText(item.status);
    final statusColor = _statusColor(item.status);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: loading ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE8EDF4)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isGranted ? Colors.white : const Color(0xFFF2F5FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon,
                  color: isGranted ? AppColors.blue : AppColors.secondaryText,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: isGranted,
                onChanged: loading ? null : (_) => onTap(),
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.blue,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: AppColors.track,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return '허용됨';
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return '시스템 설정에서 변경 필요';
    }
    return '권한 요청 필요';
  }

  Color _statusColor(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return AppColors.blue;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return const Color(0xFFF97316);
    }
    return AppColors.secondaryText;
  }
}
