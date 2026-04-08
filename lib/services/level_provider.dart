/// Base interface for horizon-level / tilt-angle providers.
///
/// Decouple the painter and camera screen from any specific sensor
/// implementation. To add real IMU support, create a subclass (e.g.
/// [SensorLevelProvider]) and inject it into [_CameraScreenState].
///
/// ### Example future implementation
/// ```dart
/// class SensorLevelProvider extends LevelProviderBase {
///   double _tilt = 0.0;
///   StreamSubscription<AccelerometerEvent>? _sub;
///
///   void start() {
///     _sub = accelerometerEventStream().listen((e) {
///       _tilt = math.atan2(e.x, e.z) - math.pi / 2;
///     });
///   }
///   void stop() => _sub?.cancel();
///
///   @override
///   double get tiltAngle => _tilt;
/// }
/// ```
abstract class LevelProviderBase {
  const LevelProviderBase();

  /// Current roll / tilt angle in radians.
  /// Positive = clockwise, negative = counter-clockwise.
  double get tiltAngle;

  /// True when [tiltAngle] is within [toleranceRad] of zero.
  bool isLevel({double toleranceRad = 0.05}) => tiltAngle.abs() < toleranceRad;
}

/// Stub implementation — always reports level (0.0 rad).
///
/// Used in production until a real [LevelProviderBase] subclass is injected.
class StubLevelProvider extends LevelProviderBase {
  const StubLevelProvider();

  @override
  double get tiltAngle => 0.0;
}
