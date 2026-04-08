import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import 'package:pose_camera_app/coaching/coaching_result.dart' hide ShootingMode;
import 'package:pose_camera_app/widget/coaching_interface.dart';
import 'package:pose_camera_app/widget/horizon_level_indicator.dart';
import 'package:pose_camera_app/coaching/object_coach.dart';
import 'package:pose_camera_app/coaching/portrait/portrait_mode_handler.dart';
import 'package:pose_camera_app/coaching/portrait/portrait_overlay_painter.dart';
import 'package:pose_camera_app/coaching/portrait/portrait_scene_state.dart' as portrait;
import 'package:pose_camera_app/coaching/subject/subject_detection.dart'
    show detectModelPath, detectionConfidenceThreshold;

const String poseModelPath = 'yolov8n-pose_float16.tflite';
const double poseConfidenceThreshold = 0.15;

enum ShootingMode {
  person('\uC778\uBB3C'),
  object('\uAC1D\uCCB4'),
  landscape('\uD48D\uACBD');

  final String label;
  const ShootingMode(this.label);
}

class CameraScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback onBack;
  final ShootingMode initialMode;

  const CameraScreen({
    super.key,
    required this.onMoveTab,
    required this.onBack,
    this.initialMode = ShootingMode.object,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  static const _cameraAspect = 3.0 / 4.0;

  final _cameraController = YOLOViewController();
  final _sceneCoach = ObjectCoach();
  final _portraitHandler = PortraitModeHandler();

  List<double> _zoomPresets = [1.0, 2.0];
  Size _previewSize = Size.zero;

  String _guidance = '\uAD6C\uB3C4\uB97C \uC7A1\uB294 \uC911...';
  String? _subGuidance;
  CoachingLevel _coachingLevel = CoachingLevel.caution;

  late ShootingMode _shootingMode;
  Offset? _focusPoint;
  bool _showFocusIndicator = false;

  double _selectedZoom = 1.0;
  double _currentZoom = 1.0;
  bool _isFrontCamera = false;
  bool _isSaving = false;
  bool _showFlash = false;
  bool _torchOn = false;

  bool _isDrawingRoi = false;
  Offset? _roiDragStart;
  Offset? _roiDragCurrent;
  Rect? _lockedRoi;
  Rect? _lockedRoiCamera;
  int? _lockedClassIndex;
  Rect? _lockedAnchorRoiCamera;
  List<double>? _lockedAppearanceSignature;
  List<double>? _lockedRecentAppearanceSignature;
  YOLOResult? _lockedTrackingDetection;
  int _lockedLostFrames = 0;
  static const int _lockLostFrameTolerance = 10;

  List<YOLOResult> _latestRawDetections = [];

  int _timerSeconds = 0;
  int _countdown = 0;

  double _tiltX = 0.0;
  double _gravX = 0.0;
  double _gravY = 9.8;

  portrait.CoachingResult _portraitCoaching = const portrait.CoachingResult(
    message: '\uCE74\uBA54\uB77C\uB97C \uC5EC\uC720\uB86D\uAC8C \uB9DE\uCDB0\uC8FC\uC138\uC694.',
    priority: portrait.CoachingPriority.critical,
    confidence: 1.0,
  );
  OverlayData _portraitOverlayData = const OverlayData(
    coaching: portrait.CoachingResult(
      message: '',
      priority: portrait.CoachingPriority.critical,
      confidence: 0.0,
    ),
  );
  int _portraitLostFrames = 0;
  static const int _portraitLostFrameTolerance = 8;

  Timer? _countdownTimer;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;

  bool get _isPortraitMode => _shootingMode == ShootingMode.person;

  @override
  void initState() {
    super.initState();
    _shootingMode = widget.initialMode;

    unawaited(_portraitHandler.init());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      await _cameraController.restartCamera();
      await _cameraController.setZoomLevel(_selectedZoom);
      await _configureZoomPresets();
    });

    _startTiltMonitoring();
    _cameraController.onImageMetrics = _onImageMetrics;
  }

  void _startTiltMonitoring() {
    try {
      _accelerometerSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.uiInterval,
      ).listen((event) {
        _gravX = (_gravX * 0.7) + (event.x * 0.3);
        _gravY = (_gravY * 0.7) + (event.y * 0.3);

        final rollDeg = math.atan2(_gravX, _gravY) * 180.0 / math.pi;
        _tiltX = rollDeg;
        _sceneCoach.updateTilt(_tiltX);
        setState(() {});
      });
    } catch (_) {}
  }

  Future<void> _configureZoomPresets() async {
    double minZoom = 1.0;

    for (int i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      minZoom = await _cameraController.getMinZoomLevel();
      if (minZoom < 1.0) break;
    }

    final next = minZoom < 1.0 ? [minZoom, 1.0, 2.0] : [1.0, 2.0];

    if (next.length == _zoomPresets.length &&
        next.indexed.every(
          (e) => (e.$2 - _zoomPresets[e.$1]).abs() < 0.001,
        )) {
      return;
    }

    setState(() => _zoomPresets = next);
  }

  void _resetPortraitState() {
    _portraitHandler.reset();
    _portraitLostFrames = 0;
    _portraitCoaching = const portrait.CoachingResult(
      message: '\uCE74\uBA54\uB77C\uB97C \uC5EC\uC720\uB86D\uAC8C \uB9DE\uCDB0\uC8FC\uC138\uC694.',
      priority: portrait.CoachingPriority.critical,
      confidence: 1.0,
    );
    _portraitOverlayData = const OverlayData(
      coaching: portrait.CoachingResult(
        message: '',
        priority: portrait.CoachingPriority.critical,
        confidence: 0.0,
      ),
    );
  }

  void _onImageMetrics(Map<String, double> metrics) {
    if (!mounted) return;

    if (_isPortraitMode) {
      _portraitHandler.updateNativeMetrics(metrics);
      return;
    }

    final coaching = _decorateLockedSubjectCoachingSafe(
      _sceneCoach.applyImageMetrics(metrics),
    );
    if (coaching.guidance != _guidance ||
        coaching.subGuidance != _subGuidance ||
        coaching.level != _coachingLevel) {
      setState(() {
        _guidance = coaching.guidance;
        _subGuidance = coaching.subGuidance;
        _coachingLevel = coaching.level;
      });
    }
  }

  List<YOLOResult> _filterResultsForMode(List<YOLOResult> results) {
    switch (_shootingMode) {
      case ShootingMode.person:
        return results
            .where((r) => r.className.toLowerCase() == 'person')
            .toList();
      case ShootingMode.object:
        return results
            .where((r) => r.className.toLowerCase() != 'person')
            .toList();
      case ShootingMode.landscape:
        return results;
    }
  }

  static double _iou(Rect a, Rect b) {
    final il = math.max(a.left, b.left);
    final it = math.max(a.top, b.top);
    final ir = math.min(a.right, b.right);
    final ib = math.min(a.bottom, b.bottom);
    if (ir <= il || ib <= it) return 0.0;
    final inter = (ir - il) * (ib - it);
    final union = a.width * a.height + b.width * b.height - inter;
    return union > 0 ? inter / union : 0.0;
  }

  static Rect _normalizedRect(YOLOResult det) {
    final b = det.normalizedBox;
    return Rect.fromLTRB(
      b.left.clamp(0.0, 1.0),
      b.top.clamp(0.0, 1.0),
      b.right.clamp(0.0, 1.0),
      b.bottom.clamp(0.0, 1.0),
    );
  }

  static double _rectArea(Rect rect) => rect.width * rect.height;

  static double _rectAspect(Rect rect) =>
      rect.height.abs() < 0.0001 ? 1.0 : rect.width / rect.height;

  static double _centerDistance(Rect a, Rect b) {
    final dx = a.center.dx - b.center.dx;
    final dy = a.center.dy - b.center.dy;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _overlapRatio(Rect a, Rect b) {
    final il = math.max(a.left, b.left);
    final it = math.max(a.top, b.top);
    final ir = math.min(a.right, b.right);
    final ib = math.min(a.bottom, b.bottom);
    if (ir <= il || ib <= it) return 0.0;
    final inter = (ir - il) * (ib - it);
    final minArea = math.max(math.min(_rectArea(a), _rectArea(b)), 0.0001);
    return inter / minArea;
  }

  static double _appearanceDistance(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    if (n == 0) return double.infinity;

    var sumSq = 0.0;
    for (var i = 0; i < n; i++) {
      final d = a[i] - b[i];
      sumSq += d * d;
    }
    return math.sqrt(sumSq / n);
  }

  List<double>? _blendAppearanceSignature(
    List<double>? current,
    List<double>? next, {
    double alpha = 0.25,
  }) {
    if (next == null) return current;
    if (current == null) return List<double>.from(next);

    final n = math.min(current.length, next.length);
    return List<double>.generate(
      n,
      (i) => current[i] * (1.0 - alpha) + next[i] * alpha,
      growable: false,
    );
  }

  double _lockedMatchScore(Rect target, YOLOResult det) {
    if (_lockedClassIndex != null && det.classIndex != _lockedClassIndex) {
      return double.negativeInfinity;
    }

    final box = _normalizedRect(det);
    final previous = _lockedTrackingDetection == null
        ? target
        : _normalizedRect(_lockedTrackingDetection!);
    final anchor = _lockedAnchorRoiCamera ?? previous;
    final iouNow = _iou(previous, box);
    final overlapNow = _overlapRatio(previous, box);
    final iouAnchor = _iou(anchor, box);
    final overlapAnchor = _overlapRatio(anchor, box);
    final areaRatioNow =
        _rectArea(box) / math.max(_rectArea(previous), 0.0001);
    final areaRatioAnchor = _rectArea(box) / math.max(_rectArea(anchor), 0.0001);
    final aspectNow = (_rectAspect(box) - _rectAspect(previous)).abs() /
        math.max(_rectAspect(previous).abs(), 0.0001);
    final aspectAnchor = (_rectAspect(box) - _rectAspect(anchor)).abs() /
        math.max(_rectAspect(anchor).abs(), 0.0001);
    final targetDistance = _centerDistance(previous, box);
    final anchorDistance = _centerDistance(anchor, box);

    final anchorSignature = _lockedAppearanceSignature;
    final recentSignature =
        _lockedRecentAppearanceSignature ?? _lockedAppearanceSignature;
    final candidateSignature = det.appearanceSignature;
    final hasAnchorAppearance =
        anchorSignature != null && candidateSignature != null;
    final hasRecentAppearance =
        recentSignature != null && candidateSignature != null;
    final anchorAppearance = hasAnchorAppearance
        ? _appearanceDistance(anchorSignature, candidateSignature)
        : double.infinity;
    final recentAppearance = hasRecentAppearance
        ? _appearanceDistance(recentSignature, candidateSignature)
        : double.infinity;

    if (hasAnchorAppearance || hasRecentAppearance) {
      final maxAnchorAppearance = _lockedLostFrames == 0 ? 0.18 : 0.24;
      final maxRecentAppearance = _lockedLostFrames == 0 ? 0.20 : 0.26;
      final appearanceMatched = anchorAppearance <= maxAnchorAppearance ||
          recentAppearance <= maxRecentAppearance;
      if (!appearanceMatched) {
        return double.negativeInfinity;
      }
    } else {
      if (iouNow < 0.01 &&
          overlapNow < 0.05 &&
          iouAnchor < 0.01 &&
          overlapAnchor < 0.05 &&
          targetDistance > 0.45) {
        return double.negativeInfinity;
      }
    }

    if (_lockedLostFrames > 0 &&
        det.confidence < 0.16 &&
        iouNow < 0.03 &&
        overlapNow < 0.08 &&
        iouAnchor < 0.03 &&
        anchorDistance > 0.60) {
      return double.negativeInfinity;
    }

    final appearanceScore = () {
      final bestAppearance = math.min(anchorAppearance, recentAppearance);
      if (!bestAppearance.isFinite) return 0.0;
      final scale = _lockedLostFrames == 0 ? 0.18 : 0.24;
      return (1.0 - (bestAppearance / scale)).clamp(0.0, 1.0);
    }();

    final distanceScore =
        (1.0 - (targetDistance / (_lockedLostFrames == 0 ? 0.32 : 0.50)))
            .clamp(0.0, 1.0);
    final anchorDistanceScore =
        (1.0 - (anchorDistance / (_lockedLostFrames == 0 ? 0.45 : 0.70)))
            .clamp(0.0, 1.0);
    final areaSimilarityNow =
        (1.0 - (areaRatioNow - 1.0).abs() / 1.4).clamp(0.0, 1.0);
    final areaSimilarityAnchor =
        (1.0 - (areaRatioAnchor - 1.0).abs() / 1.8).clamp(0.0, 1.0);
    final aspectSimilarityNow = (1.0 - aspectNow / 1.1).clamp(0.0, 1.0);
    final aspectSimilarityAnchor =
        (1.0 - aspectAnchor / 1.3).clamp(0.0, 1.0);

    return det.confidence * 1.3 +
        iouNow * 2.6 +
        overlapNow * 2.8 +
        iouAnchor * 1.2 +
        overlapAnchor * 1.4 +
        appearanceScore * 3.0 +
        distanceScore * 1.2 +
        anchorDistanceScore * 0.8 +
        areaSimilarityNow * 0.8 +
        areaSimilarityAnchor * 0.5 +
        aspectSimilarityNow * 0.45 +
        aspectSimilarityAnchor * 0.3;
  }

  YOLOResult? _bestDetectionForTarget(
    Rect target,
    List<YOLOResult> results, {
    String? lockedClassName,
  }) {
    final candidates = lockedClassName == null
        ? results
        : results
            .where((r) => r.className.toLowerCase() == lockedClassName)
            .toList();
    final searchSpace = candidates.isNotEmpty ? candidates : results;

    YOLOResult? bestMatch;
    double bestScore = double.negativeInfinity;
    for (final det in searchSpace) {
      final box = _normalizedRect(det);
      final iou = _iou(target, box);
      final overlap = _overlapRatio(target, box);
      final containsCenter = target.contains(box.center);
      final score = iou * 3.0 +
          overlap * 2.4 +
          (containsCenter ? 0.6 : 0.0) +
          det.confidence * 0.8;
      if (score > bestScore) {
        bestScore = score;
        bestMatch = det;
      }
    }
    return bestMatch;
  }

  YOLOResult? _bestDetectionForLockedTarget(
    Rect target,
    List<YOLOResult> results,
  ) {
    final scored = <MapEntry<YOLOResult, double>>[];
    for (final det in results) {
      final score = _lockedMatchScore(target, det);
      if (score.isFinite) {
        scored.add(MapEntry(det, score));
      }
    }

    if (scored.isEmpty) return null;

    scored.sort((a, b) => b.value.compareTo(a.value));
    final best = scored.first;
    final minScore = _lockedLostFrames == 0 ? 3.1 : 2.2;
    if (best.value < minScore) return null;

    return best.key;
  }

  CoachingResult _decorateLockedSubjectCoachingSafe(CoachingResult coaching) {
    if (_lockedRoiCamera == null) return coaching;
    if (coaching.guidance.startsWith('[Subject] ')) return coaching;

    return CoachingResult(
      guidance: '[Subject] ${coaching.guidance}',
      subGuidance: coaching.subGuidance,
      level: coaching.level,
    );
  }

  void _showSubjectSelectionGuidance() {
    if (!mounted) return;
    setState(() {
      _guidance = '\uD0D0\uC9C0\uB41C \uD53C\uC0AC\uCCB4\uB97C \uB2E4\uC2DC \uC120\uD0DD\uD574\uC8FC\uC138\uC694';
      _subGuidance = '\uD53C\uC0AC\uCCB4\uB97C \uD0ED\uD558\uAC70\uB098 \uADF8 \uC704\uB97C \uB4DC\uB798\uADF8\uD574\uC11C \uB2E4\uC2DC \uACE0\uC815\uD574\uBCF4\uC138\uC694';
      _coachingLevel = CoachingLevel.caution;
      _isDrawingRoi = false;
      _roiDragStart = null;
      _roiDragCurrent = null;
    });
  }

  void _lockToDetection(YOLOResult detection) {
    final cameraRoi = _normalizedRect(detection);
    final screenRoi = _cameraToScreen(cameraRoi);

    _cameraController.setLockedRoi(
      left: cameraRoi.left,
      top: cameraRoi.top,
      right: cameraRoi.right,
      bottom: cameraRoi.bottom,
    );
    _sceneCoach.reset();

    setState(() {
      _lockedRoi = screenRoi;
      _lockedRoiCamera = cameraRoi;
      _lockedClassIndex = detection.classIndex;
      _lockedAnchorRoiCamera = cameraRoi;
      _lockedAppearanceSignature = detection.appearanceSignature;
      _lockedRecentAppearanceSignature = detection.appearanceSignature;
      _lockedTrackingDetection = detection;
      _lockedLostFrames = 0;
      _isDrawingRoi = false;
      _roiDragStart = null;
      _roiDragCurrent = null;
      _guidance = '\uAD6C\uB3C4\uB97C \uC7A1\uB294 \uC911...';
      _subGuidance = null;
      _coachingLevel = CoachingLevel.caution;
    });
  }

  YOLOResult? _bestDetectionAtScreenPoint(Offset localPosition) {
    if (_previewSize == Size.zero) return null;

    final filtered = _filterResultsForMode(_latestRawDetections);
    if (filtered.isEmpty) return null;

    final nx = (localPosition.dx / _previewSize.width).clamp(0.0, 1.0);
    final ny = (localPosition.dy / _previewSize.height).clamp(0.0, 1.0);
    final cameraPoint =
        _screenToCamera(Rect.fromLTWH(nx, ny, 0.0, 0.0)).topLeft;

    YOLOResult? bestMatch;
    double bestScore = double.negativeInfinity;

    for (final det in filtered) {
      final box = _normalizedRect(det);
      final containsPoint = box.contains(cameraPoint);
      final centerDistance = math.sqrt(
        math.pow(box.center.dx - cameraPoint.dx, 2) +
            math.pow(box.center.dy - cameraPoint.dy, 2),
      );
      final score = (containsPoint ? 3.0 : 0.0) +
          det.confidence * 1.5 -
          centerDistance * 4.0 -
          _rectArea(box) * 0.35;
      if (score > bestScore) {
        bestScore = score;
        bestMatch = det;
      }
    }

    if (bestMatch == null) return null;
    final bestBox = _normalizedRect(bestMatch);
    final maxDistance = bestBox.contains(cameraPoint)
        ? 0.0
        : math.max(bestBox.width, bestBox.height) * 0.7;
    final dx = bestBox.center.dx - cameraPoint.dx;
    final dy = bestBox.center.dy - cameraPoint.dy;
    final actualDistance = math.sqrt(dx * dx + dy * dy);
    if (!bestBox.contains(cameraPoint) && actualDistance > maxDistance) {
      return null;
    }
    return bestMatch;
  }

  void _handleDetections(List<YOLOResult> results) {
    if (!mounted || _isPortraitMode) return;
    _latestRawDetections = results;
    final filteredResults = _filterResultsForMode(results);

    List<YOLOResult> forCoaching;
    Rect? updatedScreenRoi;
    var subjectInFrameForCoaching = true;
    var holdWithoutFreshDetection = false;

    final locked = _lockedRoiCamera;
    if (locked != null) {
      final bestMatch = _bestDetectionForLockedTarget(locked, filteredResults);
      if (bestMatch != null) {
        forCoaching = [bestMatch];
        subjectInFrameForCoaching = true;
        _lockedLostFrames = 0;
        final rawBox = _normalizedRect(bestMatch);
        updatedScreenRoi = _cameraToScreen(rawBox);
        _lockedRoiCamera = rawBox;
        _lockedClassIndex = bestMatch.classIndex;
        _lockedAppearanceSignature ??= bestMatch.appearanceSignature;
        _lockedRecentAppearanceSignature = _blendAppearanceSignature(
          _lockedRecentAppearanceSignature,
          bestMatch.appearanceSignature,
        );
        _lockedTrackingDetection = bestMatch;
        _cameraController.setLockedRoi(
          left: rawBox.left,
          top: rawBox.top,
          right: rawBox.right,
          bottom: rawBox.bottom,
        );
      } else {
        _lockedLostFrames++;
        final holdTrack = _lockedLostFrames < _lockLostFrameTolerance &&
            _lockedTrackingDetection != null;
        if (holdTrack) {
          forCoaching = const [];
          subjectInFrameForCoaching = true;
          holdWithoutFreshDetection = true;
        } else {
          _lockedTrackingDetection = null;
          subjectInFrameForCoaching = false;
          _cameraController.setLockedRoi();
          forCoaching = [];
        }
      }
    } else {
      forCoaching = filteredResults;
    }

    final frameSize =
        _previewSize == Size.zero ? MediaQuery.sizeOf(context) : _previewSize;
    CoachingResult? coaching;
    var coachingChanged = false;
    if (!holdWithoutFreshDetection) {
      coaching = _decorateLockedSubjectCoachingSafe(
        _sceneCoach.updateDetections(
          forCoaching,
          frameSize,
          subjectLocked: locked != null,
          subjectInFrame: subjectInFrameForCoaching,
        ),
      );

      coachingChanged = coaching.guidance != _guidance ||
          coaching.subGuidance != _subGuidance ||
          coaching.level != _coachingLevel;
    }

    final roiMoved = updatedScreenRoi != null &&
        (_lockedRoi == null ||
            (_lockedRoi!.left - updatedScreenRoi.left).abs() > 0.004 ||
            (_lockedRoi!.top - updatedScreenRoi.top).abs() > 0.004 ||
            (_lockedRoi!.right - updatedScreenRoi.right).abs() > 0.004 ||
            (_lockedRoi!.bottom - updatedScreenRoi.bottom).abs() > 0.004);

    final subjectLostBox = !subjectInFrameForCoaching && _lockedRoi != null;

    if (coachingChanged || roiMoved || subjectLostBox) {
      setState(() {
        if (coachingChanged) {
          _guidance = coaching!.guidance;
          _subGuidance = coaching.subGuidance;
          _coachingLevel = coaching.level;
        }
        if (roiMoved) _lockedRoi = updatedScreenRoi;
        if (subjectLostBox) _lockedRoi = null;
      });
    }
  }

  void _handlePoseDetections(List<YOLOResult> results) {
    if (!mounted || !_isPortraitMode) return;

    _portraitHandler.isFrontCamera = _isFrontCamera;
    final analysis = _portraitHandler.processResults(results);

    if (!analysis.hasPersonStable) {
      _portraitLostFrames++;
      if (_portraitLostFrames <= _portraitLostFrameTolerance) {
        return;
      }
    } else {
      _portraitLostFrames = 0;
    }

    setState(() {
      _portraitOverlayData = analysis.overlayData;
      _portraitCoaching = analysis.coaching;
    });
  }

  Future<void> _setZoom(double zoomLevel) async {
    setState(() => _selectedZoom = zoomLevel);
    await _cameraController.setZoomLevel(zoomLevel);
  }

  Future<void> _switchCamera() async {
    await _cameraController.switchCamera();
    if (!mounted) return;

    _sceneCoach.reset();
    _resetPortraitState();

    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _selectedZoom = 1.0;
      _currentZoom = 1.0;
      _guidance = '\uAD6C\uB3C4\uB97C \uC7A1\uB294 \uC911...';
      _subGuidance = null;
      _coachingLevel = CoachingLevel.caution;
      _focusPoint = null;
      _showFocusIndicator = false;
      _tiltX = 0.0;
      _gravX = 0.0;
      _gravY = 9.8;
    });

    await _cameraController.setZoomLevel(1.0);
  }

  void _onModeChanged(ShootingMode mode) {
    _sceneCoach.reset();
    _cameraController.setLockedRoi();
    _resetPortraitState();

    setState(() {
      _shootingMode = mode;
      _guidance = '\uAD6C\uB3C4\uB97C \uC7A1\uB294 \uC911...';
      _subGuidance = null;
      _coachingLevel = CoachingLevel.caution;
      _focusPoint = null;
      _showFocusIndicator = false;
      _isDrawingRoi = false;
      _roiDragStart = null;
      _roiDragCurrent = null;
      _lockedRoi = null;
      _lockedRoiCamera = null;
      _lockedClassIndex = null;
      _lockedAnchorRoiCamera = null;
      _lockedAppearanceSignature = null;
      _lockedRecentAppearanceSignature = null;
      _lockedTrackingDetection = null;
      _lockedLostFrames = 0;
    });
  }

  void _onTapFocus(Offset localPosition) {
    if (_previewSize == Size.zero || _isPortraitMode) return;

    final detection = _bestDetectionAtScreenPoint(localPosition);
    if (detection != null) {
      _lockToDetection(detection);
      return;
    }

    final nx = (localPosition.dx / _previewSize.width).clamp(0.0, 1.0);
    final ny = (localPosition.dy / _previewSize.height).clamp(0.0, 1.0);

    _cameraController.setFocusPoint(nx, ny);

    setState(() {
      _focusPoint = localPosition;
      _showFocusIndicator = true;
    });

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _showFocusIndicator = false);
      }
    });
  }

  void _toggleTorch() => setState(() => _torchOn = !_torchOn);

  void _toggleRoiLock() {
    if (_lockedRoi != null) {
      _clearLockedRoi();
    } else {
      setState(() => _isDrawingRoi = !_isDrawingRoi);
    }
  }

  void _clearLockedRoi() {
    _cameraController.setLockedRoi();
    _sceneCoach.reset();
    setState(() {
      _lockedRoi = null;
      _lockedRoiCamera = null;
      _lockedClassIndex = null;
      _lockedAnchorRoiCamera = null;
      _lockedAppearanceSignature = null;
      _lockedRecentAppearanceSignature = null;
      _lockedTrackingDetection = null;
      _lockedLostFrames = 0;
      _isDrawingRoi = false;
      _roiDragStart = null;
      _roiDragCurrent = null;
      _guidance = '\uAD6C\uB3C4\uB97C \uC7A1\uB294 \uC911...';
      _subGuidance = null;
      _coachingLevel = CoachingLevel.caution;
    });
  }

  void _onRoiPanStart(Offset pos) {
    setState(() {
      _roiDragStart = pos;
      _roiDragCurrent = pos;
    });
  }

  void _onRoiPanUpdate(Offset pos) {
    setState(() => _roiDragCurrent = pos);
  }

  Rect _screenToCamera(Rect screen) {
    final sa = _previewSize.width / _previewSize.height;
    if (sa < _cameraAspect) {
      final vx = sa / _cameraAspect;
      final ox = (1.0 - vx) / 2.0;
      return Rect.fromLTRB(
        screen.left * vx + ox,
        screen.top,
        screen.right * vx + ox,
        screen.bottom,
      );
    } else {
      final vy = _cameraAspect / sa;
      final oy = (1.0 - vy) / 2.0;
      return Rect.fromLTRB(
        screen.left,
        screen.top * vy + oy,
        screen.right,
        screen.bottom * vy + oy,
      );
    }
  }

  Rect _cameraToScreen(Rect cam) {
    final sa = _previewSize.width / _previewSize.height;
    if (sa < _cameraAspect) {
      final vx = sa / _cameraAspect;
      final ox = (1.0 - vx) / 2.0;
      return Rect.fromLTRB(
        ((cam.left - ox) / vx).clamp(0.0, 1.0),
        cam.top.clamp(0.0, 1.0),
        ((cam.right - ox) / vx).clamp(0.0, 1.0),
        cam.bottom.clamp(0.0, 1.0),
      );
    } else {
      final vy = _cameraAspect / sa;
      final oy = (1.0 - vy) / 2.0;
      return Rect.fromLTRB(
        cam.left.clamp(0.0, 1.0),
        ((cam.top - oy) / vy).clamp(0.0, 1.0),
        cam.right.clamp(0.0, 1.0),
        ((cam.bottom - oy) / vy).clamp(0.0, 1.0),
      );
    }
  }

  void _onRoiPanEnd() {
    final start = _roiDragStart;
    final end = _roiDragCurrent;
    if (start == null || end == null) return;

    final rawRect = Rect.fromPoints(start, end);
    if (rawRect.width < 40 || rawRect.height < 40) {
      setState(() {
        _roiDragStart = null;
        _roiDragCurrent = null;
        _isDrawingRoi = false;
      });
      return;
    }

    final size = _previewSize;
    final dragScreen = Rect.fromLTRB(
      (rawRect.left / size.width).clamp(0.0, 1.0),
      (rawRect.top / size.height).clamp(0.0, 1.0),
      (rawRect.right / size.width).clamp(0.0, 1.0),
      (rawRect.bottom / size.height).clamp(0.0, 1.0),
    );

    final dragCamera = _screenToCamera(dragScreen);

    final bestMatch = _bestDetectionForTarget(
      dragCamera,
      _filterResultsForMode(_latestRawDetections),
    );
    if (bestMatch == null) {
      _showSubjectSelectionGuidance();
      return;
    }
    final bestBox = _normalizedRect(bestMatch);

    final matchIou = _iou(dragCamera, bestBox);
    final matchOverlap = _overlapRatio(dragCamera, bestBox);
    final hasUsableMatch = matchIou >= 0.18 || matchOverlap >= 0.45;
    if (!hasUsableMatch) {
      _showSubjectSelectionGuidance();
      return;
    }
    _lockToDetection(bestMatch);
  }

  void _cycleTimer() {
    const options = [0, 3, 10];
    final idx = options.indexOf(_timerSeconds);
    setState(() => _timerSeconds = options[(idx + 1) % options.length]);
  }

  Future<void> _captureAndSavePhoto() async {
    if (_isSaving || _countdown > 0) return;

    if (_timerSeconds > 0) {
      setState(() => _countdown = _timerSeconds);

      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();

        setState(() => _countdown--);

        if (_countdown <= 0) {
          timer.cancel();
          _doCapture();
        }
      });
      return;
    }

    await _doCapture();
  }

  Future<void> _doCapture() async {
    if (!mounted) return;

    final hasAccess = await Gal.hasAccess();
    if (!hasAccess && !await Gal.requestAccess()) return;

    setState(() => _isSaving = true);

    try {
      if (_torchOn && !_isFrontCamera) {
        await _cameraController.setTorchMode(true);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      final bytes = await _cameraController.captureHighRes();

      if (_torchOn && !_isFrontCamera) {
        await _cameraController.setTorchMode(false);
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to capture camera frame.');
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _showFlash = true;
        });

        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showFlash = false);
        });
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      Gal.putImageBytes(bytes, name: 'pozy_$timestamp').then((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('\uC0AC\uC9C4\uC744 \uAC24\uB7EC\uB9AC\uC5D0 \uC800\uC7A5\uD588\uC5B4\uC694.')),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\uCD2C\uC601\uC5D0 \uC2E4\uD328\uD588\uC5B4\uC694: $e')),
        );
      }
    }
  }

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
                '\uC778\uBB3C',
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

  CoachingLevel _portraitCoachingLevel() {
    return switch (_portraitCoaching.priority) {
      portrait.CoachingPriority.perfect => CoachingLevel.good,
      portrait.CoachingPriority.critical => CoachingLevel.warning,
      _ => CoachingLevel.caution,
    };
  }

  String? _portraitSubGuidance() {
    final lighting = _portraitHandler.lastLighting;
    final lightConf = _portraitHandler.lastLightingConf;
    if (lighting != portrait.LightingCondition.unknown && lightConf > 0) {
      return '조명: ${_portraitHandler.lightingLabel(lighting)}';
    }
    return _portraitCoaching.reason;
  }

  String _shotTypeLabel() {
    if (_portraitCoaching.priority == portrait.CoachingPriority.critical) {
      return '';
    }

    switch (_portraitOverlayData.shotType) {
      case portrait.ShotType.extremeCloseUp:
        return '\uC775\uC2A4\uD2B8\uB9BC \uD074\uB85C\uC988\uC5C5';
      case portrait.ShotType.closeUp:
        return '\uD074\uB85C\uC988\uC5C5';
      case portrait.ShotType.headShot:
        return '\uD5E4\uB4DC\uC0F7';
      case portrait.ShotType.upperBody:
        return '\uC0C1\uBC18\uC2E0';
      case portrait.ShotType.waistShot:
        return '\uD5C8\uB9AC\uC0F7';
      case portrait.ShotType.kneeShot:
        return '\uBB34\uB98E\uC0F7';
      case portrait.ShotType.fullBody:
        return '\uC804\uC2E0';
      case portrait.ShotType.environmental:
        return '\uD658\uACBD \uC778\uBB3C';
      case portrait.ShotType.unknown:
        return '\uC778\uBB3C \uCF54\uCE6D \uD65C\uC131';
    }
  }

  @override
  void dispose() {
    _accelerometerSub?.cancel();
    _countdownTimer?.cancel();
    _cameraController.stop();
    _portraitHandler.dispose();
    super.dispose();
  }

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
                _previewSize = Size(constraints.maxWidth, constraints.maxHeight);

                return YOLOView(
                  key: ValueKey(
                    'yolo_${_isPortraitMode ? 'pose' : 'detect'}_${_isFrontCamera ? 'front' : 'back'}',
                  ),
                  controller: _cameraController,
                  modelPath: _isPortraitMode ? poseModelPath : detectModelPath,
                  task: _isPortraitMode ? YOLOTask.pose : YOLOTask.detect,
                  useGpu: true,
                  showNativeUI: false,
                  showOverlays: false,
                  confidenceThreshold: _isPortraitMode
                      ? poseConfidenceThreshold
                      : detectionConfidenceThreshold,
                  streamingConfig: _isPortraitMode
                      ? const YOLOStreamingConfig.withPoses()
                      : const YOLOStreamingConfig.minimal(),
                  lensFacing:
                      _isFrontCamera ? LensFacing.front : LensFacing.back,
                  onResult:
                      _isPortraitMode ? _handlePoseDetections : _handleDetections,
                  onZoomChanged: (zoomLevel) {
                    if (!mounted) return;
                    setState(() => _currentZoom = zoomLevel);
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
            IgnorePointer(
              child: CustomPaint(
                painter: _isPortraitMode
                    ? PortraitOverlayPainter(data: _portraitOverlayData)
                    : _ThirdsGridPainter(),
                size: Size.infinite,
              ),
            ),
            if (!_isPortraitMode)
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: _isDrawingRoi
                    ? null
                    : (details) => _onTapFocus(details.localPosition),
                onPanStart:
                    _isDrawingRoi ? (d) => _onRoiPanStart(d.localPosition) : null,
                onPanUpdate:
                    _isDrawingRoi ? (d) => _onRoiPanUpdate(d.localPosition) : null,
                onPanEnd: _isDrawingRoi ? (_) => _onRoiPanEnd() : null,
              ),
            if (!_isPortraitMode &&
                (_lockedRoi != null ||
                    (_isDrawingRoi &&
                        _roiDragStart != null &&
                        _roiDragCurrent != null)))
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RoiPainter(
                      lockedRoi: _lockedRoi,
                      dragStart: _roiDragStart,
                      dragEnd: _roiDragCurrent,
                      isDrawing: _isDrawingRoi,
                    ),
                  ),
                ),
              ),
            if (!_isPortraitMode && _isDrawingRoi)
              Positioned(
                top: 110,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '\uD53C\uC0AC\uCCB4\uB97C \uD0ED\uD558\uAC70\uB098 \uB4DC\uB798\uADF8\uD574 \uC120\uD0DD\uD558\uC138\uC694',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
            if (!_isPortraitMode && _showFocusIndicator && _focusPoint != null)
              Positioned(
                left: _focusPoint!.dx - 30,
                top: _focusPoint!.dy - 30,
                child: IgnorePointer(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 64,
              right: 12,
              child: IgnorePointer(
                child: CoachingSpeechBubble(
                  guidance: _isPortraitMode
                      ? _portraitCoaching.message
                      : _guidance,
                  subGuidance: _isPortraitMode
                      ? _portraitSubGuidance()
                      : _subGuidance,
                  level: _isPortraitMode
                      ? _portraitCoachingLevel()
                      : _coachingLevel,
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: _isPortraitMode
                  ? _buildPortraitTopBar()
                  : _TopCameraBar(
                      onBack: widget.onBack,
                      torchOn: _torchOn,
                      onToggleTorch: _isFrontCamera ? null : _toggleTorch,
                      timerSeconds: _timerSeconds,
                      onCycleTimer: _cycleTimer,
                      isDrawingRoi: _isDrawingRoi,
                      isRoiLocked: _lockedRoi != null,
                      onToggleRoiLock: _toggleRoiLock,
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom,
              child: _BottomCameraControls(
                zoomPresets: _zoomPresets,
                selectedZoom: _selectedZoom,
                isSaving: _isSaving,
                shootingMode: _shootingMode,
                isShootReady: _isPortraitMode
                    ? _portraitCoaching.priority ==
                        portrait.CoachingPriority.perfect
                    : _coachingLevel == CoachingLevel.good,
                shotTypeLabel: _isPortraitMode ? _shotTypeLabel() : null,
                onSelectZoom: _setZoom,
                onGallery: () => widget.onMoveTab(1),
                onCapture: _captureAndSavePhoto,
                onFlipCamera: _switchCamera,
                onModeChanged: _onModeChanged,
              ),
            ),
            // 수평 지시선 — 항상 화면 중앙에 표시
            Center(
              child: IgnorePointer(
                child: HorizonLevelIndicator(
                  tiltDeg: _tiltX,
                  isLevel: _gravX.abs() > _gravY.abs()
                      ? (_tiltX.abs() - 90.0).abs() < 2.0
                      : _tiltX.abs() < 2.0,
                ),
              ),
            ),
            if (_countdown > 0)
              Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 120,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (_showFlash) Container(color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _TopCameraBar extends StatelessWidget {
  final VoidCallback onBack;
  final bool torchOn;
  final VoidCallback? onToggleTorch;
  final int timerSeconds;
  final VoidCallback onCycleTimer;
  final bool isDrawingRoi;
  final bool isRoiLocked;
  final VoidCallback onToggleRoiLock;

  const _TopCameraBar({
    required this.onBack,
    required this.torchOn,
    required this.onToggleTorch,
    required this.timerSeconds,
    required this.onCycleTimer,
    required this.isDrawingRoi,
    required this.isRoiLocked,
    required this.onToggleRoiLock,
  });

  @override
  Widget build(BuildContext context) {
    final lockIcon = isRoiLocked
        ? Icons.lock_rounded
        : isDrawingRoi
            ? Icons.close_rounded
            : Icons.center_focus_weak_rounded;
    final lockTint = isRoiLocked
        ? const Color(0xFF38BDF8)
        : isDrawingRoi
            ? const Color(0xFFFBBF24)
            : null;

    return Row(
      children: [
        _GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: onBack,
        ),
        const Spacer(),
        _GlassIconButton(
          icon: lockIcon,
          onTap: onToggleRoiLock,
          tint: lockTint,
        ),
        const SizedBox(width: 8),
        if (onToggleTorch != null) ...[
          _GlassIconButton(
            icon: torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            onTap: onToggleTorch!,
            tint: torchOn ? const Color(0xFFFBBF24) : null,
          ),
          const SizedBox(width: 8),
        ],
        _GlassIconButton(
          icon: Icons.timer_outlined,
          onTap: onCycleTimer,
          tint: timerSeconds > 0 ? const Color(0xFF38BDF8) : null,
          label: timerSeconds > 0 ? '${timerSeconds}s' : null,
        ),
      ],
    );
  }
}

class _BottomCameraControls extends StatelessWidget {
  final List<double> zoomPresets;
  final double selectedZoom;
  final bool isSaving;
  final ShootingMode shootingMode;
  final bool isShootReady;
  final String? shotTypeLabel;
  final ValueChanged<double> onSelectZoom;
  final VoidCallback onGallery;
  final Future<void> Function() onCapture;
  final Future<void> Function() onFlipCamera;
  final ValueChanged<ShootingMode> onModeChanged;

  const _BottomCameraControls({
    required this.zoomPresets,
    required this.selectedZoom,
    required this.isSaving,
    required this.shootingMode,
    required this.isShootReady,
    required this.shotTypeLabel,
    required this.onSelectZoom,
    required this.onGallery,
    required this.onCapture,
    required this.onFlipCamera,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shotTypeLabel != null && shotTypeLabel!.isNotEmpty) ...[
          Container(
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
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: zoomPresets
                    .map(
                      (zoom) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _ZoomPill(
                          label:
                              '${zoom.toStringAsFixed(zoom == zoom.truncateToDouble() ? 0 : 1)}x',
                          selected: (selectedZoom - zoom).abs() < 0.05,
                          onTap: () => onSelectZoom(zoom),
                        ),
                      ),
                    )
                    .toList(),
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
                  _CaptureButton(
                    isSaving: isSaving,
                    isShootReady: isShootReady,
                    onCapture: onCapture,
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
          ),
        ),
        const SizedBox(height: 16),
        _ModeSwitcher(
          selected: shootingMode,
          onChanged: onModeChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CaptureButton extends StatefulWidget {
  final bool isSaving;
  final bool isShootReady;
  final Future<void> Function() onCapture;

  const _CaptureButton({
    required this.isSaving,
    required this.isShootReady,
    required this.onCapture,
  });

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isSaving ? null : widget.onCapture,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) {
          final glow = widget.isShootReady ? _pulseAnim.value : 0.0;

          return Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: widget.isShootReady
                  ? const Color(0xFF4ADE80)
                  : Colors.white,
              shape: BoxShape.circle,
              boxShadow: widget.isShootReady
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4ADE80).withValues(
                          alpha: 0.35 + glow * 0.45,
                        ),
                        blurRadius: 12 + glow * 20,
                        spreadRadius: 2 + glow * 8,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: widget.isSaving
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
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
          );
        },
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  final ShootingMode selected;
  final ValueChanged<ShootingMode> onChanged;

  const _ModeSwitcher({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: ShootingMode.values.map((mode) {
          final isSelected = selected == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(mode),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mode.label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isSelected ? 18 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double diameter;
  final Color? tint;
  final String? label;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.diameter = 40,
    this.tint,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final bg = tint ?? const Color(0x66333333);
    final iconColor = tint != null ? const Color(0xFF0F172A) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: label != null ? null : diameter,
        height: diameter,
        padding: label != null
            ? const EdgeInsets.symmetric(horizontal: 10)
            : null,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: tint ?? const Color(0x4DFFFFFF),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: label != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: diameter * 0.42),
                  const SizedBox(width: 4),
                  Text(
                    label!,
                    style: TextStyle(color: iconColor, fontSize: 11),
                  ),
                ],
              )
            : Icon(icon, color: iconColor, size: diameter * 0.45),
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

class _RoiPainter extends CustomPainter {
  final Rect? lockedRoi;
  final Offset? dragStart;
  final Offset? dragEnd;
  final bool isDrawing;

  const _RoiPainter({
    this.lockedRoi,
    this.dragStart,
    this.dragEnd,
    required this.isDrawing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isDrawing && dragStart != null && dragEnd != null) {
      final rect = Rect.fromPoints(dragStart!, dragEnd!);
      _drawDashedRect(
        canvas,
        rect,
        const Color(0xCCFFFFFF),
        strokeWidth: 1.5,
      );
      return;
    }

    if (lockedRoi != null) {
      final r = lockedRoi!;
      final rect = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      );
      _drawLockedDetectionRect(canvas, rect, const Color(0xFF38BDF8));
    }
  }

  void _drawLockedDetectionRect(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, Paint()..color = const Color(0x1438BDF8));
  }

  void _drawDashedRect(
    Canvas canvas,
    Rect rect,
    Color color, {
    double strokeWidth = 1.5,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    const dash = 8.0;
    const gap = 5.0;

    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var d = 0.0;
      while (d < total) {
        canvas.drawLine(
          a + dir * d,
          a + dir * (d + dash).clamp(0.0, total),
          paint,
        );
        d += dash + gap;
      }
    }

    line(rect.topLeft, rect.topRight);
    line(rect.topRight, rect.bottomRight);
    line(rect.bottomRight, rect.bottomLeft);
    line(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(_RoiPainter old) =>
      old.lockedRoi != lockedRoi ||
      old.dragStart != dragStart ||
      old.dragEnd != dragEnd ||
      old.isDrawing != isDrawing;
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
