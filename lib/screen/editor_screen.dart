import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pose_camera_app/services/gemini_service.dart';
import 'crop_screen.dart';
import 'editor/editor_types.dart';
import 'editor/editor_image_processing.dart';
import 'editor/editor_presets.dart';
import 'editor/editor_history.dart';
import 'editor/editor_comparison.dart';

const _kBg = Color(0xFFF6F7FB);
const _kBlue = Color(0xFF5BB8D4);
const _kDark = Color(0xFF2F2F2F);
const _kGrey600 = Color(0xFF6B7684);
const _kGrey400 = Color(0xFFB0B8C1);
const _kGrey100 = Color(0xFFF1F5F9);

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
      _isPreparingImage = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.initialBytesFuture!.then((bytes) {
          if (bytes != null && mounted) {
            _loadFromRawBytes(bytes);
          } else if (mounted) {
            setState(() => _isPreparingImage = false);
          }
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
      final prepared = await compute(rotateImage90AndPrepare, _sourceBytes!);
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
      final prepared = await compute(flipImageHorizontalAndPrepare, _sourceBytes!);
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

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── 상단 바 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
              child: Row(
                children: [
                  // 뒤로가기 / 메뉴
                  if (widget.onBack != null)
                    GestureDetector(
                      onTap: widget.onBack,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _kGrey100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: _kDark,
                        ),
                      ),
                    ),
                  if (widget.onBack != null) const SizedBox(width: 12),
                  Image.asset(
                    'assets/images/pozy_logo2.png',
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  const Spacer(),
                  // Undo / Redo
                  _HeaderIconBtn(
                    icon: Icons.undo_rounded,
                    enabled: _history.canUndo,
                    onTap: _undo,
                  ),
                  const SizedBox(width: 6),
                  _HeaderIconBtn(
                    icon: Icons.redo_rounded,
                    enabled: _history.canRedo,
                    onTap: _redo,
                  ),
                  const SizedBox(width: 10),
                  // 저장
                  GestureDetector(
                    onTap: _hasImage && !_isSaving ? _saveImage : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: _hasImage && !_isSaving ? _kBlue : _kGrey100,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _hasImage && !_isSaving
                            ? [
                                BoxShadow(
                                  color: _kBlue.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.save_alt_rounded,
                            size: 14,
                            color: _hasImage && !_isSaving
                                ? Colors.white
                                : _kGrey400,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '저장',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _hasImage && !_isSaving
                                  ? Colors.white
                                  : _kGrey400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── 이미지 캔버스 ──
            Expanded(child: _buildCanvas()),

            const SizedBox(height: 4),

            // ── 하단 패널 ──
            _buildBottomPanel(bottomPadding),
          ],
        ),
      ),
    );
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
    setState(() => _currentZoom = 1.0);
  }

  Widget _buildCanvas() {
    // 사진이 없을 때: 빈 플레이스홀더 카드 (Expanded가 크기 결정)
    if (!_hasImage) {
      return GestureDetector(
        onTap: _isPreparingImage ? null : _pickImage,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!_isPreparingImage) const _EmptyPlaceholder(),
              if (_isPreparingImage)
                Container(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            '불러오는 중…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
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

    // 사진이 있을 때: 사진 비율에 맞춰 카드 크기 동적 조정
    final aspect = _imageAspectRatio ?? 1.0;

    return GestureDetector(
      onLongPressStart: (_) {
        setState(() => _showOriginalPreview = true);
      },
      onLongPressEnd: (_) {
        if (_showOriginalPreview) {
          setState(() => _showOriginalPreview = false);
        }
      },
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 사용 가능한 영역 내에서 사진 비율에 맞는 최대 크기 계산
              double w = constraints.maxWidth;
              double h = w / aspect;
              if (h > constraints.maxHeight) {
                h = constraints.maxHeight;
                w = h * aspect;
              }

              return SizedBox(
                width: w,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 사진 영역
                    if (_comparisonMode &&
                        _previewSourceBytes != null)
                      ComparisonView(
                        originalBytes: _previewSourceBytes!,
                        editedBytes:
                            _previewBytes ?? _previewSourceBytes!,
                        width: w,
                        height: h,
                      )
                    else
                      InteractiveViewer(
                        transformationController: _zoomController,
                        minScale: 0.5,
                        maxScale: 8.0,
                        panEnabled: true,
                        scaleEnabled: true,
                        onInteractionUpdate: (details) {
                          final zoom = _zoomController.value
                              .getMaxScaleOnAxis();
                          if ((zoom - _currentZoom).abs() > 0.01) {
                            setState(() => _currentZoom = zoom);
                          }
                        },
                        onInteractionEnd: (_) {
                          setState(() {
                            _currentZoom = _zoomController.value
                                .getMaxScaleOnAxis();
                          });
                        },
                        child: Image.memory(
                          _showOriginalPreview
                              ? _previewSourceBytes!
                              : (_previewBytes ?? _previewSourceBytes!),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),

                    // 줌 인디케이터
                    if (!_comparisonMode)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _ZoomBadge(
                          zoom: _currentZoom,
                          onReset:
                              _currentZoom != 1.0 ? _resetZoom : null,
                        ),
                      ),

                    // 로딩
                    if (_isRenderingPreview || _isSaving)
                      Container(
                        color: Colors.black.withValues(alpha: 0.25),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _isSaving
                                      ? '저장 중...'
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
              );
            },
          ),
        ),
      ),
    );
  }

  // ── 하단 패널 ──

  Widget _buildBottomPanel(double bottomPadding) {
    final activeValue = _valueOf(_activeAdjustment);

    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding > 0 ? 4 : 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        border: const Border(top: BorderSide(color: Color(0xFFF7F8FB))),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionBar(),
          const SizedBox(height: 10),
          _buildSlider(activeValue),
          const SizedBox(height: 10),
          _buildTabBar(),
          const SizedBox(height: 8),
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
          _ActionChip(
            icon: Icons.photo_library_outlined,
            label: _selectedImagePath == null ? '사진' : '바꾸기',
            onTap: _pickImage,
          ),
          if (_hasImage) ...[
            const SizedBox(width: 8),
            _ActionChip(
                icon: Icons.crop_rounded,
                label: '자르기',
                onTap: _openCropScreen),
            const SizedBox(width: 8),
            _ActionChip(
                icon: Icons.rotate_right_rounded,
                label: '회전',
                onTap: _rotateImage),
            const SizedBox(width: 8),
            _ActionChip(
                icon: Icons.flip_rounded,
                label: '뒤집기',
                onTap: _flipImage),
            // 구분선
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: VerticalDivider(width: 1, color: Color(0xFFDDE1E7)),
            ),
            // AI 버튼 — 포인트 강조
            _ActionChip(
              icon: Icons.auto_awesome_rounded,
              label: 'AI 편집',
              onTap: _showAiEditSheet,
              highlight: true,
            ),
            if (_hasAnyEdit) ...[
              // 구분선
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: VerticalDivider(width: 1, color: Color(0xFFDDE1E7)),
              ),
              _ActionChip(
                icon: _comparisonMode
                    ? Icons.compare_rounded
                    : Icons.compare_outlined,
                label: '비교',
                onTap: () =>
                    setState(() => _comparisonMode = !_comparisonMode),
                active: _comparisonMode,
              ),
              const SizedBox(width: 8),
              _ActionChip(
                icon: Icons.restart_alt_rounded,
                label: '초기화',
                onTap: _resetEverything,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSlider(double activeValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 현재 조절 항목명 + 값
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Icon(_activeAdjustment.icon, size: 15, color: _kBlue),
              const SizedBox(width: 6),
              Text(
                _activeAdjustment.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _kDark,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Text(
                  activeValue.round().toString(),
                  key: ValueKey(activeValue.round()),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: activeValue != 0 ? _kBlue : _kGrey400,
                  ),
                ),
              ),
              if (activeValue != 0) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _resetActiveAdjustment,
                  child: const Icon(Icons.refresh_rounded,
                      size: 15, color: _kGrey400),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _kBlue,
            inactiveTrackColor: _kGrey100,
            thumbColor: Colors.white,
            overlayColor: _kBlue.withValues(alpha: 0.08),
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
      ],
    );
  }

  Widget _buildTabBar() {
    return Row(
      children: [
        _TabChip(
          label: '조절',
          selected: !_showPresets,
          onTap: () => setState(() => _showPresets = false),
        ),
        const SizedBox(width: 8),
        _TabChip(
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
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EditorAdjustment.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final adjustment = EditorAdjustment.values[index];
          final selected = adjustment == _activeAdjustment;
          final value = _valueOf(adjustment).round();

          return GestureDetector(
            onTap: () => setState(() => _activeAdjustment = adjustment),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? _kBlue : _kGrey100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    adjustment.icon,
                    size: 14,
                    color: selected ? Colors.white : _kDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${adjustment.shortLabel} $value',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : _kDark,
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

// ── 빈 상태 플레이스홀더 ──
class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFEEF6FB),
            const Color(0xFFF6F7FB),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DashedBorderIcon(),
            const SizedBox(height: 20),
            const Text(
              '사진을 추가해 보정을 시작하세요',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _kDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '탭해서 갤러리에서 선택',
              style: TextStyle(
                fontSize: 13,
                color: _kGrey600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashedBorderIcon extends StatelessWidget {
  const DashedBorderIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(80, 80),
      painter: _DashedRectPainter(),
      child: const SizedBox(
        width: 80,
        height: 80,
        child: Center(
          child: Icon(
            Icons.add_photo_alternate_outlined,
            size: 34,
            color: _kBlue,
          ),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kBlue.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    const radius = 20.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    final dashPath = Path();
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── 헤더 아이콘 버튼 ──
class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _HeaderIconBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _kGrey100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? _kDark : _kGrey400,
        ),
      ),
    );
  }
}

// ── 액션 칩 ──
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool highlight;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? _kDark
        : highlight
            ? _kBlue.withValues(alpha: 0.12)
            : _kGrey100;
    final iconColor = active
        ? Colors.white
        : highlight
            ? _kBlue
            : _kDark;
    final textColor = active
        ? Colors.white
        : highlight
            ? _kBlue
            : _kDark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 탭 칩 ──
class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _kBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : _kGrey400,
          ),
        ),
      ),
    );
  }
}

// ── 줌 뱃지 ──
class _ZoomBadge extends StatelessWidget {
  final double zoom;
  final VoidCallback? onReset;

  const _ZoomBadge({required this.zoom, this.onReset});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onReset,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(zoom * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onReset != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.refresh_rounded,
                  size: 12, color: Colors.white70),
            ],
          ],
        ),
      ),
    );
  }
}

// ── AI 편집 시트 ──
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: _kGrey100,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI 이미지 편집',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kDark,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '원하는 수정사항을 입력하세요',
                    style: TextStyle(fontSize: 13, color: _kGrey600),
                  ),
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
              hintStyle: const TextStyle(color: _kGrey400, fontSize: 14),
              filled: true,
              fillColor: _kGrey100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: canSubmit
                ? () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _isLoading = true);
                    try {
                      await widget.onGenerate(_controller.text.trim());
                      if (mounted) navigator.pop();
                    } catch (_) {
                      if (!mounted) return;
                      setState(() => _isLoading = false);
                      messenger.showSnackBar(
                        const SnackBar(
                          content:
                              Text('이미지 생성에 실패했어요. 다시 시도해주세요.'),
                        ),
                      );
                    }
                  }
                : null,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: canSubmit ? _kBlue : _kGrey100,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '생성하기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: canSubmit ? Colors.white : _kGrey400,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
