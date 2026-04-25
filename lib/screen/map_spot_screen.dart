import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';

import '../services/driving_route_service.dart';
import '../services/tour_api_service.dart';
import '../models/photo_spot.dart';
import '../models/tour_place.dart';

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

  static const _categoryListLimit = 10;
  static const _categorySearchConfigs = {
    SpotCategory.cherry: _CategorySearchConfig(
      queries: [
        '\uBC9A\uAF43',
        '\uBC9A\uAF43\uAE38',
        '\uBC9A\uAF43\uCD95\uC81C',
        '\uBC9A\uAF43\uACF5\uC6D0',
        '\uBC9A\uAF43\uBA85\uC18C',
      ],
      preferredTitleTokens: [
        '\uBC9A\uAF43',
        '\uBC9A\uB098\uBB34',
        '\uBC9A\uAF43\uAE38',
        '\uBC9A\uAF43\uCD95\uC81C',
        '\uBD04\uAF43',
      ],
    ),
    SpotCategory.autumn: _CategorySearchConfig(
      queries: [
        '\uB2E8\uD48D',
        '\uB2E8\uD48D\uAE38',
        '\uB2E8\uD48D\uBA85\uC18C',
        '\uB2E8\uD48D\uCD95\uC81C',
        '\uAC00\uC744\uBA85\uC18C',
        '\uB2E8\uD48D\uACF5\uC6D0',
        '\uB2E8\uD48D\uC0B0',
        '\uB2E8\uD48D \uC804\uB9DD\uB300',
        '\uB2E8\uD48D \uBA54\uD0C0\uC138\uCFFC\uC774\uC544',
        '\uAC00\uC744 \uD48D\uACBD',
        '\uB2E8\uD48D \uC0B0\uCC45\uB85C',
        '\uB2E8\uD48D \uD2B8\uB808\uD0B9',
        '\uB2E8\uD48D \uC218\uBAA9\uC6D0',
        '\uAC00\uC744 \uACF5\uC6D0',
        '\uAC00\uC744 \uC804\uB9DD\uB300',
      ],
      preferredTitleTokens: [
        '\uB2E8\uD48D',
        '\uB2E8\uD48D\uAE38',
        '\uB2E8\uD48D\uB098\uBB34',
        '\uB2E8\uD48D\uCD95\uC81C',
        '\uAC00\uC744',
        '\uB2E8\uD48D\uACF5\uC6D0',
        '\uBA54\uD0C0\uC138\uCFFC\uC774\uC544',
      ],
    ),
    SpotCategory.sunrise: _CategorySearchConfig(
      queries: [
        '\uC77C\uCD9C',
        '\uD574\uB3CB\uC774',
        '\uD574\uB9DE\uC774',
        '\uC77C\uCD9C\uBA85\uC18C',
      ],
      preferredTitleTokens: [
        '\uC77C\uCD9C',
        '\uD574\uB3CB\uC774',
        '\uD574\uB9DE\uC774',
        '\uC77C\uCD9C\uBA85\uC18C',
      ],
    ),
    SpotCategory.sunset: _CategorySearchConfig(
      queries: [
        '\uC77C\uBAB0',
        '\uB178\uC744',
        '\uC11D\uC591',
        '\uB099\uC870',
        '\uC77C\uBAB0\uBA85\uC18C',
        '\uB178\uC744 \uACF5\uC6D0',
        '\uB178\uC744 \uC804\uB9DD\uB300',
        '\uB099\uC870 \uC804\uB9DD\uB300',
        '\uC11D\uC591 \uBA85\uC18C',
        '\uD574\uC9C8\uB155 \uBA85\uC18C',
        '\uC77C\uBAB0 \uC804\uB9DD\uB300',
        '\uC11C\uD574 \uB179\uC870',
        '\uD574\uBCC0 \uB178\uC744',
        '\uB2E4\uB9AC \uB178\uC744',
        '\uB178\uC744 \uC0B0\uCC45\uB85C',
      ],
      preferredTitleTokens: [
        '\uC77C\uBAB0',
        '\uB178\uC744',
        '\uC11D\uC591',
        '\uB099\uC870',
        '\uC804\uB9DD\uB300',
      ],
    ),
    SpotCategory.night: _CategorySearchConfig(
      queries: [
        '\uC57C\uACBD',
        '\uC57C\uAC04\uBA85\uC18C',
        '\uBE5B\uCD95\uC81C',
        '\uC804\uB9DD\uB300',
        '\uBBF8\uB514\uC5B4\uC544\uD2B8',
      ],
      preferredTitleTokens: [
        '\uC57C\uACBD',
        '\uBE5B\uCD95\uC81C',
        '\uC57C\uAC04',
        '\uC804\uB9DD\uB300',
        '\uBBF8\uB514\uC5B4\uC544\uD2B8',
        '\uB77C\uC774\uD2B8',
      ],
    ),
    SpotCategory.snow: _CategorySearchConfig(
      queries: [
        '\uC124\uACBD',
        '\uB208\uAF43',
        '\uC124\uC0B0',
        '\uACA8\uC6B8\uBA85\uC18C',
        '\uB208\uCD95\uC81C',
        '\uC124\uC6D0',
        '\uC0C1\uACE0\uB300',
        '\uC5BC\uC74C\uCD95\uC81C',
        '\uACA8\uC6B8 \uD48D\uACBD',
        '\uB208 \uC804\uB9DD\uB300',
        '\uB208 \uC0B0',
        '\uB208\uAF43 \uBA85\uC18C',
        '\uACA8\uC6B8 \uD3EC\uD1A0\uC2A4\uD31F',
        '\uACA8\uC6B8 \uACF5\uC6D0',
        '\uC124\uACBD \uC0B0\uCC45\uB85C',
      ],
      preferredTitleTokens: [
        '\uC124\uACBD',
        '\uB208\uAF43',
        '\uC124\uC0B0',
        '\uACA8\uC6B8',
        '\uB208',
        '\uC0C1\uACE0\uB300',
        '\uC124\uC6D0',
      ],
    ),
  };
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
    '\uC2DD\uB2F9',
    '\uC74C\uC2DD\uC810',
    '\uB9DB\uC9D1',
    '\uBC31\uD654\uC810',
    '\uC1FC\uD551\uBAB0',
  ];

  late final AnimationController _cardAnimController;
  late final Animation<Offset> _cardSlide;

  static const _seoulLat = 37.5665;
  static const _seoulLng = 126.9780;
  static const _routeOverlayId = '__active_route__';

  int get _visibleSpotCount => _selectedCategory == SpotCategory.all
      ? _nearbyPlaces.length
      : _keywordPlaces.length;

  List<TourPlace> get _visibleKeywordPlaces =>
      _sortedByDistance(_keywordPlaces).take(_categoryListLimit).toList();

  String get _mapHeaderTitle => _selectedCategory == SpotCategory.all
      ? '내 주변 촬영 스팟'
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

      final shouldReload = lastPos == null ||
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
    await _clearRoute(updateState: false);

    if (!mounted) return;
    setState(() {
      _activeRoute = null;
      _focusedPlace = place;
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
    final place = _focusedPlace;
    if (_mapController == null || place == null) return;
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat == null || lng == null) return;

    final icon = await _getMarkerImage(const Color(0xFF4A9FE8));
    final marker = NMarker(id: '__tour_focus__', position: NLatLng(lat, lng));
    marker.setIcon(icon);
    marker.setOnTapListener((_) {
      _cardAnimController.forward(from: 0);
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
      _selectedCategory = category;
      _keywordPlaces = [];
    });

    if (category != SpotCategory.all) {
      await _buildMarkers();

      final config = _categorySearchConfigs[category];
      if (config != null) {
        if (mounted) setState(() => _isLoadingKeywords = true);

        final rawFuture = _tourApiService.searchByKeywords(
          config.queries,
          count: 360,
          pages: 4,
          rowsPerPage: 50,
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

        final filtered = _filterCategoryPlaces(raw, config);
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
      marker.setOnTapListener((_) {
        _selectNearbyPlace(place);
        return true;
      });
      await _mapController!.addOverlay(marker);
    }
  }

  List<TourPlace> _filterCategoryPlaces(
    List<TourPlace> places,
    _CategorySearchConfig config,
  ) {
    final seenIds = <String>{};
    final filtered = <TourPlace>[];

    for (final place in places) {
      final title = place.title.trim();
      if (place.contentId.isEmpty || !seenIds.add(place.contentId)) {
        continue;
      }
      if (title.isEmpty || place.latitude == null || place.longitude == null) {
        continue;
      }
      if (_excludedBusinessTitleTokens.any(title.contains)) {
        continue;
      }
      filtered.add(place);
    }

    filtered.sort((a, b) {
      final scoreCompare =
          _scoreCategoryPlace(b, config).compareTo(_scoreCategoryPlace(a, config));
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.title.compareTo(b.title);
    });

    return filtered;
  }

  int _scoreCategoryPlace(TourPlace place, _CategorySearchConfig config) {
    var score = 0;
    if (place.photoUrl != null) score += 4;
    if (config.preferredTitleTokens.any(place.title.contains)) score += 6;
    if (place.contentTypeId == '15') score += 2;

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
      case PlaceTag.leisure:
      case PlaceTag.festival:
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
        NCameraUpdate.scrollAndZoomTo(
          target: coords.first,
          zoom: 11.5,
        ),
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
                                color: Color(0xFF4A9FE8),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$_visibleSpotCount\uACF3',
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
                                  '$_visibleSpotCount\uACF3',
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
                    ],
                  ),
                ),

                const SizedBox(height: 10),

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

          Positioned(
            right: 14,
            bottom: _focusedPlace != null ? 250 : 110,
            child: _MapIconButton(
              icon: Icons.my_location_rounded,
              onTap: _goToMyLocation,
            ),
          ),

          if (_focusedPlace == null && _selectedCategory == SpotCategory.all)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _NearbyPlaceListPanel(
                title: '내 주변 촬영 스팟',
                places: _sortedByDistance(_nearbyPlaces),
                totalCount: _nearbyPlaces.length,
                currentPosition: _currentPosition,
                isLoading: _isLoadingNearbyPlaces,
                onPlaceTap: _selectNearbyPlace,
                onLocationTap: _goToMyLocation,
              ),
            ),

          if (_focusedPlace == null && _selectedCategory != SpotCategory.all)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _NearbyPlaceListPanel(
                title: '${_selectedCategory.emoji} ${_selectedCategory.label} 추천 스팟',
                places: _visibleKeywordPlaces,
                totalCount: _keywordPlaces.length,
                currentPosition: _currentPosition,
                isLoading: _isLoadingKeywords,
                onPlaceTap: _selectNearbyPlace,
                onLocationTap: _goToMyLocation,
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
                if (place.festivalDateRange != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 13,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        place.festivalDateRange!,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          height: 1.4,
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

class _CategorySearchConfig {
  final List<String> queries;
  final List<String> preferredTitleTokens;

  const _CategorySearchConfig({
    required this.queries,
    required this.preferredTitleTokens,
  });
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