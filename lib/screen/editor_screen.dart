import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';

const int _editorExportMaxDimension = 3072;
const int _editorPreviewMaxDimension = 1600;

enum _EditorAdjustment { brightness, contrast, saturation, warmth, fade }

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
    };
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

  Widget _buildActionRow() {
    final replaceButton = OutlinedButton.icon(
      onPressed: _pickImage,
      icon: const Icon(Icons.photo_library_outlined),
      label: Text(_selectedImagePath == null ? '사진 추가' : '사진 바꾸기'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        foregroundColor: AppColors.primaryText,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );

    return SizedBox(width: double.infinity, child: replaceButton);
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
            SizedBox(height: 8),
            Text(
              '밝기, 대비, 채도, 색온도, 페이드 조절을 지원합니다.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
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

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('이미지를 해석할 수 없습니다.');
  }

  final edited = _applyEditorAdjustments(
    decoded,
    brightness: brightness,
    contrast: contrast,
    saturation: saturation,
    warmth: warmth,
    fade: fade,
  );

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
