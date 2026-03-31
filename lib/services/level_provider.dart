/// Provides a horizon level / tilt angle for the level guide overlay.
///
/// Current implementation is a placeholder that always reports level (0.0 rad).
///
/// ### Future integration point
/// Replace the [tiltAngle] getter with a real IMU sensor subscription.
/// For example, use the `sensors_plus` package:
///   ```dart
///   accelerometerEvents.listen((event) { ... });
///   ```
/// and convert the accelerometer vector to a roll angle.
class LevelProvider {
  const LevelProvider();

  /// Tilt angle in radians. Positive = clockwise, negative = counter-clockwise.
  double get tiltAngle => 0.0;

  /// True when the device is within [toleranceRad] of level.
  bool isLevel({double toleranceRad = 0.05}) => tiltAngle.abs() < toleranceRad;
}
