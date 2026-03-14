import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pose_camera_app/golden.dart';

void main() {
  group('MathStabilizer Tests', () {
    test('Initialization', () {
      final stabilizer = MathStabilizer(alpha: 0.25, stickyMarginRatio: 0.08);
      expect(stabilizer.smoothedX, isNull);
      expect(stabilizer.smoothedY, isNull);
      expect(stabilizer.currentBestPoint, isNull);
    });

    test('First update sets exact value', () {
      final stabilizer = MathStabilizer(alpha: 0.25);
      final pt = stabilizer.update(100.0, 200.0);
      expect(pt.x, 100);
      expect(pt.y, 200);
      expect(stabilizer.smoothedX, 100.0);
      expect(stabilizer.smoothedY, 200.0);
    });

    test('Second update applies alpha blending', () {
      final stabilizer = MathStabilizer(alpha: 0.5);
      stabilizer.update(100.0, 200.0);
      // New value: 100 * 0.5 + 200 * 0.5 = 150
      final pt = stabilizer.update(200.0, 300.0);
      expect(pt.x, 150);
      expect(pt.y, 250);
    });

    test('getStickyTarget finds nearest point initially', () {
      final stabilizer = MathStabilizer();
      stabilizer.update(100.0, 100.0);

      final intersections = [
        const Point<int>(0, 0),
        const Point<int>(100, 105), // Closest
        const Point<int>(200, 200),
      ];

      final targetInfo = stabilizer.getStickyTarget(intersections, 1000);
      expect(targetInfo['point'], const Point<int>(100, 105));
      expect(targetInfo['distance'], closeTo(5.0, 0.1));
    });
  });

  group('GoldenCoach Tests', () {
    test('calculateGrid generates correct intersections', () {
      final coach = GoldenCoach();
      coach.calculateGrid(1000, 1000);

      expect(coach.intersections.length, 4);
      // phi = 1.6180339887
      // ratio = 1 / phi ≈ 0.618
      // invRatio = 1 - ratio ≈ 0.382

      final expectedInv = (1000 * 0.3819660113).toInt(); // ~381
      final expectedRat = (1000 * 0.6180339887).toInt(); // ~618

      expect(coach.intersections[0], Point<int>(expectedInv, expectedInv));
      expect(coach.intersections[1], Point<int>(expectedRat, expectedInv));
      expect(coach.intersections[2], Point<int>(expectedInv, expectedRat));
      expect(coach.intersections[3], Point<int>(expectedRat, expectedRat));
    });

    test('isPerfect returns true when distance is small', () {
      final coach = GoldenCoach();
      coach.calculateGrid(1000, 1000); // threshold will be 1000 * 0.1 = 100

      expect(coach.isPerfect(99.0), isTrue);
      expect(coach.isPerfect(101.0), isFalse);
    });
  });
}
