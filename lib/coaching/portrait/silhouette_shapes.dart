import 'package:flutter/material.dart';

enum SilhouetteType {
  none,
  standing,
  halfBody,
  sitting,
}

class SilhouetteShapes {
  static Path getPath(SilhouetteType type, Size size) {
    switch (type) {
      case SilhouetteType.standing:
        return _getStandingPath(size);
      case SilhouetteType.halfBody:
        return _getHalfBodyPath(size);
      case SilhouetteType.sitting:
        return _getSittingPath(size);
      case SilhouetteType.none:
        return Path();
    }
  }

  static Path _getStandingPath(Size size) {
    final path = Path();
    final width = size.width;
    final height = size.height;

    // 머리
    final headRadius = width * 0.08;
    final headCenter = Offset(width * 0.5, height * 0.25);
    path.addOval(Rect.fromCircle(center: headCenter, radius: headRadius));

    // 몸통 (어깨~골반)
    final torsoWidth = width * 0.25;
    final torsoHeight = height * 0.25;
    final torsoRect = Rect.fromCenter(
      center: Offset(width * 0.5, height * 0.45),
      width: torsoWidth,
      height: torsoHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(torsoRect, const Radius.circular(20)));

    // 왼쪽 팔
    final armWidth = width * 0.06;
    final armHeight = height * 0.25;
    final leftArmRect = Rect.fromLTWH(
      width * 0.5 - torsoWidth / 2 - armWidth * 1.2,
      height * 0.35,
      armWidth,
      armHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(leftArmRect, const Radius.circular(15)));

    // 오른쪽 팔
    final rightArmRect = Rect.fromLTWH(
      width * 0.5 + torsoWidth / 2 + armWidth * 0.2,
      height * 0.35,
      armWidth,
      armHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(rightArmRect, const Radius.circular(15)));

    // 왼쪽 다리
    final legWidth = width * 0.08;
    final legHeight = height * 0.3;
    final leftLegRect = Rect.fromLTWH(
      width * 0.5 - torsoWidth / 2 + width * 0.02,
      height * 0.56,
      legWidth,
      legHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(leftLegRect, const Radius.circular(15)));

    // 오른쪽 다리
    final rightLegRect = Rect.fromLTWH(
      width * 0.5 + torsoWidth / 2 - legWidth - width * 0.02,
      height * 0.56,
      legWidth,
      legHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(rightLegRect, const Radius.circular(15)));

    return path;
  }

  static Path _getHalfBodyPath(Size size) {
    final path = Path();
    final width = size.width;
    final height = size.height;

    // 머리
    final headRadius = width * 0.12;
    final headCenter = Offset(width * 0.5, height * 0.35);
    path.addOval(Rect.fromCircle(center: headCenter, radius: headRadius));

    // 몸통 (더 크고 화면 아래로 짤리도록)
    final torsoWidth = width * 0.45;
    final torsoHeight = height * 0.4;
    final torsoRect = Rect.fromCenter(
      center: Offset(width * 0.5, height * 0.7),
      width: torsoWidth,
      height: torsoHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(torsoRect, const Radius.circular(40)));

    // 팔 (몸통에 붙어서 살짝만 보이게)
    final armWidth = width * 0.1;
    final leftArmRect = Rect.fromLTWH(
      width * 0.5 - torsoWidth / 2 - armWidth * 0.6,
      height * 0.55,
      armWidth,
      height * 0.3,
    );
    path.addRRect(RRect.fromRectAndRadius(leftArmRect, const Radius.circular(20)));

    final rightArmRect = Rect.fromLTWH(
      width * 0.5 + torsoWidth / 2 - armWidth * 0.4,
      height * 0.55,
      armWidth,
      height * 0.3,
    );
    path.addRRect(RRect.fromRectAndRadius(rightArmRect, const Radius.circular(20)));

    return path;
  }

  static Path _getSittingPath(Size size) {
    final path = Path();
    final width = size.width;
    final height = size.height;

    // 머리
    final headRadius = width * 0.08;
    final headCenter = Offset(width * 0.5, height * 0.35);
    path.addOval(Rect.fromCircle(center: headCenter, radius: headRadius));

    // 몸통
    final torsoWidth = width * 0.22;
    final torsoHeight = height * 0.25;
    final torsoRect = Rect.fromCenter(
      center: Offset(width * 0.5, height * 0.55),
      width: torsoWidth,
      height: torsoHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(torsoRect, const Radius.circular(20)));

    // 허벅지 (앉은 형태 - 가로로 뻗은 다리)
    final thighWidth = width * 0.3;
    final thighHeight = height * 0.1;
    final thighRect = Rect.fromLTWH(
      width * 0.5 - torsoWidth / 2,
      height * 0.62,
      thighWidth,
      thighHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(thighRect, const Radius.circular(15)));

    // 종아리 (아래로 뻗은 다리)
    final calfWidth = width * 0.08;
    final calfHeight = height * 0.2;
    final calfRect = Rect.fromLTWH(
      width * 0.5 - torsoWidth / 2 + thighWidth - calfWidth,
      height * 0.65,
      calfWidth,
      calfHeight,
    );
    path.addRRect(RRect.fromRectAndRadius(calfRect, const Radius.circular(15)));

    // 팔 (무릎에 얹은 형태)
    final armPath = Path();
    armPath.moveTo(width * 0.5 - torsoWidth / 2, height * 0.45);
    armPath.lineTo(width * 0.5 + torsoWidth / 2 + 10, height * 0.62);
    
    // 두꺼운 선을 위해 Stroke 모양을 추가
    // 여기서는 간단히 팔을 RRect로 기울여서 그리기는 어려우니 비슷한 크기의 원들을 추가
    final leftArmRect = Rect.fromLTWH(
      width * 0.5 - torsoWidth / 2 - 10,
      height * 0.45,
      width * 0.06,
      height * 0.18,
    );
    path.addRRect(RRect.fromRectAndRadius(leftArmRect, const Radius.circular(10)));
    
    return path;
  }
}
