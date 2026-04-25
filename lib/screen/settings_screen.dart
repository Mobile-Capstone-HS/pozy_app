import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  late List<_PermissionItemState> _permissions;
  _AppInfoState _appInfo = const _AppInfoState.loading();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permissions = _buildInitialPermissions();
    _refreshAll();
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
        description: '사진 불러오기와 편집 결과 저장에 사용해요.',
        icon: Icons.photo_library_outlined,
      ),
      _PermissionItemState(
        type: _PermissionType.location,
        title: '위치',
        description: '내 주변 촬영 스팟과 지도 기능에 사용해요.',
        icon: Icons.location_on_outlined,
      ),
    ];
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
    });

    await Future.wait([_refreshPermissions(), _loadAppInfo()]);

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _refreshPermissions() async {
    final resolved = <_PermissionItemState>[];
    for (final item in _permissions) {
      resolved.add(await _resolvePermission(item));
    }

    if (!mounted) return;
    setState(() {
      _permissions = resolved;
    });
  }

  Future<_PermissionItemState> _resolvePermission(
    _PermissionItemState item,
  ) async {
    final permission = _permissionForType(item.type);
    final status = await permission.status;
    return item.copyWith(status: status);
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appInfo = _AppInfoState(
          appName: info.appName,
          packageName: info.packageName,
          version: info.version,
          buildNumber: info.buildNumber,
          platformLabel: Platform.isAndroid
              ? 'Android'
              : Platform.isIOS
              ? 'iOS'
              : Platform.operatingSystem,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appInfo = _AppInfoState(
          appName: 'Pozy',
          packageName: '-',
          version: '1.0.0',
          buildNumber: '1',
          platformLabel: Platform.operatingSystem,
        );
      });
    }
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
    final permission = _permissionForType(item.type);
    final status = item.status;
    final nextStatus = await permission.request();
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

    if (status.isGranted || status.isLimited) {
      _showPermissionMessage('권한 해제는 시스템 설정에서만 변경할 수 있어요.');
      return;
    }

    if (nextStatus.isPermanentlyDenied || nextStatus.isRestricted) {
      _showPermissionMessage('시스템 권한 팝업을 다시 띄울 수 없어 설정에서 변경해야 해요.');
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
          action: SnackBarAction(label: '설정 열기', onPressed: openAppSettings),
        ),
      );

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: '설정',
                leadingIcon: Icons.arrow_back_ios_new_rounded,
                onLeadingTap: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF29B6F6),
                onRefresh: _refreshAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                  children: [
                    _SettingsSection(
                      title: '권한 관리',
                      subtitle: '필요한 접근 권한의 현재 상태를 확인하고 바로 변경할 수 있어요.',
                      child: Column(
                        children: _permissions
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _PermissionCard(
                                  item: item,
                                  loading: _loading,
                                  onTap: () => _handlePermissionAction(item),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SettingsSection(
                      title: '앱 정보',
                      subtitle: '현재 앱 버전과 기본 정보를 확인할 수 있어요.',
                      child: _AppInfoCard(info: _appInfo, loading: _loading),
                    ),
                    const SizedBox(height: 10),
                    const _HelpCard(),
                  ],
                ),
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

class _AppInfoState {
  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;
  final String platformLabel;

  const _AppInfoState({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
    required this.platformLabel,
  });

  const _AppInfoState.loading()
    : appName = '',
      packageName = '',
      version = '',
      buildNumber = '',
      platformLabel = '';
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.title18),
          const SizedBox(height: 6),
          Text(subtitle, style: AppTextStyles.body13),
          const SizedBox(height: 18),
          child,
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
    final canToggle = !loading;
    final statusText = _statusText(item.status);
    final statusColor = _statusColor(item.status);
    final cardColor = isGranted ? const Color(0xFFF1FBF7) : Colors.white;
    final borderColor = isGranted
        ? const Color(0xFFD7F3E7)
        : const Color(0xFFE8EDF5);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: AppColors.primaryText, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.title, style: AppTextStyles.title16),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: AppTextStyles.caption12.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Transform.scale(
            scale: 0.92,
            child: Switch(
              value: isGranted,
              onChanged: canToggle ? (_) => onTap() : null,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF22C58B),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFD5DCE7),
            ),
          ),
        ],
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
    return AppColors.secondaryText;
  }
}

class _AppInfoCard extends StatelessWidget {
  final _AppInfoState info;
  final bool loading;

  const _AppInfoCard({required this.info, required this.loading});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('앱 이름', info.appName.isEmpty ? '불러오는 중...' : info.appName),
      ('버전', info.version.isEmpty ? '불러오는 중...' : info.version),
      ('빌드 번호', info.buildNumber.isEmpty ? '불러오는 중...' : info.buildNumber),
      ('플랫폼', info.platformLabel.isEmpty ? '불러오는 중...' : info.platformLabel),
      ('패키지명', info.packageName.isEmpty ? '불러오는 중...' : info.packageName),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        children: rows
            .map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 86,
                      child: Text(
                        row.$1,
                        style: AppTextStyles.caption12.copyWith(
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        row.$2,
                        textAlign: TextAlign.right,
                        style: AppTextStyles.body14.copyWith(
                          color: loading && row.$2 == '불러오는 중...'
                              ? AppColors.secondaryText
                              : AppColors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '안내',
            style: AppTextStyles.title16.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            '권한이 허용되지 않으면 카메라 촬영, 갤러리 불러오기, 주변 스팟 탐색 기능이 제한될 수 있어요. 설정을 변경한 뒤 다시 앱으로 돌아오면 상태가 자동으로 새로고침됩니다.',
            style: AppTextStyles.body13.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }
}
