import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/enums/composition_mode.dart';
import 'package:pose_camera_app/screens/camera_coach_screen.dart';

class RuleOfThirdsScreen extends StatelessWidget {
  const RuleOfThirdsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CameraCoachScreen(
      compositionMode: CompositionMode.ruleOfThirds,
    );
  }
}
