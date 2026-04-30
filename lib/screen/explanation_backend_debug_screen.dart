import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../feature/a_cut/model/photo_evaluation_result.dart';
import '../services/gemini_photo_explanation_services.dart';
import '../services/on_device_gemma_explanation_service.dart';
import '../services/photo_explanation_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../widget/app_top_bar.dart';

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
  final GeminiTextOnlyPhotoExplanationService _geminiTextOnlyService =
      GeminiTextOnlyPhotoExplanationService();
  final GeminiImageScoresPhotoExplanationService _geminiImageScoresService =
      GeminiImageScoresPhotoExplanationService();
  final OnDeviceGemmaExplanationService _gemmaService =
      OnDeviceGemmaExplanationService();

  bool _loading = false;
  bool _gemmaLoaded = false;
  int? _lastGemmaLoadMs;
  String? _statusMessage;
  final Map<String, PhotoExplanationResult> _results = {};

  @override
  void initState() {
    super.initState();
    _refreshGemmaStatus();
  }

  PhotoExplanationRequest get _request => PhotoExplanationRequest(
    imageBytes: widget.imageBytes,
    fileName: widget.result.fileName,
    technicalScore: widget.result.technicalScore,
    aestheticScore: widget.result.aestheticScore,
    finalScore: widget.result.finalScore,
  );

  Future<void> _refreshGemmaStatus() async {
    final status = await _gemmaService.isModelLoaded();
    if (!mounted) {
      return;
    }

    setState(() {
      _gemmaLoaded = status['model_loaded'] == true;
      _lastGemmaLoadMs = _toInt(status['model_load_time_ms']);
      _statusMessage = _cleanString(status['error']);
    });
  }

  Future<void> _preloadGemma() async {
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
      _statusMessage = _cleanString(status['error']) ?? 'Gemma preload 완료';
      _loading = false;
    });
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
      _statusMessage = 'Gemma 모델을 해제했어요.';
      _loading = false;
    });
  }

  Future<void> _runComparison() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    final request = _request;
    final futures = await Future.wait<PhotoExplanationResult>([
      _geminiTextOnlyService.explain(request),
      _geminiImageScoresService.explain(request),
      _gemmaService.explain(request),
    ]);

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _results
        ..clear()
        ..addEntries(
          futures.map((result) => MapEntry(result.backendId, result)),
        );
      final gemma = _results[_gemmaService.backendId];
      if (gemma != null && gemma.modelLoadTimeMs != null) {
        _gemmaLoaded = gemma.error == null;
        _lastGemmaLoadMs = gemma.modelLoadTimeMs;
      }
      _statusMessage = '세 백엔드 비교를 완료했어요.';
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
                      lastGemmaLoadMs: _lastGemmaLoadMs,
                      statusMessage: _statusMessage,
                      modelPath: _gemmaService.modelPath,
                    ),
                    const SizedBox(height: 14),
                    _ActionRow(
                      loading: _loading,
                      onPreload: _preloadGemma,
                      onRunComparison: _runComparison,
                      onDispose: _disposeGemma,
                    ),
                    const SizedBox(height: 18),
                    ...[
                      _results[_geminiTextOnlyService.backendId],
                      _results[_geminiImageScoresService.backendId],
                      _results[_gemmaService.backendId],
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
    required this.lastGemmaLoadMs,
    required this.statusMessage,
    required this.modelPath,
  });

  final String? fileName;
  final bool gemmaLoaded;
  final int? lastGemmaLoadMs;
  final String? statusMessage;
  final String modelPath;

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
          _MetaRow(label: '모델', value: modelPath),
          const SizedBox(height: 6),
          _MetaRow(
            label: '상태',
            value: gemmaLoaded
                ? 'loaded${lastGemmaLoadMs == null ? '' : ' ($lastGemmaLoadMs ms)'}'
                : 'not loaded',
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
    required this.onPreload,
    required this.onRunComparison,
    required this.onDispose,
  });

  final bool loading;
  final VoidCallback onPreload;
  final VoidCallback onRunComparison;
  final VoidCallback onDispose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Gemma preload',
            onTap: loading ? null : onPreload,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: loading ? '실행 중...' : '세 백엔드 비교',
            onTap: loading ? null : onRunComparison,
            primary: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: 'Gemma dispose',
            onTap: loading ? null : onDispose,
          ),
        ),
      ],
    );
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
                  color: success
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  success ? 'success' : 'failed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: success
                        ? const Color(0xFF166534)
                        : const Color(0xFF991B1B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MetaRow(label: 'comment_type', value: result.commentType),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'json_parse',
            value: result.jsonParseSuccess ? 'success' : 'failed',
          ),
          const SizedBox(height: 6),
          _MetaRow(
            label: 'load_ms',
            value: result.modelLoadTimeMs?.toString() ?? '-',
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
          if (result.rawResponse?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            const Text(
              'raw_response',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.rawResponse!,
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
