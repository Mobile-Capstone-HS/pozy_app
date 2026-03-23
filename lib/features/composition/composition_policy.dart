import 'package:flutter/material.dart';

abstract class CompositionPolicy {
  String get label;
  Color get accentColor;

  List<Offset> getTargets(Size size);
  bool isPerfect(double distance, Size size);
  void paintGuide(Canvas canvas, Size size);
}
