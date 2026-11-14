part of 'editor.dart';

bool _hasInvalidIndent(String text) => RegExp(
        r'^[ \t\u00a0\u200b\u200c\u200d\u2060\u3000]*[\u00a0\u200b\u200c\u200d\u2060\u3000]',
        multiLine: true)
    .hasMatch(text);

enum EditorCommand {
  indent,
  dedent,
  enter,
  backspace,
  caretLeft,
  caretRight,
  undo,
  redo,
}

class _PythonInputFormatter extends TextInputFormatter {
  const _PythonInputFormatter(this.state, this.position);
  final EditorState state;
  final RegionPosition position;
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final composing =
        newValue.composing.isValid && !newValue.composing.isCollapsed;
    final replacement = !composing && _hasInvalidIndent(newValue.text)
        ? _pastedReplacement(oldValue, newValue)
        : null;
    if (replacement != null &&
        replacement.text.length > 1 &&
        _hasInvalidIndent(replacement.text)) {
      if (state._deferPythonInput) {
        final start = state._regionOffset(position);
        final text = state._analysisText;
        final prefix = text.substring(0, start);
        final suffix = text.substring(start + oldValue.text.length);
        state._pythonInput.options = state._pythonOptions;
        state._queuePythonInput(position, _fullValue(oldValue, prefix, suffix),
            _fullValue(newValue, prefix, suffix), prefix, suffix,
            operation: _DeferredPythonOperation.literalPaste);
      } else {
        state._offerWhitespaceConversion(position,
            previousValue: oldValue, pastedValue: newValue);
      }
      return newValue;
    }
    final start = state._regionOffset(position);
    final text = state._analysisText;
    final prefix = text.substring(0, start);
    final suffix = text.substring(start + oldValue.text.length);
    final old = _fullValue(oldValue, prefix, suffix);
    final next = _fullValue(newValue, prefix, suffix);
    state._pythonInput.options = state._pythonOptions;
    if (state._deferPythonInput) {
      state._queuePythonInput(position, old, next, prefix, suffix);
      return newValue;
    }
    final result = state._pythonInput.formatEditUpdate(old, next,
        model: composing ? null : state._inputPythonModel,
        editableStart: start,
        editableEnd: start + oldValue.text.length);
    return _localValue(result, prefix, suffix);
  }
}

TextEditingValue _fullValue(
        TextEditingValue local, String prefix, String suffix) =>
    TextEditingValue(
        text: prefix + local.text + suffix,
        selection: local.selection.isValid
            ? local.selection.copyWith(
                baseOffset: local.selection.baseOffset + prefix.length,
                extentOffset: local.selection.extentOffset + prefix.length)
            : local.selection,
        composing: local.composing.isValid
            ? TextRange(
                start: local.composing.start + prefix.length,
                end: local.composing.end + prefix.length)
            : TextRange.empty);

TextEditingValue _localValue(
        TextEditingValue full, String prefix, String suffix) =>
    TextEditingValue(
        text: full.text
            .substring(prefix.length, full.text.length - suffix.length),
        selection: full.selection.isValid
            ? full.selection.copyWith(
                baseOffset: full.selection.baseOffset - prefix.length,
                extentOffset: full.selection.extentOffset - prefix.length)
            : full.selection,
        composing: full.composing.isValid
            ? TextRange(
                start: full.composing.start - prefix.length,
                end: full.composing.end - prefix.length)
            : TextRange.empty);

({int start, int end, String text})? _pastedReplacement(
    TextEditingValue before, TextEditingValue after,
    {bool explicitPaste = false}) {
  final selection = before.selection;
  if (before.text == after.text &&
      !(explicitPaste && selection.isValid && !selection.isCollapsed)) {
    return null;
  }
  if (selection.isValid) {
    final prefix = before.text.substring(0, selection.start);
    final suffix = before.text.substring(selection.end);
    if (after.text.length >= prefix.length + suffix.length &&
        after.text.startsWith(prefix) &&
        after.text.endsWith(suffix)) {
      return (
        start: selection.start,
        end: selection.end,
        text: after.text
            .substring(prefix.length, after.text.length - suffix.length)
      );
    }
  }
  var start = 0;
  while (start < before.text.length &&
      start < after.text.length &&
      before.text.codeUnitAt(start) == after.text.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = before.text.length;
  var newEnd = after.text.length;
  while (oldEnd > start &&
      newEnd > start &&
      before.text.codeUnitAt(oldEnd - 1) == after.text.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  return (start: start, end: oldEnd, text: after.text.substring(start, newEnd));
}

(PythonInputEngine, TextEditingValue) _convertedPythonPaste(
        (PythonInputEngine, TextEditingValue, String, bool, int, int) job) =>
    (
      job.$1,
      job.$1.paste(job.$2, job.$3,
          reindent: job.$4,
          normalizeUnsupportedWhitespace: false,
          editableStart: job.$5,
          editableEnd: job.$6)
    );

extension _PythonCommands on EditorState {
  void _offerWhitespaceConversion(RegionPosition position,
      {required TextEditingValue previousValue,
      required TextEditingValue pastedValue,
      bool explicitPaste = false,
      bool reindent = true}) {
    final replacement = _pastedReplacement(previousValue, pastedValue,
        explicitPaste: explicitPaste);
    if (replacement == null) return;
    final regionStart = _regionOffset(position);
    final oldFullText = _analysisText;
    final prefix = oldFullText.substring(0, regionStart);
    // The formatter calls before its controller updates; the public command
    // calls afterwards. The protected trailing source is identical in either.
    final suffix =
        oldFullText.substring(regionStart + _controller(position).text.length);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _whitespaceOfferOpen) return;
      final controller = _controller(position);
      final before = controller.value;
      if (before.text != pastedValue.text) return;
      if (before.composing.isValid && !before.composing.isCollapsed) return;
      final analysisText = _analysisText;
      final options = _pythonOptions;
      final analysis = analysisText.length > 80000
          ? await compute(_analyzePythonInBackground,
              (analysisText, options, _currentDocument.virtualAnalysisLine))
          : _inputPythonModel;
      if (!mounted || controller.value != before || options != _pythonOptions) {
        return;
      }
      final offsets = analysis.lines
          .expand((line) => line.diagnostics)
          .where((d) =>
              d.code == 'invalidWhitespace' &&
              d.startOffset >= regionStart + replacement.start &&
              d.startOffset <
                  regionStart + replacement.start + replacement.text.length)
          .map((d) => d.startOffset - regionStart)
          .toList()
        ..sort();
      if (offsets.isEmpty) return;
      _whitespaceOfferOpen = true;
      final convert = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Convert indentation?'),
                  content: const Text(
                      'The pasted indentation contains invisible characters Python does not accept. Convert them to regular spaces?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep text')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Convert'))
                  ]));
      _whitespaceOfferOpen = false;
      if (!mounted || convert != true || controller.text != before.text) return;
      if (!_analysisText.startsWith(prefix) ||
          !_analysisText.endsWith(suffix)) {
        return;
      }
      var converted = replacement.text;
      for (final offset in offsets.reversed) {
        final relative = offset - replacement.start;
        converted = converted.replaceRange(relative, relative + 1, ' ');
      }
      final original = _fullValue(
          previousValue.copyWith(
              selection: TextSelection(
                  baseOffset: replacement.start, extentOffset: replacement.end),
              composing: TextRange.empty),
          prefix,
          suffix);
      _pythonInput.options = _pythonOptions;
      final engine = _pythonInput.fork();
      final job = (
        engine,
        original,
        converted,
        reindent,
        regionStart,
        regionStart + previousValue.text.length
      );
      final formatted = original.text.length > 80000
          ? await compute(_convertedPythonPaste, job)
          : _convertedPythonPaste(job);
      if (!mounted ||
          controller.value != before ||
          options != _pythonOptions ||
          !_analysisText.startsWith(prefix) ||
          !_analysisText.endsWith(suffix)) {
        return;
      }
      final convertedValue = formatted.$2;
      _pythonInput.adopt(formatted.$1);
      if (!convertedValue.text.startsWith(prefix) ||
          !convertedValue.text.endsWith(suffix)) {
        return;
      }
      // An identical replacement changed only the selection, so the normal
      // controller listener has not yet recorded this paste transaction.
      if (previousValue.text == pastedValue.text) {
        _recordUndo(position, previousValue, current: pastedValue, force: true);
      }
      _performingHistory = true;
      try {
        controller.value = _localValue(convertedValue, prefix, suffix);
      } finally {
        _performingHistory = false;
      }
      handleTextChange(
          controller.text, position, widget.options.regionOptions != null);
      _revealCaret();
    });
  }

  void _executeCommand(EditorCommand command) {
    _breakUndoGroup();
    if (!_isPython || !widget.options.isEditable || isLoading) return;
    final controller = _controller(_activePosition);
    if (!controller.selection.isValid) {
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
    }
    if (command == EditorCommand.undo || command == EditorCommand.redo) {
      _restoreHistory(undo: command == EditorCommand.undo);
      return;
    }
    if (_deferPythonInput) {
      final operation = switch (command) {
        EditorCommand.indent => _DeferredPythonOperation.indent,
        EditorCommand.dedent => _DeferredPythonOperation.dedent,
        EditorCommand.enter => _DeferredPythonOperation.enter,
        EditorCommand.backspace => _DeferredPythonOperation.backspace,
        EditorCommand.caretLeft => _DeferredPythonOperation.left,
        EditorCommand.caretRight => _DeferredPythonOperation.right,
        _ => null,
      };
      if (operation != null) _deferPythonCommand(operation);
      return;
    }
    _applyPythonCommand((value, start, end) {
      final engine = _pythonInput..options = _pythonOptions;
      return switch (command) {
        EditorCommand.indent => engine.indent(value,
            model: _inputPythonModel, editableStart: start, editableEnd: end),
        EditorCommand.dedent => engine.dedent(value,
            model: _inputPythonModel, editableStart: start, editableEnd: end),
        EditorCommand.enter => engine.enter(value,
            model: _inputPythonModel, editableStart: start, editableEnd: end),
        EditorCommand.backspace => engine.backspace(value,
            model: _inputPythonModel, editableStart: start, editableEnd: end),
        EditorCommand.caretLeft => _moveIndentCaret(value, false, start, end),
        EditorCommand.caretRight => _moveIndentCaret(value, true, start, end),
        _ => value,
      };
    });
  }

  TextEditingValue _moveIndentCaret(
      TextEditingValue value, bool forward, int start, int end) {
    if (!value.selection.isCollapsed) {
      return value.copyWith(
          selection: TextSelection.collapsed(
              offset: forward ? value.selection.end : value.selection.start),
          composing: TextRange.empty);
    }
    final offset = value.selection.extentOffset;
    final model = _inputPythonModel;
    final line = model.lines[model.lineAtOffset(offset)];
    var next = forward
        ? offset < value.text.length
            ? offset + value.text.substring(offset).characters.first.length
            : offset
        : offset > 0
            ? offset - value.text.substring(0, offset).characters.last.length
            : 0;
    if (offset >= line.startOffset && offset <= line.leadingWhitespaceEnd) {
      final relative = offset - line.startOffset;
      if (!line.indentPrefix.contains('\t')) {
        final step = model.effectiveIndentSize;
        final stop = forward
            ? (relative ~/ step + 1) * step
            : ((relative - 1) ~/ step) * step;
        final target = line.startOffset + stop;
        if (target >= line.startOffset &&
            target <= line.leadingWhitespaceEnd &&
            target != offset) {
          next = target;
        }
      }
    }
    return value.copyWith(
        selection: TextSelection.collapsed(offset: next.clamp(start, end)),
        composing: TextRange.empty);
  }

  void _applyPythonCommand(
      TextEditingValue Function(TextEditingValue, int, int) command) {
    _pythonInput.options = _pythonOptions;
    final controller = _controller(_activePosition);
    final start = _regionOffset(_activePosition);
    final text = _analysisText;
    final prefix = text.substring(0, start);
    final suffix = text.substring(start + controller.text.length);
    final full = _fullValue(controller.value, prefix, suffix);
    final next = command(full, start, start + controller.text.length);
    if (!next.text.startsWith(prefix) || !next.text.endsWith(suffix)) return;
    _breakUndoGroup();
    controller.value = _localValue(next, prefix, suffix);
    _breakUndoGroup();
    handleTextChange(
        controller.text, _activePosition, widget.options.regionOptions != null);
    _revealCaret();
  }

  void _restoreHistory({required bool undo}) {
    _breakUndoGroup();
    if (!_isPython || !widget.options.isEditable || isLoading) return;
    final pending = _deferredPythonInput[_activePosition];
    final controller = _controller(_activePosition);
    final previousValue = controller.value;
    final history = (undo ? _undoHistory : _redoHistory)[_activePosition]!;
    final destination = (undo ? _redoHistory : _undoHistory)[_activePosition]!;
    if (history.isEmpty) {
      if (pending != null && !pending.cancelled) {
        // Automatic pairs/indentation can introduce undo boundaries that the
        // optimistic native text did not have. Replay every history request
        // against the worker's formatted history, even if the raw one is empty.
        final current =
            _fullValue(controller.value, pending.prefix, pending.suffix);
        _queuePythonInput(
            _activePosition, current, current, pending.prefix, pending.suffix,
            operation: undo
                ? _DeferredPythonOperation.undo
                : _DeferredPythonOperation.redo);
      }
      return;
    }
    destination.add(controller.value);
    if (_activePosition == RegionPosition.inner) {
      final sourceFlags = undo ? _undoEmptyInner : _redoEmptyInner;
      final destinationFlags = undo ? _redoEmptyInner : _undoEmptyInner;
      destinationFlags.add(_emptyInner);
      _emptyInner = sourceFlags.removeLast();
      _document = null;
    }
    _trimHistory(
        destination,
        _activePosition == RegionPosition.inner
            ? (undo ? _redoEmptyInner : _undoEmptyInner)
            : null);
    _performingHistory = true;
    controller.value = history.removeLast();
    _performingHistory = false;
    _pythonInput.reset();
    if (pending != null && !pending.cancelled) {
      _queuePythonInput(
          _activePosition,
          _fullValue(previousValue, pending.prefix, pending.suffix),
          _fullValue(controller.value, pending.prefix, pending.suffix),
          pending.prefix,
          pending.suffix,
          operation: undo
              ? _DeferredPythonOperation.undo
              : _DeferredPythonOperation.redo);
    }
    handleTextChange(
        controller.text, _activePosition, widget.options.regionOptions != null);
    _revealCaret();
  }

  void _snapIndentTap(RegionPosition position) {
    if (!_isPython || !widget.options.isEditable) return;
    final controller = _controller(position);
    if (!controller.selection.isValid || !controller.selection.isCollapsed) {
      return;
    }
    if (_deferPythonInput) {
      _deferPythonCommand(_DeferredPythonOperation.snap, position: position);
      return;
    }
    final start = _regionOffset(position);
    final caret = start + controller.selection.extentOffset;
    final model = _inputPythonModel;
    final line = model.lines[model.lineAtOffset(caret)];
    if (caret > line.leadingWhitespaceEnd || line.indentPrefix.contains('\t')) {
      return;
    }
    final unit = model.effectiveIndentSize;
    final relative = caret - line.startOffset;
    final stop = (relative / unit).round() * unit;
    controller.selection = TextSelection.collapsed(
        offset: (line.startOffset + stop)
                .clamp(line.startOffset, line.leadingWhitespaceEnd) -
            start);
  }

  void _revealCaret() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isPython) return;
      final caret = _globalCaretOffset;
      final model = _currentPythonModel;
      if (caret == null || model == null) return;
      final row = model.lineAtOffset(caret);
      final line = model.lines[row];
      final box = _textLayout.boxForLine(row);
      if (scrollController.hasClients && box != null) {
        final position = scrollController.position;
        final bottom = box.bottom;
        final target = bottom > position.pixels + position.viewportDimension
            ? bottom - position.viewportDimension
            : box.top < position.pixels
                ? box.top
                : position.pixels;
        scrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
      }
      if (horizontalController.hasClients) {
        final style = _style(context);
        final width = _measureText(
            line.text.substring(
                0, (caret - line.startOffset).clamp(0, line.text.length)),
            style,
            MediaQuery.textScalerOf(context),
            StrutStyle.fromTextStyle(style, forceStrutHeight: true));
        final position = horizontalController.position;
        final target = width + _contentPadding * 2 >
                position.pixels + position.viewportDimension
            ? width + _contentPadding * 2 - position.viewportDimension
            : width < position.pixels
                ? math.max(0.0, width - _contentPadding)
                : position.pixels;
        horizontalController
            .jumpTo(target.clamp(0.0, position.maxScrollExtent));
      }
    });
  }
}
