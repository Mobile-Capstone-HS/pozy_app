import 'package:flutter/material.dart';

class TrackedSubject {
  final String className;
  final Rect normalizedBox;
  final Rect rect;
  final double confidence;

  const TrackedSubject({
    required this.className,
    required this.normalizedBox,
    required this.rect,
    required this.confidence,
  });
}
