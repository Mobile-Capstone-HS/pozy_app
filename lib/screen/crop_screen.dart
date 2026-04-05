import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;


enum _AspectRatioOption { free, square, fourThree, threeFour, sixteenNine, nineSixteen }

extension on _AspectRatioOption {
  String get label {
    switch (this) {
      case _AspectRatioOption.free:
        return '자유';
      case _AspectRatioOption.square:
        return '1:1';
      case _AspectRatioOption.fourThree:
        return '4:3';
      case _AspectRatioOption.threeFour:
        return '3:4';
      case _AspectRatioOption.sixteenNine:
        return '16:9';
      case _AspectRatioOption.nineSixteen:
        return '9:16';
    }
  }

  double? get ratio {
    switch (this) {
      case _AspectRatioOption.free:
        return null;
      case _AspectRatioOption.square:
        return 1.0;
      case _AspectRatioOption.fourThree:
        return 4.0 / 3.0;
      case _AspectRatioOption.threeFour:
        return 3.0 / 4.0;
      case _AspectRatioOption.sixteenNine:
        return 16.0 / 9.0;
      case _AspectRatioOption.nineSixteen:
        return 9.0 / 16.0;
    }
  }
}

class CropScreen extends StatefulWidget {
  final Uint8List sourceBytes;

  const CropScreen({super.key, required this.sourceBytes});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  Uint8List? _displayBytes;
  int _imageWidth = 0;
  int _imageHeight = 0;
  int _rotationSteps = 0;
  bool _isProcessing = false;

  Rect _cropRect = const Rect.fromLTWH(0, 0, 1, 1);
  _AspectRatioOption _selectedAspect = _AspectRatioOption.free;

  _DragHandle? _activeHandle;
  Offset? _dragStart;
  Rect? _cropRectAtDragStart;

  @override
  void initState() {
    super.initState();
    _decodeDisplay();
  }

  Future<void> _decodeDisplay() async {
    setState(() => _isProcessing = true);
    try {
      final result = await compute(_decodeForDisplay, {
        'bytes': widget.sourceBytes,
        'rotation': _rotationSteps * 90,
      });
      if (!mounted) return;
      setState(() {
        _displayBytes = result['display'] as Uint8List;
        _imageWidth = result['width'] as int;
        _imageHeight = result['height'] as int;
        _isProcessing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }
  }

  void _rotate() {
    setState(() {
      _rotationSteps = (_rotationSteps + 1) % 4;
      _cropRect = const Rect.fromLTWH(0, 0, 1, 1);
      _selectedAspect = _AspectRatioOption.free;
    });
    _decodeDisplay();
  }

  void _selectAspectRatio(_AspectRatioOption option) {
    setState(() {
      _selectedAspect = option;
    });
    _applyCropAspectRatio(option);
  }

  void _applyCropAspectRatio(_AspectRatioOption option) {
    final ratio = option.ratio;
    if (ratio == null) return;

    if (_imageWidth == 0 || _imageHeight == 0) return;

    final imageAspect = _imageWidth / _imageHeight;
    final targetRatio = ratio / imageAspect;

    double newW, newH;
    if (targetRatio <= 1) {
      newH = 1.0;
      newW = targetRatio;
    } else {
      newW = 1.0;
      newH = 1.0 / targetRatio;
    }

    newW = newW.clamp(0.1, 1.0);
    newH = newH.clamp(0.1, 1.0);

    final cx = _cropRect.center.dx.clamp(newW / 2, 1.0 - newW / 2);
    final cy = _cropRect.center.dy.clamp(newH / 2, 1.0 - newH / 2);

    setState(() {
      _cropRect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: newW,
        height: newH,
      );
    });
  }

  Future<void> _apply() async {
    setState(() => _isProcessing = true);
    try {
      final result = await compute(_applyCropAndRotate, {
        'bytes': widget.sourceBytes,
        'rotation': _rotationSteps * 90,
        'cropLeft': _cropRect.left,
        'cropTop': _cropRect.top,
        'cropWidth': _cropRect.width,
        'cropHeight': _cropRect.height,
      });
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('자르기에 실패했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildCropArea()),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Text(
              '취소',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              '자르기',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          GestureDetector(
            onTap: _isProcessing ? null : _apply,
            child: Text(
              '적용',
              style: TextStyle(
                color: _isProcessing ? Colors.white38 : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropArea() {
    if (_displayBytes == null || _isProcessing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final areaWidth = constraints.maxWidth;
        final areaHeight = constraints.maxHeight;

        final imageAspect = _imageWidth / _imageHeight;
        double imgW, imgH;
        if (imageAspect > areaWidth / areaHeight) {
          imgW = areaWidth;
          imgH = areaWidth / imageAspect;
        } else {
          imgH = areaHeight;
          imgW = areaHeight * imageAspect;
        }

        final imgLeft = (areaWidth - imgW) / 2;
        final imgTop = (areaHeight - imgH) / 2;
        final imageRect = Rect.fromLTWH(imgLeft, imgTop, imgW, imgH);

        return GestureDetector(
          onPanStart: (d) => _onPanStart(d, imageRect),
          onPanUpdate: (d) => _onPanUpdate(d, imageRect),
          onPanEnd: (_) => _onPanEnd(),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: imageRect,
                child: Image.memory(
                  _displayBytes!,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropOverlayPainter(
                    cropRect: _cropRect,
                    imageRect: imageRect,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _AspectRatioOption.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final option = _AspectRatioOption.values[index];
                final selected = option == _selectedAspect;
                return GestureDetector(
                  onTap: () => _selectAspectRatio(option),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.white12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _isProcessing ? null : _rotate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.rotate_right, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '회전',
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
        ],
      ),
    );
  }

  // --- Gesture handling ---

  void _onPanStart(DragStartDetails details, Rect imageRect) {
    final local = details.localPosition;
    final handle = _hitTestHandle(local, imageRect);
    _activeHandle = handle;
    _dragStart = local;
    _cropRectAtDragStart = _cropRect;
  }

  void _onPanUpdate(DragUpdateDetails details, Rect imageRect) {
    if (_activeHandle == null || _dragStart == null || _cropRectAtDragStart == null) return;

    final dx = (details.localPosition.dx - _dragStart!.dx) / imageRect.width;
    final dy = (details.localPosition.dy - _dragStart!.dy) / imageRect.height;
    final base = _cropRectAtDragStart!;

    Rect newRect;
    switch (_activeHandle!) {
      case _DragHandle.topLeft:
        newRect = Rect.fromLTRB(
          (base.left + dx).clamp(0.0, base.right - 0.1),
          (base.top + dy).clamp(0.0, base.bottom - 0.1),
          base.right,
          base.bottom,
        );
        break;
      case _DragHandle.topRight:
        newRect = Rect.fromLTRB(
          base.left,
          (base.top + dy).clamp(0.0, base.bottom - 0.1),
          (base.right + dx).clamp(base.left + 0.1, 1.0),
          base.bottom,
        );
        break;
      case _DragHandle.bottomLeft:
        newRect = Rect.fromLTRB(
          (base.left + dx).clamp(0.0, base.right - 0.1),
          base.top,
          base.right,
          (base.bottom + dy).clamp(base.top + 0.1, 1.0),
        );
        break;
      case _DragHandle.bottomRight:
        newRect = Rect.fromLTRB(
          base.left,
          base.top,
          (base.right + dx).clamp(base.left + 0.1, 1.0),
          (base.bottom + dy).clamp(base.top + 0.1, 1.0),
        );
        break;
      case _DragHandle.top:
        newRect = Rect.fromLTRB(
          base.left,
          (base.top + dy).clamp(0.0, base.bottom - 0.1),
          base.right,
          base.bottom,
        );
        break;
      case _DragHandle.bottom:
        newRect = Rect.fromLTRB(
          base.left,
          base.top,
          base.right,
          (base.bottom + dy).clamp(base.top + 0.1, 1.0),
        );
        break;
      case _DragHandle.left:
        newRect = Rect.fromLTRB(
          (base.left + dx).clamp(0.0, base.right - 0.1),
          base.top,
          base.right,
          base.bottom,
        );
        break;
      case _DragHandle.right:
        newRect = Rect.fromLTRB(
          base.left,
          base.top,
          (base.right + dx).clamp(base.left + 0.1, 1.0),
          base.bottom,
        );
        break;
      case _DragHandle.move:
        final newLeft = (base.left + dx).clamp(0.0, 1.0 - base.width);
        final newTop = (base.top + dy).clamp(0.0, 1.0 - base.height);
        newRect = Rect.fromLTWH(newLeft, newTop, base.width, base.height);
        break;
    }

    if (_selectedAspect.ratio != null) {
      newRect = _enforceAspectRatio(newRect, _activeHandle!);
    }

    setState(() {
      _cropRect = newRect;
    });
  }

  void _onPanEnd() {
    _activeHandle = null;
    _dragStart = null;
    _cropRectAtDragStart = null;
  }

  Rect _enforceAspectRatio(Rect rect, _DragHandle handle) {
    final ratio = _selectedAspect.ratio;
    if (ratio == null) return rect;

    final imageAspect = _imageWidth / _imageHeight;
    final targetNorm = ratio / imageAspect;

    double w = rect.width;
    double h = rect.height;

    if (handle == _DragHandle.move) {
      return rect;
    }

    if (w / h > targetNorm) {
      w = h * targetNorm;
    } else {
      h = w / targetNorm;
    }

    w = w.clamp(0.1, 1.0);
    h = h.clamp(0.1, 1.0);

    double l = rect.left;
    double t = rect.top;

    switch (handle) {
      case _DragHandle.topLeft:
        l = rect.right - w;
        t = rect.bottom - h;
        break;
      case _DragHandle.topRight:
        t = rect.bottom - h;
        break;
      case _DragHandle.bottomLeft:
        l = rect.right - w;
        break;
      case _DragHandle.bottomRight:
      case _DragHandle.top:
      case _DragHandle.bottom:
      case _DragHandle.left:
      case _DragHandle.right:
      case _DragHandle.move:
        break;
    }

    l = l.clamp(0.0, 1.0 - w);
    t = t.clamp(0.0, 1.0 - h);

    return Rect.fromLTWH(l, t, w, h);
  }

  _DragHandle _hitTestHandle(Offset point, Rect imageRect) {
    const threshold = 30.0;

    final cropPixelRect = Rect.fromLTWH(
      imageRect.left + _cropRect.left * imageRect.width,
      imageRect.top + _cropRect.top * imageRect.height,
      _cropRect.width * imageRect.width,
      _cropRect.height * imageRect.height,
    );

    final tl = cropPixelRect.topLeft;
    final tr = cropPixelRect.topRight;
    final bl = cropPixelRect.bottomLeft;
    final br = cropPixelRect.bottomRight;

    if ((point - tl).distance < threshold) return _DragHandle.topLeft;
    if ((point - tr).distance < threshold) return _DragHandle.topRight;
    if ((point - bl).distance < threshold) return _DragHandle.bottomLeft;
    if ((point - br).distance < threshold) return _DragHandle.bottomRight;

    final topCenter = Offset(cropPixelRect.center.dx, cropPixelRect.top);
    final bottomCenter = Offset(cropPixelRect.center.dx, cropPixelRect.bottom);
    final leftCenter = Offset(cropPixelRect.left, cropPixelRect.center.dy);
    final rightCenter = Offset(cropPixelRect.right, cropPixelRect.center.dy);

    if ((point - topCenter).distance < threshold * 1.5 &&
        (point.dy - cropPixelRect.top).abs() < threshold) {
      return _DragHandle.top;
    }
    if ((point - bottomCenter).distance < threshold * 1.5 &&
        (point.dy - cropPixelRect.bottom).abs() < threshold) {
      return _DragHandle.bottom;
    }
    if ((point - leftCenter).distance < threshold * 1.5 &&
        (point.dx - cropPixelRect.left).abs() < threshold) {
      return _DragHandle.left;
    }
    if ((point - rightCenter).distance < threshold * 1.5 &&
        (point.dx - cropPixelRect.right).abs() < threshold) {
      return _DragHandle.right;
    }

    if (cropPixelRect.contains(point)) return _DragHandle.move;

    return _DragHandle.move;
  }
}

enum _DragHandle { topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right, move }

// --- Overlay Painter ---

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;
  final Rect imageRect;

  _CropOverlayPainter({required this.cropRect, required this.imageRect});

  @override
  void paint(Canvas canvas, Size size) {
    final cropPixelRect = Rect.fromLTWH(
      imageRect.left + cropRect.left * imageRect.width,
      imageRect.top + cropRect.top * imageRect.height,
      cropRect.width * imageRect.width,
      cropRect.height * imageRect.height,
    );

    // Darken outside
    final dimPaint = Paint()..color = const Color.fromRGBO(0, 0, 0, 0.55);
    canvas.save();
    canvas.clipRect(cropPixelRect, clipOp: ui.ClipOp.difference);
    canvas.drawRect(Offset.zero & size, dimPaint);
    canvas.restore();

    // Border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(cropPixelRect, borderPaint);

    // Grid lines (rule of thirds)
    final gridPaint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 1; i <= 2; i++) {
      final x = cropPixelRect.left + cropPixelRect.width * i / 3;
      canvas.drawLine(
        Offset(x, cropPixelRect.top),
        Offset(x, cropPixelRect.bottom),
        gridPaint,
      );
      final y = cropPixelRect.top + cropPixelRect.height * i / 3;
      canvas.drawLine(
        Offset(cropPixelRect.left, y),
        Offset(cropPixelRect.right, y),
        gridPaint,
      );
    }

    // Corner handles (L-shapes)
    final handlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const handleLen = 20.0;
    final corners = [
      cropPixelRect.topLeft,
      cropPixelRect.topRight,
      cropPixelRect.bottomLeft,
      cropPixelRect.bottomRight,
    ];

    for (int i = 0; i < corners.length; i++) {
      final c = corners[i];
      final hDir = (i % 2 == 0) ? 1.0 : -1.0;
      final vDir = (i < 2) ? 1.0 : -1.0;

      canvas.drawLine(c, Offset(c.dx + handleLen * hDir, c.dy), handlePaint);
      canvas.drawLine(c, Offset(c.dx, c.dy + handleLen * vDir), handlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect || oldDelegate.imageRect != imageRect;
  }
}

// --- Isolate functions ---

Map<String, dynamic> _decodeForDisplay(Map<String, dynamic> request) {
  final bytes = request['bytes'] as Uint8List;
  final rotation = request['rotation'] as int;

  var image = img.decodeImage(bytes);
  if (image == null) throw Exception('이미지를 해석할 수 없습니다.');

  image = img.bakeOrientation(image);

  if (rotation != 0) {
    image = img.copyRotate(image, angle: rotation);
  }

  final maxDim = 1200;
  final longestSide = max(image.width, image.height);
  if (longestSide > maxDim) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxDim);
    } else {
      image = img.copyResize(image, height: maxDim);
    }
  }

  return {
    'display': Uint8List.fromList(img.encodeJpg(image, quality: 88)),
    'width': image.width,
    'height': image.height,
  };
}

Uint8List _applyCropAndRotate(Map<String, dynamic> request) {
  final bytes = request['bytes'] as Uint8List;
  final rotation = request['rotation'] as int;
  final cropLeft = (request['cropLeft'] as num).toDouble();
  final cropTop = (request['cropTop'] as num).toDouble();
  final cropWidth = (request['cropWidth'] as num).toDouble();
  final cropHeight = (request['cropHeight'] as num).toDouble();

  var image = img.decodeImage(bytes);
  if (image == null) throw Exception('이미지를 해석할 수 없습니다.');

  image = img.bakeOrientation(image);

  if (rotation != 0) {
    image = img.copyRotate(image, angle: rotation);
  }

  final x = (cropLeft * image.width).round().clamp(0, image.width - 1);
  final y = (cropTop * image.height).round().clamp(0, image.height - 1);
  final w = (cropWidth * image.width).round().clamp(1, image.width - x);
  final h = (cropHeight * image.height).round().clamp(1, image.height - y);

  image = img.copyCrop(image, x: x, y: y, width: w, height: h);

  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}
