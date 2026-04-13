import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import 'package:pose_camera_app/coaching/coaching_result.dart';
import 'package:pose_camera_app/screen/camera/shooting_mode.dart';
import 'package:pose_camera_app/screen/camera/widgets/bottom_camera_controls.dart';
import 'package:pose_camera_app/screen/camera/widgets/portrait_top_bar.dart';
import 'package:pose_camera_app/screen/camera/widgets/roi_painter.dart';
import 'package:pose_camera_app/screen/camera/widgets/thirds_grid_painter.dart';
import 'package:pose_camera_app/screen/camera/widgets/top_camera_bar.dart';
import 'package:pose_camera_app/widget/coaching_interface.dart';
import 'package:pose_camera_app/widget/horizon_level_indicator.dart';
import 'package:pose_camera_app/coaching/object_coach.dart';
import 'package:pose_camera_app/coaching/portrait/portrait_mode_handler.dart';
import 'package:pose_camera_app/coaching/portrait/portrait_overlay_painter.dart';
import 'package:pose_camera_app/coaching/portrait/portrait_scene_state.dart'
    as portrait;
import 'package:pose_camera_app/coaching/subject/subject_detection.dart'
    show detectModelPath, detectionConfidenceThreshold;
import 'package:pose_camera_app/segmentation/composition_engine.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/composition_summary.dart';
import 'package:pose_camera_app/segmentation/composition_temporal_filter.dart';
import 'package:pose_camera_app/segmentation/fastscnn_segmentor.dart';
import 'package:pose_camera_app/segmentation/fastscnn_view.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

const String poseModelPath = 'yolov8n-pose_float16.tflite';
const double poseConfidenceThreshold = 0.25;

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
  final _landscapeController = FastScnnViewController();
  final _sceneCoach = ObjectCoach();
  final _portraitHandler = PortraitModeHandler();
  final _landscapeCompositionEngine = CompositionEngine();
  final _landscapeResolver = const CompositionResolver();
  final _landscapeTemporalFilter = CompositionTemporalFilter();

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
    message:
        '\uCE74\uBA54\uB77C\uB97C \uC5EC\uC720\uB86D\uAC8C \uB9DE\uCDB0\uC8FC\uC138\uC694.',
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
  CompositionDecision? _landscapeDecision;
  SegmentationResult? _landscapeSegmentation;

  Timer? _countdownTimer;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  bool _loggedFirstBuild = false;

  bool get _isPortraitMode => _shootingMode == ShootingMode.person;
  bool get _isLandscapeMode => _shootingMode == ShootingMode.landscape;
  bool get _isObjectMode => _shootingMode == ShootingMode.object;

  @override
  void initState() {
    super.initState();
    _shootingMode = widget.initialMode;
    debugPrint('[CameraScreen] initState mode=${_shootingMode.name}');

    unawaited(_portraitHandler.init());

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('[CameraScreen] postFrame restartCamera scheduled');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      try {
        debugPrint('[CameraScreen] restartCamera start');
        await _cameraController.restartCamera();
        debugPrint('[CameraScreen] restartCamera done');
        await _cameraController.setZoomLevel(_selectedZoom);
        debugPrint('[CameraScreen] setZoomLevel done zoom=$_selectedZoom');
        await _configureZoomPresets();
        debugPrint(
          '[CameraScreen] configureZoomPresets done presets=$_zoomPresets',
        );
      } catch (error, stackTrace) {
        debugPrint('[CameraScreen] startup error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });

    _startTiltMonitoring();
    _cameraController.onImageMetrics = _onImageMetrics;
  }

  void _startTiltMonitoring() {
    try {
      _accelerometerSub =
          accelerometerEventStream(
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
        next.indexed.every((e) => (e.$2 - _zoomPresets[e.$1]).abs() < 0.001)) {
      return;
    }

    setState(() => _zoomPresets = next);
  }

  void _resetPortraitState() {
    _portraitHandler.reset();
    _portraitLostFrames = 0;
    _portraitCoaching = const portrait.CoachingResult(
      message:
          '\uCE74\uBA54\uB77C\uB97C \uC5EC\uC720\uB86D\uAC8C \uB9DE\uCDB0\uC8FC\uC138\uC694.',
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

    if (_isLandscapeMode) return;

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
    final areaRatioNow = _rectArea(box) / math.max(_rectArea(previous), 0.0001);
    final areaRatioAnchor =
        _rectArea(box) / math.max(_rectArea(anchor), 0.0001);
    final aspectNow =
        (_rectAspect(box) - _rectAspect(previous)).abs() /
        math.max(_rectAspect(previous).abs(), 0.0001);
    final aspectAnchor =
        (_rectAspect(box) - _rectAspect(anchor)).abs() /
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
      final appearanceMatched =
          anchorAppearance <= maxAnchorAppearance ||
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
        (1.0 - (targetDistance / (_lockedLostFrames == 0 ? 0.32 : 0.50))).clamp(
          0.0,
          1.0,
        );
    final anchorDistanceScore =
        (1.0 - (anchorDistance / (_lockedLostFrames == 0 ? 0.45 : 0.70))).clamp(
          0.0,
          1.0,
        );
    final areaSimilarityNow = (1.0 - (areaRatioNow - 1.0).abs() / 1.4).clamp(
      0.0,
      1.0,
    );
    final areaSimilarityAnchor = (1.0 - (areaRatioAnchor - 1.0).abs() / 1.8)
        .clamp(0.0, 1.0);
    final aspectSimilarityNow = (1.0 - aspectNow / 1.1).clamp(0.0, 1.0);
    final aspectSimilarityAnchor = (1.0 - aspectAnchor / 1.3).clamp(0.0, 1.0);

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
      final score =
          iou * 3.0 +
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
      _guidance =
          '\uD0D0\uC9C0\uB41C \uD53C\uC0AC\uCCB4\uB97C \uB2E4\uC2DC \uC120\uD0DD\uD574\uC8FC\uC138\uC694';
      _subGuidance =
          '\uD53C\uC0AC\uCCB4\uB97C \uD0ED\uD558\uAC70\uB098 \uADF8 \uC704\uB97C \uB4DC\uB798\uADF8\uD574\uC11C \uB2E4\uC2DC \uACE0\uC815\uD574\uBCF4\uC138\uC694';
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
    final cameraPoint = _screenToCamera(
      Rect.fromLTWH(nx, ny, 0.0, 0.0),
    ).topLeft;

    YOLOResult? bestMatch;
    double bestScore = double.negativeInfinity;

    for (final det in filtered) {
      final box = _normalizedRect(det);
      final containsPoint = box.contains(cameraPoint);
      final centerDistance = math.sqrt(
        math.pow(box.center.dx - cameraPoint.dx, 2) +
            math.pow(box.center.dy - cameraPoint.dy, 2),
      );
      final score =
          (containsPoint ? 3.0 : 0.0) +
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
    if (!mounted || !_isObjectMode) return;
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
        final holdTrack =
            _lockedLostFrames < _lockLostFrameTolerance &&
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

    final frameSize = _previewSize == Size.zero
        ? MediaQuery.sizeOf(context)
        : _previewSize;
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

      coachingChanged =
          coaching.guidance != _guidance ||
          coaching.subGuidance != _subGuidance ||
          coaching.level != _coachingLevel;
    }

    final roiMoved =
        updatedScreenRoi != null &&
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

  /// 가속도계 데이터(_gravX, _gravY)로 기기 방향을 0/90/270 중 하나로 반환합니다.
  int get _deviceOrientationDeg {
    // |gravX| > 5 m/s² 이면 가로 모드
    if (_gravX.abs() > 5.0) {
      return _gravX < 0 ? 90 : 270; // 왼쪽/오른쪽 가로
    }
    return 0; // 세로
  }

  void _handlePoseDetections(List<YOLOResult> results) {
    if (!mounted || !_isPortraitMode) return;

    _portraitHandler.deviceOrientationDeg = _deviceOrientationDeg;
    _portraitHandler.isFrontCamera = _isFrontCamera;
    // 그룹샷 눈 감김 검사를 위해 YOLO 카메라의 captureFrame 콜백을 주입
    _portraitHandler.captureFrameCallback ??= _cameraController.captureFrame;
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
    if (_isLandscapeMode) {
      await _landscapeController.setZoomLevel(zoomLevel);
      return;
    }
    await _cameraController.setZoomLevel(zoomLevel);
  }

  Future<void> _switchCamera() async {
    if (_isLandscapeMode) {
      await _landscapeController.switchCamera();
    } else {
      await _cameraController.switchCamera();
    }
    if (!mounted) return;

    _sceneCoach.reset();
    _resetPortraitState();
    _landscapeTemporalFilter.reset();

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
      _landscapeDecision = null;
      _landscapeSegmentation = null;
    });

    if (_isLandscapeMode) {
      await _landscapeController.setZoomLevel(1.0);
      return;
    }
    await _cameraController.setZoomLevel(1.0);
  }

  void _onModeChanged(ShootingMode mode) {
    _sceneCoach.reset();
    _cameraController.setLockedRoi();
    _resetPortraitState();
    _landscapeCompositionEngine.reset();
    _landscapeTemporalFilter.reset();

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
      _landscapeDecision = null;
      _landscapeSegmentation = null;
    });
  }

  void _onTapFocus(Offset localPosition) {
    if (_previewSize == Size.zero || !_isObjectMode) return;

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
      if (_torchOn && !_isFrontCamera && !_isLandscapeMode) {
        await _cameraController.setTorchMode(true);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      final bytes = _isLandscapeMode
          ? await _landscapeController.captureFrame()
          : await _cameraController.captureHighRes();

      if (_torchOn && !_isFrontCamera && !_isLandscapeMode) {
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
            const SnackBar(
              content: Text(
                '\uC0AC\uC9C4\uC744 \uAC24\uB7EC\uB9AC\uC5D0 \uC800\uC7A5\uD588\uC5B4\uC694.',
              ),
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\uCD2C\uC601\uC5D0 \uC2E4\uD328\uD588\uC5B4\uC694: $e',
            ),
          ),
        );
      }
    }
  }

  void _handleLandscapeFrame(FastScnnFrame frame) {
    if (!mounted || !_isLandscapeMode) return;

    final raw = LandscapeAnalyzer.analyzeFeatures(frame.result);
    final smoothed = _landscapeTemporalFilter.smooth(raw);
    final decision = _landscapeTemporalFilter.stabilize(
      _landscapeResolver.resolve(smoothed),
    );
    final summary = _landscapeCompositionEngine.evaluate(
      features: smoothed,
      decision: decision,
    );
    final landscapeSubGuidance =
        decision.secondaryGuidance ??
        (decision.primaryGuidance == summary.guideMessage
            ? null
            : decision.primaryGuidance);
    final landscapeLevel = _landscapeCoachingLevel(summary.guideState);

    setState(() {
      _landscapeSegmentation = frame.result;
      _landscapeDecision = decision;
      _isFrontCamera = frame.isFrontCamera;
      _currentZoom = frame.zoomLevel;
      _guidance = summary.guideMessage;
      _subGuidance = landscapeSubGuidance;
      _coachingLevel = landscapeLevel;
    });
    debugPrint(
      '[Landscape] frame applied seg=${frame.result.width}x${frame.result.height} '
      'front=${frame.isFrontCamera} zoom=${frame.zoomLevel.toStringAsFixed(2)} '
      'mode=${decision.compositionMode.name} overlay=${decision.overlayType}',
    );
  }

  CoachingLevel _landscapeCoachingLevel(CompositionGuideState state) {
    switch (state) {
      case CompositionGuideState.aligned:
        return CoachingLevel.good;
      case CompositionGuideState.nearlyAligned:
        return CoachingLevel.warning;
      case CompositionGuideState.searchingLeading:
      case CompositionGuideState.moveLeft:
      case CompositionGuideState.moveRight:
      case CompositionGuideState.moveUp:
      case CompositionGuideState.moveDown:
      case CompositionGuideState.adjustHorizon:
      case CompositionGuideState.adjustSkyMore:
      case CompositionGuideState.adjustGroundMore:
        return CoachingLevel.warning;
    }
  }

  Widget _buildCameraPreview() {
    if (_isLandscapeMode) {
      return FastScnnView(
        key: ValueKey('fastscnn_${_isFrontCamera ? 'front' : 'back'}'),
        controller: _landscapeController,
        frameSkipLevel: 2,
        inferenceIntervalMs: 220,
        startWithBackCamera: !_isFrontCamera,
        onResult: _handleLandscapeFrame,
        onZoomChanged: (zoomLevel) {
          if (!mounted) return;
          setState(() => _currentZoom = zoomLevel);
        },
      );
    }

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
      lensFacing: _isFrontCamera ? LensFacing.front : LensFacing.back,
      onResult: _isPortraitMode ? _handlePoseDetections : _handleDetections,
      onZoomChanged: (zoomLevel) {
        if (!mounted) return;
        setState(() => _currentZoom = zoomLevel);
      },
    );
  }

  Widget _buildPortraitTopBar() {
    return PortraitTopBar(
      onBack: widget.onBack,
      isFrontCamera: _isFrontCamera,
      currentZoom: _currentZoom,
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
    _landscapeController.stop();
    _portraitHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedFirstBuild) {
      _loggedFirstBuild = true;
      debugPrint('[CameraScreen] first build mode=${_shootingMode.name}');
    }
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
                return _buildCameraPreview();
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
                    : const ThirdsGridPainter(),
                size: Size.infinite,
              ),
            ),
            if (_isObjectMode)
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: _isDrawingRoi
                    ? null
                    : (details) => _onTapFocus(details.localPosition),
                onPanStart: _isDrawingRoi
                    ? (d) => _onRoiPanStart(d.localPosition)
                    : null,
                onPanUpdate: _isDrawingRoi
                    ? (d) => _onRoiPanUpdate(d.localPosition)
                    : null,
                onPanEnd: _isDrawingRoi ? (_) => _onRoiPanEnd() : null,
              ),
            if (_isObjectMode &&
                (_lockedRoi != null ||
                    (_isDrawingRoi &&
                        _roiDragStart != null &&
                        _roiDragCurrent != null)))
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: RoiPainter(
                      lockedRoi: _lockedRoi,
                      dragStart: _roiDragStart,
                      dragEnd: _roiDragCurrent,
                      isDrawing: _isDrawingRoi,
                    ),
                  ),
                ),
              ),
            if (_isObjectMode && _isDrawingRoi)
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
            if (_isObjectMode && _showFocusIndicator && _focusPoint != null)
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
                  : TopCameraBar(
                      onBack: widget.onBack,
                      torchOn: _torchOn,
                      onToggleTorch: (_isFrontCamera || _isLandscapeMode)
                          ? null
                          : _toggleTorch,
                      timerSeconds: _timerSeconds,
                      onCycleTimer: _cycleTimer,
                      isDrawingRoi: _isDrawingRoi,
                      isRoiLocked: _lockedRoi != null,
                      onToggleRoiLock: _isObjectMode ? _toggleRoiLock : null,
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom,
              child: BottomCameraControls(
                zoomPresets: _zoomPresets,
                selectedZoom: _selectedZoom,
                isSaving: _isSaving,
                shootingMode: _shootingMode,
                isShootReady: _isPortraitMode
                    ? _portraitCoaching.priority ==
                          portrait.CoachingPriority.perfect
                    : _isLandscapeMode
                    ? true
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
            if (!_isLandscapeMode)
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
