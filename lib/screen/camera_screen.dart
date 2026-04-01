import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import '../portrait/lighting_classifier.dart';
import '../portrait/portrait_coach_engine.dart';
import '../portrait/portrait_overlay_painter.dart';
import '../portrait/portrait_scene_state.dart';
import '../subject_detection.dart'
    show detectModelPath, detectionConfidenceThreshold;
import '../subject_selector.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// ─── YOLO Pose 키포인트 인덱스 (COCO 17) ────────────────────
// 0: nose, 1: leftEye, 2: rightEye, 3: leftEar, 4: rightEar,
// 5: leftShoulder, 6: rightShoulder, 7: leftElbow, 8: rightElbow,
// 9: leftWrist, 10: rightWrist, 11: leftHip, 12: rightHip,
// 13: leftKnee, 14: rightKnee, 15: leftAnkle, 16: rightAnkle

class _PoseKeypointIndex {
  static const int nose = 0;
  static const int leftEye = 1;
  static const int rightEye = 2;
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

/// assets/models/yolov8n-pose_float16.tflite
/// ultralytics_yolo 플러그인이 assets/models 내부 basename으로 찾는 구조에 맞춤
const String poseModelPath = 'yolov8n-pose_float16.tflite';

/// 인물 모드 코칭 confidence threshold
const double poseConfidenceThreshold = 0.2;

class CameraScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;

  const CameraScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const List<double> _zoomPresets = [0.5, 1.0, 2.0];
  static const int _lightingInferenceEveryNFrames = 15;
  static const double _lightingMinConfidence = 0.55;

  final YOLOViewController _cameraController = YOLOViewController();
  final SubjectSelector _subjectSelector = const SubjectSelector(
    wSize: 0.35,
    wCenter: 0.25,
    wClass: 0.2,
    wConfidence: 0.1,
    wSaliency: 0.1,
    threshold: 0.3,
  );
  final PortraitCoachEngine _coachEngine = PortraitCoachEngine();
  final LightingClassifier _lightingClassifier = LightingClassifier();

  final List<_DetectionBox> _detections = [];

  Size _previewSize = Size.zero;
  int _detectedCount = 0;
  int _personCount = 0;
  int _objectCount = 0;
  String _guidance = 'Scene is balanced';
  String? _mainSubjectLabel;
  _TrackedSubject? _currentMainSubject;
  _TrackedSubject? _lockedSubject;
  double _currentZoom = 1.0;
  double _selectedZoom = 1.0;
  bool _isFrontCamera = false;
  bool _isSaving = false;
  bool _showFlash = false;
  int _personStreak = 0;
  bool _hasPersonStable = false;
  // ─── 인물 모드 상태 ────────────────────────────────
  bool _isPortraitMode = false;
  int _lightingFrameCount = 0;
  bool _isLightingProcessing = false;
  LightingCondition _lastLighting = LightingCondition.unknown;
  double _lastLightingConf = 0.0;
  // ─── 얼굴 분석 상태 (ML Kit) ────────────────────────
  static const int _faceAnalysisEveryNFrames = 10;
  int _faceFrameCount = 0;
  bool _isFaceProcessing = false;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // 눈 감김, 웃음 확률
      enableTracking: false,
      performanceMode: FaceDetectorMode.fast,
    ),
  );
  double? _lastFaceYaw;
  double? _lastFacePitch;
  double? _lastFaceRoll;
  double? _lastLeftEyeOpenProb;
  double? _lastRightEyeOpenProb;
  double? _lastSmileProb;
  CoachingResult _currentCoaching = const CoachingResult(
    message: '카메라를 사람에게 향해주세요',
    priority: CoachingPriority.critical,
    confidence: 1.0,
  );

  String _stableMessage = '카메라를 사람에게 향해주세요';
  String _pendingMessage = '';
  int _pendingCount = 0;
  static const int _stabilityThreshold = 5;

  OverlayData _overlayData = OverlayData(
    coaching: const CoachingResult(
      message: '',
      priority: CoachingPriority.critical,
      confidence: 0.0,
    ),
  );

  @override
  void initState() {
    super.initState();
    debugPrint('[CAMERA_SCREEN] initState called');
    _lightingClassifier
        .load()
        .then((_) {
          debugPrint('[LIGHT_INIT] isLoaded=${_lightingClassifier.isLoaded}');
        })
        .catchError((e, st) {
          debugPrint('[LIGHT_INIT] FAILED: $e');
        });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _cameraController.restartCamera();
      await _cameraController.setZoomLevel(_selectedZoom);
    });
  }

  Future<void> _runLightingClassification(
    YOLOResult mainPerson, {
    required Rect faceRect,
  }) async {
    _lightingFrameCount++;
    if (!_isPortraitMode ||
        !_lightingClassifier.isLoaded ||
        _isLightingProcessing ||
        _isSaving ||
        _lightingFrameCount % _lightingInferenceEveryNFrames != 0) {
      return;
    }

    _isLightingProcessing = true;
    debugPrint('[LIGHT] start');

    try {
      final bytes = await _cameraController.captureFrame();
      if (bytes == null || bytes.isEmpty) {
        debugPrint('[LIGHT] skipped empty-frame');
        return;
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint('[LIGHT] skipped decode-failed');
        return;
      }

      final baked = img.bakeOrientation(decoded);
      final luminance = _toLuminanceBytes(baked);
      final faceCrop = _lightingClassifier.prepareFaceCrop(
        imageBytes: luminance,
        imageWidth: baked.width,
        imageHeight: baked.height,
        faceLeft: faceRect.left,
        faceTop: faceRect.top,
        faceWidth: faceRect.width,
        faceHeight: faceRect.height,
      );

      if (faceCrop == null) {
        debugPrint('[LIGHT] skipped face-crop-null');
        return;
      }

      final result = _lightingClassifier.classify(faceCrop);
      final condition = result.confidence >= _lightingMinConfidence
          ? result.condition
          : LightingCondition.unknown;
      final confidence = condition == LightingCondition.unknown
          ? 0.0
          : result.confidence;

      debugPrint(
        '[LIGHT] label=${_lightingLabel(condition)} '
        'score=${confidence.toStringAsFixed(2)} '
        'rect=${faceRect.left.toStringAsFixed(2)},${faceRect.top.toStringAsFixed(2)},'
        '${faceRect.width.toStringAsFixed(2)},${faceRect.height.toStringAsFixed(2)}',
      );

      if (!mounted) return;

      final changed =
          _lastLighting != condition ||
          (_lastLightingConf - confidence).abs() > 0.05;

      if (changed) {
        setState(() {
          _lastLighting = condition;
          _lastLightingConf = confidence;
        });
      }
    } catch (e) {
      debugPrint('[LIGHT] error=$e');
    } finally {
      _isLightingProcessing = false;
    }
  }

  Future<void> _runFaceAnalysis() async {
    _faceFrameCount++;
    if (!_isPortraitMode ||
        _isFaceProcessing ||
        _isSaving ||
        _faceFrameCount % _faceAnalysisEveryNFrames != 0) {
      return;
    }

    _isFaceProcessing = true;

    try {
      final bytes = await _cameraController.captureFrame();
      if (bytes == null || bytes.isEmpty) return;

      // JPEG 바이트를 임시 파일로 저장 후 ML Kit에 전달
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/pozy_face_temp.jpg');
      await tempFile.writeAsBytes(bytes);
      final inputImage = InputImage.fromFilePath(tempFile.path);

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        final changed =
            _lastFaceYaw != face.headEulerAngleY ||
            _lastFacePitch != face.headEulerAngleX ||
            _lastFaceRoll != face.headEulerAngleZ;

        if (changed && mounted) {
          setState(() {
            _lastFaceYaw = face.headEulerAngleY;
            _lastFacePitch = face.headEulerAngleX;
            _lastFaceRoll = face.headEulerAngleZ;
            _lastLeftEyeOpenProb = face.leftEyeOpenProbability;
            _lastRightEyeOpenProb = face.rightEyeOpenProbability;
            _lastSmileProb = face.smilingProbability;
          });
        }

        debugPrint(
          '[FACE] yaw=${face.headEulerAngleY?.toStringAsFixed(1)} '
          'pitch=${face.headEulerAngleX?.toStringAsFixed(1)} '
          'roll=${face.headEulerAngleZ?.toStringAsFixed(1)} '
          'leftEye=${face.leftEyeOpenProbability?.toStringAsFixed(2)} '
          'rightEye=${face.rightEyeOpenProbability?.toStringAsFixed(2)}',
        );
      }
    } catch (e) {
      debugPrint('[FACE] error=$e');
    } finally {
      _isFaceProcessing = false;
    }
  }

  Uint8List _toLuminanceBytes(img.Image image) {
    final bytes = Uint8List(image.width * image.height);
    var index = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            .round();
        bytes[index++] = luminance.clamp(0, 255);
      }
    }
    return bytes;
  }

  Rect _estimateFaceRectFromPose({
    required Rect personBox,
    Offset? nose,
    Offset? leftEye,
    Offset? rightEye,
    Offset? leftShoulder,
    Offset? rightShoulder,
  }) {
    final eyeMidpoint = (leftEye != null && rightEye != null)
        ? Offset((leftEye.dx + rightEye.dx) / 2, (leftEye.dy + rightEye.dy) / 2)
        : null;

    final center = eyeMidpoint ?? nose ?? personBox.center;

    double width;
    if (leftShoulder != null && rightShoulder != null) {
      width = (rightShoulder.dx - leftShoulder.dx).abs() * 0.75;
    } else if (leftEye != null && rightEye != null) {
      width = (rightEye.dx - leftEye.dx).abs() * 2.4;
    } else {
      width = personBox.width * 0.38;
    }

    width = width.clamp(0.12, 0.45);
    final height = (width * 1.18).clamp(0.14, 0.52);

    final left = (center.dx - width / 2).clamp(0.0, 1.0);
    final top = (center.dy - height * 0.45).clamp(0.0, 1.0);
    final safeWidth = width.clamp(0.05, 1.0 - left);
    final safeHeight = height.clamp(0.05, 1.0 - top);

    return Rect.fromLTWH(left, top, safeWidth, safeHeight);
  }

  String _lightingLabel(LightingCondition condition) {
    switch (condition) {
      case LightingCondition.side:
        return '측면광 경향';
      case LightingCondition.back:
        return '역광 경향';
      case LightingCondition.normal:
        return '정면광 경향';
      case LightingCondition.unknown:
        return '판별 대기중';
    }
  }

  Color _lightingBadgeColor(LightingCondition condition) {
    switch (condition) {
      case LightingCondition.side:
        return Colors.amber;
      case LightingCondition.back:
        return Colors.redAccent;
      case LightingCondition.normal:
        return Colors.greenAccent;
      case LightingCondition.unknown:
        return Colors.white70;
    }
  }

  // ─── 모드 전환 ───────────────────────────────────────
  void _togglePortraitMode() {
    setState(() {
      _isPortraitMode = !_isPortraitMode;
      _detections.clear();
      _detectedCount = 0;
      _personCount = 0;
      _objectCount = 0;
      _guidance = _isPortraitMode ? '' : 'Scene is balanced';
      _mainSubjectLabel = null;
      _currentMainSubject = null;
      _lockedSubject = null;
      _currentCoaching = const CoachingResult(
        message: '카메라를 사람에게 향해주세요',
        priority: CoachingPriority.critical,
        confidence: 1.0,
      );
      _stableMessage = '카메라를 사람에게 향해주세요';
      _pendingMessage = '';
      _pendingCount = 0;
      _lightingFrameCount = 0;
      _isLightingProcessing = false;
      _lastLighting = LightingCondition.unknown;
      _lastLightingConf = 0.0;
      _faceFrameCount = 0;
      _isFaceProcessing = false;
      _lastFaceYaw = null;
      _lastFacePitch = null;
      _lastFaceRoll = null;
      _lastLeftEyeOpenProb = null;
      _lastRightEyeOpenProb = null;
      _lastSmileProb = null;
      _overlayData = OverlayData(
        coaching: const CoachingResult(
          message: '',
          priority: CoachingPriority.critical,
          confidence: 0.0,
        ),
      );
    });
  }

  // ─── 좌표 / 유틸리티 ──────────────────────────────────
  Rect _toPreviewRect(Rect normalizedBox, Size previewSize) {
    return Rect.fromLTRB(
      (normalizedBox.left * previewSize.width).clamp(0.0, previewSize.width),
      (normalizedBox.top * previewSize.height).clamp(0.0, previewSize.height),
      (normalizedBox.right * previewSize.width).clamp(0.0, previewSize.width),
      (normalizedBox.bottom * previewSize.height).clamp(
        0.0,
        previewSize.height,
      ),
    );
  }

  SubjectSelectionResult _selectMainSubject(
    List<YOLOResult> results,
    Size previewSize,
  ) {
    final detections = results
        .asMap()
        .entries
        .map(
          (entry) => SubjectDetection(
            id: entry.key,
            normalizedBox: Rect.fromLTRB(
              entry.value.normalizedBox.left,
              entry.value.normalizedBox.top,
              entry.value.normalizedBox.right,
              entry.value.normalizedBox.bottom,
            ),
            className: entry.value.className,
            confidence: entry.value.confidence,
          ),
        )
        .toList();

    return _subjectSelector.selectMainSubject(
      detections: detections,
      imageSize: previewSize,
    );
  }

  _TrackedSubject? _subjectFromResult(YOLOResult result, Size previewSize) {
    final rect = _toPreviewRect(result.normalizedBox, previewSize);
    return _TrackedSubject(
      className: result.className,
      normalizedBox: Rect.fromLTRB(
        result.normalizedBox.left,
        result.normalizedBox.top,
        result.normalizedBox.right,
        result.normalizedBox.bottom,
      ),
      rect: rect,
      confidence: result.confidence,
    );
  }

  int? _matchLockedSubject(List<YOLOResult> results) {
    final locked = _lockedSubject;
    if (locked == null || results.isEmpty) {
      return null;
    }

    int? bestIndex;
    double bestScore = 0;

    for (final entry in results.asMap().entries) {
      final result = entry.value;
      final sameClass =
          result.className.toLowerCase() == locked.className.toLowerCase();
      final iou = _intersectionOverUnion(
        locked.normalizedBox,
        Rect.fromLTRB(
          result.normalizedBox.left,
          result.normalizedBox.top,
          result.normalizedBox.right,
          result.normalizedBox.bottom,
        ),
      );
      final centerA = Offset(
        result.normalizedBox.center.dx,
        result.normalizedBox.center.dy,
      );
      final centerB = Offset(
        locked.normalizedBox.center.dx,
        locked.normalizedBox.center.dy,
      );

      final centerDistance = (centerA - centerB).distance;
      final distanceScore = (1 - (centerDistance / 0.45)).clamp(0.0, 1.0);
      final classScore = sameClass ? 1.0 : 0.0;
      final score = (classScore * 0.45) + (iou * 0.35) + (distanceScore * 0.20);

      if (score > bestScore) {
        bestScore = score;
        bestIndex = entry.key;
      }
    }

    if (bestScore < 0.35) {
      return null;
    }

    return bestIndex;
  }

  double _intersectionOverUnion(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) {
      return 0;
    }

    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) {
      return 0;
    }
    return intersectionArea / unionArea;
  }

  void _toggleSubjectLock() {
    setState(() {
      if (_lockedSubject != null) {
        _lockedSubject = null;
        return;
      }

      if (_currentMainSubject != null) {
        _lockedSubject = _currentMainSubject;
      }
    });
  }

  // ─── YOLO 키포인트에서 정규화 좌표 추출 ─────────────────
  //
  // YOLOResult.keypoints 는 dynamic 타입입니다.
  // 네이티브 브릿지에서 넘어오는 실제 구조에 관계없이 안전하게 추출합니다.
  bool _keypointDiagDone = false;

  void _logKeypointDiagnostics(YOLOResult result) {
    if (_keypointDiagDone) return;
    //_keypointDiagDone = true;

    final dynamic kps = result.keypoints;
    final dynamic confs = result.keypointConfidences;
    debugPrint('[KP_DIAG] boundingBox=${result.boundingBox}');
    debugPrint('[KP_DIAG] normalizedBox=${result.normalizedBox}');
    debugPrint('[KP_DIAG] raw kps[0]=${(result.keypoints as List)[0]}');
    debugPrint('[KP_DIAG] raw kps[5]=${(result.keypoints as List)[5]}');
    debugPrint('[KP_DIAG] ═══════════════════════════════════');
    debugPrint('[KP_DIAG] keypoints type: ${kps.runtimeType}');
    debugPrint('[KP_DIAG] keypoints isNull: ${kps == null}');
    debugPrint('[KP_DIAG] keypointConfidences type: ${confs.runtimeType}');
    debugPrint('[KP_DIAG] keypointConfidences isNull: ${confs == null}');

    if (kps is List && kps.isNotEmpty) {
      debugPrint('[KP_DIAG] keypoints.length: ${kps.length}');
      debugPrint('[KP_DIAG] keypoints[0] type: ${kps[0].runtimeType}');
      debugPrint('[KP_DIAG] keypoints[0] value: ${kps[0]}');
      if (kps.length > 1) {
        debugPrint('[KP_DIAG] keypoints[1] type: ${kps[1].runtimeType}');
        debugPrint('[KP_DIAG] keypoints[1] value: ${kps[1]}');
      }
      if (kps.length > 2) {
        debugPrint('[KP_DIAG] keypoints[2] value: ${kps[2]}');
      }
      // 첫 번째 요소의 프로퍼티 탐색
      final first = kps[0];
      try {
        debugPrint('[KP_DIAG] kps[0].x = ${first.x}');
      } catch (_) {}
      try {
        debugPrint('[KP_DIAG] kps[0].y = ${first.y}');
      } catch (_) {}
      try {
        debugPrint('[KP_DIAG] kps[0].dx = ${first.dx}');
      } catch (_) {}
      try {
        debugPrint('[KP_DIAG] kps[0].dy = ${first.dy}');
      } catch (_) {}
    } else if (kps != null) {
      debugPrint('[KP_DIAG] keypoints is not List or empty. toString: $kps');
    }

    if (confs is List && confs.isNotEmpty) {
      debugPrint('[KP_DIAG] confs.length: ${confs.length}');
      debugPrint('[KP_DIAG] confs[0] type: ${confs[0].runtimeType}');
      debugPrint('[KP_DIAG] confs[0] value: ${confs[0]}');
      debugPrint('[KP_DIAG] confs sample: ${confs.take(5).toList()}');
    }
    debugPrint('[KP_DIAG] ═══════════════════════════════════');
  }

  Offset? _getKeypoint(
    YOLOResult result,
    int index, {
    double minConfidence = 0.01,
  }) {
    final dynamic kps = result.keypoints;
    final dynamic confs = result.keypointConfidences;
    if (kps == null || confs == null) return null;

    final List<dynamic> confList = confs is List ? confs : <dynamic>[];
    if (index >= confList.length) return null;

    final double conf = (confList[index] as num).toDouble();
    if (conf < minConfidence) return null;

    final List<dynamic> kpList = kps is List ? kps : <dynamic>[];
    if (kpList.isEmpty) return null;

    double x;
    double y;

    try {
      final dynamic first = kpList[0];

      if (first is num) {
        // flat 리스트: [x0, y0, x1, y1, ...]
        final int xIdx = index * 2;
        final int yIdx = index * 2 + 1;
        if (yIdx >= kpList.length) return null;
        x = (kpList[xIdx] as num).toDouble();
        y = (kpList[yIdx] as num).toDouble();
      } else if (first is Offset) {
        // List<Offset>
        if (index >= kpList.length) return null;
        final Offset pt = kpList[index] as Offset;
        x = pt.dx;
        y = pt.dy;
      } else if (first is List) {
        // List<List<num>>: [[x0, y0], [x1, y1], ...]
        if (index >= kpList.length) return null;
        final List<dynamic> pt = kpList[index] as List<dynamic>;
        x = (pt[0] as num).toDouble();
        y = (pt[1] as num).toDouble();
      } else {
        // Point<num> 등 .x / .y 프로퍼티를 가진 객체
        if (index >= kpList.length) return null;
        final dynamic pt = kpList[index];
        x = (pt.x as num).toDouble();
        y = (pt.y as num).toDouble();
      }
    } catch (e) {
      debugPrint('[KEYPOINT] extract error index=$index: $e');
      return null;
    }

    // 픽셀 좌표를 정규화 (origShape 기준)
    final dynamic kpsList = result.keypoints;
    // YOLOResult의 boundingBox에서 원본 이미지 크기를 추정할 수 없으므로
    // 좌표가 1.0보다 크면 픽셀 좌표로 판단하고 정규화
    // 픽셀 좌표를 정규화 — boundingBox의 right/bottom을 이미지 크기로 사용
    if (x > 1.0 || y > 1.0) {
      // normalizedBox로 원본 이미지 크기 역산
      final normBox = result.normalizedBox;
      final bbox = result.boundingBox;
      // right / normBox.right = 이미지 전체 폭, bottom / normBox.bottom = 이미지 전체 높이
      final imgW = (normBox.right > 0) ? bbox.right / normBox.right : 480.0;
      final imgH = (normBox.bottom > 0) ? bbox.bottom / normBox.bottom : 640.0;
      x = x / imgW;
      y = y / imgH;
    }
    final nx = x.clamp(0.0, 1.0);
    final ny = y.clamp(0.0, 1.0);
    // 전면 카메라는 프리뷰가 좌우 반전되므로 x좌표도 반전
    if (_isFrontCamera) {
      return Offset(1.0 - nx, ny);
    }
    return Offset(nx, ny);
  }

  double _getKeypointConfidence(YOLOResult result, int index) {
    final dynamic confs = result.keypointConfidences;
    if (confs == null) return 0.0;
    final List<dynamic> list = confs is List ? confs : <dynamic>[];
    if (index >= list.length) return 0.0;
    return (list[index] as num).toDouble();
  }

  // ─── 인물 모드: 포즈 결과 처리 ──────────────────────────
  void _handlePoseDetections(List<YOLOResult> results) {
    if (!mounted) return;
    debugPrint(
      '[LIGHT_CHECK] isLoaded=${_lightingClassifier.isLoaded} isProcessing=$_isLightingProcessing frameCount=$_lightingFrameCount',
    );
    debugPrint('[POSE] results=${results.length}');
    for (final r in results) {
      debugPrint('[POSE] class=${r.className} conf=${r.confidence}');
    }

    final previewSize = _previewSize == Size.zero
        ? MediaQuery.sizeOf(context)
        : _previewSize;

    final personResults = results
        .where((r) => r.className.toLowerCase() == 'person')
        .toList();

    final int personCount = personResults.length;
    debugPrint('[POSE] personCount=$personCount');

    if (personCount > 0) {
      _personStreak++;
    } else {
      _personStreak--;
    }

    _personStreak = _personStreak.clamp(0, 5);
    _hasPersonStable = _personStreak >= 2;

    debugPrint('[POSE] stable=$_hasPersonStable streak=$_personStreak');

    if (!_hasPersonStable) {
      final coaching = _coachEngine.evaluate(
        const PortraitSceneState(personCount: 0),
      );
      _stabilizeMessage(coaching);

      setState(() {
        _detectedCount = 0;
        _personCount = 0;
        _objectCount = 0;
        _currentCoaching = coaching;
        _overlayData = OverlayData(
          coaching: coaching,
          shotType: ShotType.unknown,
        );
        _detections.clear();
      });
      return;
    }
    final mainPerson = personResults.reduce((a, b) {
      final areaA = a.normalizedBox.width * a.normalizedBox.height;
      final areaB = b.normalizedBox.width * b.normalizedBox.height;
      return areaA >= areaB ? a : b;
    });

    // ─── 키포인트 진단 (최초 1회) ───────────────────
    _logKeypointDiagnostics(mainPerson);

    final leftEye = _getKeypoint(mainPerson, _PoseKeypointIndex.leftEye);
    final rightEye = _getKeypoint(mainPerson, _PoseKeypointIndex.rightEye);
    final nose = _getKeypoint(mainPerson, _PoseKeypointIndex.nose);
    final leftShoulder = _getKeypoint(
      mainPerson,
      _PoseKeypointIndex.leftShoulder,
    );
    final rightShoulder = _getKeypoint(
      mainPerson,
      _PoseKeypointIndex.rightShoulder,
    );
    final leftElbow = _getKeypoint(mainPerson, _PoseKeypointIndex.leftElbow);
    final rightElbow = _getKeypoint(mainPerson, _PoseKeypointIndex.rightElbow);
    final leftWrist = _getKeypoint(mainPerson, _PoseKeypointIndex.leftWrist);
    final rightWrist = _getKeypoint(mainPerson, _PoseKeypointIndex.rightWrist);
    final leftHip = _getKeypoint(mainPerson, _PoseKeypointIndex.leftHip);
    final rightHip = _getKeypoint(mainPerson, _PoseKeypointIndex.rightHip);

    // 키포인트 추출 결과 확인 (최초 몇 프레임)
    if (!_keypointDiagDone || _personStreak <= 3) {
      debugPrint('[KP_RESULT] nose=$nose leftEye=$leftEye rightEye=$rightEye');
      debugPrint(
        '[KP_RESULT] lShoulder=$leftShoulder rShoulder=$rightShoulder',
      );
    }
    final leftKnee = _getKeypoint(
      mainPerson,
      _PoseKeypointIndex.leftKnee,
      minConfidence: 0.3,
    );
    final rightKnee = _getKeypoint(
      mainPerson,
      _PoseKeypointIndex.rightKnee,
      minConfidence: 0.3,
    );
    final leftAnkle = _getKeypoint(
      mainPerson,
      _PoseKeypointIndex.leftAnkle,
      minConfidence: 0.3,
    );
    final rightAnkle = _getKeypoint(
      mainPerson,
      _PoseKeypointIndex.rightAnkle,
      minConfidence: 0.3,
    );

    final faceRect = _estimateFaceRectFromPose(
      personBox: Rect.fromLTRB(
        mainPerson.normalizedBox.left,
        mainPerson.normalizedBox.top,
        mainPerson.normalizedBox.right,
        mainPerson.normalizedBox.bottom,
      ),
      nose: nose,
      leftEye: leftEye,
      rightEye: rightEye,
      leftShoulder: leftShoulder,
      rightShoulder: rightShoulder,
    );
    unawaited(_runLightingClassification(mainPerson, faceRect: faceRect));
    unawaited(_runFaceAnalysis());
    double? shoulderAngle;
    final shoulderConf = math.min(
      _getKeypointConfidence(mainPerson, _PoseKeypointIndex.leftShoulder),
      _getKeypointConfidence(mainPerson, _PoseKeypointIndex.rightShoulder),
    );
    if (leftShoulder != null && rightShoulder != null && shoulderConf > 0.5) {
      final dy = rightShoulder.dy - leftShoulder.dy;
      final dx = rightShoulder.dx - leftShoulder.dx;
      shoulderAngle = math.atan2(dy, dx) * 180 / math.pi;
    }

    double? leftArmGap;
    double? rightArmGap;
    final elbowConf = math.max(
      _getKeypointConfidence(mainPerson, _PoseKeypointIndex.leftElbow),
      _getKeypointConfidence(mainPerson, _PoseKeypointIndex.rightElbow),
    );

    if (leftElbow != null && leftShoulder != null && leftHip != null) {
      final bodyX = (leftShoulder.dx + leftHip.dx) / 2;
      leftArmGap = (leftElbow.dx - bodyX).abs();
    }
    if (rightElbow != null && rightShoulder != null && rightHip != null) {
      final bodyX = (rightShoulder.dx + rightHip.dx) / 2;
      rightArmGap = (rightElbow.dx - bodyX).abs();
    }

    Offset? eyeMidpoint;
    final eyeConf = math.min(
      _getKeypointConfidence(mainPerson, _PoseKeypointIndex.leftEye),
      _getKeypointConfidence(mainPerson, _PoseKeypointIndex.rightEye),
    );
    if (leftEye != null && rightEye != null) {
      eyeMidpoint = Offset(
        (leftEye.dx + rightEye.dx) / 2,
        (leftEye.dy + rightEye.dy) / 2,
      );
    }

    ShotType shotType = ShotType.unknown;
    double headroomRatio = 0.0;
    double footSpaceRatio = 0.0;

    final allKeypoints = <Offset?>[
      leftEye,
      rightEye,
      nose,
      leftShoulder,
      rightShoulder,
      leftElbow,
      rightElbow,
      leftWrist,
      rightWrist,
      leftHip,
      rightHip,
      leftKnee,
      rightKnee,
      leftAnkle,
      rightAnkle,
    ];

    double minY = 1.0;
    double maxY = 0.0;
    for (final kp in allKeypoints) {
      if (kp != null) {
        minY = math.min(minY, kp.dy);
        maxY = math.max(maxY, kp.dy);
      }
    }

    if (maxY > minY) {
      final bboxHeight = maxY - minY;
      if (bboxHeight > 0.6) {
        shotType = ShotType.closeUp;
      } else if (bboxHeight > 0.35) {
        shotType = ShotType.upperBody;
      } else {
        shotType = ShotType.fullBody;
      }
      headroomRatio = minY;
      footSpaceRatio = 1.0 - maxY;
    }

    bool isJointCropped = false;
    const edgeMargin = 0.03;
    final edgeCheckPoints = <Offset?>[
      leftWrist,
      rightWrist,
      leftElbow,
      rightElbow,
      leftKnee,
      rightKnee,
      leftAnkle,
      rightAnkle,
    ];
    for (final pt in edgeCheckPoints) {
      if (pt != null &&
          (pt.dx < edgeMargin ||
              pt.dx > 1 - edgeMargin ||
              pt.dy < edgeMargin ||
              pt.dy > 1 - edgeMargin)) {
        isJointCropped = true;
        break;
      }
    }

    final state = PortraitSceneState(
      personCount: personCount,
      faceYaw: _lastFaceYaw,
      facePitch: _lastFacePitch,
      faceRoll: _lastFaceRoll,
      smileProbability: _lastSmileProb,
      leftEyeOpenProb: _lastLeftEyeOpenProb,
      rightEyeOpenProb: _lastRightEyeOpenProb,
      shoulderAngleDeg: shoulderAngle,
      leftArmBodyGap: leftArmGap,
      rightArmBodyGap: rightArmGap,
      eyeMidpoint: eyeMidpoint,
      isJointCropped: isJointCropped,
      headroomRatio: headroomRatio,
      footSpaceRatio: footSpaceRatio,
      shoulderConfidence: shoulderConf,
      elbowConfidence: elbowConf,
      eyeConfidence: eyeConf,
      lightingCondition: _lastLighting,
      lightingConfidence: _lastLightingConf,
      visibleKeypointCount: allKeypoints.where((kp) => kp != null).length,
      hasNose: nose != null,
      hasEyes: leftEye != null && rightEye != null,
      hasShoulders: leftShoulder != null && rightShoulder != null,
    );

    final coaching = _coachEngine.evaluate(state);
    debugPrint(
      '[POSE] coaching=${coaching.message} '
      'priority=${coaching.priority} '
      'lighting=${_lastLighting.name} '
      'lightConf=${_lastLightingConf.toStringAsFixed(2)}',
    );

    final overlayData = OverlayData(
      leftEye: leftEye,
      rightEye: rightEye,
      nose: nose,
      leftShoulder: leftShoulder,
      rightShoulder: rightShoulder,
      leftElbow: leftElbow,
      rightElbow: rightElbow,
      leftWrist: leftWrist,
      rightWrist: rightWrist,
      leftHip: leftHip,
      rightHip: rightHip,
      coaching: coaching,
      shotType: shotType,
      eyeConfidence: eyeConf,
      shoulderConfidence: shoulderConf,
    );

    _stabilizeMessage(coaching);

    final mainRect = _toPreviewRect(
      Rect.fromLTRB(
        mainPerson.normalizedBox.left,
        mainPerson.normalizedBox.top,
        mainPerson.normalizedBox.right,
        mainPerson.normalizedBox.bottom,
      ),
      previewSize,
    );

    setState(() {
      _detectedCount = personCount;
      _personCount = personCount;
      _objectCount = 0;
      _currentCoaching = coaching;
      _overlayData = overlayData;
      _detections
        ..clear()
        ..add(
          _DetectionBox(
            rect: mainRect,
            className: 'person',
            confidence: mainPerson.confidence,
            isMainSubject: true,
          ),
        );
    });
  }

  // ─── 메시지 안정화 ──────────────────────────────────
  void _stabilizeMessage(CoachingResult coaching) {
    if (coaching.message == _pendingMessage) {
      _pendingCount++;
    } else {
      _pendingMessage = coaching.message;
      _pendingCount = 1;
    }

    final threshold = _stableMessage.contains('좋은 구도')
        ? _stabilityThreshold * 2
        : _stabilityThreshold;

    if (_pendingCount >= threshold) {
      _stableMessage = _pendingMessage;
    }
  }

  // ─── 일반 모드: 탐지 결과 처리 ──────────────────────────
  void _handleDetections(List<YOLOResult> results) {
    if (!mounted) return;

    final previewSize = _previewSize == Size.zero
        ? MediaQuery.sizeOf(context)
        : _previewSize;
    final selection = _selectMainSubject(results, previewSize);
    final lockedIndex = _matchLockedSubject(results);
    final mainId = _lockedSubject != null
        ? lockedIndex
        : selection.best?.detection.id;
    final currentMain = mainId == null
        ? null
        : _subjectFromResult(results[mainId], previewSize);
    final visibleResults = _lockedSubject != null
        ? (mainId == null ? <YOLOResult>[] : <YOLOResult>[results[mainId]])
        : results;

    setState(() {
      _detectedCount = visibleResults.length;
      _personCount = visibleResults
          .where((result) => result.className.toLowerCase() == 'person')
          .length;
      _objectCount = visibleResults.length - _personCount;
      _guidance = _lockedSubject != null
          ? (currentMain == null ? '고정한 피사체를 찾는 중이에요.' : '피사체 고정 중')
          : selection.guidance;
      _mainSubjectLabel = _lockedSubject != null
          ? (currentMain?.className ?? _lockedSubject?.className)
          : selection.best?.detection.className;
      _currentMainSubject = currentMain;
      if (_lockedSubject != null && currentMain != null) {
        _lockedSubject = currentMain;
      }

      _detections
        ..clear()
        ..addAll(
          visibleResults.asMap().entries.map(
            (entry) => _DetectionBox(
              rect: _lockedSubject != null
                  ? (currentMain?.rect ??
                        _toPreviewRect(entry.value.normalizedBox, previewSize))
                  : _toPreviewRect(entry.value.normalizedBox, previewSize),
              className: entry.value.className,
              confidence: entry.value.confidence,
              isMainSubject: _lockedSubject != null
                  ? true
                  : entry.key == mainId,
            ),
          ),
        );
    });
  }

  Future<void> _setZoom(double zoomLevel) async {
    setState(() {
      _selectedZoom = zoomLevel;
    });

    await _cameraController.setZoomLevel(zoomLevel);
  }

  Future<void> _switchCamera() async {
    await _cameraController.switchCamera();
    if (!mounted) return;

    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _currentZoom = 1.0;
      _selectedZoom = 1.0;
      _detections.clear();
      _detectedCount = 0;
      _personCount = 0;
      _objectCount = 0;
      _guidance = _isPortraitMode ? '' : 'Scene is balanced';
      _mainSubjectLabel = null;
      _currentMainSubject = null;
      _lockedSubject = null;
      _lastLighting = LightingCondition.unknown;
      _lastLightingConf = 0.0;
    });

    await _cameraController.setZoomLevel(1.0);
  }

  Future<void> _captureAndSavePhoto() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          return;
        }
      }

      final bytes = await _cameraController.captureFrame();
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to capture camera frame.');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[CAPTURE] size=${bytes.length} bytes');
      final capturedImage = img.decodeImage(bytes);
      if (capturedImage != null) {
        debugPrint(
          '[CAPTURE] resolution=${capturedImage.width}x${capturedImage.height} size=${bytes.length} bytes',
        );
      }
      await Gal.putImageBytes(bytes, name: 'pozy_$timestamp');

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo saved to gallery.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save photo: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _showFlash = true;
        });

        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          setState(() {
            _showFlash = false;
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController.stop();
    _lightingClassifier.dispose();
    _faceDetector.close();
    super.dispose();
  }

  // ─── UI ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                _previewSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );

                return YOLOView(
                  key: ValueKey('yolo_${_isPortraitMode ? 'pose' : 'detect'}'),
                  controller: _cameraController,
                  modelPath: _isPortraitMode ? poseModelPath : detectModelPath,
                  task: _isPortraitMode ? YOLOTask.pose : YOLOTask.detect,
                  useGpu: false,
                  showNativeUI: false,
                  showOverlays: false,
                  confidenceThreshold: _isPortraitMode
                      ? poseConfidenceThreshold
                      : detectionConfidenceThreshold,
                  streamingConfig: const YOLOStreamingConfig.withPoses(),
                  lensFacing: LensFacing.back,
                  onResult: _isPortraitMode
                      ? _handlePoseDetections
                      : _handleDetections,
                  onZoomChanged: (zoomLevel) {
                    if (!mounted) return;
                    setState(() {
                      _currentZoom = zoomLevel;
                    });
                  },
                );
              },
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x4D000000),
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x66000000),
                    ],
                    stops: [0, 0.2, 0.8, 1],
                  ),
                ),
              ),
            ),
            if (_isPortraitMode)
              IgnorePointer(
                child: CustomPaint(
                  painter: PortraitOverlayPainter(data: _overlayData),
                  size: Size.infinite,
                ),
              )
            else
              IgnorePointer(
                child: CustomPaint(
                  painter: _ThirdsGridPainter(),
                  size: Size.infinite,
                ),
              ),
            if (!_isPortraitMode)
              IgnorePointer(
                child: CustomPaint(
                  painter: _CameraDetectionPainter(detections: _detections),
                  size: Size.infinite,
                ),
              ),
            if (_isPortraitMode) _buildCoachingOverlay(),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: _isPortraitMode
                  ? _buildPortraitTopBar()
                  : _TopCameraBar(
                      onBack: widget.onBack,
                      detectedCount: _detectedCount,
                      personCount: _personCount,
                      objectCount: _objectCount,
                      guidance: _guidance,
                      mainSubjectLabel: _mainSubjectLabel,
                      isFrontCamera: _isFrontCamera,
                      currentZoom: _currentZoom,
                      isLocked: _lockedSubject != null,
                      canLock: _currentMainSubject != null,
                      onToggleLock: _toggleSubjectLock,
                    ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24 + MediaQuery.of(context).padding.bottom,
              child: _BottomCameraControls(
                zoomPresets: _zoomPresets,
                selectedZoom: _selectedZoom,
                isSaving: _isSaving,
                onSelectZoom: _setZoom,
                onGallery: () => widget.onMoveTab(1),
                onCapture: _captureAndSavePhoto,
                onFlipCamera: _switchCamera,
                isPortraitMode: _isPortraitMode,
                onTogglePortraitMode: _togglePortraitMode,
                shotTypeLabel: _isPortraitMode ? _shotTypeLabel() : null,
              ),
            ),
            if (_showFlash) Container(color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ─── 인물 모드 코칭 오버레이 ────────────────────────────
  Widget _buildCoachingOverlay() {
    final isPerfect = _currentCoaching.priority == CoachingPriority.perfect;
    final isCritical = _currentCoaching.priority == CoachingPriority.critical;

    final bgColor = isPerfect
        ? const Color(0xCC22C55E)
        : isCritical
        ? const Color(0xCCEF4444)
        : const Color(0xCC3B82F6);

    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Column(
          key: ValueKey('${_stableMessage}_${_lastLighting.name}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    isPerfect
                        ? Icons.check_circle_outline
                        : isCritical
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _stableMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_lastLighting != LightingCondition.unknown &&
                _lastLightingConf > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _lightingBadgeColor(
                          _lastLighting,
                        ).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wb_sunny_outlined,
                          color: _lightingBadgeColor(_lastLighting),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_lightingLabel(_lastLighting)} '
                          '(${(_lastLightingConf * 100).toStringAsFixed(0)}%)',
                          style: TextStyle(
                            color: _lightingBadgeColor(_lastLighting),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── 인물 모드 상단 바 ──────────────────────────────────
  Widget _buildPortraitTopBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: widget.onBack,
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person, color: Colors.amber, size: 18),
              const SizedBox(width: 6),
              const Text(
                '인물',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_isFrontCamera ? 'Front' : 'Back'} | ${_currentZoom.toStringAsFixed(1)}x',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _shotTypeLabel() {
    if (_currentCoaching.priority == CoachingPriority.critical) {
      return '';
    }
    switch (_overlayData.shotType) {
      case ShotType.closeUp:
        return '클로즈업';
      case ShotType.upperBody:
        return '상반신';
      case ShotType.fullBody:
        return '전신';
      default:
        return '인물 코칭 활성';
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 위젯: 상단 카메라 바 (일반 모드)
// ═══════════════════════════════════════════════════════════════
class _TopCameraBar extends StatelessWidget {
  final VoidCallback onBack;
  final int detectedCount;
  final int personCount;
  final int objectCount;
  final String guidance;
  final String? mainSubjectLabel;
  final bool isFrontCamera;
  final double currentZoom;
  final bool isLocked;
  final bool canLock;
  final VoidCallback onToggleLock;

  const _TopCameraBar({
    required this.onBack,
    required this.detectedCount,
    required this.personCount,
    required this.objectCount,
    required this.guidance,
    required this.mainSubjectLabel,
    required this.isFrontCamera,
    required this.currentZoom,
    required this.isLocked,
    required this.canLock,
    required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
        const Spacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isFrontCamera ? 'Front' : 'Back'} | ${currentZoom.toStringAsFixed(1)}x',
                  ),
                  Text(
                    'Total: $detectedCount  Person: $personCount  Object: $objectCount',
                  ),
                  Text(
                    mainSubjectLabel == null
                        ? guidance
                        : 'Main: $mainSubjectLabel',
                  ),
                  if (mainSubjectLabel != null) Text(guidance),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: canLock || isLocked ? onToggleLock : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isLocked
                              ? const Color(0xFF38BDF8)
                              : Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isLocked
                                ? const Color(0xFF38BDF8)
                                : Colors.white24,
                          ),
                        ),
                        child: Text(
                          isLocked ? '고정 해제' : '피사체 고정',
                          style: TextStyle(
                            color: isLocked
                                ? const Color(0xFF0F172A)
                                : (canLock ? Colors.white : Colors.white54),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 위젯: 하단 카메라 컨트롤
// ═══════════════════════════════════════════════════════════════
class _BottomCameraControls extends StatelessWidget {
  final List<double> zoomPresets;
  final double selectedZoom;
  final bool isSaving;
  final ValueChanged<double> onSelectZoom;
  final VoidCallback onGallery;
  final Future<void> Function() onCapture;
  final Future<void> Function() onFlipCamera;
  final bool isPortraitMode;
  final VoidCallback onTogglePortraitMode;
  final String? shotTypeLabel;

  const _BottomCameraControls({
    required this.zoomPresets,
    required this.selectedZoom,
    required this.isSaving,
    required this.onSelectZoom,
    required this.onGallery,
    required this.onCapture,
    required this.onFlipCamera,
    required this.isPortraitMode,
    required this.onTogglePortraitMode,
    this.shotTypeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isPortraitMode &&
            shotTypeLabel != null &&
            shotTypeLabel!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                shotTypeLabel!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            height: 36,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModePill(
                  label: '일반',
                  icon: Icons.camera_alt_outlined,
                  selected: !isPortraitMode,
                  onTap: isPortraitMode ? onTogglePortraitMode : () {},
                ),
                const SizedBox(width: 4),
                _ModePill(
                  label: '인물',
                  icon: Icons.person_outline,
                  selected: isPortraitMode,
                  onTap: !isPortraitMode ? onTogglePortraitMode : () {},
                ),
              ],
            ),
          ),
        ),
        Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: zoomPresets
                .map(
                  (zoom) => _ZoomPill(
                    label:
                        '${zoom.toStringAsFixed(zoom == zoom.truncateToDouble() ? 0 : 1)}x',
                    selected: (selectedZoom - zoom).abs() < 0.05,
                    onTap: () => onSelectZoom(zoom),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GlassIconButton(
              icon: Icons.photo_library_outlined,
              onTap: onGallery,
              diameter: 48,
            ),
            const SizedBox(width: 48),
            GestureDetector(
              onTap: isSaving ? null : onCapture,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: isSaving
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Color(0xFF333333),
                          ),
                        )
                      : Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0x1A333333),
                              width: 2,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 48),
            _GlassIconButton(
              icon: Icons.flip_camera_ios_outlined,
              onTap: onFlipCamera,
              diameter: 48,
            ),
          ],
        ),
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? const Color(0xFF333333) : Colors.white60,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF333333) : Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double diameter;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.diameter = 40,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: const Color(0x66333333),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x4DFFFFFF), width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: diameter * 0.45),
      ),
    );
  }
}

class _ZoomPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ZoomPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: selected ? 40 : 34,
        height: selected ? 32 : 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF333333) : Colors.white,
            fontSize: selected ? 11 : 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ThirdsGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;

    final dx1 = size.width / 3;
    final dx2 = size.width * 2 / 3;
    final dy1 = size.height / 3;
    final dy2 = size.height * 2 / 3;

    canvas.drawLine(Offset(dx1, 0), Offset(dx1, size.height), paint);
    canvas.drawLine(Offset(dx2, 0), Offset(dx2, size.height), paint);
    canvas.drawLine(Offset(0, dy1), Offset(size.width, dy1), paint);
    canvas.drawLine(Offset(0, dy2), Offset(size.width, dy2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DetectionBox {
  final Rect rect;
  final String className;
  final double confidence;
  final bool isMainSubject;

  const _DetectionBox({
    required this.rect,
    required this.className,
    required this.confidence,
    required this.isMainSubject,
  });

  bool get isPerson => className.toLowerCase() == 'person';
}

class _TrackedSubject {
  final String className;
  final Rect normalizedBox;
  final Rect rect;
  final double confidence;

  const _TrackedSubject({
    required this.className,
    required this.normalizedBox,
    required this.rect,
    required this.confidence,
  });
}

class _CameraDetectionPainter extends CustomPainter {
  final List<_DetectionBox> detections;

  const _CameraDetectionPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    for (final detection in detections) {
      final accent = detection.isMainSubject
          ? const Color(0xFF38BDF8)
          : detection.isPerson
          ? const Color(0xFF4ADE80)
          : const Color(0xFFFB923C);

      final rect = Rect.fromLTRB(
        detection.rect.left.clamp(0.0, size.width),
        detection.rect.top.clamp(0.0, size.height),
        detection.rect.right.clamp(0.0, size.width),
        detection.rect.bottom.clamp(0.0, size.height),
      );

      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = detection.isMainSubject ? 4 : 3,
      );

      canvas.drawRect(
        rect,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = detection.isMainSubject ? 3 : 2,
      );

      final label =
          '${detection.className} ${(detection.confidence * 100).toStringAsFixed(1)}%';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: accent,
            fontSize: detection.isMainSubject ? 13 : 12,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(rect.left, (rect.top - 20).clamp(0.0, size.height - 20)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CameraDetectionPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
