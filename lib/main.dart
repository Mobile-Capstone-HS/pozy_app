import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'golden.dart' as golden;
import 'third.dart' as third;

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
    golden.cameras = cameras;
    third.cameras = cameras;
  } catch (error) {
    debugPrint('Camera initialization error: $error');
  }

  runApp(const PozyApp());
}
