import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
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
        description: '내 주변 스팟 탐색과 지도 기능에 사용해요.',
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
      _showPermissionMessage('권한 해제는 시스템 설정에서만 변경할 수 있어요.');
      return;
    }

    if (nextStatus.isPermanentlyDenied || nextStatus.isRestricted) {
      _showPermissionMessage('권한 팝업을 다시 띄울 수 없어 설정에서 변경해야 해요.');
    }
  }

  void _showPermissionMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: '설정 열기',
            onPressed: openAppSettings,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            '설정',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.black87,
            unselectedLabelColor: Color(0xFF8A94A6),
            indicatorColor: Color(0xFF29B6F6),
            indicatorWeight: 2.5,
            labelStyle: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: '일반'),
              Tab(text: '권한 관리'),
            ],
          ),
        ),
        backgroundColor: const Color(0xFFF6F7FB),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                _buildSettingsItem(
                  context,
                  icon: Icons.article_outlined,
                  title: '서비스 이용약관',
                  onTap: () => _showTermsDialog(
                    context,
                    '서비스 이용약관',
                    _getTermsOfService(),
                  ),
                ),
                const Divider(height: 1, color: Colors.transparent),
                _buildSettingsItem(
                  context,
                  icon: Icons.privacy_tip_outlined,
                  title: '개인정보 처리방침',
                  onTap: () => _showTermsDialog(
                    context,
                    '개인정보 처리방침',
                    _getPrivacyPolicy(),
                  ),
                ),
                const Divider(height: 1, color: Colors.transparent),
                _buildSettingsItem(
                  context,
                  icon: Icons.location_on_outlined,
                  title: '위치기반서비스 이용약관',
                  onTap: () => _showTermsDialog(
                    context,
                    '위치기반서비스 이용약관',
                    _getLocationTerms(),
                  ),
                ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                _PermissionSection(
                  permissions: _permissions,
                  loading: _loadingPermissions,
                  onTapPermission: _handlePermissionAction,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        leading: Icon(icon, color: Colors.grey.shade700),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _showTermsDialog(BuildContext context, String title, String content) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(
              content,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: Colors.black87,
                height: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
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
AI 모델이 제공하는 사진 코칭 조언, 구도 평가, 임의의 자동 편집 기능 등의 결과물은 완벽하지 않거나 오류가 있을 수 있습니다. 해당 결과물을 신뢰하여 발생하는 판단이나 문제에 대한 서비스의 법적 책임은 모두 면책되며, 이에 대한 모든 책임은 사용자에게 귀속됩니다.

제4조 (이용자의 의무)
이용자는 서비스를 불법적인 목적으로 사용하여서는 안 되며, 다른 사람의 권리를 직간접적으로 침해하지 않아야 합니다.''';
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

class _PermissionSection extends StatelessWidget {
  final List<_PermissionItemState> permissions;
  final bool loading;
  final ValueChanged<_PermissionItemState> onTapPermission;

  const _PermissionSection({
    required this.permissions,
    required this.loading,
    required this.onTapPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '권한 관리',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '필요한 권한의 현재 상태를 확인하고 바로 요청할 수 있어요.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < permissions.length; i++) ...[
            _PermissionCard(
              item: permissions[i],
              loading: loading,
              onTap: () => onTapPermission(permissions[i]),
            ),
            if (i != permissions.length - 1) const SizedBox(height: 10),
          ],
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

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isGranted ? const Color(0xFFF1FBF7) : const Color(0xFFF9FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isGranted
                ? const Color(0xFFD7F3E7)
                : const Color(0xFFE3E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: Colors.black87, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
              activeTrackColor: const Color(0xFF22C58B),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFD5DCE7),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return '허용됨';
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return '설정에서 변경 필요';
    }
    return '탭해서 권한 요청';
  }

  Color _statusColor(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return const Color(0xFF12805C);
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return const Color(0xFFB45511);
    }
    return const Color(0xFF6B7280);
  }
}
