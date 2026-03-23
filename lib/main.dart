import 'package:flutter/material.dart';
import 'package:pose_camera_app/screens/main_shell_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFFF6F6F2);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pozy',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: base,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF181818),
          brightness: Brightness.light,
        ),
      ),
      home: const MainShellScreen(),
    );
  }
}