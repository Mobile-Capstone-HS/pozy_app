// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:ultralytics_yolo/config/channel_config.dart';
import 'package:ultralytics_yolo/models/yolo_task.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/utils/logger.dart';

/// Controller for managing YOLO detection settings and camera controls.
class YOLOViewController {
  MethodChannel? _methodChannel;
  int? _viewId;
  double _confidenceThreshold = 0.5;
  double _iouThreshold = 0.45;
  int _numItemsThreshold = 30;

  StreamSubscription<dynamic>? _metricsSubscription;
  void Function(Map<String, double>)? onImageMetrics;

  double get confidenceThreshold => _confidenceThreshold;
  double get iouThreshold => _iouThreshold;
  int get numItemsThreshold => _numItemsThreshold;
  bool get isInitialized => _methodChannel != null && _viewId != null;

  YOLOViewController();

  void init(MethodChannel methodChannel, int viewId, String viewUniqueId) {
    _methodChannel = methodChannel;
    _viewId = viewId;
    _applyThresholds();
    _subscribeToMetrics(viewUniqueId);
  }

  void _subscribeToMetrics(String viewUniqueId) {
    final channel = ChannelConfig.createImageMetricsChannel(viewUniqueId);
    _metricsSubscription = channel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map && onImageMetrics != null) {
          final metrics = <String, double>{};
          event.forEach((k, v) {
            if (k is String && v is num) metrics[k] = v.toDouble();
          });
          onImageMetrics!(metrics);
        }
      },
      onError: (e) => logInfo('imageMetrics stream error: $e'),
    );
  }

  void dispose() {
    _metricsSubscription?.cancel();
    _metricsSubscription = null;
  }

  Future<void> _applyThresholds() async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setThresholds', {
          'confidenceThreshold': _confidenceThreshold,
          'iouThreshold': _iouThreshold,
          'numItemsThreshold': _numItemsThreshold,
        });
      } catch (e) {
        logInfo('Error applying thresholds: $e');
      }
    }
  }

  Future<void> setConfidenceThreshold(double threshold) async {
    _confidenceThreshold = threshold.clamp(0.0, 1.0);
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setConfidenceThreshold', {
          'threshold': _confidenceThreshold,
        });
      } catch (e) {
        logInfo('Error setting confidence threshold: $e');
      }
    }
  }

  Future<void> setIoUThreshold(double threshold) async {
    _iouThreshold = threshold.clamp(0.0, 1.0);
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setIoUThreshold', {
          'threshold': _iouThreshold,
        });
      } catch (e) {
        logInfo('Error setting IoU threshold: $e');
      }
    }
  }

  Future<void> setNumItemsThreshold(int numItems) async {
    _numItemsThreshold = numItems.clamp(1, 100);
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setNumItemsThreshold', {
          'numItems': _numItemsThreshold,
        });
      } catch (e) {
        logInfo('Error setting num items threshold: $e');
      }
    }
  }

  Future<void> setThresholds({
    double? confidenceThreshold,
    double? iouThreshold,
    int? numItemsThreshold,
  }) async {
    if (confidenceThreshold != null) {
      _confidenceThreshold = confidenceThreshold.clamp(0.0, 1.0);
    }
    if (iouThreshold != null) {
      _iouThreshold = iouThreshold.clamp(0.0, 1.0);
    }
    if (numItemsThreshold != null) {
      _numItemsThreshold = numItemsThreshold.clamp(1, 100);
    }

    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setThresholds', {
          'confidenceThreshold': _confidenceThreshold,
          'iouThreshold': _iouThreshold,
          'numItemsThreshold': _numItemsThreshold,
        });
      } catch (e) {
        logInfo('Error setting thresholds: $e');
      }
    }
  }

  Future<void> switchCamera() async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('switchCamera');
      } catch (e) {
        logInfo('Error switching camera: $e');
      }
    }
  }

  Future<void> zoomIn() async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('zoomIn');
      } catch (e) {
        logInfo('Error zooming in: $e');
      }
    }
  }

  Future<void> zoomOut() async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('zoomOut');
      } catch (e) {
        logInfo('Error zooming out: $e');
      }
    }
  }

  Future<void> setZoomLevel(double zoomLevel) async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setZoomLevel', {
          'zoomLevel': zoomLevel,
        });
      } catch (e) {
        logInfo('Error setting zoom level: $e');
      }
    }
  }

  Future<void> switchModel(String modelPath, YOLOTask task) async {
    if (_methodChannel != null && _viewId != null) {
      await _methodChannel!.invokeMethod('setModel', {
        'modelPath': modelPath,
        'task': task.name,
      });
    }
  }

  Future<void> setStreamingConfig(YOLOStreamingConfig config) async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setStreamingConfig', {
          'includeDetections': config.includeDetections,
          'includeClassifications': config.includeClassifications,
          'includeProcessingTimeMs': config.includeProcessingTimeMs,
          'includeFps': config.includeFps,
          'includeMasks': config.includeMasks,
          'includePoses': config.includePoses,
          'includeOBB': config.includeOBB,
          'includeOriginalImage': config.includeOriginalImage,
          'maxFPS': config.maxFPS,
          'throttleIntervalMs': config.throttleInterval?.inMilliseconds,
          'inferenceFrequency': config.inferenceFrequency,
          'skipFrames': config.skipFrames,
        });
      } catch (e) {
        logInfo('Error setting streaming config: $e');
      }
    }
  }

  Future<void> stop() async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('stop');
      } catch (e) {
        logInfo('Error stopping: $e');
      }
    }
  }

  Future<void> restartCamera() async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('restartCamera');
      } catch (e) {
        logInfo('Error restarting camera: $e');
      }
    }
  }

  Future<void> setShowUIControls(bool show) async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setShowUIControls', {'show': show});
      } catch (e) {
        logInfo('Error setting UI controls: $e');
      }
    }
  }

  Future<void> setShowOverlays(bool show) async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setShowOverlays', {'show': show});
      } catch (e) {
        logInfo('Error setting overlay visibility: $e');
      }
    }
  }

  Future<void> setFocusPoint(double x, double y) async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setFocusPoint', {'x': x, 'y': y});
      } catch (_) {}
    }
  }

  Future<void> setTorchMode(bool enabled) async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setTorchMode', {'enabled': enabled});
      } catch (_) {}
    }
  }

  Future<Uint8List?> captureFrame() async {
    if (_methodChannel != null) {
      try {
        final result = await _methodChannel!.invokeMethod('captureFrame');
        return result is Uint8List ? result : null;
      } catch (e) {
        logInfo('Error capturing frame: $e');
        return null;
      }
    }
    return null;
  }

  /// 실제 카메라가 지원하는 최소 줌 비율 반환.
  /// 초광각 렌즈 탑재 기기는 1.0 미만 (예: 0.5, 0.6).
  /// 지원 안 하면 1.0 반환.
  Future<double> getMinZoomLevel() async {
    if (_methodChannel != null) {
      try {
        final result = await _methodChannel!.invokeMethod<double>('getMinZoomLevel');
        return result ?? 1.0;
      } catch (e) {
        logInfo('Error getting min zoom level: $e');
      }
    }
    return 1.0;
  }

  /// 풀해상도 사진 촬영 (ImageCapture use case).
  /// 갤러리 저장용 — captureFrame()보다 화질이 크게 높음.
  Future<void> setLockedRoi({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) async {
    if (_methodChannel != null) {
      try {
        await _methodChannel!.invokeMethod('setLockedRoi', {
          'left': left,
          'top': top,
          'right': right,
          'bottom': bottom,
        });
      } catch (e) {
        logInfo('Error setting locked roi: $e');
      }
    }
  }

  Future<Uint8List?> captureHighRes() async {
    if (_methodChannel != null) {
      try {
        final result = await _methodChannel!.invokeMethod('captureHighRes');
        return result is Uint8List ? result : null;
      } catch (e) {
        logInfo('Error capturing high-res photo: $e');
        return null;
      }
    }
    return null;
  }
}
