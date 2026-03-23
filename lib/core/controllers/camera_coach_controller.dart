import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/enums/composition_mode.dart';
import 'package:pose_camera_app/core/enums/scene_type.dart';
import 'package:pose_camera_app/core/models/classification_result.dart';
import 'package:pose_camera_app/core/models/overlay_state.dart' as coach;
import 'package:pose_camera_app/core/models/subject_state.dart';
import 'package:pose_camera_app/core/services/math_stabilizer.dart';
import 'package:pose_camera_app/features/composition/composition_policy.dart';
import 'package:pose_camera_app/features/composition/golden_ratio_policy.dart';
import 'package:pose_camera_app/features/composition/rule_of_thirds_policy.dart';
import 'package:pose_camera_app/features/food/food_score_engine.dart';
import 'package:pose_camera_app/features/object/object_score_engine.dart';
import 'package:pose_camera_app/features/person/person_pose_tracker.dart';
import 'package:pose_camera_app/features/person/person_score_engine.dart';
import 'package:ultralytics_yolo/yolo.dart';

class CameraCoachController extends ChangeNotifier {
  CameraCoachController({
    required CompositionMode compositionMode,
    SceneType initialManualScene = SceneType.object,
  })  : _compositionMode = compositionMode,
        _manualScene = initialManualScene,
        _overlayState = coach.OverlayState.initial().copyWith(
          manualScene: initialManualScene,
          resolvedScene: initialManualScene,
        );

  final MathStabilizer _stabilizer = MathStabilizer();
  final PersonPoseTracker _personTracker = PersonPoseTracker();
  final PersonScoreEngine _personScoreEngine = PersonScoreEngine();
  final FoodScoreEngine _foodScoreEngine = FoodScoreEngine();
  final ObjectScoreEngine _objectScoreEngine = ObjectScoreEngine();

  final CompositionMode _compositionMode;
  SceneType _manualScene;
  coach.OverlayState _overlayState;
  ClassificationResult _latestClassification = ClassificationResult.unknown();
  SubjectState? _latestPerson;
  Offset? _preferredTarget;
  DateTime? _perfectLatchUntil;
  bool _isFrontCamera = false;

  CompositionMode get compositionMode => _compositionMode;
  SceneType get manualScene => _manualScene;
  coach.OverlayState get overlayState => _overlayState;

  CompositionPolicy get compositionPolicy {
    switch (_compositionMode) {
      case CompositionMode.goldenRatio:
        return GoldenRatioPolicy();
      case CompositionMode.ruleOfThirds:
        return RuleOfThirdsPolicy();
    }
  }

  void setManualScene(SceneType sceneType, Size screenSize) {
    _manualScene = sceneType;
    _rebuildState(screenSize);
    notifyListeners();
  }

  void setPreferredTarget(Offset tapPosition, Size screenSize) {
    final targets = compositionPolicy.getTargets(screenSize);
    _preferredTarget = _stabilizer.findNearestTarget(tapPosition, targets);
    _rebuildState(screenSize);
    notifyListeners();
  }

  void clearPreferredTarget(Size screenSize) {
    _preferredTarget = null;
    _rebuildState(screenSize);
    notifyListeners();
  }

  void applyClassificationResult(ClassificationResult result, Size screenSize) {
    _latestClassification = result;
    _rebuildState(screenSize);
    notifyListeners();
  }

  void onYoloResults(List<YOLOResult> results, Size screenSize) {
    _latestPerson = _personTracker.track(results, screenSize);
    _rebuildState(screenSize);
    notifyListeners();
  }

  void setCameraFacing(bool isFrontCamera, Size screenSize) {
    if (_isFrontCamera == isFrontCamera) return;
    _isFrontCamera = isFrontCamera;
    _rebuildState(screenSize);
    notifyListeners();
  }

  void reset(Size screenSize) {
    _latestPerson = null;
    _latestClassification = ClassificationResult.unknown();
    _preferredTarget = null;
    _perfectLatchUntil = null;
    _stabilizer.reset();
    _rebuildState(screenSize);
    notifyListeners();
  }

  void _rebuildState(Size screenSize) {
    final policy = compositionPolicy;
    final targets = policy.getTargets(screenSize);

    if (_latestPerson != null) {
      final smoothedPosition = _stabilizer.update(_latestPerson!.position);
      final target = _preferredTarget ??
          _stabilizer.getStickyTarget(targets, screenSize.width).point;
      final distance =
          target == null ? double.infinity : (smoothedPosition - target).distance;

      final rawPerfect = target != null && policy.isPerfect(distance, screenSize);
      final isPerfect = _applyPerfectLatch(rawPerfect);
      final alignmentLevel =
          _buildAlignmentLevel(distance: distance, screenSize: screenSize, isPerfect: isPerfect);

      final score = target == null
          ? 0.0
          : _personScoreEngine.calculate(
              subjectPosition: smoothedPosition,
              targetPosition: target,
              screenSize: screenSize,
              subjectBox: _latestPerson!.boundingBox,
              isPerfect: isPerfect,
            );

      _overlayState = coach.OverlayState(
        resolvedScene: SceneType.person,
        manualScene: _manualScene,
        personDetected: true,
        isPerfect: isPerfect,
        score: score,
        headline: _buildPersonHeadline(alignmentLevel),
        detail: _buildPersonDetail(alignmentLevel),
        movementHint: _buildMovementHint(
          subject: smoothedPosition,
          target: target,
          alignmentLevel: alignmentLevel,
        ),
        targetLocked: _preferredTarget != null,
        classificationSource: 'yolo-pose',
        classificationConfidence: _latestPerson!.confidence,
        labelPreview: 'person ${(_latestPerson!.confidence * 100).toStringAsFixed(0)}%',
        alignmentLevel: alignmentLevel,
        subjectPosition: smoothedPosition,
        targetPosition: target,
        boundingBox: _latestPerson!.boundingBox,
      );
      return;
    }

    _stabilizer.reset();
    final resolvedScene = _latestClassification.scene == SceneType.food ||
            _latestClassification.scene == SceneType.object
        ? _latestClassification.scene
        : _manualScene;
    final target = _preferredTarget ?? (targets.isNotEmpty ? targets.first : null);

    if (resolvedScene == SceneType.food) {
      final screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
      final score = target == null
          ? 0.0
          : _foodScoreEngine.calculate(
              virtualSubjectPosition: screenCenter,
              targetPosition: target,
              screenSize: screenSize,
              isPerfect: false,
            );
      _overlayState = coach.OverlayState(
        resolvedScene: SceneType.food,
        manualScene: _manualScene,
        personDetected: false,
        isPerfect: false,
        score: score,
        headline: '음식으로 분류했어',
        detail:
            '지금은 음식 위치 박스를 아직 안 잡고 있어. 대신 메인 피사체 중심을 선택한 타깃 점으로 맞추는 1차 버전이야.',
        movementHint: '접시나 음식 중심을 ${_targetWords(target, screenSize)} 타깃 점 쪽으로 옮겨봐.',
        targetLocked: _preferredTarget != null,
        classificationSource: _latestClassification.source,
        classificationConfidence: _latestClassification.confidence,
        labelPreview: _latestClassification.labelPreview,
        alignmentLevel: 'far',
        targetPosition: target,
      );
      return;
    }

    final screenCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final score = target == null
        ? 0.0
        : _objectScoreEngine.calculate(
            virtualSubjectPosition: screenCenter,
            targetPosition: target,
            screenSize: screenSize,
            isPerfect: false,
          );

    _overlayState = coach.OverlayState(
      resolvedScene: SceneType.object,
      manualScene: _manualScene,
      personDetected: false,
      isPerfect: false,
      score: score,
      headline: '사물 모드로 보고 있어',
      detail: '사람이 없으면 ML 라벨 결과와 네 수동 선택을 합쳐서 음식/사물을 나누도록 짜뒀어.',
      movementHint: '메인 사물 중심을 ${_targetWords(target, screenSize)} 타깃 점에 배치해봐.',
      targetLocked: _preferredTarget != null,
      classificationSource: _latestClassification.source,
      classificationConfidence: _latestClassification.confidence,
      labelPreview: _latestClassification.labelPreview,
      alignmentLevel: 'far',
      targetPosition: target,
    );
  }

  bool _applyPerfectLatch(bool rawPerfect) {
    final now = DateTime.now();

    if (rawPerfect) {
      _perfectLatchUntil = now.add(const Duration(milliseconds: 1000));
      return true;
    }

    if (_perfectLatchUntil != null && now.isBefore(_perfectLatchUntil!)) {
      return true;
    }

    _perfectLatchUntil = null;
    return false;
  }

  String _buildAlignmentLevel({
    required double distance,
    required Size screenSize,
    required bool isPerfect,
  }) {
    if (isPerfect) return 'perfect';

    final nearThreshold = screenSize.width * 0.18;
    if (distance <= nearThreshold) return 'near';

    return 'far';
  }

  String _buildPersonHeadline(String alignmentLevel) {
    switch (alignmentLevel) {
      case 'perfect':
        return '좋아, 지금 촬영해도 돼';
      case 'near':
        return '거의 맞았어';
      default:
        return '얼굴 중심을 타깃 점에 맞춰봐';
    }
  }

  String _buildPersonDetail(String alignmentLevel) {
    switch (alignmentLevel) {
      case 'perfect':
        return 'PERFECT 상태를 잠깐 유지하게 바꿔뒀어. 흔들려도 바로 사라지지 않아.';
      case 'near':
        return '얼굴 중심은 거의 들어왔어. 지금은 아주 조금만 더 맞추면 돼.';
      default:
        return '현재 사람 모드는 얼굴 중심(코+눈 평균)을 기준으로 추적하고 있어. 타깃 점을 탭해서 원하는 포인트를 고정할 수도 있어.';
    }
  }

  String _buildMovementHint({
    required Offset subject,
    required Offset? target,
    required String alignmentLevel,
  }) {
    if (target == null) {
      return '타깃 점을 한번 탭해서 원하는 구도 포인트를 고정해봐.';
    }

    if (alignmentLevel == 'perfect') {
      return '좋아. 지금 셔터를 눌러도 돼.';
    }

    final dx = target.dx - subject.dx;
    final dy = target.dy - subject.dy;

    final horizontal = _horizontalWord(dx);
    final vertical = _verticalWord(dy);

    if (alignmentLevel == 'near') {
      if (horizontal.isEmpty && vertical.isEmpty) {
        return '거의 맞았어. 지금 찍어도 괜찮아.';
      }
      if (horizontal.isNotEmpty && vertical.isNotEmpty) {
        return '$horizontal $vertical 방향으로 조금만 더 옮겨봐.';
      }
      return '${horizontal.isNotEmpty ? horizontal : vertical}으로 조금만 더 옮겨봐.';
    }

    if (horizontal.isEmpty && vertical.isEmpty) {
      return '좋아. 거의 맞았어. 지금 셔터를 눌러도 돼.';
    }
    if (horizontal.isNotEmpty && vertical.isNotEmpty) {
      return '$horizontal $vertical 방향으로 이동해봐.';
    }
    return '${horizontal.isNotEmpty ? horizontal : vertical}으로 이동해봐.';
  }

  String _horizontalWord(double dx) {
    if (dx.abs() < 18) return '';

    final normal = dx > 0 ? '오른쪽' : '왼쪽';
    if (!_isFrontCamera) return normal;

    return normal == '오른쪽' ? '왼쪽' : '오른쪽';
  }

  String _verticalWord(double dy) {
    if (dy.abs() < 18) return '';
    return dy > 0 ? '아래' : '위';
  }

  String _targetWords(Offset? target, Size size) {
    if (target == null) return '가까운';

    final horizontal = target.dx < size.width / 2 ? '왼쪽' : '오른쪽';
    final vertical = target.dy < size.height / 2 ? '위' : '아래';
    return '$horizontal $vertical';
  }
}