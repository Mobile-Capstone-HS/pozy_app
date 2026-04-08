import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pose_camera_app/segmentation/composition_engine.dart';
import 'package:pose_camera_app/segmentation/composition_resolver.dart';
import 'package:pose_camera_app/segmentation/composition_temporal_filter.dart';
import 'package:pose_camera_app/segmentation/fastscnn_pipeline.dart';
import 'package:pose_camera_app/segmentation/fastscnn_segmentor.dart';
import 'package:pose_camera_app/segmentation/landscape_analyzer.dart';

class LandscapeImageTestScreen extends StatefulWidget {
  final VoidCallback onBack;

  const LandscapeImageTestScreen({super.key, required this.onBack});

  @override
  State<LandscapeImageTestScreen> createState() =>
      _LandscapeImageTestScreenState();
}

class _LandscapeImageTestScreenState extends State<LandscapeImageTestScreen> {
  static const List<String> _candidateAssetPaths = <String>[
    'lib/assets/image.png',
    'lib/assets/image2.png',
    'lib/assets/image3.png',
  ];

  final FastScnnPipeline _pipeline = FastScnnPipeline();
  final CompositionResolver _resolver = const CompositionResolver();
  final CompositionTemporalFilter _temporalFilter = CompositionTemporalFilter();
  final CompositionEngine _compositionEngine = CompositionEngine();
  final PageController _pageController = PageController();
  StreamSubscription<Map<String, dynamic>>? _eventSub;

  SegmentationResult? _result;
  LandscapeFeatures? _features;
  CompositionDecision? _decision;
  String _guidance = '테스트 준비 중...';
  String _nativeStatus = 'native: waiting';
  bool _isRunning = false;
  List<String> _testAssetPaths = const <String>[];
  int _currentAssetIndex = 0;
  int _imageWidth = 0;
  int _imageHeight = 0;
  double? _preMs;
  double? _infMs;
  double? _postMs;
  double? _totMs;

  String get _currentAssetPath {
    if (_testAssetPaths.isEmpty) return _candidateAssetPaths.first;
    return _testAssetPaths[_currentAssetIndex.clamp(0, _testAssetPaths.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _pipeline.initialize();
    _testAssetPaths = await _resolveTestAssetPaths();
    await _loadImageMetaForAsset(_currentAssetPath);
    _eventSub = _pipeline.events.listen((event) {
      if (!mounted) return;
      if (event['type'] == 'perf') {
        setState(() {
          _preMs = (event['preprocessMs'] as num?)?.toDouble();
          _infMs = (event['inferenceMs'] as num?)?.toDouble();
          _postMs = (event['postprocessMs'] as num?)?.toDouble();
          _totMs = (event['totalMs'] as num?)?.toDouble();
          _nativeStatus = 'native: running';
        });
      } else if (event['type'] == 'status') {
        setState(() {
          _nativeStatus = 'native: ${event['state'] ?? 'unknown'}';
        });
      } else if (event['type'] == 'error') {
        setState(() {
          _nativeStatus = 'native error: ${event['message'] ?? 'unknown'}';
        });
      }
    });
    if (!mounted) return;
    setState(() {
      _guidance = _pipeline.isInitialized
          ? '준비 완료. 테스트를 실행해 주세요.'
          : '네이티브 초기화에 실패했습니다. 로그를 확인해 주세요.';
    });
  }

  Future<List<String>> _resolveTestAssetPaths() async {
    final collected = <String>{};
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final key in manifest.listAssets()) {
        final lower = key.toLowerCase();
        final isImage = lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.webp');
        if (isImage && key.startsWith('lib/assets/')) {
          collected.add(key);
        }
      }
    } catch (_) {}

    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(manifestJson);
      if (decoded is Map<String, dynamic>) {
        for (final key in decoded.keys) {
          final lower = key.toLowerCase();
          final isImage = lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.webp');
          if (isImage && key.startsWith('lib/assets/')) {
            collected.add(key);
          }
        }
      }
    } catch (_) {}

    for (final path in _candidateAssetPaths) {
      try {
        await rootBundle.load(path);
        collected.add(path);
      } catch (_) {}
    }

    final paths = collected.toList()..sort();
    return paths.isEmpty ? List<String>.from(_candidateAssetPaths) : paths;
  }

  Future<void> _loadImageMetaForAsset(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || !mounted) return;
      setState(() {
        _imageWidth = decoded.width;
        _imageHeight = decoded.height;
      });
    } catch (_) {}
  }

  Future<void> _onAssetChanged(int index) async {
    if (!mounted || index == _currentAssetIndex) return;
    _temporalFilter.reset();
    _compositionEngine.reset();
    setState(() {
      _currentAssetIndex = index;
      _result = null;
      _features = null;
      _decision = null;
      _guidance = '이미지가 변경되었습니다. 테스트를 실행해 주세요.';
    });
    await _loadImageMetaForAsset(_currentAssetPath);
  }

  Future<void> _runTest() async {
    if (_isRunning) return;
    final requestAssetPath = _currentAssetPath;
    _temporalFilter.reset();
    _compositionEngine.reset();
    setState(() {
      _isRunning = true;
      _guidance = '테스트 실행 중...';
    });

    try {
      final data = await rootBundle.load(requestAssetPath);
      final bytes = data.buffer.asUint8List();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        _imageWidth = decoded.width;
        _imageHeight = decoded.height;
      }

      final result = await _pipeline.segment(bytes);
      if (result == null) {
        setState(() {
          _guidance = '세그멘테이션 결과가 비어 있습니다.';
        });
        return;
      }

      final features = _temporalFilter.smooth(
        LandscapeAnalyzer.analyzeFeatures(result),
      );
      final decision = _temporalFilter.stabilize(_resolver.resolve(features));
      final summary = _compositionEngine.evaluate(
        features: features,
        decision: decision,
      );

      if (!mounted || requestAssetPath != _currentAssetPath) return;
      setState(() {
        _result = result;
        _features = features;
        _decision = decision;
        _guidance = summary.guideMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guidance = '테스트 실패: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _pageController.dispose();
    unawaited(_pipeline.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('풍경 정적 테스트'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: widget.onBack,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final imageRect = _computeImageRect(size);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_testAssetPaths.isEmpty)
                        const Center(
                          child: Text(
                            '테스트 가능한 이미지가 없습니다.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      else
                        PageView.builder(
                          controller: _pageController,
                          itemCount: _testAssetPaths.length,
                          onPageChanged: (index) {
                            unawaited(_onAssetChanged(index));
                          },
                          itemBuilder: (context, index) {
                            return Image.asset(
                              _testAssetPaths[index],
                              fit: BoxFit.contain,
                            );
                          },
                        ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _SegmentationImagePainter(
                            result: _result,
                            imageRect: imageRect,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _CompositionImagePainter(
                            decision: _decision,
                            imageRect: imageRect,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nativeStatus,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (_totMs != null)
                  Text(
                    'ms | pre:${_preMs?.toStringAsFixed(1) ?? '-'} '
                    'inf:${_infMs?.toStringAsFixed(1) ?? '-'} '
                    'post:${_postMs?.toStringAsFixed(1) ?? '-'} '
                    'tot:${_totMs?.toStringAsFixed(1) ?? '-'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                Text(
                  _guidance,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                if (_features != null)
                  Text(
                    'sky=${_features!.skyRatio.toStringAsFixed(2)} '
                    'ground=${(1 - _features!.skyRatio).toStringAsFixed(2)} '
                    'horizon=${_features!.horizonPosition?.toStringAsFixed(2) ?? '-'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                if (_decision != null)
                  Text(
                    'mode=${_decision!.compositionMode.name} conf=${_decision!.confidence.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _pipeline.isInitialized && !_isRunning
                      ? _runTest
                      : null,
                  child: Text(_isRunning ? 'Running...' : 'Fast-SCNN 테스트'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Rect _computeImageRect(Size canvas) {
    if (_imageWidth <= 0 || _imageHeight <= 0) {
      return Offset.zero & canvas;
    }
    final scale = math.min(
      canvas.width / _imageWidth,
      canvas.height / _imageHeight,
    );
    final w = _imageWidth * scale;
    final h = _imageHeight * scale;
    final left = (canvas.width - w) / 2;
    final top = (canvas.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }
}

class _SegmentationImagePainter extends CustomPainter {
  final SegmentationResult? result;
  final Rect imageRect;

  const _SegmentationImagePainter({
    required this.result,
    required this.imageRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final seg = result;
    if (seg == null || seg.height == 0 || seg.width == 0) return;

    final cellW = imageRect.width / seg.width;
    final cellH = imageRect.height / seg.height;
    final strideX = math.max(1, (seg.width / 24).round());
    final strideY = math.max(1, (seg.height / 14).round());
    final radius = math.max(
      1.5,
      math.min(cellW * strideX, cellH * strideY) * 0.14,
    );
    final paint = Paint();

    for (int y = 0; y < seg.height; y += strideY) {
      final row = seg.classMap[y];
      for (int x = 0; x < seg.width; x += strideX) {
        final color = _classColor(row[x]);
        if (color == null) continue;
        paint.color = color;
        canvas.drawCircle(
          Offset(
            imageRect.left + (x + 0.5) * cellW,
            imageRect.top + (y + 0.5) * cellH,
          ),
          radius,
          paint,
        );
      }
    }
  }

  Color? _classColor(int classId) {
    if (classId == CityscapesClass.sky) return const Color(0xAA4DB8FF);
    if (classId == CityscapesClass.vegetation) return const Color(0xAA62D26F);
    if (classId == CityscapesClass.terrain) return const Color(0xAAE2A15D);
    if (classId == CityscapesClass.road) return const Color(0xAA7A7A7A);
    return null;
  }

  @override
  bool shouldRepaint(covariant _SegmentationImagePainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.imageRect != imageRect;
  }
}

class _CompositionImagePainter extends CustomPainter {
  final CompositionDecision? decision;
  final Rect imageRect;

  const _CompositionImagePainter({
    required this.decision,
    required this.imageRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final d = decision;
    if (d == null || d.compositionMode == CompositionMode.none) return;
    if (imageRect.width <= 0 || imageRect.height <= 0) return;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    Offset p(double nx, double ny) => Offset(
      imageRect.left + imageRect.width * nx,
      imageRect.top + imageRect.height * ny,
    );

    canvas.drawLine(p(1 / 3, 0), p(1 / 3, 1), paint);
    canvas.drawLine(p(2 / 3, 0), p(2 / 3, 1), paint);
    canvas.drawLine(p(0, 1 / 3), p(1, 1 / 3), paint);
    canvas.drawLine(p(0, 2 / 3), p(1, 2 / 3), paint);
  }

  @override
  bool shouldRepaint(covariant _CompositionImagePainter oldDelegate) {
    return oldDelegate.decision != decision ||
        oldDelegate.imageRect != imageRect;
  }
}
