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
  }) async {
    final handle = await _getHandle(
      assetPath,
      useFlexDelegate: useFlexDelegate,
    );
    return handle.interpreter;
  }

  Future<T> withInterpreter<T>(
    String assetPath, {
    bool useFlexDelegate = false,
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
    );
    return handle.synchronized(action);
  }

  Future<_InterpreterHandle> _getHandle(
    String assetPath, {
    required bool useFlexDelegate,
  }) async {
    final cacheKey = '$assetPath|flex:$useFlexDelegate';
    final pending = _cache.putIfAbsent(
      cacheKey,
      () =>
          _createHandle(assetPath: assetPath, useFlexDelegate: useFlexDelegate),
    );
    try {
      return await pending;
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
  }) async {
    FlexDelegate? flexDelegate;
    Interpreter? interpreter;

    try {
      final options = InterpreterOptions()..threads = 2;

      if (useFlexDelegate) {
        if (Platform.isAndroid) {
          flexDelegate = await FlexDelegate.create();
        } else {
          flexDelegate = FlexDelegate();
        }
        options.addDelegate(flexDelegate);
      }

      interpreter = await Interpreter.fromAsset(assetPath, options: options);
      debugPrint(
        '[TfliteInterpreterManager] Loaded $assetPath '
        '(flex=$useFlexDelegate)',
      );
      final descriptor = _readDescriptor(
        interpreter: interpreter,
        assetPath: assetPath,
      );
      debugPrint(
        '[TfliteInterpreterManager] Loaded $assetPath '
        'inputShapes=${descriptor.inputShapes} '
        'outputShapes=${descriptor.outputShapes} '
        'inputTypes=${descriptor.inputTypes} '
        'outputTypes=${descriptor.outputTypes} '
        'signatures=${descriptor.signatureKeys}',
      );

      return _InterpreterHandle(
        interpreter: interpreter,
        flexDelegate: flexDelegate,
        descriptor: descriptor,
      );
    } catch (error) {
      interpreter?.close();
      flexDelegate?.delete();
      throw Exception(
        'Failed to initialize interpreter (flex=$useFlexDelegate): $error',
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

  Future<void> evict(String assetPath, {bool useFlexDelegate = false}) async {
    final cacheKey = '$assetPath|flex:$useFlexDelegate';
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
  final FlexDelegate? flexDelegate;
  final TfliteModelDescriptor descriptor;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  _InterpreterHandle({
    required this.interpreter,
    required this.flexDelegate,
    required this.descriptor,
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
      flexDelegate?.delete();
    });
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
