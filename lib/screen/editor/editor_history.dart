import 'dart:typed_data';

import 'editor_types.dart';

class EditorSnapshot {
  final Map<EditorAdjustment, double> adjustments;
  final Uint8List? sourceBytes;
  final Uint8List? previewSourceBytes;
  final double? imageAspectRatio;
  final bool imageModified;

  const EditorSnapshot({
    required this.adjustments,
    this.sourceBytes,
    this.previewSourceBytes,
    this.imageAspectRatio,
    required this.imageModified,
  });
}

class EditorHistoryManager {
  static const int maxDepth = 20;

  final List<EditorSnapshot> _undoStack = [];
  final List<EditorSnapshot> _redoStack = [];

  bool get canUndo => _undoStack.length > 1;
  bool get canRedo => _redoStack.isNotEmpty;

  void push(EditorSnapshot snapshot) {
    _undoStack.add(snapshot);
    _redoStack.clear();
    if (_undoStack.length > maxDepth) {
      _undoStack.removeAt(0);
    }
  }

  EditorSnapshot? undo() {
    if (!canUndo) return null;
    final current = _undoStack.removeLast();
    _redoStack.add(current);
    return _undoStack.last;
  }

  EditorSnapshot? redo() {
    if (!canRedo) return null;
    final snapshot = _redoStack.removeLast();
    _undoStack.add(snapshot);
    return snapshot;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
