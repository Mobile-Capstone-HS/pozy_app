import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

import '../../../../config/experimental_features.dart';

class TfliteInterpreterManager {
  TfliteInterpreterManager._();

  static final TfliteInterpreterManager instance = TfliteInterpreterManager._();

  final Map<String, Future<_InterpreterHandle>> _cache = {};

  Future<Interpreter> getInterpreter(
    String assetPath, {
    bool useFlexDelegate = false,
    String? modelId,
  }) async {
    final handle = await _getHandle(
      assetPath,
      useFlexDelegate: useFlexDelegate,
      modelId: modelId,
    );
    return handle.interpreter;
  }

  Future<T> withInterpreter<T>(
    String assetPath, {
    bool useFlexDelegate = false,
    String? modelId,
    required Future<T> Function(
      Interpreter interpreter,
      TfliteModelDescriptor descriptor,
    )
    action,
  }) async {
    if (ExperimentalFeatures.useFreshInterpreterPerImageForDebug) {
      final handle = await _createHandle(
        assetPath: assetPath,
        useFlexDelegate: useFlexDelegate,
        modelId: modelId,
      );
      try {
        return await handle.synchronized(action);
      } finally {
        await handle.close();
      }
    }

    final handle = await _getHandle(
      assetPath,
      useFlexDelegate: useFlexDelegate,
      modelId: modelId,
    );
    return handle.synchronized(action);
  }

  Future<_InterpreterHandle> _getHandle(
    String assetPath, {
    required bool useFlexDelegate,
    String? modelId,
  }) async {
    final plan = _AcutTfliteExperimentPlan.resolve(
      modelId: modelId,
      assetPath: assetPath,
      useFlexDelegate: useFlexDelegate,
    );
    final cacheKey = plan.cacheKey;
    final existing = _cache[cacheKey];
    if (existing != null) {
      return existing;
    }

    final pending = _createHandle(
      assetPath: assetPath,
      useFlexDelegate: useFlexDelegate,
      modelId: modelId,
      initialPlan: plan,
    );
    _cache[cacheKey] = pending;
    try {
      final handle = await pending;
      if (handle.cacheKey != cacheKey && identical(_cache[cacheKey], pending)) {
        _cache.remove(cacheKey);
      }
      return handle;
    } catch (_) {
      if (identical(_cache[cacheKey], pending)) {
        _cache.remove(cacheKey);
      }
      rethrow;
    }
  }

  Future<_InterpreterHandle> _createHandle({
    required String assetPath,
    required bool useFlexDelegate,
    String? modelId,
    _AcutTfliteExperimentPlan? initialPlan,
  }) async {
    final plan =
        initialPlan ??
        _AcutTfliteExperimentPlan.resolve(
          modelId: modelId,
          assetPath: assetPath,
          useFlexDelegate: useFlexDelegate,
        );

    if (plan.delegateKind == _AcutDelegateKind.nnapi) {
      return _handleUnavailableDelegatePlan(
        plan: plan,
        reason: 'nnapi_api_unavailable',
      );
    }

    if (plan.delegateKind == _AcutDelegateKind.gpu && !Platform.isAndroid) {
      return _handleUnavailableDelegatePlan(
        plan: plan,
        reason: 'gpu_delegate_android_only',
      );
    }

    return _createHandleWithPlan(plan);
  }

  Future<_InterpreterHandle> _handleUnavailableDelegatePlan({
    required _AcutTfliteExperimentPlan plan,
    required String reason,
  }) async {
    if (!ExperimentalFeatures.acutTfliteAllowFallback) {
      throw UnsupportedError(reason);
    }

    final fallbackPlan = plan.fallbackCpu(reason);
    return _createHandleWithPlan(fallbackPlan);
  }

  Future<_InterpreterHandle> _createHandleWithPlan(
    _AcutTfliteExperimentPlan plan,
  ) async {
    final delegates = <Delegate>[];
    Interpreter? interpreter;

    try {
      final options = InterpreterOptions()..threads = plan.numThreads;
      var createDelegateMs = 0;
      var createDelegateUs = 0;

      if (plan.useFlexDelegate) {
        if (Platform.isAndroid) {
          delegates.add(await FlexDelegate.create());
        } else {
          delegates.add(FlexDelegate());
        }
        options.addDelegate(delegates.last);
      }

      if (plan.delegateKind == _AcutDelegateKind.gpu) {
        final delegateSw = Stopwatch()..start();
        final acceleratorDelegate = GpuDelegateV2();
        delegateSw.stop();
        createDelegateMs = delegateSw.elapsedMilliseconds;
        createDelegateUs = delegateSw.elapsedMicroseconds;
        delegates.add(acceleratorDelegate);
        options.addDelegate(acceleratorDelegate);
      }

      debugPrint(
        '[TfliteInterpreterManager] Loading ${plan.assetPath} '
        '(flex=${plan.useFlexDelegate} model=${plan.modelId ?? '-'})',
      );
      final interpreterSw = Stopwatch()..start();
      interpreter = await Interpreter.fromAsset(
        plan.assetPath,
        options: options,
      );
      interpreter.allocateTensors();
      interpreterSw.stop();
      _logDelegateTiming(
        plan: plan,
        createDelegateMs: createDelegateMs,
        createDelegateUs: createDelegateUs,
        createInterpreterMs: interpreterSw.elapsedMilliseconds,
        createInterpreterUs: interpreterSw.elapsedMicroseconds,
        fallback: plan.fallback,
        fallbackReason: plan.fallbackReason,
      );
      debugPrint(
        '[TfliteInterpreterManager] Loaded ${plan.assetPath} '
        '(flex=${plan.useFlexDelegate} model=${plan.modelId ?? '-'})',
      );
      final descriptor = _readDescriptor(
        interpreter: interpreter,
        assetPath: plan.assetPath,
      );
      debugPrint(
        '[TfliteInterpreterManager] Loaded ${plan.assetPath} '
        'inputShapes=${descriptor.inputShapes} '
        'outputShapes=${descriptor.outputShapes} '
        'inputTypes=${descriptor.inputTypes} '
        'outputTypes=${descriptor.outputTypes} '
        'signatures=${descriptor.signatureKeys}',
      );

      return _InterpreterHandle(
        interpreter: interpreter,
        delegates: delegates,
        descriptor: descriptor,
        cacheKey: plan.cacheKey,
      );
    } catch (error) {
      interpreter?.close();
      for (final delegate in delegates.reversed) {
        delegate.delete();
      }
      if (plan.delegateKind != _AcutDelegateKind.none &&
          !plan.fallback &&
          ExperimentalFeatures.acutTfliteAllowFallback) {
        final fallbackPlan = plan.fallbackCpu(error);
        return _createHandleWithPlan(fallbackPlan);
      }
      throw Exception(
        'Failed to initialize interpreter for ${plan.assetPath} '
        '(flex=${plan.useFlexDelegate} model=${plan.modelId ?? '-'}): $error',
      );
    }
  }

  Future<void> closeAll() async {
    final handles = await Future.wait(_cache.values);
    for (final handle in handles) {
      await handle.close();
    }
    _cache.clear();
  }

  Future<void> evict(
    String assetPath, {
    bool useFlexDelegate = false,
    String? modelId,
  }) async {
    final plan = _AcutTfliteExperimentPlan.resolve(
      modelId: modelId,
      assetPath: assetPath,
      useFlexDelegate: useFlexDelegate,
    );
    final cacheKey = plan.cacheKey;
    final pending = _cache.remove(cacheKey);
    if (pending != null) {
      try {
        final handle = await pending;
        await handle.close();
      } catch (_) {}
    }
  }

  TfliteModelDescriptor _readDescriptor({
    required Interpreter interpreter,
    required String assetPath,
  }) {
    final inputTensors = interpreter.getInputTensors();
    final outputTensors = interpreter.getOutputTensors();
    final signatures = <String, TfliteSignatureDescriptor>{};

    for (final signatureKey in interpreter.signatureKeys) {
      final runner = interpreter.getSignatureRunner(signatureKey);
      try {
        final inputNames = runner.inputNames;
        final outputNames = runner.outputNames;
        runner.allocateTensors();
        signatures[signatureKey] = TfliteSignatureDescriptor(
          key: signatureKey,
          inputNames: inputNames,
          outputNames: outputNames,
          inputTensors: {
            for (final name in inputNames)
              name: TfliteTensorDescriptor.fromTensor(
                runner.getInputTensor(name),
              ),
          },
          outputTensors: {
            for (final name in outputNames)
              name: TfliteTensorDescriptor.fromTensor(
                runner.getOutputTensor(name),
              ),
          },
        );
      } finally {
        runner.close();
      }
    }

    return TfliteModelDescriptor(
      modelName: assetPath.split('/').last,
      assetPath: assetPath,
      inputTensors: inputTensors
          .map(TfliteTensorDescriptor.fromTensor)
          .toList(growable: false),
      outputTensors: outputTensors
          .map(TfliteTensorDescriptor.fromTensor)
          .toList(growable: false),
      signatures: signatures,
    );
  }
}

class _InterpreterHandle {
  final Interpreter interpreter;
  final List<Delegate> delegates;
  final TfliteModelDescriptor descriptor;
  final String cacheKey;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  _InterpreterHandle({
    required this.interpreter,
    required this.delegates,
    required this.descriptor,
    required this.cacheKey,
  });

  Future<T> synchronized<T>(
    Future<T> Function(
      Interpreter interpreter,
      TfliteModelDescriptor descriptor,
    )
    action,
  ) {
    final previous = _tail;
    late final Future<T> next;
    next = previous.then((_) {
      if (_closed) {
        throw StateError(
          'Interpreter is already closed: ${descriptor.assetPath}',
        );
      }
      return action(interpreter, descriptor);
    });
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<void> close() {
    if (_closed) {
      return Future<void>.value();
    }
    return synchronized((interpreter, descriptor) async {
      if (_closed) {
        return;
      }
      _closed = true;
      interpreter.close();
      for (final delegate in delegates.reversed) {
        delegate.delete();
      }
    });
  }
}

enum _AcutDelegateKind { none, nnapi, gpu }

class _AcutTfliteExperimentPlan {
  static const _defaultThreads = 2;
  static const _targetRgnet = 'rgnet_pil_resize_aadb';
  static const _allowedModes = <String>{
    'cpu_baseline',
    'threads_rgnet',
    'nnapi_rgnet',
    'gpu_rgnet',
  };

  final String assetPath;
  final bool useFlexDelegate;
  final String? modelId;
  final String requestedMode;
  final String appliedMode;
  final _AcutDelegateKind delegateKind;
  final int numThreads;
  final bool targetMatched;
  final bool fallback;
  final String? fallbackReason;

  const _AcutTfliteExperimentPlan({
    required this.assetPath,
    required this.useFlexDelegate,
    required this.modelId,
    required this.requestedMode,
    required this.appliedMode,
    required this.delegateKind,
    required this.numThreads,
    required this.targetMatched,
    this.fallback = false,
    this.fallbackReason,
  });

  factory _AcutTfliteExperimentPlan.resolve({
    required String assetPath,
    required bool useFlexDelegate,
    required String? modelId,
  }) {
    final configuredMode = ExperimentalFeatures.acutTfliteExperimentMode;
    final requestedMode = _allowedModes.contains(configuredMode)
        ? configuredMode
        : 'cpu_baseline';
    final targetMatched = _targetsModel(requestedMode, modelId);

    if (!targetMatched) {
      return _AcutTfliteExperimentPlan(
        assetPath: assetPath,
        useFlexDelegate: useFlexDelegate,
        modelId: modelId,
        requestedMode: requestedMode,
        appliedMode: 'cpu',
        delegateKind: _AcutDelegateKind.none,
        numThreads: _defaultThreads,
        targetMatched: false,
      );
    }

    if (requestedMode.startsWith('threads_')) {
      return _AcutTfliteExperimentPlan(
        assetPath: assetPath,
        useFlexDelegate: useFlexDelegate,
        modelId: modelId,
        requestedMode: requestedMode,
        appliedMode: 'threads',
        delegateKind: _AcutDelegateKind.none,
        numThreads: ExperimentalFeatures.acutTfliteNumThreads,
        targetMatched: true,
      );
    }

    if (requestedMode.startsWith('nnapi_')) {
      return _AcutTfliteExperimentPlan(
        assetPath: assetPath,
        useFlexDelegate: useFlexDelegate,
        modelId: modelId,
        requestedMode: requestedMode,
        appliedMode: 'nnapi',
        delegateKind: _AcutDelegateKind.nnapi,
        numThreads: _defaultThreads,
        targetMatched: true,
      );
    }

    if (requestedMode.startsWith('gpu_')) {
      return _AcutTfliteExperimentPlan(
        assetPath: assetPath,
        useFlexDelegate: useFlexDelegate,
        modelId: modelId,
        requestedMode: requestedMode,
        appliedMode: 'gpu',
        delegateKind: _AcutDelegateKind.gpu,
        numThreads: _defaultThreads,
        targetMatched: true,
      );
    }

    return _AcutTfliteExperimentPlan(
      assetPath: assetPath,
      useFlexDelegate: useFlexDelegate,
      modelId: modelId,
      requestedMode: requestedMode,
      appliedMode: 'cpu',
      delegateKind: _AcutDelegateKind.none,
      numThreads: _defaultThreads,
      targetMatched: false,
    );
  }

  _AcutTfliteExperimentPlan fallbackCpu(Object? reason) {
    return _AcutTfliteExperimentPlan(
      assetPath: assetPath,
      useFlexDelegate: useFlexDelegate,
      modelId: modelId,
      requestedMode: requestedMode,
      appliedMode: 'fallback_cpu',
      delegateKind: _AcutDelegateKind.none,
      numThreads: _defaultThreads,
      targetMatched: targetMatched,
      fallback: true,
      fallbackReason: reason?.toString(),
    );
  }

  String get delegateLabel {
    return switch (delegateKind) {
      _AcutDelegateKind.none => 'none',
      _AcutDelegateKind.nnapi => 'nnapi',
      _AcutDelegateKind.gpu => 'gpu',
    };
  }

  String get assetName => assetPath.split('/').last;

  String get cacheKey {
    return '$assetPath|flex:$useFlexDelegate|model:${modelId ?? '-'}|'
        'mode:$appliedMode|delegate:$delegateLabel|threads:$numThreads';
  }

  String get cacheKeySummary {
    return '$assetName|flex:$useFlexDelegate|model:${modelId ?? '-'}|'
        'mode:$appliedMode|delegate:$delegateLabel|threads:$numThreads';
  }

  static bool _targetsModel(String mode, String? modelId) {
    return switch (modelId) {
      _targetRgnet => mode.endsWith('_rgnet'),
      _ => false,
    };
  }
}

class TfliteModelDescriptor {
  final String modelName;
  final String assetPath;
  final List<TfliteTensorDescriptor> inputTensors;
  final List<TfliteTensorDescriptor> outputTensors;
  final Map<String, TfliteSignatureDescriptor> signatures;

  const TfliteModelDescriptor({
    required this.modelName,
    required this.assetPath,
    required this.inputTensors,
    required this.outputTensors,
    required this.signatures,
  });

  List<List<int>> get inputShapes =>
      inputTensors.map((tensor) => tensor.shape).toList(growable: false);

  List<List<int>> get outputShapes =>
      outputTensors.map((tensor) => tensor.shape).toList(growable: false);

  List<String> get inputTypes =>
      inputTensors.map((tensor) => tensor.type).toList(growable: false);

  List<String> get outputTypes =>
      outputTensors.map((tensor) => tensor.type).toList(growable: false);

  List<String> get signatureKeys => signatures.keys.toList(growable: false);
}

class TfliteSignatureDescriptor {
  final String key;
  final List<String> inputNames;
  final List<String> outputNames;
  final Map<String, TfliteTensorDescriptor> inputTensors;
  final Map<String, TfliteTensorDescriptor> outputTensors;

  const TfliteSignatureDescriptor({
    required this.key,
    required this.inputNames,
    required this.outputNames,
    required this.inputTensors,
    required this.outputTensors,
  });

  TfliteTensorDescriptor input(String name) {
    final tensor = inputTensors[name];
    if (tensor == null) {
      throw ArgumentError('Unknown signature input "$name" for $key.');
    }
    return tensor;
  }

  TfliteTensorDescriptor output(String name) {
    final tensor = outputTensors[name];
    if (tensor == null) {
      throw ArgumentError('Unknown signature output "$name" for $key.');
    }
    return tensor;
  }
}

class TfliteTensorDescriptor {
  final String name;
  final String type;
  final List<int> shape;
  final int byteCount;

  const TfliteTensorDescriptor({
    required this.name,
    required this.type,
    required this.shape,
    required this.byteCount,
  });

  factory TfliteTensorDescriptor.fromTensor(Tensor tensor) {
    final shape = List<int>.unmodifiable(tensor.shape);
    return TfliteTensorDescriptor(
      name: tensor.name,
      type: tensor.type.name,
      shape: shape,
      byteCount: _safeTensorByteCount(tensor, shape),
    );
  }

  int get elementCount => byteCount <= 0 ? 0 : byteCount ~/ 4;

  static int _safeTensorByteCount(Tensor tensor, List<int> shape) {
    try {
      return tensor.numBytes();
    } catch (error) {
      if (shape.isNotEmpty && shape.every((dimension) => dimension > 0)) {
        final elementCount = shape.fold<int>(
          1,
          (product, dimension) => product * dimension,
        );
        return elementCount * 4;
      }
      debugPrint(
        '[TfliteInterpreterManager] tensor_num_bytes_unavailable '
        'name=${tensor.name} shape=$shape error=$error',
      );
      return -1;
    }
  }
}

void _logDelegateTiming({
  required _AcutTfliteExperimentPlan plan,
  required int createDelegateMs,
  required int createDelegateUs,
  required int createInterpreterMs,
  required int createInterpreterUs,
  required bool fallback,
  Object? fallbackReason,
}) {
  if (!ExperimentalFeatures.enableAcutDelegateTimingDebug) {
    return;
  }

  debugPrint(
    '[AcutDelegateTiming] '
    'model=${plan.modelId ?? '-'} '
    'asset=${plan.assetName} '
    'requestedMode=${plan.requestedMode} '
    'appliedMode=${plan.appliedMode} '
    'delegate=${plan.delegateLabel} '
    'threads=${plan.numThreads} '
    'targetMatched=${plan.targetMatched} '
    'createDelegateMs=$createDelegateMs '
    'createDelegateUs=$createDelegateUs '
    'createInterpreterMs=$createInterpreterMs '
    'createInterpreterUs=$createInterpreterUs '
    'fallback=$fallback '
    'fallbackReason=${_quote(_summarizeError(fallbackReason))} '
    'cacheKey=${_quote(plan.cacheKeySummary)}',
  );
}

String _summarizeError(Object? error) {
  if (error == null) {
    return 'none';
  }
  final message = error.toString().replaceAll('\n', ' ');
  return message.length <= 160 ? message : '${message.substring(0, 160)}...';
}

String _quote(String value) {
  return '"${value.replaceAll('"', r'\"')}"';
}
