import 'package:cloud_functions/cloud_functions.dart';

class DrivingRouteService {
  DrivingRouteService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _functions;

  Future<DrivingRoute> fetchDrivingRoute({
    required double startLat,
    required double startLng,
    required double goalLat,
    required double goalLng,
    String option = 'traoptimal',
  }) async {
    try {
      final callable = _functions.httpsCallable('getDrivingRoute');
      final result = await callable.call({
        'startLat': startLat,
        'startLng': startLng,
        'goalLat': goalLat,
        'goalLng': goalLng,
        'option': option,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      return DrivingRoute.fromMap(data);
    } on FirebaseFunctionsException catch (error) {
      throw DrivingRouteException(_mapFunctionsError(error));
    } catch (_) {
      throw const DrivingRouteException('길찾기 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  String _mapFunctionsError(FirebaseFunctionsException error) {
    final message = error.message?.trim();

    if (error.code == 'not-found') {
      if (message == null || message.isEmpty || message.toUpperCase() == 'NOT FOUND') {
        return '길찾기 서버 함수가 아직 배포되지 않았어요. Firebase Functions 배포 상태를 확인해 주세요.';
      }
      return message;
    }

    if (error.code == 'unauthenticated') {
      return '사용자 인증이 아직 준비되지 않았어요. 앱을 다시 열고 잠시 후 시도해 주세요.';
    }

    if (error.code == 'failed-precondition') {
      return message ?? '네이버 길찾기 응답을 처리하지 못했어요.';
    }

    if (error.code == 'unavailable') {
      return '길찾기 서버에 연결할 수 없어요. 네트워크 상태나 Functions 배포를 확인해 주세요.';
    }

    return message ?? '길찾기 요청 중 오류가 발생했어요.';
  }
}

class DrivingRoute {
  final String option;
  final int distanceMeters;
  final int durationMs;
  final int tollFare;
  final int taxiFare;
  final int fuelPrice;
  final String? departureTime;
  final RouteBounds? bounds;
  final List<RoutePoint> path;
  final List<RouteGuide> guide;

  const DrivingRoute({
    required this.option,
    required this.distanceMeters,
    required this.durationMs,
    required this.tollFare,
    required this.taxiFare,
    required this.fuelPrice,
    required this.departureTime,
    required this.bounds,
    required this.path,
    required this.guide,
  });

  factory DrivingRoute.fromMap(Map<String, dynamic> map) {
    final rawPath = (map['path'] as List? ?? const [])
        .whereType<Map>()
        .map((point) => RoutePoint.fromMap(Map<String, dynamic>.from(point)))
        .toList();

    final rawGuide = (map['guide'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => RouteGuide.fromMap(Map<String, dynamic>.from(item)))
        .toList();

    final boundsMap = map['bounds'];

    return DrivingRoute(
      option: map['option'] as String? ?? 'traoptimal',
      distanceMeters: (map['distanceMeters'] as num?)?.round() ?? 0,
      durationMs: (map['durationMs'] as num?)?.round() ?? 0,
      tollFare: (map['tollFare'] as num?)?.round() ?? 0,
      taxiFare: (map['taxiFare'] as num?)?.round() ?? 0,
      fuelPrice: (map['fuelPrice'] as num?)?.round() ?? 0,
      departureTime: map['departureTime'] as String?,
      bounds: boundsMap is Map
          ? RouteBounds.fromMap(Map<String, dynamic>.from(boundsMap))
          : null,
      path: rawPath,
      guide: rawGuide,
    );
  }

  String get formattedDistance {
    if (distanceMeters < 1000) return '${distanceMeters}m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }

  String get formattedDuration {
    final totalMinutes = (durationMs / 60000).round();
    if (totalMinutes < 60) return '$totalMinutes분';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) return '$hours시간';
    return '$hours시간 $minutes분';
  }

  String get summaryText {
    final fareText = tollFare > 0 ? ' · 통행료 ${_formatWon(tollFare)}' : '';
    return '실제 도로 기준 $formattedDistance · 약 $formattedDuration$fareText';
  }

  String? get primaryGuideText {
    for (final item in guide) {
      if (item.instructions.isNotEmpty) return item.instructions;
    }
    return null;
  }

  static String _formatWon(int amount) {
    final chars = amount.toString().split('').reversed.toList();
    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(',');
      buffer.write(chars[i]);
    }
    return '${buffer.toString().split('').reversed.join()}원';
  }
}

class RoutePoint {
  final double lat;
  final double lng;

  const RoutePoint({required this.lat, required this.lng});

  factory RoutePoint.fromMap(Map<String, dynamic> map) {
    return RoutePoint(
      lat: (map['lat'] as num?)?.toDouble() ?? 0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RouteBounds {
  final RoutePoint southWest;
  final RoutePoint northEast;

  const RouteBounds({required this.southWest, required this.northEast});

  factory RouteBounds.fromMap(Map<String, dynamic> map) {
    return RouteBounds(
      southWest: RoutePoint.fromMap(
        Map<String, dynamic>.from(map['southWest'] as Map),
      ),
      northEast: RoutePoint.fromMap(
        Map<String, dynamic>.from(map['northEast'] as Map),
      ),
    );
  }
}

class RouteGuide {
  final int? pointIndex;
  final int? type;
  final String instructions;
  final int distance;
  final int duration;

  const RouteGuide({
    required this.pointIndex,
    required this.type,
    required this.instructions,
    required this.distance,
    required this.duration,
  });

  factory RouteGuide.fromMap(Map<String, dynamic> map) {
    return RouteGuide(
      pointIndex: (map['pointIndex'] as num?)?.round(),
      type: (map['type'] as num?)?.round(),
      instructions: map['instructions'] as String? ?? '',
      distance: (map['distance'] as num?)?.round() ?? 0,
      duration: (map['duration'] as num?)?.round() ?? 0,
    );
  }
}

class DrivingRouteException implements Exception {
  final String message;

  const DrivingRouteException(this.message);

  @override
  String toString() => message;
}
