import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/tour_place.dart';

class TourApiService {
  static const _baseUrl = 'https://apis.data.go.kr/B551011/KorService2';
  static const _weeklyCandidatePages = 5;
  static const _weeklyRowsPerPage = 20;
  static const _allowedContentTypes = {'12', '14'};

  static const _areaCodes = [
    '1',
    '39',
    '32',
    '6',
    '38',
    '31',
    '35',
    '36',
    '37',
    '34',
    '33',
    '4',
    '5',
    '2',
    '3',
    '7',
    '8',
  ];

  String? get _serviceKey => dotenv.env['TOUR_API_KEY'];
  final Map<String, Future<String?>> _overviewCache = {};

  bool get hasApiKey => (_serviceKey ?? '').isNotEmpty;

  static int get _weekOfYear {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(startOfYear).inDays;
    return (dayOfYear / 7).floor() + 1;
  }

  static String get weeklyAreaCode =>
      _areaCodes[_weekOfYear % _areaCodes.length];

  static String get weeklyAreaName {
    /* const names = {
      '1': '서울',
      '39': '제주',
      '32': '강원',
      '6': '부산',
      '38': '경남',
      '31': '경기',
      '35': '전북',
      '36': '전남',
      '37': '경북',
      '34': '충남',
      '33': '충북',
      '4': '대구',
      '5': '광주',
      '2': '인천',
      '3': '대전',
      '7': '울산',
      '8': '세종',
    }; */
    const names = {
      '1': '\uC11C\uC6B8',
      '39': '\uC81C\uC8FC',
      '32': '\uAC15\uC6D0',
      '6': '\uBD80\uC0B0',
      '38': '\uACBD\uB0A8',
      '31': '\uACBD\uAE30',
      '35': '\uC804\uBD81',
      '36': '\uC804\uB0A8',
      '37': '\uACBD\uBD81',
      '34': '\uCDA9\uB0A8',
      '33': '\uCDA9\uBD81',
      '4': '\uB300\uAD6C',
      '5': '\uAD11\uC8FC',
      '2': '\uC778\uCC9C',
      '3': '\uB300\uC804',
      '7': '\uC6B8\uC0B0',
      '8': '\uC138\uC885',
    };
    return names[weeklyAreaCode] ?? '';
  }

  static String get weekLabel {
    final now = DateTime.now();
    final weekInMonth = ((now.day - 1) / 7).floor() + 1;
    return '${now.month}월 $weekInMonth주차';
  }

  Future<List<TourPlace>> fetchWeeklySpots({int count = 10}) async {
    final candidates = await _fetchAreaSpots(
      areaCode: weeklyAreaCode,
      contentTypeId: '12',
      numOfRows: _weeklyRowsPerPage,
      count: _weeklyRowsPerPage * _weeklyCandidatePages,
      pages: _weeklyCandidatePages,
    );

    return _pickWeeklySlice(
      places: candidates,
      count: count,
      areaCode: weeklyAreaCode,
    );
  }

  Future<List<TourPlace>> fetchPopularSpots({int count = 10}) async {
    return _fetchAreaSpots(
      areaCode: '',
      contentTypeId: '12',
      numOfRows: 40,
      count: count,
      arrange: 'P',
    );
  }

  Future<List<TourPlace>> searchByKeyword(
    String keyword, {
    int count = 30,
    String contentTypeId = '',
  }) async {
    return searchByKeywords(
      [keyword],
      count: count,
      pages: 1,
      rowsPerPage: count * 2,
      contentTypeId: contentTypeId,
    );
  }

  Future<List<TourPlace>> searchByKeywords(
    List<String> keywords, {
    int count = 120,
    int pages = 2,
    int rowsPerPage = 40,
    String contentTypeId = '',
    bool prioritizePhotoSpots = true,
  }) async {
    final normalizedKeywords = <String>{};
    for (final keyword in keywords) {
      final trimmed = keyword.trim();
      if (trimmed.isNotEmpty) {
        normalizedKeywords.add(trimmed);
      }
    }
    if (normalizedKeywords.isEmpty) return [];

    try {
      final requests = <Future<List<TourPlace>>>[];
      for (final keyword in normalizedKeywords) {
        for (var pageNo = 1; pageNo <= pages; pageNo++) {
          requests.add(
            _searchKeywordPage(
              keyword: keyword,
              pageNo: pageNo,
              rowsPerPage: rowsPerPage,
              contentTypeId: contentTypeId,
            ),
          );
        }
      }

      final pageResults = await Future.wait(requests);
      final seenIds = <String>{};
      final merged = <TourPlace>[];

      for (final pageItems in pageResults) {
        for (final place in pageItems) {
          if (place.contentId.isEmpty || !seenIds.add(place.contentId)) {
            continue;
          }
          merged.add(place);
        }
      }

      final prioritized = prioritizePhotoSpots
          ? _prioritizePhotoSpots(merged)
          : _sortPhotoSpots(merged);
      final withPhoto = prioritized
          .where((place) => place.photoUrl != null)
          .toList();
      final withoutPhoto = prioritized
          .where((place) => place.photoUrl == null)
          .toList();
      return [...withPhoto, ...withoutPhoto].take(count).toList();
    } catch (error) {
      debugPrint('TourApiService.searchByKeywords error: $error');
      return [];
    }
  }

  Future<List<TourPlace>> fetchNearbySpots({
    required double latitude,
    required double longitude,
    int radius = 12000,
    int count = 12,
    String contentTypeId = '12',
  }) async {
    final key = _serviceKey;
    if (key == null || key.isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/locationBasedList2').replace(
      queryParameters: {
        'serviceKey': key,
        'numOfRows': '${max(count * 5, 30)}',
        'pageNo': '1',
        'MobileOS': 'ETC',
        'MobileApp': 'Pozy',
        '_type': 'json',
        'arrange': 'S',
        'mapX': longitude.toString(),
        'mapY': latitude.toString(),
        'radius': '$radius',
        'contentTypeId': contentTypeId,
      },
    );

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        debugPrint(
          'TourApiService.fetchNearbySpots status: ${resp.statusCode}',
        );
        debugPrint('TourApiService.fetchNearbySpots body: ${resp.body}');
        return [];
      }

      final places = _prioritizePhotoSpots(_parseItems(resp.body));
      final seenIds = <String>{};
      final candidates = <TourPlace>[];

      for (final place in places) {
        if (place.contentId.isEmpty ||
            seenIds.contains(place.contentId) ||
            !place.isPhotoSpotCandidate) {
          continue;
        }
        seenIds.add(place.contentId);
        candidates.add(place);
      }

      candidates.sort((a, b) {
        final da = _distanceFrom(latitude, longitude, a);
        final db = _distanceFrom(latitude, longitude, b);
        final distanceCompare = da.compareTo(db);
        if (distanceCompare != 0) return distanceCompare;
        final scoreCompare = b.photoSpotScore.compareTo(a.photoSpotScore);
        if (scoreCompare != 0) return scoreCompare;
        if (a.photoUrl != null && b.photoUrl == null) return -1;
        if (a.photoUrl == null && b.photoUrl != null) return 1;
        return a.title.compareTo(b.title);
      });

      return candidates.take(count).toList();
    } catch (error) {
      debugPrint('TourApiService.fetchNearbySpots error: $error');
      return [];
    }
  }

  Future<String?> fetchOverview(TourPlace place) {
    if (place.contentId.isEmpty) return Future.value(null);
    return _overviewCache[place.contentId] ??= _fetchOverview(place);
  }

  Future<List<TourPlace>> _fetchAreaSpots({
    required String areaCode,
    required String contentTypeId,
    required int numOfRows,
    required int count,
    int pages = 1,
    String arrange = 'C',
  }) async {
    final key = _serviceKey;
    if (key == null || key.isEmpty) return [];

    try {
      final pageFutures = List.generate(pages, (i) async {
        final pageNo = i + 1;
        final params = <String, String>{
          'serviceKey': key,
          'numOfRows': '$numOfRows',
          'pageNo': '$pageNo',
          'MobileOS': 'ETC',
          'MobileApp': 'Pozy',
          '_type': 'json',
          'arrange': arrange,
          'contentTypeId': contentTypeId,
        };
        if (areaCode.isNotEmpty) {
          params['areaCode'] = areaCode;
        }

        final uri = Uri.parse(
          '$_baseUrl/areaBasedList2',
        ).replace(queryParameters: params);
        try {
          final resp = await http.get(uri).timeout(const Duration(seconds: 10));
          if (resp.statusCode != 200) return <TourPlace>[];
          return _parseItems(resp.body);
        } catch (_) {
          return <TourPlace>[];
        }
      });

      final pageResults = await Future.wait(pageFutures);
      final seenIds = <String>{};
      final merged = <TourPlace>[];

      for (final pageItems in pageResults) {
        for (final place in pageItems) {
          if (place.contentId.isEmpty || seenIds.contains(place.contentId)) {
            continue;
          }
          seenIds.add(place.contentId);
          merged.add(place);
        }
      }

      final prioritized = _prioritizePhotoSpots(merged);
      final withPhoto = prioritized
          .where((place) => place.photoUrl != null)
          .toList();
      final withoutPhoto = prioritized
          .where((place) => place.photoUrl == null)
          .toList();
      return [...withPhoto, ...withoutPhoto].take(count).toList();
    } catch (error) {
      debugPrint('TourApiService._fetchAreaSpots error: $error');
      return [];
    }
  }

  List<TourPlace> _pickWeeklySlice({
    required List<TourPlace> places,
    required int count,
    required String areaCode,
  }) {
    if (places.length <= count) return places;

    final pool = (_prioritizePhotoSpots(places).where((p) {
      return p.photoUrl != null && p.isPhotoSpotCandidate;
    }).toList()..shuffle(Random()));

    const maxPerTag = 2;
    final tagCount = <PlaceTag, int>{};
    final result = <TourPlace>[];

    for (final place in pool) {
      if (result.length >= count) break;
      final tag = place.placeTag;
      if ((tagCount[tag] ?? 0) < maxPerTag) {
        result.add(place);
        tagCount[tag] = (tagCount[tag] ?? 0) + 1;
      }
    }

    if (result.length < count) {
      for (final place in pool) {
        if (result.length >= count) break;
        if (!result.contains(place)) {
          result.add(place);
        }
      }
    }
    return result;
  }

  List<TourPlace> _parseItems(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final items = json['response']?['body']?['items']?['item'];
      if (items == null) return [];
      if (items is List) {
        return items
            .map((item) => TourPlace.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      if (items is Map) {
        return [TourPlace.fromJson(items as Map<String, dynamic>)];
      }
      return [];
    } catch (error) {
      debugPrint('TourApiService._parseItems error: $error');
      return [];
    }
  }

  Future<String?> _fetchOverview(TourPlace place) async {
    final key = _serviceKey;
    if (key == null || key.isEmpty) return null;

    final params = <String, String>{
      'serviceKey': key,
      'MobileOS': 'ETC',
      'MobileApp': 'Pozy',
      '_type': 'json',
      'contentId': place.contentId,
      'defaultYN': 'Y',
      'firstImageYN': 'N',
      'areacodeYN': 'N',
      'catcodeYN': 'N',
      'addrinfoYN': 'N',
      'mapinfoYN': 'N',
      'overviewYN': 'Y',
    };
    if (place.contentTypeId.isNotEmpty) {
      params['contentTypeId'] = place.contentTypeId;
    }

    final uri = Uri.parse(
      '$_baseUrl/detailCommon2',
    ).replace(queryParameters: params);

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = json['response']?['body']?['items']?['item'];
      final item = items is List && items.isNotEmpty
          ? items.first
          : items is Map
          ? items
          : null;
      if (item is! Map) return null;
      return _cleanText(item['overview']?.toString());
    } catch (error) {
      debugPrint('TourApiService._fetchOverview error: $error');
      return null;
    }
  }

  String? _cleanText(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<TourPlace> _prioritizePhotoSpots(List<TourPlace> places) {
    return _sortPhotoSpots(
      places.where((place) => place.isPhotoSpotCandidate).toList(),
    );
  }

  double _distanceFrom(double latitude, double longitude, TourPlace place) {
    final lat = place.latitude;
    final lng = place.longitude;
    if (lat == null || lng == null) return double.infinity;

    const earthRadiusMeters = 6371000.0;
    final dLat = _degreesToRadians(lat - latitude);
    final dLng = _degreesToRadians(lng - longitude);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(latitude)) *
            cos(_degreesToRadians(lat)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _degreesToRadians(double degrees) => degrees * pi / 180;

  List<TourPlace> _sortPhotoSpots(List<TourPlace> places) {
    return places.toList()..sort((a, b) {
      final scoreCompare = b.photoSpotScore.compareTo(a.photoSpotScore);
      if (scoreCompare != 0) return scoreCompare;
      if (a.photoUrl != null && b.photoUrl == null) return -1;
      if (a.photoUrl == null && b.photoUrl != null) return 1;
      return a.title.compareTo(b.title);
    });
  }

  Future<List<TourPlace>> _searchKeywordPage({
    required String keyword,
    required int pageNo,
    required int rowsPerPage,
    required String contentTypeId,
  }) async {
    final key = _serviceKey;
    if (key == null || key.isEmpty) return [];

    final params = <String, String>{
      'serviceKey': key,
      'numOfRows': '$rowsPerPage',
      'pageNo': '$pageNo',
      'MobileOS': 'ETC',
      'MobileApp': 'Pozy',
      '_type': 'json',
      'arrange': 'P',
      'keyword': keyword,
    };
    if (contentTypeId.isNotEmpty) {
      params['contentTypeId'] = contentTypeId;
    }

    final uri = Uri.parse(
      '$_baseUrl/searchKeyword2',
    ).replace(queryParameters: params);

    final resp = await http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return [];

    return _parseItems(resp.body).where((place) {
      if (contentTypeId.isNotEmpty) {
        return place.contentTypeId == contentTypeId;
      }
      return _allowedContentTypes.contains(place.contentTypeId);
    }).toList();
  }
}
