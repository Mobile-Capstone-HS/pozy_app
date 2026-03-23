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

class GoldenCoach {
  static const double perfectThresholdRatio = 0.1;
  static const double phi = 1.6180339887;
  static const double ratio = 1 / phi;

  int width = 0;
  int height = 0;
  List<math.Point<int>> intersections = [];

  void calculateGrid(int screenWidth, int screenHeight) {
    width = screenWidth;
    height = screenHeight;
    final inverseRatio = 1 - ratio;
    final left = (width * inverseRatio).toInt();
    final right = (width * ratio).toInt();
    final top = (height * inverseRatio).toInt();
    final bottom = (height * ratio).toInt();

    intersections = [
      math.Point<int>(left, top),
      math.Point<int>(right, top),
      math.Point<int>(left, bottom),
      math.Point<int>(right, bottom),
    ];
  }

  bool isPerfect(double distance) => distance < (width * perfectThresholdRatio);
}

class GoldenCoachPainter extends CustomPainter {
  final GoldenCoach coach;
  final math.Point<int>? currentSubjectPos;
  final math.Point<int>? targetPos;
  final bool isPerfect;
  final Rect? subjectBoundingBox;
  final String? subjectLabel;
  final Color subjectAccentColor;

  const GoldenCoachPainter({
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

    final spiralLinePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final spiralShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (coach.intersections.isNotEmpty) {
      const activeTargetIndex = 3;

      void drawSpiralArc(Rect rect, double startAngle, double sweepAngle) {
        canvas.drawArc(rect, startAngle, sweepAngle, false, spiralShadowPaint);
        canvas.drawArc(rect, startAngle, sweepAngle, false, spiralLinePaint);
      }

      void drawSpiralRect(Rect rect) {
        canvas.drawRect(rect, spiralShadowPaint);
        canvas.drawRect(rect, spiralLinePaint);
      }

      double xMin = 0;
      double yMin = 0;
      double xMax = size.width;
      double yMax = size.height;
      const spiralRatio = GoldenCoach.ratio;

      for (int i = 0; i < 8; i++) {
        final w = xMax - xMin;
        final h = yMax - yMin;
        if (w <= 2 || h <= 2) break;

        final step = i % 4;
        int dir = 0;
        if (activeTargetIndex == 3) {
          dir = step;
        } else if (activeTargetIndex == 1) {
          dir = [0, 3, 2, 1][step];
        } else if (activeTargetIndex == 2) {
          dir = [2, 1, 0, 3][step];
        } else if (activeTargetIndex == 0) {
          dir = [2, 3, 0, 1][step];
        }

        if (dir == 0) {
          drawSpiralRect(
            Rect.fromLTRB(xMin, yMin, xMin + w * spiralRatio, yMax),
          );
          final cx = xMin + w * spiralRatio;
          final cy = (activeTargetIndex == 3 || activeTargetIndex == 2)
              ? yMax
              : yMin;
          final startAngle = (activeTargetIndex == 3 || activeTargetIndex == 2)
              ? math.pi
              : math.pi / 2;
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * spiralRatio * 2,
              height: h * 2,
            ),
            startAngle,
            math.pi / 2 * (activeTargetIndex <= 1 ? -1 : 1),
          );
          xMin += w * spiralRatio;
        } else if (dir == 1) {
          drawSpiralRect(
            Rect.fromLTRB(xMin, yMin, xMax, yMin + h * spiralRatio),
          );
          final cx = (activeTargetIndex == 3 || activeTargetIndex == 1)
              ? xMin
              : xMax;
          final cy = yMin + h * spiralRatio;
          final startAngle = (activeTargetIndex == 3 || activeTargetIndex == 1)
              ? -math.pi / 2
              : math.pi;
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * 2,
              height: h * spiralRatio * 2,
            ),
            startAngle,
            math.pi /
                2 *
                (activeTargetIndex == 0 || activeTargetIndex == 3 ? 1 : -1),
          );
          yMin += h * spiralRatio;
        } else if (dir == 2) {
          drawSpiralRect(
            Rect.fromLTRB(xMin + w * (1 - spiralRatio), yMin, xMax, yMax),
          );
          final cx = xMin + w * (1 - spiralRatio);
          final cy = (activeTargetIndex == 3 || activeTargetIndex == 2)
              ? yMin
              : yMax;
          final startAngle = (activeTargetIndex == 3 || activeTargetIndex == 2)
              ? 0.0
              : -math.pi / 2;
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * spiralRatio * 2,
              height: h * 2,
            ),
            startAngle,
            math.pi / 2 * (activeTargetIndex <= 1 ? -1 : 1),
          );
          xMax -= w * spiralRatio;
        } else if (dir == 3) {
          drawSpiralRect(
            Rect.fromLTRB(xMin, yMin + h * (1 - spiralRatio), xMax, yMax),
          );
          final cx = (activeTargetIndex == 3 || activeTargetIndex == 1)
              ? xMax
              : xMin;
          final cy = yMin + h * (1 - spiralRatio);
          final startAngle = (activeTargetIndex == 3 || activeTargetIndex == 1)
              ? math.pi / 2
              : 0.0;
          drawSpiralArc(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: w * 2,
              height: h * spiralRatio * 2,
            ),
            startAngle,
            math.pi /
                2 *
                (activeTargetIndex == 0 || activeTargetIndex == 3 ? 1 : -1),
          );
          yMax -= h * spiralRatio;
        }
      }
    }

    if (subjectBoundingBox != null) {
      final boxShadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      final boxPaint = Paint()
        ..color = subjectAccentColor.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRect(subjectBoundingBox!, boxShadowPaint);
      canvas.drawRect(subjectBoundingBox!, boxPaint);

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
      final stateColor = isPerfect ? Colors.greenAccent : Colors.amber;
      final connectionPaint = Paint()
        ..color = stateColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isPerfect ? 3.0 : 2.0;
      final subjectPaint = Paint()
        ..color = isPerfect ? Colors.greenAccent : Colors.redAccent
        ..style = PaintingStyle.fill;

      canvas.drawLine(
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        connectionPaint,
      );
      canvas.drawCircle(
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        isPerfect ? 8.0 : 6.0,
        subjectPaint,
      );
      canvas.drawCircle(
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        8.0,
        connectionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GoldenRatioScreen extends StatefulWidget {
  const GoldenRatioScreen({super.key});

  @override
  State<GoldenRatioScreen> createState() => _GoldenRatioScreenState();
}

class _GoldenRatioScreenState extends State<GoldenRatioScreen> {
  final MathStabilizer _stabilizer = MathStabilizer();
  final GoldenCoach _coach = GoldenCoach();
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
              painter: GoldenCoachPainter(
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
