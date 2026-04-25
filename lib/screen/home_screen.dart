import 'package:flutter/material.dart';

import '../models/tour_place.dart';
import '../screen/settings_screen.dart';
import '../services/tour_api_service.dart';
import '../widget/home_bottom_nav.dart';
import 'camera_screen.dart';
import 'map_spot_screen.dart';

// ── PlaceTag 배지 정의 ──────────────────────────────────────────
const _tagInfo = <PlaceTag, ({Color color, IconData icon, String label})>{
  PlaceTag.nature: (
    color: Color(0xFF43A047),
    icon: Icons.park_outlined,
    label: '자연',
  ),
  PlaceTag.history: (
    color: Color(0xFF8D6E63),
    icon: Icons.account_balance_outlined,
    label: '역사',
  ),
  PlaceTag.architecture: (
    color: Color(0xFFF59E0B),
    icon: Icons.apartment_outlined,
    label: '건축',
  ),
  PlaceTag.culture: (
    color: Color(0xFF5C6BC0),
    icon: Icons.palette_outlined,
    label: '문화',
  ),
  PlaceTag.leisure: (
    color: Color(0xFF00ACC1),
    icon: Icons.directions_run,
    label: '레포츠',
  ),
  PlaceTag.festival: (
    color: Color(0xFFE91E63),
    icon: Icons.celebration_outlined,
    label: '축제',
  ),
  PlaceTag.landmark: (
    color: Color(0xFF607D8B),
    icon: Icons.place_outlined,
    label: '명소',
  ),
};

class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;

  const HomeScreen({super.key, required this.onMoveTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 앱 세션 내에서 1회만 API 호출 — 탭 전환 시 재로딩 없음
  static _HomeData? _cache;

  final _api = TourApiService();
  late Future<_HomeData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _cache != null ? Future.value(_cache) : _loadData();
  }

  Future<_HomeData> _loadData() async {
    final results = await Future.wait([
      _api.fetchWeeklySpots(count: 10),
      _api.fetchCurrentEvents(count: 8),
    ]);

    final data = _HomeData(
      weeklySpots: results[0],
      events: results[1],
    );
    _cache = data;
    return data;
  }

  void _openCamera() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          onMoveTab: (index) {
            Navigator.of(context).pop();
            widget.onMoveTab(index);
          },
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openMap([TourPlace? place]) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MapSpotScreen(focusPlace: place)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onSettingsTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            Expanded(
              child: FutureBuilder<_HomeData>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _LoadingBody();
                  }

                  if (snapshot.hasError || !snapshot.hasData) {
                    return _ErrorBody(
                      hasApiKey: _api.hasApiKey,
                      onRetry: () => setState(() {
                          _cache = null;
                          _dataFuture = _loadData();
                        }),
                      onMap: () => _openMap(),
                    );
                  }

                  return _Body(
                    data: snapshot.data!,
                    onMap: () => _openMap(),
                    onPlaceTap: _openMap,
                  );
                },
              ),
            ),
            HomeBottomNav(
              currentIndex: 0,
              onTap: widget.onMoveTab,
              onShutter: _openCamera,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeData {
  final List<TourPlace> weeklySpots;
  final List<TourPlace> events;

  const _HomeData({required this.weeklySpots, required this.events});
}

class _Header extends StatelessWidget {
  final VoidCallback onSettingsTap;

  const _Header({required this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F7FB),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Image.asset(
            'assets/images/pozy_logo.png',
            height: 28,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          GestureDetector(
            onTap: onSettingsTap,
            child: Icon(
              Icons.settings_outlined,
              color: Colors.grey.shade400,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            height: 188,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF29B6F6),
                strokeWidth: 2,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: 240,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: 4,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.96,
              ),
              itemBuilder: (_, _) => Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final bool hasApiKey;
  final VoidCallback onRetry;
  final VoidCallback onMap;

  const _ErrorBody({
    required this.hasApiKey,
    required this.onRetry,
    required this.onMap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              const Text('📷', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                hasApiKey ? '추천 장소를 불러오는 중 문제가 생겼어요' : '관광 정보 API 키 설정이 필요해요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasApiKey
                    ? '네트워크 상태를 확인하고 다시 시도해 주세요.'
                    : '.env 파일에 TOUR_API_KEY를 추가하면\n실제 추천 장소를 가져올 수 있어요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              _ActionButton(
                label: hasApiKey ? '다시 시도' : '스팟 지도 보기',
                icon: hasApiKey ? Icons.refresh_rounded : Icons.map_outlined,
                onTap: hasApiKey ? onRetry : onMap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF29B6F6),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final _HomeData data;
  final VoidCallback onMap;
  final ValueChanged<TourPlace> onPlaceTap;

  const _Body({
    required this.data,
    required this.onMap,
    required this.onPlaceTap,
  });

  @override
  Widget build(BuildContext context) {
    final weekly = data.weeklySpots;
    final events = data.events;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          if (weekly.isNotEmpty)
            _FeaturedBanner(place: weekly.first, onTap: onPlaceTap),
          if (weekly.isNotEmpty) const SizedBox(height: 14),
          if (weekly.length > 1)
            _PlaceSection(
              title: '이번 주 사진 찍으러 가기 좋은\n${TourApiService.weeklyAreaName} 추천 스팟 📸',
              places: weekly.skip(1).toList(),
              onMoreTap: onMap,
              onPlaceTap: onPlaceTap,
            ),
          if (weekly.length > 1) const SizedBox(height: 14),
          if (events.isNotEmpty)
            _PlaceSection(
              title: '분위기까지 함께 담기 좋은\n축제 촬영 스팟 🎉',
              places: events,
              onMoreTap: onMap,
              onPlaceTap: onPlaceTap,
              showTagBadge: false,
            ),
          if (events.isNotEmpty) const SizedBox(height: 14),
          _CTABanner(onTap: onMap),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  final TourPlace place;
  final ValueChanged<TourPlace> onTap;

  const _FeaturedBanner({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final regionLabel = _placeRegionLabel(place);
    final regionDescription = _placeRegionDescription(place);

    return GestureDetector(
      onTap: () => onTap(place),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 188,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (place.photoUrl != null)
                Image.network(
                  place.photoUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : _PhotoPlaceholder(place: place),
                  errorBuilder: (_, _, _) => _PhotoPlaceholder(place: place),
                )
              else
                _PhotoPlaceholder(place: place),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      stops: const [0.0, 0.42, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          regionLabel,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF5F8BFF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            '이번 주',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      regionDescription,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      place.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceSection extends StatelessWidget {
  final String title;
  final List<TourPlace> places;
  final VoidCallback onMoreTap;
  final ValueChanged<TourPlace> onPlaceTap;
  final bool showTagBadge;

  const _PlaceSection({
    required this.title,
    required this.places,
    required this.onMoreTap,
    required this.onPlaceTap,
    this.showTagBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final visiblePlaces = places.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                    height: 1.3,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onMoreTap,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '더보기',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: visiblePlaces.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.96,
            ),
            itemBuilder: (_, index) => _PlaceCard(
              place: visiblePlaces[index],
              onTap: () => onPlaceTap(visiblePlaces[index]),
              showTagBadge: showTagBadge,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final TourPlace place;
  final VoidCallback onTap;
  final bool showTagBadge;

  const _PlaceCard({
    required this.place,
    required this.onTap,
    this.showTagBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final tag = _tagInfo[place.placeTag]!;
    final regionLabel = _placeRegionLabel(place);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (place.photoUrl != null)
                Image.network(
                  place.photoUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : _PhotoPlaceholder(place: place),
                  errorBuilder: (_, _, _) => _PhotoPlaceholder(place: place),
                )
              else
                _PhotoPlaceholder(place: place),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                      stops: const [0.0, 0.38, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showTagBadge)
                      _PlaceTagBadge(tag: tag)
                    else
                      Row(
                        children: [
                          const Icon(
                            Icons.place,
                            color: Colors.white70,
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            regionLabel,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Text(
                      place.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceTagBadge extends StatelessWidget {
  final ({Color color, IconData icon, String label}) tag;

  const _PlaceTagBadge({required this.tag});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tag.color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.icon, color: Colors.white, size: 11),
          const SizedBox(width: 4),
          Text(
            tag.label,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  final TourPlace place;

  const _PhotoPlaceholder({required this.place});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFDCECF9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.photo_camera_outlined,
              color: Color(0xFF90CAF9),
              size: 28,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                place.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF5F89A8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _placeRegionLabel(TourPlace place) {
  if (place.areaName.isNotEmpty) return place.areaName;

  final parts = place.addr1
      .split(' ')
      .where((part) => part.trim().isNotEmpty)
      .toList();

  if (parts.isEmpty) return '추천';
  return parts.first;
}

String _placeRegionDescription(TourPlace place) {
  final region = _placeRegionLabel(place);
  const descriptions = {
    '서울': '도심 야경과 감성 스냅이 살아나는 이번 주 촬영지',
    '제주': '바다와 오름 풍경을 한 컷에 담기 좋은 이번 주 지역',
    '강원': '산과 호수 풍경이 시원하게 펼쳐지는 이번 주 명소',
    '부산': '바다와 도시 야경을 함께 담기 좋은 이번 주 스팟',
    '경남': '드라이브와 자연 풍경 촬영이 잘 어울리는 이번 주 지역',
    '경기': '가볍게 떠나기 좋은 근교 감성 스팟이 모인 지역',
    '전북': '한옥과 로컬 감성을 담기 좋은 이번 주 촬영지',
    '전남': '바다와 섬 풍경이 깊게 남는 이번 주 추천 지역',
    '경북': '전통과 자연 풍경을 함께 담기 좋은 이번 주 명소',
    '충남': '노을과 바닷가 분위기를 담기 좋은 이번 주 스팟',
    '충북': '호수와 숲 풍경이 차분하게 어울리는 이번 주 지역',
    '대구': '도시 감성과 전망 포인트가 살아나는 이번 주 촬영지',
    '광주': '전시와 거리 풍경을 함께 담기 좋은 이번 주 지역',
    '인천': '항구와 바다 무드를 한 번에 담기 좋은 이번 주 스팟',
    '대전': '한적한 공원과 도심 풍경이 어울리는 이번 주 지역',
    '울산': '바다와 산 풍경을 함께 담기 좋은 이번 주 촬영지',
    '세종': '여유로운 산책 풍경이 잘 살아나는 이번 주 지역',
  };

  return descriptions[region] ?? '지금 카메라 들고 떠나기 좋은 이번 주 추천 지역';
}

class _CTABanner extends StatelessWidget {
  final VoidCallback onTap;

  const _CTABanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF29B6F6), Color(0xFF0288D1)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '추천 촬영지를 지도에서 바로 열고',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '위치와 길찾기 정보를 확인해 보세요',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '스팟 지도 >',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
