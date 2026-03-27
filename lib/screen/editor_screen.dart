import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../service/gemini_service.dart';
import 'crop_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

const int _editorExportMaxDimension = 3072;
const int _editorPreviewMaxDimension = 1600;

enum _EditorAdjustment { brightness, contrast, saturation, warmth, fade, sharpness }

extension on _EditorAdjustment {
  String get label {
    switch (this) {
      case _EditorAdjustment.brightness:
        return '밝기';
      case _EditorAdjustment.contrast:
        return '대비';
      case _EditorAdjustment.saturation:
        return '채도';
      case _EditorAdjustment.warmth:
        return '색온도';
      case _EditorAdjustment.fade:
        return '페이드';
      case _EditorAdjustment.sharpness:
        return '선명도';
    }
  }

  String get shortLabel {
    switch (this) {
      case _EditorAdjustment.brightness:
        return '밝기';
      case _EditorAdjustment.contrast:
        return '대비';
      case _EditorAdjustment.saturation:
        return '채도';
      case _EditorAdjustment.warmth:
        return '온도';
      case _EditorAdjustment.fade:
        return '페이드';
      case _EditorAdjustment.sharpness:
        return '선명도';
    }
  }

  String get description {
    switch (this) {
      case _EditorAdjustment.brightness:
        return '사진 전체의 밝기를 조절합니다';
      case _EditorAdjustment.contrast:
        return '밝고 어두운 영역의 차이를 키웁니다';
      case _EditorAdjustment.saturation:
        return '색상의 선명함과 진하기를 조절합니다';
      case _EditorAdjustment.warmth:
        return '차갑거나 따뜻한 색감으로 바꿉니다';
      case _EditorAdjustment.fade:
        return '대비를 누그러뜨려 부드러운 분위기를 만듭니다';
      case _EditorAdjustment.sharpness:
        return '이미지의 디테일과 경계를 강조합니다';
    }
  }

  IconData get icon {
    switch (this) {
      case _EditorAdjustment.brightness:
        return Icons.wb_sunny_outlined;
      case _EditorAdjustment.contrast:
        return Icons.contrast;
      case _EditorAdjustment.saturation:
        return Icons.palette_outlined;
      case _EditorAdjustment.warmth:
        return Icons.thermostat_auto_outlined;
      case _EditorAdjustment.fade:
        return Icons.blur_on_outlined;
      case _EditorAdjustment.sharpness:
        return Icons.deblur;
    }
  }
}

class EditorScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback? onBack;

  const EditorScreen({super.key, required this.onMoveTab, this.onBack});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _sourceBytes;
  Uint8List? _previewSourceBytes;
  Uint8List? _previewBytes;
  String? _selectedImagePath;
  double? _imageAspectRatio;

  Uint8List? _originalSourceBytes;
  Uint8List? _originalPreviewSourceBytes;
  double? _originalAspectRatio;
  bool _imageModified = false;

  bool _isPreparingImage = false;
  bool _isRenderingPreview = false;
  bool _isSaving = false;
  bool _showOriginalPreview = false;

  Timer? _previewDebounce;
  int _previewJobId = 0;

  _EditorAdjustment _activeAdjustment = _EditorAdjustment.brightness;
  final Map<_EditorAdjustment, double> _adjustments = {
    for (final adjustment in _EditorAdjustment.values) adjustment: 0,
  };

  final GeminiService _geminiService = GeminiService();

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  double _valueOf(_EditorAdjustment adjustment) =>
      _adjustments[adjustment] ?? 0;

  bool get _hasImage =>
      _sourceBytes != null &&
      _previewSourceBytes != null &&
      _previewBytes != null;

  bool get _hasNonZeroAdjustment =>
      _adjustments.values.any((v) => v != 0);

  bool get _hasAnyEdit => _imageModified || _hasNonZeroAdjustment;

  void _resetEverything() {
    if (_originalSourceBytes == null) return;
    setState(() {
      _sourceBytes = _originalSourceBytes;
      _previewSourceBytes = _originalPreviewSourceBytes;
      _previewBytes = _originalPreviewSourceBytes;
      _imageAspectRatio = _originalAspectRatio;
      _imageModified = false;
      _resetAdjustmentsLocally();
    });
  }

  void _resetAllAdjustments() {
    setState(() {
      _resetAdjustmentsLocally();
    });
    _schedulePreviewRender();
  }

  Future<void> _pickImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final rawBytes = await File(file.path).readAsBytes();

    setState(() {
      _selectedImagePath = file.path;
      _isPreparingImage = true;
      _isRenderingPreview = false;
      _sourceBytes = null;
      _previewSourceBytes = null;
      _previewBytes = null;
      _imageAspectRatio = null;
      _showOriginalPreview = false;
      _resetAdjustmentsLocally();
    });

    try {
      final prepared = await compute(_prepareEditorBuffers, rawBytes);
      if (!mounted) return;

      setState(() {
        _sourceBytes = prepared['source'];
        _previewSourceBytes = prepared['preview'];
        _previewBytes = prepared['preview'];
        _imageAspectRatio = prepared['aspectRatio'] as double;
        _originalSourceBytes = prepared['source'];
        _originalPreviewSourceBytes = prepared['preview'];
        _originalAspectRatio = prepared['aspectRatio'] as double;
        _imageModified = false;
        _isPreparingImage = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPreparingImage = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('사진을 불러오지 못했습니다: $error')));
    }
  }

  void _resetAdjustmentsLocally() {
    for (final adjustment in _EditorAdjustment.values) {
      _adjustments[adjustment] = 0;
    }
    _activeAdjustment = _EditorAdjustment.brightness;
  }

  void _updateAdjustment(double value) {
    setState(() {
      _adjustments[_activeAdjustment] = value;
    });
    _schedulePreviewRender();
  }

  void _schedulePreviewRender() {
    if (_previewSourceBytes == null) return;

    _previewDebounce?.cancel();
    final int jobId = ++_previewJobId;

    _previewDebounce = Timer(const Duration(milliseconds: 50), () async {
      final previewSourceBytes = _previewSourceBytes;
      if (previewSourceBytes == null) return;

      final request = _buildRenderRequest(previewSourceBytes);

      if (mounted) {
        setState(() {
          _isRenderingPreview = true;
        });
      }

      try {
        final rendered = await compute(_renderAdjustedJpg, request);
        if (!mounted || jobId != _previewJobId) return;

        setState(() {
          _previewBytes = rendered;
          _isRenderingPreview = false;
        });
      } catch (_) {
        if (!mounted || jobId != _previewJobId) return;
        setState(() {
          _isRenderingPreview = false;
        });
      }
    });
  }

  Map<String, dynamic> _buildRenderRequest(Uint8List bytes) {
    return {
      'bytes': bytes,
      'brightness': _valueOf(_EditorAdjustment.brightness),
      'contrast': _valueOf(_EditorAdjustment.contrast),
      'saturation': _valueOf(_EditorAdjustment.saturation),
      'warmth': _valueOf(_EditorAdjustment.warmth),
      'fade': _valueOf(_EditorAdjustment.fade),
      'sharpness': _valueOf(_EditorAdjustment.sharpness),
    };
  }

  Future<void> _runAiEdit(String prompt) async {
    debugPrint('[EditorScreen] _runAiEdit 호출됨, 프롬프트: $prompt');

    if (_previewSourceBytes == null) {
      debugPrint('[EditorScreen] _previewSourceBytes가 null → 조기 반환');
      return;
    }

    debugPrint('[EditorScreen] _previewSourceBytes 크기: ${_previewSourceBytes!.lengthInBytes} bytes');

    try {
      final result = await _geminiService.editImage(
        imageBytes: _previewSourceBytes!,
        prompt: prompt,
      );

      debugPrint('[EditorScreen] editImage 결과: ${result == null ? "null" : "${result.lengthInBytes} bytes"}');

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _previewBytes = result;
          _sourceBytes = result;
          _previewSourceBytes = result;
          _imageModified = true;
          _resetAdjustmentsLocally();
        });
        debugPrint('[EditorScreen] 이미지 업데이트 완료');
      } else {
        debugPrint('[EditorScreen] result null → 예외 throw');
        throw Exception('이미지 생성에 실패했어요.');
      }
    } catch (e, stackTrace) {
      debugPrint('[EditorScreen] _runAiEdit 오류: $e');
      debugPrint('[EditorScreen] 스택트레이스: $stackTrace');
      rethrow;
    }
  }

  Future<void> _openCropScreen() async {
    if (_sourceBytes == null) return;

    final result = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => CropScreen(sourceBytes: _sourceBytes!),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _isPreparingImage = true;
    });

    try {
      final prepared = await compute(_prepareEditorBuffers, result);
      if (!mounted) return;
      setState(() {
        _sourceBytes = prepared['source'];
        _previewSourceBytes = prepared['preview'];
        _previewBytes = prepared['preview'];
        _imageAspectRatio = prepared['aspectRatio'] as double;
        _imageModified = true;
        _isPreparingImage = false;
        _resetAdjustmentsLocally();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isPreparingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('자르기에 실패했습니다: $error')),
      );
    }
  }

  void _showAiEditSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiEditSheet(onGenerate: _runAiEdit),
    );
  }

  Future<void> _saveImage() async {
    if (_sourceBytes == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 사진을 선택해 주세요.')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final rendered = await compute(
        _renderAdjustedJpg,
        _buildRenderRequest(_sourceBytes!),
      );

      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          throw Exception('갤러리 접근 권한이 허용되지 않았습니다.');
        }
      }

      final imageName = 'pozy_${DateTime.now().millisecondsSinceEpoch}.jpg';

      try {
        await Gal.putImageBytes(rendered, name: imageName);
      } catch (_) {
        final tempFile = File('${Directory.systemTemp.path}\\$imageName');
        await tempFile.writeAsBytes(rendered, flush: true);
        await Gal.putImage(tempFile.path);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('보정한 사진이 갤러리에 저장되었습니다.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('사진 저장에 실패했습니다: $error')));
    } finally {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final activeValue = _valueOf(_activeAdjustment);
          final screenWidth = constraints.maxWidth;
          final previewMetrics = _resolvePreviewMetrics(
            screenWidth: screenWidth,
            screenHeight: mediaQuery.size.height,
          );

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              18,
              10,
              18,
              mediaQuery.padding.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTopBar(
                  title: '보정',
                  onBack: widget.onBack,
                  trailingWidth: 64,
                  trailing: GestureDetector(
                    onTap: _hasImage && !_isSaving ? _saveImage : null,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '저장',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _hasImage && !_isSaving
                              ? AppColors.primaryText
                              : AppColors.lightText,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildPreviewCard(
                  previewWidth: previewMetrics.width,
                  previewHeight: previewMetrics.height,
                ),
                const SizedBox(height: 14),
                _buildActionRow(),
                if (_hasImage) ...[
                  const SizedBox(height: 10),
                  _buildAiEditButton(),
                  if (_hasAnyEdit) ...[
                    const SizedBox(height: 10),
                    _buildFullResetButton(),
                  ],
                ],
                const SizedBox(height: 18),
                _buildAdjustmentPanel(activeValue),
                const SizedBox(height: 14),
                _buildToolStrip(screenWidth),
              ],
            ),
          );
        },
      ),
    );
  }

  Size _resolvePreviewMetrics({
    required double screenWidth,
    required double screenHeight,
  }) {
    final maxWidth = screenWidth;
    final defaultHeight = (screenWidth * 0.98).clamp(
      280.0,
      screenHeight * 0.46,
    );
    final aspectRatio = _imageAspectRatio;

    if (aspectRatio == null || aspectRatio <= 0) {
      return Size(maxWidth, defaultHeight);
    }

    final maxHeight = screenHeight * 0.68;
    final minHeight = 260.0;
    final widthFromMaxHeight = maxHeight * aspectRatio;

    if (widthFromMaxHeight <= maxWidth) {
      return Size(widthFromMaxHeight, maxHeight.clamp(minHeight, maxHeight));
    }

    final resolvedHeight = (maxWidth / aspectRatio).clamp(minHeight, maxHeight);
    return Size(maxWidth, resolvedHeight);
  }

  Widget _buildPreviewCard({
    required double previewWidth,
    required double previewHeight,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: _pickImage,
        onLongPressStart: (_) {
          if (_hasImage) {
            setState(() {
              _showOriginalPreview = true;
            });
          }
        },
        onLongPressEnd: (_) {
          if (_showOriginalPreview) {
            setState(() {
              _showOriginalPreview = false;
            });
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Container(
            height: previewHeight,
            width: previewWidth,
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_hasImage && !_isPreparingImage) const _PlusPlaceholder(),
                if (_hasImage)
                  InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: SizedBox(
                      width: previewWidth,
                      height: previewHeight,
                      child: Image.memory(
                        _showOriginalPreview
                            ? _previewSourceBytes!
                            : (_previewBytes ?? _previewSourceBytes!),
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                if (_isPreparingImage || _isRenderingPreview || _isSaving)
                  Container(
                    color: Colors.black.withOpacity(0.22),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.62),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _isSaving
                                  ? '사진 저장 중...'
                                  : _isPreparingImage
                                  ? '사진 준비 중...'
                                  : '미리보기 적용 중...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAiEditButton() {
    return GestureDetector(
      onTap: _showAiEditSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 18, color: AppColors.primaryText),
            SizedBox(width: 8),
            Text(
              'AI로 편집하기',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullResetButton() {
    return GestureDetector(
      onTap: _resetEverything,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restart_alt, size: 18, color: AppColors.primaryText),
            SizedBox(width: 8),
            Text(
              '전체 초기화',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    final buttonStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 14),
      foregroundColor: AppColors.primaryText,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(_selectedImagePath == null ? '사진 추가' : '사진 바꾸기'),
            style: buttonStyle,
          ),
        ),
        if (_hasImage) ...[
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _openCropScreen,
              icon: const Icon(Icons.crop),
              label: const Text('자르기'),
              style: buttonStyle,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAdjustmentPanel(double activeValue) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _activeAdjustment.icon,
                  color: AppColors.primaryText,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeAdjustment.label,
                      style: AppTextStyles.title16,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _activeAdjustment.description,
                      style: AppTextStyles.caption12,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  activeValue.round().toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              if (_hasNonZeroAdjustment) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _resetAllAdjustments,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '초기화',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primaryText,
              inactiveTrackColor: AppColors.track,
              thumbColor: Colors.white,
              overlayColor: Colors.transparent,
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              min: -100,
              max: 100,
              divisions: 200,
              value: activeValue,
              onChanged: _hasImage ? _updateAdjustment : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: const [
                Text('-100', style: AppTextStyles.caption12),
                Spacer(),
                Text('0', style: AppTextStyles.caption12),
                Spacer(),
                Text('100', style: AppTextStyles.caption12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolStrip(double screenWidth) {
    final chipWidth = screenWidth < 380 ? 88.0 : 96.0;

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _EditorAdjustment.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final adjustment = _EditorAdjustment.values[index];
          final selected = adjustment == _activeAdjustment;

          return SizedBox(
            width: chipWidth,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _activeAdjustment = adjustment;
                });
              },
              child: _AdjustmentChip(
                icon: adjustment.icon,
                label: adjustment.shortLabel,
                value: _valueOf(adjustment).round(),
                selected: selected,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlusPlaceholder extends StatelessWidget {
  const _PlusPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 58,
              color: Colors.white70,
            ),
            SizedBox(height: 14),
            Text(
              '사진을 추가해 보정을 시작하세요',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdjustmentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final bool selected;

  const _AdjustmentChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryText : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.primaryText : AppColors.border,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: selected ? Colors.white : AppColors.primaryText,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white70 : AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _prepareEditorBuffers(Uint8List rawBytes) {
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) {
    throw Exception('이미지를 해석할 수 없습니다.');
  }

  final normalized = img.bakeOrientation(decoded);
  final exportBase = _resizeImageToMaxDimension(
    normalized,
    _editorExportMaxDimension,
  );
  final sourceBytes = Uint8List.fromList(
    img.encodeJpg(exportBase, quality: 92),
  );

  final previewBase = _resizeImageToMaxDimension(
    exportBase,
    _editorPreviewMaxDimension,
  );

  final previewBytes = Uint8List.fromList(
    img.encodeJpg(previewBase, quality: 92),
  );

  return {
    'source': sourceBytes,
    'preview': previewBytes,
    'aspectRatio': normalized.width / normalized.height,
  };
}

Uint8List _renderAdjustedJpg(Map<String, dynamic> request) {
  final bytes = request['bytes'] as Uint8List;
  final brightness = (request['brightness'] as num).toDouble();
  final contrast = (request['contrast'] as num).toDouble();
  final saturation = (request['saturation'] as num).toDouble();
  final warmth = (request['warmth'] as num).toDouble();
  final fade = (request['fade'] as num).toDouble();
  final sharpness = (request['sharpness'] as num).toDouble();

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('이미지를 해석할 수 없습니다.');
  }

  var edited = _applyEditorAdjustments(
    decoded,
    brightness: brightness,
    contrast: contrast,
    saturation: saturation,
    warmth: warmth,
    fade: fade,
  );

  if (sharpness != 0) {
    edited = _applySharpness(edited, sharpness);
  }

  return Uint8List.fromList(img.encodeJpg(edited, quality: 90));
}

img.Image _applyEditorAdjustments(
  img.Image source, {
  required double brightness,
  required double contrast,
  required double saturation,
  required double warmth,
  required double fade,
}) {
  final output = img.Image.from(source);

  final brightnessOffset = brightness * 2.2;
  final contrastScaled = contrast.clamp(-99.0, 99.0) * 2.55;
  final contrastFactor =
      (259 * (contrastScaled + 255)) / (255 * (259 - contrastScaled));
  final saturationFactor = 1 + (saturation / 100);
  final warmthFactor = warmth / 100;
  final fadeFactor = fade / 100;

  for (int y = 0; y < output.height; y++) {
    for (int x = 0; x < output.width; x++) {
      final pixel = output.getPixel(x, y);

      double r = pixel.r.toDouble();
      double g = pixel.g.toDouble();
      double b = pixel.b.toDouble();
      final int a = pixel.a.toInt();

      r += brightnessOffset;
      g += brightnessOffset;
      b += brightnessOffset;

      r = contrastFactor * (r - 128) + 128;
      g = contrastFactor * (g - 128) + 128;
      b = contrastFactor * (b - 128) + 128;

      final luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
      r = luminance + ((r - luminance) * saturationFactor);
      g = luminance + ((g - luminance) * saturationFactor);
      b = luminance + ((b - luminance) * saturationFactor);

      r += 30 * warmthFactor;
      g += 8 * warmthFactor;
      b -= 30 * warmthFactor;

      if (fadeFactor >= 0) {
        r = (r * (1 - (fadeFactor * 0.18))) + (255 * fadeFactor * 0.10);
        g = (g * (1 - (fadeFactor * 0.16))) + (255 * fadeFactor * 0.08);
        b = (b * (1 - (fadeFactor * 0.14))) + (255 * fadeFactor * 0.06);
      } else {
        final deepen = fadeFactor.abs();
        r = (r * (1 + (deepen * 0.16))) - (255 * deepen * 0.08);
        g = (g * (1 + (deepen * 0.15))) - (255 * deepen * 0.07);
        b = (b * (1 + (deepen * 0.14))) - (255 * deepen * 0.06);
      }

      output.setPixelRgba(
        x,
        y,
        _clampChannel(r),
        _clampChannel(g),
        _clampChannel(b),
        a,
      );
    }
  }

  return output;
}

int _clampChannel(double value) {
  if (value.isNaN) return 0;
  if (value < 0) return 0;
  if (value > 255) return 255;
  return value.round();
}

img.Image _applySharpness(img.Image source, double sharpness) {
  if (sharpness > 0) {
    final amount = sharpness / 100 * 1.5;
    final blurred = img.gaussianBlur(img.Image.from(source), radius: 2);
    final output = img.Image.from(source);

    for (int y = 0; y < output.height; y++) {
      for (int x = 0; x < output.width; x++) {
        final orig = source.getPixel(x, y);
        final blur = blurred.getPixel(x, y);

        output.setPixelRgba(
          x,
          y,
          _clampChannel(orig.r + amount * (orig.r - blur.r)),
          _clampChannel(orig.g + amount * (orig.g - blur.g)),
          _clampChannel(orig.b + amount * (orig.b - blur.b)),
          orig.a.toInt(),
        );
      }
    }
    return output;
  } else {
    final radius = (sharpness.abs() / 100 * 5).round().clamp(1, 5);
    return img.gaussianBlur(source, radius: radius);
  }
}

class _AiEditSheet extends StatefulWidget {
  final Future<void> Function(String prompt) onGenerate;

  const _AiEditSheet({required this.onGenerate});

  @override
  State<_AiEditSheet> createState() => _AiEditSheetState();
}

class _AiEditSheetState extends State<_AiEditSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canSubmit = !_isLoading && _controller.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI 이미지 편집', style: AppTextStyles.title16),
                  const SizedBox(height: 2),
                  Text('원하는 수정사항을 입력하세요', style: AppTextStyles.caption12),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            maxLines: 3,
            minLines: 2,
            enabled: !_isLoading,
            decoration: InputDecoration(
              hintText: '예: 배경을 노을로 바꿔줘',
              hintStyle: const TextStyle(
                color: AppColors.lightText,
                fontSize: 14,
              ),
              filled: true,
              fillColor: AppColors.soft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: canSubmit
                  ? () async {
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() {
                        _isLoading = true;
                      });
                      try {
                        await widget.onGenerate(_controller.text.trim());
                        if (mounted) navigator.pop();
                      } catch (_) {
                        if (!mounted) return;
                        setState(() {
                          _isLoading = false;
                        });
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('이미지 생성에 실패했어요. 다시 시도해주세요.'),
                          ),
                        );
                      }
                    }
                  : null,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.buttonDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                disabledBackgroundColor: AppColors.soft,
                disabledForegroundColor: AppColors.secondaryText,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '재생성',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

img.Image _resizeImageToMaxDimension(img.Image source, int maxDimension) {
  final longestSide = source.width >= source.height
      ? source.width
      : source.height;

  if (longestSide <= maxDimension) {
    return source;
  }

  if (source.width >= source.height) {
    return img.copyResize(source, width: maxDimension);
  }

  return img.copyResize(source, height: maxDimension);
}
