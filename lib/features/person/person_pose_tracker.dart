import 'package:flutter/material.dart';
import 'package:pose_camera_app/core/models/subject_state.dart';
import 'package:ultralytics_yolo/yolo.dart';

class PersonPoseTracker {
  SubjectState? track(List<YOLOResult> results, Size screenSize) {
    if (results.isEmpty) return null;

    YOLOResult? bestPerson;
    double maxArea = 0;

    for (final result in results) {
      final keypoints = result.keypoints;
      if (keypoints == null || keypoints.isEmpty) continue;

      final area = result.normalizedBox.width * result.normalizedBox.height;
      if (area > maxArea) {
        maxArea = area;
        bestPerson = result;
      }
    }

    if (bestPerson == null) return null;

    final keypoints = bestPerson.keypoints;
    if (keypoints == null || keypoints.isEmpty) return null;

    final nose = keypoints[0];
    final leftEye = keypoints.length > 1 ? keypoints[1] : keypoints[0];
    final rightEye = keypoints.length > 2 ? keypoints[2] : keypoints[0];

    final imageWidth =
        bestPerson.boundingBox.width / bestPerson.normalizedBox.width;
    final imageHeight =
        bestPerson.boundingBox.height / bestPerson.normalizedBox.height;

    final faceX = (nose.x + leftEye.x + rightEye.x) / 3;
    final faceY = (nose.y + leftEye.y + rightEye.y) / 3;

    final position = Offset(
      (faceX / imageWidth) * screenSize.width,
      (faceY / imageHeight) * screenSize.height,
    );

    final screenBox = Rect.fromLTRB(
      bestPerson.normalizedBox.left * screenSize.width,
      bestPerson.normalizedBox.top * screenSize.height,
      bestPerson.normalizedBox.right * screenSize.width,
      bestPerson.normalizedBox.bottom * screenSize.height,
    );

    return SubjectState(
      position: position,
      boundingBox: screenBox,
      confidence: bestPerson.confidence,
      label: bestPerson.className,
    );
  }
}