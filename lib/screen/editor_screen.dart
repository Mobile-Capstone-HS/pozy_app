import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pose_camera_app/services/gemini_service.dart';
import 'crop_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widget/app_top_bar.dart';
import 'editor/editor_types.dart';
import 'editor/editor_image_processing.dart';
import 'editor/editor_presets.dart';
import 'editor/editor_history.dart';
import 'editor/editor_comparison.dart';

class EditorScreen extends StatefulWidget {
  final ValueChanged<int> onMoveTab;
  final VoidCallback? onBack;
  final Future<Uint8List?>? initialBytesFuture;

  const EditorScreen({
    super.key,
    required this.onMoveTab,
    this.onBack,
    this.initialBytesFuture,
  });

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
  bool _comparisonMode = false;

  Timer? _previewDebounce;
  int _previewJobId = 0;

  EditorAdjustment _activeAdjustment = EditorAdjustment.brightness;
  final Map<EditorAdjustment, double> _adjustments = {
    for (final adjustment in EditorAdjustment.values) adjustment: 0,
  };

  final GeminiService _geminiService = GeminiService();

  FilterPreset? _activePreset;
  final EditorHistoryManager _history = EditorHistoryManager();

  final TransformationController _zoomController = TransformationController();
  double _currentZoom = 1.0;
  bool _showPresets = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialBytesFuture != null) {
      _selectedImagePath = 'gallery';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.initialBytesFuture!.then((bytes) {
          if (bytes != null && mounted) _loadFromRawBytes(bytes);
        });
      });
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _zoomController.dispose();
    super.dispose();
  }

  double _valueOf(EditorAdjustment adjustment) => _adjustments[adjustment] ?? 0;

  bool get _hasImage =>
      _sourceBytes != null &&
      _previewSourceBytes != null &&
      _previewBytes != null;

  bool get _hasNonZeroAdjustment => _adjustments.values.any((v) => v != 0);

  bool get _hasAnyEdit => _imageModified || _hasNonZeroAdjustment;

  void _resetEverything() {
    if (_originalSourceBytes == null) return;
    setState(() {
      _sourceBytes = _originalSourceBytes;
      _previewSourceBytes = _originalPreviewSourceBytes;
      _previewBytes = _originalPreviewSourceBytes;
      _imageAspectRatio = _originalAspectRatio;
      _imageModified = false;
      _comparisonMode = false;
      _resetAdjustmentsLocally();
    });
    _pushHistory(includeBytes: true);
  }

  void _resetActiveAdjustment() {
    setState(() {
      _adjustments[_activeAdjustment] = 0;
      _activePreset = null;
    });
    _schedulePreviewRender();
    _pushHistory();
  }

  void _pushHistory({bool includeBytes = false}) {
    _history.push(
      EditorSnapshot(
        adjustments: Map<EditorAdjustment, double>.from(_adjustments),
        sourceBytes: includeBytes ? _sourceBytes : null,
        previewSourceBytes: includeBytes ? _previewSourceBytes : null,
        imageAspectRatio: includeBytes ? _imageAspectRatio : null,
        imageModified: _imageModified,
      ),
    );
    setState(() {});
  }

  void _undo() {
    final snapshot = _history.undo();
    if (snapshot == null) return;
    _restoreSnapshot(snapshot);
  }

  void _redo() {
    final snapshot = _history.redo();
    if (snapshot == null) return;
    _restoreSnapshot(snapshot);
  }

  void _restoreSnapshot(EditorSnapshot snapshot) {
    setState(() {
      for (final entry in snapshot.adjustments.entries) {
        _adjustments[entry.key] = entry.value;
      }
      if (snapshot.sourceBytes != null) {
        _sourceBytes = snapshot.sourceBytes;
        _previewSourceBytes = snapshot.previewSourceBytes;
        _imageAspectRatio = snapshot.imageAspectRatio;
        _imageModified = snapshot.imageModified;
      }
      _activePreset = null;
    });
    _schedulePreviewRender();
  }

  Future<void> _pickImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final rawBytes = await File(file.path).readAsBytes();
    _selectedImagePath = file.path;
    await _loadFromRawBytes(rawBytes);
  }

  Future<void> _loadFromRawBytes(Uint8List rawBytes) async {
    setState(() {
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
      final prepared = await compute(prepareEditorBuffers, rawBytes);
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
      _resetZoom();
      _history.clear();
      _pushHistory(includeBytes: true);
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
    for (final adjustment in EditorAdjustment.values) {
      _adjustments[adjustment] = 0;
    }
    _activeAdjustment = EditorAdjustment.brightness;
    _activePreset = null;
  }

  void _applyPreset(FilterPreset preset) {
    setState(() {
      _activePreset = preset;
      for (final entry in preset.values.entries) {
        _adjustments[entry.key] = entry.value;
      }
    });
    _schedulePreviewRender();
    _pushHistory();
  }

  void _updateAdjustment(double value) {
    setState(() {
      _adjustments[_activeAdjustment] = value;
      _activePreset = null;
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
        final rendered = await compute(renderAdjustedJpg, request);
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
      'brightness': _valueOf(EditorAdjustment.brightness),
      'contrast': _valueOf(EditorAdjustment.contrast),
      'saturation': _valueOf(EditorAdjustment.saturation),
      'warmth': _valueOf(EditorAdjustment.warmth),
      'fade': _valueOf(EditorAdjustment.fade),
      'sharpness': _valueOf(EditorAdjustment.sharpness),
    };
  }

  Future<void> _runAiEdit(String prompt) async {
    debugPrint('[EditorScreen] _runAiEdit 호출됨, 프롬프트: $prompt');

    if (_previewSourceBytes == null) {
      debugPrint('[EditorScreen] _previewSourceBytes가 null → 조기 반환');
      return;
    }

    debugPrint(
      '[EditorScreen] _previewSourceBytes 크기: ${_previewSourceBytes!.lengthInBytes} bytes',
    );

    try {
      final result = await _geminiService.editImage(
        imageBytes: _previewSourceBytes!,
        prompt: prompt,
      );

      debugPrint(
        '[EditorScreen] editImage 결과: ${result == null ? "null" : "${result.lengthInBytes} bytes"}',
      );

      if (!mounted) return;

      if (result != null) {
        setState(() {
          _previewBytes = result;
          _sourceBytes = result;
          _previewSourceBytes = result;
          _imageModified = true;
          _resetAdjustmentsLocally();
        });
        _pushHistory(includeBytes: true);
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
      MaterialPageRoute(builder: (_) => CropScreen(sourceBytes: _sourceBytes!)),
    );

    if (result == null || !mounted) return;

    setState(() {
      _isPreparingImage = true;
    });

    try {
      final prepared = await compute(prepareEditorBuffers, result);
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
      _pushHistory(includeBytes: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isPreparingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('자르기에 실패했습니다: $error')));
    }
  }

  Future<void> _rotateImage() async {
    if (_sourceBytes == null) return;
    setState(() => _isPreparingImage = true);
    try {
      final rotated = await compute(rotateImage90, _sourceBytes!);
      final prepared = await compute(prepareEditorBuffers, rotated);
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
      _pushHistory(includeBytes: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isPreparingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('회전에 실패했습니다: $error')));
    }
  }

  Future<void> _flipImage() async {
    if (_sourceBytes == null) return;
    setState(() => _isPreparingImage = true);
    try {
      final flipped = await compute(flipImageHorizontal, _sourceBytes!);
      final prepared = await compute(prepareEditorBuffers, flipped);
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
      _pushHistory(includeBytes: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isPreparingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('뒤집기에 실패했습니다: $error')));
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
        renderAdjustedJpg,
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      child: Column(
        children: [
          // ── 상단 바 (고정) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: AppTopBar(
              title: '보정',
              onBack: widget.onBack,
              leadingIcon: widget.onBack != null
                  ? Icons.arrow_back_ios_new_rounded
                  : Icons.menu_rounded,
              trailingWidth: 120,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _history.canUndo ? _undo : null,
                    child: Icon(
                      Icons.undo,
                      size: 20,
                      color: _history.canUndo
                          ? AppColors.primaryText
                          : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _history.canRedo ? _redo : null,
                    child: Icon(
                      Icons.redo,
                      size: 20,
                      color: _history.canRedo
                          ? AppColors.primaryText
                          : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: _hasImage && !_isSaving ? _saveImage : null,
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
                ],
              ),
            ),
          ),

          // ── 이미지 캔버스 (남는 공간 전부 사용) ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: _buildCanvas(),
            ),
          ),

          // ── 하단 컨트롤 패널 (고정) ──
          _buildBottomPanel(bottomPadding),
        ],
      ),
    );
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
    setState(() => _currentZoom = 1.0);
  }

  // ── 이미지 캔버스 ──

  Widget _buildCanvas() {
    return GestureDetector(
      onTap: _hasImage ? null : _pickImage,
      onLongPressStart: (_) {
        if (_hasImage) setState(() => _showOriginalPreview = true);
      },
      onLongPressEnd: (_) {
        if (_showOriginalPreview) setState(() => _showOriginalPreview = false);
      },
      child: Container(
          color: AppColors.soft,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_hasImage)
                CustomPaint(painter: _CheckerboardPainter()),

              if (!_hasImage && !_isPreparingImage) const _PlusPlaceholder(),

              if (_hasImage && _comparisonMode && _originalPreviewSourceBytes != null)
                LayoutBuilder(
                  builder: (context, constraints) => ComparisonView(
                    originalBytes: _originalPreviewSourceBytes!,
                    editedBytes: _previewBytes ?? _previewSourceBytes!,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                )
              else if (_hasImage)
                InteractiveViewer(
                  transformationController: _zoomController,
                  minScale: 0.5,
                  maxScale: 8.0,
                  panEnabled: true,
                  scaleEnabled: true,
                  onInteractionUpdate: (details) {
                    final zoom = _zoomController.value.getMaxScaleOnAxis();
                    if ((zoom - _currentZoom).abs() > 0.01) {
                      setState(() => _currentZoom = zoom);
                    }
                  },
                  onInteractionEnd: (_) {
                    setState(() {
                      _currentZoom = _zoomController.value.getMaxScaleOnAxis();
                    });
                  },
                  child: Center(
                    child: Image.memory(
                      _showOriginalPreview
                          ? _previewSourceBytes!
                          : (_previewBytes ?? _previewSourceBytes!),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),

              // 줌 인디케이터
              if (_hasImage && !_comparisonMode)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: _ZoomIndicator(
                    zoom: _currentZoom,
                    onReset: _currentZoom != 1.0 ? _resetZoom : null,
                  ),
                ),

              // 로딩 오버레이
              if (_isPreparingImage || _isRenderingPreview || _isSaving)
                Container(
                  color: const Color(0x38000000),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0x9E000000),
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
    );
  }

  // ── 하단 고정 패널 ──

  Widget _buildBottomPanel(double bottomPadding) {
    final activeValue = _valueOf(_activeAdjustment);

    return Container(
      padding: EdgeInsets.fromLTRB(18, 6, 18, bottomPadding > 0 ? 4 : 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 액션 아이콘 바
          _buildActionBar(),
          const SizedBox(height: 8),
          // 슬라이더
          _buildCompactSlider(activeValue),
          const SizedBox(height: 8),
          // 탭 전환: 조절 / 필터
          _buildTabBar(),
          const SizedBox(height: 8),
          // 탭 내용
          _showPresets ? _buildPresetStrip() : _buildToolStrip(),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _ActionBarButton(
            icon: Icons.photo_library_outlined,
            label: _selectedImagePath == null ? '사진' : '바꾸기',
            onTap: _pickImage,
          ),
          if (_hasImage) ...[
            const SizedBox(width: 8),
            _ActionBarButton(
              icon: Icons.crop,
              label: '자르기',
              onTap: _openCropScreen,
            ),
            const SizedBox(width: 8),
            _ActionBarButton(
              icon: Icons.rotate_right,
              label: '회전',
              onTap: _rotateImage,
            ),
            const SizedBox(width: 8),
            _ActionBarButton(
              icon: Icons.flip,
              label: '뒤집기',
              onTap: _flipImage,
            ),
            const SizedBox(width: 8),
            _ActionBarButton(
              icon: Icons.auto_awesome,
              label: 'AI',
              onTap: _showAiEditSheet,
            ),
            if (_hasAnyEdit) ...[
              const SizedBox(width: 8),
              _ActionBarButton(
                icon: _comparisonMode ? Icons.compare : Icons.compare_outlined,
                label: '비교',
                onTap: () => setState(() => _comparisonMode = !_comparisonMode),
                active: _comparisonMode,
              ),
              const SizedBox(width: 8),
              _ActionBarButton(
                icon: Icons.restart_alt,
                label: '초기화',
                onTap: _resetEverything,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCompactSlider(double activeValue) {
    return Row(
      children: [
        Icon(_activeAdjustment.icon, size: 18, color: AppColors.primaryText),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          child: Text(
            _activeAdjustment.shortLabel,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primaryText,
              inactiveTrackColor: AppColors.track,
              thumbColor: Colors.white,
              overlayColor: Colors.transparent,
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              min: -100,
              max: 100,
              divisions: 200,
              value: activeValue,
              onChanged: _hasImage ? _updateAdjustment : null,
              onChangeEnd: _hasImage ? (_) => _pushHistory() : null,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            activeValue.round().toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
        ),
        if (activeValue != 0) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _resetActiveAdjustment,
            child: const Icon(Icons.refresh, size: 16, color: AppColors.secondaryText),
          ),
        ],
      ],
    );
  }

  Widget _buildTabBar() {
    return Row(
      children: [
        _TabButton(
          label: '조절',
          selected: !_showPresets,
          onTap: () => setState(() => _showPresets = false),
        ),
        const SizedBox(width: 8),
        _TabButton(
          label: '필터',
          selected: _showPresets,
          onTap: () => setState(() => _showPresets = true),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildPresetStrip() {
    return PresetStrip(
      activePreset: _activePreset,
      onSelect: _applyPreset,
    );
  }

  Widget _buildToolStrip() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EditorAdjustment.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final adjustment = EditorAdjustment.values[index];
          final selected = adjustment == _activeAdjustment;
          final value = _valueOf(adjustment).round();

          return GestureDetector(
            onTap: () => setState(() => _activeAdjustment = adjustment),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryText : AppColors.soft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primaryText : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    adjustment.icon,
                    size: 14,
                    color: selected ? Colors.white : AppColors.primaryText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${adjustment.shortLabel} $value',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.primaryText,
                    ),
                  ),
                ],
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
              color: AppColors.secondaryText,
            ),
            SizedBox(height: 14),
            Text(
              '사진을 추가해 보정을 시작하세요',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _ActionBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryText : AppColors.soft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? AppColors.primaryText : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : AppColors.primaryText),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : AppColors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryText : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  static const double _cellSize = 10.0;
  static const Color _light = Color(0xFFEEF1F5);
  static const Color _dark = Color(0xFFE4E8EE);

  @override
  void paint(Canvas canvas, Size size) {
    final paintLight = Paint()..color = _light;
    final paintDark = Paint()..color = _dark;
    final cols = (size.width / _cellSize).ceil();
    final rows = (size.height / _cellSize).ceil();

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final rect = Rect.fromLTWH(
          col * _cellSize,
          row * _cellSize,
          _cellSize,
          _cellSize,
        );
        canvas.drawRect(rect, (row + col).isEven ? paintLight : paintDark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ZoomIndicator extends StatelessWidget {
  final double zoom;
  final VoidCallback? onReset;

  const _ZoomIndicator({required this.zoom, this.onReset});

  @override
  Widget build(BuildContext context) {
    final label = '${(zoom * 100).round()}%';
    return GestureDetector(
      onTap: onReset,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onReset != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.refresh, size: 12, color: AppColors.secondaryText),
            ],
          ],
        ),
      ),
    );
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
    final mq = MediaQuery.of(context);
    final bottomPadding = mq.viewInsets.bottom > 0
        ? mq.viewInsets.bottom
        : mq.viewPadding.bottom;
    final canSubmit = !_isLoading && _controller.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomPadding),
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
