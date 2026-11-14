part of 'editor.dart';

enum _DeferredPythonOperation {
  input,
  indent,
  dedent,
  enter,
  backspace,
  paste,
  literalPaste,
  convert,
  left,
  right,
  snap,
  undo,
  redo,
}

class _DeferredPythonEdit {
  _DeferredPythonEdit(this.before, this.after,
      {this.operation = _DeferredPythonOperation.input,
      this.inserted = '',
      this.reindent = true,
      this.indentSize = 4,
      this.usesTabs = false})
      : timestamp = DateTime.now().microsecondsSinceEpoch;
  final TextEditingValue before, after;
  final _DeferredPythonOperation operation;
  final String inserted;
  final bool reindent, usesTabs;
  final int indentSize;
  final int timestamp;
}

class _DeferredPythonBatch {
  const _DeferredPythonBatch(this.engine, this.raw, this.formatted, this.edits,
      this.prefixLength, this.suffixLength, this.history);
  final PythonInputEngine engine;
  final TextEditingValue raw, formatted;
  final List<_DeferredPythonEdit> edits;
  final int prefixLength, suffixLength;
  final _DeferredPythonHistory history;
}

class _DeferredPythonResult {
  const _DeferredPythonResult(
      this.engine, this.raw, this.formatted, this.history, this.offers);
  final PythonInputEngine engine;
  final TextEditingValue raw, formatted;
  final _DeferredPythonHistory history;
  final List<(TextEditingValue, TextEditingValue, bool)> offers;
}

class _DeferredPythonHistory {
  _DeferredPythonHistory(this.undo, this.redo, this.undoEmpty, this.redoEmpty,
      this.empty, this.inner, this.prefix, this.suffix, this.group,
      {this.undoPrefix = 0, this.redoPrefix = 0});
  final List<TextEditingValue> undo, redo;
  final List<bool> undoEmpty, redoEmpty;
  bool empty;
  final bool inner;
  final String prefix, suffix;
  final _UndoGroup group;
  int undoPrefix, redoPrefix;

  /// Normal input needs no old snapshots in the worker. Only send as many tail
  /// entries as this batch could restore; retain the unchanged prefix here.
  _DeferredPythonHistory forBatch(List<_DeferredPythonEdit> edits) {
    final restores = edits
        .where((edit) =>
            edit.operation == _DeferredPythonOperation.undo ||
            edit.operation == _DeferredPythonOperation.redo)
        .length;
    final undoStart = math.max(0, undo.length - restores);
    final redoStart = math.max(0, redo.length - restores);
    return _DeferredPythonHistory(
        undo.sublist(undoStart),
        redo.sublist(redoStart),
        inner ? undoEmpty.sublist(undoStart) : [],
        inner ? redoEmpty.sublist(redoStart) : [],
        empty,
        inner,
        prefix,
        suffix,
        group.fork(),
        undoPrefix: undoStart,
        redoPrefix: redoStart);
  }

  _DeferredPythonHistory merge(_DeferredPythonHistory result) {
    final merged = _DeferredPythonHistory(
        [...undo.take(result.undoPrefix), ...result.undo],
        [...redo.take(result.redoPrefix), ...result.redo],
        inner
            ? [...undoEmpty.take(result.undoPrefix), ...result.undoEmpty]
            : [],
        inner
            ? [...redoEmpty.take(result.redoPrefix), ...result.redoEmpty]
            : [],
        result.empty,
        inner,
        prefix,
        suffix,
        result.group);
    _trimHistory(merged.undo, inner ? merged.undoEmpty : null);
    _trimHistory(merged.redo, inner ? merged.redoEmpty : null);
    return merged;
  }

  void record(TextEditingValue before, TextEditingValue after,
      _DeferredPythonEdit edit) {
    if (before.text == after.text) {
      if (before.selection != after.selection) group.reset();
      return;
    }
    final localBefore = _localValue(before, prefix, suffix);
    final localAfter = _localValue(after, prefix, suffix);
    if (edit.operation != _DeferredPythonOperation.input) group.reset();
    if (before.composing.isCollapsed) {
      if (group.startsStep(localBefore, localAfter, edit.timestamp)) {
        undo.add(localBefore);
        if (inner) undoEmpty.add(empty);
        _trimHistory(undo, inner ? undoEmpty : null);
      }
      redo.clear();
      redoPrefix = 0;
      redoEmpty.clear();
    }
    if (edit.operation != _DeferredPythonOperation.input) group.reset();
    empty = false;
  }

  TextEditingValue restore(TextEditingValue current, bool backwards) {
    group.reset();
    final source = backwards ? undo : redo;
    final destination = backwards ? redo : undo;
    if (source.isEmpty) return current;
    destination.add(_localValue(current, prefix, suffix));
    if (inner) {
      final flags = backwards ? undoEmpty : redoEmpty;
      final destinationFlags = backwards ? redoEmpty : undoEmpty;
      destinationFlags.add(empty);
      empty = flags.removeLast();
    }
    return _fullValue(source.removeLast(), prefix, suffix);
  }
}

// A pending formatter may have inserted indentation or a paired delimiter.
// Remap subsequent native edits through that correction, using the caret as an
// anchor at insertion boundaries. If a moved selection points inside a rewritten
// range with no unique correspondence, leave the user's raw edits untouched.
class _DeferredOffsetMap {
  _DeferredOffsetMap(this.raw, this.formatted)
      : change = _pastedReplacement(
            raw.copyWith(selection: const TextSelection.collapsed(offset: -1)),
            formatted.copyWith(
                selection: const TextSelection.collapsed(offset: -1)));
  final TextEditingValue raw, formatted;
  final ({int start, int end, String text})? change;

  int? offset(int value) {
    if (value < 0) return value;
    if (raw.selection.isValid && formatted.selection.isValid) {
      if (value == raw.selection.baseOffset) {
        return formatted.selection.baseOffset;
      }
      if (value == raw.selection.extentOffset) {
        return formatted.selection.extentOffset;
      }
    }
    // A caret-only command still changes the anchor even when the text is
    // unchanged. Keep that correction when the live selection has not moved.
    if (raw.text == formatted.text) return value;
    final edit = change!;
    if (value <= edit.start) return value;
    if (value >= edit.end) {
      return value + formatted.text.length - raw.text.length;
    }
    return null;
  }

  TextEditingValue? selectionOf(TextEditingValue next) {
    final base = offset(next.selection.baseOffset);
    final extent = offset(next.selection.extentOffset);
    final composingStart = offset(next.composing.start);
    final composingEnd = offset(next.composing.end);
    if (base == null ||
        extent == null ||
        composingStart == null ||
        composingEnd == null) {
      return null;
    }
    return formatted.copyWith(
        selection:
            next.selection.copyWith(baseOffset: base, extentOffset: extent),
        composing: TextRange(start: composingStart, end: composingEnd));
  }

  TextEditingValue? edit(TextEditingValue before, TextEditingValue after) {
    final replacement = _pastedReplacement(before, after);
    if (replacement == null) return selectionOf(after);
    final start = offset(replacement.start), end = offset(replacement.end);
    if (start == null || end == null || end < start) return null;
    final rawEnd = replacement.start + replacement.text.length;
    int? afterOffset(int value) {
      if (value < 0) return value;
      if (value >= replacement.start && value <= rawEnd) {
        return start + value - replacement.start;
      }
      final oldOffset =
          value > rawEnd ? value + replacement.end - rawEnd : value;
      final mapped = offset(oldOffset);
      if (mapped == null) return null;
      return oldOffset >= replacement.end
          ? mapped + replacement.text.length - (end - start)
          : mapped;
    }

    final base = afterOffset(after.selection.baseOffset);
    final extent = afterOffset(after.selection.extentOffset);
    final composingStart = afterOffset(after.composing.start);
    final composingEnd = afterOffset(after.composing.end);
    if (base == null ||
        extent == null ||
        composingStart == null ||
        composingEnd == null) {
      return null;
    }
    return TextEditingValue(
        text: formatted.text.replaceRange(start, end, replacement.text),
        selection:
            after.selection.copyWith(baseOffset: base, extentOffset: extent),
        composing: TextRange(start: composingStart, end: composingEnd));
  }
}

_DeferredPythonResult? _formatPythonInputBatch(_DeferredPythonBatch job) {
  var raw = job.raw, formatted = job.formatted;
  final history = job.history;
  final offers = <(TextEditingValue, TextEditingValue, bool)>[];
  for (final edit in job.edits) {
    if (raw.text != edit.before.text) return null;
    final mapping = _DeferredOffsetMap(raw, formatted);
    final before = mapping.selectionOf(edit.before);
    if (before == null) return null;
    final rawCaret = edit.before.selection.extentOffset;
    final deletion = _pastedReplacement(edit.before, edit.after);
    final nativeBackspace = edit.operation == _DeferredPythonOperation.input &&
        edit.before.composing.isCollapsed &&
        edit.after.composing.isCollapsed &&
        edit.before.selection.isCollapsed &&
        edit.after.selection.isCollapsed &&
        deletion != null &&
        deletion.text.isEmpty &&
        deletion.end == rawCaret &&
        deletion.start == edit.after.selection.extentOffset &&
        rawCaret > 0 &&
        rawCaret - deletion.start ==
            edit.before.text.substring(0, rawCaret).characters.last.length;
    final restoring = edit.operation == _DeferredPythonOperation.undo ||
        edit.operation == _DeferredPythonOperation.redo;
    final after = nativeBackspace || restoring
        ? before
        : mapping.edit(edit.before, edit.after);
    if (after == null) return null;
    final start = job.prefixLength;
    final end = before.text.length - job.suffixLength;
    final engine = job.engine;
    final result = switch (edit.operation) {
      _DeferredPythonOperation.input => nativeBackspace
          ? engine.backspace(before, editableStart: start, editableEnd: end)
          : engine.formatEditUpdate(before, after,
              editableStart: start, editableEnd: end),
      _DeferredPythonOperation.indent =>
        engine.indent(before, editableStart: start, editableEnd: end),
      _DeferredPythonOperation.dedent =>
        engine.dedent(before, editableStart: start, editableEnd: end),
      _DeferredPythonOperation.enter =>
        engine.enter(before, editableStart: start, editableEnd: end),
      _DeferredPythonOperation.backspace =>
        engine.backspace(before, editableStart: start, editableEnd: end),
      _DeferredPythonOperation.literalPaste => after,
      _DeferredPythonOperation.paste => engine.paste(before, edit.inserted,
          reindent: edit.reindent, editableStart: start, editableEnd: end),
      _DeferredPythonOperation.convert => engine.convertIndentation(before,
          indentSize: edit.indentSize,
          usesTabs: edit.usesTabs,
          editableStart: start,
          editableEnd: end),
      _DeferredPythonOperation.undo || _DeferredPythonOperation.redo => history
          .restore(before, edit.operation == _DeferredPythonOperation.undo),
      _DeferredPythonOperation.left ||
      _DeferredPythonOperation.right ||
      _DeferredPythonOperation.snap =>
        _deferredCaretMove(before, engine.options, edit.operation, start, end),
    };
    if (edit.operation == _DeferredPythonOperation.literalPaste) {
      offers.add((before, result, edit.reindent));
    }
    if (restoring) {
      engine.reset();
    } else {
      history.record(before, result, edit);
    }
    raw = edit.after;
    formatted = result;
  }
  return _DeferredPythonResult(job.engine, raw, formatted, history, offers);
}

TextEditingValue _deferredCaretMove(
    TextEditingValue value,
    PythonIndentOptions options,
    _DeferredPythonOperation operation,
    int start,
    int end) {
  final forward = operation == _DeferredPythonOperation.right;
  if (!value.selection.isCollapsed) {
    return value.copyWith(
        selection: TextSelection.collapsed(
            offset: forward ? value.selection.end : value.selection.start),
        composing: TextRange.empty);
  }
  final model = PythonIndentModel.analyze(value.text, options: options);
  final offset = value.selection.extentOffset;
  final line = model.lines[model.lineAtOffset(offset)];
  final snap = operation == _DeferredPythonOperation.snap;
  var next = snap
      ? offset
      : forward
          ? offset < value.text.length
              ? offset + value.text.substring(offset).characters.first.length
              : offset
          : offset > 0
              ? offset - value.text.substring(0, offset).characters.last.length
              : 0;
  if (offset >= line.startOffset &&
      offset <= line.leadingWhitespaceEnd &&
      !line.indentPrefix.contains('\t')) {
    final relative = offset - line.startOffset;
    final unit = model.effectiveIndentSize;
    final stop = snap
        ? (relative / unit).round() * unit
        : forward
            ? (relative ~/ unit + 1) * unit
            : ((relative - 1) ~/ unit) * unit;
    final target = line.startOffset + stop;
    if (snap) {
      next = target.clamp(line.startOffset, line.leadingWhitespaceEnd);
    } else if (target >= line.startOffset &&
        target <= line.leadingWhitespaceEnd &&
        target != offset) {
      next = target;
    }
  }
  return value.copyWith(
      selection: TextSelection.collapsed(offset: next.clamp(start, end)),
      composing: TextRange.empty);
}

class _DeferredPythonInput {
  _DeferredPythonInput(this.state, this.position, this.prefix, this.suffix,
      TextEditingValue initial)
      : initialization = state._initialization,
        options = state._pythonOptions,
        engine = state._pythonInput.fork(),
        raw = initial,
        formatted = initial,
        latest = initial,
        history = _DeferredPythonHistory(
            [...state._undoHistory[position]!],
            [...state._redoHistory[position]!],
            position == RegionPosition.inner ? [...state._undoEmptyInner] : [],
            position == RegionPosition.inner ? [...state._redoEmptyInner] : [],
            state._emptyInner,
            position == RegionPosition.inner,
            prefix,
            suffix,
            state._historyGroups[position]!.fork());
  final EditorState state;
  final RegionPosition position;
  final String prefix, suffix;
  final int initialization;
  final PythonIndentOptions options;
  PythonInputEngine engine;
  TextEditingValue raw, formatted, latest;
  final edits = <_DeferredPythonEdit>[];
  final offers = <(TextEditingValue, TextEditingValue, bool)>[];
  _DeferredPythonHistory history;

  bool working = false, cancelled = false;
  bool get valid =>
      !cancelled &&
      state.mounted &&
      state._initialization == initialization &&
      state._pythonOptions == options &&
      state.widget.options.isEditable &&
      state._isPython &&
      state._analysisText == prefix + state._controller(position).text + suffix;

  void cancel() {
    cancelled = true;
    edits.clear();
    if (identical(state._deferredPythonInput[position], this)) {
      state._deferredPythonInput.remove(position);
    }
  }

  void add(_DeferredPythonEdit edit) {
    edits.add(edit);
    latest = edit.after;
    if (!working) unawaited(_drain());
  }

  Future<void> _drain() async {
    working = true;
    try {
      while (edits.isNotEmpty && !cancelled) {
        final batch = List<_DeferredPythonEdit>.of(edits);
        edits.clear();
        final result = await compute(
            _formatPythonInputBatch,
            _DeferredPythonBatch(engine.fork(), raw, formatted, batch,
                prefix.length, suffix.length, history.forBatch(batch)));
        if (!valid ||
            state._controller(position).text !=
                _localValue(latest, prefix, suffix).text ||
            result == null) {
          cancel();
          return;
        }
        engine = result.engine;
        raw = result.raw;
        formatted = result.formatted;
        history = history.merge(result.history);
        offers.addAll(result.offers);
      }
      if (!valid) return;
      final controller = state._controller(position);
      // A live composing range belongs to the IME. Keep the result pending
      // until its commit arrives, without replacing its text or selection.
      if (controller.value.composing.isValid &&
          !controller.value.composing.isCollapsed) {
        return;
      }
      final actual = _fullValue(controller.value, prefix, suffix);
      final finalValue = _DeferredOffsetMap(raw, formatted).selectionOf(actual);
      if (finalValue == null) {
        cancel();
        return;
      }
      state._undoHistory[position]!
        ..clear()
        ..addAll(history.undo);
      state._redoHistory[position]!
        ..clear()
        ..addAll(history.redo);
      if (position == RegionPosition.inner) {
        state._undoEmptyInner
          ..clear()
          ..addAll(history.undoEmpty);
        state._redoEmptyInner
          ..clear()
          ..addAll(history.redoEmpty);
        state._emptyInner = history.empty;
        state._document = null;
      }
      state._historyGroups[position] = history.group;
      state._pythonInput.adopt(engine);
      state._performingHistory = true;
      try {
        controller.value = _localValue(finalValue, prefix, suffix);
      } finally {
        state._performingHistory = false;
      }
      cancel();
      for (final offer in offers) {
        final pasted = _localValue(offer.$2, prefix, suffix);
        if (controller.text != pasted.text) continue;
        state._offerWhitespaceConversion(position,
            previousValue: _localValue(offer.$1, prefix, suffix),
            pastedValue: pasted,
            explicitPaste: true,
            reindent: offer.$3);
      }
      state._revealCaret();
    } catch (error, stack) {
      cancel();
      FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'phone_ide',
          context: ErrorDescription('while formatting Python input')));
    } finally {
      working = false;
    }
  }
}

extension _DeferredPythonEditor on EditorState {
  bool get _deferPythonInput =>
      _analysisText.length > 80000 || _deferredPythonInput.isNotEmpty;

  bool _deferPublicPythonPaste(String text, {required bool reindent}) {
    if (!_deferPythonInput) return false;
    if (!_hasInvalidIndent(text)) {
      _deferPythonCommand(_DeferredPythonOperation.paste,
          inserted: text, reindent: reindent);
      return true;
    }
    _deferPythonCommand(_DeferredPythonOperation.literalPaste,
        inserted: text, reindent: reindent);
    return true;
  }

  void _cancelDeferredPythonInputs() {
    for (final input in _deferredPythonInput.values.toList()) {
      input.cancel();
    }
  }

  void _queuePythonInput(RegionPosition position, TextEditingValue old,
      TextEditingValue next, String prefix, String suffix,
      {_DeferredPythonOperation operation = _DeferredPythonOperation.input,
      String inserted = '',
      bool reindent = true,
      int indentSize = 4,
      bool usesTabs = false,
      bool explicitCommand = false}) {
    var pending = _deferredPythonInput[position];
    if (pending != null &&
        (!pending.valid ||
            pending.latest.text != old.text ||
            pending.prefix != prefix ||
            pending.suffix != suffix)) {
      pending.cancel();
      pending = null;
    }
    pending ??= _DeferredPythonInput(this, position, prefix, suffix, old);
    _deferredPythonInput[position] = pending;
    final changesText = old.text != next.text;
    final caretCommand = const {
      _DeferredPythonOperation.left,
      _DeferredPythonOperation.right,
      _DeferredPythonOperation.snap
    }.contains(operation);
    final historyIndex = old.composing.isCollapsed &&
            (changesText || (explicitCommand && !caretCommand))
        ? _undoHistory[position]!.length
        : null;
    if (explicitCommand && !changesText && historyIndex != null) {
      _recordUndo(position, _localValue(old, prefix, suffix),
          current: _localValue(next, prefix, suffix), force: true);
    }
    pending.add(_DeferredPythonEdit(old, next,
        operation: operation,
        inserted: inserted,
        reindent: reindent,
        indentSize: indentSize,
        usesTabs: usesTabs));
  }

  void _deferPythonCommand(_DeferredPythonOperation operation,
      {String inserted = '',
      bool reindent = true,
      int indentSize = 4,
      bool usesTabs = false,
      RegionPosition? position}) {
    position ??= _activePosition;
    final controller = _controller(position);
    final local = controller.value;
    if (!local.selection.isValid ||
        (local.composing.isValid && !local.composing.isCollapsed)) {
      return;
    }
    final start = _regionOffset(position);
    final text = _analysisText;
    final prefix = text.substring(0, start);
    final suffix = text.substring(start + local.text.length);
    final old = _fullValue(local, prefix, suffix);
    var next = old;
    var first = old.selection.start, last = old.selection.end;
    String? insertion;
    switch (operation) {
      case _DeferredPythonOperation.enter:
        insertion =
            RegExp(r'\r\n|\r|\n').firstMatch(old.text)?.group(0) ?? '\n';
      case _DeferredPythonOperation.backspace:
        if (first == last && first > start) {
          first -= old.text.substring(start, first).characters.last.length;
        }
        insertion = '';
      case _DeferredPythonOperation.paste:
      case _DeferredPythonOperation.literalPaste:
      case _DeferredPythonOperation.input:
        insertion = inserted;
      default:
        break;
    }
    if (insertion != null) {
      next = old.copyWith(
          text: old.text.replaceRange(first, last, insertion),
          selection: TextSelection.collapsed(offset: first + insertion.length),
          composing: TextRange.empty);
    }
    _pythonInput.options = _pythonOptions;
    _queuePythonInput(position, old, next, prefix, suffix,
        operation: operation,
        inserted: inserted,
        reindent: reindent,
        indentSize: indentSize,
        usesTabs: usesTabs,
        explicitCommand: true);
    controller.value = _localValue(next, prefix, suffix);
  }
}
