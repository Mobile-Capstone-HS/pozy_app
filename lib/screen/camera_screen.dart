import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';

import '../subject_detection.dart';

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
      ..color = Colors.white.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

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
        3.5,
        intersectionPaint,
      );
    }

    if (subjectBoundingBox != null) {
      canvas.drawRect(
        subjectBoundingBox!,
        Paint()
          ..color = Colors.black.withOpacity(0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      canvas.drawRect(
        subjectBoundingBox!,
        Paint()
          ..color = subjectAccentColor.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: subjectLabel ?? 'Subject detected',
          style: TextStyle(
            color: subjectAccentColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
          ..strokeWidth = isPerfect ? 3 : 2,
      );

      canvas.drawCircle(
        Offset(
          currentSubjectPos!.x.toDouble(),
          currentSubjectPos!.y.toDouble(),
        ),
        isPerfect ? 8 : 6,
        Paint()
          ..color = isPerfect ? Colors.greenAccent : Colors.redAccent
          ..style = PaintingStyle.fill,
      );

      canvas.drawCircle(
        Offset(targetPos!.x.toDouble(), targetPos!.y.toDouble()),
        8,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPerfect ? 3 : 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class StableSubjectTracker {
  final int switchFrames;
  final int missingFrames;

  SubjectTarget? _current;
  SubjectTarget? _pending;
  int _pendingHits = 0;
  int _missingHits = 0;

  StableSubjectTracker({
    this.switchFrames = 4,
    this.missingFrames = 6,
  });

  SubjectTarget? update(SubjectTarget? candidate, Size screenSize) {
    if (candidate == null) {
      if (_current == null) return null;

      _missingHits += 1;
      if (_missingHits > missingFrames) {
        reset();
        return null;
      }

      return _current;
    }

    _missingHits = 0;

    if (_current == null) {
      _current = candidate;
      _pending = null;
      _pendingHits = 0;
      return _current;
    }

    if (_isSameTrack(_current!, candidate, screenSize)) {
      _current = _blendSubject(_current!, candidate);
      _pending = null;
      _pendingHits = 0;
      return _current;
    }

    if (_pending != null && _isSameTrack(_pending!, candidate, screenSize)) {
      _pending = _blendSubject(_pending!, candidate);
      _pendingHits += 1;
    } else {
      _pending = candidate;
      _pendingHits = 1;
    }

    if (_pendingHits >= switchFrames) {
      _current = _pending;
      _pending = null;
      _pendingHits = 0;
      return _current;
    }

    return _current;
  }

  bool _isSameTrack(
    SubjectTarget previous,
    SubjectTarget next,
    Size screenSize,
  ) {
    final sameCategory = previous.category == next.category;
    final sameLabel = previous.rawLabel == next.rawLabel;
    final iou = _intersectionOverUnion(previous.boundingBox, next.boundingBox);
    final centerDistance =
        (previous.boundingBox.center - next.boundingBox.center).distance;
    final diagonal = math.sqrt(
      (screenSize.width * screenSize.width) +
          (screenSize.height * screenSize.height),
    );

    if (sameCategory || sameLabel) {
      return iou > 0.18 || centerDistance < diagonal * 0.09;
    }

    return iou > 0.55 && centerDistance < diagonal * 0.06;
  }

  SubjectTarget _blendSubject(SubjectTarget previous, SubjectTarget next) {
    final rect = Rect.fromLTRB(
      _lerp(previous.boundingBox.left, next.boundingBox.left, 0.35),
      _lerp(previous.boundingBox.top, next.boundingBox.top, 0.35),
      _lerp(previous.boundingBox.right, next.boundingBox.right, 0.35),
      _lerp(previous.boundingBox.bottom, next.boundingBox.bottom, 0.35),
    );

    return SubjectTarget(
      focusPoint: math.Point<int>(
        rect.center.dx.round(),
        rect.center.dy.round(),
      ),
      boundingBox: rect,
      rawLabel: previous.category == next.category
          ? next.rawLabel
          : previous.rawLabel,
      category: previous.category == next.category
          ? next.category
          : previous.category,
      confidence: _lerp(previous.confidence, next.confidence, 0.35),
      detectionScore: _lerp(previous.detectionScore, next.detectionScore, 0.35),
    );
  }

  double _intersectionOverUnion(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0;

    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;

    if (unionArea <= 0) return 0;
    return intersectionArea / unionArea;
  }

  double _lerp(double a, double b, double t) => a + ((b - a) * t);

  void reset() {
    _current = null;
    _pending = null;
    _pendingHits = 0;
    _missingHits = 0;
  }
}

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
  final MathStabilizer _stabilizer = MathStabilizer();
  final RuleOfThirdsCoach _coach = RuleOfThirdsCoach();
  final StableSubjectTracker _subjectTracker = StableSubjectTracker();
  final GlobalKey _cameraKey = GlobalKey();
  final YOLOViewController _cameraController = YOLOViewController();
  final List<String> _idleCoachingMessages = const [
    '피사체를 화면 안에 안정적으로 들어오게 맞춰보세요',
    '배경보다 피사체가 잘 보이도록 카메라 각도를 조금 바꿔보세요',
    '손떨림을 줄이면 인식과 촬영이 더 안정적입니다',
    '화면을 드래그해서 원하는 피사체를 고정할 수 있어요',
  ];

  math.Point<int>? _smoothPos;
  math.Point<int>? _targetPos;
  bool _isPerfect = false;
  Rect? _subjectBoundingBox;
  String? _subjectLabel;
  SubjectCategory? _subjectCategory;
  SubjectTarget? _lockedSubject;
  Color _subjectAccentColor = Colors.cyanAccent;
  List<SubjectTarget> _latestCandidates = const [];
  Rect? _selectionRect;
  Offset? _dragStart;

  bool _isFrontCamera = false;
  bool _isCapturing = false;
  bool _showFlash = false;
  Timer? _coachingTimer;
  List<String> _coachingMessages = const [
    '피사체를 화면 안에 안정적으로 들어오게 맞춰보세요',
  ];
  int _coachingMessageIndex = 0;

  bool get _isSubjectLocked => _lockedSubject != null;

  String _selectedMode = 'PHOTO';
  final List<String> _modes = [
    'CINEMATIC',
    'VIDEO',
    'PHOTO',
    'PORTRAIT',
    'PANO',
  ];

  @override
  void initState() {
    super.initState();
    _coachingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _coachingMessages.length <= 1) return;
      setState(() {
        _coachingMessageIndex =
            (_coachingMessageIndex + 1) % _coachingMessages.length;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _cameraController.restartCamera();
    });
  }

  Rect _rectFromPoints(Offset a, Offset b) {
    return Rect.fromLTRB(
      math.min(a.dx, b.dx),
      math.min(a.dy, b.dy),
      math.max(a.dx, b.dx),
      math.max(a.dy, b.dy),
    );
  }

  void _handleSelectionStart(DragStartDetails details) {
    if (_isCapturing) return;

    setState(() {
      _dragStart = details.localPosition;
      _selectionRect = Rect.fromLTWH(
        details.localPosition.dx,
        details.localPosition.dy,
        0,
        0,
      );
    });
  }

  void _handleSelectionUpdate(DragUpdateDetails details) {
    final start = _dragStart;
    if (start == null) return;

    setState(() {
      _selectionRect = _rectFromPoints(start, details.localPosition);
    });
  }

  void _handleSelectionEnd(DragEndDetails details) {
    final selection = _selectionRect;
    _dragStart = null;

    if (selection == null || selection.width < 28 || selection.height < 28) {
      setState(() {
        _selectionRect = null;
      });
      return;
    }

    final selected = _pickSubjectFromSelection(selection);

    setState(() {
      _selectionRect = null;
      if (selected != null) {
        _lockedSubject = selected;
        _subjectTracker.reset();
        _coachingMessageIndex = 0;
      }
    });

    if (selected == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택한 영역에서 잠글 피사체를 찾지 못했어요.')),
      );
    }
  }

  SubjectTarget? _pickSubjectFromSelection(Rect selection) {
    if (_latestCandidates.isEmpty) return null;

    SubjectTarget? bestTarget;
    double bestScore = 0;

    for (final candidate in _latestCandidates) {
      final intersection = candidate.boundingBox.intersect(selection);
      if (intersection.isEmpty) continue;

      final intersectionArea = intersection.width * intersection.height;
      final selectionArea = selection.width * selection.height;
      final candidateArea =
          candidate.boundingBox.width * candidate.boundingBox.height;
      final overlapOnSelection = selectionArea <= 0
          ? 0
          : intersectionArea / selectionArea;
      final overlapOnCandidate = candidateArea <= 0
          ? 0
          : intersectionArea / candidateArea;
      final centerInside =
          selection.contains(candidate.boundingBox.center) ? 1.0 : 0.0;
      final score =
          (overlapOnSelection * 0.35) +
          (overlapOnCandidate * 0.35) +
          (centerInside * 0.15) +
          (candidate.detectionScore * 0.15);

      if (score > bestScore) {
        bestScore = score;
        bestTarget = candidate;
      }
    }

    return bestScore >= 0.18 ? bestTarget : null;
  }

  SubjectTarget? _selectLockedCandidate(
    List<SubjectTarget> candidates,
    Size screenSize,
  ) {
    final locked = _lockedSubject;
    if (locked == null || candidates.isEmpty) return null;

    SubjectTarget? bestTarget;
    double bestScore = 0;
    final diagonal = math.sqrt(
      (screenSize.width * screenSize.width) +
          (screenSize.height * screenSize.height),
    );

    for (final candidate in candidates) {
      final categoryScore = candidate.category == locked.category ? 1.0 : 0.0;
      final labelScore = candidate.rawLabel == locked.rawLabel ? 1.0 : 0.0;
      final centerDistance =
          (candidate.boundingBox.center - locked.boundingBox.center).distance;
      final distanceScore =
          (1 - (centerDistance / (diagonal * 0.18))).clamp(0.0, 1.0);
      final iou = _intersectionOverUnion(
        candidate.boundingBox,
        locked.boundingBox,
      );
      final score =
          (iou * 0.45) +
          (distanceScore * 0.30) +
          (categoryScore * 0.15) +
          (labelScore * 0.05) +
          (candidate.detectionScore * 0.05);

      if (score > bestScore) {
        bestScore = score;
        bestTarget = candidate;
      }
    }

    return bestScore >= 0.28 ? bestTarget : null;
  }

  double _intersectionOverUnion(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0;

    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;
    if (unionArea <= 0) return 0;
    return intersectionArea / unionArea;
  }

  void _clearSubjectLock() {
    setState(() {
      _lockedSubject = null;
      _coachingMessageIndex = 0;
    });
  }

  void _handleDetections(List<YOLOResult> results) {
    if (_isCapturing) return;

    final screenSize = MediaQuery.of(context).size;
    final candidates = collectSubjectTargets(results, screenSize);
    final detectedSubject = _isSubjectLocked
        ? _selectLockedCandidate(candidates, screenSize)
        : selectSubjectTarget(results, screenSize);
    final subject = _subjectTracker.update(detectedSubject, screenSize);

    if (subject == null) {
      _stabilizer.reset();
      _subjectTracker.reset();
      setState(() {
        _latestCandidates = candidates;
        _smoothPos = null;
        _targetPos = null;
        _isPerfect = false;
        _subjectBoundingBox = null;
        _subjectLabel = null;
        _subjectCategory = null;
        _subjectAccentColor = Colors.cyanAccent;
        if (_isSubjectLocked) {
          _lockedSubject = null;
        }
        _coachingMessages = _idleCoachingMessages;
        _coachingMessageIndex = 0;
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
    final targetPoint = targetInfo['point'] as math.Point<int>?;
    final isPerfect = targetPoint != null
        ? _coach.isPerfect(targetInfo['distance'])
        : false;
    final coachingMessages = _buildCoachingMessages(
      subject: subject,
      screenSize: screenSize,
      currentPoint: smoothed,
      targetPoint: targetPoint,
      isPerfect: isPerfect,
    );

    setState(() {
      _latestCandidates = candidates;
      _smoothPos = smoothed;
      _targetPos = targetPoint;
      _isPerfect = isPerfect;
      _subjectBoundingBox = subject.boundingBox;
      _subjectLabel = subject.displayLabel;
      _subjectCategory = subject.category;
      _subjectAccentColor = subject.accentColor;
      if (_isSubjectLocked) {
        _lockedSubject = subject;
      }
      _coachingMessages = coachingMessages;
      if (_coachingMessageIndex >= coachingMessages.length) {
        _coachingMessageIndex = 0;
      }
    });
  }

  Future<void> _toggleCamera() async {
    await _cameraController.switchCamera();
    if (!mounted) return;

    _subjectTracker.reset();
    _stabilizer.reset();
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _smoothPos = null;
      _targetPos = null;
      _isPerfect = false;
      _subjectBoundingBox = null;
      _subjectLabel = null;
      _subjectCategory = null;
      _subjectAccentColor = Colors.cyanAccent;
      _coachingMessages = _idleCoachingMessages;
      _coachingMessageIndex = 0;
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
          _cameraKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();
        await Gal.putImageBytes(pngBytes);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved to gallery.')),
        );
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save photo: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
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

  String _buildStatusText() {
    if (_subjectLabel == null) {
      return '피사체를 비춰 주세요';
    }

    if (_isPerfect) {
      return '${_subjectCategory?.label ?? '피사체'} 구도가 안정적입니다';
    }

    return '${_subjectCategory?.label ?? '피사체'}를 인식했어요';
  }

  String get _currentCoachingMessage {
    if (_coachingMessages.isEmpty) {
      return _idleCoachingMessages.first;
    }

    return _coachingMessages[_coachingMessageIndex % _coachingMessages.length];
  }

  List<String> _buildCoachingMessages({
    required SubjectTarget subject,
    required Size screenSize,
    required math.Point<int> currentPoint,
    required math.Point<int>? targetPoint,
    required bool isPerfect,
  }) {
    final messages = <String>[];
    final compositionMessage = _buildCompositionCoaching(
      currentPoint: currentPoint,
      targetPoint: targetPoint,
      screenSize: screenSize,
      isPerfect: isPerfect,
    );
    final distanceMessage = _buildDistanceCoaching(
      category: subject.category,
      boundingBox: subject.boundingBox,
      screenSize: screenSize,
    );
    final framingMessage = _buildFramingCoaching(
      category: subject.category,
      boundingBox: subject.boundingBox,
      screenSize: screenSize,
    );
    final clarityMessage = _buildClarityCoaching(subject.confidence);
    final readyToShoot = _isReadyToShoot(
      subject: subject,
      currentPoint: currentPoint,
      targetPoint: targetPoint,
      screenSize: screenSize,
      distanceMessage: distanceMessage,
      framingMessage: framingMessage,
    );

    if (compositionMessage != null) {
      messages.add(compositionMessage);
    }
    if (distanceMessage != null) {
      messages.add(distanceMessage);
    }
    if (framingMessage != null) {
      messages.add(framingMessage);
    }
    if (clarityMessage != null) {
      messages.add(clarityMessage);
    }

    if (readyToShoot) {
      messages.insert(0, '구도가 좋아요. 지금 촬영을 시도해 보세요');
    }

    if (messages.isEmpty) {
      messages.addAll([
        '구도가 안정적입니다. 지금 촬영해 보세요',
        '셔터를 누를 때 손을 잠시 멈추면 더 선명해집니다',
      ]);
    } else if (isPerfect && !readyToShoot) {
      messages.insert(0, '3분할선 위치가 좋아요. 이 구도를 유지해 보세요');
    }

    return messages.toSet().toList();
  }

  bool _isReadyToShoot({
    required SubjectTarget subject,
    required math.Point<int> currentPoint,
    required math.Point<int>? targetPoint,
    required Size screenSize,
    required String? distanceMessage,
    required String? framingMessage,
  }) {
    if (targetPoint == null) return false;
    if (distanceMessage != null || framingMessage != null) return false;

    final distance = math.sqrt(
      math.pow((targetPoint.x - currentPoint.x).toDouble(), 2) +
          math.pow((targetPoint.y - currentPoint.y).toDouble(), 2),
    );
    final compositionOk = distance < screenSize.width * 0.17;
    final areaRatio =
        (subject.boundingBox.width * subject.boundingBox.height) /
        (screenSize.width * screenSize.height);
    final preferred = _preferredAreaRange(subject.category);
    final sizeOk =
        areaRatio >= preferred.width * 0.85 &&
        areaRatio <= preferred.height * 1.15;

    return compositionOk && sizeOk && subject.confidence >= 0.45;
  }

  String? _buildCompositionCoaching({
    required math.Point<int> currentPoint,
    required math.Point<int>? targetPoint,
    required Size screenSize,
    required bool isPerfect,
  }) {
    if (targetPoint == null) {
      return '피사체가 3분할선 가까이에 오도록 구도를 맞춰보세요';
    }

    if (isPerfect) {
      return '주 피사체가 3분할선에 잘 맞고 있습니다';
    }

    final dx = targetPoint.x - currentPoint.x;
    final dy = targetPoint.y - currentPoint.y;
    final horizontalThreshold = screenSize.width * 0.06;
    final verticalThreshold = screenSize.height * 0.06;

    String? horizontal;
    String? vertical;

    if (dx.abs() >= horizontalThreshold) {
      horizontal = dx > 0 ? '오른쪽' : '왼쪽';
    }
    if (dy.abs() >= verticalThreshold) {
      vertical = dy > 0 ? '아래' : '위';
    }

    if (horizontal != null && vertical != null) {
      return '피사체를 $horizontal $vertical 3분할선 쪽으로 옮겨보세요';
    }
    if (horizontal != null) {
      return '피사체를 $horizontal 3분할선 쪽으로 옮겨보세요';
    }
    if (vertical != null) {
      return '피사체를 $vertical 3분할선 쪽으로 옮겨보세요';
    }
    return null;
  }

  String? _buildDistanceCoaching({
    required SubjectCategory category,
    required Rect boundingBox,
    required Size screenSize,
  }) {
    final areaRatio =
        (boundingBox.width * boundingBox.height) /
        (screenSize.width * screenSize.height);
    final widthRatio = boundingBox.width / screenSize.width;
    final heightRatio = boundingBox.height / screenSize.height;
    final range = _preferredAreaRange(category);

    if (areaRatio > range.height || widthRatio > 0.82 || heightRatio > 0.82) {
      return '피사체가 너무 가까워요. 한 걸음 뒤로 물러나 보세요';
    }

    if (areaRatio < range.width) {
      switch (category) {
        case SubjectCategory.food:
        case SubjectCategory.electronics:
        case SubjectCategory.object:
          return '핵심 피사체가 더 크게 보이도록 조금 더 가까이 가보세요';
        case SubjectCategory.person:
        case SubjectCategory.animal:
        case SubjectCategory.plant:
          return '피사체가 더 도드라지게 한 걸음 가까이 가보세요';
        case SubjectCategory.vehicle:
          return '차량이 더 또렷하게 보이도록 조금 더 가까이 맞춰보세요';
      }
    }

    return null;
  }

  Size _preferredAreaRange(SubjectCategory category) {
    switch (category) {
      case SubjectCategory.person:
        return const Size(0.16, 0.52);
      case SubjectCategory.food:
        return const Size(0.12, 0.42);
      case SubjectCategory.animal:
        return const Size(0.15, 0.48);
      case SubjectCategory.plant:
        return const Size(0.12, 0.40);
      case SubjectCategory.vehicle:
        return const Size(0.08, 0.30);
      case SubjectCategory.electronics:
        return const Size(0.10, 0.34);
      case SubjectCategory.object:
        return const Size(0.10, 0.36);
    }
  }

  String? _buildFramingCoaching({
    required SubjectCategory category,
    required Rect boundingBox,
    required Size screenSize,
  }) {
    final horizontalMargin = screenSize.width * 0.05;
    final verticalMargin = screenSize.height * 0.05;

    if (boundingBox.left < horizontalMargin ||
        boundingBox.right > screenSize.width - horizontalMargin ||
        boundingBox.top < verticalMargin ||
        boundingBox.bottom > screenSize.height - verticalMargin) {
      return '피사체가 잘리지 않도록 주변 여백을 조금 더 남겨보세요';
    }

    if (category == SubjectCategory.person &&
        boundingBox.top < screenSize.height * 0.10) {
      return '머리 위 공간이 아주 조금 보이게 구도를 다듬어 보세요';
    }

    return null;
  }

  String? _buildClarityCoaching(double confidence) {
    if (confidence < 0.45) {
      return '배경이 복잡하면 인식이 흔들릴 수 있어요. 각도를 조금 바꿔보세요';
    }
    return null;
  }

  Widget _buildTopControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onBack,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 22),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flash_off,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Container(
                    key: ValueKey<String>(_currentCoachingMessage),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.42),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      _currentCoachingMessage,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
              if (_isSubjectLocked) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _clearSubjectLock,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.42),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_open, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          '고정 해제',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFFFFD50B)
                  : Colors.white.withOpacity(0.85),
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      color: Colors.black.withOpacity(0.35),
      padding: const EdgeInsets.only(bottom: 20, top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 30),
              children: _modes.map(_buildModeText).toList(),
            ),
          ),
          const SizedBox(height: 15),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => widget.onMoveTab(1),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
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
                      size: 24,
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

  @override
  void dispose() {
    _coachingTimer?.cancel();
    _cameraController.stop();
    super.dispose();
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
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: _handleSelectionStart,
                onPanUpdate: _handleSelectionUpdate,
                onPanEnd: _handleSelectionEnd,
                child: Stack(
                  children: [
                    if (_selectionRect != null)
                      Positioned.fromRect(
                        rect: _selectionRect!,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.10),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.95),
                              width: 1.6,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (false && !_isCapturing)
            Positioned(
              top: 62,
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
                      fontWeight: FontWeight.w700,
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
                      '좋아요',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
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
                children: [
                  _buildTopControls(),
                  _buildBottomControls(),
                ],
              ),
            ),
          if (_showFlash) Container(color: Colors.white),
        ],
      ),
    );
  }
}
