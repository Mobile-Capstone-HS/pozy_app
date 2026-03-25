import 'dart:io';

import 'package:flutter_litert/flutter_litert.dart';

class TfliteInterpreterManager {
  TfliteInterpreterManager._();

  static final TfliteInterpreterManager instance = TfliteInterpreterManager._();

  final Map<String, Future<_InterpreterHandle>> _cache = {};

  Future<Interpreter> getInterpreter(
    String assetPath, {
    bool useFlexDelegate = false,
  }) async {
    final cacheKey = '$assetPath|flex:$useFlexDelegate';
    final handle = await _cache.putIfAbsent(
      cacheKey,
      () =>
          _createHandle(assetPath: assetPath, useFlexDelegate: useFlexDelegate),
    );
    return handle.interpreter;
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

      return _InterpreterHandle(
        interpreter: interpreter,
        flexDelegate: flexDelegate,
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
      handle.interpreter.close();
      handle.flexDelegate?.delete();
    }
    _cache.clear();
  }
}

class _InterpreterHandle {
  final Interpreter interpreter;
  final FlexDelegate? flexDelegate;

  const _InterpreterHandle({
    required this.interpreter,
    required this.flexDelegate,
  });
}
