import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';

import '../services/driving_route_service.dart';
import '../services/spot_theme_rule_service.dart';
import '../services/tour_api_service.dart';
import '../models/photo_spot.dart';
import '../models/tour_place.dart';

class MapSpotScreen extends StatefulWidget {
  /// 홈 화면에서 특정 장소를 포커스해서 열 때 사용
  final TourPlace? focusPlace;
  final String? initialAreaCode;
  final String? initialAreaName;
  final List<TourPlace> initialAreaPlaces;

  const MapSpotScreen({
    super.key,
    this.focusPlace,
    this.initialAreaCode,
    this.initialAreaName,
    this.initialAreaPlaces = const [],
  });

  @override
  State<MapSpotScreen> createState() => _MapSpotScreenState();
}

class _MapSpotScreenState extends State<MapSpotScreen>
    with TickerProviderStateMixin {
  final _routeService = DrivingRouteService();
  final _themeRuleService = SpotThemeRuleService();
  final _tourApiService = TourApiService();

  NaverMapController? _mapController;
  SpotCategory _selectedCategory = SpotCategory.all;
  TourPlace? _focusedPlace; // 홈에서 넘어온 Tour 장소
  TourPlace? _recentPlace;
  String? _activeSearchKeyword;
  Position? _currentPosition;
  List<TourPlace> _nearbyPlaces = [];
  List<TourPlace> _keywordPlaces = [];
  _ActiveDrivingRoute? _activeRoute;
  bool _isAreaMode = false;
  bool _isLoadingNearbyPlaces = false;
  bool _isLoadingKeywords = false;
  bool _isLoadingRoute = false;

  // 커스텀 마커 이미지 캐시 (color → NOverlayImage)
  final Map<int, NOverlayImage> _markerImageCache = {};

  static const _categoryListLimit = 10;
  static const _excludedBusinessTitleTokens = [
    '\uB9C8\uD2B8',
    '\uC57D\uAD6D',
    '\uBCD1\uC6D0',
    '\uC758\uC6D0',
    '\uCE58\uACFC',
    '\uD3B8\uC758\uC810',
    '\uC8FC\uC720\uC18C',
    '\uCDA9\uC804\uC18C',
    '\uC740\uD589',
    '\uBD80\uB3D9\uC0B0',
    '\uC544\uD30C\uD2B8',
    '\uC624\uD53C\uC2A4\uD154',
    '\uD638\uD154',
    '\uBAA8\uD154',
    '\uD39C\uC158',
    '\uB9AC\uC870\uD2B8',
    '\uCE74\uD398',
    '\uCE74\uD398\uAC70\uB9AC',
    '\uC2DD\uB2F9',
    '\uC2DD\uB2F9\uAC00',
    '\uC74C\uC2DD\uC810',
    '\uC74C\uC2DD\uAC70\uB9AC',
    '\uB9DB\uC9D1',
    '\uB9DB\uC9D1\uAC70\uB9AC',
    '\uBA39\uAC70\uB9AC',
    '\uBA39\uC790\uACE8\uBAA9',
    '\uC804 \uACE8\uBAA9',
    '\uC804\uACE8\uBAA9',
    '\uC871\uBC1C',
    '\uB2ED\uAC08\uBE44',
    '\uB9C9\uAD6D\uC218',
    '\uC21C\uB300',
    '\uAD6D\uBC25',
    '\uD574\uC7A5\uAD6D',
    '\uACF1\uCC3D',
    '\uC870\uAC1C',
    '\uCE58\uD0A8',
    '\uD68C\uC13C\uD130',
    '\uD69F\uC9D1',
    '\uD3EC\uCC28',
    '\uBC31\uD654\uC810',
    '\uC1FC\uD551\uBAB0',
  ];

  static const _nearbySpotListLimit = 20;
  late final AnimationController _cardAnimController;
  late final Animation<Offset> _cardSlide;

  static const _seoulLat = 37.5665;
  static const _seoulLng = 126.9780;
  static const _routeOverlayId = '__active_route__';
  static const _nearbySpotRadiusMeters = 5000;
  static const _nearbySpotFallbackRadiusMeters = 12000;
  bool get _isKeywordMode => _activeSearchKeyword != null;

  int get _visibleSpotCount =>
      _selectedCategory == SpotCategory.all && !_isKeywordMode
      ? _nearbyPlaces.length
      : _keywordPlaces.length;

  List<TourPlace> get _visibleKeywordPlaces =>
      _sortedByDistance(_keywordPlaces).take(_categoryListLimit).toList();

  String get _searchBarText {
    if (_isAreaMode) return '${widget.initialAreaName} 추천 스팟';
    if (_isKeywordMode) return '"$_activeSearchKeyword" 검색 결과';
    if (_selectedCategory != SpotCategory.all) {
      return '${_selectedCategory.emoji} ${_selectedCategory.label} 스팟';
    }
    return '장소/분위기 검색';
  }

  String get _resultPanelTitle {
    if (_isAreaMode) return '${widget.initialAreaName} 추천 촬영 스팟';
    if (_isKeywordMode) return '"$_activeSearchKeyword" 검색 스팟';
    if (_selectedCategory == SpotCategory.all) return '내 주변 촬영 스팟';
    return '${_selectedCategory.emoji} ${_selectedCategory.label} 추천 스팟';
  }

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
    } else if (widget.initialAreaPlaces.isNotEmpty) {
      _isAreaMode = true;
      _activeSearchKeyword = widget.initialAreaName ?? '추천 지역';
      _keywordPlaces = widget.initialAreaPlaces
          .where((place) => place.latitude != null && place.longitude != null)
          .toList();
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

      Position? lastPos;
      try {
        lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null && mounted) {
          setState(() {
            _currentPosition = lastPos;
            if (_keywordPlaces.isNotEmpty) {
              _keywordPlaces = _sortedByDistance(_keywordPlaces);
            }
          });
          unawaited(_loadNearbyPlaces());
        }
      } catch (_) {}

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      final shouldReload =
          lastPos == null ||
          Geolocator.distanceBetween(
                lastPos.latitude,
                lastPos.longitude,
                pos.latitude,
                pos.longitude,
              ) >
              500;

      setState(() {
        _currentPosition = pos;
        if (_keywordPlaces.isNotEmpty) {
          _keywordPlaces = _sortedByDistance(_keywordPlaces);
        }
      });

      if (shouldReload) await _loadNearbyPlaces();
      await _updateLocationOverlay();

      if (widget.focusPlace == null &&
          _selectedCategory == SpotCategory.all &&
          !_isKeywordMode &&
          !_isAreaMode) {
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

  Future<void> _loadInitialAreaPlaces() async {
    final areaCode = widget.initialAreaCode;
    if (areaCode == null || areaCode.isEmpty) return;

    if (mounted) {
      setState(() => _isLoadingKeywords = true);
    }

    try {
      final places = await _tourApiService.fetchAreaPhotoSpots(
        areaCode: areaCode,
        count: 60,
      );
      if (!mounted || !_isAreaMode) return;

      final filtered = places
          .where((place) => place.latitude != null && place.longitude != null)
          .toList();
      if (filtered.isEmpty) {
        setState(() => _isLoadingKeywords = false);
        return;
      }

      setState(() {
        _keywordPlaces = filtered;
        _isLoadingKeywords = false;
      });
      await _buildMarkers();
      await _fitPlacesToScreen(filtered);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingKeywords = false);
    }
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
      var places = await _tourApiService.fetchNearbySpots(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        radius: _nearbySpotRadiusMeters,
        count: _nearbySpotListLimit,
      );
      if (places.length < 3) {
        final fallbackPlaces = await _tourApiService.fetchNearbySpots(
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          radius: _nearbySpotFallbackRadiusMeters,
          count: _nearbySpotListLimit,
        );
        places = _mergePlacesByDistance([...places, ...fallbackPlaces]);
      }
      if (!mounted) return;
      setState(() {
        _nearbyPlaces = _sortedByDistance(
          places,
        ).take(_nearbySpotListLimit).toList();
      });
      if (_selectedCategory == SpotCategory.all && !_isKeywordMode) {
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
    await _clearRoute(updateState: false);

    if (!mounted) return;
    setState(() {
      _activeRoute = null;
      _focusedPlace = place;
      _recentPlace = place;
    });

    final lat = place.latitude;
    final lng = place.longitude;

    if (lat != null && lng != null) {
      final update = NCameraUpdate.scrollAndZoomTo(
        target: NLatLng(lat - 0.012, lng),
        zoom: 13,
      );
      update.setAnimation(duration: const Duration(milliseconds: 700));
      await _mapController?.updateCamera(update);
    }

    if (mounted) {
      _cardAnimController.forward(from: 0);
    }
  }

  Future<NOverlayImage> _getMarkerImage(
    Color color, {
    bool small = false,
  }) async {
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

    final update = NCameraUpdate.scrollAndZoomTo(
      target: NLatLng(lat - 0.012, lng),
      zoom: 13,
    );
    update.setAnimation(duration: const Duration(milliseconds: 700));
    await _mapController!.updateCamera(update);

    if (mounted) {
      _cardAnimController.forward(from: 0);
    }
  }

  void _dismissFocus() {
    final dismissedPlace = _focusedPlace;
    _clearRoute();
    _cardAnimController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _activeRoute = null;
        _focusedPlace = null;
        _recentPlace = dismissedPlace;
      });
      _buildMarkers();
    });
  }

  Future<void> _buildMarkers() async {
    if (_mapController == null) return;
    await _mapController!.clearOverlays(type: NOverlayType.marker);

    if (_selectedCategory == SpotCategory.all && !_isKeywordMode) {
      final icon = await _getMarkerImage(const Color(0xFF4A9FE8));
      for (final place in _nearbyPlaces) {
        final lat = place.latitude;
        final lng = place.longitude;
        if (lat == null || lng == null) continue;
        final marker = NMarker(
          id: 'tour_${place.contentId}',
          position: NLatLng(lat, lng),
        );
        marker.setIcon(icon);
        marker.setOnTapListener((_) {
          _selectNearbyPlace(place);
          return true;
        });
        await _mapController!.addOverlay(marker);
      }
    } else {
      final icon = await _getMarkerImage(_selectedCategory.color, small: true);
      for (final place in _keywordPlaces) {
        final lat = place.latitude;
        final lng = place.longitude;
        if (lat == null || lng == null) continue;
        final marker = NMarker(
          id: 'kw_${place.contentId}',
          position: NLatLng(lat, lng),
        );
        marker.setIcon(icon);
        marker.setOnTapListener((_) {
          _selectNearbyPlace(place);
          return true;
        });
        await _mapController!.addOverlay(marker);
      }
    }

    await _restoreFocusMarkerIfNeeded();
  }

  Future<void> _restoreFocusMarkerIfNeeded() async {
    final place = _focusedPlace ?? _recentPlace;
    if (_mapController == null || place == null) return;
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat == null || lng == null) return;

    final icon = await _getMarkerImage(const Color(0xFF4A9FE8));
    final marker = NMarker(
      id: _focusedPlace != null ? '__tour_focus__' : '__tour_recent__',
      position: NLatLng(lat, lng),
    );
    marker.setIcon(icon);
    marker.setOnTapListener((_) {
      _selectNearbyPlace(place);
      return true;
    });
    await _mapController!.addOverlay(marker);
  }

  Future<void> _onCategoryChanged(SpotCategory category) async {
    if (_focusedPlace != null) _dismissFocus();
    await _clearRoute();
    setState(() {
      _activeRoute = null;
      _focusedPlace = null;
      _recentPlace = null;
      _activeSearchKeyword = null;
      _isAreaMode = false;
      _selectedCategory = category;
      _keywordPlaces = [];
    });

    if (category != SpotCategory.all) {
      await _buildMarkers();

      final rules = await _themeRuleService.loadRules();
      final config = rules[category];
      if (config != null) {
        if (mounted) setState(() => _isLoadingKeywords = true);

        final rawFuture = _tourApiService.searchByKeywords(
          config.queries,
          count: 360,
          pages: 4,
          rowsPerPage: 50,
          prioritizePhotoSpots: false,
        );

        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
            ),
          ).timeout(const Duration(seconds: 4));
          if (mounted) setState(() => _currentPosition = pos);
        } catch (_) {
          if (_currentPosition == null) {
            try {
              final lastPos = await Geolocator.getLastKnownPosition();
              if (lastPos != null && mounted) {
                setState(() => _currentPosition = lastPos);
              }
            } catch (_) {}
          }
        }

        final raw = await rawFuture;
        if (!mounted || _selectedCategory != category) return;

        final filtered = await _filterCategoryPlaces(raw, config);
        final sorted = _sortedByDistance(filtered);

        setState(() {
          _keywordPlaces = sorted;
          _isLoadingKeywords = false;
        });

        await _buildMarkers();
        await _fitPlacesToScreen(sorted);
      }
    } else {
      await _loadNearbyPlaces();
      if (_currentPosition != null) {
        _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(
            target: NLatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
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

  Future<void> _showCategoryPicker() async {
    final selected = await showModalBottomSheet<SpotCategory>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryPickerSheet(selectedCategory: _selectedCategory),
    );
    if (selected == null || selected == _selectedCategory) return;
    await _onCategoryChanged(selected);
  }

  Future<void> _showSearchSheet() async {
    final keyword = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SpotSearchSheet(initialKeyword: _activeSearchKeyword),
    );
    final trimmed = keyword?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await _searchSpots(trimmed);
  }

  Future<void> _searchSpots(String keyword) async {
    if (_focusedPlace != null) _dismissFocus();
    await _clearRoute();
    if (!mounted) return;

    setState(() {
      _activeRoute = null;
      _focusedPlace = null;
      _recentPlace = null;
      _activeSearchKeyword = keyword;
      _isAreaMode = false;
      _selectedCategory = SpotCategory.all;
      _keywordPlaces = [];
      _isLoadingKeywords = true;
    });

    await _buildMarkers();

    try {
      final raw = await _tourApiService.searchByKeyword(keyword, count: 80);
      if (!mounted || _activeSearchKeyword != keyword) return;
      final filtered = _filterSearchPlaces(raw);
      final sorted = _sortedByDistance(filtered);
      setState(() {
        _keywordPlaces = sorted;
        _isLoadingKeywords = false;
      });
      await _buildMarkers();
      await _fitPlacesToScreen(sorted);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _keywordPlaces = [];
        _isLoadingKeywords = false;
      });
    }
  }

  List<TourPlace> _filterSearchPlaces(List<TourPlace> places) {
    final seenIds = <String>{};
    final filtered = <TourPlace>[];
    for (final place in places) {
      final title = place.title.trim();
      if (place.contentId.isEmpty || !seenIds.add(place.contentId)) continue;
      if (title.isEmpty || place.latitude == null || place.longitude == null) {
        continue;
      }
      if (_excludedBusinessTitleTokens.any(title.contains) ||
          !place.isPhotoSpotCandidate) {
        continue;
      }
      filtered.add(place);
    }
    filtered.sort((a, b) {
      final scoreCompare = b.photoSpotScore.compareTo(a.photoSpotScore);
      if (scoreCompare != 0) return scoreCompare;
      return a.title.compareTo(b.title);
    });
    return filtered;
  }

  Future<List<TourPlace>> _filterCategoryPlaces(
    List<TourPlace> places,
    SpotThemeRule config,
  ) async {
    final seenIds = <String>{};
    final filtered = <TourPlace>[];
    final overviewCandidates = <TourPlace>[];

    for (final place in places) {
      final title = place.title.trim();
      if (place.contentId.isEmpty || !seenIds.add(place.contentId)) {
        continue;
      }
      if (title.isEmpty || place.latitude == null || place.longitude == null) {
        continue;
      }
      final matchesTitle = config.matchesTitle(title);
      if (_excludedBusinessTitleTokens.any(title.contains) ||
          config.excludes(title)) {
        continue;
      }
      if (matchesTitle) {
        filtered.add(place);
        continue;
      }
      overviewCandidates.add(place);
    }

    for (final place in overviewCandidates.take(80)) {
      final overview = await _tourApiService.fetchOverview(place);
      if (overview != null && config.matchesOverview(overview)) {
        filtered.add(place);
      }
    }

    filtered.sort((a, b) {
      final scoreCompare = _scoreCategoryPlace(
        b,
        config,
      ).compareTo(_scoreCategoryPlace(a, config));
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.title.compareTo(b.title);
    });

    return filtered;
  }

  int _scoreCategoryPlace(TourPlace place, SpotThemeRule config) {
    var score = 0;
    score += place.photoSpotScore;
    if (place.photoUrl != null) score += 4;
    if (config.matchesTitle(place.title)) score += 6;
    switch (place.placeTag) {
      case PlaceTag.nature:
        score += 3;
        break;
      case PlaceTag.landmark:
        score += 2;
        break;
      case PlaceTag.architecture:
        score += 2;
        break;
      case PlaceTag.culture:
      case PlaceTag.history:
        score += 1;
        break;
    }

    return score;
  }

  Future<void> _fitPlacesToScreen(List<TourPlace> places) async {
    if (_mapController == null) return;

    final coords = places
        .where((place) => place.latitude != null && place.longitude != null)
        .map((place) => NLatLng(place.latitude!, place.longitude!))
        .toList();
    if (coords.isEmpty) return;

    if (coords.length == 1) {
      await _mapController!.updateCamera(
        NCameraUpdate.scrollAndZoomTo(target: coords.first, zoom: 11.5),
      );
      return;
    }

    final update = NCameraUpdate.fitBounds(
      NLatLngBounds.from(coords),
      padding: const EdgeInsets.fromLTRB(48, 140, 48, 220),
    );
    update.setAnimation(duration: const Duration(milliseconds: 900));
    await _mapController!.updateCamera(update);
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
        content: const Text(
          '\uD604\uC7AC \uC704\uCE58\uB97C \uD655\uC778\uD558\uBA74 \uBC14\uB85C \uAE38\uCC3E\uAE30\uB97C \uC2DC\uC791\uD560 \uC218 \uC788\uC5B4\uC694.',
        ),
        backgroundColor: const Color(0xFF4A9FE8),
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
          backgroundColor: const Color(0xFF4A9FE8),
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
      color: const Color(0xFF4A9FE8),
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

  Future<void> _startRouteToPlace(TourPlace place) async {
    final destination = _RouteDestination.fromPlace(place);
    if (destination == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${place.title}\uC758 \uC704\uCE58 \uC815\uBCF4\uAC00 \uC544\uC9C1 \uC5C6\uC5B4\uC694.',
          ),
          backgroundColor: const Color(0xFF4A9FE8),
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

  List<TourPlace> _mergePlacesByDistance(List<TourPlace> places) {
    final seenIds = <String>{};
    final merged = <TourPlace>[];
    for (final place in places) {
      if (place.contentId.isEmpty || !seenIds.add(place.contentId)) continue;
      merged.add(place);
    }
    return _sortedByDistance(merged);
  }

  double? _distToPlace(TourPlace p) {
    final lat = p.latitude;
    final lng = p.longitude;
    if (_currentPosition == null || lat == null || lng == null) return null;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      lat,
      lng,
    );
  }

  String? _routeSummaryForPlace(TourPlace place) {
    if (_activeRoute?.destination.id != place.contentId) return null;
    return _activeRoute?.route.summaryText;
  }

  @override
  Widget build(BuildContext context) {
    final hasRecentPlace = _focusedPlace == null && _recentPlace != null;

    return Scaffold(
      body: Stack(
        children: [
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
              if (_isAreaMode) {
                await _fitPlacesToScreen(_keywordPlaces);
                unawaited(_loadInitialAreaPlaces());
              }
            },
            onMapTapped: (_, _) {
              if (_activeRoute != null) _clearRoute();
              if (_focusedPlace != null) _dismissFocus();
            },
          ),

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
                      const SizedBox(width: 8),
                      _CategoryFilterChip(
                        category: SpotCategory.all,
                        selected:
                            _selectedCategory == SpotCategory.all &&
                            !_isKeywordMode,
                        compact: true,
                        onTap: () => _onCategoryChanged(SpotCategory.all),
                      ),
                      _ThemeMoreChip(
                        active: _selectedCategory != SpotCategory.all,
                        compact: true,
                        onTap: _showCategoryPicker,
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: GestureDetector(
                          onTap: _showSearchSheet,
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
                                  Icons.search_rounded,
                                  color: Color(0xFF4A9FE8),
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _searchBarText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          _isKeywordMode ||
                                              _selectedCategory !=
                                                  SpotCategory.all
                                          ? const Color(0xFF1A1A2E)
                                          : const Color(0xFF888888),
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
                                      color: Color(0xFF4A9FE8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            right: 14,
            bottom: _focusedPlace != null ? 250 : (hasRecentPlace ? 210 : 110),
            child: _MapIconButton(
              icon: Icons.my_location_rounded,
              onTap: _goToMyLocation,
            ),
          ),

          if (_focusedPlace == null &&
              _selectedCategory == SpotCategory.all &&
              !_isKeywordMode)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _NearbyPlaceListPanel(
                title: _resultPanelTitle,
                places: _sortedByDistance(_nearbyPlaces),
                totalCount: _nearbyPlaces.length,
                currentPosition: _currentPosition,
                isLoading: _isLoadingNearbyPlaces,
                onPlaceTap: _selectNearbyPlace,
                onLocationTap: _goToMyLocation,
              ),
            ),

          if (_focusedPlace == null &&
              (_selectedCategory != SpotCategory.all || _isKeywordMode))
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _NearbyPlaceListPanel(
                title: _resultPanelTitle,
                places: _visibleKeywordPlaces,
                totalCount: _keywordPlaces.length,
                currentPosition: _currentPosition,
                isLoading: _isLoadingKeywords,
                onPlaceTap: _selectNearbyPlace,
                onLocationTap: _goToMyLocation,
              ),
            ),

          if (hasRecentPlace)
            Positioned(
              left: 16,
              right: 16,
              bottom: 126.0 + MediaQuery.of(context).padding.bottom,
              child: _RecentPlacePeek(
                place: _recentPlace!,
                onTap: () => _selectNearbyPlace(_recentPlace!),
                onClose: () {
                  setState(() => _recentPlace = null);
                  _buildMarkers();
                },
              ),
            ),

          if (_focusedPlace != null)
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

class _CategoryFilterChip extends StatelessWidget {
  final SpotCategory category;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _CategoryFilterChip({
    required this.category,
    required this.selected,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(right: compact ? 6 : 8),
        height: compact ? 36 : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: selected ? category.color : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? category.color.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: selected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[
              Text(category.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
            ],
            Text(
              category.label,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF555555),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeMoreChip extends StatelessWidget {
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  const _ThemeMoreChip({
    required this.active,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        height: compact ? 36 : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 14,
              color: active ? Colors.white : const Color(0xFF555555),
            ),
            const SizedBox(width: 4),
            Text(
              '\uD14C\uB9C8',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xFF555555),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotSearchSheet extends StatefulWidget {
  final String? initialKeyword;

  const _SpotSearchSheet({this.initialKeyword});

  @override
  State<_SpotSearchSheet> createState() => _SpotSearchSheetState();
}

class _SpotSearchSheetState extends State<_SpotSearchSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKeyword ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    Navigator.of(context).pop(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '스팟 검색',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '예: 한옥마을, 바다, 전망대',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: const Color(0xFFF7F8FB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _submit,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9FE8),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '검색',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPickerSheet extends StatelessWidget {
  final SpotCategory selectedCategory;

  const _CategoryPickerSheet({required this.selectedCategory});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad + 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            '\uC2A4\uD31F \uD14C\uB9C8',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '\uD544\uC694\uD55C \uCD2C\uC601 \uD14C\uB9C8\uB97C \uACE0\uB974\uBA74 \uC9C0\uB3C4\uC5D0 \uBC14\uB85C \uBC18\uC601\uD574\uC694.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              color: Color(0xFF777777),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SpotCategory.values.map((category) {
              final selected = selectedCategory == category;
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(category),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? category.color : const Color(0xFFF7F8FB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? category.color.withValues(alpha: 0.5)
                          : const Color(0xFFE7E9EF),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category.emoji,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        category.label,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _NearbyPlaceListPanel extends StatelessWidget {
  final String title;
  final List<TourPlace> places;
  final int totalCount;
  final Position? currentPosition;
  final bool isLoading;
  final ValueChanged<TourPlace> onPlaceTap;
  final VoidCallback onLocationTap;

  const _NearbyPlaceListPanel({
    required this.title,
    required this.places,
    required this.totalCount,
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
                  '$totalCount',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A9FE8),
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
                      color: Color(0xFF4A9FE8),
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
                      '내 주변에서 불러온 촬영 스팟이 아직 없습니다',
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
                            border: Border.all(color: const Color(0xFFF0F1F3)),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
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
                                        color: Color(0xFF4A9FE8),
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

class _RecentPlacePeek extends StatelessWidget {
  final TourPlace place;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _RecentPlacePeek({
    required this.place,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 64,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: place.photoUrl != null
                      ? Image.network(
                          place.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              _TourPlaceThumbFallback(label: place.title),
                        )
                      : _TourPlaceThumbFallback(label: place.title),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '\uBC29\uAE08 \uBCF8 \uC2A4\uD31F',
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4A9FE8),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      place.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F7FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '\uB2E4\uC2DC \uBCF4\uAE30',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A9FE8),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                iconSize: 18,
                color: const Color(0xFF999999),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
              ),
            ],
          ),
        ),
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
          const Icon(
            Icons.photo_camera_outlined,
            size: 16,
            color: Color(0xFF90CAF9),
          ),
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

  String get _typeLabel => '촬영 스팟';

  String get _introText => '지금 바로 사진 찍으러 가기 좋은 추천 장소예요.';

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 핸들 + 닫기 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
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
          ),
          // ── 풀블리드 이미지 ──
          if (place.photoUrl != null)
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    place.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _TourPlacePhotoPlaceholder(place: place),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // ── 정보 섹션 ──
          Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, bottomPad + 12),
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
                          color: Color(0xFF4A9FE8),
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
                const SizedBox(height: 8),
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
                            color: const Color(0xFF4A9FE8),
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
          const Icon(Icons.route_rounded, size: 18, color: Color(0xFF4A9FE8)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '\uD604\uC7AC \uC704\uCE58 \uAE30\uC900 \uAE38\uCC3E\uAE30',
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
