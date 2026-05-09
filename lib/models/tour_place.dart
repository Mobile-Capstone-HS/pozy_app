enum PlaceTag { nature, history, architecture, culture, landmark }

class TourPlace {
  final String contentId;
  final String title;
  final String addr1;
  final String addr2;
  final String? firstImage;
  final String? firstImage2;
  final double? latitude;
  final double? longitude;
  final String areaCode;
  final String contentTypeId;
  final String cat1;
  final String cat2;
  final String cat3;

  const TourPlace({
    required this.contentId,
    required this.title,
    required this.addr1,
    required this.addr2,
    this.firstImage,
    this.firstImage2,
    this.latitude,
    this.longitude,
    required this.areaCode,
    required this.contentTypeId,
    this.cat1 = '',
    this.cat2 = '',
    this.cat3 = '',
  });

  factory TourPlace.fromJson(Map<String, dynamic> json) {
    final mapx = json['mapx']?.toString() ?? '';
    final mapy = json['mapy']?.toString() ?? '';
    return TourPlace(
      contentId: json['contentid']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      addr1: json['addr1']?.toString() ?? '',
      addr2: json['addr2']?.toString() ?? '',
      firstImage: _nonEmpty(json['firstimage']?.toString()),
      firstImage2: _nonEmpty(json['firstimage2']?.toString()),
      latitude: mapy.isNotEmpty ? double.tryParse(mapy) : null,
      longitude: mapx.isNotEmpty ? double.tryParse(mapx) : null,
      areaCode: json['areacode']?.toString() ?? '',
      contentTypeId: json['contenttypeid']?.toString() ?? '',
      cat1: json['cat1']?.toString() ?? '',
      cat2: json['cat2']?.toString() ?? '',
      cat3: json['cat3']?.toString() ?? '',
    );
  }

  PlaceTag get placeTag {
    if (_matchesAny(title, _kNature)) return PlaceTag.nature;
    if (_matchesAny(title, _kHistory)) return PlaceTag.history;
    if (_matchesAny(title, _kArchitecture)) return PlaceTag.architecture;
    if (_matchesAny(title, _kCulture)) return PlaceTag.culture;

    if (cat1 == 'A01') return PlaceTag.nature;
    if (cat2 == 'A0202') return PlaceTag.nature;
    if (cat2 == 'A0201') return PlaceTag.history;
    if (cat2 == 'A0205') return PlaceTag.architecture;
    if (cat1 == 'A02' || contentTypeId == '14') return PlaceTag.culture;

    return PlaceTag.landmark;
  }

  bool get isPhotoSpotCandidate {
    if (contentId.isEmpty || title.trim().isEmpty) return false;
    if (latitude == null || longitude == null) return false;
    if (contentTypeId == '15' || contentTypeId == '28' || cat1 == 'A03') {
      return false;
    }
    return photoSpotScore >= 6;
  }

  int get photoSpotScore {
    var score = 0;

    if (title.codeUnits.any((c) => c >= 0xAC00 && c <= 0xD7AF)) score += 1;
    if (photoUrl != null) score += 3;

    switch (contentTypeId) {
      case '12':
        score += 1;
        break;
      case '14':
        score += 2;
        break;
      case '15':
      case '28':
      case '32':
      case '38':
      case '39':
        score -= 6;
        break;
    }

    switch (cat1) {
      case 'A01':
        score += 4;
        break;
      case 'A02':
        score += 2;
        break;
      case 'A03':
      case 'A04':
      case 'A05':
      case 'B02':
      case 'C01':
        score -= 6;
        break;
    }

    switch (cat2) {
      case 'A0201':
      case 'A0202':
      case 'A0205':
        score += 3;
        break;
      case 'A0203':
      case 'A0206':
      case 'A0207':
        score += 1;
        break;
      case 'A0401':
      case 'A0402':
      case 'A0502':
        score -= 6;
        break;
    }

    switch (placeTag) {
      case PlaceTag.nature:
      case PlaceTag.history:
      case PlaceTag.architecture:
      case PlaceTag.landmark:
        score += 3;
        break;
      case PlaceTag.culture:
        score += 2;
        break;
    }

    if (_matchesAny(title, _kPhotoPositiveTitleTokens)) score += 4;
    if (_matchesAny(title, _kPhotoNegativeTitleTokens)) score -= 8;
    if (_looksLikeLocalBusiness(title)) score -= 4;

    return score;
  }

  static bool _matchesAny(String title, List<String> kw) =>
      kw.any(title.contains);

  static bool _looksLikeLocalBusiness(String title) {
    if (_matchesAny(title, _kPhotoPositiveTitleTokens)) return false;
    return title.endsWith('점') ||
        title.endsWith('본점') ||
        title.endsWith('지점') ||
        title.contains('식당') ||
        title.contains('강남점') ||
        title.contains('역점');
  }

  static const _kNature = [
    '숲',
    '수목원',
    '자연휴양림',
    '국립공원',
    '도립공원',
    '군립공원',
    '생태공원',
    '계곡',
    '폭포',
    '호수',
    '저수지',
    '오름',
    '둘레길',
    '해변',
    '해수욕장',
    '갯벌',
    '해안산책',
    '생태',
  ];

  static const _kHistory = [
    '유적',
    '사적',
    '고궁',
    '궁궐',
    '정릉',
    '성곽',
    '성경',
    '산성',
    '서원',
    '향교',
    '사찰',
    '암자',
    '대웅전',
    '문화재',
    '고택',
    '고분',
  ];

  static const _kArchitecture = ['전망대', '타워', '스카이워크', '조형물', '케이블카', '등대'];

  static const _kCulture = [
    '박물관',
    '미술관',
    '갤러리',
    '공연장',
    '전시관',
    '예술마을',
    '전통시장',
    '문화관',
  ];

  static const _kPhotoPositiveTitleTokens = [
    '공원',
    '생태',
    '수목원',
    '정원',
    '숲',
    '휴양림',
    '해변',
    '해수욕장',
    '바다',
    '섬',
    '항',
    '오름',
    '산',
    '계곡',
    '폭포',
    '호수',
    '강',
    '둘레길',
    '전망',
    '전망대',
    '스카이',
    '타워',
    '대교',
    '교량',
    '다리',
    '궁',
    '문',
    '사찰',
    '절',
    '향교',
    '서원',
    '고택',
    '예술',
    '마을',
    '벽화',
    '거리',
    '광장',
    '동상',
    '조형물',
    '기념관',
    '유적',
    '사적',
    '박물관',
    '미술관',
    '갤러리',
  ];

  static const _kPhotoNegativeTitleTokens = [
    '맛집',
    '음식',
    '식당',
    '먹거리',
    '카페',
    '주점',
    '주차',
    '국밥',
    '탕',
    '감자국',
    '해장국',
    '곱창',
    '조개',
    '치킨',
    '일자',
    '마트',
    '슈퍼',
    '편의점',
    '약국',
    '병원',
    '의원',
    '치과',
    '은행',
    '주유소',
    '충전소',
    '부동산',
    '호텔',
    '모텔',
    '리조트',
  ];

  static String? _nonEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  String get address {
    final parts = [addr1, addr2].where((s) => s.isNotEmpty).toList();
    return parts.join(' ');
  }

  String get areaName => _areaNames[areaCode] ?? '';

  String? get photoUrl => firstImage ?? firstImage2;

  static const _areaNames = {
    '1': '서울',
    '2': '인천',
    '3': '대전',
    '4': '대구',
    '5': '광주',
    '6': '부산',
    '7': '울산',
    '8': '세종',
    '31': '경기',
    '32': '강원',
    '33': '충북',
    '34': '충남',
    '35': '전북',
    '36': '전남',
    '37': '경북',
    '38': '경남',
    '39': '제주',
  };
}
