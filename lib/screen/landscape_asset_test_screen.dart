import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pose_camera_app/feature/landscape/landscape_overlay_painter.dart';
import 'package:pose_camera_app/segmentation/composition_engine.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/composition_summary.dart';
import 'package:pose_camera_app/segmentation/fastscnn_pipeline.dart';
import 'package:pose_camera_app/segmentation/fastscnn_segmentor.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class LandscapeAssetTestScreen extends StatefulWidget {
  const LandscapeAssetTestScreen({super.key});

  @override
  State<LandscapeAssetTestScreen> createState() => _LandscapeAssetTestScreenState();
}

class _LandscapeAssetTestScreenState extends State<LandscapeAssetTestScreen> {
  static const int _warmupPasses = 1;

  final FastScnnPipeline _pipeline = FastScnnPipeline();
  final LandscapeAnalyzer _analyzer = LandscapeAnalyzer();
  final CompositionResolver _resolver = const CompositionResolver();
  final CompositionEngine _engine = CompositionEngine();

  bool _isLoading = true;
  String _loadingMessage = 'Fast-SCNN 초기화 중...';
  String? _error;
  List<_LandscapeAssetResult> _results = const [];
  int _loadedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _analyzer.reset();
    _engine.reset();
    _pipeline.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Fast-SCNN 초기화 중...';
      _error = null;
      _results = const [];
      _loadedCount = 0;
      _totalCount = 0;
    });

    try {
      await _pipeline.initialize().timeout(const Duration(seconds: 8));
      if (!_pipeline.isInitialized) {
        throw StateError('Fast-SCNN 초기화에 실패했어요. Android 기기에서 테스트해 주세요.');
      }

      if (!mounted) return;
      setState(() {
        _loadingMessage = '에셋 목록을 불러오는 중...';
      });

      final assetPaths = await _loadAssetPaths().timeout(const Duration(seconds: 5));
      if (assetPaths.isEmpty) {
        throw StateError('lib/assets 아래에서 테스트할 이미지를 찾지 못했어요.');
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _totalCount = assetPaths.length;
      });

      for (final path in assetPaths) {
        _analyzer.reset();
        _engine.reset();

        final data = await rootBundle.load(path);
        final bytes = data.buffer.asUint8List();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw StateError('이미지를 열 수 없어요: $path');
        }

        final segmentation = await _pipeline
            .segment(bytes)
            .timeout(const Duration(seconds: 12));
        if (segmentation == null) {
          throw StateError('세그멘테이션 결과가 비어 있어요: $path');
        }

        LandscapeAnalysisFrame analysis = _analyzer.analyze(segmentation);
        for (int pass = 1; pass < _warmupPasses; pass++) {
          analysis = _analyzer.analyze(segmentation);
        }
        final decision = _resolver.resolve(analysis.features);
        final summary = _engine.evaluate(
          features: analysis.features,
          decision: decision,
        );

        if (!mounted) return;
        setState(() {
          _results = [
            ..._results,
            _LandscapeAssetResult(
              assetPath: path,
              bytes: bytes,
              width: decoded.width,
              height: decoded.height,
              segmentation: segmentation,
              analysis: analysis,
              decision: decision,
              summary: summary,
              debug: analysis.debug,
            ),
          ];
          _loadedCount++;
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
        title: const Text('풍경 샘플 테스트'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _loadingMessage,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : Column(
              children: [
                if (_totalCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '분석 진행 중: $_loadedCount / $_totalCount',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _totalCount == 0 ? null : _loadedCount / _totalCount,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 20),
                    itemBuilder: (context, index) =>
                        _ResultCard(result: _results[index]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LandscapeAssetResult {
  final String assetPath;
  final Uint8List bytes;
  final int width;
  final int height;
  final SegmentationResult segmentation;
  final LandscapeAnalysisFrame analysis;
  final CompositionDecision decision;
  final CompositionSummary summary;
  final HorizonDetectorDebug debug;

  const _LandscapeAssetResult({
    required this.assetPath,
    required this.bytes,
    required this.width,
    required this.height,
    required this.segmentation,
    required this.analysis,
    required this.decision,
    required this.summary,
    required this.debug,
  });
}

class _ResultCard extends StatelessWidget {
  final _LandscapeAssetResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final features = result.analysis.features;
    final advice = result.analysis.advice;
    final debug = result.debug;

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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(result.bytes, fit: BoxFit.cover),
                    CustomPaint(
                      painter: LandscapeSegmentationDotPainter(
                        result: result.segmentation,
                      ),
                    ),
                    CustomPaint(
                      painter: LandscapeCompositionOverlayPainter(
                        decision: result.decision,
                        advice: advice,
                        leadingEntryX: features.leadingEntryX,
                        leadingTargetX: features.leadingTargetX,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(label: 'mode ${result.decision.compositionMode.name}'),
                _Pill(label: 'source ${features.horizonSource.name}'),
                _Pill(label: 'valid ${features.horizonValidity.name}'),
                _Pill(label: 'guide ${advice.overlayState.name}'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              advice.primaryGuidance,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (advice.secondaryGuidance != null) ...[
              const SizedBox(height: 6),
              Text(
                advice.secondaryGuidance!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'skyOnly ${features.skyOnlyRatio.toStringAsFixed(2)}  topOpen ${features.topOpenAreaRatio.toStringAsFixed(2)}  horizon ${features.horizonConfidence.toStringAsFixed(2)}  stability ${features.horizonStability.toStringAsFixed(2)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'position ${features.horizonPosition?.toStringAsFixed(3) ?? '-'}  tilt ${features.horizonTiltDeg?.toStringAsFixed(1) ?? '-'}  quality ${result.summary.compositionQualityScore.toStringAsFixed(2)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'leading ${features.leadingLineStrength.toStringAsFixed(2)}  leadingConf ${features.leadingConfidence.toStringAsFixed(2)}  entryX ${features.leadingEntryX?.toStringAsFixed(3) ?? '-'}  targetX ${features.leadingTargetX?.toStringAsFixed(3) ?? '-'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Horizon Debug',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'detected ${features.horizonDetected}  source ${features.horizonSource.name}  validity ${features.horizonValidity.name}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'targetY ${advice.targetHorizonY?.toStringAsFixed(3) ?? '-'}  actualY ${features.horizonPosition?.toStringAsFixed(3) ?? '-'}  delta ${_formatDelta(advice, features)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'confidence ${features.horizonConfidence.toStringAsFixed(3)}  stability ${features.horizonStability.toStringAsFixed(3)}  type ${features.horizonType.name}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'guide ${advice.overlayState.name}  adjustment ${advice.recommendedAdjustmentY?.toStringAsFixed(3) ?? '-'}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'direct ${_formatCandidate(debug.direct)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'terrain ${_formatCandidate(debug.terrainFallback)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'gradient ${_formatCandidate(debug.gradientFallback)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'selected ${debug.selectedSource.name}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDelta(
    LandscapeOverlayAdvice advice,
    LandscapeFeatures features,
  ) {
    final target = advice.targetHorizonY;
    final actual = features.horizonPosition;
    if (target == null || actual == null) return '-';
    return (actual - target).toStringAsFixed(3);
  }

  String _formatCandidate(HorizonDetectionResult result) {
    return 'det ${result.horizonDetected} '
        'val ${result.validity.name} '
        'conf ${result.confidence.toStringAsFixed(3)} '
        'y ${result.averageY?.toStringAsFixed(3) ?? '-'}';
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 12),
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
