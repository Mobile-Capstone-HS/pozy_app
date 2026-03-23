import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

class CaptureService {
  Future<File> capturePreviewToTempFile({
    required GlobalKey repaintBoundaryKey,
    double pixelRatio = 1.6,
  }) async {
    final bytes = await captureToBytes(
      repaintBoundaryKey: repaintBoundaryKey,
      pixelRatio: pixelRatio,
    );

    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/pozy_preview_${DateTime.now().millisecondsSinceEpoch}.png',
    );

    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Uint8List> captureToBytes({
    required GlobalKey repaintBoundaryKey,
    double pixelRatio = 3.0,
  }) async {
    final context = repaintBoundaryKey.currentContext;
    if (context == null) {
      throw Exception('캡처할 화면을 찾지 못했어.');
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw Exception('캡처 대상이 RepaintBoundary가 아니야.');
    }

    final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw Exception('이미지 바이트 변환에 실패했어.');
    }

    return byteData.buffer.asUint8List();
  }

  Future<String> captureToGalleryAndAppStorage({
    required GlobalKey repaintBoundaryKey,
    double pixelRatio = 3.0,
  }) async {
    final pngBytes = await captureToBytes(
      repaintBoundaryKey: repaintBoundaryKey,
      pixelRatio: pixelRatio,
    );

    final hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      final granted = await Gal.requestAccess();
      if (!granted) {
        throw Exception('갤러리 권한이 허용되지 않았어.');
      }
    }

    await Gal.putImageBytes(pngBytes, album: 'Pozy');

    final appDir = await getApplicationDocumentsDirectory();
    final captureDir = Directory('${appDir.path}/captures');

    if (!captureDir.existsSync()) {
      captureDir.createSync(recursive: true);
    }

    final filePath =
        '${captureDir.path}/capture_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(filePath);
    await file.writeAsBytes(pngBytes, flush: true);

    return file.path;
  }

  Future<List<File>> listLocalCaptures() async {
    final appDir = await getApplicationDocumentsDirectory();
    final captureDir = Directory('${appDir.path}/captures');

    if (!captureDir.existsSync()) {
      return [];
    }

    final files =
        captureDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.png'))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );

    return files;
  }

  Future<void> deleteLocalCapture(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteAllLocalCaptures() async {
    final files = await listLocalCaptures();

    for (final file in files) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
