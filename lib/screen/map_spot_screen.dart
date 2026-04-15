import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';

import '../services/driving_route_service.dart';
import '../services/tour_api_service.dart';
import '../models/photo_spot.dart';
import '../models/tour_place.dart';
import '../data/photo_spots_data.dart';

class MapSpotScreen extends StatefulWidget {
  /// 홈 화면에서 특정 장소를 포커스해서 열 때 사용
  final TourPlace? focusPlace;

  const MapSpotScreen({super.key, this.focusPlace});

  @override
  State<MapSpotScreen> createState() => _MapSpotScreenState();
}

class _MapSpotScreenState extends State<MapSpotScreen>
    with TickerProviderStateMixin {
  final _routeService = DrivingRouteService();
  final _tourApiService = TourApiService();

  NaverMapController? _mapController;
  SpotCategory _selectedCategory = SpotCategory.all;
  PhotoSpot? _selectedSpot;
  TourPlace? _focusedPlace; // 홈에서 넘어온 Tour 장소
  Position? _currentPosition;
  List<TourPlace> _nearbyPlaces = [];
  List<TourPlace> _keywordPlaces = [];
  _ActiveDrivingRoute? _activeRoute;
  bool _isLoadingNearbyPlaces = false;
  bool _isLoadingKeywords = false;
  bool _isLoadingRoute = false;

  // 커스텀 마커 이미지 캐시 (color → NOverlayImage)
  final Map<int, NOverlayImage> _markerImageCache = {};

  // 카테고리 → 검색 키워드 매핑 (전체 6개 카테고리)
  static const _categoryKeywords = {
    SpotCategory.cherry:  '벚꽃',
    SpotCategory.autumn:  '단풍',
    SpotCategory.sunrise: '일출',
    SpotCategory.sunset:  '일몰',
    SpotCategory.night:   '야경',
    SpotCategory.snow:    '설경',
  };

  late final AnimationController _cardAnimController;
  late final Animation<Offset> _cardSlide;

  static const _seoulLat = 37.5665;
  static const _seoulLng = 126.9780;
  static const _routeOverlayId = '__active_route__';

  List<PhotoSpot> get _filteredSpots => _selectedCategory == SpotCategory.all
      ? _nearbyPlaces
          .where((place) => place.latitude != null && place.longitude != null)
          .map(
            (place) => PhotoSpot(
              id: 'tour_${place.contentId}',
              name: place.title,
              address: place.address,
              latitude: place.latitude!,
              longitude: place.longitude!,
              category: SpotCategory.sunset,
              description: place.address,
            ),
          )
          .toList()
      : photoSpotsData.where((s) => s.category == _selectedCategory).toList();

  int get _visibleSpotCount => _selectedCategory == SpotCategory.all
      ? _nearbyPlaces.length
      : _filteredSpots.length + _keywordPlaces.length;

  String get _mapHeaderTitle => _selectedCategory == SpotCategory.all
      ? '내 주변 인기 스팟'
      : '${_selectedCategory.emoji} ${_selectedCategory.label} 명소';

  @override
  void initState() {
    super.initState();
    _cardAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _cardSlide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _cardAnimController,
            curve: Curves.easeOutCubic,
          ),
        );

    if (widget.focusPlace != null) {
      _focusedPlace = widget.focusPlace;
    }

    _requestLocation();
  }

  @override
  void dispose() {
    _cardAnimController.dispose();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      // 즉각적인 초기 위치: 마지막으로 알려진 위치 사용 (빠름)
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null && mounted) {
          setState(() {
            _currentPosition = lastPos;
            if (_keywordPlaces.isNotEmpty) {
              _keywordPlaces = _sortedByDistance(_keywordPlaces);
            }
          });
        }
      } catch (_) {}

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        // 위치 획득 후 카테고리 탭 스팟 거리순 재정렬
        if (_keywordPlaces.isNotEmpty) {
          _keywordPlaces = _sortedByDistance(_keywordPlaces);
        }
      });
      await _loadNearbyPlaces();
      await _updateLocationOverlay();
      if (widget.focusPlace == null && _selectedCategory == SpotCategory.all) {
        _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(
            target: NLatLng(pos.latitude, pos.longitude),
            zoom: 12.5,
          ),
        );
      }
      if (_activeRoute != null) {
        await _startRouteToDestination(
          _activeRoute!.destination,
          forceRefresh: true,
        );
      }
    } catch (_) {}
  }

  Future<void> _updateLocationOverlay() async {
    if (_mapController == null || _currentPosition == null) return;
    final overlay = _mapController!.getLocationOverlay();
    overlay.setIsVisible(true);
    overlay.setPosition(
      NLatLng(_currentPosition!.latitude, _currentPosition!.longitude),
    );
  }

  Future<void> _loadNearbyPlaces() async {
    if (_currentPosition == null) return;

    if (mounted) {
      setState(() => _isLoadingNearbyPlaces = true);
    }

    try {
      final places = await _tourApiService.fetchNearbySpots(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        count: 10,
      );
      if (!mounted) return;
      setState(() => _nearbyPlaces = places);
      if (_selectedCategory == SpotCategory.all) {
        await _buildMarkers();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _nearbyPlaces = []);
    } finally {
      if (mounted) {
        setState(() => _isLoadingNearbyPlaces = false);
      }
    }
  }

  Future<void> _selectNearbyPlace(TourPlace place) async {
    _clearRoute(updateState: false);
    setState(() {
      _activeRoute = null;
      _selectedSpot = null;
      _focusedPlace = place;
    });
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat != null && lng != null) {
      await _mapController?.updateCamera(
        NCameraUpdate.scrollAndZoomTo(
          target: NLatLng(lat - 0.012, lng),
          zoom: 13,
        ),
      );
    }
    _cardAnimController.forward(from: 0);
  }

  /// 색상 기반 커스텀 핀 마커 이미지 (캐시)
  Future<NOverlayImage> _getMarkerImage(Color color, {bool small = false}) async {
    final key = color.toARGB32() ^ (small ? 1 : 0);
    return _markerImageCache[key] ??= await NOverlayImage.fromWidget(
      widget: _CategoryPin(color: color, small: small),
      size: small ? const Size(26, 36) : const Size(32, 44),
      context: context,
    );
  }

  Future<void> _focusOnTourPlace() async {
    final place = _focusedPlace;
    if (_mapController == null || place == null) return;
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat == null || lng == null) return;

    // 마커는 _buildMarkers() 마지막의 _restoreFocusMarkerIfNeeded()에서 이미 추가됨
    // 여기서 중복 addOverlay 하면 같은 id로 충돌 → 맵 freeze 발생
    _mapController!.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(lat - 0.012, lng),
        zoom: 13,
      ),
    );
    _cardAnimController.forward(from: 0);
  }

  void _dismissFocus() {
    _clearRoute();
    _cardAnimController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _activeRoute = null;
        _focusedPlace = null;
      });
      _buildMarkers();
    });
  }

  Future<void> _buildMarkers() async {
    if (_mapController == null) return;
    await _mapController!.clearOverlays(type: NOverlayType.marker);

    if (_selectedCategory == SpotCategory.all) {
      final icon = await _getMarkerImage(const Color(0xFF29B6F6));
      for (final place in _nearbyPlaces) {
        final lat = place.latitude;
        final lng = place.longitude;
        if (lat == null || lng == null) continue;
        final marker = NMarker(
          id: 'tour_${place.contentId}',
          position: NLatLng(lat, lng),
        );
        marker.setIcon(icon);
        marker.setOnTapListener((_) { _selectNearbyPlace(place); return true; });
        await _mapController!.addOverlay(marker);
      }
    } else {
      final icon = await _getMarkerImage(_selectedCategory.color);
      for (final spot in _filteredSpots) {
        final marker = NMarker(
          id: spot.id,
          position: NLatLng(spot.latitude, spot.longitude),
        );
        marker.setIcon(icon);
        marker.setOnTapListener((_) { _selectSpot(spot); return true; });
        await _mapController!.addOverlay(marker);
      }
    }

    // clearOverlays 이후에도 포커스 마커는 항상 유지
    await _restoreFocusMarkerIfNeeded();
  }

  /// _buildMarkers()가 clearOverlays를 호출한 뒤 포커스 마커를 재추가한다.
  Future<void> _restoreFocusMarkerIfNeeded() async {
    final place = _focusedPlace;
    if (_mapController == null || place == null) return;
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat == null || lng == null) return;

    final icon = await _getMarkerImage(const Color(0xFF29B6F6));
    final marker = NMarker(id: '__tour_focus__', position: NLatLng(lat, lng));
    marker.setIcon(icon);
    marker.setOnTapListener((_) {
      _cardAnimController.forward(from: 0);
      return true;
    });
    await _mapController!.addOverlay(marker);
  }

  void _selectSpot(PhotoSpot spot) {
    _clearRoute(updateState: false);
    setState(() {
      _activeRoute = null;
      _focusedPlace = null;
      _selectedSpot = spot;
    });
    _cardAnimController.forward(from: 0);
    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(spot.latitude - 0.012, spot.longitude),
        zoom: 13,
      ),
    );
  }

  void _deselectSpot() {
    _clearRoute();
    _cardAnimController.reverse().then((_) {
      if (mounted) setState(() => _selectedSpot = null);
    });
  }

  Future<void> _onCategoryChanged(SpotCategory category) async {
    if (_selectedSpot != null) _deselectSpot();
    if (_focusedPlace != null) _dismissFocus();
    await _clearRoute();
    setState(() {
      _activeRoute = null;
      _focusedPlace = null;
      _selectedCategory = category;
      _keywordPlaces = [];
    });

    if (category != SpotCategory.all) {
      // 하드코딩 스팟 마커 먼저 표시
      await _buildMarkers();

      final spots = photoSpotsData.where((s) => s.category == category).toList();
      if (spots.isNotEmpty) {
        final avgLat = spots.map((s) => s.latitude).reduce((a, b) => a + b) / spots.length;
        final avgLng = spots.map((s) => s.longitude).reduce((a, b) => a + b) / spots.length;
        _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: NLatLng(avgLat, avgLng), zoom: 7),
        );
      }

      // Tour API 키워드 스팟 추가 로딩
      final keyword = _categoryKeywords[category];
      if (keyword != null) {
        if (mounted) setState(() => _isLoadingKeywords = true);
        // API 호출과 GPS 취득을 병렬 실행
        final rawFuture = _tourApiService.searchByKeyword(keyword, count: 80);
        final posFuture = _currentPosition == null
            ? Geolocator.getLastKnownPosition().catchError((_) => null)
            : null;
        // 위치 먼저 await (빠름) → API도 이미 진행 중
        if (posFuture != null) {
          final lastPos = await posFuture;
          if (lastPos != null && mounted) {
            setState(() => _currentPosition = lastPos);
          }
        }
        final raw = await rawFuture;
        if (!mounted || _selectedCategory != category) return;
        // 사진 있는 것만 필터 후 거리순 정렬
        final withPhoto = raw.where((p) => p.photoUrl != null).toList();
        final sorted = _sortedByDistance(withPhoto);
        setState(() {
          _keywordPlaces = sorted;
          _isLoadingKeywords = false;
        });
        await _addKeywordMarkers(sorted, category.color);
      }
    } else {
      await _loadNearbyPlaces();
      if (_currentPosition != null) {
        _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(
            target: NLatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            zoom: 12.5,
          ),
        );
      } else {
        _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(
            target: const NLatLng(_seoulLat, _seoulLng),
            zoom: 10.5,
          ),
        );
      }
    }
  }

  Future<void> _addKeywordMarkers(List<TourPlace> places, Color color) async {
    if (_mapController == null) return;
    final icon = await _getMarkerImage(color, small: true);
    for (final place in places) {
      final lat = place.latitude;
      final lng = place.longitude;
      if (lat == null || lng == null) continue;
      final marker = NMarker(
        id: 'kw_${place.contentId}',
        position: NLatLng(lat, lng),
      );
      marker.setIcon(icon);
      marker.setOnTapListener((_) { _selectNearbyPlace(place); return true; });
      await _mapController!.addOverlay(marker);
    }
  }

  void _goToMyLocation() {
    if (_currentPosition == null) return;
    _mapController?.updateCamera(
      NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        ),
        zoom: 14,
      ),
    );
  }

  String? _distanceText(PhotoSpot spot) {
    if (_currentPosition == null) return null;
    final d = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      spot.latitude,
      spot.longitude,
    );
    return d < 1000 ? '${d.round()}m' : '${(d / 1000).toStringAsFixed(1)}km';
  }

  Future<void> _clearRoute({bool updateState = true}) async {
    if (_mapController != null) {
      await _mapController!.clearOverlays(type: NOverlayType.pathOverlay);
      await _mapController!.clearOverlays(type: NOverlayType.polylineOverlay);
    }
    if (updateState && mounted && _activeRoute != null) {
      setState(() => _activeRoute = null);
    }
  }

  Future<bool> _ensureCurrentLocation() async {
    if (_currentPosition != null) return true;
    await _requestLocation();
    if (_currentPosition != null) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('현재 위치를 확인하면 앱 내 길찾기를 시작할 수 있어요'),
        backgroundColor: const Color(0xFF29B6F6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    return false;
  }

  Future<void> _startRouteToDestination(
    _RouteDestination destination, {
    bool forceRefresh = false,
  }) async {
    if (!await _ensureCurrentLocation()) return;

    if (!forceRefresh && _activeRoute?.destination.id == destination.id) {
      await _fitRouteToScreen(_activeRoute!.route.path);
      return;
    }

    if (mounted) {
      setState(() => _isLoadingRoute = true);
    }

    try {
      final route = await _routeService.fetchDrivingRoute(
        startLat: _currentPosition!.latitude,
        startLng: _currentPosition!.longitude,
        goalLat: destination.latitude,
        goalLng: destination.longitude,
      );
      if (!mounted) return;
      setState(() {
        _activeRoute = _ActiveDrivingRoute(
          destination: destination,
          route: route,
        );
      });
      await _drawRoute(route);
    } on DrivingRouteException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: const Color(0xFF29B6F6),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingRoute = false);
      }
    }
  }

  Future<void> _drawRoute(DrivingRoute route) async {
    if (_mapController == null || route.path.length < 2) return;
    await _clearRoute(updateState: false);

    final coords = route.path
        .map((point) => NLatLng(point.lat, point.lng))
        .toList();

    final routeOverlay = NPolylineOverlay(
      id: _routeOverlayId,
      coords: coords,
      width: 6,
      color: const Color(0xFF29B6F6),
      lineCap: NLineCap.round,
      lineJoin: NLineJoin.round,
    );
    routeOverlay.setGlobalZIndex(250000);
    await _mapController!.addOverlay(routeOverlay);
    await _fitRouteToScreen(route.path);
  }

  Future<void> _fitRouteToScreen(List<RoutePoint> path) async {
    if (_mapController == null || path.length < 2) return;
    final update = NCameraUpdate.fitBounds(
      NLatLngBounds.from(path.map((point) => NLatLng(point.lat, point.lng))),
      padding: const EdgeInsets.fromLTRB(48, 140, 48, 280),
    );
    update.setAnimation(duration: const Duration(milliseconds: 900));
    await _mapController!.updateCamera(update);
  }

  Future<void> _startRouteToSpot(PhotoSpot spot) {
    return _startRouteToDestination(_RouteDestination.fromSpot(spot));
  }

  Future<void> _startRouteToPlace(TourPlace place) async {
    final destination = _RouteDestination.fromPlace(place);
    if (destination == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${place.title}의 위치 정보가 아직 없어요'),
          backgroundColor: const Color(0xFF29B6F6),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }
    await _startRouteToDestination(destination);
  }

  /// TourPlace 목록을 현재 위치 기준 거리순 정렬
  List<TourPlace> _sortedByDistance(List<TourPlace> places) {
    if (_currentPosition == null) return places;
    final sorted = List<TourPlace>.from(places);
    sorted.sort((a, b) {
      final da = _distToPlace(a);
      final db = _distToPlace(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return sorted;
  }

  double? _distToPlace(TourPlace p) {
    final lat = p.latitude;
    final lng = p.longitude;
    if (_currentPosition == null || lat == null || lng == null) return null;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
  }

  /// PhotoSpot 목록을 현재 위치 기준 거리순 정렬
  List<PhotoSpot> _sortedSpotsByDistance(List<PhotoSpot> spots) {
    if (_currentPosition == null) return spots;
    final sorted = List<PhotoSpot>.from(spots);
    sorted.sort((a, b) {
      final da = Geolocator.distanceBetween(
          _currentPosition!.latitude, _currentPosition!.longitude,
          a.latitude, a.longitude);
      final db = Geolocator.distanceBetween(
          _currentPosition!.latitude, _currentPosition!.longitude,
          b.latitude, b.longitude);
      return da.compareTo(db);
    });
    return sorted;
  }

  String? _routeSummaryForSpot(PhotoSpot spot) {
    if (_activeRoute?.destination.id != spot.id) return null;
    return _activeRoute?.route.summaryText;
  }

  String? _routeSummaryForPlace(TourPlace place) {
    if (_activeRoute?.destination.id != place.contentId) return null;
    return _activeRoute?.route.summaryText;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── 네이버 지도 ────────────────────────────────────
          NaverMap(
            options: const NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: NLatLng(_seoulLat, _seoulLng),
                zoom: 10.5,
              ),
              locationButtonEnable: false,
              consumeSymbolTapEvents: false,
            ),
            onMapReady: (controller) async {
              _mapController = controller;
              await _buildMarkers();
              await _updateLocationOverlay();
              await _focusOnTourPlace();
            },
            onMapTapped: (_, _) {
              if (_activeRoute != null) _clearRoute();
              if (_selectedSpot != null) _deselectSpot();
              if (_focusedPlace != null) _dismissFocus();
            },
          ),

          // ── 상단 오버레이 ──────────────────────────────────
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _MapIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              const Icon(
                                Icons.photo_camera_outlined,
                                color: Color(0xFF29B6F6),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _mapHeaderTitle,
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F7FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$_visibleSpotCount곳',
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF29B6F6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ── 카테고리 필터 칩 ──────────────────────────
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: SpotCategory.values.map((cat) {
                      final selected = _selectedCategory == cat;
                      return GestureDetector(
                        onTap: () => _onCategoryChanged(cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? cat.color : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: selected
                                    ? cat.color.withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.08),
                                blurRadius: selected ? 8 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cat.emoji,
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                cat.label,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF555555),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // ── 현재 위치 FAB ──────────────────────────────────
          Positioned(
            right: 14,
            bottom: (_selectedSpot != null || _focusedPlace != null)
                ? 250
                : 110,
            child: _MapIconButton(
              icon: Icons.my_location_rounded,
              onTap: _goToMyLocation,
            ),
          ),

          // ── 스팟 목록 패널 (선택 없을 때) ─────────────────
          if (_selectedSpot == null &&
              _focusedPlace == null &&
              _selectedCategory == SpotCategory.all)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _NearbyPlaceListPanel(
                title: '내 주변 인기 스팟',
                places: _sortedByDistance(_nearbyPlaces),
                currentPosition: _currentPosition,
                isLoading: _isLoadingNearbyPlaces,
                onPlaceTap: _selectNearbyPlace,
                onLocationTap: _goToMyLocation,
              ),
            ),

          if (_selectedSpot == null &&
              _focusedPlace == null &&
              _selectedCategory != SpotCategory.all)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _keywordPlaces.isNotEmpty || _isLoadingKeywords
                  ? _NearbyPlaceListPanel(
                      title: '${_selectedCategory.emoji} ${_selectedCategory.label} 추천 스팟',
                      places: _sortedByDistance(_keywordPlaces),
                      currentPosition: _currentPosition,
                      isLoading: _isLoadingKeywords,
                      onPlaceTap: _selectNearbyPlace,
                      onLocationTap: _goToMyLocation,
                    )
                  : _SpotListPanel(
                      title: '${_selectedCategory.label} 촬영 스팟',
                      spots: _sortedSpotsByDistance(_filteredSpots),
                      currentPosition: _currentPosition,
                      onSpotTap: _selectSpot,
                      onLocationTap: _goToMyLocation,
                    ),
            ),

          // ── 스팟 상세 카드 (마커 탭 시) ───────────────────
          if (_selectedSpot != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _cardSlide,
                child: _SpotDetailCard(
                  spot: _selectedSpot!,
                  distanceText: _distanceText(_selectedSpot!),
                  routeSummary: _routeSummaryForSpot(_selectedSpot!),
                  isRouting: _isLoadingRoute,
                  onClose: _deselectSpot,
                  onRouteTap: () => _startRouteToSpot(_selectedSpot!),
                ),
              ),
            ),

          // ── Tour 장소 상세 카드 (홈에서 진입 시) ─────────
          if (_focusedPlace != null && _selectedSpot == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _cardSlide,
                child: _TourPlaceCard(
                  place: _focusedPlace!,
                  routeSummary: _routeSummaryForPlace(_focusedPlace!),
                  isRouting: _isLoadingRoute,
                  onClose: _dismissFocus,
                  onRouteTap: () => _startRouteToPlace(_focusedPlace!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 지도 아이콘 버튼
// ─────────────────────────────────────────────────────────
class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF333333)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 하단 스팟 목록 패널
// ─────────────────────────────────────────────────────────
class _NearbyPlaceListPanel extends StatelessWidget {
  final String title;
  final List<TourPlace> places;
  final Position? currentPosition;
  final bool isLoading;
  final ValueChanged<TourPlace> onPlaceTap;
  final VoidCallback onLocationTap;

  const _NearbyPlaceListPanel({
    required this.title,
    required this.places,
    required this.currentPosition,
    required this.isLoading,
    required this.onPlaceTap,
    required this.onLocationTap,
  });

  String? _distance(TourPlace place) {
    final lat = place.latitude;
    final lng = place.longitude;
    if (currentPosition == null || lat == null || lng == null) return null;

    final d = Geolocator.distanceBetween(
      currentPosition!.latitude,
      currentPosition!.longitude,
      lat,
      lng,
    );
    return d < 1000 ? '${d.round()}m' : '${(d / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${places.length}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF29B6F6),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onLocationTap,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F7FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      size: 16,
                      color: Color(0xFF29B6F6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          SizedBox(
            height: 88,
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : places.isEmpty
                    ? const Center(
                        child: Text(
                          '내 주변에서 불러온 관광 스팟이 아직 없습니다',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 13,
                            color: Color(0xFF999999),
                          ),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        itemCount: places.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final place = places[i];
                          return GestureDetector(
                            onTap: () => onPlaceTap(place),
                            child: Container(
                              width: 180,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F8FB),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFF0F1F3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 42,
                                      height: 42,
                                      child: place.photoUrl != null
                                          ? Image.network(
                                              place.photoUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  _TourPlaceThumbFallback(
                                                label: place.title,
                                              ),
                                            )
                                          : _TourPlaceThumbFallback(
                                              label: place.title,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          place.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1A1A2E),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _distance(place) ?? place.areaName,
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 10,
                                            color: Color(0xFF29B6F6),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _TourPlaceThumbFallback extends StatelessWidget {
  final String label;

  const _TourPlaceThumbFallback({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE3F4FD),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_camera_outlined,
              size: 16, color: Color(0xFF90CAF9)),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: Color(0xFF90CAF9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SpotListPanel extends StatelessWidget {
  final String title;
  final List<PhotoSpot> spots;
  final Position? currentPosition;
  final ValueChanged<PhotoSpot> onSpotTap;
  final VoidCallback onLocationTap;

  const _SpotListPanel({
    required this.title,
    required this.spots,
    required this.currentPosition,
    required this.onSpotTap,
    required this.onLocationTap,
  });

  String? _distance(PhotoSpot spot) {
    if (currentPosition == null) return null;
    final d = Geolocator.distanceBetween(
      currentPosition!.latitude,
      currentPosition!.longitude,
      spot.latitude,
      spot.longitude,
    );
    return d < 1000 ? '${d.round()}m' : '${(d / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${spots.length}',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF29B6F6),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onLocationTap,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F7FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.my_location_rounded,
                      size: 16,
                      color: Color(0xFF29B6F6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          SizedBox(
            height: 88,
            child: spots.isEmpty
                ? const Center(
                    child: Text(
                      '해당 카테고리의 스팟이 없습니다',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        color: Color(0xFF999999),
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: spots.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final spot = spots[i];
                      return GestureDetector(
                        onTap: () => onSpotTap(spot),
                        child: Container(
                          width: 160,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FB),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF0F1F3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: spot.category.color.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    spot.category.emoji,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      spot.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _distance(spot) ?? spot.category.label,
                                      style: TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 10,
                                        color: spot.category.color,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// 스팟 상세 카드
// ─────────────────────────────────────────────────────────
class _SpotDetailCard extends StatelessWidget {
  final PhotoSpot spot;
  final String? distanceText;
  final String? routeSummary;
  final bool isRouting;
  final VoidCallback onClose;
  final VoidCallback onRouteTap;

  const _SpotDetailCard({
    required this.spot,
    required this.distanceText,
    required this.routeSummary,
    required this.isRouting,
    required this.onClose,
    required this.onRouteTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDDDDD),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: spot.category.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    spot.category.emoji,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: spot.category.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            spot.category.label,
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: spot.category.color,
                            ),
                          ),
                        ),
                        if (distanceText != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            distanceText!,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 11,
                              color: Color(0xFF999999),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      spot.name,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 14,
                color: Colors.grey.shade400,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  spot.address,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
          if (spot.bestSeason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 13,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                Text(
                  '베스트 시즌  ${spot.bestSeason}',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            spot.description,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              color: Color(0xFF444444),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: spot.tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F1F3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '#$tag',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          if (routeSummary != null) ...[
            const SizedBox(height: 14),
            _RouteInfoBox(summary: routeSummary!),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: isRouting ? null : onRouteTap,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF29B6F6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isRouting) ...[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '길찾는 중',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ] else ...[
                          const Icon(
                            Icons.directions_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '길찾기',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: GestureDetector(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${spot.name} 저장됨'),
                      backgroundColor: const Color(0xFF5C6BC0),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  ),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F1F3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bookmark_border_rounded,
                          color: Color(0xFF555555),
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '저장',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF555555),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TourPlaceCard extends StatelessWidget {
  final TourPlace place;
  final String? routeSummary;
  final bool isRouting;
  final VoidCallback onClose;
  final VoidCallback onRouteTap;

  const _TourPlaceCard({
    required this.place,
    required this.routeSummary,
    required this.isRouting,
    required this.onClose,
    required this.onRouteTap,
  });

  String get _typeLabel => place.contentTypeId == '15' ? '축제 스팟' : '촬영 스팟';

  String get _introText => place.contentTypeId == '15'
      ? '축제 분위기와 현장 스냅을 함께 담기 좋은 추천 장소예요.'
      : '지금 바로 사진 찍으러 가기 좋은 추천 장소예요.';

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPad + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDDDDD),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: place.photoUrl != null
                      ? Image.network(
                          place.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              _TourPlacePhotoPlaceholder(place: place),
                        )
                      : _TourPlacePhotoPlaceholder(place: place),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3F7FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _typeLabel,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF29B6F6),
                            ),
                          ),
                        ),
                        if (place.areaName.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F1F3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              place.areaName,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF666666),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      place.title,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                        height: 1.3,
                      ),
                    ),
                    if (place.address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              place.address,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                color: Colors.grey.shade500,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _introText,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              color: Color(0xFF444444),
              height: 1.5,
            ),
          ),
          if (routeSummary != null) ...[
            const SizedBox(height: 14),
            _RouteInfoBox(summary: routeSummary!),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: isRouting ? null : onRouteTap,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF29B6F6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isRouting) ...[
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '길찾는 중',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ] else ...[
                          const Icon(
                            Icons.directions_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '길찾기',
                            style: TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onClose,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F1F3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Color(0xFF555555),
                          size: 20,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '닫기',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF555555),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteInfoBox extends StatelessWidget {
  final String summary;

  const _RouteInfoBox({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.route_rounded, size: 18, color: Color(0xFF29B6F6)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '현재 위치 기준 길찾기',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    color: Color(0xFF4F5B67),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TourPlacePhotoPlaceholder extends StatelessWidget {
  final TourPlace place;

  const _TourPlacePhotoPlaceholder({required this.place});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE8F4FD),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            place.areaName.isNotEmpty ? place.areaName : 'POZY',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF90CAF9),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteDestination {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  const _RouteDestination({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory _RouteDestination.fromSpot(PhotoSpot spot) {
    return _RouteDestination(
      id: spot.id,
      name: spot.name,
      latitude: spot.latitude,
      longitude: spot.longitude,
    );
  }

  static _RouteDestination? fromPlace(TourPlace place) {
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat == null || lng == null) return null;
    return _RouteDestination(
      id: place.contentId,
      name: place.title,
      latitude: lat,
      longitude: lng,
    );
  }
}

class _ActiveDrivingRoute {
  final _RouteDestination destination;
  final DrivingRoute route;

  const _ActiveDrivingRoute({required this.destination, required this.route});
}

// ─────────────────────────────────────────────────────────
// 카테고리 색상 핀 마커 위젯 (NOverlayImage.fromWidget 용)
// ─────────────────────────────────────────────────────────
class _CategoryPin extends StatelessWidget {
  final Color color;
  final bool small;
  const _CategoryPin({required this.color, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 28.0 : 36.0;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_on, color: Colors.white, size: size + 4),
        Icon(Icons.location_on, color: color, size: size),
      ],
    );
  }
}
