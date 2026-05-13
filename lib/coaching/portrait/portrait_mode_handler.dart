/// 인물 모드 핸들러
///
/// camera_screen.dart에서 인물 모드 관련 로직을 분리한 클래스.
/// YOLO Pose 키포인트 파싱, 조명 분류, ML Kit 얼굴 분석,
/// 코칭 엔진 호출을 담당합니다.
///
/// 최적화:
/// - captureFrame()을 조명+얼굴 분석에서 공유 (한 번만 캡처)
/// - 분석 주기를 조명 30프레임, 얼굴 20프레임으로 설정
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:ultralytics_yolo/yolo.dart';

import '../../composition/composition_rule.dart';
import '../../utils/debug_log_flags.dart';
import 'face_quality_classifier.dart';
import 'lighting_classifier.dart';
import 'portrait_coach_engine.dart';
import 'portrait_overlay_painter.dart';
import 'portrait_scene_state.dart';

// Face analysis source selection. Default: previewCapture (existing behavior).
enum FaceAnalysisSource { previewCapture, imageAnalysis }

enum NativeFaceConfidenceStatus {
  usable,
  small,
  outOfBounds,
  uncertain,
}

class NativeFaceResult {
  final Rect boundingBox;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? smilingProbability;
  final double? headEulerAngleY;
  final double? headEulerAngleZ;
  final double? headEulerAngleX;
  final int imageWidth;
  final int imageHeight;
  final int rotationDegrees;
  final bool isFrontCamera;
  final int? timestampMs;
  final int? frameNumber;
  final NativeFaceConfidenceStatus confidenceStatus;

  const NativeFaceResult({
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.rotationDegrees,
    required this.isFrontCamera,
    this.confidenceStatus = NativeFaceConfidenceStatus.usable,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.smilingProbability,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.headEulerAngleX,
    this.timestampMs,
    this.frameNumber,
  });

  factory NativeFaceResult.fromMap(Map<String, dynamic> map) {
    final boundingBox = Rect.fromLTRB(
        (map['left'] as num?)?.toDouble() ?? 0.0,
        (map['top'] as num?)?.toDouble() ?? 0.0,
        (map['right'] as num?)?.toDouble() ?? 0.0,
        (map['bottom'] as num?)?.toDouble() ?? 0.0,
    );
    final imageWidth = (map['imageWidth'] as num?)?.toInt() ?? 0;
    final imageHeight = (map['imageHeight'] as num?)?.toInt() ?? 0;
    return NativeFaceResult(
      boundingBox: boundingBox,
      leftEyeOpenProbability:
          (map['leftEyeOpenProbability'] as num?)?.toDouble(),
      rightEyeOpenProbability:
          (map['rightEyeOpenProbability'] as num?)?.toDouble(),
      smilingProbability: (map['smilingProbability'] as num?)?.toDouble(),
      headEulerAngleY: (map['headEulerAngleY'] as num?)?.toDouble(),
      headEulerAngleZ: (map['headEulerAngleZ'] as num?)?.toDouble(),
      headEulerAngleX: (map['headEulerAngleX'] as num?)?.toDouble(),
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      rotationDegrees: (map['rotationDegrees'] as num?)?.toInt() ?? 0,
      isFrontCamera: map['isFrontCamera'] == true,
      timestampMs: (map['timestampMs'] as num?)?.toInt(),
      frameNumber: (map['frameNumber'] as num?)?.toInt(),
      confidenceStatus: _statusFromMap(
        map['confidenceStatus'] as String?,
        boundingBox,
        imageWidth,
        imageHeight,
      ),
    );
  }

  NativeFaceResult copyWith({
    Rect? boundingBox,
    NativeFaceConfidenceStatus? confidenceStatus,
  }) {
    return NativeFaceResult(
      boundingBox: boundingBox ?? this.boundingBox,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      rotationDegrees: rotationDegrees,
      isFrontCamera: isFrontCamera,
      confidenceStatus: confidenceStatus ?? this.confidenceStatus,
      leftEyeOpenProbability: leftEyeOpenProbability,
      rightEyeOpenProbability: rightEyeOpenProbability,
      smilingProbability: smilingProbability,
      headEulerAngleY: headEulerAngleY,
      headEulerAngleZ: headEulerAngleZ,
      headEulerAngleX: headEulerAngleX,
      timestampMs: timestampMs,
      frameNumber: frameNumber,
    );
  }

  static NativeFaceConfidenceStatus _statusFromMap(
    String? raw,
    Rect boundingBox,
    int imageWidth,
    int imageHeight,
  ) {
    switch (raw) {
      case 'usable':
        return NativeFaceConfidenceStatus.usable;
      case 'small':
        return NativeFaceConfidenceStatus.small;
      case 'out_of_bounds':
        return NativeFaceConfidenceStatus.outOfBounds;
      case 'uncertain':
        return NativeFaceConfidenceStatus.uncertain;
    }
    return _inferStatus(boundingBox, imageWidth, imageHeight);
  }

  static NativeFaceConfidenceStatus _inferStatus(
    Rect boundingBox,
    int imageWidth,
    int imageHeight,
  ) {
    if (imageWidth <= 0 || imageHeight <= 0 || boundingBox.isEmpty) {
      return NativeFaceConfidenceStatus.uncertain;
    }
    final outOfBounds = boundingBox.left < 0 ||
        boundingBox.top < 0 ||
        boundingBox.right > imageWidth ||
        boundingBox.bottom > imageHeight;
    if (outOfBounds) return NativeFaceConfidenceStatus.outOfBounds;

    final imageArea = imageWidth * imageHeight;
    final faceArea = boundingBox.width * boundingBox.height;
    if (imageArea <= 0 || faceArea <= 0) {
      return NativeFaceConfidenceStatus.uncertain;
    }
    if (faceArea / imageArea < 0.006) {
      return NativeFaceConfidenceStatus.small;
    }
    return NativeFaceConfidenceStatus.usable;
  }

  String get confidenceStatusName {
    switch (confidenceStatus) {
      case NativeFaceConfidenceStatus.usable:
        return 'usable';
      case NativeFaceConfidenceStatus.small:
        return 'small';
      case NativeFaceConfidenceStatus.outOfBounds:
        return 'out_of_bounds';
      case NativeFaceConfidenceStatus.uncertain:
        return 'uncertain';
    }
  }
}

// ─── YOLO Pose 키포인트 인덱스 (COCO 17) ────────────────────

class PoseKeypointIndex {
  static const int nose = 0;
  static const int leftEye = 1;
  static const int rightEye = 2;
  static const int leftEar = 3;
  static const int rightEar = 4;
  static const int leftShoulder = 5;
  static const int rightShoulder = 6;
  static const int leftElbow = 7;
  static const int rightElbow = 8;
  static const int leftWrist = 9;
  static const int rightWrist = 10;
  static const int leftHip = 11;
  static const int rightHip = 12;
  static const int leftKnee = 13;
  static const int rightKnee = 14;
  static const int leftAnkle = 15;
  static const int rightAnkle = 16;
}

/// 인물 모드 분석 결과 — camera_screen이 UI 갱신에 사용
class PortraitAnalysisResult {
  final CoachingResult coaching;
  final OverlayData overlayData;
  final ShotType shotType;
  final int personCount;
  final bool hasPersonStable;

  const PortraitAnalysisResult({
    required this.coaching,
    required this.overlayData,
    required this.shotType,
    required this.personCount,
    required this.hasPersonStable,
  });
}

// ─── 인물 모드 핸들러 ──────────────────────────────────────

class PortraitModeHandler {
  final PortraitCoachEngine _coachEngine = PortraitCoachEngine();
  final LightingClassifier _lightingClassifier = LightingClassifier();
  final FaceQualityClassifier _faceQualityClassifier = FaceQualityClassifier();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  // ─── 분석 주기 (최적화: 기존 15/10 → 30/20으로 늘림) ────
  static const double _posePointAlpha = 0.38;
  static const int _lightingEveryN = 30;
  // 얼굴 분석 간격(프레임): 기기 성능에 맞춰 조절 가능
  // 기본값은 45 (저사양 기기는 30 권장). 성능 실험을 위해 120을 임시로 사용 가능.
  int _faceEveryN = 45;
  static const int _faceQualityEveryN = 120;
  static const int _maxFaceQualityFaces = 1; // 디버깅용: 임시 최대 처리 얼굴 수
  final bool _faceQualityDebug = false; // true일 때만 상세 로그 출력
  bool _isFaceQualityAnalyzing = false; // 중복 분석 방지
  bool _enableFaceQuality = false; // 전체 기능 ON/OFF (false = 완전 비활성)
  bool _enableFaceAnalysis = false; // ML Kit face analysis (false = off)
  bool _enableLightingAnalysis = false; // Lighting classifier (false = off)
  bool _enableBitmapCaptureForFace =
      true; // when false, captureFrame won't be called for face
  int _lastFaceAnalysisFrame = -999999;
  bool _isLightingAnalyzing = false;
  int _lastFaceQualityFrame = -999999;
  static const double _lightingMinConf = 0.5;

  // ─── 메시지 안정화 ────────────────────────────────
  static const int _stabilityThreshold = 5;
  String stableMessage = '카메라를 사람에게 향해주세요';
  String _pendingMessage = '';
  int _pendingCount = 0;
  CoachingResult _stableCoaching = const CoachingResult(
    message: '카메라를 사람에게 향해주세요',
    priority: CoachingPriority.critical,
    confidence: 1.0,
  );

  // ─── 사람 감지 안정화 ──────────────────────────────
  int _personStreak = 0;

  // ─── 그룹샷 안정화 (히스테리시스) ─────────────────
  // 진입: 2프레임 연속 2명 이상 → 그룹샷 확정
  // 이탈: 5프레임 연속 1명 이하 → 그룹샷 해제
  bool _isGroupShotStable = false;
  int _groupStreak = 0;
  int _stablePersonCount = 1;
  int _candidatePersonCount = 1;
  int _candidatePersonCountStreak = 0;
  static const int _groupEnterThreshold = 2;
  static const int _groupExitThreshold = 5;

  // ─── 분석 프레임 카운터 ────────────────────────────
  int _frameCount = 0;
  bool _isAnalyzing = false; // captureFrame 기반 분석 잠금
  bool _isFaceAnalyzing = false;

  List<double> _faceQualityScores = const [];

  // ─── 조명 결과 ────────────────────────────────────
  LightingCondition lastLighting = LightingCondition.unknown;
  double lastLightingConf = 0.0;

  // ─── 얼굴 분석 결과 ───────────────────────────────
  double? _faceYaw;
  double? _facePitch;
  double? _faceRoll;
  double? _leftEyeOpen;
  double? _rightEyeOpen;
  double? _smileProb;
  Rect? _trackedMainBox;
  Rect? _smoothedFaceRect;
  Rect? _smoothedBodyRect;
  final Map<int, Offset> _smoothedPosePoints = <int, Offset>{};
  List<NativeFaceResult> _latestNativeFaceResults = const [];
  int _nativeFaceImageWidth = 0;
  int _nativeFaceImageHeight = 0;
  int _nativeFaceRotationDegrees = 0;
  int _nativeFaceFrameNumber = -1;
  bool _nativeFaceIsFrontCamera = false;
  int _nativeFaceTimestampMs = 0;
  int _lastNativeFaceCount = -1;
  int _lastNativeFaceSummaryLogMs = 0;
  int _lastNonEmptyNativeFaceAtMs = 0;
  int _lastNonEmptyNativeFaceFrame = -1;
  static const int _nativeFaceGraceMs = 400;
  static const int _nativeFaceGraceFrames = 8;
  static const int _maxGroupNativeFaces = 6;

  /// 그룹샷 전용: ML Kit으로 감지한 모든 얼굴 중 눈 감긴 사람이 있는지 여부
  bool _anyFaceEyesClosed = false;
  int _closedFaceCount = 0;
  List<Rect> _closedFaceRects = const [];

  // ─── 눈 감김 정밀 추적 ────────────────────────────
  int _eyeClosedStreak = 0; // 연속 눈 감김 프레임 수 (네이티브 raw 기반)
  int _anyEyeClosedStreak = 0; // 그룹 눈 감김 연속 프레임
  static const int _eyeConfirmFrames = 2; // 확정에 필요한 연속 프레임

  // ─── 카메라 안정성 추적 ───────────────────────────
  double _cameraStability = 1.0;
  final List<double> _recentDeltas = [];
  Offset? _prevStabilityCenter;
  double? _prevShoulderWidth;
  double? _prevEyeWidth;
  double? _prevShoulderAngle;
  static const int _stabilityWindow = 10;
  static const double _stabilityMaxDelta = 0.018;

  static const double _faceMetricAlpha = 0.3;
  static const double _faceRectAlpha = 0.35;
  static const double _bodyRectAlpha = 0.2;

  // ─── 외부 설정 ────────────────────────────────────
  bool isFrontCamera = false;
  PortraitIntent intent = PortraitIntent.single;

  // Face analysis source selection (previewCapture by default).
  FaceAnalysisSource _faceAnalysisSource = FaceAnalysisSource.previewCapture;
  void setFaceAnalysisSource(FaceAnalysisSource s) => _faceAnalysisSource = s;
  FaceAnalysisSource get faceAnalysisSource => _faceAnalysisSource;

  /// 기기 방향 (0=세로, 90=가로 왼쪽, 180=거꾸로, 270=가로 오른쪽)
  /// camera_screen.dart에서 가속도계 기반으로 갱신합니다.
  int deviceOrientationDeg = 0;

  String get _portraitModeLabel =>
      intent == PortraitIntent.group ? 'group' : 'single';

  /// 현재 카메라 프레임을 JPEG bytes로 캡처하는 콜백.
  /// camera_screen.dart에서 _cameraController.captureFrame을 주입합니다.
  Future<Uint8List?> Function()? captureFrameCallback;

  // ─── 초기화 / 해제 ────────────────────────────────

  Future<void> init() async {
    await _lightingClassifier.load();
    await _faceQualityClassifier.load();
    if (DebugLogFlags.portraitMode) {
      debugPrint(
        '[PORTRAIT_MODE] init done lighting=${_lightingClassifier.isLoaded} '
        'faceQuality=${_faceQualityClassifier.isLoaded}',
      );
    }
  }

  // 런타임에서 얼굴 분석 주기를 조절할 수 있도록 setter/getter 제공
  void setFaceAnalysisInterval(int frames) {
    _faceEveryN = frames.clamp(1, 10000);
  }

  int get faceAnalysisInterval => _faceEveryN;

  /// 사용자가 상단 selector에서 선택한 구도 규칙을 코칭 엔진에 전달.
  void setRule(CompositionRule rule) {
    _coachEngine.setRule(rule);
  }

  void setIntent(PortraitIntent nextIntent) {
    if (intent == nextIntent) return;
    intent = nextIntent;
    _isGroupShotStable = false;
    _groupStreak = 0;
    _stablePersonCount = 1;
    _candidatePersonCount = 1;
    _candidatePersonCountStreak = 0;
  }

  // Debug toggles (public) to allow runtime enabling/disabling from UI
  void setFaceAnalysisEnabled(bool enabled) => _enableFaceAnalysis = enabled;
  bool get isFaceAnalysisEnabled => _enableFaceAnalysis;

  void setLightingAnalysisEnabled(bool enabled) =>
      _enableLightingAnalysis = enabled;
  bool get isLightingAnalysisEnabled => _enableLightingAnalysis;

  void setFaceQualityEnabled(bool enabled) => _enableFaceQuality = enabled;
  bool get isFaceQualityEnabled => _enableFaceQuality;

  void setBitmapCaptureForFaceEnabled(bool enabled) =>
      _enableBitmapCaptureForFace = enabled;
  bool get isBitmapCaptureForFaceEnabled => _enableBitmapCaptureForFace;

  void dispose() {
    _lightingClassifier.dispose();
    _faceQualityClassifier.dispose();
    _faceDetector.close();
  }

  void reset() {
    _personStreak = 0;
    _isGroupShotStable = false;
    _groupStreak = 0;
    _stablePersonCount = 1;
    _candidatePersonCount = 1;
    _candidatePersonCountStreak = 0;
    _frameCount = 0;
    _isAnalyzing = false;
    _isFaceAnalyzing = false;
    lastLighting = LightingCondition.unknown;
    lastLightingConf = 0.0;
    _faceYaw = null;
    _facePitch = null;
    _faceRoll = null;
    _leftEyeOpen = null;
    _rightEyeOpen = null;
    _smileProb = null;
    _trackedMainBox = null;
    _smoothedFaceRect = null;
    _smoothedBodyRect = null;
    _smoothedPosePoints.clear();
    _latestNativeFaceResults = const [];
    _nativeFaceImageWidth = 0;
    _nativeFaceImageHeight = 0;
    _nativeFaceRotationDegrees = 0;
    _nativeFaceFrameNumber = -1;
    _nativeFaceIsFrontCamera = false;
    _nativeFaceTimestampMs = 0;
    _lastNativeFaceCount = -1;
    _lastNativeFaceSummaryLogMs = 0;
    _lastNonEmptyNativeFaceAtMs = 0;
    _lastNonEmptyNativeFaceFrame = -1;
    _anyFaceEyesClosed = false;
    _closedFaceCount = 0;
    _closedFaceRects = const [];
    _eyeClosedStreak = 0;
    _anyEyeClosedStreak = 0;
    _cameraStability = 1.0;
    _recentDeltas.clear();
    _prevStabilityCenter = null;
    _prevShoulderWidth = null;
    _prevEyeWidth = null;
    _prevShoulderAngle = null;

    _faceQualityScores = const [];
    stableMessage = '카메라를 사람에게 향해주세요';
    _pendingMessage = '';
    _pendingCount = 0;
    _stableCoaching = const CoachingResult(
      message: '카메라를 사람에게 향해주세요',
      priority: CoachingPriority.critical,
      confidence: 1.0,
    );
  }

  void updateNativeMetrics(Map<String, double> metrics) {
    double? rawYaw = metrics['portraitFaceYaw'];
    double? rawPitch = metrics['portraitFacePitch'];
    double? rawRoll = metrics['portraitFaceRoll'];

    // ─── 가로 모드 각도 보정 ───────────────────────────────
    // 기기가 가로로 돌아갔을 때 카메라 센서 기준의 yaw/roll이
    // 화면 기준과 90° 어긋납니다.
    // 가로 왼쪽(90°): 센서 yaw → 화면 roll, 센서 roll → 화면 -yaw
    // 가로 오른쪽(270°): 센서 yaw → 화면 -roll, 센서 roll → 화면 yaw
    if (deviceOrientationDeg == 90 && rawYaw != null && rawRoll != null) {
      final tmp = rawYaw;
      rawYaw = -rawRoll;
      rawRoll = tmp;
    } else if (deviceOrientationDeg == 180 &&
        rawYaw != null &&
        rawRoll != null) {
      // 거꾸로(180°): yaw 부호 반전, roll 부호 반전
      rawYaw = -rawYaw;
      rawRoll = -rawRoll;
    } else if (deviceOrientationDeg == 270 &&
        rawYaw != null &&
        rawRoll != null) {
      final tmp = rawYaw;
      rawYaw = rawRoll;
      rawRoll = -tmp;
    }

    _faceYaw = _smoothMetric(_faceYaw, rawYaw);
    _facePitch = _smoothMetric(_facePitch, rawPitch);
    _faceRoll = _smoothMetric(_faceRoll, rawRoll);
    _leftEyeOpen = _smoothEyeMetric(
      _leftEyeOpen,
      metrics['portraitLeftEyeOpen'],
    );
    _rightEyeOpen = _smoothEyeMetric(
      _rightEyeOpen,
      metrics['portraitRightEyeOpen'],
    );

    // 눈 감김 스트릭 추적 (원본 값 기반, 스무딩 무관)
    final rawL = metrics['portraitLeftEyeOpen'];
    final rawR = metrics['portraitRightEyeOpen'];
    if (rawL != null && rawR != null && rawL < 0.35 && rawR < 0.35) {
      _eyeClosedStreak++;
    } else {
      _eyeClosedStreak = 0;
    }
    _smileProb = _smoothMetric(_smileProb, metrics['portraitSmileProbability']);

    final lightingCode = metrics['portraitLightingCode'];
    lastLighting = _lightingFromCode(lightingCode);
    lastLightingConf =
        _smoothMetric(
          lastLightingConf == 0.0 ? null : lastLightingConf,
          metrics['portraitLightingConfidence'],
        ) ??
        0.0;
  }

  void updateNativeFaceResults(
    List<NativeFaceResult> results, {
    int? imageWidth,
    int? imageHeight,
    int? rotationDegrees,
    int? frameNumber,
    bool? isFrontCamera,
    int? timestampMs,
  }) {
    _nativeFaceImageWidth = imageWidth ?? _nativeFaceImageWidth;
    _nativeFaceImageHeight = imageHeight ?? _nativeFaceImageHeight;
    _nativeFaceRotationDegrees = rotationDegrees ?? _nativeFaceRotationDegrees;
    _nativeFaceFrameNumber = frameNumber ?? _nativeFaceFrameNumber;
    _nativeFaceIsFrontCamera = isFrontCamera ?? _nativeFaceIsFrontCamera;
    _nativeFaceTimestampMs = timestampMs ?? _nativeFaceTimestampMs;

    final rawCount = results.length;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final hasRecentFace =
        _latestNativeFaceResults.isNotEmpty &&
        (nowMs - _lastNonEmptyNativeFaceAtMs <= _nativeFaceGraceMs ||
            (_nativeFaceFrameNumber >= 0 &&
                _lastNonEmptyNativeFaceFrame >= 0 &&
                _nativeFaceFrameNumber - _lastNonEmptyNativeFaceFrame <=
                    _nativeFaceGraceFrames));

    if (results.isNotEmpty) {
      _latestNativeFaceResults = _selectNativeFacesForIntent(results);
      _lastNonEmptyNativeFaceAtMs = nowMs;
      _lastNonEmptyNativeFaceFrame = _nativeFaceFrameNumber;
    } else if (!hasRecentFace) {
      _latestNativeFaceResults = const [];
    }

    final effectiveResults = _latestNativeFaceResults;

    final countChanged = rawCount != _lastNativeFaceCount;
    final shouldLogSummary =
        countChanged || nowMs - _lastNativeFaceSummaryLogMs >= 1000;
    if (shouldLogSummary && DebugLogFlags.nativeFace) {
      _lastNativeFaceSummaryLogMs = nowMs;
      _lastNativeFaceCount = rawCount;
      debugPrint(
        '[NATIVE_FACE] count=$rawCount '
        'image=${_nativeFaceImageWidth}x$_nativeFaceImageHeight '
        'rotation=$_nativeFaceRotationDegrees',
      );
      debugPrint(
        '[NATIVE_FACE_DEBUG] mode=$_portraitModeLabel '
        'subscribed=true rawCount=$rawCount effectiveCount=${effectiveResults.length} '
        'image=${_nativeFaceImageWidth}x$_nativeFaceImageHeight '
        'rotation=$_nativeFaceRotationDegrees '
        'frame=$_nativeFaceFrameNumber source=$_faceAnalysisSource',
      );
    }

    if (_faceAnalysisSource != FaceAnalysisSource.imageAnalysis) return;

    if (effectiveResults.isNotEmpty) {
      final mainFace = _selectPrimaryNativeFace(effectiveResults);
      _faceYaw = _smoothMetric(_faceYaw, mainFace.headEulerAngleY);
      _facePitch = _smoothMetric(_facePitch, mainFace.headEulerAngleX);
      _faceRoll = _smoothMetric(_faceRoll, mainFace.headEulerAngleZ);
      final canUseMainEyeProb = _isNativeFaceFrontalForEyes(mainFace);
      if (canUseMainEyeProb) {
        _leftEyeOpen = _smoothEyeMetric(
          _leftEyeOpen,
          mainFace.leftEyeOpenProbability,
        );
        _rightEyeOpen = _smoothEyeMetric(
          _rightEyeOpen,
          mainFace.rightEyeOpenProbability,
        );
      } else {
        _leftEyeOpen = null;
        _rightEyeOpen = null;
      }
      _smileProb = _smoothMetric(_smileProb, mainFace.smilingProbability);
      _smoothedFaceRect = _smoothRect(
        _smoothedFaceRect,
        _normalizeFaceRect(
          mainFace.boundingBox,
          mainFace.imageWidth,
          mainFace.imageHeight,
        ),
      );

      if (canUseMainEyeProb && _isNativeFaceLikelyEyesClosed(mainFace)) {
        _eyeClosedStreak++;
      } else {
        _eyeClosedStreak = 0;
      }

      final visibleFaces = effectiveResults
          .where(_hasUsableNativeEyeData)
          .toList(growable: false);
      final closedFaces = visibleFaces
          .where(_isNativeFaceLikelyEyesClosed)
          .toList(growable: false);
      final closedFaceCount = closedFaces.length;
      _closedFaceRects = closedFaces
          .map(
            (face) => _normalizeFaceRect(
              face.boundingBox,
              face.imageWidth,
              face.imageHeight,
            ),
          )
          .whereType<Rect>()
          .toList(growable: false);

      if (closedFaceCount > 0) {
        _anyEyeClosedStreak++;
        _closedFaceCount = math.max(_closedFaceCount, closedFaceCount);
      } else if (visibleFaces.length >= 2 || _stablePersonCount <= 1) {
        _anyEyeClosedStreak = 0;
        _closedFaceCount = 0;
        _closedFaceRects = const [];
      } else {
        _anyEyeClosedStreak = math.max(0, _anyEyeClosedStreak - 1);
        if (_anyEyeClosedStreak == 0) {
          _closedFaceCount = 0;
          _closedFaceRects = const [];
        }
      }
      _anyFaceEyesClosed = _anyEyeClosedStreak >= 1;
    } else if (_stablePersonCount <= 1) {
      _anyFaceEyesClosed = false;
      _closedFaceCount = 0;
      _closedFaceRects = const [];
      _anyEyeClosedStreak = 0;
    }

    if (shouldLogSummary && DebugLogFlags.faceImageAnalysis) {
      debugPrint(
        '[FACE_IMAGE_ANALYSIS] use native results count=${effectiveResults.length} '
        'rawCount=$rawCount image=${_nativeFaceImageWidth}x$_nativeFaceImageHeight '
        'rotation=$_nativeFaceRotationDegrees '
        'front=$_nativeFaceIsFrontCamera frame=$_nativeFaceFrameNumber',
      );
      for (final face in effectiveResults.take(
        _portraitModeLabel == 'group' ? 6 : 1,
      )) {
        debugPrint(
          '[FACE_IMAGE_ANALYSIS] '
          'status=${face.confidenceStatusName} '
          'bbox=${face.boundingBox.left.toStringAsFixed(1)},'
          '${face.boundingBox.top.toStringAsFixed(1)},'
          '${face.boundingBox.right.toStringAsFixed(1)},'
          '${face.boundingBox.bottom.toStringAsFixed(1)} '
          'eyeL=${face.leftEyeOpenProbability?.toStringAsFixed(3) ?? 'null'} '
          'eyeR=${face.rightEyeOpenProbability?.toStringAsFixed(3) ?? 'null'} '
          'yaw=${face.headEulerAngleY?.toStringAsFixed(2) ?? 'null'} '
          'roll=${face.headEulerAngleZ?.toStringAsFixed(2) ?? 'null'} '
          'pitch=${face.headEulerAngleX?.toStringAsFixed(2) ?? 'null'}',
        );
      }
    }
  }

  // ─── 메인 처리 ────────────────────────────────────

  int _portraitDebugFrame = 0;
  PortraitAnalysisResult processResults(List<YOLOResult> results) {
    final rawPersons = results
        .where((r) => r.className.toLowerCase() == 'person')
        .toList();
    final persons = _dedupePersons(rawPersons);

    // 사람 안정화
    _personStreak = (persons.isNotEmpty ? _personStreak + 1 : _personStreak - 1)
        .clamp(0, 5);
    final stable = _personStreak >= 2;
    if (++_portraitDebugFrame % 30 == 1 && DebugLogFlags.yoloDebug) {
      debugPrint(
        '[YOLO_DEBUG][handler] frame#$_portraitDebugFrame results=${results.length} '
        'personsRaw=${rawPersons.length} persons=${persons.length} '
        'streak=$_personStreak stable=$stable',
      );
      if (DebugLogFlags.portraitMode) {
        debugPrint('[PORTRAIT_MODE] mode=$_portraitModeLabel frame=$_frameCount');
      }
    }

    if (!stable) {
      final c = _coachEngine.evaluate(const PortraitSceneState(personCount: 0));
      final stableCoaching = _stabilize(c);
      return PortraitAnalysisResult(
        coaching: stableCoaching,
        overlayData: OverlayData(
          closedFaceRects: const [],
          coaching: stableCoaching,
          shotType: ShotType.unknown,
        ),
        shotType: ShotType.unknown,
        personCount: 0,
        hasPersonStable: false,
      );
    }

    // 가장 큰 person
    if (persons.isEmpty) {
      final c = _coachEngine.evaluate(const PortraitSceneState(personCount: 0));
      final stableCoaching = _stabilize(c);
      return PortraitAnalysisResult(
        coaching: stableCoaching,
        overlayData: OverlayData(
          closedFaceRects: const [],
          coaching: stableCoaching,
          shotType: ShotType.unknown,
        ),
        shotType: ShotType.unknown,
        personCount: 0,
        hasPersonStable: false,
      );
    }

    final main = _selectMainPerson(persons);

    final areas =
        persons
            .map((p) => p.normalizedBox.width * p.normalizedBox.height)
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final mainArea = main.normalizedBox.width * main.normalizedBox.height;
    final secondArea = areas.length > 1 ? areas[1] : 0.0;
    double secondPersonSizeRatio = mainArea > 0 ? secondArea / mainArea : 0.0;

    double groupLeft = double.infinity;
    double groupTop = double.infinity;
    double groupRight = double.negativeInfinity;
    double groupBottom = double.negativeInfinity;
    for (final p in persons) {
      final b = p.normalizedBox;
      if (b.left < groupLeft) groupLeft = b.left;
      if (b.top < groupTop) groupTop = b.top;
      if (b.right > groupRight) groupRight = b.right;
      if (b.bottom > groupBottom) groupBottom = b.bottom;
    }
    final groupBboxRatio =
        groupLeft.isFinite &&
            groupTop.isFinite &&
            groupRight.isFinite &&
            groupBottom.isFinite
        ? (groupRight - groupLeft) * (groupBottom - groupTop)
        : mainArea;

    final groupShotCandidate =
        intent == PortraitIntent.group && persons.length >= 2;

    // ─── 다중 인물 메트릭 ─────────────────────────────
    // 그룹샷 안정화: 진입은 빠르게, 이탈은 느리게 (깜빡임 방지)
    if (groupShotCandidate) {
      _groupStreak = (_groupStreak + 1).clamp(0, _groupExitThreshold);
    } else {
      _groupStreak = (_groupStreak - 1).clamp(0, _groupExitThreshold);
    }
    if (!_isGroupShotStable && _groupStreak >= _groupEnterThreshold) {
      _isGroupShotStable = true;
    } else if (_isGroupShotStable && _groupStreak <= 0) {
      _isGroupShotStable = false;
    }
    final isGroupShot = _isGroupShotStable;
    // 인원수도 안정화: 그룹샷 모드일 때만 갱신
    _updateStablePersonCount(persons.length, groupShotCandidate);
    int groupCroppedCount = 0;
    int faceHiddenCount = 0;
    double spacingUnevenness = 0.0;
    double heightVariation = 0.0;

    if (intent == PortraitIntent.group && isGroupShot) {
      final metricPersons = _selectGroupMetricPersons(persons, mainArea);
      // 모든 인물의 바운딩박스가 프레임 가장자리에 걸리는지 검사
      const edgeMgn = 0.03;
      for (final p in metricPersons) {
        final b = p.normalizedBox;
        if (b.left < edgeMgn ||
            b.right > 1.0 - edgeMgn ||
            b.top < edgeMgn ||
            b.bottom > 1.0 - edgeMgn) {
          groupCroppedCount++;
        }
      }

      // ── 얼굴 가시성: 코 키포인트 없으면 얼굴이 안 보이는 것 ──
      // confidence가 낮은 감지(0.3 미만)는 키포인트가 부실할 수 있으므로 제외
      for (final p in metricPersons) {
        if (p.confidence < 0.3) continue;
        final noseKp = _kp(p, PoseKeypointIndex.nose);
        if (noseKp == null) faceHiddenCount++;
      }

      // ── 간격 균등성 (3명 이상) ────────────────────────────
      if (metricPersons.length >= 3) {
        final centerXs =
            metricPersons
                .map((p) => (p.normalizedBox.left + p.normalizedBox.right) / 2)
                .toList()
              ..sort();
        final gaps = <double>[];
        for (int i = 1; i < centerXs.length; i++) {
          gaps.add(centerXs[i] - centerXs[i - 1]);
        }
        if (gaps.isNotEmpty) {
          final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
          if (avgGap > 0.01) {
            spacingUnevenness =
                gaps.map((g) => (g - avgGap).abs()).reduce((a, b) => a + b) /
                gaps.length /
                avgGap;
          }
        }
      }

      // ── 키 차이 (bbox top Y 범위) ─────────────────────────
      final topYs = metricPersons.map((p) => p.normalizedBox.top).toList();
      double minTop = topYs.first, maxTop = topYs.first;
      for (final y in topYs) {
        if (y < minTop) minTop = y;
        if (y > maxTop) maxTop = y;
      }
      heightVariation = maxTop - minTop;
    }

    // 키포인트 추출
    final nose = _smoothedKp(main, PoseKeypointIndex.nose);
    final lEye = _smoothedKp(main, PoseKeypointIndex.leftEye);
    final rEye = _smoothedKp(main, PoseKeypointIndex.rightEye);
    final lShoulder = _smoothedKp(main, PoseKeypointIndex.leftShoulder);
    final rShoulder = _smoothedKp(main, PoseKeypointIndex.rightShoulder);
    final lElbow = _smoothedKp(main, PoseKeypointIndex.leftElbow, minConf: 0.3);
    final rElbow = _smoothedKp(
      main,
      PoseKeypointIndex.rightElbow,
      minConf: 0.3,
    );
    final lWrist = _smoothedKp(main, PoseKeypointIndex.leftWrist, minConf: 0.3);
    final rWrist = _smoothedKp(
      main,
      PoseKeypointIndex.rightWrist,
      minConf: 0.3,
    );
    final lHip = _smoothedKp(main, PoseKeypointIndex.leftHip, minConf: 0.3);
    final rHip = _smoothedKp(main, PoseKeypointIndex.rightHip, minConf: 0.3);
    final lKnee = _smoothedKp(main, PoseKeypointIndex.leftKnee, minConf: 0.05);
    final rKnee = _smoothedKp(main, PoseKeypointIndex.rightKnee, minConf: 0.05);
    final lAnkle = _smoothedKp(
      main,
      PoseKeypointIndex.leftAnkle,
      minConf: 0.05,
    );
    final rAnkle = _smoothedKp(
      main,
      PoseKeypointIndex.rightAnkle,
      minConf: 0.05,
    );

    // ─── 카메라 안정성 계산 ──────────────────────────────
    // ─── 비동기 분석 (조명 + 얼굴, captureFrame 공유) ─────
    // 어깨 각도
    final sConf = math.min(
      _conf(main, PoseKeypointIndex.leftShoulder),
      _conf(main, PoseKeypointIndex.rightShoulder),
    );
    final kneeConf = math.max(
      _conf(main, PoseKeypointIndex.leftKnee),
      _conf(main, PoseKeypointIndex.rightKnee),
    );
    final ankleConf = math.max(
      _conf(main, PoseKeypointIndex.leftAnkle),
      _conf(main, PoseKeypointIndex.rightAnkle),
    );
    double? shoulderAngle;
    if (lShoulder != null && rShoulder != null && sConf > 0.5) {
      shoulderAngle =
          math.atan2(rShoulder.dy - lShoulder.dy, rShoulder.dx - lShoulder.dx) *
          180 /
          math.pi;
    }

    // 팔 간격
    final eConf = math.max(
      _conf(main, PoseKeypointIndex.leftElbow),
      _conf(main, PoseKeypointIndex.rightElbow),
    );
    double? lArmGap, rArmGap;
    if (lElbow != null && lShoulder != null && lHip != null) {
      lArmGap = (lElbow.dx - (lShoulder.dx + lHip.dx) / 2).abs();
    }
    if (rElbow != null && rShoulder != null && rHip != null) {
      rArmGap = (rElbow.dx - (rShoulder.dx + rHip.dx) / 2).abs();
    }

    // 눈 중심
    final eyeConf = math.min(
      _conf(main, PoseKeypointIndex.leftEye),
      _conf(main, PoseKeypointIndex.rightEye),
    );
    Offset? eyeMid;
    if (lEye != null && rEye != null) {
      eyeMid = Offset((lEye.dx + rEye.dx) / 2, (lEye.dy + rEye.dy) / 2);
    }
    final shoulderWidth = (lShoulder != null && rShoulder != null)
        ? (rShoulder.dx - lShoulder.dx).abs()
        : null;
    final eyeWidth = (lEye != null && rEye != null)
        ? (rEye.dx - lEye.dx).abs()
        : null;

    _updateStability(
      current: {
        'nose': nose,
        'lEye': lEye,
        'rEye': rEye,
        'lShoulder': lShoulder,
        'rShoulder': rShoulder,
      },
      shoulderAngle: shoulderAngle,
      shoulderWidth: shoulderWidth,
      eyeWidth: eyeWidth,
    );

    // 샷 타입
    final all = <Offset?>[
      lEye,
      rEye,
      nose,
      lShoulder,
      rShoulder,
      lElbow,
      rElbow,
      lWrist,
      rWrist,
      lHip,
      rHip,
      lKnee,
      rKnee,
      lAnkle,
      rAnkle,
    ];
    double minY = 1, maxY = 0;
    for (final p in all) {
      if (p != null) {
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
    }
    var shot = ShotType.unknown;
    double headroom = 0, footSpace = 0;

    // 인물 bbox 비율 계산
    // 그룹샷: 모든 인물을 포함하는 전체 영역 비율 사용
    final mainBox = main.normalizedBox;
    final double bboxRatio;
    if (isGroupShot) {
      bboxRatio = groupBboxRatio;
    } else {
      bboxRatio = mainBox.width * mainBox.height;
    }
    // 그룹샷: 그룹 전체 중심 사용, 솔로: 메인 인물 중심
    final double centerX;
    if (isGroupShot) {
      double sumCx = 0;
      for (final p in persons) {
        sumCx += (p.normalizedBox.left + p.normalizedBox.right) / 2;
      }
      centerX = sumCx / persons.length;
    } else {
      centerX = (mainBox.left + mainBox.right) / 2;
    }

    final hasReliableAnkle =
        (lAnkle != null || rAnkle != null) && ankleConf >= 0.12 && maxY > 0.50;
    final hasKnee = lKnee != null || rKnee != null;
    final hasHip = lHip != null || rHip != null;
    final hasShoulder = lShoulder != null || rShoulder != null;

    if (isGroupShot) {
      shot = ShotType.groupShot;
      double groupMinTop = double.infinity;
      double groupMaxBottom = double.negativeInfinity;
      for (final p in persons) {
        final b = p.normalizedBox;
        if (b.top < groupMinTop) groupMinTop = b.top;
        if (b.bottom > groupMaxBottom) groupMaxBottom = b.bottom;
      }
      if (groupMinTop.isFinite) {
        headroom = groupMinTop;
      }
      if (groupMaxBottom.isFinite) {
        footSpace = 1.0 - groupMaxBottom;
      }
    } else if (maxY > minY) {
      final h = maxY - minY;

      if (hasReliableAnkle) {
        shot = ShotType.fullBody;
      } else if (hasKnee) {
        shot = ShotType.kneeShot;
      } else if (hasHip && !hasKnee && h > 0.45) {
        shot = ShotType.waistShot;
      } else if (hasShoulder && !hasHip && h > 0.3) {
        shot = ShotType.headShot;
      } else if (hasShoulder && hasHip) {
        shot = ShotType.upperBody;
      } else if (!hasShoulder && h < 0.3) {
        shot = ShotType.extremeCloseUp;
      } else if (h > 0.25) {
        shot = ShotType.closeUp;
      } else {
        shot = ShotType.extremeCloseUp;
      }
      headroom = minY;
      footSpace = 1.0 - maxY;
    }

    // 관절 크로핑 (샷 타입에 따라 체크 관절 구분)
    // - 손목/팔꿈치: upperBody 이상에서만 (upperBody, kneeShot, fullBody)
    // - 무릎: kneeShot/fullBody 에서만
    // - 발목: fullBody 에서만
    final croppedList = <String>[];
    if (shot == ShotType.upperBody ||
        shot == ShotType.kneeShot ||
        shot == ShotType.fullBody) {
      if (_isAtEdge(lWrist) || _isAtEdge(rWrist)) croppedList.add('wrist');
      if (_isAtEdge(lElbow) || _isAtEdge(rElbow)) croppedList.add('elbow');
    }
    if ((shot == ShotType.kneeShot || shot == ShotType.fullBody) &&
        kneeConf >= 0.15) {
      if (_isAtEdge(lKnee) || _isAtEdge(rKnee)) croppedList.add('knee');
    }
    if (shot == ShotType.fullBody && ankleConf >= 0.15) {
      if (_isAtEdge(lAnkle) || _isAtEdge(rAnkle)) croppedList.add('ankle');
    }

    // SceneState
    final rawFaceRect = _estimateFaceRect(
      personBox: Rect.fromLTRB(
        main.normalizedBox.left,
        main.normalizedBox.top,
        main.normalizedBox.right,
        main.normalizedBox.bottom,
      ),
      nose: nose,
      leftEye: lEye,
      rightEye: rEye,
      leftShoulder: lShoulder,
      rightShoulder: rShoulder,
    );
    _smoothedFaceRect = _smoothRect(_smoothedFaceRect, rawFaceRect);
    final faceRect = _smoothedFaceRect ?? rawFaceRect;

    // ─── 발 간격 비율 (어깨 너비 대비) ──────────────────────
    double? ankleSpacing;
    if (lAnkle != null &&
        rAnkle != null &&
        lShoulder != null &&
        rShoulder != null &&
        ankleConf >= 0.15 &&
        sConf >= 0.35) {
      final shoulderW = (rShoulder.dx - lShoulder.dx).abs();
      if (shoulderW > 0.02) {
        ankleSpacing = (rAnkle.dx - lAnkle.dx).abs() / shoulderW;
      }
    }

    // ─── 프레임 하단에 가장 가까운 관절 감지 ────────────────
    // 관절에서 자르면 어색 → 관절이 화면 하단 12% 안에 있으면 경고
    String? bottomJoint;
    double? bottomJointY;
    const bottomZone = 0.85;
    final jointCandidates = <String, double?>{
      'knee': kneeConf >= 0.15 ? _maxY(lKnee, rKnee) : null,
      'ankle': ankleConf >= 0.15 ? _maxY(lAnkle, rAnkle) : null,
      'wrist': _maxY(lWrist, rWrist),
      'hip': _maxY(lHip, rHip),
    };
    for (final entry in jointCandidates.entries) {
      final y = entry.value;
      if (y != null && y > bottomZone) {
        if (bottomJointY == null || y > bottomJointY) {
          bottomJoint = entry.key;
          bottomJointY = y;
        }
      }
    }

    final state = PortraitSceneState(
      personCount: _stablePersonCount,
      shotType: shot,
      intent: intent,
      faceYaw: _faceYaw,
      facePitch: _facePitch,
      faceRoll: _faceRoll,
      smileProbability: _smileProb,
      leftEyeOpenProb: _leftEyeOpen,
      rightEyeOpenProb: _rightEyeOpen,
      faceCenterX: faceRect.center.dx,
      faceCenterY: faceRect.center.dy,
      faceBoxRatio: faceRect.width * faceRect.height,
      shoulderAngleDeg: shoulderAngle,
      leftArmBodyGap: lArmGap,
      rightArmBodyGap: rArmGap,
      eyeMidpoint: eyeMid,
      croppedJoints: croppedList,
      headroomRatio: headroom,
      footSpaceRatio: footSpace,
      personCenterX: centerX,
      personBboxRatio: bboxRatio,
      shoulderConfidence: sConf,
      elbowConfidence: eConf,
      eyeConfidence: eyeConf,
      kneeConfidence: kneeConf,
      ankleConfidence: ankleConf,
      isGroupShot: isGroupShot,
      secondPersonSizeRatio: secondPersonSizeRatio,
      groupCroppedCount: groupCroppedCount,
      anyFaceEyesClosed: _anyFaceEyesClosed,
      closedFaceCount: _closedFaceCount,
      lightingCondition: lastLighting,
      lightingConfidence: lastLightingConf,
      faceQualityScores: _faceQualityScores,
      visibleKeypointCount: all.where((p) => p != null).length,
      hasNose: nose != null,
      hasEyes: lEye != null && rEye != null,
      hasShoulders: lShoulder != null && rShoulder != null,
      leftWristPosition: lWrist,
      rightWristPosition: rWrist,
      leftAnklePosition: lAnkle,
      rightAnklePosition: rAnkle,
      leftHipPosition: lHip,
      rightHipPosition: rHip,
      leftKneePosition: lKnee,
      rightKneePosition: rKnee,
      ankleSpacingRatio: ankleSpacing,
      bottomJoint: bottomJoint,
      bottomJointY: bottomJointY,
      lowerBodyTouchesBottom:
          mainBox.bottom > 0.97 &&
          !hasReliableAnkle &&
          (shot == ShotType.fullBody || shot == ShotType.kneeShot),
      isFrontCamera: isFrontCamera,
      cameraStability: _cameraStability,
      eyeClosedConfirmed: _eyeClosedStreak >= _eyeConfirmFrames,
      faceHiddenCount: faceHiddenCount,
      spacingUnevenness: spacingUnevenness,
      heightVariation: heightVariation,
    );

    // ─── 그룹샷: 모든 얼굴 눈 감김 비동기 검사 ───────────────
    // 코칭 평가 전에 트리거하여 다음 프레임부터 바로 반영
    _frameCount++;

    // 디버그: face quality 스케줄 체크 로그 (디버그 플래그가 true일 때만)
    if (_faceQualityDebug && DebugLogFlags.portraitMode) {
      debugPrint(
        '[FaceQuality] SCHEDULE check frame=$_frameCount mod=${_frameCount % _faceQualityEveryN}',
      );
    }

    // 항상(디버깅용) 또는 그룹샷일 때 captureFrame을 통해 얼굴 분석 스케줄
    if (captureFrameCallback != null) {
      _scheduleAnalysis(
        captureFrameCallback!,
        main,
        nose,
        lEye,
        rEye,
        lShoulder,
        rShoulder,
      );
    }

    final coaching = _stabilize(_coachEngine.evaluate(state));

    final overlay = OverlayData(
      closedFaceRects: _closedFaceRects,
      leftEye: lEye,
      rightEye: rEye,
      nose: nose,
      leftShoulder: lShoulder,
      rightShoulder: rShoulder,
      leftElbow: lElbow,
      rightElbow: rElbow,
      leftWrist: lWrist,
      rightWrist: rWrist,
      leftHip: lHip,
      rightHip: rHip,
      leftKnee: lKnee,
      rightKnee: rKnee,
      leftAnkle: lAnkle,
      rightAnkle: rAnkle,
      coaching: coaching,
      shotType: shot,
      eyeConfidence: eyeConf,
      shoulderConfidence: sConf,
      faceGuideRect: faceRect,
      bodyGuideRect: _smoothedBodyRect = _smoothRect(
        _smoothedBodyRect,
        Rect.fromLTRB(
          main.normalizedBox.left.clamp(0.0, 1.0).toDouble(),
          main.normalizedBox.top.clamp(0.0, 1.0).toDouble(),
          main.normalizedBox.right.clamp(0.0, 1.0).toDouble(),
          main.normalizedBox.bottom.clamp(0.0, 1.0).toDouble(),
        ),
        alpha: _bodyRectAlpha,
      ),
      targetEyeLineY: _targetEyeLineY(shot),
      targetHeadroomTop: _targetHeadroomTop(shot),
      groupPersonCount: _stablePersonCount,
      groupFaceHiddenCount: faceHiddenCount,
      groupClosedEyeCount: _closedFaceCount,
    );

    return PortraitAnalysisResult(
      coaching: coaching,
      overlayData: overlay,
      shotType: shot,
      personCount: _stablePersonCount,
      hasPersonStable: true,
    );
  }

  // ─── 비동기 분석 스케줄러 (captureFrame 공유) ──────────

  void _scheduleAnalysis(
    Future<Uint8List?> Function() captureFrame,
    YOLOResult mainPerson,
    Offset? nose,
    Offset? lEye,
    Offset? rEye,
    Offset? lShoulder,
    Offset? rShoulder,
  ) {
    if (_faceAnalysisSource == FaceAnalysisSource.imageAnalysis) {
      return;
    }

    // 결정: 어떤 분석이 필요한가
    // 조명(Lighting)은 네이티브 메트릭(updateNativeMetrics)을 통해 처리합니다.
    // captureFrame 기반 조명 분석은 프레임 드랍을 유발하므로 사용하지 않습니다.
    final faceArea =
        (mainPerson.normalizedBox.width * mainPerson.normalizedBox.height)
            .clamp(0.0, 1.0);

    // 얼굴 분석(캡처 필요): 주기적으로만 실행
    final needFace =
        _enableFaceAnalysis &&
        !_isAnalyzing &&
        !_isFaceAnalyzing &&
        _enableBitmapCaptureForFace &&
        (_frameCount - _lastFaceAnalysisFrame >= _faceEveryN) &&
        faceArea >= 0.005; // 작게 잡힌 얼굴은 스킵

    // FaceQuality는 절대 별도의 capture를 트리거하지 않습니다.
    // FaceQuality는 ML Kit에서 반환된 `faces` 결과가 있을 때만
    // `_analyzeFace(..., analyzeQuality: true)` 내부에서 실행됩니다.
    var needFaceQuality =
        _enableFaceQuality &&
        _faceQualityClassifier.isLoaded &&
        !_isFaceQualityAnalyzing &&
        (_frameCount - _lastFaceQualityFrame >= _faceQualityEveryN);

    // FaceQuality는 capture 없이 별도 트리거를 하지 않도록, 필요시에도
    // 반드시 face 캡처(needFace)가 true일 때만 함께 실행되도록 제한합니다.
    if (!needFace) needFaceQuality = false;

    // captureFrame은 얼굴 분석(needFace)이 필요한 경우에만 호출
    if (!needFace) return;

    if (DebugLogFlags.portraitMode) {
      debugPrint(
        '[PORTRAIT_MODE] face path request source=$_faceAnalysisSource '
        'mode=$_portraitModeLabel frame=$_frameCount',
      );
    }

    _isAnalyzing = true;

    unawaited(() async {
      try {
        final reasons = <String>[];
        if (needFace) reasons.add('face');
        if (needFaceQuality) reasons.add('faceQuality');

        if (DebugLogFlags.portraitMode) {
          debugPrint(
            '[PORTRAIT_MODE] capture run reason=${reasons.join('+')} '
            'mode=$_portraitModeLabel frame=$_frameCount',
          );
        }

        // captureFrame 호출(타임아웃으로 UI 블로킹 완화)
        final bytes = await captureFrame().timeout(
          const Duration(milliseconds: 800),
          onTimeout: () => null,
        );
        if (bytes == null || bytes.isEmpty) return;

        // 짧게 이벤트 루프 양보
        await Future<void>.delayed(const Duration(milliseconds: 1));

        // 얼굴 분석(ML Kit) — FaceQuality는 여기서만 실행될 수 있음
        _isFaceAnalyzing = true;
        _lastFaceAnalysisFrame = _frameCount;
        final faceStart = DateTime.now().millisecondsSinceEpoch;
        try {
          if (needFaceQuality) {
            _lastFaceQualityFrame = _frameCount;
            _isFaceQualityAnalyzing = true;
          }

          await _analyzeFace(bytes, analyzeQuality: needFaceQuality);

          final faceElapsed = DateTime.now().millisecondsSinceEpoch - faceStart;
          if (DebugLogFlags.portraitMode) {
            debugPrint(
              '[PORTRAIT_MODE] face run frame=$_frameCount elapsedMs=$faceElapsed',
            );
          }
        } finally {
          _isFaceQualityAnalyzing = false;
          _isFaceAnalyzing = false;
        }
      } catch (e) {
        if (DebugLogFlags.portraitMode) {
          debugPrint('[PORTRAIT_MODE] analysis error=$e');
        }
      } finally {
        _isAnalyzing = false;
      }
    }());
  }

  Future<void> _analyzeLight(
    Uint8List bytes,
    YOLOResult mainPerson,
    Offset? nose,
    Offset? lEye,
    Offset? rEye,
    Offset? lShoulder,
    Offset? rShoulder,
  ) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      final baked = img.bakeOrientation(decoded);

      final faceRect = _estimateFaceRect(
        personBox: Rect.fromLTRB(
          mainPerson.normalizedBox.left,
          mainPerson.normalizedBox.top,
          mainPerson.normalizedBox.right,
          mainPerson.normalizedBox.bottom,
        ),
        nose: nose,
        leftEye: lEye,
        rightEye: rEye,
        leftShoulder: lShoulder,
        rightShoulder: rShoulder,
      );

      // 최적화: 전체 이미지를 luminance 변환하지 않고
      // 얼굴 영역만 크롭 → 224x224 리사이즈 → 작은 이미지에서 luminance
      final fx = (faceRect.left * baked.width).round().clamp(
        0,
        baked.width - 1,
      );
      final fy = (faceRect.top * baked.height).round().clamp(
        0,
        baked.height - 1,
      );
      final fw = (faceRect.width * baked.width).round().clamp(
        1,
        baked.width - fx,
      );
      final fh = (faceRect.height * baked.height).round().clamp(
        1,
        baked.height - fy,
      );

      final faceCrop = img.copyCrop(baked, x: fx, y: fy, width: fw, height: fh);
      final resized = img.copyResize(faceCrop, width: 224, height: 224);

      // 224x224 작은 이미지에서만 luminance → 5만 픽셀 (기존 400만에서 80배 감소)
      final lum = _toLuminance(resized);
      final crop = _lightingClassifier.prepareFaceCrop(
        imageBytes: lum,
        imageWidth: 224,
        imageHeight: 224,
        faceLeft: 0.0,
        faceTop: 0.0,
        faceWidth: 1.0,
        faceHeight: 1.0,
      );
      if (crop == null) return;

      final r = _lightingClassifier.classify(crop);
      final cond = r.confidence >= _lightingMinConf
          ? r.condition
          : LightingCondition.unknown;
      lastLighting = cond;
      lastLightingConf = cond == LightingCondition.unknown ? 0.0 : r.confidence;
    } catch (e) {
      if (DebugLogFlags.portraitMode) {
        debugPrint('[PORTRAIT_MODE] light error=$e');
      }
    }
  }

  // Dispatcher: routes to configured face analysis source implementation.
  Future<void> _analyzeFace(
    Uint8List bytes, {
    bool analyzeQuality = false,
  }) async {
    if (DebugLogFlags.portraitMode) {
      debugPrint(
        '[PORTRAIT_MODE] face dispatcher source=$_faceAnalysisSource '
        'mode=$_portraitModeLabel frame=$_frameCount',
      );
    }
    switch (_faceAnalysisSource) {
      case FaceAnalysisSource.previewCapture:
        return _analyzeFaceFromPreviewCapture(bytes, analyzeQuality: analyzeQuality);
      case FaceAnalysisSource.imageAnalysis:
        return _analyzeFaceFromImageAnalysis(bytes, analyzeQuality: analyzeQuality);
    }
  }

  // Existing preview-capture-based face analysis (original path).
  // Kept as fallback and renamed for clarity.
  Future<void> _analyzeFaceFromPreviewCapture(
    Uint8List bytes, {
    bool analyzeQuality = false,
  }) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    if (DebugLogFlags.portraitMode) {
      debugPrint(
        '[PORTRAIT_MODE] face preview start mode=$_portraitModeLabel '
        'frame=$_frameCount',
      );
    }
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      final tempFile = File('${Directory.systemTemp.path}/pozy_face.jpg');
      await tempFile.writeAsBytes(bytes);
      final input = InputImage.fromFilePath(tempFile.path);
      final faces = await _faceDetector.processImage(input);

      if (faces.isNotEmpty) {
        if (analyzeQuality) {
          // 얼굴 영역을 crop -> 112x112 RGB 바이트로 변환
          final crops = <Uint8List>[];
          final toProcess = math.min(_maxFaceQualityFaces, faces.length);
          for (int i = 0; i < toProcess; i++) {
            final f = faces[i];
            final box = f.boundingBox;

            // clamp bbox to image bounds
            int x = box.left.round().clamp(0, decoded.width - 1);
            int y = box.top.round().clamp(0, decoded.height - 1);
            int w = box.width.round();
            int h = box.height.round();
            if (w <= 0) w = 1;
            if (h <= 0) h = 1;
            if (x + w > decoded.width) w = decoded.width - x;
            if (y + h > decoded.height) h = decoded.height - y;

            // crop and resize
            final cropImg = img.copyCrop(
              decoded,
              x: x,
              y: y,
              width: w,
              height: h,
            );
            final resized = img.copyResize(cropImg, width: 112, height: 112);

            // extract RGB bytes
            final rgb = Uint8List(112 * 112 * 3);
            int idx = 0;
            for (int ty = 0; ty < 112; ty++) {
              for (int tx = 0; tx < 112; tx++) {
                final p = resized.getPixel(tx, ty);
                final r = p.r.toInt();
                final g = p.g.toInt();
                final b = p.b.toInt();
                rgb[idx++] = r;
                rgb[idx++] = g;
                rgb[idx++] = b;
              }
            }
            crops.add(rgb);
            // crop debug logs removed to reduce noise; keep only final RUN log
          }

          // 실제 crop 데이터를 넘겨 분류 실행 (더미 분류기는 bytes 기반으로 동작)
          _faceQualityScores = _faceQualityClassifier.classifyCrops(
            crops,
            112,
            112,
          );
        }
        // ─── 메인 얼굴: yaw/pitch/roll/smile만 보조 업데이트 ────
        // 눈 데이터는 네이티브 메트릭 스트림이 primary source
        // (여기서 덮어쓰면 비대칭 스무딩이 깨지고 값이 점프함)
        final mainFace = faces.length == 1
            ? faces.first
            : faces.reduce(
                (a, b) =>
                    (a.boundingBox.width * a.boundingBox.height) >=
                        (b.boundingBox.width * b.boundingBox.height)
                    ? a
                    : b,
              );

        _faceYaw = _smoothMetric(_faceYaw, mainFace.headEulerAngleY);
        _facePitch = _smoothMetric(_facePitch, mainFace.headEulerAngleX);
        _faceRoll = _smoothMetric(_faceRoll, mainFace.headEulerAngleZ);
        _smileProb = _smoothMetric(_smileProb, mainFace.smilingProbability);

        // ─── 모든 얼굴: 눈 감김 검사 (그룹샷 + 싱글 보조) ────
        final visibleFaces = faces.where(_hasUsableEyeData).toList();
        final closedFaces = visibleFaces
            .where(_isFaceLikelyEyesClosed)
            .toList();
        final closedFaceCount = closedFaces.length;
        _closedFaceRects = closedFaces
            .map(
              (face) => _normalizeFaceRect(
                face.boundingBox,
                decoded.width,
                decoded.height,
              ),
            )
            .whereType<Rect>()
            .toList(growable: false);

        if (closedFaceCount > 0) {
          _anyEyeClosedStreak++;
          _closedFaceCount = math.max(_closedFaceCount, closedFaceCount);
        } else if (visibleFaces.length >= 2 || _stablePersonCount <= 1) {
          _anyEyeClosedStreak = 0;
          _closedFaceCount = 0;
          _closedFaceRects = const [];
        } else {
          // 다중 인물에서는 한 프레임 얼굴 누락이 잦아서 즉시 초기화하지 않습니다.
          _anyEyeClosedStreak = math.max(0, _anyEyeClosedStreak - 1);
          if (_anyEyeClosedStreak == 0) {
            _closedFaceCount = 0;
            _closedFaceRects = const [];
          }
        }
        _anyFaceEyesClosed = _anyEyeClosedStreak >= 1;
      } else if (_stablePersonCount <= 1) {
        _anyFaceEyesClosed = false;
        _closedFaceCount = 0;
        _closedFaceRects = const [];
        _anyEyeClosedStreak = 0;
      }
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAt;
      if (DebugLogFlags.portraitMode) {
        debugPrint(
          '[PORTRAIT_MODE] face preview end faces=${faces.length} '
          'elapsedMs=$elapsedMs',
        );
      }
    } catch (e) {
      if (DebugLogFlags.portraitMode) {
        debugPrint('[PORTRAIT_MODE] face error=$e');
      }
    }
  }

  // TODO: ImageAnalysis-based face analysis stub. Implement in next step.
  Future<void> _analyzeFaceFromImageAnalysis(
    Uint8List bytes, {
    bool analyzeQuality = false,
  }) async {
    if (DebugLogFlags.faceImageAnalysis) {
      debugPrint(
        '[FACE_IMAGE_ANALYSIS] stub called '
        'mode=$_portraitModeLabel frame=$_frameCount',
      );
    }
    if (DebugLogFlags.nativeFace) {
      debugPrint(
        '[NATIVE_FACE] count=${_latestNativeFaceResults.length} '
        'image=${_nativeFaceImageWidth}x$_nativeFaceImageHeight '
        'rotation=$_nativeFaceRotationDegrees '
        'source=imageAnalysis',
      );
    }
    return;
  }

  // ─── 키포인트 추출 ────────────────────────────────

  Offset? _kp(YOLOResult r, int idx, {double minConf = 0.01}) {
    final dynamic kps = r.keypoints;
    final dynamic confs = r.keypointConfidences;
    if (kps == null || confs == null) return null;

    final cList = confs is List ? confs : <dynamic>[];
    if (idx >= cList.length) return null;
    if ((cList[idx] as num).toDouble() < minConf) return null;

    final kList = kps is List ? kps : <dynamic>[];
    if (kList.isEmpty) return null;

    double x, y;
    try {
      final first = kList[0];
      if (first is num) {
        final xi = idx * 2, yi = idx * 2 + 1;
        if (yi >= kList.length) return null;
        x = (kList[xi] as num).toDouble();
        y = (kList[yi] as num).toDouble();
      } else if (first is Offset) {
        if (idx >= kList.length) return null;
        x = (kList[idx] as Offset).dx;
        y = (kList[idx] as Offset).dy;
      } else if (first is List) {
        if (idx >= kList.length) return null;
        final pt = kList[idx] as List;
        x = (pt[0] as num).toDouble();
        y = (pt[1] as num).toDouble();
      } else {
        if (idx >= kList.length) return null;
        final pt = kList[idx];
        x = (pt.x as num).toDouble();
        y = (pt.y as num).toDouble();
      }
    } catch (_) {
      return null;
    }

    // 픽셀→정규화
    if (x > 1.0 || y > 1.0) {
      final nb = r.normalizedBox;
      final bb = r.boundingBox;
      final w = nb.right > 0 ? bb.right / nb.right : 480.0;
      final h = nb.bottom > 0 ? bb.bottom / nb.bottom : 640.0;
      x = x / w;
      y = y / h;
    }

    final nx = x.clamp(0.0, 1.0);
    final ny = y.clamp(0.0, 1.0);
    return isFrontCamera ? Offset(1.0 - nx, ny) : Offset(nx, ny);
  }

  Offset? _smoothedKp(YOLOResult r, int idx, {double minConf = 0.01}) {
    final next = _kp(r, idx, minConf: minConf);

    if (next == null) {
      // 신뢰도 부족 → 캐시 제거하고 null 반환
      // (스테일 위치를 그대로 표시하면 화면 모서리로 몰리는 버그 발생)
      _smoothedPosePoints.remove(idx);
      return null;
    }

    final previous = _smoothedPosePoints[idx];
    if (previous == null) {
      _smoothedPosePoints[idx] = next;
      return next;
    }

    final smoothed = Offset(
      previous.dx + (next.dx - previous.dx) * _posePointAlpha,
      previous.dy + (next.dy - previous.dy) * _posePointAlpha,
    );
    _smoothedPosePoints[idx] = smoothed;
    return smoothed;
  }

  double _conf(YOLOResult r, int idx) {
    final dynamic confs = r.keypointConfidences;
    if (confs == null) return 0.0;
    final list = confs is List ? confs : <dynamic>[];
    if (idx >= list.length) return 0.0;
    return (list[idx] as num).toDouble();
  }

  List<YOLOResult> _dedupePersons(List<YOLOResult> persons) {
    if (persons.length <= 1) return persons;

    final minConfidence = intent == PortraitIntent.group ? 0.06 : 0.12;
    final sorted = [...persons]
      ..sort((a, b) {
        final aScore =
            a.confidence * a.normalizedBox.width * a.normalizedBox.height;
        final bScore =
            b.confidence * b.normalizedBox.width * b.normalizedBox.height;
        return bScore.compareTo(aScore);
      });

    final kept = <YOLOResult>[];
    for (final person in sorted) {
      if (person.confidence < minConfidence) continue;

      final isDuplicate = kept.any(
        (other) => _looksLikeSamePerson(other, person),
      );
      if (!isDuplicate) {
        kept.add(person);
      }
    }

    return kept.isEmpty ? [sorted.first] : kept;
  }

  bool _looksLikeSamePerson(YOLOResult a, YOLOResult b) {
    final boxA = a.normalizedBox;
    final boxB = b.normalizedBox;

    final intersectionArea = _intersectionArea(boxA, boxB);
    final areaA = boxA.width * boxA.height;
    final areaB = boxB.width * boxB.height;
    final minArea = math.min(areaA, areaB);
    final maxArea = math.max(areaA, areaB);
    final overlapOnSmaller = minArea <= 0 ? 0.0 : intersectionArea / minArea;
    final areaRatio = maxArea <= 0 ? 0.0 : minArea / maxArea;
    final centerDistance = (boxA.center - boxB.center).distance;
    final iou = _intersectionOverUnion(boxA, boxB);

    if (isFrontCamera) {
      if (intent == PortraitIntent.group) {
        return iou > 0.68 ||
            overlapOnSmaller > 0.92 ||
            (centerDistance < 0.035 && areaRatio > 0.82);
      }
      return iou > 0.52 ||
          overlapOnSmaller > 0.82 ||
          (centerDistance < 0.05 && areaRatio > 0.72);
    }

    if (intent == PortraitIntent.group) {
      return iou > 0.70 ||
          overlapOnSmaller > 0.90 ||
          (centerDistance < 0.04 && areaRatio > 0.78);
    }

    return iou > 0.55 ||
        overlapOnSmaller > 0.75 ||
        (centerDistance < 0.06 && areaRatio > 0.55);
  }

  double _intersectionArea(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;
    return intersection.width * intersection.height;
  }

  bool _hasUsableEyeData(Face face) {
    return face.leftEyeOpenProbability != null ||
        face.rightEyeOpenProbability != null;
  }

  bool _hasUsableNativeEyeData(NativeFaceResult face) {
    return face.confidenceStatus == NativeFaceConfidenceStatus.usable &&
        face.leftEyeOpenProbability != null &&
        face.rightEyeOpenProbability != null &&
        face.headEulerAngleY != null &&
        face.headEulerAngleX != null &&
        face.headEulerAngleZ != null;
  }

  bool _isFaceLikelyEyesClosed(Face face) {
    final l = face.leftEyeOpenProbability;
    final r = face.rightEyeOpenProbability;

    if (l != null && r != null) {
      final avg = (l + r) / 2;
      return (l < 0.38 && r < 0.38) || (avg < 0.32 && (l < 0.45 || r < 0.45));
    }

    if (l != null) return l < 0.18;
    if (r != null) return r < 0.18;
    return false;
  }

  bool _isNativeFaceLikelyEyesClosed(NativeFaceResult face) {
    final l = face.leftEyeOpenProbability;
    final r = face.rightEyeOpenProbability;
    if (l == null || r == null) return false;
    return _isNativeFaceFrontalForEyes(face) && l < 0.35 && r < 0.35;
  }

  bool _isNativeFaceFrontalForEyes(NativeFaceResult face) {
    if (face.confidenceStatus != NativeFaceConfidenceStatus.usable) {
      return false;
    }
    final yaw = face.headEulerAngleY?.abs();
    final pitch = face.headEulerAngleX?.abs();
    final roll = face.headEulerAngleZ?.abs();

    if (yaw == null || pitch == null || roll == null) return false;
    if (yaw != null && yaw > 25) return false;
    if (pitch != null && pitch > 20) return false;
    if (roll != null && roll > 25) return false;
    return true;
  }

  NativeFaceResult _selectPrimaryNativeFace(List<NativeFaceResult> faces) {
    return faces.reduce((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaA >= areaB ? a : b;
    });
  }

  List<NativeFaceResult> _selectNativeFacesForIntent(
    List<NativeFaceResult> faces,
  ) {
    if (faces.isEmpty) return const [];

    final annotated = faces.map(_withDerivedNativeStatus).toList();
    final sorted = annotated..sort((a, b) {
        final areaA = a.boundingBox.width * a.boundingBox.height;
        final areaB = b.boundingBox.width * b.boundingBox.height;
        return areaB.compareTo(areaA);
      });

    final limit = intent == PortraitIntent.group ? _maxGroupNativeFaces : 1;
    return List<NativeFaceResult>.unmodifiable(sorted.take(limit));
  }

  NativeFaceResult _withDerivedNativeStatus(NativeFaceResult face) {
    final bboxStatus = NativeFaceResult._inferStatus(
      face.boundingBox,
      face.imageWidth,
      face.imageHeight,
    );
    if (bboxStatus != NativeFaceConfidenceStatus.usable) {
      return face.copyWith(confidenceStatus: bboxStatus);
    }

    final hasEyeProb =
        face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null;
    final hasPoseAngles = face.headEulerAngleY != null &&
        face.headEulerAngleX != null &&
        face.headEulerAngleZ != null;
    if (!hasEyeProb || !hasPoseAngles) {
      return face.copyWith(
        confidenceStatus: NativeFaceConfidenceStatus.uncertain,
      );
    }
    return face.copyWith(confidenceStatus: NativeFaceConfidenceStatus.usable);
  }

  Rect? _normalizeFaceRect(Rect rect, int imageWidth, int imageHeight) {
    if (imageWidth <= 0 || imageHeight <= 0) return null;

    final left = (rect.left / imageWidth).clamp(0.0, 1.0);
    final top = (rect.top / imageHeight).clamp(0.0, 1.0);
    final right = (rect.right / imageWidth).clamp(0.0, 1.0);
    final bottom = (rect.bottom / imageHeight).clamp(0.0, 1.0);
    if (right <= left || bottom <= top) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  bool _shouldTreatAsGroupShot(
    List<YOLOResult> persons,
    double secondPersonSizeRatio,
    double thirdPersonSizeRatio,
    double groupBboxRatio,
    double avgPersonArea,
    int significantPersonCount,
  ) {
    if (persons.length < 2) return false;

    if (persons.length >= 3) {
      final hasEnoughSignificantPeople = significantPersonCount >= 3;
      final sizeGate = persons.length >= 4
          ? (avgPersonArea >= 0.018 || thirdPersonSizeRatio >= 0.14)
          : (avgPersonArea >= 0.02 || thirdPersonSizeRatio >= 0.18);
      return hasEnoughSignificantPeople && groupBboxRatio >= 0.22 && sizeGate;
    }

    return groupBboxRatio >= 0.18 && secondPersonSizeRatio >= 0.28;
  }

  // ─── 얼굴 영역 추정 ───────────────────────────────

  Rect _estimateFaceRect({
    required Rect personBox,
    Offset? nose,
    Offset? leftEye,
    Offset? rightEye,
    Offset? leftShoulder,
    Offset? rightShoulder,
  }) {
    final eyeMid = (leftEye != null && rightEye != null)
        ? Offset((leftEye.dx + rightEye.dx) / 2, (leftEye.dy + rightEye.dy) / 2)
        : null;
    final center = eyeMid ?? nose ?? personBox.center;

    double w;
    if (leftShoulder != null && rightShoulder != null) {
      w = (rightShoulder.dx - leftShoulder.dx).abs() * 0.75;
    } else if (leftEye != null && rightEye != null) {
      w = (rightEye.dx - leftEye.dx).abs() * 2.4;
    } else {
      w = personBox.width * 0.38;
    }
    w = w.clamp(0.12, 0.45);
    final h = (w * 1.18).clamp(0.14, 0.52);
    final l = (center.dx - w / 2).clamp(0.0, 1.0);
    final t = (center.dy - h * 0.45).clamp(0.0, 1.0);
    return Rect.fromLTWH(l, t, w.clamp(0.05, 1.0 - l), h.clamp(0.05, 1.0 - t));
  }

  // ─── 유틸리티 ─────────────────────────────────────

  YOLOResult _selectMainPerson(List<YOLOResult> persons) {
    if (persons.length == 1) {
      _trackedMainBox = persons.first.normalizedBox;
      return persons.first;
    }

    final previousBox = _trackedMainBox;
    final targetCenter = previousBox?.center ?? const Offset(0.5, 0.45);
    YOLOResult selected = persons.first;
    double bestScore = double.negativeInfinity;

    for (final person in persons) {
      final box = person.normalizedBox;
      final area = box.width * box.height;
      final overlap = previousBox == null
          ? 0.0
          : _intersectionOverUnion(previousBox, box);
      final centerDistance = (box.center - targetCenter).distance;
      final score = area * 1.2 + overlap * 1.6 - centerDistance * 0.35;

      if (score > bestScore) {
        bestScore = score;
        selected = person;
      }
    }

    _trackedMainBox = selected.normalizedBox;
    return selected;
  }

  double _intersectionOverUnion(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0.0;

    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) return 0.0;
    return intersectionArea / unionArea;
  }

  double? _smoothMetric(double? previous, double? next) {
    if (next == null || next.isNaN) return previous;
    if (previous == null || previous.isNaN) return next;
    return previous + (next - previous) * _faceMetricAlpha;
  }

  Rect? _smoothRect(Rect? previous, Rect? next, {double? alpha}) {
    if (next == null) return previous;
    if (previous == null) return next;

    final a = alpha ?? _faceRectAlpha;
    return Rect.fromLTRB(
      previous.left + (next.left - previous.left) * a,
      previous.top + (next.top - previous.top) * a,
      previous.right + (next.right - previous.right) * a,
      previous.bottom + (next.bottom - previous.bottom) * a,
    );
  }

  double? _targetEyeLineY(ShotType shot) {
    switch (shot) {
      case ShotType.extremeCloseUp:
        return 0.38;
      case ShotType.closeUp:
        return 0.35;
      case ShotType.headShot:
        return 0.35;
      case ShotType.upperBody:
        return 0.33;
      case ShotType.waistShot:
        return 0.30;
      case ShotType.kneeShot:
        return 0.31;
      case ShotType.fullBody:
        return 0.29;
      case ShotType.environmental:
        return 0.30;
      case ShotType.groupShot:
      case ShotType.unknown:
        return null;
    }
  }

  double? _targetHeadroomTop(ShotType shot) {
    switch (shot) {
      case ShotType.extremeCloseUp:
        return 0.06;
      case ShotType.closeUp:
        return 0.08;
      case ShotType.headShot:
        return 0.09;
      case ShotType.upperBody:
        return 0.10;
      case ShotType.waistShot:
        return 0.09;
      case ShotType.kneeShot:
        return 0.12;
      case ShotType.fullBody:
        return 0.08;
      case ShotType.environmental:
        return 0.10;
      case ShotType.groupShot:
      case ShotType.unknown:
        return null;
    }
  }

  Uint8List _toLuminance(img.Image image) {
    final out = Uint8List(image.width * image.height);
    var i = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        out[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(
          0,
          255,
        );
      }
    }
    return out;
  }

  CoachingResult _stabilize(CoachingResult c) {
    if (c.priority == CoachingPriority.critical) {
      stableMessage = c.message;
      _pendingMessage = c.message;
      _pendingCount = 0;
      _stableCoaching = c;
      return c;
    }

    if (c.message == _pendingMessage) {
      _pendingCount++;
    } else {
      _pendingMessage = c.message;
      _pendingCount = 1;
    }
    final threshold = _stableCoaching.priority == CoachingPriority.perfect
        ? _stabilityThreshold + 2
        : _stabilityThreshold;
    if (_pendingCount >= threshold) {
      stableMessage = _pendingMessage;
      _stableCoaching = CoachingResult(
        message: c.message,
        priority: c.priority,
        confidence: c.confidence,
        reason: c.reason,
      );
    }
    return _stableCoaching;
  }

  // ─── 조명 라벨/색상 헬퍼 (UI에서 사용) ────────────────

  LightingCondition _lightingFromCode(double? code) {
    switch (code?.round()) {
      case 0:
        return LightingCondition.normal;
      case 1:
        return LightingCondition.short;
      case 2:
        return LightingCondition.side;
      case 3:
        return LightingCondition.rim;
      case 4:
        return LightingCondition.back;
      default:
        return LightingCondition.unknown;
    }
  }

  String lightingLabel(LightingCondition c) {
    switch (c) {
      case LightingCondition.normal:
        return '순광';
      case LightingCondition.short:
        return '사광 (좋은 빛)';
      case LightingCondition.side:
        return '측광';
      case LightingCondition.rim:
        return '역사광';
      case LightingCondition.back:
        return '역광';
      case LightingCondition.unknown:
        return '판별 대기중';
    }
  }

  Color lightingBadgeColor(LightingCondition c) {
    switch (c) {
      case LightingCondition.normal:
        return const Color(0xFF90CAF9);
      case LightingCondition.short:
        return const Color(0xFF69F0AE);
      case LightingCondition.side:
        return const Color(0xFFFFC107);
      case LightingCondition.rim:
        return const Color(0xFFFFAB40);
      case LightingCondition.back:
        return const Color(0xFFFF5252);
      case LightingCondition.unknown:
        return const Color(0xB3FFFFFF);
    }
  }

  bool _isAtEdge(Offset? p, {double margin = 0.03}) {
    if (p == null) return false;
    return p.dx < margin ||
        p.dx > 1 - margin ||
        p.dy < margin ||
        p.dy > 1 - margin;
  }

  /// 두 키포인트 중 더 큰 y값을 반환 (프레임 하단에 가까운 쪽)
  double? _maxY(Offset? a, Offset? b) {
    if (a == null && b == null) return null;
    if (a == null) return b!.dy;
    if (b == null) return a.dy;
    return a.dy > b.dy ? a.dy : b.dy;
  }

  /// 눈 전용 비대칭 스무딩: 감는 방향은 빠르게, 뜨는 방향은 느리게
  double? _smoothEyeMetric(double? previous, double? next) {
    if (next == null || next.isNaN) return previous;
    if (previous == null || previous.isNaN) return next;
    // 눈 감는 중 (값 하락): alpha 0.6 → 2프레임이면 반응
    // 눈 뜨는 중 (값 상승): alpha 0.2 → 플리커 방지
    final alpha = next < previous ? 0.6 : 0.2;
    return previous + (next - previous) * alpha;
  }

  /// 키포인트 프레임 간 이동량으로 카메라 안정성을 계산합니다.
  void _updateStability({
    required Map<String, Offset?> current,
    double? shoulderAngle,
    double? shoulderWidth,
    double? eyeWidth,
  }) {
    final visiblePoints = current.values.whereType<Offset>().toList(
      growable: false,
    );
    if (visiblePoints.length < 2) return;

    final currentCenter = Offset(
      visiblePoints.map((p) => p.dx).reduce((a, b) => a + b) /
          visiblePoints.length,
      visiblePoints.map((p) => p.dy).reduce((a, b) => a + b) /
          visiblePoints.length,
    );

    if (_prevStabilityCenter == null) {
      _prevStabilityCenter = currentCenter;
      _prevShoulderWidth = shoulderWidth;
      _prevEyeWidth = eyeWidth;
      _prevShoulderAngle = shoulderAngle;
      _cameraStability = 1.0;
      return;
    }

    final centerDelta = (currentCenter - _prevStabilityCenter!).distance;
    final widthDelta = _normalizedMetricDelta(
      _prevShoulderWidth,
      shoulderWidth,
    );
    final eyeDelta = _normalizedMetricDelta(_prevEyeWidth, eyeWidth);
    final angleDelta = _angleDelta(_prevShoulderAngle, shoulderAngle) / 24.0;
    final poseChangeScore = math.max(
      widthDelta,
      math.max(eyeDelta, angleDelta),
    );

    _prevStabilityCenter = currentCenter;
    _prevShoulderWidth = shoulderWidth ?? _prevShoulderWidth;
    _prevEyeWidth = eyeWidth ?? _prevEyeWidth;
    _prevShoulderAngle = shoulderAngle ?? _prevShoulderAngle;

    if (poseChangeScore > 0.22) {
      _cameraStability = math.min(1.0, _cameraStability + 0.06);
      return;
    }

    _recentDeltas.add(centerDelta);
    if (_recentDeltas.length > _stabilityWindow) {
      _recentDeltas.removeAt(0);
    }
    if (_recentDeltas.length < 3) {
      _cameraStability = 1.0;
      return;
    }

    final avg = _recentDeltas.reduce((a, b) => a + b) / _recentDeltas.length;
    _cameraStability = (1.0 - (avg / _stabilityMaxDelta)).clamp(0.0, 1.0);
  }

  void _updateStablePersonCount(int detectedCount, bool groupShotCandidate) {
    if (detectedCount == _candidatePersonCount) {
      _candidatePersonCountStreak++;
    } else {
      _candidatePersonCount = detectedCount;
      _candidatePersonCountStreak = 1;
    }

    final confirmFrames = detectedCount >= 3
        ? 3
        : detectedCount == 2
        ? 2
        : (_isGroupShotStable || groupShotCandidate)
        ? 3
        : 2;

    if (_candidatePersonCountStreak >= confirmFrames) {
      _stablePersonCount = _candidatePersonCount;
    }
  }

  List<YOLOResult> _selectGroupMetricPersons(
    List<YOLOResult> persons,
    double mainArea,
  ) {
    if (persons.length <= 2 || mainArea <= 0) return persons;

    final filtered = persons
        .where((person) {
          final area = person.normalizedBox.width * person.normalizedBox.height;
          final areaRatio = area / mainArea;
          return areaRatio >= 0.14 ||
              (person.confidence >= 0.45 && areaRatio >= 0.08);
        })
        .toList(growable: false);

    return filtered.length >= 2 ? filtered : persons;
  }

  double _normalizedMetricDelta(double? previous, double? current) {
    if (previous == null ||
        current == null ||
        previous <= 0.0 ||
        current <= 0.0) {
      return 0.0;
    }
    return ((current - previous).abs() / previous).clamp(0.0, 1.0);
  }

  double _angleDelta(double? previous, double? current) {
    if (previous == null || current == null) return 0.0;
    return (current - previous).abs();
  }
}
