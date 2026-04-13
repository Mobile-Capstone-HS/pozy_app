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
import 'lighting_classifier.dart';
import 'portrait_coach_engine.dart';
import 'portrait_overlay_painter.dart';
import 'portrait_scene_state.dart';

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
  static const int _faceEveryN = 20;
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

  // ─── 분석 프레임 카운터 ────────────────────────────
  int _frameCount = 0;
  bool _isAnalyzing = false; // captureFrame 기반 분석 잠금

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
  final Map<int, Offset> _smoothedPosePoints = <int, Offset>{};

  /// 그룹샷 전용: ML Kit으로 감지한 모든 얼굴 중 눈 감긴 사람이 있는지 여부
  bool _anyFaceEyesClosed = false;

  static const double _faceMetricAlpha = 0.3;
  static const double _faceRectAlpha = 0.35;

  // ─── 외부 설정 ────────────────────────────────────
  bool isFrontCamera = false;

  /// 기기 방향 (0=세로, 90=가로 왼쪽, 270=가로 오른쪽)
  /// camera_screen.dart에서 가속도계 기반으로 갱신합니다.
  int deviceOrientationDeg = 0;

  /// 현재 카메라 프레임을 JPEG bytes로 캡처하는 콜백.
  /// camera_screen.dart에서 _cameraController.captureFrame을 주입합니다.
  Future<Uint8List?> Function()? captureFrameCallback;

  // ─── 초기화 / 해제 ────────────────────────────────

  Future<void> init() async {
    await _lightingClassifier.load();
    debugPrint(
      '[PORTRAIT] init done, lighting=${_lightingClassifier.isLoaded}',
    );
  }

  /// 사용자가 상단 selector에서 선택한 구도 규칙을 코칭 엔진에 전달.
  void setRule(CompositionRule rule) {
    _coachEngine.setRule(rule);
  }

  void dispose() {
    _lightingClassifier.dispose();
    _faceDetector.close();
  }

  void reset() {
    _personStreak = 0;
    _frameCount = 0;
    _isAnalyzing = false;
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
    _smoothedPosePoints.clear();
    _anyFaceEyesClosed = false;
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
    _leftEyeOpen = _smoothMetric(_leftEyeOpen, metrics['portraitLeftEyeOpen']);
    _rightEyeOpen = _smoothMetric(
      _rightEyeOpen,
      metrics['portraitRightEyeOpen'],
    );
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

  // ─── 메인 처리 ────────────────────────────────────

  PortraitAnalysisResult processResults(List<YOLOResult> results) {
    final persons = results
        .where((r) => r.className.toLowerCase() == 'person')
        .toList();

    // 사람 안정화
    _personStreak = (persons.isNotEmpty ? _personStreak + 1 : _personStreak - 1)
        .clamp(0, 5);
    final stable = _personStreak >= 2;

    if (!stable) {
      final c = _coachEngine.evaluate(const PortraitSceneState(personCount: 0));
      final stableCoaching = _stabilize(c);
      return PortraitAnalysisResult(
        coaching: stableCoaching,
        overlayData: OverlayData(
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
          coaching: stableCoaching,
          shotType: ShotType.unknown,
        ),
        shotType: ShotType.unknown,
        personCount: 0,
        hasPersonStable: false,
      );
    }

    final main = _selectMainPerson(persons);

    // ─── 다중 인물 메트릭 ─────────────────────────────
    final isGroupShot = persons.length >= 2;
    double secondPersonSizeRatio = 0.0;
    int groupCroppedCount = 0;

    if (isGroupShot) {
      // 면적 기준으로 정렬해 메인 다음으로 큰 인물과 크기 비율 계산
      final areas =
          persons
              .map((p) => p.normalizedBox.width * p.normalizedBox.height)
              .toList()
            ..sort((a, b) => b.compareTo(a));
      final mainArea = main.normalizedBox.width * main.normalizedBox.height;
      final secondArea = areas.length > 1 ? areas[1] : 0.0;
      secondPersonSizeRatio = mainArea > 0 ? secondArea / mainArea : 0.0;

      // 모든 인물의 바운딩박스가 프레임 가장자리에 걸리는지 검사
      const edgeMgn = 0.03;
      for (final p in persons) {
        final b = p.normalizedBox;
        if (b.left < edgeMgn ||
            b.right > 1.0 - edgeMgn ||
            b.top < edgeMgn ||
            b.bottom > 1.0 - edgeMgn) {
          groupCroppedCount++;
        }
      }
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
    final lKnee = _smoothedKp(main, PoseKeypointIndex.leftKnee, minConf: 0.3);
    final rKnee = _smoothedKp(main, PoseKeypointIndex.rightKnee, minConf: 0.3);
    final lAnkle = _smoothedKp(main, PoseKeypointIndex.leftAnkle, minConf: 0.3);
    final rAnkle = _smoothedKp(
      main,
      PoseKeypointIndex.rightAnkle,
      minConf: 0.3,
    );

    // ─── 비동기 분석 (조명 + 얼굴, captureFrame 공유) ─────
    // 어깨 각도
    final sConf = math.min(
      _conf(main, PoseKeypointIndex.leftShoulder),
      _conf(main, PoseKeypointIndex.rightShoulder),
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
    final mainBox = main.normalizedBox;
    final bboxRatio = mainBox.width * mainBox.height;
    final centerX = (mainBox.left + mainBox.right) / 2;

    final hasAnkle = lAnkle != null || rAnkle != null;
    final hasKnee = lKnee != null || rKnee != null;
    final hasHip = lHip != null || rHip != null;
    final hasShoulder = lShoulder != null || rShoulder != null;

    if (bboxRatio < 0.35) {
      shot = ShotType.environmental;
    } else if (maxY > minY) {
      final h = maxY - minY;

      if (hasAnkle && h > 0.7) {
        shot = ShotType.fullBody;
      } else if (hasKnee && !hasAnkle) {
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
    if (shot == ShotType.kneeShot || shot == ShotType.fullBody) {
      if (_isAtEdge(lKnee) || _isAtEdge(rKnee)) croppedList.add('knee');
    }
    if (shot == ShotType.fullBody) {
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

    final state = PortraitSceneState(
      personCount: persons.length,
      shotType: shot,
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
      isGroupShot: isGroupShot,
      secondPersonSizeRatio: secondPersonSizeRatio,
      groupCroppedCount: groupCroppedCount,
      anyFaceEyesClosed: _anyFaceEyesClosed,
      lightingCondition: lastLighting,
      lightingConfidence: lastLightingConf,
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
    );

    final coaching = _stabilize(_coachEngine.evaluate(state));

    // ─── 그룹샷 전용: 모든 얼굴 눈 감김 비동기 검사 ───────────
    // captureFrameCallback이 연결된 경우에만 실행 (_faceEveryN 프레임마다)
    _frameCount++;
    if (isGroupShot &&
        captureFrameCallback != null &&
        !_isAnalyzing &&
        _frameCount % _faceEveryN == 0) {
      _isAnalyzing = true;
      unawaited(() async {
        try {
          final bytes = await captureFrameCallback!();
          if (bytes != null && bytes.isNotEmpty) {
            await _analyzeFace(bytes);
          }
        } finally {
          _isAnalyzing = false;
        }
      }());
    }

    final overlay = OverlayData(
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
      coaching: coaching,
      shotType: shot,
      eyeConfidence: eyeConf,
      shoulderConfidence: sConf,
      faceGuideRect: faceRect,
      targetEyeLineY: _targetEyeLineY(shot),
      targetHeadroomTop: _targetHeadroomTop(shot),
    );

    return PortraitAnalysisResult(
      coaching: coaching,
      overlayData: overlay,
      shotType: shot,
      personCount: persons.length,
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
    final needLighting =
        _lightingClassifier.isLoaded &&
        !_isAnalyzing &&
        _frameCount % _lightingEveryN == 0;
    final needFace = !_isAnalyzing && _frameCount % _faceEveryN == 0;

    if (!needLighting && !needFace) return;

    _isAnalyzing = true;

    unawaited(() async {
      try {
        // captureFrame 한 번만 호출
        final bytes = await captureFrame();
        if (bytes == null || bytes.isEmpty) return;

        // 조명 분석
        if (needLighting) {
          await _analyzeLight(
            bytes,
            mainPerson,
            nose,
            lEye,
            rEye,
            lShoulder,
            rShoulder,
          );
        }

        // 얼굴 분석
        if (needFace) {
          await _analyzeFace(bytes);
        }
      } catch (e) {
        debugPrint('[PORTRAIT] analysis error=$e');
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
      debugPrint('[LIGHT] error=$e');
    }
  }

  Future<void> _analyzeFace(Uint8List bytes) async {
    try {
      final tempFile = File('${Directory.systemTemp.path}/pozy_face.jpg');
      await tempFile.writeAsBytes(bytes);
      final input = InputImage.fromFilePath(tempFile.path);
      final faces = await _faceDetector.processImage(input);

      if (faces.isNotEmpty) {
        // 가장 큰 얼굴을 메인으로 사용
        final mainFace = faces.length == 1
            ? faces.first
            : faces.reduce(
                (a, b) =>
                    (a.boundingBox.width * a.boundingBox.height) >=
                        (b.boundingBox.width * b.boundingBox.height)
                    ? a
                    : b,
              );

        _faceYaw = mainFace.headEulerAngleY;
        _facePitch = mainFace.headEulerAngleX;
        _faceRoll = mainFace.headEulerAngleZ;
        _leftEyeOpen = mainFace.leftEyeOpenProbability;
        _rightEyeOpen = mainFace.rightEyeOpenProbability;
        _smileProb = mainFace.smilingProbability;

        // ─── 그룹샷: 감지된 모든 얼굴에서 눈 감김 검사 ────────
        // enableClassification: true 이므로 eyeOpenProbability가 제공됨
        _anyFaceEyesClosed = faces.any((f) {
          final l = f.leftEyeOpenProbability ?? 1.0;
          final r = f.rightEyeOpenProbability ?? 1.0;
          return l < 0.3 && r < 0.3;
        });
      } else {
        _anyFaceEyesClosed = false;
      }
    } catch (e) {
      debugPrint('[FACE] error=$e');
    }
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

  Rect? _smoothRect(Rect? previous, Rect? next) {
    if (next == null) return previous;
    if (previous == null) return next;

    return Rect.fromLTRB(
      previous.left + (next.left - previous.left) * _faceRectAlpha,
      previous.top + (next.top - previous.top) * _faceRectAlpha,
      previous.right + (next.right - previous.right) * _faceRectAlpha,
      previous.bottom + (next.bottom - previous.bottom) * _faceRectAlpha,
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
}
