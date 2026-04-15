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
  static const int _faceEveryN = 8;
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
  static const int _groupEnterThreshold = 2;
  static const int _groupExitThreshold = 5;

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

  // ─── 눈 감김 정밀 추적 ────────────────────────────
  int _eyeClosedStreak = 0;          // 연속 눈 감김 프레임 수 (네이티브 raw 기반)
  int _anyEyeClosedStreak = 0;       // 그룹 눈 감김 연속 프레임
  static const int _eyeConfirmFrames = 2; // 확정에 필요한 연속 프레임

  // ─── 카메라 안정성 추적 ───────────────────────────
  double _cameraStability = 0.0;
  final List<double> _recentDeltas = [];
  final Map<String, Offset> _prevKeypoints = {};
  static const int _stabilityWindow = 10;
  static const double _stabilityMaxDelta = 0.025;

  static const double _faceMetricAlpha = 0.3;
  static const double _faceRectAlpha = 0.35;

  // ─── 외부 설정 ────────────────────────────────────
  bool isFrontCamera = false;

  /// 기기 방향 (0=세로, 90=가로 왼쪽, 180=거꾸로, 270=가로 오른쪽)
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
    _eyeClosedStreak = 0;
    _anyEyeClosedStreak = 0;
    _cameraStability = 0.0;
    _recentDeltas.clear();
    _prevKeypoints.clear();
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
    _leftEyeOpen = _smoothEyeMetric(_leftEyeOpen, metrics['portraitLeftEyeOpen']);
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
    // 그룹샷 안정화: 진입은 빠르게, 이탈은 느리게 (깜빡임 방지)
    if (persons.length >= 2) {
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
    if (isGroupShot) {
      _stablePersonCount = persons.length;
    } else {
      _stablePersonCount = persons.isEmpty ? 0 : 1;
    }
    double secondPersonSizeRatio = 0.0;
    int groupCroppedCount = 0;
    int faceHiddenCount = 0;
    double spacingUnevenness = 0.0;
    double heightVariation = 0.0;

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

      // ── 얼굴 가시성: 코 키포인트 없으면 얼굴이 안 보이는 것 ──
      // confidence가 낮은 감지(0.3 미만)는 키포인트가 부실할 수 있으므로 제외
      for (final p in persons) {
        if (p.confidence < 0.3) continue;
        final noseKp = _kp(p, PoseKeypointIndex.nose);
        if (noseKp == null) faceHiddenCount++;
      }

      // ── 간격 균등성 (3명 이상) ────────────────────────────
      if (persons.length >= 3) {
        final centerXs = persons
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
            spacingUnevenness = gaps
                    .map((g) => (g - avgGap).abs())
                    .reduce((a, b) => a + b) /
                gaps.length /
                avgGap;
          }
        }
      }

      // ── 키 차이 (bbox top Y 범위) ─────────────────────────
      final topYs = persons.map((p) => p.normalizedBox.top).toList();
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
    final lAnkle =
        _smoothedKp(main, PoseKeypointIndex.leftAnkle, minConf: 0.05);
    final rAnkle = _smoothedKp(
      main,
      PoseKeypointIndex.rightAnkle,
      minConf: 0.05,
    );

    // ─── 카메라 안정성 계산 ──────────────────────────────
    _updateStability({
      'nose': nose,
      'lEye': lEye,
      'rEye': rEye,
      'lShoulder': lShoulder,
      'rShoulder': rShoulder,
    });

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
    // 그룹샷: 모든 인물을 포함하는 전체 영역 비율 사용
    final mainBox = main.normalizedBox;
    final double bboxRatio;
    if (isGroupShot) {
      double gLeft = double.infinity, gTop = double.infinity;
      double gRight = double.negativeInfinity, gBottom = double.negativeInfinity;
      for (final p in persons) {
        final b = p.normalizedBox;
        if (b.left < gLeft) gLeft = b.left;
        if (b.top < gTop) gTop = b.top;
        if (b.right > gRight) gRight = b.right;
        if (b.bottom > gBottom) gBottom = b.bottom;
      }
      bboxRatio = (gRight - gLeft) * (gBottom - gTop);
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

    final hasAnkle = lAnkle != null || rAnkle != null;
    final hasKnee = lKnee != null || rKnee != null;
    final hasHip = lHip != null || rHip != null;
    final hasShoulder = lShoulder != null || rShoulder != null;

    if (isGroupShot) {
      shot = ShotType.groupShot;
    } else if (bboxRatio < 0.35) {
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

    // 그룹샷: headroom을 전체 인물 중 가장 위쪽(키 큰 사람) 기준으로 보정
    if (isGroupShot) {
      double groupMinTop = double.infinity;
      for (final p in persons) {
        if (p.normalizedBox.top < groupMinTop) {
          groupMinTop = p.normalizedBox.top;
        }
      }
      if (groupMinTop < headroom) {
        headroom = groupMinTop;
      }
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

    // ─── 발 간격 비율 (어깨 너비 대비) ──────────────────────
    double? ankleSpacing;
    if (lAnkle != null && rAnkle != null && lShoulder != null && rShoulder != null) {
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
      'knee': _maxY(lKnee, rKnee),
      'ankle': _maxY(lAnkle, rAnkle),
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
      ankleSpacingRatio: ankleSpacing,
      bottomJoint: bottomJoint,
      bottomJointY: bottomJointY,
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

    final coaching = _stabilize(_coachEngine.evaluate(state));

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
      leftKnee: lKnee,
      rightKnee: rKnee,
      leftAnkle: lAnkle,
      rightAnkle: rAnkle,
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
        // 비동기 주기가 8프레임(~0.27초)이므로 streak 1이면 확정
        final anyEyesClosed = faces.any((f) {
          final l = f.leftEyeOpenProbability ?? 1.0;
          final r = f.rightEyeOpenProbability ?? 1.0;
          return l < 0.3 && r < 0.3;
        });
        if (anyEyesClosed) {
          _anyEyeClosedStreak++;
        } else {
          _anyEyeClosedStreak = 0;
        }
        _anyFaceEyesClosed = _anyEyeClosedStreak >= 1;
      } else {
        _anyFaceEyesClosed = false;
        _anyEyeClosedStreak = 0;
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
  void _updateStability(Map<String, Offset?> current) {
    double totalDelta = 0;
    int count = 0;
    for (final entry in current.entries) {
      if (entry.value == null) continue;
      final prev = _prevKeypoints[entry.key];
      if (prev != null) {
        totalDelta += (entry.value! - prev).distance;
        count++;
      }
      _prevKeypoints[entry.key] = entry.value!;
    }
    if (count >= 2) {
      final avgDelta = totalDelta / count;
      _recentDeltas.add(avgDelta);
      if (_recentDeltas.length > _stabilityWindow) {
        _recentDeltas.removeAt(0);
      }
      final avg = _recentDeltas.reduce((a, b) => a + b) / _recentDeltas.length;
      _cameraStability = (1.0 - (avg / _stabilityMaxDelta)).clamp(0.0, 1.0);
    }
  }
}
