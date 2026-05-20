import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screen/main_shell.dart';
import 'theme/app_colors.dart';

bool isCameraScreenActive = false;

class PozyApp extends StatelessWidget {
  const PozyApp({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('[PozyApp] build');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pozy',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryText,
          surface: AppColors.background,
        ),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        useMaterial3: true,
      ),
      builder: (context, child) {
        return Listener(
          onPointerDown: (_) {
            if (!isCameraScreenActive) {
              SystemSound.play(SystemSoundType.click);
            }
          },
          child: child ?? const SizedBox(),
        );
      },
      home: const MainShell(),
    );
  }
}
