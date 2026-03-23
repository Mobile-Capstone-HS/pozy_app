import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pose_camera_app/core/services/math_stabilizer.dart';
import 'package:pose_camera_app/features/composition/golden_ratio_policy.dart';

void main() {
  group('MathStabilizer', () {
    test('first update stores exact point', () {
      final stabilizer = MathStabilizer(alpha: 0.25);
      final pt = stabilizer.update(const Offset(100, 200));

      expect(pt.dx, 100);
      expect(pt.dy, 200);
    });

    test('second update applies smoothing', () {
      final stabilizer = MathStabilizer(alpha: 0.5);
      stabilizer.update(const Offset(100, 200));
      final pt = stabilizer.update(const Offset(200, 300));

      expect(pt.dx, 150);
      expect(pt.dy, 250);
    });

    test('findNearestTarget returns closest target', () {
      final stabilizer = MathStabilizer();
      final target = stabilizer.findNearestTarget(
        const Offset(100, 100),
        const [Offset(0, 0), Offset(100, 105), Offset(200, 200)],
      );

      expect(target, const Offset(100, 105));
    });
  });

  group('GoldenRatioPolicy', () {
    test('getTargets creates 4 intersections', () {
      final policy = GoldenRatioPolicy();
      final targets = policy.getTargets(const Size(1000, 1000));

      expect(targets.length, 4);
      expect(targets.first.dx, closeTo(381.97, 0.2));
      expect(targets.first.dy, closeTo(381.97, 0.2));
      expect(targets[3].dx, closeTo(618.03, 0.2));
      expect(targets[3].dy, closeTo(618.03, 0.2));
    });

    test('isPerfect uses 10 percent threshold', () {
      final policy = GoldenRatioPolicy();

      expect(policy.isPerfect(99, const Size(1000, 1000)), isTrue);
      expect(policy.isPerfect(101, const Size(1000, 1000)), isFalse);
    });
  });
}
