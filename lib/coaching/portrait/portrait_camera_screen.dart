/// 인물 모드 카메라 화면 v2
///
/// ML Kit Pose + Face Detection + 조명 분류
/// 좌표 변환 수정, 구도 기준 수정
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'lighting_classifier.dart';
import 'portrait_overlay_painter.dart';
import 'portrait_scene_state.dart';
import 'portrait_coach_engine.dart';

class PortraitCameraScreen extends StatefulWidget {
  const PortraitCameraScreen({super.key});

  @override
  State<PortraitCameraScreen> createState() => _PortraitCameraScreenState();
}

class _PortraitCameraScreenState extends State<PortraitCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isFrontCamera = false;

  /// 가로 모드 감지를 위한 기기 방향 (0=세로, 90=가로 왼쪽, 270=가로 오른쪽)
  int _deviceOrientationDeg = 0;

  late final PoseDetector _poseDetector;
  late final FaceDetector _faceDetector;

  final PortraitCoachEngine _coachEngine = PortraitCoachEngine();
  final LightingClassifier _lightingClassifier = LightingClassifier();

  int _lightingFrameCount = 0;
  LightingCondition _lastLighting = LightingCondition.unknown;
  double _lastLightingConf = 0.0;

  CoachingResult _currentCoaching = const CoachingResult(
    message: '카메라를 사람에게 향해주세요',
    priority: CoachingPriority.critical,
    confidence: 1.0,
  );

  String _stableMessage = '카메라를 사람에게 향해주세요';
  String _pendingMessage = '';
  int _pendingCount = 0;
  static const int _stabilityThreshold = 5;

  int _fps = 0;
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();

  OverlayData _overlayData = const OverlayData(
    coaching: CoachingResult(
      message: '',
      priority: CoachingPriority.critical,
      confidence: 0.0,
    ),
  );

  // 카메라 센서 회전 정보
  int _sensorOrientation = 90;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDetectors();
    _lightingClassifier.load();
    _initCamera();
  }

  @override
  void didChangeMetrics() {
    // 화면 크기 변화로 가로/세로 전환 감지
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize;
    setState(() {
      // physicalSize는 회전 전과 같은 방향으로 보고될 수 있으므로
      // 가로 여부만 판별하고 방향은 90으로 통일
      _deviceOrientationDeg = size.width > size.height ? 90 : 0;
    });
  }

  void _initDetectors() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.base,
      ),
    );
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final targetDirection = _isFrontCamera
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final selectedCamera = cameras.firstWhere(
      (c) => c.lensDirection == targetDirection,
      orElse: () => cameras.first,
    );

    _sensorOrientation = selectedCamera.sensorOrientation;

    _cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      await _cameraController!.startImageStream(_processImage);
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
    }
  }

  // ─── 좌표 변환 핵심 ───────────────────────────

  /// 센서 방향 + 기기 방향을 합산한 실효 회전각(degree)
  int get _effectiveRotationDeg {
    if (_isFrontCamera) {
      return (_sensorOrientation + _deviceOrientationDeg) % 360;
    }
    return (_sensorOrientation - _deviceOrientationDeg + 360) % 360;
  }

  /// ML Kit 좌표를 화면 정규화 좌표(0~1)로 변환
  /// 실효 회전각(센서 + 기기 방향)을 기반으로 가로세로를 결정합니다.
  Offset? _transformLandmark(double lmX, double lmY, double rawW, double rawH) {
    final int effRot = _effectiveRotationDeg;
    final bool isRotated = effRot == 90 || effRot == 270;
    final double coordW = isRotated ? rawH : rawW;
    final double coordH = isRotated ? rawW : rawH;

    double nx = lmX / coordW;
    double ny = lmY / coordH;

    // 전면 카메라는 좌우 반전
    if (_isFrontCamera) {
      nx = 1.0 - nx;
    }

    return Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
  }

  /// Face boundingBox를 정규화 좌표로 변환
  Rect _transformFaceRect(Rect bbox, double rawW, double rawH) {
    final int effRot = _effectiveRotationDeg;
    final bool isRotated = effRot == 90 || effRot == 270;
    final double coordW = isRotated ? rawH : rawW;
    final double coordH = isRotated ? rawW : rawH;

    double left = bbox.left / coordW;
    double top = bbox.top / coordH;
    double right = bbox.right / coordW;
    double bottom = bbox.bottom / coordH;

    if (_isFrontCamera) {
      final tmp = left;
      left = 1.0 - right;
      right = 1.0 - tmp;
    }

    return Rect.fromLTRB(
      left.clamp(0.0, 1.0),
      top.clamp(0.0, 1.0),
      right.clamp(0.0, 1.0),
      bottom.clamp(0.0, 1.0),
    );
  }

  // ─── 프레임 처리 ──────────────────────────────

  Future<void> _processImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _convertToInputImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }

      final poses = await _poseDetector.processImage(inputImage);
      final faces = await _faceDetector.processImage(inputImage);

      final rawW = image.width.toDouble();
      final rawH = image.height.toDouble();

      // ─── 포즈 분석 ──────────────────────────
      int personCount = poses.length;
      ShotType shotType = ShotType.unknown;
      double? shoulderAngle;
      double? leftArmGap;
      double? rightArmGap;
      Offset? eyeMidpoint;
      final croppedJointList = <String>{};
      double headroomRatio = 0.0;
      double footSpaceRatio = 0.0;
      double shoulderConf = 0.0;
      double elbowConf = 0.0;
      double eyeConf = 0.0;

      // 오버레이용 키포인트
      Offset? olLeftEye, olRightEye, olNose;
      Offset? olLeftShoulder, olRightShoulder;
      Offset? olLeftElbow, olRightElbow;
      Offset? olLeftWrist, olRightWrist;
      Offset? olLeftHip, olRightHip;

      if (poses.isNotEmpty) {
        // 여러 인물이 감지된 경우 화면 중심에 가장 가깝고 가장 큰 포즈를 선택
        final pose = _selectMainPose(poses, rawW, rawH);
        final lm = pose.landmarks;

        // 키포인트를 화면 좌표로 변환하는 헬퍼
        Offset? toScreen(PoseLandmarkType type) {
          final p = lm[type];
          if (p == null || p.likelihood < 0.5) return null;
          return _transformLandmark(p.x, p.y, rawW, rawH);
        }

        double conf(PoseLandmarkType type) {
          return lm[type]?.likelihood ?? 0.0;
        }

        // 키포인트 추출
        olLeftEye = toScreen(PoseLandmarkType.leftEye);
        olRightEye = toScreen(PoseLandmarkType.rightEye);
        olNose = toScreen(PoseLandmarkType.nose);
        olLeftShoulder = toScreen(PoseLandmarkType.leftShoulder);
        olRightShoulder = toScreen(PoseLandmarkType.rightShoulder);
        olLeftElbow = toScreen(PoseLandmarkType.leftElbow);
        olRightElbow = toScreen(PoseLandmarkType.rightElbow);
        olLeftWrist = toScreen(PoseLandmarkType.leftWrist);
        olRightWrist = toScreen(PoseLandmarkType.rightWrist);
        olLeftHip = toScreen(PoseLandmarkType.leftHip);
        olRightHip = toScreen(PoseLandmarkType.rightHip);

        // 어깨 각도
        if (olLeftShoulder != null && olRightShoulder != null) {
          shoulderConf = math.min(
            conf(PoseLandmarkType.leftShoulder),
            conf(PoseLandmarkType.rightShoulder),
          );
          if (shoulderConf > 0.5) {
            final dy = olRightShoulder.dy - olLeftShoulder.dy;
            final dx = olRightShoulder.dx - olLeftShoulder.dx;
            shoulderAngle = math.atan2(dy, dx) * 180 / math.pi;
          }
        }

        // 팔-몸통 간격
        if (olLeftElbow != null &&
            olLeftShoulder != null &&
            olLeftHip != null) {
          elbowConf = conf(PoseLandmarkType.leftElbow);
          if (elbowConf > 0.5) {
            final bodyX = (olLeftShoulder.dx + olLeftHip.dx) / 2;
            leftArmGap = (olLeftElbow.dx - bodyX).abs();
          }
        }
        if (olRightElbow != null &&
            olRightShoulder != null &&
            olRightHip != null) {
          final rConf = conf(PoseLandmarkType.rightElbow);
          if (rConf > 0.5) {
            elbowConf = math.max(elbowConf, rConf);
            final bodyX = (olRightShoulder.dx + olRightHip.dx) / 2;
            rightArmGap = (olRightElbow.dx - bodyX).abs();
          }
        }

        // 눈 중심점 (이미 정규화된 좌표)
        if (olLeftEye != null && olRightEye != null) {
          eyeConf = math.min(
            conf(PoseLandmarkType.leftEye),
            conf(PoseLandmarkType.rightEye),
          );
          eyeMidpoint = Offset(
            (olLeftEye.dx + olRightEye.dx) / 2,
            (olLeftEye.dy + olRightEye.dy) / 2,
          );
        }

        // 샷 타입 + 헤드룸 + 풋스페이스
        double minY = 1.0;
        double maxY = 0.0;
        for (final entry in lm.entries) {
          if (entry.value.likelihood > 0.5) {
            final pt = _transformLandmark(
              entry.value.x,
              entry.value.y,
              rawW,
              rawH,
            );
            if (pt != null) {
              minY = math.min(minY, pt.dy);
              maxY = math.max(maxY, pt.dy);
            }
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

        // 관절 크로핑 체크
        const edgeMargin = 0.03;
        bool ptAtEdge(Offset? pt) =>
            pt != null &&
            (pt.dx < edgeMargin ||
                pt.dx > 1 - edgeMargin ||
                pt.dy < edgeMargin ||
                pt.dy > 1 - edgeMargin);

        Offset? toSc(PoseLandmarkType t) {
          final p = lm[t];
          if (p == null || p.likelihood < 0.3) return null;
          return _transformLandmark(p.x, p.y, rawW, rawH);
        }

        if (ptAtEdge(toSc(PoseLandmarkType.leftWrist)) ||
            ptAtEdge(toSc(PoseLandmarkType.rightWrist))) {
          croppedJointList.add('wrist');
        }
        if (ptAtEdge(toSc(PoseLandmarkType.leftElbow)) ||
            ptAtEdge(toSc(PoseLandmarkType.rightElbow))) {
          croppedJointList.add('elbow');
        }
        if (ptAtEdge(toSc(PoseLandmarkType.leftKnee)) ||
            ptAtEdge(toSc(PoseLandmarkType.rightKnee))) {
          croppedJointList.add('knee');
        }
        if (ptAtEdge(toSc(PoseLandmarkType.leftAnkle)) ||
            ptAtEdge(toSc(PoseLandmarkType.rightAnkle))) {
          croppedJointList.add('ankle');
        }
      }

      // ─── 얼굴 분석 ──────────────────────────
      double? faceYaw, facePitch, faceRoll;
      double? smileProb, leftEyeOpen, rightEyeOpen;

      if (faces.isNotEmpty) {
        // 여러 얼굴이 감지된 경우 메인 포즈 상단(얼굴 위치)에 가장 가까운 얼굴 선택
        final face = _selectMainFace(faces, rawW, rawH,
            olNose ?? olLeftEye ?? olRightEye);
        faceYaw = face.headEulerAngleY;
        facePitch = face.headEulerAngleX;
        faceRoll = face.headEulerAngleZ;
        smileProb = face.smilingProbability;
        leftEyeOpen = face.leftEyeOpenProbability;
        rightEyeOpen = face.rightEyeOpenProbability;
      }

      // ─── 조명 분석 (10프레임마다) ─────────────
      _lightingFrameCount++;
      if (_lightingClassifier.isLoaded &&
          faces.isNotEmpty &&
          _lightingFrameCount % 10 == 0) {
        final face = faces.first;
        final normRect = _transformFaceRect(face.boundingBox, rawW, rawH);

        final faceCrop = _lightingClassifier.prepareFaceCrop(
          imageBytes: image.planes.first.bytes,
          imageWidth: image.width,
          imageHeight: image.height,
          faceLeft: normRect.left,
          faceTop: normRect.top,
          faceWidth: normRect.width,
          faceHeight: normRect.height,
        );

        if (faceCrop != null) {
          final result = _lightingClassifier.classify(faceCrop);
          _lastLighting = result.condition;
          _lastLightingConf = result.confidence;
        }
      }

      // ─── SceneState 조합 ──────────────────────
      final state = PortraitSceneState(
        personCount: personCount,
        shotType: shotType,
        faceYaw: faceYaw,
        facePitch: facePitch,
        faceRoll: faceRoll,
        smileProbability: smileProb,
        leftEyeOpenProb: leftEyeOpen,
        rightEyeOpenProb: rightEyeOpen,
        shoulderAngleDeg: shoulderAngle,
        leftArmBodyGap: leftArmGap,
        rightArmBodyGap: rightArmGap,
        eyeMidpoint: eyeMidpoint,
        croppedJoints: croppedJointList.toList(),
        headroomRatio: headroomRatio,
        footSpaceRatio: footSpaceRatio,
        shoulderConfidence: shoulderConf,
        elbowConfidence: elbowConf,
        eyeConfidence: eyeConf,
        lightingCondition: _lastLighting,
        lightingConfidence: _lastLightingConf,
      );

      // ─── 코칭 ────────────────────────────────
      final coaching = _coachEngine.evaluate(state);

      _overlayData = OverlayData(
        leftEye: olLeftEye,
        rightEye: olRightEye,
        nose: olNose,
        leftShoulder: olLeftShoulder,
        rightShoulder: olRightShoulder,
        leftElbow: olLeftElbow,
        rightElbow: olRightElbow,
        leftWrist: olLeftWrist,
        rightWrist: olRightWrist,
        leftHip: olLeftHip,
        rightHip: olRightHip,
        coaching: coaching,
        shotType: state.shotType,
        eyeConfidence: eyeConf,
        shoulderConfidence: shoulderConf,
      );

      _stabilizeMessage(coaching);

      _frameCount++;
      final now = DateTime.now();
      if (now.difference(_lastFpsTime).inMilliseconds > 1000) {
        _fps = _frameCount;
        _frameCount = 0;
        _lastFpsTime = now;
      }

      if (mounted) {
        setState(() => _currentCoaching = coaching);
      }
    } catch (e) {
      debugPrint('프레임 처리 에러: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // ─── InputImage 변환 ─────────────────────────

  InputImage? _convertToInputImage(CameraImage image) {
    final camera = _cameraController?.description;
    if (camera == null) return null;

    // 실효 회전각 = 센서 방향 - 기기 방향(후면) 또는 + 기기 방향(전면)
    // 가로 모드에서도 ML Kit이 올바른 회전을 적용하도록 보정합니다.
    final rotation =
        InputImageRotationValue.fromRawValue(_effectiveRotationDeg) ??
        InputImageRotation.rotation0deg;

    final bytes = _concatenatePlanes(image.planes);
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    int totalBytes = 0;
    for (final plane in planes) {
      totalBytes += plane.bytes.length;
    }
    final result = Uint8List(totalBytes);
    int offset = 0;
    for (final plane in planes) {
      result.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }
    return result;
  }

  // ─── 메시지 안정화 ────────────────────────────

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

  // ─── 다중 인물/얼굴 선택 헬퍼 ─────────────────────────

  /// 여러 포즈 중 화면 중심에 가깝고 가장 큰 포즈를 반환합니다.
  Pose _selectMainPose(List<Pose> poses, double rawW, double rawH) {
    if (poses.length == 1) return poses.first;

    Pose? best;
    double bestScore = double.negativeInfinity;
    for (final pose in poses) {
      // 키포인트 bounding box 계산
      double minX = double.infinity, minY = double.infinity;
      double maxX = 0, maxY = 0;
      int count = 0;
      for (final lm in pose.landmarks.values) {
        if (lm.likelihood > 0.4) {
          final pt = _transformLandmark(lm.x, lm.y, rawW, rawH);
          if (pt != null) {
            minX = math.min(minX, pt.dx);
            minY = math.min(minY, pt.dy);
            maxX = math.max(maxX, pt.dx);
            maxY = math.max(maxY, pt.dy);
            count++;
          }
        }
      }
      if (count == 0) continue;
      final area = (maxX - minX) * (maxY - minY);
      final centerDist =
          ((minX + maxX) / 2 - 0.5).abs() + ((minY + maxY) / 2 - 0.5).abs();
      final score = area * 1.5 - centerDist * 0.4;
      if (score > bestScore) {
        bestScore = score;
        best = pose;
      }
    }
    return best ?? poses.first;
  }

  /// 여러 얼굴 중 메인 포즈의 얼굴 위치에 가장 가까운 얼굴을 반환합니다.
  Face _selectMainFace(
      List<Face> faces, double rawW, double rawH, Offset? poseHeadPos) {
    if (faces.length == 1) return faces.first;

    if (poseHeadPos == null) {
      // 포즈 정보 없으면 가장 큰 얼굴 선택
      return faces.reduce((a, b) =>
          (a.boundingBox.width * a.boundingBox.height) >=
                  (b.boundingBox.width * b.boundingBox.height)
              ? a
              : b);
    }

    Face? best;
    double bestDist = double.infinity;
    for (final face in faces) {
      final faceCenter = _transformFaceRect(face.boundingBox, rawW, rawH).center;
      final dist = (faceCenter - poseHeadPos).distance;
      if (dist < bestDist) {
        bestDist = dist;
        best = face;
      }
    }
    return best ?? faces.first;
  }

  // ─── 카메라 전환 ──────────────────────────────

  Future<void> _switchCamera() async {
    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isInitialized = false;
    });
    await _initCamera();
  }

  // ─── 촬영 ────────────────────────────────────

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      await _cameraController!.stopImageStream();
      final xFile = await _cameraController!.takePicture();
      debugPrint('사진 저장: ${xFile.path}');
      if (mounted) {
        await _cameraController!.startImageStream(_processImage);
      }
    } catch (e) {
      debugPrint('촬영 에러: $e');
      if (mounted) {
        try {
          await _cameraController!.startImageStream(_processImage);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _poseDetector.close();
    _faceDetector.close();
    _lightingClassifier.dispose();
    super.dispose();
  }

  // ─── UI ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 카메라 프리뷰
          if (_isInitialized &&
              _cameraController != null &&
              _cameraController!.value.isInitialized)
            CameraPreview(_cameraController!)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // 시각적 가이드 오버레이
          CustomPaint(
            size: Size.infinite,
            painter: PortraitOverlayPainter(data: _overlayData),
          ),

          // 코칭 메시지
          _buildCoachingOverlay(),

          // 상단 바
          _buildTopBar(),

          // 하단 컨트롤
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildCoachingOverlay() {
    final isPerfect = _currentCoaching.priority == CoachingPriority.perfect;
    final isCritical = _currentCoaching.priority == CoachingPriority.critical;

    final bgColor = isPerfect
        ? const Color(0xCC22C55E)
        : isCritical
        ? const Color(0xCCEF4444)
        : const Color(0xCC3B82F6);

    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 20,
      right: 20,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(_stableMessage),
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
      ),
    );
  }

  Widget _buildTopBar() {
    // 조명 상태 텍스트
    String lightingText = '';
    Color lightingColor = Colors.white70;
    if (_lastLighting == LightingCondition.side) {
      lightingText = '측광';
      lightingColor = Colors.amber;
    } else if (_lastLighting == LightingCondition.back) {
      lightingText = '역광';
      lightingColor = Colors.redAccent;
    } else if (_lastLighting == LightingCondition.normal) {
      lightingText = '정상광';
      lightingColor = Colors.greenAccent;
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          // 인물 모드 + 조명 상태
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
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
                if (lightingText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(width: 1, height: 14, color: Colors.white24),
                  const SizedBox(width: 8),
                  Icon(Icons.wb_sunny_outlined, color: lightingColor, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    lightingText,
                    style: TextStyle(
                      color: lightingColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // FPS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_fps fps',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 30,
      left: 0,
      right: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 샷 타입 표시
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _shotTypeLabel(),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 48),
              const SizedBox(width: 32),
              GestureDetector(
                onTap: _capturePhoto,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Center(
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 32),
              GestureDetector(
                onTap: _switchCamera,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.flip_camera_ios,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shotTypeLabel() {
    if (_currentCoaching.priority == CoachingPriority.critical) {
      return '';
    }

    switch (_overlayData.shotType) {
      case ShotType.closeUp:
        return '클로즈업';
      case ShotType.headShot:
        return '헤드샷';
      case ShotType.upperBody:
        return '상반신';
      case ShotType.waistShot:
        return '허리샷';
      case ShotType.fullBody:
        return '전신';
      default:
        return '인물 코칭 활성';
    }
  }
}
