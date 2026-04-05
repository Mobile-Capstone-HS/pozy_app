import 'package:flutter/material.dart';

enum EditorAdjustment { brightness, contrast, saturation, warmth, fade, sharpness }

extension EditorAdjustmentExt on EditorAdjustment {
  String get label {
    switch (this) {
      case EditorAdjustment.brightness:
        return '밝기';
      case EditorAdjustment.contrast:
        return '대비';
      case EditorAdjustment.saturation:
        return '채도';
      case EditorAdjustment.warmth:
        return '색온도';
      case EditorAdjustment.fade:
        return '페이드';
      case EditorAdjustment.sharpness:
        return '선명도';
    }
  }

  String get shortLabel {
    switch (this) {
      case EditorAdjustment.brightness:
        return '밝기';
      case EditorAdjustment.contrast:
        return '대비';
      case EditorAdjustment.saturation:
        return '채도';
      case EditorAdjustment.warmth:
        return '온도';
      case EditorAdjustment.fade:
        return '페이드';
      case EditorAdjustment.sharpness:
        return '선명도';
    }
  }

  String get description {
    switch (this) {
      case EditorAdjustment.brightness:
        return '사진 전체의 밝기를 조절합니다';
      case EditorAdjustment.contrast:
        return '밝고 어두운 영역의 차이를 키웁니다';
      case EditorAdjustment.saturation:
        return '색상의 선명함과 진하기를 조절합니다';
      case EditorAdjustment.warmth:
        return '차갑거나 따뜻한 색감으로 바꿉니다';
      case EditorAdjustment.fade:
        return '대비를 누그러뜨려 부드러운 분위기를 만듭니다';
      case EditorAdjustment.sharpness:
        return '이미지의 디테일과 경계를 강조합니다';
    }
  }

  IconData get icon {
    switch (this) {
      case EditorAdjustment.brightness:
        return Icons.wb_sunny_outlined;
      case EditorAdjustment.contrast:
        return Icons.contrast;
      case EditorAdjustment.saturation:
        return Icons.palette_outlined;
      case EditorAdjustment.warmth:
        return Icons.thermostat_auto_outlined;
      case EditorAdjustment.fade:
        return Icons.blur_on_outlined;
      case EditorAdjustment.sharpness:
        return Icons.deblur;
    }
  }
}
