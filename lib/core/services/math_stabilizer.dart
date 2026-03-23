import 'dart:ui';

class StickyTargetResult {
  const StickyTargetResult({required this.point, required this.distance});

  final Offset? point;
  final double distance;
}

class MathStabilizer {
  MathStabilizer({this.alpha = 0.25, this.stickyMarginRatio = 0.08});

  final double alpha;
  final double stickyMarginRatio;

  Offset? _smoothedPosition;
  Offset? _currentBestTarget;

  Offset update(Offset raw) {
    if (_smoothedPosition == null) {
      _smoothedPosition = raw;
    } else {
      _smoothedPosition = Offset(
        _smoothedPosition!.dx * (1 - alpha) + raw.dx * alpha,
        _smoothedPosition!.dy * (1 - alpha) + raw.dy * alpha,
      );
    }
    return _smoothedPosition!;
  }

  StickyTargetResult getStickyTarget(List<Offset> targets, double screenWidth) {
    if (_smoothedPosition == null || targets.isEmpty) {
      return const StickyTargetResult(point: null, distance: double.infinity);
    }

    if (_currentBestTarget == null) {
      _currentBestTarget = _findNearestTarget(_smoothedPosition!, targets);
    } else {
      final currentDistance = (_smoothedPosition! - _currentBestTarget!).distance;
      final stickyMargin = screenWidth * stickyMarginRatio;
      var candidate = _currentBestTarget!;
      var bestDistance = currentDistance;

      for (final target in targets) {
        final newDistance = (_smoothedPosition! - target).distance;
        if (newDistance < bestDistance - stickyMargin) {
          candidate = target;
          bestDistance = newDistance;
        }
      }

      _currentBestTarget = candidate;
    }

    return StickyTargetResult(
      point: _currentBestTarget,
      distance: (_smoothedPosition! - _currentBestTarget!).distance,
    );
  }

  Offset findNearestTarget(Offset source, List<Offset> targets) {
    return _findNearestTarget(source, targets);
  }

  void reset() {
    _smoothedPosition = null;
    _currentBestTarget = null;
  }

  Offset _findNearestTarget(Offset source, List<Offset> targets) {
    Offset best = targets.first;
    double minDistance = (source - targets.first).distance;

    for (final target in targets.skip(1)) {
      final distance = (source - target).distance;
      if (distance < minDistance) {
        minDistance = distance;
        best = target;
      }
    }

    return best;
  }
}
