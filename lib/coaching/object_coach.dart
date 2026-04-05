import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';

import 'coaching_result.dart';
import 'object_image_analyzer.dart';

class ObjectFeatures {
  final double numObjects;
  final double areaRatio;
  final double sceneCenterX;
  final double sceneCenterY;

  /// union ROI와 프레임 가장자리 사이 최소 여백 [0, 0.5]
  final double unionMarginMin;

  final double brightness;
  final double subjectBrightness;
  final double backgroundBrightness;
  final double globalBlurScore;
  final double subjectBlurScore;
  final double highlightRatio;
  final double shadowRatio;
  final double subjectHighlightRatio;
  final double subjectShadowRatio;
  const ObjectFeatures({
    this.numObjects = 0,
    this.areaRatio = 0,
    this.sceneCenterX = 0.5,
    this.sceneCenterY = 0.5,
    this.unionMarginMin = 0.5,
    this.brightness = 0.5,
    this.subjectBrightness = 0.5,
    this.backgroundBrightness = 0.5,
    this.globalBlurScore = 999,
    this.subjectBlurScore = 999,
    this.highlightRatio = 0,
    this.shadowRatio = 0,
    this.subjectHighlightRatio = 0,
    this.subjectShadowRatio = 0,
  });
}

class SceneGeometry {
  final double numObjects;
  final double areaRatio;
  final double sceneCenterX;
  final double sceneCenterY;
  final double unionMarginMin;
  final Rect? unionRoi;

  const SceneGeometry({
    required this.numObjects,
    required this.areaRatio,
    required this.sceneCenterX,
    required this.sceneCenterY,
    required this.unionMarginMin,
    required this.unionRoi,
  });
}

class _FeatureExtractor {
  static const double _minArea = 0.002;

  SceneGeometry extract(List<YOLOResult> results) {
    final valid = <Rect>[];

    for (final r in results) {
      final b = r.normalizedBox;
      final rect = Rect.fromLTWH(
        b.left.clamp(0.0, 1.0),
        b.top.clamp(0.0, 1.0),
        b.width.clamp(0.0, 1.0),
        b.height.clamp(0.0, 1.0),
      );

      final area = rect.width * rect.height;
      if (area >= _minArea) {
        valid.add(rect);
      }
    }

    if (valid.isEmpty) {
      return const SceneGeometry(
        numObjects: 0,
        areaRatio: 0,
        sceneCenterX: 0.5,
        sceneCenterY: 0.5,
        unionMarginMin: 0.5,
        unionRoi: null,
      );
    }

    double totalArea = 0;
    double weightedX = 0;
    double weightedY = 0;

    double left = 1.0;
    double top = 1.0;
    double right = 0.0;
    double bottom = 0.0;

    for (final rect in valid) {
      final area = rect.width * rect.height;
      totalArea += area;
      weightedX += rect.center.dx * area;
      weightedY += rect.center.dy * area;

      left = math.min(left, rect.left);
      top = math.min(top, rect.top);
      right = math.max(right, rect.right);
      bottom = math.max(bottom, rect.bottom);
    }

    final union = Rect.fromLTRB(
      left.clamp(0.0, 1.0),
      top.clamp(0.0, 1.0),
      right.clamp(0.0, 1.0),
      bottom.clamp(0.0, 1.0),
    );

    final unionMarginMin = math.min(
      math.min(union.left, union.top),
      math.min(1.0 - union.right, 1.0 - union.bottom),
    ).clamp(0.0, 0.5);

    return SceneGeometry(
      numObjects: valid.length.toDouble(),
      areaRatio: totalArea.clamp(0.0, 1.0),
      sceneCenterX: (weightedX / totalArea).clamp(0.0, 1.0),
      sceneCenterY: (weightedY / totalArea).clamp(0.0, 1.0),
      unionMarginMin: unionMarginMin,
      unionRoi: union,
    );
  }
}

class _EmaSmoother {
  static const _alphaGeometry = 0.24;
  static const _alphaBrightness = 0.38;
  static const _alphaBlur = 0.34;
  static const _alphaExposure = 0.32;

  double? _numObjects;
  double? _areaRatio;
  double? _sceneCenterX;
  double? _sceneCenterY;
  double? _unionMarginMin;

  double? _brightness;
  double? _subjectBrightness;
  double? _backgroundBrightness;
  double? _globalBlurScore;
  double? _subjectBlurScore;
  double? _highlightRatio;
  double? _shadowRatio;
  double? _subjectHighlightRatio;
  double? _subjectShadowRatio;

  ObjectFeatures _current = const ObjectFeatures();
  ObjectFeatures get current => _current;

  ObjectFeatures updateGeometry(SceneGeometry g) {
    _numObjects = _ema(_numObjects, g.numObjects, _alphaGeometry);
    _areaRatio = _ema(_areaRatio, g.areaRatio, _alphaGeometry);
    _sceneCenterX = _ema(_sceneCenterX, g.sceneCenterX, _alphaGeometry);
    _sceneCenterY = _ema(_sceneCenterY, g.sceneCenterY, _alphaGeometry);
    _unionMarginMin = _ema(_unionMarginMin, g.unionMarginMin, _alphaGeometry);
    return _current = _snapshot();
  }

  ObjectFeatures updateImageMetrics(ObjectImageMetrics m) {
    _brightness = _ema(_brightness, m.brightness, _alphaBrightness);
    _subjectBrightness =
        _ema(_subjectBrightness, m.subjectBrightness, _alphaBrightness);
    _backgroundBrightness =
        _ema(_backgroundBrightness, m.backgroundBrightness, _alphaBrightness);

    _globalBlurScore = _ema(_globalBlurScore, m.globalBlurScore, _alphaBlur);
    _subjectBlurScore = _ema(_subjectBlurScore, m.subjectBlurScore, _alphaBlur);

    _highlightRatio = _ema(_highlightRatio, m.highlightRatio, _alphaExposure);
    _shadowRatio = _ema(_shadowRatio, m.shadowRatio, _alphaExposure);
    _subjectHighlightRatio =
        _ema(_subjectHighlightRatio, m.subjectHighlightRatio, _alphaExposure);
    _subjectShadowRatio =
        _ema(_subjectShadowRatio, m.subjectShadowRatio, _alphaExposure);

    return _current = _snapshot();
  }

  void reset() {
    _numObjects = null;
    _areaRatio = null;
    _sceneCenterX = null;
    _sceneCenterY = null;
    _unionMarginMin = null;

    _brightness = null;
    _subjectBrightness = null;
    _backgroundBrightness = null;
    _globalBlurScore = null;
    _subjectBlurScore = null;
    _highlightRatio = null;
    _shadowRatio = null;
    _subjectHighlightRatio = null;
    _subjectShadowRatio = null;

    _current = const ObjectFeatures();
  }

  ObjectFeatures _snapshot() => ObjectFeatures(
        numObjects: _numObjects ?? 0,
        areaRatio: _areaRatio ?? 0,
        sceneCenterX: _sceneCenterX ?? 0.5,
        sceneCenterY: _sceneCenterY ?? 0.5,
        unionMarginMin: _unionMarginMin ?? 0.5,
        brightness: _brightness ?? 0.5,
        subjectBrightness: _subjectBrightness ?? 0.5,
        backgroundBrightness: _backgroundBrightness ?? 0.5,
        globalBlurScore: _globalBlurScore ?? 999,
        subjectBlurScore: _subjectBlurScore ?? 999,
        highlightRatio: _highlightRatio ?? 0,
        shadowRatio: _shadowRatio ?? 0,
        subjectHighlightRatio: _subjectHighlightRatio ?? 0,
        subjectShadowRatio: _subjectShadowRatio ?? 0,
      );

  static double _ema(double? prev, double value, double alpha) {
    if (prev == null) return value;
    return prev * (1.0 - alpha) + value * alpha;
  }
}

class _IssueAccumulator {
  static const double _riseStrong = 0.24;
  static const double _riseSoft = 0.16;
  static const double _decay = 0.12;

  double _tiltStrong = 0;
  double _tiltMild = 0;
  double _blur = 0;
  double _dark = 0;
  double _over = 0;
  double _backlight = 0;
  double _smallSubject = 0;
  double _imbalance = 0;
  double _tightFraming = 0;
  double _clippedSubject = 0;
  double _tooClose = 0;

  void update({
    required bool tiltStrong,
    required bool tiltMild,
    required bool blur,
    required bool dark,
    required bool over,
    required bool backlight,
    required bool smallSubject,
    required bool imbalance,
    required bool tightFraming,
    required bool clippedSubject,
    required bool tooClose,
    bool updateGeometry = true,
    bool updateImageQuality = true,
  }) {
    if (updateGeometry) {
      _tiltStrong = _next(_tiltStrong, tiltStrong, _riseStrong);
      _tiltMild = _next(_tiltMild, tiltMild, _riseSoft);
    }
    if (updateImageQuality) {
      _blur = _next(_blur, blur, _riseStrong);
      _dark = _next(_dark, dark, _riseStrong);
      _over = _next(_over, over, _riseStrong);
      _backlight = _next(_backlight, backlight, _riseStrong);
    }
    if (updateGeometry) {
      _smallSubject = _next(_smallSubject, smallSubject, _riseSoft);
      _imbalance = _next(_imbalance, imbalance, _riseSoft);
      _tightFraming = _next(_tightFraming, tightFraming, _riseSoft);
      _clippedSubject = _next(_clippedSubject, clippedSubject, _riseStrong);
      _tooClose = _next(_tooClose, tooClose, _riseSoft);
    }
  }

  double get tiltStrong => _tiltStrong;
  double get tiltMild => _tiltMild;
  double get blur => _blur;
  double get dark => _dark;
  double get over => _over;
  double get backlight => _backlight;
  double get smallSubject => _smallSubject;
  double get imbalance => _imbalance;
  double get tightFraming => _tightFraming;
  double get clippedSubject => _clippedSubject;
  double get tooClose => _tooClose;

  void reset() {
    _tiltStrong = 0;
    _tiltMild = 0;
    _blur = 0;
    _dark = 0;
    _over = 0;
    _backlight = 0;
    _smallSubject = 0;
    _imbalance = 0;
    _tightFraming = 0;
    _clippedSubject = 0;
    _tooClose = 0;
  }

  static double _next(double prev, bool active, double rise) {
    if (active) return (prev + rise).clamp(0.0, 1.0);
    return (prev - _decay).clamp(0.0, 1.0);
  }
}

class _CoachingEngine {
  static const _tiltWarnDeg = 12.0;
  static const _tiltCautionDeg = 7.0;

  static const _blurCritical = 110.0;
  static const _blurWarning = 160.0;

  static const _subjectDark = 0.20;
  static const _globalDark = 0.18;
  static const _shadowWarn = 0.34;

  static const _overBright = 0.86;
  static const _highlightWarn = 0.18;

  static const _backlightMinBg = 0.65;
  static const _backlightDiff = 0.25;

  static const _smallSubjectSingle = 0.045;
  static const _smallSubjectMulti = 0.030;

  final _IssueAccumulator _acc = _IssueAccumulator();

  CoachingResult decide(
    ObjectFeatures s, {
    required double tiltDeg,
    required bool subjectLocked,
    bool updateGeometry = true,
    bool updateImageQuality = true,
  }) {
    final dark = subjectLocked
        ? (s.subjectBrightness < _subjectDark &&
                s.subjectShadowRatio > 0.18) ||
            s.subjectBrightness < (_subjectDark - 0.03)
        : (s.subjectBrightness < _subjectDark && s.shadowRatio > 0.20) ||
            (s.brightness < _globalDark && s.shadowRatio > _shadowWarn);

    final over = subjectLocked
        ? (s.subjectBrightness > 0.83) ||
            (s.subjectHighlightRatio > 0.16 && s.subjectBrightness > 0.70)
        : (s.brightness > _overBright) ||
            (s.highlightRatio > _highlightWarn && s.subjectBrightness > 0.72);

    final backlight =
        s.subjectBrightness < (s.backgroundBrightness - _backlightDiff) &&
            s.backgroundBrightness > _backlightMinBg &&
            s.subjectBrightness < 0.38;
    final severeTilt = tiltDeg.abs() >= _tiltWarnDeg;
    final mildTilt = tiltDeg.abs() >= _tiltCautionDeg;

    final blur = subjectLocked
        ? s.subjectBlurScore < _blurCritical
        : s.subjectBlurScore < _blurCritical &&
            s.globalBlurScore < _blurWarning;

    final smallSubjectThreshold =
        s.numObjects <= 2 ? _smallSubjectSingle : _smallSubjectMulti;
    final smallSubject =
        s.numObjects >= 1 && s.areaRatio < smallSubjectThreshold;

    final imbalanceThreshold = s.numObjects <= 2 ? 0.17 : 0.24;
    final imbalance = (s.sceneCenterX - 0.5).abs() > imbalanceThreshold;

    final tightFramingSingle =
        s.numObjects <= 2 && s.unionMarginMin < 0.025 && s.areaRatio > 0.18;
    final tightFramingMulti =
        s.numObjects >= 3 && s.unionMarginMin < 0.012 && s.areaRatio > 0.28;
    final tightFraming = tightFramingSingle || tightFramingMulti;
    final clippedSubject = subjectLocked &&
        s.numObjects >= 1 &&
        s.unionMarginMin < 0.04 &&
        s.areaRatio > 0.05;
    final tooClose = subjectLocked &&
        s.numObjects >= 1 &&
        (s.areaRatio > 0.62 ||
            (s.areaRatio > 0.50 && s.unionMarginMin < 0.010));

    _acc.update(
      tiltStrong: severeTilt,
      tiltMild: mildTilt,
      blur: blur,
      dark: dark,
      over: over,
      backlight: backlight,
      smallSubject: smallSubject,
      imbalance: imbalance,
      tightFraming: tightFraming,
      clippedSubject: clippedSubject,
      tooClose: tooClose,
      updateGeometry: updateGeometry,
      updateImageQuality: updateImageQuality,
    );

    // 피사체 고정 조건은 다른 모든 코칭보다 우선한다.
    // clippedSubject: 피사체가 프레임 가장자리에 걸쳐 잘리는 경우 (즉시 감지)
    if (_acc.clippedSubject >= 0.24) {
      return const CoachingResult(
        guidance: '피사체가 화면에서 잘리고 있어요',
        subGuidance: '피사체 전체가 보이도록 조금 뒤로 가거나 프레임 안쪽으로 옮겨보세요',
        level: CoachingLevel.warning,
      );
    }

    if (_acc.tiltStrong >= 0.45) {
      return const CoachingResult(
        guidance: '화면이 많이 기울어져 있어요',
        subGuidance: '휴대폰을 수평에 가깝게 맞춰보세요',
        level: CoachingLevel.warning,
      );
    }

    if (_acc.tooClose >= 0.48) {
      return const CoachingResult(
        guidance: '고정한 피사체가 너무 가까워요',
        subGuidance: '피사체가 답답하지 않게 보이도록 조금 뒤로 가서 여백을 만들어보세요',
        level: CoachingLevel.caution,
      );
    }

    if (_acc.blur >= 0.52) {
      return const CoachingResult(
        guidance: '화면이 흐릿해요',
        subGuidance: '잠시 멈추고 초점이나 손떨림을 확인해보세요',
        level: CoachingLevel.warning,
      );
    }

    if (_acc.dark >= 0.52) {
      return const CoachingResult(
        guidance: '장면이 어두워요',
        subGuidance: '조명을 켜거나 더 밝은 곳으로 이동해보세요',
        level: CoachingLevel.warning,
      );
    }

    if (_acc.over >= 0.52) {
      return const CoachingResult(
        guidance: '빛이 너무 강해요',
        subGuidance: '각도나 위치를 조금 바꿔보세요',
        level: CoachingLevel.warning,
      );
    }

    if (_acc.backlight >= 0.52) {
      return const CoachingResult(
        guidance: '피사체가 배경보다 어두워요',
        subGuidance: '촬영 각도를 바꾸거나 피사체 쪽 빛을 늘려보세요',
        level: CoachingLevel.warning,
      );
    }

    if (_acc.tiltMild >= 0.50) {
      return const CoachingResult(
        guidance: '화면이 약간 기울어져 있어요',
        subGuidance: '수평을 조금만 더 맞춰보세요',
        level: CoachingLevel.caution,
      );
    }

    if (_acc.smallSubject >= 0.56) {
      return const CoachingResult(
        guidance: '조금 더 가까이 담아도 좋아요',
        subGuidance: '피사체가 더 또렷하게 보일 수 있어요',
        level: CoachingLevel.caution,
      );
    }

    if (_acc.imbalance >= 0.58) {
      final moveRight = s.sceneCenterX < 0.5;
      return CoachingResult(
        guidance: moveRight
            ? '구도가 왼쪽으로 치우쳐 있어요'
            : '구도가 오른쪽으로 치우쳐 있어요',
        subGuidance: moveRight
            ? '카메라를 조금 오른쪽으로 옮겨보세요'
            : '카메라를 조금 왼쪽으로 옮겨보세요',
        level: CoachingLevel.caution,
      );
    }

    if (_acc.tightFraming >= 0.62) {
      return const CoachingResult(
        guidance: '조금 더 넓게 담아도 좋아요',
        subGuidance: '여백이 생기면 장면이 더 편안해 보여요',
        level: CoachingLevel.caution,
      );
    }

    // 치명적 결함이 있으면 good 불가
    final hasCriticalIssue = _acc.blur >= 0.35 ||
        _acc.dark >= 0.35 ||
        _acc.over >= 0.35 ||
        _acc.backlight >= 0.35 ||
        _acc.clippedSubject >= 0.35 ||
        _acc.tooClose >= 0.35 ||
        _acc.tiltStrong >= 0.35;

    if (!hasCriticalIssue) {
      final score = _computeGoodScore(
        s,
        tiltDeg,
        subjectLocked: subjectLocked,
      );
      if (score >= 70.0) {
        return const CoachingResult(
          guidance: '지금 찍어보세요',
          subGuidance: '현재 장면이 비교적 안정적이에요',
          level: CoachingLevel.good,
        );
      }
    }

    return const CoachingResult(
      guidance: '원하는 장면대로 담아보세요',
      subGuidance: '크게 문제는 없어요. 필요하면 각도만 조금 조정해보세요',
      level: CoachingLevel.caution,
    );
  }

  // 0~100점 환산. 블러 35점 + 밝기 30점 + 기울기 15점 + 구도 12점 + 균형 8점
  double _computeGoodScore(
    ObjectFeatures s,
    double tiltDeg, {
    required bool subjectLocked,
  }) {
    if (s.numObjects < 0.5) return 0.0;

    // 블러 (35점) — subjectBlurScore 140~200 선형
    final blurScore = _lerp(s.subjectBlurScore, 140.0, 200.0, 0.0, 35.0);

    // 밝기 (30점) — subjectBrightness 0.24~0.78, 중심 0.51에 가까울수록 만점
    final brightnessScore = () {
      final b = s.subjectBrightness;
      if (b < 0.24 || b > 0.78) return 0.0;
      // 중심(0.51)에서 거리가 멀수록 감점
      final dist = (b - 0.51).abs();
      final maxDist = 0.27; // 0.51 - 0.24
      return _lerp(dist, 0.0, maxDist, 30.0, 0.0);
    }();

    // 기울기 (15점) — 0~4.5도 만점, 4.5~12도 선형 감소
    final tiltScore = _lerp(tiltDeg.abs(), 0.0, 12.0, 15.0, 0.0);

    // 구도 (12점) — areaRatio 적정 범위 + marginMin 여백
    final framingScore = () {
      final areaOk = subjectLocked
          ? s.areaRatio >= 0.05 && s.areaRatio <= 0.52
          : s.areaRatio >= 0.04 && s.areaRatio <= 0.58;
      final marginOk = s.unionMarginMin >= 0.02;
      if (areaOk && marginOk) return 12.0;
      if (areaOk || marginOk) return 6.0;
      return 0.0;
    }();

    // 균형 (8점) — sceneCenterX 0.5 기준 거리 선형
    final balanceThreshold = s.numObjects <= 2 ? 0.15 : 0.22;
    final balanceScore =
        _lerp((s.sceneCenterX - 0.5).abs(), 0.0, balanceThreshold, 8.0, 0.0);

    return blurScore + brightnessScore + tiltScore + framingScore + balanceScore;
  }

  static double _lerp(
      double value, double inMin, double inMax, double outMin, double outMax) {
    if (inMax <= inMin) return outMin;
    final t = ((value - inMin) / (inMax - inMin)).clamp(0.0, 1.0);
    return outMin + t * (outMax - outMin);
  }

  void reset() => _acc.reset();
}

class ObjectCoach {
  final _extractor = _FeatureExtractor();
  final _smoother = _EmaSmoother();
  final _engine = _CoachingEngine();

  SceneGeometry _latestGeometry = const SceneGeometry(
    numObjects: 0,
    areaRatio: 0,
    sceneCenterX: 0.5,
    sceneCenterY: 0.5,
    unionMarginMin: 0.5,
    unionRoi: null,
  );

  bool _imageAnalysisPending = false;
  double _tiltDeg = 0.0;
  bool _subjectLocked = false;
  bool _subjectInFrame = true;

  CoachingResult _currentResult = const CoachingResult(
    guidance: '구도를 잡는 중...',
    level: CoachingLevel.caution,
  );

  void updateTilt(double tiltDeg) {
    _tiltDeg = tiltDeg;
  }

  CoachingResult updateDetections(
    List<YOLOResult> results,
    Size frameSize, {
    required bool subjectLocked,
    required bool subjectInFrame,
  }) {
    _subjectLocked = subjectLocked;
    _subjectInFrame = subjectInFrame;

    // 피사체가 화면 밖으로 완전히 사라진 경우 — 가장 높은 우선순위.
    // geometry 추출 이전에 확인해 다른 어떤 코칭도 이를 덮어쓰지 않는다.
    if (_subjectLocked && !_subjectInFrame) {
      _currentResult = const CoachingResult(
        guidance: '피사체가 화면 밖으로 나갔어요',
        subGuidance: '고정한 피사체가 다시 프레임 안으로 들어오도록 카메라를 움직여보세요',
        level: CoachingLevel.warning,
      );
      return _currentResult;
    }

    final geometry = _extractor.extract(results);
    _latestGeometry = geometry;
    _smoother.updateGeometry(geometry);
    final current = _smoother.current;
    _currentResult = _engine.decide(
      current,
      tiltDeg: _tiltDeg,
      subjectLocked: _subjectLocked,
      updateGeometry: true,
      updateImageQuality: false,
    );
    return _currentResult;
  }

  /// Called directly with pre-computed metrics from Kotlin native side.
  CoachingResult applyImageMetrics(Map<String, double> metrics) {
    final m = ObjectImageMetrics(
      brightness: metrics['brightness'] ?? 0.5,
      subjectBrightness: metrics['subjectBrightness'] ?? 0.5,
      backgroundBrightness: metrics['backgroundBrightness'] ?? 0.5,
      highlightRatio: metrics['highlightRatio'] ?? 0.0,
      shadowRatio: metrics['shadowRatio'] ?? 0.0,
      subjectHighlightRatio: metrics['subjectHighlightRatio'] ?? 0.0,
      subjectShadowRatio: metrics['subjectShadowRatio'] ?? 0.0,
      globalBlurScore: metrics['globalBlurScore'] ?? 999.0,
      subjectBlurScore: metrics['subjectBlurScore'] ?? 999.0,
    );
    _smoother.updateImageMetrics(m);
    if (_subjectLocked && !_subjectInFrame) {
      _currentResult = const CoachingResult(
        guidance: '피사체가 화면 밖으로 나갔어요',
        subGuidance: '고정한 피사체가 다시 프레임 안으로 들어오도록 카메라를 움직여보세요',
        level: CoachingLevel.warning,
      );
      return _currentResult;
    }
    _currentResult = _engine.decide(
      _smoother.current,
      tiltDeg: _tiltDeg,
      subjectLocked: _subjectLocked,
      updateGeometry: false,
      updateImageQuality: true,
    );
    return _currentResult;
  }

  Future<void> analyzeImage(List<int> jpegBytes) async {
    if (_imageAnalysisPending) return;
    _imageAnalysisPending = true;

    try {
      final metrics = await analyzeObjectImage(
        AnalyzeRequest(
          jpegBytes: jpegBytes,
          unionRoi: _latestGeometry.unionRoi == null
              ? null
              : [
                  _latestGeometry.unionRoi!.left,
                  _latestGeometry.unionRoi!.top,
                  _latestGeometry.unionRoi!.right,
                  _latestGeometry.unionRoi!.bottom,
                ],
        ),
      );

      _smoother.updateImageMetrics(metrics);
      _currentResult = _engine.decide(
        _smoother.current,
        tiltDeg: _tiltDeg,
        subjectLocked: _subjectLocked,
        updateGeometry: false,
        updateImageQuality: true,
      );
    } finally {
      _imageAnalysisPending = false;
    }
  }

  CoachingResult get currentResult => _currentResult;
  ObjectFeatures get smoothedFeatures => _smoother.current;

  void reset() {
    _smoother.reset();
    _engine.reset();
    _tiltDeg = 0.0;
    _subjectLocked = false;
    _subjectInFrame = true;

    _latestGeometry = const SceneGeometry(
      numObjects: 0,
      areaRatio: 0,
      sceneCenterX: 0.5,
      sceneCenterY: 0.5,
      unionMarginMin: 0.5,
      unionRoi: null,
    );

    _currentResult = const CoachingResult(
      guidance: '구도를 잡는 중...',
      level: CoachingLevel.caution,
    );
  }
}
