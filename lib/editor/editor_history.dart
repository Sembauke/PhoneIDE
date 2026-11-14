part of 'editor.dart';

const _maxUndoEntries = 100;
const _maxUndoBytes = 2 * 1024 * 1024;

void _trimHistory(List<TextEditingValue> values, [List<bool>? flags]) {
  var bytes = values.fold<int>(0, (sum, value) => sum + value.text.length * 2);
  var remove = 0;
  while (remove < values.length &&
      (values.length - remove > _maxUndoEntries || bytes > _maxUndoBytes)) {
    bytes -= values[remove].text.length * 2;
    remove++;
  }
  if (remove == 0) return;
  values.removeRange(0, remove);
  flags?.removeRange(0, remove);
}

/// Consecutive, adjacent typing/deletion within one second is one undo step.
/// Commands, multiline edits, caret moves, and IME transactions form boundaries.
class _UndoGroup {
  TextEditingValue? last;
  int? kind;
  int timestamp = 0;

  _UndoGroup fork() => _UndoGroup()
    ..last = last
    ..kind = kind
    ..timestamp = timestamp;

  void reset() {
    last = null;
    kind = null;
  }

  bool startsStep(TextEditingValue before, TextEditingValue after, int now) {
    final nextKind = _kind(before, after);
    final grouped = nextKind != null &&
        nextKind == kind &&
        last?.text == before.text &&
        last?.selection == before.selection &&
        now - timestamp <= const Duration(seconds: 1).inMicroseconds;
    last = after;
    kind = nextKind;
    timestamp = now;
    return !grouped;
  }

  int? _kind(TextEditingValue before, TextEditingValue after) {
    if (!before.selection.isValid ||
        !before.selection.isCollapsed ||
        !after.selection.isValid ||
        !after.selection.isCollapsed ||
        !before.composing.isCollapsed ||
        !after.composing.isCollapsed) {
      return null;
    }
    final offset = before.selection.extentOffset;
    final next = after.selection.extentOffset;
    if (next == offset + 1 &&
        after.text.length == before.text.length + 1 &&
        after.text.codeUnitAt(offset) != 10 &&
        after.text.codeUnitAt(offset) != 13 &&
        after.text.substring(0, offset) == before.text.substring(0, offset) &&
        after.text.substring(next) == before.text.substring(offset)) {
      return 1;
    }
    if (offset > 0 &&
        next == offset - 1 &&
        after.text.length == before.text.length - 1 &&
        before.text.codeUnitAt(next) != 10 &&
        before.text.codeUnitAt(next) != 13 &&
        after.text.substring(0, next) == before.text.substring(0, next) &&
        after.text.substring(next) == before.text.substring(offset)) {
      return -1;
    }
    return null;
  }
}

extension _EditorHistory on EditorState {
  void _breakUndoGroup() {
    for (final group in _historyGroups.values) {
      group.reset();
    }
  }

  void _recordUndo(RegionPosition position, TextEditingValue before,
      {required TextEditingValue current, bool force = false}) {
    final group = _historyGroups[position]!;
    if (force) group.reset();
    if (force ||
        group.startsStep(
            before, current, DateTime.now().microsecondsSinceEpoch)) {
      _undoHistory[position]!.add(before);
      if (position == RegionPosition.inner) _undoEmptyInner.add(_emptyInner);
      _trimHistory(_undoHistory[position]!,
          position == RegionPosition.inner ? _undoEmptyInner : null);
    }
    _redoHistory[position]!.clear();
    if (position == RegionPosition.inner) _redoEmptyInner.clear();
  }
}
