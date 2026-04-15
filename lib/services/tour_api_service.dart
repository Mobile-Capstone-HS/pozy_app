import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/tour_place.dart';

/// Korea Tourism API service.
class TourApiService {
  static const _baseUrl = 'https://apis.data.go.kr/B551011/KorService2';
  static const _weeklyCandidatePages = 3;
  static const _weeklyRowsPerPage = 20;

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

  static int get _weekOfYear {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(startOfYear).inDays;
    return (dayOfYear / 7).floor() + 1;
  }

  static String get weeklyAreaCode =>
      _areaCodes[_weekOfYear % _areaCodes.length];

  static String get weeklyAreaName {
    const names = {
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
    };
    return names[weeklyAreaCode] ?? '';
  }

  static String get weekLabel {
    final now = DateTime.now();
    final weekInMonth = ((now.day - 1) / 7).floor() + 1;
    return '${now.month}월 ${weekInMonth}주차';
  }

  String? get _serviceKey => dotenv.env['TOUR_API_KEY'];

  bool get hasApiKey => (_serviceKey ?? '').isNotEmpty;

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

  /// 키워드로 전국 관광지 검색 (벚꽃, 단풍, 일출, 일몰 등)
  Future<List<TourPlace>> searchByKeyword(
    String keyword, {
    int count = 30,
    String contentTypeId = '12',
  }) async {
    final key = _serviceKey;
    if (key == null || key.isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/searchKeyword2').replace(
      queryParameters: {
        'serviceKey': key,
        'numOfRows': '$count',
        'pageNo': '1',
        'MobileOS': 'ETC',
        'MobileApp': 'Pozy',
        '_type': 'json',
        'arrange': 'P',
        'keyword': keyword,
        'contentTypeId': contentTypeId,
      },
    );

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final places = _parseItems(resp.body);
      final withPhoto = places.where((p) => p.photoUrl != null).toList();
      final withoutPhoto = places.where((p) => p.photoUrl == null).toList();
      return [...withPhoto, ...withoutPhoto].take(count).toList();
    } catch (e) {
      debugPrint('TourApiService.searchByKeyword error: $e');
      return [];
    }
  }

  Future<List<TourPlace>> fetchCurrentEvents({int count = 8}) async {
    final key = _serviceKey;
    if (key == null || key.isEmpty) return [];

    final now = DateTime.now();
    final eventStart = '${now.year}${now.month.toString().padLeft(2, '0')}01';

    final uri = Uri.parse('$_baseUrl/searchFestival2').replace(
      queryParameters: {
        'serviceKey': key,
        'numOfRows': '30',
        'pageNo': '1',
        'MobileOS': 'ETC',
        'MobileApp': 'Pozy',
        '_type': 'json',
        'eventStartDate': eventStart,
        'arrange': 'A',
      },
    );

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final places = _parseItems(resp.body);
      return places.where((place) => place.photoUrl != null).take(count).toList();
    } catch (error) {
      debugPrint('TourApiService.fetchCurrentEvents error: $error');
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
        'numOfRows': '$count',
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
        debugPrint('TourApiService.fetchNearbySpots status: ${resp.statusCode}');
        debugPrint('TourApiService.fetchNearbySpots body: ${resp.body}');
        return [];
      }

      final places = _parseItems(resp.body);
      final seenIds = <String>{};
      final withPhoto = <TourPlace>[];
      final withoutPhoto = <TourPlace>[];

      for (final place in places) {
        if (place.contentId.isEmpty || seenIds.contains(place.contentId)) {
          continue;
        }
        seenIds.add(place.contentId);
        if (place.photoUrl != null) {
          withPhoto.add(place);
        } else {
          withoutPhoto.add(place);
        }
      }

      return [...withPhoto, ...withoutPhoto].take(count).toList();
    } catch (error) {
      debugPrint('TourApiService.fetchNearbySpots error: $error');
      return [];
    }
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

    final merged = <TourPlace>[];
    final seenIds = <String>{};

    try {
      for (var pageNo = 1; pageNo <= pages; pageNo++) {
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

        final uri = Uri.parse('$_baseUrl/areaBasedList2').replace(
          queryParameters: params,
        );

        final resp = await http.get(uri).timeout(const Duration(seconds: 10));
        debugPrint('TourAPI status(page $pageNo): ${resp.statusCode}');
        if (resp.statusCode != 200) {
          debugPrint('TourAPI error body: ${resp.body}');
          continue;
        }

        final places = _parseItems(resp.body);
        debugPrint('TourAPI parsed ${places.length} places on page $pageNo');
        if (places.isEmpty) {
          debugPrint(
            'TourAPI raw: ${resp.body.substring(0, resp.body.length.clamp(0, 500))}',
          );
          continue;
        }

        for (final place in places) {
          if (place.contentId.isEmpty || seenIds.contains(place.contentId)) {
            continue;
          }
          seenIds.add(place.contentId);
          merged.add(place);
        }

        if (merged.length >= count) {
          break;
        }
      }

      final withPhoto = merged.where((place) => place.photoUrl != null).toList();
      final withoutPhoto =
          merged.where((place) => place.photoUrl == null).toList();
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
    // 한글이 포함된 유효한 이름의 스팟만 선택 (코드성 값 "Fe01" 등 제거)
    final valid = places
        .where((p) => p.title.codeUnits.any((c) => c >= 0xAC00 && c <= 0xD7AF))
        .toList();
    final pool = valid.isNotEmpty ? valid : places;
    return (List<TourPlace>.from(pool)..shuffle(Random())).take(count).toList();
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
}
