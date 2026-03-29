import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'app.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    cameras = await availableCameras();
  } catch (error) {
    debugPrint('Camera initialization error: $error'); 
  }

  runApp(const PozyApp());
}
