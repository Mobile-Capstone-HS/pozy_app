import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'detect.dart' as detect;
import 'figma_design.dart' as figma_design;
import 'golden.dart' as golden;
import 'third.dart' as third;

List<CameraDescription> cameras = [];
String? cameraInitError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
    golden.cameras = cameras;
    third.cameras = cameras;
    detect.cameras = cameras;
  } catch (e) {
    cameraInitError = e.toString();
    debugPrint('Camera Initialization Error: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Camera Coach',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        cardTheme: const CardThemeData(
          color: Color(0xFF16213E),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
        ),
      ),
      home: cameraInitError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    'Camera Error: $cameraInitError',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          : const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(30.0),
                child: Column(
                  children: [
                    const Icon(
                      Icons.camera_alt_rounded,
                      size: 80,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'AI Camera Coach',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'AI composition guide for better photos',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.7),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildMenuCard(
                          context,
                          title: 'Golden Ratio',
                          subtitle: '1:1.618 composition helper',
                          icon: Icons.auto_awesome,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const golden.GoldenRatioScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildMenuCard(
                          context,
                          title: 'Rule of Thirds',
                          subtitle: 'Classic balanced composition',
                          icon: Icons.grid_on,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00D4FF), Color(0xFF0099FF)],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const third.RuleOfThirdsScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildMenuCard(
                          context,
                          title: 'Detect',
                          subtitle: 'Person + Object Bounding Boxes',
                          icon: Icons.center_focus_strong,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const detect.DetectScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildMenuCard(
                          context,
                          title: 'Figma Design',
                          subtitle: 'Open the new design page',
                          icon: Icons.design_services_rounded,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const figma_design.FigmaDesignScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'YOLO Pose + Object Detection',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.05),
                Colors.white.withOpacity(0.02),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.colors.first.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(icon, size: 40, color: Colors.white),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withOpacity(0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
