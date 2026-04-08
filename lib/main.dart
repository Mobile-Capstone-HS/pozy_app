import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  try {
    cameras = await availableCameras();
  } catch (error) {
    debugPrint('Camera initialization error: $error'); 
  }
  
  runApp(const PozyApp()); 
}
