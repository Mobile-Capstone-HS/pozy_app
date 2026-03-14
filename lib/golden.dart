import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/services.dart';

List<CameraDescription> cameras = [];

// ---------------------------------------------------------
// 1. MathStabilizer
// ---------------------------------------------------------
class MathStabilizer {
  final double alpha;
  final double stickyMarginRatio;

  double? smoothedX;
  double? smoothedY;
  Point<int>? currentBestPoint;

  MathStabilizer({this.alpha = 0.25, this.stickyMarginRatio = 0.08});

  Point<int> update(double rawX, double rawY) {
    if (smoothedX == null || smoothedY == null) {
      smoothedX = rawX;
      smoothedY = rawY;
    } else {
      smoothedX = smoothedX! * (1 - alpha) + rawX * alpha;
      smoothedY = smoothedY! * (1 - alpha) + rawY * alpha;
    }
    return Point<int>(smoothedX!.toInt(), smoothedY!.toInt());
  }

  Map<String, dynamic> getStickyTarget(List<Point<int>> intersections, int screenWidth) {
    if (smoothedX == null || smoothedY == null || intersections.isEmpty) {
      return {'point': null, 'distance': double.infinity};
    }

    if (currentBestPoint == null) {
      double minDist = double.infinity;
      for (var p in intersections) {
        double dist = sqrt(pow(smoothedX! - p.x, 2) + pow(smoothedY! - p.y, 2));
        if (dist < minDist) {
          minDist = dist;
          currentBestPoint = p;
        }
      }
    } else {
      double currDist = sqrt(
        pow(smoothedX! - currentBestPoint!.x, 2) + pow(smoothedY! - currentBestPoint!.y, 2),
      );
      double stickyMargin = screenWidth * stickyMarginRatio;
      for (var p in intersections) {
        double newDist = sqrt(pow(smoothedX! - p.x, 2) + pow(smoothedY! - p.y, 2));
        if (newDist < currDist - stickyMargin) {
          currentBestPoint = p;
          currDist = newDist;
        }
      }
    }

    double finalDist = sqrt(
      pow(smoothedX! - currentBestPoint!.x, 2) + pow(smoothedY! - currentBestPoint!.y, 2),
    );
    return {'point': currentBestPoint, 'distance': finalDist};
  }

  void reset() {
    smoothedX = null;
    smoothedY = null;
    currentBestPoint = null;
  }
}

// ---------------------------------------------------------
// 2. GoldenCoach
// ---------------------------------------------------------
class GoldenCoach {
  static const double perfectThresholdRatio = 0.1;
  static const double phi = 1.6180339887;
  static const double ratio = 1 / phi;

  int width = 0;
  int height = 0;
  List<Point<int>> intersections = [];

  void calculateGrid(int screenWidth, int screenHeight) {
    width = screenWidth;
    height = screenHeight;

    double xr3 = width.toDouble(), xl3 = 0, yt3 = 0, yb3 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr3 - xl3, h = yb3 - yt3;
      int dir = i % 4;
      if (dir == 0) xl3 += w * ratio;
      else if (dir == 1) yt3 += h * ratio;
      else if (dir == 2) xr3 -= w * ratio;
      else yb3 -= h * ratio;
    }

    double xr1 = width.toDouble(), xl1 = 0, yt1 = 0, yb1 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr1 - xl1, h = yb1 - yt1;
      int dir = [0, 3, 2, 1][i % 4];
      if (dir == 0) xl1 += w * ratio;
      else if (dir == 1) yt1 += h * ratio;
      else if (dir == 2) xr1 -= w * ratio;
      else yb1 -= h * ratio;
    }

    double xr2 = width.toDouble(), xl2 = 0, yt2 = 0, yb2 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr2 - xl2, h = yb2 - yt2;
      int dir = [2, 1, 0, 3][i % 4];
      if (dir == 0) xl2 += w * ratio;
      else if (dir == 1) yt2 += h * ratio;
      else if (dir == 2) xr2 -= w * ratio;
      else yb2 -= h * ratio;
    }

    double xr0 = width.toDouble(), xl0 = 0, yt0 = 0, yb0 = height.toDouble();
    for (int i = 0; i < 8; i++) {
      double w = xr0 - xl0, h = yb0 - yt0;
      int dir = [2, 3, 0, 1][i % 4];
      if (dir == 0) xl0 += w * ratio;
      else if (dir == 1) yt0 += h * ratio;
      else if (dir == 2) xr0 -= w * ratio;
      else yb0 -= h * ratio;
    }

    intersections = [
      Point<int>((xl0 + xr0) ~/ 2, (yt0 + yb0) ~/ 2),
      Point<int>((xl1 + xr1) ~/ 2, (yt1 + yb1) ~/ 2),
      Point<int>((xl2 + xr2) ~/ 2, (yt2 + yb2) ~/ 2),
      Point<int>((xl3 + xr3) ~/ 2, (yt3 + yb3) ~/ 2),
    ];
  }

  bool isPerfect(double distance) => distance < (width * perfectThresholdRatio);
}

// ---------------------------------------------------------
// 3. GoldenCoachPainter
// ---------------------------------------------------------
class GoldenCoachPainter extends CustomPainter {
  final GoldenCoach coach;
  final Point<int>? currentSubjectPos;
  final Point<int>? targetPos;
  final bool isPerfect;
  final Rect? personBoundingBox;

  GoldenCoachPainter({
    required this.coach,
    this.currentSubjectPos,
    this.targetPos,
    this.isPerfect = false,
    this.personBoundingBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    coach.calculateGrid(size.width.toInt(), size.height.toInt());

    final Paint spiralLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final Paint spiralShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (coach.intersections.isNotEmpty) {
      int activeTargetIdx = 3;
      if (targetPos != null) {
        for (int i = 0; i < coach.intersections.length; i++) {
          final pt = coach.intersections[i];
          if (pt.x == targetPos!.x && pt.y == targetPos!.y) {
            activeTargetIdx = i;
            break;
          }
        }
      }

      void drawSpiralArc(Rect rect, double startAngle, double sweepAngle) {
        canvas.drawArc(rect, startAngle, sweepAngle, false, spiralShadowPaint);
        canvas.drawArc(rect, startAngle, sweepAngle, false, spiralLinePaint);
      }

      void drawSpiralRect(Rect rect) {
        canvas.drawRect(rect, spiralShadowPaint);
        canvas.drawRect(rect, spiralLinePaint);
      }

      double xMin = 0, yMin = 0, xMax = size.width, yMax = size.height;
      double R = GoldenCoach.ratio;

      for (int i = 0; i < 8; i++) {
        double w = xMax - xMin, h = yMax - yMin;
        if (w <= 2 || h <= 2) break;

        int step = i % 4;
        int dir = 0;
        if (activeTargetIdx == 3) dir = step;
        else if (activeTargetIdx == 1) dir = [0, 3, 2, 1][step];
        else if (activeTargetIdx == 2) dir = [2, 1, 0, 3][step];
        else if (activeTargetIdx == 0) dir = [2, 3, 0, 1][step];

        if (dir == 0) {
          drawSpiralRect(Rect.fromLTRB(xMin, yMin, xMin + w * R, yMax));
          double cx = xMin + w * R;
          double cy = (activeTargetIdx == 3 || activeTargetIdx == 2) ? yMax : yMin;
          double startAngle = (activeTargetIdx == 3 || activeTargetIdx == 2) ? pi : pi / 2;
          drawSpiralArc(
            Rect.fromCenter(center: Offset(cx, cy), width: w * R * 2, height: h * 2),
            startAngle, pi / 2 * (activeTargetIdx <= 1 ? -1 : 1),
          );
          xMin += w * R;
        } else if (dir == 1) {
          drawSpiralRect(Rect.fromLTRB(xMin, yMin, xMax, yMin + h * R));
          double cx = (activeTargetIdx == 3 || activeTargetIdx == 1) ? xMin : xMax;
          double cy = yMin + h * R;
          double startAngle = (activeTargetIdx == 3 || activeTargetIdx == 1) ? -pi / 2 : pi;
          drawSpiralArc(
            Rect.fromCenter(center: Offset(cx, cy), width: w * 2, height: h * R * 2),
            startAngle, pi / 2 * (activeTargetIdx == 0 || activeTargetIdx == 3 ? 1 : -1),
          );
          yMin += h * R;
        } else if (dir == 2) {
          drawSpiralRect(Rect.fromLTRB(xMin + w * (1 - R), yMin, xMax, yMax));
          double cx = xMin + w * (1 - R);
          double cy = (activeTargetIdx == 3 || activeTargetIdx == 2) ? yMin : yMax;
          double startAngle = (activeTargetIdx == 3 || activeTargetIdx == 2) ? 0 : -pi / 2;
          drawSpiralArc(
            Rect.fromCenter(center: Offset(cx, cy), width: w * R * 2, height: h * 2),
            startAngle, pi / 2 * (activeTargetIdx <= 1 ? -1 : 1),
          );
          xMax -= w * R;
        } else if (dir == 3) {
          drawSpiralRect(Rect.fromLTRB(xMin, yMin + h * (1 - R), xMax, yMax));
          double cx = (activeTargetIdx == 3 || activeTargetIdx == 1) ? xMax : xMin;
          double cy = yMin + h * (1 - R);
          double startAngle = (activeTargetIdx == 3 || activeTargetIdx == 1) ? pi / 2 : 0;
          drawSpiralArc(
            Rect.fromCenter(center: Offset(cx, cy), width: w * 2, height: h * R * 2),
            startAngle, pi / 2 * (activeTargetIdx == 0 || activeTargetIdx == 3 ? 1 : -1),
          );
          yMax -= h * R;
        }
      }

      const textStyle = TextStyle(
        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500,
        shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
      );
      void drawText(String text, Offset position) {
        final tp = TextPainter(text: TextSpan(text: text, style: textStyle), textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, position);
      }

      drawText("Vortex", Offset(coach.intersections[0].x.toDouble() + 5, coach.intersections[0].y.toDouble() + 5));
      drawText("Vortex", Offset(coach.intersections[1].x.toDouble() - 45, coach.intersections[1].y.toDouble() + 5));
      drawText("Vortex", Offset(coach.intersections[2].x.toDouble() + 5, coach.intersections[2].y.toDouble() - 20));
      drawText("Vortex", Offset(coach.intersections[3].x.toDouble() - 45, coach.intersections[3].y.toDouble() - 20));
    }

    if (personBoundingBox != null) {
      final boxShadowPaint = Paint()..color = Colors.black.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 3.0;
      final boxPaint = Paint()..color = Colors.cyanAccent.withOpacity(0.8)..style = PaintingStyle.stroke..strokeWidth = 2.0;
      canvas.drawRect(personBoundingBox!, boxShadowPaint);
      canvas.drawRect(personBoundingBox!, boxPaint);

      final tp = TextPainter(
        text: const TextSpan(text: "Person Detected", style: TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 3)])),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(personBoundingBox!.left, personBoundingBox!.top - 20));
    }

    if (currentSubjectPos != null && targetPos != null) {
      Color stateColor = isPerfect ? Colors.greenAccent : Colors.amber;
      final connectionPaint = Paint()..color = stateColor..style = PaintingStyle.stroke..strokeWidth = isPerfect ? 3.0 : 2.0;
      final subjectPaint = Paint()..color = isPerfect ? Colors.greenAccent : Colors.redAccent..style = PaintingStyle.fill;

      canvas.drawLine(
        Offset(currentSubjectPos!.x.toDouble(), currentSubjectPos!.y.toDouble()),
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        connectionPaint,
      );
      canvas.drawCircle(Offset(currentSubjectPos!.x.toDouble(), currentSubjectPos!.y.toDouble()), isPerfect ? 8.0 : 6.0, subjectPaint);
      canvas.drawCircle(Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()), 8.0, connectionPaint);

      if (isPerfect) {
        final tp = TextPainter(
          text: const TextSpan(text: "PERFECT!", style: TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, const Offset(20, 100));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---------------------------------------------------------
// 4. GoldenRatioScreen
// ---------------------------------------------------------
class GoldenRatioScreen extends StatefulWidget {
  const GoldenRatioScreen({super.key});

  @override
  State<GoldenRatioScreen> createState() => _GoldenRatioScreenState();
}

class _GoldenRatioScreenState extends State<GoldenRatioScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base),
  );

  bool _isDetecting = false;
  bool _isProcessingFrame = false;
  String? _screenError;

  final MathStabilizer _stabilizer = MathStabilizer();
  final GoldenCoach _coach = GoldenCoach();

  Point<int>? _smoothPos;
  Point<int>? _targetPos;
  bool _isPerfect = false;
  Rect? _personBoundingBox;

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    if (cameras.isNotEmpty) {
      _initializeCamera();
    } else {
      _screenError = "카메라를 찾을 수 없습니다.";
    }
  }

  void _initializeCamera() {
    _controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isCameraReady = true);

      try {
        _controller!.startImageStream((CameraImage image) {
          if (!_isDetecting) {
            _isDetecting = true;
            _processMLKit(image).then((_) => _isDetecting = false);
          }
        });
      } catch (e) {
        if (mounted) setState(() => _screenError = '카메라 스트림 오류:\n$e');
      }
    }).catchError((e) {
      if (mounted) setState(() => _screenError = '카메라 초기화 실패:\n$e');
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = cameras[0];
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Theme.of(context).platform == TargetPlatform.android) {
      var rotationCompensation = _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    // Android YUV420 → NV21 변환 (ML Kit은 NV21을 기대)
    final Uint8List bytes;
    final InputImageFormat format;

    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length == 3) {
      // YUV420 → NV21: Y plane 그대로 + U/V interleave
      final int width = image.width;
      final int height = image.height;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      final nv21 = Uint8List(width * height + (width * height / 2).round());

      // Y plane 복사
      final yPlane = image.planes[0];
      int yIndex = 0;
      for (int row = 0; row < height; row++) {
        nv21.setRange(yIndex, yIndex + width, yPlane.bytes, row * yPlane.bytesPerRow);
        yIndex += width;
      }

      // V, U interleave (NV21: V먼저)
      int uvIndex = width * height;
      for (int row = 0; row < height ~/ 2; row++) {
        for (int col = 0; col < width ~/ 2; col++) {
          final int uvOffset = row * uvRowStride + col * uvPixelStride;
          nv21[uvIndex++] = image.planes[2].bytes[uvOffset]; // V
          nv21[uvIndex++] = image.planes[1].bytes[uvOffset]; // U
        }
      }

      bytes = nv21;
      format = InputImageFormat.nv21;
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      bytes = image.planes[0].bytes;
      format = InputImageFormat.bgra8888;
    } else {
      return null;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.width,
      ),
    );
  }

  Future<void> _processMLKit(CameraImage image) async {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final poses = await _poseDetector.processImage(inputImage);
      if (!mounted) return;

      final Size screenSize = MediaQuery.of(context).size;

      if (poses.isEmpty) {
        _stabilizer.reset();
        setState(() {
          _smoothPos = null;
          _targetPos = null;
          _isPerfect = false;
          _personBoundingBox = null;
        });
        return;
      }

      final pose = poses.first;

      final imageWidth = inputImage.metadata?.size.width ?? image.width.toDouble();
      final imageHeight = inputImage.metadata?.size.height ?? image.height.toDouble();

      // 회전 후 실제 이미지 방향 결정
      final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
      final isLandscape = imageWidth > imageHeight;
      final double actualW = (isLandscape && isPortrait) ? imageHeight : imageWidth;
      final double actualH = (isLandscape && isPortrait) ? imageWidth : imageHeight;

      // CameraPreview와 동일한 스케일/오프셋 계산
      final double screenAR = screenSize.width / screenSize.height;
      final double imageAR = actualW / actualH;
      double scaleX, offsetX = 0, offsetY = 0;

      if (imageAR > screenAR) {
        scaleX = screenSize.height / actualH;
        offsetX = (actualW * scaleX - screenSize.width) / 2;
      } else {
        scaleX = screenSize.width / actualW;
        offsetY = (actualH * scaleX - screenSize.height) / 2;
      }

      // 피사체 위치: 코 → 얼굴 평균 → 어깨 순으로 fallback
      double targetX = actualW / 2, targetY = actualH / 2;

      final nose = pose.landmarks[PoseLandmarkType.nose];
      if (nose != null && nose.likelihood > 0.5) {
        targetX = nose.x;
        targetY = nose.y;
      } else {
        final facePoints = [
          pose.landmarks[PoseLandmarkType.leftEye],
          pose.landmarks[PoseLandmarkType.rightEye],
          pose.landmarks[PoseLandmarkType.leftEar],
          pose.landmarks[PoseLandmarkType.rightEar],
        ].where((lm) => lm != null && lm.likelihood > 0.5).toList();

        if (facePoints.isNotEmpty) {
          targetX = facePoints.map((lm) => lm!.x).reduce((a, b) => a + b) / facePoints.length;
          targetY = facePoints.map((lm) => lm!.y).reduce((a, b) => a + b) / facePoints.length;
        } else {
          final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
          final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
          if (ls != null && rs != null) {
            targetX = (ls.x + rs.x) / 2;
            final shoulderDist = (ls.x - rs.x).abs();
            targetY = ((ls.y + rs.y) / 2) - (shoulderDist * 0.5);
          }
        }
      }

      final double rawX = (targetX * scaleX) - offsetX;
      final double rawY = (targetY * scaleX) - offsetY;

      // 바운딩 박스 (어깨~엉덩이 기준)
      Rect? boundingBox;
      final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
      final lh = pose.landmarks[PoseLandmarkType.leftHip];
      final rh = pose.landmarks[PoseLandmarkType.rightHip];
      if (ls != null && rs != null && lh != null && rh != null) {
        double minX = [ls.x, rs.x, lh.x, rh.x].reduce(min);
        double maxX = [ls.x, rs.x, lh.x, rh.x].reduce(max);
        double sw = maxX - minX;
        minX -= sw * 0.2;
        maxX += sw * 0.2;
        double minY = min([ls.y, rs.y].reduce(min) - sw * 0.5, nose?.y ?? ls.y);
        double maxY = [lh.y, rh.y].reduce(max);
        boundingBox = Rect.fromLTRB(
          ((minX * scaleX) - offsetX).clamp(0, screenSize.width),
          ((minY * scaleX) - offsetY).clamp(0, screenSize.height),
          ((maxX * scaleX) - offsetX).clamp(0, screenSize.width),
          ((maxY * scaleX) - offsetY).clamp(0, screenSize.height),
        );
      }

      final smoothed = _stabilizer.update(rawX, rawY);
      final targetInfo = _stabilizer.getStickyTarget(_coach.intersections, screenSize.width.toInt());

      setState(() {
        _smoothPos = smoothed;
        _targetPos = targetInfo['point'];
        _isPerfect = targetInfo['point'] != null ? _coach.isPerfect(targetInfo['distance']) : false;
        _personBoundingBox = boundingBox;
      });
    } catch (e) {
      debugPrint('ML Kit Error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_screenError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(_screenError!, style: const TextStyle(color: Colors.redAccent, fontSize: 16), textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (!_isCameraReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          CustomPaint(
            painter: GoldenCoachPainter(
              coach: _coach,
              currentSubjectPos: _smoothPos,
              targetPos: _targetPos,
              isPerfect: _isPerfect,
              personBoundingBox: _personBoundingBox,
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: Text(
              _isPerfect ? "PERFECT 구도입니다!" : "타겟을 향해 카메라를 이동하세요",
              style: TextStyle(
                color: _isPerfect ? Colors.greenAccent : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
