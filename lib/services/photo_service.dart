import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PhotoService {
  Future<Directory> _photosDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docsDir.path, 'photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    return photosDir;
  }

  Future<String> savePhoto(XFile photo) async {
    final photosDir = await _photosDirectory();
    final fileName = 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savePath = p.join(photosDir.path, fileName);
    final bytes = await photo.readAsBytes();
    final savedFile = await File(savePath).writeAsBytes(
      bytes,
      flush: true,
    );
    return savedFile.path;
  }

  Future<List<File>> loadPhotos() async {
    final photosDir = await _photosDirectory();
    final entities = await photosDir.list().toList();

    final files = entities.whereType<File>().toList();
    files.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return files;
  }

  Future<void> deletePhoto(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
