import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/services.dart';

List<CameraDescription> cameras = [];

class MathStabilizer {
  final double alpha;
  final double stickyMarginRatio;
  double? smoothedX;
  double? smoothedY;
  Point<int>? currentBestPoint;

  MathStabilizer({this.alpha = 0.25, this.stickyMarginRatio = 0.08});

  Point<int> update(double rawX, double rawY) {
    if (smoothedX == null || smoothedY == null) {
      smoothedX = rawX; smoothedY = rawY;
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
        if (dist < minDist) { minDist = dist; currentBestPoint = p; }
      }
    } else {
      double currDist = sqrt(pow(smoothedX! - currentBestPoint!.x, 2) + pow(smoothedY! - currentBestPoint!.y, 2));
      double stickyMargin = screenWidth * stickyMarginRatio;
      for (var p in intersections) {
        double newDist = sqrt(pow(smoothedX! - p.x, 2) + pow(smoothedY! - p.y, 2));
        if (newDist < currDist - stickyMargin) { currentBestPoint = p; currDist = newDist; }
      }
    }
    double finalDist = sqrt(pow(smoothedX! - currentBestPoint!.x, 2) + pow(smoothedY! - currentBestPoint!.y, 2));
    return {'point': currentBestPoint, 'distance': finalDist};
  }

  void reset() { smoothedX = null; smoothedY = null; currentBestPoint = null; }
}

class RuleOfThirdsCoach {
  static const double perfectThresholdRatio = 0.1;
  int width = 0, height = 0, x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  List<Point<int>> intersections = [];

  void calculateGrid(int screenWidth, int screenHeight) {
    width = screenWidth; height = screenHeight;
    x1 = width ~/ 3; x2 = (width * 2) ~/ 3;
    y1 = height ~/ 3; y2 = (height * 2) ~/ 3;
    intersections = [Point<int>(x1,y1), Point<int>(x2,y1), Point<int>(x1,y2), Point<int>(x2,y2)];
  }

  bool isPerfect(double distance) => distance < (width * perfectThresholdRatio);
}

class RuleOfThirdsPainter extends CustomPainter {
  final RuleOfThirdsCoach coach;
  final Point<int>? currentSubjectPos;
  final Point<int>? targetPos;
  final bool isPerfect;
  final Rect? personBoundingBox;

  RuleOfThirdsPainter({required this.coach, this.currentSubjectPos, this.targetPos, this.isPerfect = false, this.personBoundingBox});

  @override
  void paint(Canvas canvas, Size size) {
    coach.calculateGrid(size.width.toInt(), size.height.toInt());
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawLine(Offset(coach.x1.toDouble(), 0), Offset(coach.x1.toDouble(), size.height), gridPaint);
    canvas.drawLine(Offset(coach.x2.toDouble(), 0), Offset(coach.x2.toDouble(), size.height), gridPaint);
    canvas.drawLine(Offset(0, coach.y1.toDouble()), Offset(size.width, coach.y1.toDouble()), gridPaint);
    canvas.drawLine(Offset(0, coach.y2.toDouble()), Offset(size.width, coach.y2.toDouble()), gridPaint);
    final iPaint = Paint()..color = Colors.white.withOpacity(0.8)..style = PaintingStyle.fill;
    for (var p in coach.intersections) { canvas.drawCircle(Offset(p.x.toDouble(), p.y.toDouble()), 4.0, iPaint); }

    if (personBoundingBox != null) {
      canvas.drawRect(personBoundingBox!, Paint()..color = Colors.black.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 3.0);
      canvas.drawRect(personBoundingBox!, Paint()..color = Colors.cyanAccent.withOpacity(0.8)..style = PaintingStyle.stroke..strokeWidth = 2.0);
      final tp = TextPainter(text: const TextSpan(text: "Person Detected", style: TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 3)])), textDirection: TextDirection.ltr);
      tp.layout(); tp.paint(canvas, Offset(personBoundingBox!.left, personBoundingBox!.top - 20));
    }

    if (currentSubjectPos != null && targetPos != null) {
      Color c = isPerfect ? Colors.greenAccent : Colors.amber;
      canvas.drawLine(Offset(currentSubjectPos!.x.toDouble(), currentSubjectPos!.y.toDouble()), Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()), Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = isPerfect ? 3.0 : 2.0);
      canvas.drawCircle(Offset(currentSubjectPos!.x.toDouble(), currentSubjectPos!.y.toDouble()), isPerfect ? 8.0 : 6.0, Paint()..color = isPerfect ? Colors.greenAccent : Colors.redAccent..style = PaintingStyle.fill);
      canvas.drawCircle(Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()), 8.0, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = isPerfect ? 3.0 : 2.0);
      if (isPerfect) {
        final tp = TextPainter(text: const TextSpan(text: "PERFECT!", style: TextStyle(color: Colors.greenAccent, fontSize: 24, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)])), textDirection: TextDirection.ltr);
        tp.layout(); tp.paint(canvas, const Offset(20, 100));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class RuleOfThirdsScreen extends StatefulWidget {
  const RuleOfThirdsScreen({super.key});
  @override
  State<RuleOfThirdsScreen> createState() => _RuleOfThirdsScreenState();
}

class _RuleOfThirdsScreenState extends State<RuleOfThirdsScreen> {
  CameraController? _controller;
  bool _isCameraReady = false;
  final PoseDetector _poseDetector = PoseDetector(options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base));
  bool _isDetecting = false;
  bool _isProcessingFrame = false;
  String? _screenError;
  final MathStabilizer _stabilizer = MathStabilizer();
  final RuleOfThirdsCoach _coach = RuleOfThirdsCoach();
  Point<int>? _smoothPos;
  Point<int>? _targetPos;
  bool _isPerfect = false;
  Rect? _personBoundingBox;
  final _orientations = {DeviceOrientation.portraitUp: 0, DeviceOrientation.landscapeLeft: 90, DeviceOrientation.portraitDown: 180, DeviceOrientation.landscapeRight: 270};

  @override
  void initState() {
    super.initState();
    if (cameras.isNotEmpty) { _initializeCamera(); } else { _screenError = "카메라를 찾을 수 없습니다."; }
  }

  void _initializeCamera() {
    _controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() => _isCameraReady = true);
      try {
        _controller!.startImageStream((CameraImage image) {
          if (!_isDetecting) { _isDetecting = true; _processMLKit(image).then((_) => _isDetecting = false); }
        });
      } catch (e) { if (mounted) setState(() => _screenError = '카메라 스트림 오류:\n$e'); }
    }).catchError((e) { if (mounted) setState(() => _screenError = '카메라 초기화 실패:\n$e'); });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;
    final camera = cameras[0];
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Theme.of(context).platform == TargetPlatform.android) {
      var rc = _orientations[_controller!.value.deviceOrientation];
      if (rc == null) return null;
      rc = camera.lensDirection == CameraLensDirection.front ? (sensorOrientation + rc) % 360 : (sensorOrientation - rc + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(rc);
    }
    if (rotation == null) return null;

    // Android YUV420 -> NV21 변환 (ML Kit은 NV21을 기대)
    final Uint8List bytes;
    final InputImageFormat format;

    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length == 3) {
      final int width = image.width;
      final int height = image.height;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      final nv21 = Uint8List(width * height + (width * height / 2).round());
      final yPlane = image.planes[0];
      int yIndex = 0;
      for (int row = 0; row < height; row++) {
        nv21.setRange(yIndex, yIndex + width, yPlane.bytes, row * yPlane.bytesPerRow);
        yIndex += width;
      }
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
        setState(() { _smoothPos = null; _targetPos = null; _isPerfect = false; _personBoundingBox = null; });
        return;
      }
      final pose = poses.first;
      final imageWidth = inputImage.metadata?.size.width ?? image.width.toDouble();
      final imageHeight = inputImage.metadata?.size.height ?? image.height.toDouble();
      final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
      final isLandscape = imageWidth > imageHeight;
      final double actualW = (isLandscape && isPortrait) ? imageHeight : imageWidth;
      final double actualH = (isLandscape && isPortrait) ? imageWidth : imageHeight;
      final double screenAR = screenSize.width / screenSize.height;
      final double imageAR = actualW / actualH;
      double scaleX, offsetX = 0, offsetY = 0;
      if (imageAR > screenAR) { scaleX = screenSize.height / actualH; offsetX = (actualW * scaleX - screenSize.width) / 2; }
      else { scaleX = screenSize.width / actualW; offsetY = (actualH * scaleX - screenSize.height) / 2; }
      double targetX = actualW / 2, targetY = actualH / 2;
      final nose = pose.landmarks[PoseLandmarkType.nose];
      if (nose != null && nose.likelihood > 0.5) {
        targetX = nose.x; targetY = nose.y;
      } else {
        final fp = [pose.landmarks[PoseLandmarkType.leftEye], pose.landmarks[PoseLandmarkType.rightEye], pose.landmarks[PoseLandmarkType.leftEar], pose.landmarks[PoseLandmarkType.rightEar]].where((lm) => lm != null && lm.likelihood > 0.5).toList();
        if (fp.isNotEmpty) {
          targetX = fp.map((lm) => lm!.x).reduce((a, b) => a + b) / fp.length;
          targetY = fp.map((lm) => lm!.y).reduce((a, b) => a + b) / fp.length;
        } else {
          final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
          final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
          if (ls != null && rs != null) { targetX = (ls.x + rs.x) / 2; targetY = ((ls.y + rs.y) / 2) - ((ls.x - rs.x).abs() * 0.5); }
        }
      }
      final double rawX = (targetX * scaleX) - offsetX;
      final double rawY = (targetY * scaleX) - offsetY;
      Rect? boundingBox;
      final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
      final lh = pose.landmarks[PoseLandmarkType.leftHip];
      final rh = pose.landmarks[PoseLandmarkType.rightHip];
      if (ls != null && rs != null && lh != null && rh != null) {
        double minX = [ls.x, rs.x, lh.x, rh.x].reduce(min);
        double maxX = [ls.x, rs.x, lh.x, rh.x].reduce(max);
        double sw = maxX - minX; minX -= sw * 0.2; maxX += sw * 0.2;
        double minY = min([ls.y, rs.y].reduce(min) - sw * 0.5, nose?.y ?? ls.y);
        double maxY = [lh.y, rh.y].reduce(max);
        boundingBox = Rect.fromLTRB(((minX * scaleX) - offsetX).clamp(0, screenSize.width), ((minY * scaleX) - offsetY).clamp(0, screenSize.height), ((maxX * scaleX) - offsetX).clamp(0, screenSize.width), ((maxY * scaleX) - offsetY).clamp(0, screenSize.height));
      }
      final smoothed = _stabilizer.update(rawX, rawY);
      final targetInfo = _stabilizer.getStickyTarget(_coach.intersections, screenSize.width.toInt());
      setState(() {
        _smoothPos = smoothed;
        _targetPos = targetInfo['point'];
        _isPerfect = targetInfo['point'] != null ? _coach.isPerfect(targetInfo['distance']) : false;
        _personBoundingBox = boundingBox;
      });
    } catch (e) { debugPrint('ML Kit Error: $e'); }
    finally { _isProcessingFrame = false; }
  }

  @override
  void dispose() { _controller?.dispose(); _poseDetector.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_screenError != null) {
      return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text(_screenError!, style: const TextStyle(color: Colors.redAccent, fontSize: 16), textAlign: TextAlign.center))));
    }
    if (!_isCameraReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        CameraPreview(_controller!),
        CustomPaint(painter: RuleOfThirdsPainter(coach: _coach, currentSubjectPos: _smoothPos, targetPos: _targetPos, isPerfect: _isPerfect, personBoundingBox: _personBoundingBox)),
        Positioned(top: 50, left: 20, child: Text(_isPerfect ? "PERFECT 구도입니다!" : "타겟을 향해 카메라를 이동하세요", style: TextStyle(color: _isPerfect ? Colors.greenAccent : Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: const [Shadow(color: Colors.black, blurRadius: 4)]))),
        Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 32), onPressed: () => Navigator.of(context).pop())),
      ]),
    );
  }
}