import 'package:flutter/material.dart';

class SubjectState {
  const SubjectState({
    required this.position,
    required this.confidence,
    required this.label,
    this.boundingBox,
  });

  final Offset position;
  final Rect? boundingBox;
  final double confidence;
  final String label;
}
