import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';

import 'subject_detection.dart';

List<CameraDescription> cameras = [];

class MathStabilizer {
  final double alpha;
  final double stickyMarginRatio;

  double? smoothedX;
  double? smoothedY;
  math.Point<int>? currentBestPoint;

  MathStabilizer({this.alpha = 0.25, this.stickyMarginRatio = 0.08});

  math.Point<int> update(double rawX, double rawY) {
    if (smoothedX == null || smoothedY == null) {
      smoothedX = rawX;
      smoothedY = rawY;
    } else {
      smoothedX = smoothedX! * (1 - alpha) + rawX * alpha;
      smoothedY = smoothedY! * (1 - alpha) + rawY * alpha;
    }
    return math.Point<int>(smoothedX!.toInt(), smoothedY!.toInt());
  }

  Map<String, dynamic> getStickyTarget(
    List<math.Point<int>> intersections,
    int screenWidth,
  ) {
    if (smoothedX == null || smoothedY == null || intersections.isEmpty) {
      return {'point': null, 'distance': double.infinity};
    }

    if (currentBestPoint == null) {
      double minDist = double.infinity;
      for (final point in intersections) {
        final dist = math.sqrt(
          math.pow(smoothedX! - point.x, 2) + math.pow(smoothedY! - point.y, 2),
        );
        if (dist < minDist) {
          minDist = dist;
          currentBestPoint = point;
        }
      }
    } else {
      double currentDistance = math.sqrt(
        math.pow(smoothedX! - currentBestPoint!.x, 2) +
            math.pow(smoothedY! - currentBestPoint!.y, 2),
      );
      final stickyMargin = screenWidth * stickyMarginRatio;

      for (final point in intersections) {
        final nextDistance = math.sqrt(
          math.pow(smoothedX! - point.x, 2) + math.pow(smoothedY! - point.y, 2),
        );
        if (nextDistance < currentDistance - stickyMargin) {
          currentBestPoint = point;
          currentDistance = nextDistance;
        }
      }
    }

    final finalDistance = math.sqrt(
      math.pow(smoothedX! - currentBestPoint!.x, 2) +
          math.pow(smoothedY! - currentBestPoint!.y, 2),
    );

    return {'point': currentBestPoint, 'distance': finalDistance};
  }

  void reset() {
    smoothedX = null;
    smoothedY = null;
    currentBestPoint = null;
  }
}

class RuleOfThirdsCoach {
  static const double perfectThresholdRatio = 0.1;

  int width = 0;
  int height = 0;
  int x1 = 0;
  int x2 = 0;
  int y1 = 0;
  int y2 = 0;
  List<math.Point<int>> intersections = [];

  void calculateGrid(int screenWidth, int screenHeight) {
    width = screenWidth;
    height = screenHeight;
    x1 = width ~/ 3;
    x2 = (width * 2) ~/ 3;
    y1 = height ~/ 3;
    y2 = (height * 2) ~/ 3;
    intersections = [
      math.Point<int>(x1, y1),
      math.Point<int>(x2, y1),
      math.Point<int>(x1, y2),
      math.Point<int>(x2, y2),
    ];
  }

  bool isPerfect(double distance) => distance < (width * perfectThresholdRatio);
}

class RuleOfThirdsPainter extends CustomPainter {
  final RuleOfThirdsCoach coach;
  final math.Point<int>? currentSubjectPos;
  final math.Point<int>? targetPos;
  final bool isPerfect;
  final Rect? subjectBoundingBox;
  final String? subjectLabel;
  final Color subjectAccentColor;

  const RuleOfThirdsPainter({
    required this.coach,
    this.currentSubjectPos,
    this.targetPos,
    this.isPerfect = false,
    this.subjectBoundingBox,
    this.subjectLabel,
    this.subjectAccentColor = Colors.cyanAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    coach.calculateGrid(size.width.toInt(), size.height.toInt());

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(coach.x1.toDouble(), 0),
      Offset(coach.x1.toDouble(), size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(coach.x2.toDouble(), 0),
      Offset(coach.x2.toDouble(), size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, coach.y1.toDouble()),
      Offset(size.width, coach.y1.toDouble()),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, coach.y2.toDouble()),
      Offset(size.width, coach.y2.toDouble()),
      gridPaint,
    );

    final intersectionPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    for (final point in coach.intersections) {
      canvas.drawCircle(
        Offset(point.x.toDouble(), point.y.toDouble()),
        4.0,
        intersectionPaint,
      );
    }

    if (subjectBoundingBox != null) {
      canvas.drawRect(
        subjectBoundingBox!,
        Paint()
          ..color = Colors.black.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
      canvas.drawRect(
        subjectBoundingBox!,
        Paint()
          ..color = subjectAccentColor.withOpacity(0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: subjectLabel ?? 'Subject detected',
          style: TextStyle(
            color: subjectAccentColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(subjectBoundingBox!.left, subjectBoundingBox!.top - 20),
      );
    }

    if (currentSubjectPos != null && targetPos != null) {
      final lineColor = isPerfect ? Colors.greenAccent : Colors.amber;
      canvas.drawLine(
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPerfect ? 3.0 : 2.0,
      );
      canvas.drawCircle(
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        isPerfect ? 8.0 : 6.0,
        Paint()
          ..color = isPerfect ? Colors.greenAccent : Colors.redAccent
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        8.0,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPerfect ? 3.0 : 2.0,
      );
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
  final MathStabilizer _stabilizer = MathStabilizer();
  final RuleOfThirdsCoach _coach = RuleOfThirdsCoach();
  final GlobalKey _cameraKey = GlobalKey();
  final YOLOViewController _cameraController = YOLOViewController();

  math.Point<int>? _smoothPos;
  math.Point<int>? _targetPos;
  bool _isPerfect = false;
  Rect? _subjectBoundingBox;
  String? _subjectLabel;
  SubjectCategory? _subjectCategory;
  Color _subjectAccentColor = Colors.cyanAccent;
  bool _isFrontCamera = false;

  bool _isCapturing = false;
  bool _showFlash = false;
  String _selectedMode = 'PHOTO';
  final List<String> _modes = [
    'CINEMATIC',
    'VIDEO',
    'PHOTO',
    'PORTRAIT',
    'PANO',
  ];

  void _handleDetections(List<YOLOResult> results) {
    if (_isCapturing) return;

    final screenSize = MediaQuery.of(context).size;
    final subject = selectSubjectTarget(results, screenSize);

    if (subject == null) {
      _stabilizer.reset();
      setState(() {
        _smoothPos = null;
        _targetPos = null;
        _isPerfect = false;
        _subjectBoundingBox = null;
        _subjectLabel = null;
        _subjectCategory = null;
      });
      return;
    }

    final smoothed = _stabilizer.update(
      subject.focusPoint.x.toDouble(),
      subject.focusPoint.y.toDouble(),
    );
    final targetInfo = _stabilizer.getStickyTarget(
      _coach.intersections,
      screenSize.width.toInt(),
    );

    setState(() {
      _smoothPos = smoothed;
      _targetPos = targetInfo['point'];
      _isPerfect = targetInfo['point'] != null
          ? _coach.isPerfect(targetInfo['distance'])
          : false;
      _subjectBoundingBox = subject.boundingBox;
      _subjectLabel = subject.displayLabel;
      _subjectCategory = subject.category;
      _subjectAccentColor = subject.accentColor;
    });
  }

  Future<void> _toggleCamera() async {
    await _cameraController.switchCamera();
    if (!mounted) return;

    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
  }

  Future<void> _takePhoto() async {
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final request = await Gal.requestAccess();
        if (!request) return;
      }

      final boundary =
          _cameraKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();
        await Gal.putImageBytes(pngBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo saved to gallery.')),
          );
        }
      }
    } catch (error) {
      debugPrint('Capture error: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save photo: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _showFlash = true;
        });

        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            setState(() {
              _showFlash = false;
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            key: _cameraKey,
            child: YOLOView(
              controller: _cameraController,
              modelPath: detectModelPath,
              task: YOLOTask.detect,
              useGpu: false,
              streamingConfig: detectionStreamingConfig,
              confidenceThreshold: detectionConfidenceThreshold,
              showOverlays: false,
              lensFacing: LensFacing.back,
              onResult: _handleDetections,
            ),
          ),
          if (!_isCapturing)
            CustomPaint(
              painter: RuleOfThirdsPainter(
                coach: _coach,
                currentSubjectPos: _smoothPos,
                targetPos: _targetPos,
                isPerfect: _isPerfect,
                subjectBoundingBox: _subjectBoundingBox,
                subjectLabel: _subjectLabel,
                subjectAccentColor: _subjectAccentColor,
              ),
            ),
          if (!_isCapturing)
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _buildStatusText(),
                    style: TextStyle(
                      color: _isPerfect ? Colors.greenAccent : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 4),
                      ],
                    ),
                  ),
                  if (_subjectLabel != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _subjectLabel!,
                      style: TextStyle(
                        color: _subjectAccentColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                  if (_isPerfect) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'PERFECT!',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (!_isCapturing)
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [_buildTopControls(), _buildBottomControls()],
              ),
            ),
          if (_showFlash) Container(color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildTopControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(Icons.flash_off, color: Colors.white, size: 24),
          const Icon(Icons.nightlight_round, color: Colors.white54, size: 24),
          Icon(
            Icons.keyboard_arrow_up,
            color: Colors.white.withOpacity(0.8),
            size: 24,
          ),
          const Icon(Icons.hdr_auto, color: Colors.white54, size: 24),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  String _buildStatusText() {
    if (_subjectLabel == null) {
      return 'Point the camera at a subject';
    }

    if (_isPerfect) {
      return 'Balanced ${_subjectCategory?.label ?? 'subject'} composition found';
    }

    return '${_subjectCategory?.label ?? 'Subject'} detected - move toward the guide point';
  }

  Widget _buildBottomControls() {
    return Container(
      color: Colors.black.withOpacity(0.4),
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 30),
              children: _modes.map((mode) => _buildModeText(mode)).toList(),
            ),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 30.0,
              vertical: 10.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                ),
                GestureDetector(
                  onTap: _takePhoto,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3.5),
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
                GestureDetector(
                  onTap: _toggleCamera,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isFrontCamera
                            ? Colors.white70
                            : Colors.transparent,
                      ),
                    ),
                    child: const Icon(
                      Icons.flip_camera_ios,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeText(String text) {
    final isSelected = _selectedMode == text;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMode = text;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFFFFD50B)
                  : Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontFamily: 'SF Compact',
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
