import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pose_camera_app/coaching/portrait/portrait_mode_handler.dart';
import 'package:pose_camera_app/coaching/portrait/portrait_overlay_painter.dart';
import 'package:pose_camera_app/coaching/portrait/portrait_scene_state.dart';
import 'package:pose_camera_app/composition/composition_rule.dart';
import 'package:pose_camera_app/composition/composition_rule_registry.dart';
import 'package:ultralytics_yolo/yolo.dart';

const String _poseModelPath = 'yolov8n-pose_float16.tflite';
const double _poseConfidenceThreshold = 0.15;
const double _poseIouThreshold = 0.65;
const int _stillImageStabilizationPasses = 6;

class PortraitAssetTestScreen extends StatefulWidget {
  const PortraitAssetTestScreen({super.key});

  @override
  State<PortraitAssetTestScreen> createState() => _PortraitAssetTestScreenState();
}

class _PortraitAssetTestScreenState extends State<PortraitAssetTestScreen> {
  final PortraitModeHandler _handler = PortraitModeHandler();
  late final YOLO _yolo = YOLO(
    modelPath: _poseModelPath,
    task: YOLOTask.pose,
    useGpu: true,
    useMultiInstance: true,
  );

  bool _isLoading = true;
  String _loadingMessage = '인물 테스트 환경을 준비하는 중...';
  String? _error;
  List<_PortraitAssetResult> _results = const [];
  int _loadedCount = 0;
  int _totalCount = 0;
  PortraitIntent _intent = PortraitIntent.single;
  bool _isFrontCamera = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _handler.dispose();
    unawaited(_yolo.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = '인물 테스트 환경을 준비하는 중...';
      _error = null;
      _results = const [];
      _loadedCount = 0;
      _totalCount = 0;
    });

    try {
      await _handler.init();
      _handler.setRule(CompositionRuleRegistry.of(CompositionRuleType.none));
      _handler.setIntent(_intent);
      _handler.isFrontCamera = _isFrontCamera;

      final ready = await _yolo.loadModel();
      if (!ready) {
        throw StateError('포즈 모델을 불러오지 못했어요.');
      }

      if (!mounted) return;
      setState(() {
        _loadingMessage = 'lib/assets 이미지를 찾는 중...';
      });

      final assetPaths = await _loadAssetPaths();
      if (assetPaths.isEmpty) {
        throw StateError('lib/assets 아래에서 테스트할 이미지를 찾지 못했어요.');
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _totalCount = assetPaths.length;
      });

      final nextResults = <_PortraitAssetResult>[];
      for (final path in assetPaths) {
        _handler.reset();
        _handler.setRule(CompositionRuleRegistry.of(CompositionRuleType.none));
        _handler.setIntent(_intent);
        _handler.isFrontCamera = _isFrontCamera;

        final data = await rootBundle.load(path);
        final bytes = data.buffer.asUint8List();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw StateError('이미지를 읽지 못했어요: $path');
        }
        final prediction = await _yolo.predict(
          bytes,
          confidenceThreshold: _poseConfidenceThreshold,
          iouThreshold: _poseIouThreshold,
        );
        final detections = (prediction['detections'] as List<dynamic>? ?? const [])
            .map((entry) => YOLOResult.fromMap(entry as Map<dynamic, dynamic>))
            .toList(growable: false);

        await _handler.analyzeStillImage(bytes, detections);
        PortraitAnalysisResult analysis = _handler.processResults(detections);
        for (int i = 1; i < _stillImageStabilizationPasses; i++) {
          analysis = _handler.processResults(detections);
        }

        nextResults.add(
          _PortraitAssetResult(
            assetPath: path,
            bytes: bytes,
            width: decoded.width,
            height: decoded.height,
            analysis: analysis,
            lightingLabel: _handler.lightingLabel(_handler.lastLighting),
          ),
        );

        if (!mounted) return;
        setState(() {
          _results = List<_PortraitAssetResult>.from(nextResults);
          _loadedCount = nextResults.length;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '$error';
      });
    }
  }

  Future<List<String>> _loadAssetPaths() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest.listAssets()
        .where(
          (path) =>
              path.startsWith('lib/assets/') &&
              (path.endsWith('.png') ||
                  path.endsWith('.jpg') ||
                  path.endsWith('.jpeg') ||
                  path.endsWith('.webp')),
        )
        .toList()
      ..sort();
    return paths;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('인물 에셋 테스트'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? _LoadingView(message: _loadingMessage)
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : Column(
              children: [
                _ControlPanel(
                  intent: _intent,
                  isFrontCamera: _isFrontCamera,
                  loadedCount: _loadedCount,
                  totalCount: _totalCount,
                  onIntentChanged: (intent) {
                    setState(() => _intent = intent);
                    _load();
                  },
                  onFrontCameraChanged: (value) {
                    setState(() => _isFrontCamera = value);
                    _load();
                  },
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 20),
                    itemBuilder: (context, index) => _ResultCard(
                      result: _results[index],
                      intent: _intent,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PortraitAssetResult {
  final String assetPath;
  final Uint8List bytes;
  final int width;
  final int height;
  final PortraitAnalysisResult analysis;
  final String lightingLabel;

  const _PortraitAssetResult({
    required this.assetPath,
    required this.bytes,
    required this.width,
    required this.height,
    required this.analysis,
    required this.lightingLabel,
  });
}

class _LoadingView extends StatelessWidget {
  final String message;

  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  final PortraitIntent intent;
  final bool isFrontCamera;
  final int loadedCount;
  final int totalCount;
  final ValueChanged<PortraitIntent> onIntentChanged;
  final ValueChanged<bool> onFrontCameraChanged;

  const _ControlPanel({
    required this.intent,
    required this.isFrontCamera,
    required this.loadedCount,
    required this.totalCount,
    required this.onIntentChanged,
    required this.onFrontCameraChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '분석 진행: $loadedCount / $totalCount',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _IntentChip(
                label: '인물',
                selected: intent == PortraitIntent.single,
                onTap: () => onIntentChanged(PortraitIntent.single),
              ),
              _IntentChip(
                label: '환경',
                selected: intent == PortraitIntent.environmental,
                onTap: () => onIntentChanged(PortraitIntent.environmental),
              ),
              _IntentChip(
                label: '그룹',
                selected: intent == PortraitIntent.group,
                onTap: () => onIntentChanged(PortraitIntent.group),
              ),
              FilterChip(
                selected: isFrontCamera,
                label: const Text('셀카 규칙 적용'),
                onSelected: onFrontCameraChanged,
                selectedColor: const Color(0xFFBFDBFE),
                backgroundColor: const Color(0xFF1A1A1A),
                labelStyle: TextStyle(
                  color: isFrontCamera ? const Color(0xFF10367D) : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntentChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _IntentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: const Color(0xFFBFDBFE),
      backgroundColor: const Color(0xFF1A1A1A),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF10367D) : Colors.white,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final _PortraitAssetResult result;
  final PortraitIntent intent;

  const _ResultCard({required this.result, required this.intent});

  @override
  Widget build(BuildContext context) {
    final analysis = result.analysis;
    final scene = analysis.sceneState;
    final overlay = analysis.overlayData.copyWithRule(
      CompositionRuleRegistry.of(CompositionRuleType.none),
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.assetPath.split('/').last,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: result.width / result.height,
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        result.bytes,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: PortraitOverlayPainter(
                            data: overlay,
                            showDebugGuides: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(label: 'Intent', value: _intentLabel(intent)),
                _Badge(label: 'Shot', value: _shotLabel(analysis.shotType)),
                _Badge(label: 'Priority', value: analysis.coaching.priority.name),
                _Badge(label: 'People', value: '${analysis.personCount}'),
                _Badge(
                  label: 'Stable',
                  value: analysis.hasPersonStable ? 'yes' : 'no',
                ),
                if (scene != null)
                  _Badge(
                    label: 'Lighting',
                    value: scene.lightingConfidence > 0
                        ? '${result.lightingLabel} ${_formatDecimal(scene.lightingConfidence)}'
                        : 'n/a',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              analysis.coaching.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (analysis.coaching.reason != null) ...[
              const SizedBox(height: 6),
              Text(
                analysis.coaching.reason!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (scene != null) _MetricGrid(scene: scene),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final PortraitSceneState scene;

  const _MetricGrid({required this.scene});

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (label: 'Headroom', value: _formatPercent(scene.headroomRatio)),
      (label: 'Foot space', value: _formatPercent(scene.footSpaceRatio)),
      (label: 'Person bbox', value: _formatPercent(scene.personBboxRatio)),
      (label: 'Face bbox', value: _formatPercent(scene.faceBoxRatio)),
      (label: 'Person center X', value: _formatDecimal(scene.personCenterX)),
      (label: 'Face center X', value: _formatDecimal(scene.faceCenterX)),
      (
        label: 'Eye midpoint Y',
        value: scene.eyeMidpoint != null ? _formatDecimal(scene.eyeMidpoint!.dy) : 'n/a',
      ),
      (label: 'Bottom joint cut', value: scene.isBottomJointCut ? 'risk' : 'ok'),
      (label: 'Has nose', value: scene.hasNose ? 'yes' : 'no'),
      (label: 'Has eyes', value: scene.hasEyes ? 'yes' : 'no'),
      (label: 'Has shoulders', value: scene.hasShoulders ? 'yes' : 'no'),
      (label: 'Visible keypoints', value: '${scene.visibleKeypointCount}'),
      (label: 'Eye confidence', value: _formatDecimal(scene.eyeConfidence)),
      (label: 'Shoulder conf', value: _formatDecimal(scene.shoulderConfidence)),
      (label: 'Ankle conf', value: _formatDecimal(scene.ankleConfidence)),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.15,
      ),
      itemBuilder: (context, index) {
        final row = rows[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                row.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final String value;

  const _Badge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        '$label  $value',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _formatPercent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _formatDecimal(double value) => value.toStringAsFixed(3);

String _intentLabel(PortraitIntent intent) {
  switch (intent) {
    case PortraitIntent.single:
      return 'single';
    case PortraitIntent.environmental:
      return 'environmental';
    case PortraitIntent.group:
      return 'group';
  }
}

String _shotLabel(ShotType shotType) {
  switch (shotType) {
    case ShotType.extremeCloseUp:
      return 'extremeCloseUp';
    case ShotType.closeUp:
      return 'closeUp';
    case ShotType.headShot:
      return 'headShot';
    case ShotType.upperBody:
      return 'upperBody';
    case ShotType.waistShot:
      return 'waistShot';
    case ShotType.kneeShot:
      return 'kneeShot';
    case ShotType.fullBody:
      return 'fullBody';
    case ShotType.environmental:
      return 'environmental';
    case ShotType.groupShot:
      return 'groupShot';
    case ShotType.unknown:
      return 'unknown';
  }
}
