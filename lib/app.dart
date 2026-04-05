import 'package:flutter/material.dart';
import 'screen/splash_screen.dart';
import 'theme/app_colors.dart';

class PozyApp extends StatelessWidget {
  const PozyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pozy',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryText,
          background: AppColors.background,
        ),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}