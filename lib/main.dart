import 'dart:async';

import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import 'app.dart';
import 'firebase/firebase_options.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadDotenv();
  runApp(const PozyApp());
  unawaited(_initializeAppServices());
}

Future<void> _loadDotenv() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (error) {
    debugPrint('Dotenv initialization error: $error');
  }
}

Future<void> _initializeAppServices() async {
  unawaited(_initializeNaverMap());
  unawaited(_initializeFirebase());
  unawaited(_initializeCameras());
}

Future<void> _initializeNaverMap() async {
  try {
    await FlutterNaverMap().init(
      clientId: dotenv.isInitialized
          ? dotenv.env['NAVER_MAP_CLIENT_ID'] ?? ''
          : '',
      onAuthFailed: (error) => debugPrint('Naver Map auth failed: $error'),
    );
  } catch (error) {
    debugPrint('Naver Map initialization error: $error');
  }
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (error) {
    debugPrint('Firebase initialization error: $error');
  }
}

Future<void> _initializeCameras() async {
  try {
    cameras = await availableCameras();
  } catch (error) {
    debugPrint('Camera initialization error: $error');
  }
}
