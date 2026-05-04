/// 스팟 테마 태그
enum PlaceTag {
  nature,
  history,
  architecture,
  culture,
  leisure,
  festival,
  landmark,
}

/// 한국관광공사 Tour API 응답 모델
class TourPlace {
  final String contentId;
  final String title;
  final String addr1;
  final String addr2;
  final String? firstImage; // 실제 관광지 사진 URL
  final String? firstImage2; // 썸네일 URL
  final double? latitude; // mapy
  final double? longitude; // mapx
  final String areaCode;
  final String contentTypeId;
  final String cat1; // 대분류: A01=자연, A02=인문, A03=레포츠, A05=음식, B02=숙박
  final String cat2; // 중분류: A0201=역사, A0205=건축/조형물 등
  final String cat3;
  final String? eventStartDate; // 축제 시작일 (YYYYMMDD), contentTypeId==15일 때만
  final String? eventEndDate; // 축제 종료일 (YYYYMMDD)

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
    this.eventStartDate,
    this.eventEndDate,
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
      eventStartDate: _nonEmpty(json['eventstartdate']?.toString()),
      eventEndDate: _nonEmpty(json['eventenddate']?.toString()),
    );
  }

  /// 축제 기간 표시용 문자열 (예: "2026.04.15 ~ 2026.04.30")
  String? get festivalDateRange {
    final s = _formatDate(eventStartDate);
    final e = _formatDate(eventEndDate);
    if (s == null && e == null) return null;
    if (s == null) return e;
    if (e == null) return s;
    return '$s ~ $e';
  }

  static String? _formatDate(String? raw) {
    if (raw == null || raw.length != 8) return null;
    return '${raw.substring(0, 4)}.${raw.substring(4, 6)}.${raw.substring(6, 8)}';
  }

  /// 스팟 테마 태그
  /// 우선순위:
  ///   1. contentTypeId
  ///   2. 제목 키워드 (API cat 분류가 실제 성격과 다를 때 보정)
  ///   3. cat1 / cat2 (관광공사 대·중분류)
  ///   4. 기본값 landmark
  PlaceTag get placeTag {
    // ── 1. contentTypeId 명확 분류 ────────────────────────
    if (contentTypeId == '15') return PlaceTag.festival;
    if (contentTypeId == '28' || cat1 == 'A03') return PlaceTag.leisure;

    // 2. 제목 키워드 우선 보정
    // API가 A02(인문)으로 분류해도 실제 자연 스팟인 경우 다수 존재
    if (_matchesAny(title, _kNature)) return PlaceTag.nature;
    if (_matchesAny(title, _kHistory)) return PlaceTag.history;
    if (_matchesAny(title, _kArchitecture)) return PlaceTag.architecture;
    if (_matchesAny(title, _kCulture)) return PlaceTag.culture;

    // 3. cat1 / cat2 분류
    if (cat1 == 'A01') return PlaceTag.nature;
    // A0202 = 휴양관광지: 수목원·자연휴양림·치유의숲 포함
    if (cat2 == 'A0202') return PlaceTag.nature;
    if (cat2 == 'A0201') return PlaceTag.history;
    if (cat2 == 'A0205') return PlaceTag.architecture;
    if (cat1 == 'A02' || contentTypeId == '14') return PlaceTag.culture;

    return PlaceTag.landmark;
  }

  bool get isPhotoSpotCandidate {
    if (contentId.isEmpty || title.trim().isEmpty) return false;
    if (latitude == null || longitude == null) return false;
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
      case '15':
        score += 2;
        break;
      case '28':
        score -= 1;
        break;
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
        score -= 1;
        break;
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
      case PlaceTag.festival:
      case PlaceTag.landmark:
        score += 3;
        break;
      case PlaceTag.culture:
        score += 2;
        break;
      case PlaceTag.leisure:
        score += 1;
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
        title.contains('홍대점') ||
        title.contains('강남점') ||
        title.contains('역점');
  }

  // 자연: 숲/수목/공원/계곡/바다 계열
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
    '해안절경',
    '생태',
  ];

  // 역사: 유적·사적·사찰·궁 계열
  static const _kHistory = [
    '유적',
    '사적',
    '고궁',
    '궁궐',
    '왕릉',
    '성곽',
    '성벽',
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

  // 건축: 전망대·교량·조형물 계열
  static const _kArchitecture = ['전망대', '타워', '스카이워크', '조형물', '케이블카', '등대'];

  // 문화: 전시·공연·체험 계열
  static const _kCulture = [
    '박물관',
    '미술관',
    '갤러리',
    '공연장',
    '전시관',
    '한옥마을',
    '전통시장',
    '문화원',
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
    '항',
    '섬',
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
    '성',
    '문',
    '사찰',
    '절',
    '향교',
    '서원',
    '고택',
    '한옥',
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
    '축제',
  ];

  static const _kPhotoNegativeTitleTokens = [
    '맛집',
    '음식',
    '식당',
    '먹거리',
    '카페',
    '주점',
    '포차',
    '국밥',
    '탕',
    '감자국',
    '해장국',
    '곱창',
    '족발',
    '치킨',
    '피자',
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
    '휴대폰',
    '핸드폰',
    '폰케이스',
    '케이스',
    '프린팅',
    '네일',
    '미용실',
    '학원',
    '모텔',
    '호텔',
    '펜션',
    '리조트',
  ];

  static String? _nonEmpty(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  /// 노출용 주소 (addr1 + addr2 조합)
  String get address {
    final parts = [addr1, addr2].where((s) => s.isNotEmpty).toList();
    return parts.join(' ');
  }

  /// 지역 한글 이름
  String get areaName => _areaNames[areaCode] ?? '';

  /// 사진 우선순위: firstImage → firstImage2
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
