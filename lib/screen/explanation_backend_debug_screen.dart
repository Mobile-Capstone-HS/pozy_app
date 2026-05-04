import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../config/experimental_features.dart';
import '../feature/a_cut/model/photo_evaluation_result.dart';
import '../services/gemini_photo_explanation_services.dart';
import '../services/on_device_gemma_explanation_service.dart';
import '../services/photo_explanation_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../widget/app_top_bar.dart';

class _GemmaModelOption {
  const _GemmaModelOption({required this.label, required this.path});

  final String label;
  final String path;
}

class _GemmaBenchmarkRun {
  const _GemmaBenchmarkRun({
    required this.index,
    required this.modelLabel,
    required this.modelPath,
    required this.preloadMs,
    required this.nativeGenerationMs,
    required this.totalMs,
    required this.promptChars,
    required this.outputLength,
    required this.backendInfo,
    required this.gpuFallbackUsed,
    required this.jsonParse,
    this.error,
  });

  final int index;
  final String modelLabel;
  final String modelPath;
  final int? preloadMs;
  final int? nativeGenerationMs;
  final int? totalMs;
  final int? promptChars;
  final int? outputLength;
  final String backendInfo;
  final bool gpuFallbackUsed;
  final bool jsonParse;
  final String? error;
}

class ExplanationBackendDebugScreen extends StatefulWidget {
  const ExplanationBackendDebugScreen({
    super.key,
    required this.imageBytes,
    required this.result,
  });

  final Uint8List imageBytes;
  final PhotoEvaluationResult result;

  @override
  State<ExplanationBackendDebugScreen> createState() =>
      _ExplanationBackendDebugScreenState();
}

class _ExplanationBackendDebugScreenState
    extends State<ExplanationBackendDebugScreen> {
  static const List<String> _backendModes = ['gpu_preferred', 'cpu_only'];
  static const List<_GemmaModelOption> _gemmaModelOptions = [
    _GemmaModelOption(
      label: ExperimentalFeatures.gemmaE4bLabel,
      path: ExperimentalFeatures.gemmaE4bDeviceModelPath,
    ),
    _GemmaModelOption(
      label: ExperimentalFeatures.gemmaE2bLabel,
      path: ExperimentalFeatures.gemmaE2bDeviceModelPath,
    ),
  ];

  final GeminiTextOnlyPhotoExplanationService _geminiTextOnlyService =
      GeminiTextOnlyPhotoExplanationService();
  final GeminiImageScoresPhotoExplanationService _geminiImageScoresService =
      GeminiImageScoresPhotoExplanationService();

  bool _loading = false;
  bool _gemmaLoaded = false;
  String _selectedModelPath = ExperimentalFeatures.gemmaLiteRtLmModelPath;
  String _selectedBackendMode = ExperimentalFeatures.gemmaBackendMode;
  Map<String, dynamic>? _lastModelFileStatus;
  int? _lastGemmaLoadMs;
  int? _lastGemmaPreloadElapsedMs;
  String? _lastGemmaEngineConfigMode;
  String? _lastGemmaDecodingConfig;
  String? _statusMessage;

  final Map<String, PhotoExplanationResult> _results = {};
  final List<_GemmaBenchmarkRun> _gemmaRuns = [];

  // _prepareDebugVlmImagePath()에서 초기화
  final TextEditingController _visualImagePathController =
      TextEditingController();

  late final TextEditingController _visualPromptController;

  Map<String, dynamic>? _visualProbeResult;
  String? _selectedDebugVlmImagePath;

  final bool _runSequentialComparison =
      ExperimentalFeatures.gemmaDebugSequentialComparison;

  late OnDeviceGemmaExplanationService _gemmaService;
  late OnDeviceGemmaExplanationService _gemmaVlmService;

  void _updateGemmaServices() {
    _gemmaService = OnDeviceGemmaExplanationService(
      modelPath: _selectedModelPath,
      backendMode: _selectedBackendMode,
    );

    // 디버그 화면에서 선택한 모델과 실제 VLM 실행 모델이 다르면 혼란이 생긴다.
    // 따라서 VLM도 현재 선택된 모델 경로를 그대로 사용한다.
    _gemmaVlmService = OnDeviceGemmaExplanationService.visual(
      modelPath: _selectedModelPath,
      backendMode: _selectedBackendMode,
    );
  }

  _GemmaModelOption get _selectedModelOption => _gemmaModelOptions.firstWhere(
    (option) => option.path == _selectedModelPath,
    orElse: () => _gemmaModelOptions.first,
  );

  bool get _selectedModelKnownMissing =>
      _lastModelFileStatus?['file_exists'] == false;

  @override
  void initState() {
    super.initState();
    _visualPromptController = TextEditingController(
      text: _buildDefaultVisualPrompt(),
    );
    _updateGemmaServices();
    _prepareDebugVlmImagePath();
    _refreshGemmaStatus();
  }

  @override
  void dispose() {
    _visualImagePathController.dispose();
    _visualPromptController.dispose();
    super.dispose();
  }

  PhotoExplanationRequest get _request => PhotoExplanationRequest(
    imageBytes: widget.imageBytes,
    fileName: widget.result.fileName,
    technicalScore: widget.result.technicalScore,
    aestheticScore: widget.result.aestheticScore,
    finalAestheticScore: widget.result.finalAestheticScore,
    finalScore: widget.result.finalScore,
    verdict: widget.result.verdict,
    usesTechnicalScoreAsFinal: widget.result.usesTechnicalScoreAsFinal,
    primaryHint: widget.result.primaryHint,
    qualitySummary: widget.result.qualitySummary,
  );

  String _buildDefaultVisualPrompt() {
    final aestheticScore = widget.result.aestheticScore;
    final finalAestheticScore = widget.result.finalAestheticScore;
    final scoreLines = <String>[
      '- final_score: ${_scoreText(widget.result.finalScore * 100)}/100',
      '- technical_score: ${_scoreText(widget.result.technicalScore * 100)}/100',
      if (aestheticScore != null)
        '- aesthetic_score: ${_scoreText(aestheticScore * 100)}/100',
      if (finalAestheticScore != null)
        '- final_aesthetic_score: ${_scoreText(finalAestheticScore * 100)}/100',
      '- verdict: ${widget.result.verdict}',
      '- uses_technical_score_as_final: ${widget.result.usesTechnicalScoreAsFinal}',
      if (_nonEmpty(widget.result.primaryHint))
        '- primary_hint: ${widget.result.primaryHint}',
      if (_nonEmpty(widget.result.qualitySummary))
        '- quality_summary: ${widget.result.qualitySummary}',
    ];

    return '''

당신은 사진 A-cut 추천 앱의 설명 작성기입니다.

이미지와 아래 점수는 같은 사진에 대한 정보입니다.

점수는 앱이 이미 계산한 값이므로 수정하거나 다시 계산하지 마세요.

가장 중요한 규칙:

점수만 보고 일반적인 문장을 만들지 마세요.

반드시 사진에서 실제로 보이는 구체적인 시각 요소를 근거로 설명하세요.

예: 피사체 위치, 얼굴/주요 피사체 초점, 노출, 빛 방향, 색감, 배경 복잡도, 구도 안정성, 기울어짐, 상하/좌우 반전, 흐림, 방해 요소.

[입력 점수 - 수정 불가]

${scoreLines.join('\n')}

[판정 규칙]

- final_score >= 80 이면 comment_type은 "selected_explanation"

- 60 <= final_score < 80 이면 comment_type은 "near_miss_feedback"

- final_score < 60 이면 comment_type은 "rejection_reason"

[작성 규칙]

- 답변은 반드시 한국어 JSON 한 개만 출력하세요.

- 마크다운, 코드블록, JSON 밖 설명은 금지합니다.

- short_reason은 한 문장으로 작성하세요.

- short_reason에는 사진의 핵심 특징과 판정을 함께 담으세요.

- detailed_reason은 정확히 2문장으로 작성하세요.

- detailed_reason 첫 번째 문장은 사진에서 보이는 기술적 요소를 설명하세요.

  예: 초점, 선명도, 노출, 흔들림, 노이즈, 피사체 포착 상태.

- detailed_reason 두 번째 문장은 사진에서 보이는 미적 요소를 설명하세요.

  예: 구도, 색감, 배경 정리, 시선 집중도, 반전/기울어짐, 분위기.

- near_miss_feedback이면 두 번째 문장 끝에 보완 방향을 자연스럽게 포함하세요.

- rejection_reason이면 선택 후보로 약한 이유를 사진 내용과 점수에 맞게 설명하세요.

- selected_explanation이면 선택할 만한 이유를 사진 내용과 점수에 맞게 설명하세요.

- comparison_reason은 순위/비교 정보가 없으면 null로 출력하세요.

- 사진에 보이지 않는 내용은 단정하지 마세요.

- 점수와 모순되는 칭찬이나 비판은 금지합니다.

- 같은 표현을 반복하지 마세요.

[금지되는 일반 문장]

- "전반적인 기술 품질은 안정적입니다."

- "미적 요소에서 개선의 여지가 있습니다."

- "더 좋은 결과물을 만들 수 있습니다."

위와 같은 문장은 사진에서 보이는 구체적 근거 없이 단독으로 사용하지 마세요.

출력 JSON 스키마:

{

  "comment_type": "<selected_explanation|near_miss_feedback|rejection_reason>",

  "short_reason": "<사진의 핵심 특징과 판정 한 문장>",

  "detailed_reason": "<기술적 근거 1문장 + 미적 근거/보완 방향 1문장>",

  "comparison_reason": null

}

''';
  }

  String _scoreText(num value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.001) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }

  bool _nonEmpty(String? value) => value?.trim().isNotEmpty ?? false;

  Future<void> _refreshGemmaStatus() async {
    final status = await _gemmaService.isModelLoaded();
    if (!mounted) {
      return;
    }
    final loadedModelPath = _cleanString(status['model_path']);

    setState(() {
      _gemmaLoaded =
          status['model_loaded'] == true &&
          loadedModelPath == _selectedModelPath;
      _lastGemmaLoadMs = _toInt(status['model_load_time_ms']);
      _lastGemmaEngineConfigMode = _cleanString(status['engine_config_mode']);
      _lastGemmaDecodingConfig = _cleanString(status['decoding_config']);
      _statusMessage = _cleanString(status['error']);
    });
  }

  void _resetVisualPrompt() {
    setState(() {
      _visualPromptController.text = _buildDefaultVisualPrompt();
    });
  }

  void _selectModel(String? modelPath) {
    if (modelPath == null || modelPath == _selectedModelPath) {
      return;
    }
    setState(() {
      _selectedModelPath = modelPath;
      _gemmaLoaded = false;
      _lastModelFileStatus = null;
      _lastGemmaLoadMs = null;
      _lastGemmaPreloadElapsedMs = null;
      _lastGemmaEngineConfigMode = null;
      _lastGemmaDecodingConfig = null;
      _visualProbeResult = null;
      _statusMessage = '모델을 변경했어요. 다음 preload/generate에서 엔진을 새로 준비합니다.';
      _gemmaRuns.clear();
      _results.remove('on_device_gemma');
      _results.remove('on_device_gemma_vlm');
    });
    _updateGemmaServices();
    _refreshGemmaStatus();
  }

  void _selectBackendMode(String? backendMode) {
    if (backendMode == null || backendMode == _selectedBackendMode) {
      return;
    }
    setState(() {
      _selectedBackendMode = backendMode;
      _gemmaLoaded = false;
      _lastGemmaLoadMs = null;
      _lastGemmaPreloadElapsedMs = null;
      _lastGemmaEngineConfigMode = null;
      _lastGemmaDecodingConfig = null;
      _visualProbeResult = null;
      _statusMessage = '백엔드를 변경했어요. 다음 실행에서 해당 모드로 probe합니다.';
    });
    _updateGemmaServices();
    _refreshGemmaStatus();
  }

  Future<void> _checkModelFile() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    final status = await _gemmaService.checkModelFile();
    if (!mounted) {
      return;
    }

    final exists = status['file_exists'] == true;
    final sizeBytes = _toInt(status['file_size_bytes']);
    setState(() {
      _lastModelFileStatus = status;
      _statusMessage =
          'file_exists=$exists file_size_bytes=${sizeBytes ?? '-'}';
      _loading = false;
    });
  }

  Future<void> _preloadGemma() async {
    if (_selectedModelKnownMissing) {
      setState(() {
        _statusMessage =
            'model file missing: $_selectedModelPath\nsetup: ./scripts/push_gemma_model.sh <device_id> <local_model.litertlm>';
      });
      return;
    }
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    final status = await _gemmaService.preloadModel();
    if (!mounted) {
      return;
    }

    setState(() {
      _gemmaLoaded = status['model_loaded'] == true;
      _lastGemmaLoadMs = _toInt(status['model_load_time_ms']);
      _lastGemmaPreloadElapsedMs = _toInt(status['elapsed_ms']);
      _lastGemmaEngineConfigMode = _cleanString(status['engine_config_mode']);
      _lastGemmaDecodingConfig = _cleanString(status['decoding_config']);
      _statusMessage = _cleanString(status['error']) ?? 'Gemma preload 완료';
      _loading = false;
    });
  }

  Future<void> _generateGemmaOnce() async {
    if (_selectedModelKnownMissing) {
      setState(() {
        _statusMessage =
            'model file missing: $_selectedModelPath\nsetup: ./scripts/push_gemma_model.sh <device_id> <local_model.litertlm>';
      });
      return;
    }
    setState(() {
      _loading = true;
      _statusMessage = 'Gemma generate once 실행 중...';
      _gemmaRuns.clear();
    });

    final run = await _runGemmaBenchmarkIteration(1);
    if (!mounted) {
      return;
    }

    setState(() {
      _gemmaRuns.add(run);
      _statusMessage = 'Generate once 완료';
      _loading = false;
      _gemmaLoaded = run.error == null;
    });
  }

  Future<void> _generateGemmaWarmBenchmark() async {
    if (_selectedModelKnownMissing) {
      setState(() {
        _statusMessage =
            'model file missing: $_selectedModelPath\nsetup: ./scripts/push_gemma_model.sh <device_id> <local_model.litertlm>';
      });
      return;
    }
    setState(() {
      _loading = true;
      _statusMessage = 'Gemma 3x warm benchmark 실행 중...';
      _gemmaRuns.clear();
    });

    final runs = <_GemmaBenchmarkRun>[];
    for (var index = 1; index <= 3; index++) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Gemma warm benchmark $index/3';
      });
      runs.add(await _runGemmaBenchmarkIteration(index));
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _gemmaRuns.addAll(runs);
      _statusMessage = 'Generate 3x warm benchmark 완료';
      _loading = false;
      _gemmaLoaded = runs.any((run) => run.error == null);
    });
  }

  Future<_GemmaBenchmarkRun> _runGemmaBenchmarkIteration(int index) async {
    try {
      final preloadStatus = await _gemmaService.preloadModel();
      final generateStatus = await _gemmaService.generateRaw(_request);
      final error =
          _cleanString(preloadStatus['error']) ??
          _cleanString(generateStatus['error']);
      return _GemmaBenchmarkRun(
        index: index,
        modelLabel: _selectedModelOption.label,
        modelPath: _selectedModelPath,
        preloadMs: _toInt(preloadStatus['model_load_time_ms']),
        nativeGenerationMs: _toInt(generateStatus['native_generation_time_ms']),
        totalMs:
            _toInt(generateStatus['total_generation_time_ms']) ??
            _toInt(generateStatus['elapsed_ms']),
        promptChars: _toInt(generateStatus['prompt_chars']),
        outputLength: _toInt(generateStatus['output_length']),
        backendInfo: _cleanString(generateStatus['backend_info']) ?? '-',
        gpuFallbackUsed:
            preloadStatus['gpu_fallback_used'] == true ||
            generateStatus['gpu_fallback_used'] == true,
        jsonParse: generateStatus['json_parse_success'] == true,
        error: error,
      );
    } catch (error) {
      return _GemmaBenchmarkRun(
        index: index,
        modelLabel: _selectedModelOption.label,
        modelPath: _selectedModelPath,
        preloadMs: null,
        nativeGenerationMs: null,
        totalMs: null,
        promptChars: null,
        outputLength: null,
        backendInfo: '-',
        gpuFallbackUsed: false,
        jsonParse: false,
        error: error.toString(),
      );
    }
  }

  Future<void> _disposeGemma() async {
    setState(() {
      _loading = true;
    });
    await _gemmaService.disposeModel();
    if (!mounted) {
      return;
    }
    setState(() {
      _gemmaLoaded = false;
      _lastGemmaLoadMs = null;
      _lastGemmaPreloadElapsedMs = null;
      _lastGemmaEngineConfigMode = null;
      _lastGemmaDecodingConfig = null;
      _statusMessage = 'Gemma 모델을 해제했어요.';
      _loading = false;
    });
  }

  Future<void> _runVisualProbe() async {
    if (_selectedModelKnownMissing) {
      setState(() {
        _statusMessage =
            'model file missing: $_selectedModelPath\nsetup: ./scripts/push_gemma_model.sh <device_id> <local_model.litertlm>';
      });
      return;
    }
    setState(() {
      _loading = true;
      _statusMessage = 'Gemma Vision Probe 실행 중...';
      _visualProbeResult = null;
    });

    final prompt = _visualPromptController.text;
    final imagePath = _visualImagePathController.text;

    debugPrint(
      '[ExplanationBackendDebugScreen] GEMMA_VLM_PROMPT_MODE '
      'mode=visual_image_context prompt_chars=${prompt.length}',
    );
    debugPrint(
      '[ExplanationBackendDebugScreen] GEMMA_VLM_IMAGE_PATH path=$imagePath',
    );
    debugPrint('[ExplanationBackendDebugScreen] GEMMA_VLM_PROMPT_BEGIN');
    debugPrint(prompt);
    debugPrint('[ExplanationBackendDebugScreen] GEMMA_VLM_PROMPT_END');

    final result = await _gemmaVlmService.generateAcutVisualComment(
      prompt: prompt,
      imagePath: imagePath,
    );

    if (!mounted) {
      return;
    }
    final supported = result['image_input_supported'] == true;
    final used = result['image_input_used'] == true;
    final ok = result['ok'] == true;
    setState(() {
      _visualProbeResult = result;
      _loading = false;
      _statusMessage = ok && supported && used
          ? 'Gemma Vision Probe 성공: 이미지 입력이 실제로 사용된 응답을 받았어요.'
          : 'Gemma Vision Probe 완료: ${_cleanString(result['reason']) ?? _cleanString(result['error']) ?? 'unsupported_or_failed'}';
    });
  }

  Future<String?> _prepareDebugVlmImagePath() async {
    final cached = _selectedDebugVlmImagePath;
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }
    try {
      final decoded = img.decodeImage(widget.imageBytes);
      if (decoded == null) {
        return null;
      }
      final oriented = img.bakeOrientation(decoded);
      final longSide = oriented.width > oriented.height
          ? oriented.width
          : oriented.height;
      final resized = longSide > ExperimentalFeatures.gemmaVlmMaxLongSide
          ? img.copyResize(
              oriented,
              width: oriented.width >= oriented.height
                  ? ExperimentalFeatures.gemmaVlmMaxLongSide
                  : null,
              height: oriented.height > oriented.width
                  ? ExperimentalFeatures.gemmaVlmMaxLongSide
                  : null,
              interpolation: img.Interpolation.average,
            )
          : oriented;
      final dir = Directory('${Directory.systemTemp.path}/acut_vlm_inputs');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeName = (widget.result.fileName ?? 'selected_image').replaceAll(
        RegExp(r'[^a-zA-Z0-9_.-]'),
        '_',
      );
      final file = File('${dir.path}/${safeName}_debug_vlm.jpg');
      await file.writeAsBytes(
        img.encodeJpg(
          resized,
          quality: ExperimentalFeatures.gemmaVlmJpegQuality,
        ),
        flush: true,
      );
      if (!mounted) {
        return file.path;
      }
      setState(() {
        _selectedDebugVlmImagePath = file.path;
        if (_visualImagePathController.text.isEmpty) {
          _visualImagePathController.text = file.path;
        }
      });
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runComparison() async {
    if (_selectedModelKnownMissing) {
      setState(() {
        _statusMessage =
            'model file missing: $_selectedModelPath\nsetup: ./scripts/push_gemma_model.sh <device_id> <local_model.litertlm>';
      });
      return;
    }
    setState(() {
      _loading = true;
      _statusMessage = null;
      _results.clear();
    });

    final visualPath = await _prepareDebugVlmImagePath();
    final request = visualPath == null
        ? _request
        : PhotoExplanationRequest(
            imageBytes: widget.imageBytes,
            fileName: widget.result.fileName,
            localImagePath: visualPath,
            technicalScore: widget.result.technicalScore,
            aestheticScore: widget.result.aestheticScore,
            finalAestheticScore: widget.result.finalAestheticScore,
            finalScore: widget.result.finalScore,
            verdict: widget.result.verdict,
            usesTechnicalScoreAsFinal: widget.result.usesTechnicalScoreAsFinal,
            primaryHint: widget.result.primaryHint,
            qualitySummary: widget.result.qualitySummary,
          );
    final orderedServices = <PhotoExplanationService>[
      _geminiTextOnlyService,
      _geminiImageScoresService,
      _gemmaService,
      if (visualPath != null) _gemmaVlmService,
    ];

    if (_runSequentialComparison) {
      for (var index = 0; index < orderedServices.length; index++) {
        final service = orderedServices[index];
        if (!mounted) {
          return;
        }
        setState(() {
          _statusMessage =
              '비교 실행 ${index + 1}/${orderedServices.length}: ${service.backendLabel}';
        });
        final result = await service.explain(request);
        if (!mounted) {
          return;
        }
        setState(() {
          _results[result.backendId] = result;
          if (result.backendId == _gemmaService.backendId &&
              result.modelLoadTimeMs != null) {
            _gemmaLoaded = result.error == null;
            _lastGemmaLoadMs = result.modelLoadTimeMs;
            _lastGemmaEngineConfigMode = result.engineConfigMode;
            _lastGemmaDecodingConfig = result.decodingConfig;
          }
        });
      }
    } else {
      final futures = await Future.wait<PhotoExplanationResult>(
        orderedServices.map((service) => service.explain(request)),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results
          ..clear()
          ..addEntries(
            futures.map((result) => MapEntry(result.backendId, result)),
          );
        final gemma = _results[_gemmaService.backendId];
        if (gemma != null && gemma.modelLoadTimeMs != null) {
          _gemmaLoaded = gemma.error == null;
          _lastGemmaLoadMs = gemma.modelLoadTimeMs;
          _lastGemmaEngineConfigMode = gemma.engineConfigMode;
          _lastGemmaDecodingConfig = gemma.decodingConfig;
        }
      });
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _statusMessage = _runSequentialComparison
          ? '세 백엔드를 순차적으로 비교했어요.'
          : '세 백엔드를 병렬로 비교했어요.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: AppTopBar(
                title: '설명 백엔드 비교',
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusCard(
                      fileName: widget.result.fileName,
                      gemmaLoaded: _gemmaLoaded,
                      modelOptions: _gemmaModelOptions,
                      selectedModelPath: _selectedModelPath,
                      onModelChanged: _loading ? null : _selectModel,
                      backendModes: _backendModes,
                      selectedBackendMode: _selectedBackendMode,
                      onBackendModeChanged: _loading
                          ? null
                          : _selectBackendMode,
                      modelFileStatus: _lastModelFileStatus,
                      selectedModelKnownMissing: _selectedModelKnownMissing,
                      lastGemmaLoadMs: _lastGemmaLoadMs,
                      lastGemmaPreloadElapsedMs: _lastGemmaPreloadElapsedMs,
                      lastGemmaEngineConfigMode: _lastGemmaEngineConfigMode,
                      lastGemmaDecodingConfig: _lastGemmaDecodingConfig,
                      statusMessage: _statusMessage,
                      modelPath: _gemmaService.modelPath,
                      preloadTimeoutSeconds:
                          _gemmaService.preloadTimeout.inSeconds,
                      generationTimeoutSeconds:
                          _gemmaService.generationTimeout.inSeconds,
                      comparisonMode: _runSequentialComparison
                          ? 'sequential'
                          : 'parallel',
                    ),
                    const SizedBox(height: 14),
                    _ActionRow(
                      loading: _loading,
                      modelKnownMissing: _selectedModelKnownMissing,
                      onCheckModelFile: _checkModelFile,
                      onPreload: _preloadGemma,
                      onGenerateOnce: _generateGemmaOnce,
                      onGenerateWarmBenchmark: _generateGemmaWarmBenchmark,
                      onRunComparison: _runComparison,
                      onDispose: _disposeGemma,
                    ),
                    const SizedBox(height: 18),
                    _VisionProbeCard(
                      loading: _loading,
                      modelKnownMissing: _selectedModelKnownMissing,
                      modelLabel: _selectedModelOption.label,
                      modelPath: _selectedModelPath,
                      backendMode: _selectedBackendMode,
                      imagePathController: _visualImagePathController,
                      promptController: _visualPromptController,
                      result: _visualProbeResult,
                      onRun: _runVisualProbe,
                      onResetPrompt: _resetVisualPrompt,
                    ),
                    const SizedBox(height: 18),
                    ..._gemmaRuns.map(
                      (run) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _GemmaRunCard(run: run),
                      ),
                    ),
                    ...[
                      _results[_geminiTextOnlyService.backendId],
                      _results[_geminiImageScoresService.backendId],
                      _results[_gemmaService.backendId],
                      _results[_gemmaVlmService.backendId],
                    ].whereType<PhotoExplanationResult>().map(
                      (result) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _BackendResultCard(result: result),
                      ),
                    ),
                    if (_results.isEmpty)
                      const _HintCard(
                        text:
                            'Gemini 텍스트 전용, Gemini 이미지+점수, 온디바이스 Gemma를 여기서 한 번에 비교할 수 있어요.',
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _cleanString(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.fileName,
    required this.gemmaLoaded,
    required this.modelOptions,
    required this.selectedModelPath,
    required this.onModelChanged,
    required this.backendModes,
    required this.selectedBackendMode,
    required this.onBackendModeChanged,
    required this.modelFileStatus,
    required this.selectedModelKnownMissing,
    required this.lastGemmaLoadMs,
    required this.lastGemmaPreloadElapsedMs,
    required this.lastGemmaEngineConfigMode,
    required this.lastGemmaDecodingConfig,
    required this.statusMessage,
    required this.modelPath,
    required this.preloadTimeoutSeconds,
    required this.generationTimeoutSeconds,
    required this.comparisonMode,
  });

  final String? fileName;
  final bool gemmaLoaded;
  final List<_GemmaModelOption> modelOptions;
  final String selectedModelPath;
  final ValueChanged<String?>? onModelChanged;
  final List<String> backendModes;
  final String selectedBackendMode;
  final ValueChanged<String?>? onBackendModeChanged;
  final Map<String, dynamic>? modelFileStatus;
  final bool selectedModelKnownMissing;
  final int? lastGemmaLoadMs;
  final int? lastGemmaPreloadElapsedMs;
  final String? lastGemmaEngineConfigMode;
  final String? lastGemmaDecodingConfig;
  final String? statusMessage;
  final String modelPath;
  final int preloadTimeoutSeconds;
  final int generationTimeoutSeconds;
  final String comparisonMode;

  @override
  Widget build(BuildContext context) {
    final dropdownValue =
        modelOptions.any((option) => option.path == selectedModelPath)
        ? selectedModelPath
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gemma LiteRT-LM 디버그',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 8),
          _MetaRow(label: '파일', value: fileName ?? 'selected_image'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: dropdownValue,
            items: modelOptions
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.path,
                    child: Text(option.label),
                  ),
                )
                .toList(),
            onChanged: onModelChanged,
            decoration: const InputDecoration(
              labelText: '모델',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: backendModes.contains(selectedBackendMode)
                ? selectedBackendMode
                : backendModes.first,
            items: backendModes
                .map(
                  (mode) =>
                      DropdownMenuItem<String>(value: mode, child: Text(mode)),
                )
                .toList(),
            onChanged: onBackendModeChanged,
            decoration: const InputDecoration(
              labelText: '백엔드',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          _MetaRow(label: 'model_path', value: modelPath),
          if (modelFileStatus != null) ...[
            const SizedBox(height: 6),
            _MetaRow(
              label: 'file_exists',
              value: (modelFileStatus!['file_exists'] == true).toString(),
            ),
            const SizedBox(height: 6),
            _MetaRow(
              label: 'file_size',
              value: '${modelFileStatus!['file_size_bytes'] ?? '-'}',
            ),
          ],
          if (selectedModelKnownMissing) ...[
            const SizedBox(height: 8),
            const Text(
              'model file missing',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w800,
                color: Color(0xFFB91C1C),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'setup: ./scripts/push_gemma_model.sh <device_id> <local_model.litertlm>',
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
          ],
          const SizedBox(height: 6),
          _MetaRow(label: '비교 모드', value: comparisonMode),
          const SizedBox(height: 6),
          _MetaRow(label: 'preload timeout', value: '$preloadTimeoutSeconds s'),
          const SizedBox(height: 6),
          _MetaRow(label: 'backend mode', value: selectedBackendMode),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'generation timeout',
            value: '$generationTimeoutSeconds s',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: '상태',
            value: gemmaLoaded
                ? 'loaded${lastGemmaLoadMs == null ? '' : ' ($lastGemmaLoadMs ms)'}'
                : 'not loaded',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'preload elapsed',
            value: lastGemmaPreloadElapsedMs == null
                ? '-'
                : '$lastGemmaPreloadElapsedMs ms',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'engine_config',
            value: lastGemmaEngineConfigMode ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'decoding_config',
            value: lastGemmaDecodingConfig ?? '-',
          ),
          if (statusMessage?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              statusMessage!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.loading,
    required this.modelKnownMissing,
    required this.onCheckModelFile,
    required this.onPreload,
    required this.onGenerateOnce,
    required this.onGenerateWarmBenchmark,
    required this.onRunComparison,
    required this.onDispose,
  });

  final bool loading;
  final bool modelKnownMissing;
  final VoidCallback onCheckModelFile;
  final VoidCallback onPreload;
  final VoidCallback onGenerateOnce;
  final VoidCallback onGenerateWarmBenchmark;
  final VoidCallback onRunComparison;
  final VoidCallback onDispose;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = (constraints.maxWidth - 10) / 2;
        final gemmaActionDisabled = loading || modelKnownMissing;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: buttonWidth,
              child: _ActionButton(
                label: 'Check model file',
                onTap: loading ? null : onCheckModelFile,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _ActionButton(
                label: 'Gemma preload',
                onTap: gemmaActionDisabled ? null : onPreload,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _ActionButton(
                label: 'Generate once',
                onTap: gemmaActionDisabled ? null : onGenerateOnce,
                primary: true,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _ActionButton(
                label: 'Generate 3x warm',
                onTap: gemmaActionDisabled ? null : onGenerateWarmBenchmark,
                primary: true,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _ActionButton(
                label: loading ? '실행 중...' : '세 백엔드 비교',
                onTap: gemmaActionDisabled ? null : onRunComparison,
              ),
            ),
            SizedBox(
              width: buttonWidth,
              child: _ActionButton(
                label: 'Gemma dispose',
                onTap: loading ? null : onDispose,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GemmaRunCard extends StatelessWidget {
  const _GemmaRunCard({required this.run});

  final _GemmaBenchmarkRun run;

  @override
  Widget build(BuildContext context) {
    final ok = run.error == null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gemma run ${run.index} · ${run.modelLabel}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              Text(
                ok ? 'success' : 'failed',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ok ? const Color(0xFF166534) : const Color(0xFF991B1B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MetaRow(label: 'model_path', value: run.modelPath),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'preload_ms',
            value: run.preloadMs?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'native_ms',
            value: run.nativeGenerationMs?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(label: 'total_ms', value: run.totalMs?.toString() ?? '-'),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'prompt_chars',
            value: run.promptChars?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'output_length',
            value: run.outputLength?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(label: 'backend_info', value: run.backendInfo),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'gpu_fallback',
            value: run.gpuFallbackUsed.toString(),
          ),
          const SizedBox(height: 6),
          _MetaRow(label: 'json_parse', value: run.jsonParse.toString()),
          if (run.error?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              run.error!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB91C1C),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VisionProbeCard extends StatelessWidget {
  const _VisionProbeCard({
    required this.loading,
    required this.modelKnownMissing,
    required this.modelLabel,
    required this.modelPath,
    required this.backendMode,
    required this.imagePathController,
    required this.promptController,
    required this.result,
    required this.onRun,
    required this.onResetPrompt,
  });

  final bool loading;
  final bool modelKnownMissing;
  final String modelLabel;
  final String modelPath;
  final String backendMode;
  final TextEditingController imagePathController;
  final TextEditingController promptController;
  final Map<String, dynamic>? result;
  final VoidCallback onRun;
  final VoidCallback onResetPrompt;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final supported = result?['image_input_supported'] == true;
    final used = result?['image_input_used'] == true;
    final ok = result?['ok'] == true;
    final statusLabel = result == null
        ? 'not run'
        : ok && supported && used
        ? 'vision probe success'
        : supported
        ? 'probe failed'
        : 'unsupported';
    final statusColor = result == null
        ? AppColors.secondaryText
        : ok && supported && used
        ? const Color(0xFF166534)
        : const Color(0xFF991B1B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Gemma Vision Probe',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MetaRow(label: 'model', value: modelLabel),
          const SizedBox(height: 6),
          _MetaRow(label: 'model_path', value: modelPath),
          const SizedBox(height: 6),
          _MetaRow(label: 'backend', value: backendMode),
          const SizedBox(height: 12),
          TextField(
            controller: imagePathController,
            enabled: !loading,
            decoration: const InputDecoration(
              labelText: 'device imagePath',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: promptController,
            enabled: !loading,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'visual prompt',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          _ActionButton(
            label: modelKnownMissing
                ? 'Model file missing'
                : loading
                ? 'Probe 실행 중...'
                : 'Run visual probe',
            onTap: loading || modelKnownMissing ? null : onRun,
            primary: true,
          ),
          const SizedBox(height: 10),
          _ActionButton(
            label: 'Reset prompt from current scores',
            onTap: loading ? null : onResetPrompt,
          ),
          if (result != null) ...[
            const SizedBox(height: 14),
            _MetaRow(
              label: 'supported',
              value: _value(result['image_input_supported']),
            ),
            const SizedBox(height: 6),
            _MetaRow(label: 'used', value: _value(result['image_input_used'])),
            const SizedBox(height: 6),
            _MetaRow(
              label: 'file_exists',
              value: _value(result['image_file_exists']),
            ),
            const SizedBox(height: 6),
            _MetaRow(
              label: 'file_size',
              value: _value(result['image_file_size_bytes']),
            ),
            const SizedBox(height: 6),
            _MetaRow(
              label: 'backend_info',
              value: _value(result['backend_info']),
            ),
            const SizedBox(height: 6),
            _MetaRow(
              label: 'vision_ms',
              value: _value(result['vision_or_prefill_ms']),
            ),
            const SizedBox(height: 6),
            _MetaRow(
              label: 'native_ms',
              value: _value(result['native_generation_ms']),
            ),
            const SizedBox(height: 6),
            _MetaRow(
              label: 'total_ms',
              value: _value(result['total_ms'] ?? result['elapsed_ms']),
            ),
            const SizedBox(height: 6),
            _MetaRow(label: 'reason', value: _value(result['reason'])),
            if (_value(result['error']) != '-') ...[
              const SizedBox(height: 8),
              Text(
                _value(result['error']),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB91C1C),
                ),
              ),
            ],
            if (_value(result['output']) != '-') ...[
              const SizedBox(height: 12),
              const Text(
                'output',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _value(result['output']),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ],
            if (_value(result['raw_preview']) != '-' &&
                _value(result['output']) == '-') ...[
              const SizedBox(height: 12),
              _MetaRow(
                label: 'raw_preview',
                value: _value(result['raw_preview']),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _value(Object? value) {
    if (value == null) {
      return '-';
    }
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: primary ? AppColors.primaryText : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: primary ? Colors.white : AppColors.primaryText,
          ),
        ),
      ),
    );
  }
}

class _BackendResultCard extends StatelessWidget {
  const _BackendResultCard({required this.result});

  final PhotoExplanationResult result;

  @override
  Widget build(BuildContext context) {
    final success = result.isSuccessful;
    final statusLabel = result.usedFallback
        ? 'fallback'
        : success
        ? 'success'
        : 'failed';
    final statusColor = result.usedFallback
        ? const Color(0xFF854D0E)
        : success
        ? const Color(0xFF166534)
        : const Color(0xFF991B1B);
    final statusBackground = result.usedFallback
        ? const Color(0xFFFEF3C7)
        : success
        ? const Color(0xFFDCFCE7)
        : const Color(0xFFFEE2E2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.backendLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MetaRow(label: 'comment_type', value: result.commentType),
          const SizedBox(height: 6),
          _MetaRow(label: 'backend', value: result.backendLabel),
          const SizedBox(height: 6),
          _MetaRow(label: 'mode', value: result.promptMode ?? '-'),
          const SizedBox(height: 6),
          _MetaRow(label: 'backend_info', value: result.backendInfo ?? '-'),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'gpu_fallback',
            value: result.gpuFallbackUsed.toString(),
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'image_used',
            value: result.imageInputUsed.toString(),
          ),
          const SizedBox(height: 6),
          _MetaRow(label: 'image_path', value: result.imagePath ?? '-'),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'image_size',
            value: result.imageFileSizeBytes?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'timeout_seconds',
            value: result.timeoutSeconds?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'elapsed_ms',
            value: result.totalGenerationTimeMs?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'json_parse',
            value: result.jsonParseSuccess ? 'success' : 'failed',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'parse_failed',
            value: result.parseFailed ? 'true' : 'false',
          ),
          const SizedBox(height: 6),
          _MetaRow(label: 'repaired', value: result.repaired.toString()),
          const SizedBox(height: 6),
          _MetaRow(label: 'repair', value: result.repairReason ?? '-'),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'fallback_used',
            value: result.usedFallback ? 'true' : 'false',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'load_ms',
            value: result.modelLoadTimeMs?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'native_generation_ms',
            value: result.nativeGenerationTimeMs?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'output_length',
            value: result.outputLength?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'engine_config',
            value: result.engineConfigMode ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'decoding_config',
            value: result.decodingConfig ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(label: 'prompt_mode', value: result.promptMode ?? '-'),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'prompt_chars',
            value: result.promptChars?.toString() ?? '-',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'total_ms',
            value: result.totalGenerationTimeMs?.toString() ?? '-',
          ),
          if (result.shortReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'short_reason',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.shortReason,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
          ],
          if (result.detailedReason.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'detailed_reason',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.detailedReason,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ],
          if (result.comparisonReason?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            const Text(
              'comparison_reason',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.comparisonReason!,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ],
          if (result.error?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            const Text(
              'error',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFFB91C1C),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.error!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB91C1C),
              ),
            ),
          ],
          if (result.fallbackReason?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            const Text(
              'fallback_reason',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.fallbackReason!,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.card,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1.55,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryText,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}
