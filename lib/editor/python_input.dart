import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'python_indentation.dart';

/// Python editing operations expressed as single full-document transactions.
///
/// The host owns its undo history and maps any bounded text fields to these
/// document offsets. Protected text outside [editableStart]/[editableEnd] is
/// never modified by an automatic edit.
class PythonInputEngine {
  PythonInputEngine({this.options = const PythonIndentOptions()});

  PythonIndentOptions options;
  final _pairs = <_InsertedPair>[];
  final _dedentedLines = <int>{};
  String? _lastText;

  /// Copies the small editing state for formatting in a background isolate.
  PythonInputEngine fork() => PythonInputEngine(options: options)..adopt(this);

  /// Accepts a worker result only after the host verifies its source revision.
  void adopt(PythonInputEngine other) {
    options = other.options;
    _pairs
      ..clear()
      ..addAll(other._pairs);
    _dedentedLines
      ..clear()
      ..addAll(other._dedentedLines);
    _lastText = other._lastText;
  }

  void reset() {
    _pairs.clear();
    _dedentedLines.clear();
    _lastText = null;
  }

  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue, {
    PythonIndentModel? model,
    int editableStart = 0,
    int? editableEnd,
  }) {
    _prepare(oldValue);
    final end = editableEnd ?? oldValue.text.length;
    if (!_valid(oldValue) || !_valid(newValue)) return newValue;
    if (_composing(newValue)) {
      return _finish(oldValue, newValue, editableStart, end);
    }
    newValue = _normalizeKeyboardPunctuation(oldValue, newValue);
    if (oldValue.text == newValue.text) {
      return cleanupOnCaretMove(oldValue, newValue,
          editableStart: editableStart, editableEnd: end);
    }
    final change = _TextChange.between(oldValue.text, newValue.text);
    final caret = oldValue.selection.extentOffset;
    final collapsed = oldValue.selection.isCollapsed;
    if (!_composing(oldValue) &&
        collapsed &&
        change.removed.length == 1 &&
        change.inserted.isEmpty &&
        newValue.selection.isCollapsed &&
        newValue.selection.extentOffset == caret - 1 &&
        newValue.text == oldValue.text.replaceRange(caret - 1, caret, '')) {
      return backspace(oldValue,
          model: model, editableStart: editableStart, editableEnd: end);
    }

    // A committed IME batch can replace the composing word and add Enter in
    // the same update. Treat that final newline after the committed text.
    if (_composing(oldValue) &&
        newValue.selection.isCollapsed &&
        newValue.selection.extentOffset > 0) {
      final committedCaret = newValue.selection.extentOffset;
      final newlineLength = _newlineBefore(newValue.text, committedCaret);
      if (newlineLength > 0 && change.inserted.contains(RegExp(r'[\r\n]'))) {
        final withoutNewline = newValue.copyWith(
          text: newValue.text
              .replaceRange(committedCaret - newlineLength, committedCaret, ''),
          selection:
              TextSelection.collapsed(offset: committedCaret - newlineLength),
          composing: TextRange.empty,
        );
        final adjusted = _enter(withoutNewline);
        return _finish(oldValue, adjusted, editableStart, end);
      }
    }

    final selectionReplacement =
        _isSelectionReplacement(oldValue, newValue, change);
    final inserted = selectionReplacement
        ? newValue.text.substring(
            oldValue.selection.start, newValue.selection.extentOffset)
        : '';
    if (selectionReplacement) {
      if (inserted == '\n' || inserted == '\r' || inserted == '\r\n') {
        return enter(oldValue,
            model: model, editableStart: editableStart, editableEnd: end);
      }
      if (inserted.length > 1 && inserted.contains(RegExp(r'[\r\n]'))) {
        return paste(oldValue, inserted,
            model: model, editableStart: editableStart, editableEnd: end);
      }
    }

    if (collapsed && selectionReplacement && inserted.length == 1) {
      final character = inserted;
      final pair = _pairAt(caret, character);
      if (pair != null) {
        _pairs.remove(pair);
        if (pair.closing.length > 1) {
          _pairs.add(pair.copyWith(
              close: pair.close + 1, closing: pair.closing.substring(1)));
        }
        return _finish(
            oldValue,
            oldValue.copyWith(
                selection: TextSelection.collapsed(offset: caret + 1),
                composing: TextRange.empty),
            editableStart,
            end);
      }
      // Ordinary letters do not need lexical state. In particular, typing
      // during a large background invalidation must not scan every line.
      const closing = {'(': ')', '[': ']', '{': '}', '"': '"', "'": "'"};
      final closer = closing[character];
      if (closer != null) {
        final analysis = model ?? _analyze(oldValue.text);
        final context = analysis.contextAt(caret);
        if (!context.inString &&
            !context.inComment &&
            _canPairAt(oldValue.text, caret, character)) {
          final triple = (character == '"' || character == "'") &&
              caret >= 2 &&
              oldValue.text.substring(caret - 2, caret) == character * 2;
          final tail = triple ? character * 3 : closer;
          final result = _replace(oldValue, caret, caret, '$character$tail',
              caret: caret + 1);
          final accepted = _finish(oldValue, result, editableStart, end);
          if (accepted.text == result.text) {
            _pairs.add(_InsertedPair(
                open: triple ? caret - 2 : caret,
                close: caret + 1,
                opening: triple ? character * 3 : character,
                closing: tail));
          }
          return accepted;
        }
      }
      if (character == ':' || character == ' ') {
        final adjusted = _clauseDedent(newValue);
        if (adjusted != newValue) {
          final accepted = _finish(oldValue, adjusted, editableStart, end);
          if (accepted.text == adjusted.text) {
            _dedentedLines.add(
                _lineStart(accepted.text, accepted.selection.extentOffset));
          }
          return accepted;
        }
      }
    }
    return _finish(oldValue, newValue, editableStart, end);
  }

  TextEditingValue _normalizeKeyboardPunctuation(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (oldValue.text == newValue.text) return newValue;
    final change = _TextChange.between(oldValue.text, newValue.text);
    final lineStart = _lineStart(oldValue.text, change.start);
    final inIndentation = oldValue.text
        .substring(lineStart, change.end)
        .codeUnits
        .every((code) => code == 32 || code == 9);
    // Some IMEs replace the second space while retaining the first and final
    // spaces in their editing delta. Detect the surrounding whitespace too.
    if (inIndentation &&
        change.removed == ' ' &&
        change.inserted == '.' &&
        change.start > lineStart &&
        oldValue.text[change.start - 1] == ' ' &&
        oldValue.text.startsWith(' ', change.end)) {
      return newValue.copyWith(text: oldValue.text);
    }
    if (!change.inserted.contains(RegExp('[‘’“”]'))) return newValue;
    var text = newValue.text;
    String? smartClosing;
    for (var index = change.start;
        index < change.start + change.inserted.length;
        index++) {
      final character = text[index];
      if (!'‘’“”'.contains(character)) continue;
      final quote = '‘’'.contains(character) ? "'" : '"';
      final context = _analyze(text.substring(0, index)).contextAt(index);
      final matchingSmartClose = character == smartClosing;
      if ((!context.inString && !context.inComment) ||
          matchingSmartClose ||
          _pairAt(index, quote) != null) {
        text = text.replaceRange(index, index + 1, quote);
        var backslashes = 0;
        for (var previous = index - 1;
            previous >= 0 && text[previous] == '\\';
            previous--) {
          backslashes++;
        }
        if (!matchingSmartClose) {
          smartClosing = quote == '"' ? '”' : '’';
        } else if (backslashes.isEven) {
          smartClosing = null;
        }
      }
    }
    return newValue.copyWith(text: text);
  }

  TextEditingValue enter(TextEditingValue value,
      {PythonIndentModel? model, int editableStart = 0, int? editableEnd}) {
    _prepare(value);
    if (!_valid(value) || _composing(value)) return value;
    return _finish(value, _enter(value, model: model), editableStart,
        editableEnd ?? value.text.length);
  }

  TextEditingValue _enter(TextEditingValue value, {PythonIndentModel? model}) {
    final selection = value.selection;
    final caret = selection.start;
    final base = selection.isCollapsed
        ? value
        : _replace(value, selection.start, selection.end, '', caret: caret);
    final analysis =
        selection.isCollapsed && model != null ? model : _analyze(base.text);
    final context = analysis.contextAt(caret);
    final lineStart = _lineStart(base.text, caret);
    final lineEnd = _lineEnd(base.text, caret);
    final line = base.text.substring(lineStart, lineEnd);
    final prefix = _whitespace(line);
    final newline = _lineEnding(base.text);
    final left = base.text.substring(lineStart, caret);
    final right = base.text.substring(caret, lineEnd);

    // Inside a real line's indentation, keep the original line intact.
    if (line.trim().isNotEmpty && caret < lineStart + prefix.length) {
      return _replace(base, lineStart, lineStart, newline,
          caret: caret + newline.length);
    }

    var indentation = prefix;
    final inLiteral = context.inString || context.inComment;
    if (context.opensBlock && !context.inString) {
      indentation += analysis.indentUnit;
    } else if (!inLiteral) {
      if (context.bracketDepth > 0 || context.explicitContinuation) {
        indentation += analysis.indentUnit;
      } else if (context.terminalStatement) {
        indentation = _prefixAtColumn(prefix,
            math.max(0, pythonIndentColumns(prefix) - _indentStep(analysis)),
            usesTabs: analysis.usesTabs);
      }
    }

    const bracketPairs = {'(': ')', '[': ']', '{': '}'};
    final preceding = left.isEmpty ? '' : left[left.length - 1];
    if (!inLiteral &&
        bracketPairs[preceding] != null &&
        right.startsWith(bracketPairs[preceding]!)) {
      final middle = '$newline${prefix + analysis.indentUnit}';
      return _replace(base, caret, caret, '$middle$newline$prefix',
          caret: caret + middle.length);
    }
    if (line.trim().isEmpty) {
      return _replace(base, lineStart, lineEnd, '$newline$indentation',
          caret: lineStart + newline.length + indentation.length);
    }
    return _replace(base, caret, caret, '$newline$indentation',
        caret: caret + newline.length + indentation.length);
  }

  TextEditingValue backspace(TextEditingValue value,
      {PythonIndentModel? model,
      int editableStart = 0,
      int? editableEnd,
      int count = 1}) {
    _prepare(value);
    if (!_valid(value) || _composing(value) || count < 1) return value;
    final selection = value.selection;
    final end = editableEnd ?? value.text.length;
    if (!selection.isCollapsed) {
      return _finish(value, _replace(value, selection.start, selection.end, ''),
          editableStart, end);
    }
    final caret = selection.extentOffset;
    if (caret == 0) return value;
    if (count > 1) {
      return _finish(
          value,
          _replace(value, math.max(editableStart, caret - count), caret, ''),
          editableStart,
          end);
    }
    for (final pair in _pairs) {
      if (pair.close == caret &&
          pair.open + pair.opening.length == caret &&
          value.text.startsWith(pair.opening, pair.open) &&
          value.text.startsWith(pair.closing, pair.close)) {
        return _finish(
            value,
            _replace(value, pair.open, pair.close + pair.closing.length, ''),
            editableStart,
            end);
      }
    }
    final lineStart = _lineStart(value.text, caret);
    final prefix = value.text.substring(lineStart, caret);
    if (prefix.isEmpty) {
      final amount = _newlineBefore(value.text, caret);
      return _finish(
          value,
          _replace(value, caret - math.max(1, amount), caret, ''),
          editableStart,
          end);
    }
    if (_whitespace(prefix).length == prefix.length) {
      if (prefix.endsWith('\t')) {
        return _finish(
            value, _replace(value, caret - 1, caret, ''), editableStart, end);
      }
      final analysis = model ?? _analyze(value.text);
      final context = analysis.contextAt(caret);
      final column = pythonIndentColumns(prefix);
      final stops = context.indentStops.where((stop) => stop < column).toList();
      final unit = _indentStep(analysis);
      final ordinary = ((column - 1) ~/ unit) * unit;
      final mixed = analysis.hasMixedIndentWidths;
      final target = mixed && stops.isNotEmpty ? stops.last : ordinary;
      final kept = _prefixLengthAtColumn(prefix, target);
      return _finish(value, _replace(value, lineStart + kept, caret, ''),
          editableStart, end);
    }
    final removed = value.text.substring(0, caret).characters.last.length;
    return _finish(
        value, _replace(value, caret - removed, caret, ''), editableStart, end);
  }

  TextEditingValue indent(TextEditingValue value,
          {PythonIndentModel? model,
          int editableStart = 0,
          int? editableEnd}) =>
      _shift(value,
          decrease: false,
          model: model,
          editableStart: editableStart,
          editableEnd: editableEnd);

  TextEditingValue dedent(TextEditingValue value,
          {PythonIndentModel? model,
          int editableStart = 0,
          int? editableEnd}) =>
      _shift(value,
          decrease: true,
          model: model,
          editableStart: editableStart,
          editableEnd: editableEnd);

  TextEditingValue _shift(TextEditingValue value,
      {required bool decrease,
      PythonIndentModel? model,
      int editableStart = 0,
      int? editableEnd}) {
    _prepare(value);
    if (!_valid(value) || _composing(value)) return value;
    final analysis = model ?? _analyze(value.text);
    final rows = _selectedRows(value);
    final amount = _indentStep(analysis);
    final edits = <_Replacement>[];
    for (final row in rows) {
      if (!value.selection.isCollapsed && row.text.trim().isEmpty) continue;
      final prefix = _whitespace(row.text);
      final width = pythonIndentColumns(prefix);
      final target = decrease ? math.max(0, width - amount) : width + amount;
      final replacement = _indentText(target, analysis.usesTabs);
      edits
          .add(_Replacement(row.start, row.start + prefix.length, replacement));
    }
    return _finish(value, _applyReplacements(value, edits), editableStart,
        editableEnd ?? value.text.length);
  }

  TextEditingValue paste(TextEditingValue value, String inserted,
      {bool reindent = true,
      bool normalizeUnsupportedWhitespace = true,
      PythonIndentModel? model,
      int editableStart = 0,
      int? editableEnd}) {
    _prepare(value);
    if (!_valid(value) || _composing(value)) return value;
    final end = editableEnd ?? value.text.length;
    if (!reindent) {
      return _finish(
          value,
          _replace(value, value.selection.start, value.selection.end, inserted),
          editableStart,
          end);
    }
    final analysis = model ?? _analyze(value.text);
    final start = value.selection.start;
    final lineStart = _lineStart(value.text, start);
    final preceding = value.text.substring(lineStart, start);
    final inIndent = _whitespace(preceding).length == preceding.length;
    final destinationPrefix = _whitespace(value.text.substring(lineStart));
    final base = pythonIndentColumns(destinationPrefix);
    final precedingWidth = pythonIndentColumns(preceding);
    final rows = inserted.replaceAll(RegExp(r'\r\n?|\n'), '\n').split('\n');
    final pastedSource =
        value.text.replaceRange(start, value.selection.end, rows.join('\n'));
    final pastedModel = _analyze(pastedSource);
    var rowOffset = start;
    final literalRows = <bool>[];
    for (final row in rows) {
      final context = pastedModel.contextAt(rowOffset);
      literalRows.add(context.inString);
      rowOffset += row.length + 1;
    }
    final normalized = <String>[
      for (var row = 0; row < rows.length; row++)
        normalizeUnsupportedWhitespace && !literalRows[row]
            ? _normalizeLeadingSpaces(rows[row])
            : rows[row],
    ];
    final widths = <int>[];
    for (var row = 0; row < normalized.length; row++) {
      if (literalRows[row]) continue;
      final text = normalized[row];
      if (text.trim().isEmpty) continue;
      final width = pythonIndentColumns(_whitespace(text));
      // An inline first row is not a full source line. At a line's
      // indentation, however, column zero is meaningful: excluding it
      // would flatten the body of an ordinary pasted block.
      if (!inIndent && row == 0 && normalized.length > 1) continue;
      widths.add(width);
    }
    final common = widths.isEmpty ? 0 : widths.reduce(math.min);
    final rebased = <String>[];
    for (var index = 0; index < normalized.length; index++) {
      final row = normalized[index];
      if (literalRows[index]) {
        rebased.add(row);
        continue;
      }
      if (index == 0 && !inIndent) {
        rebased.add(row);
        continue;
      }
      final prefix = _whitespace(row);
      if (row.trim().isEmpty) {
        final suffix = value.text.substring(value.selection.end);
        final joinsExistingLine = index == normalized.length - 1 &&
            suffix.isNotEmpty &&
            !suffix.startsWith(RegExp(r'[\r\n]'));
        // Retain the destination line's indentation when a trailing newline
        // puts its existing code after the pasted complete lines.
        final suffixIndent = pythonIndentColumns(_whitespace(suffix));
        rebased.add(joinsExistingLine
            ? _indentText(math.max(0, base - suffixIndent), analysis.usesTabs)
            : '');
        continue;
      }
      final relative = math.max(0, pythonIndentColumns(prefix) - common);
      final column = relative + (index == 0 ? base - precedingWidth : base);
      rebased.add(
          '${_indentText(column, analysis.usesTabs)}${row.substring(prefix.length)}');
    }
    return _finish(
        value,
        _replace(value, start, value.selection.end,
            rebased.join(_lineEnding(value.text))),
        editableStart,
        end);
  }

  TextEditingValue convertIndentation(TextEditingValue value,
      {required int indentSize,
      required bool usesTabs,
      PythonIndentModel? model,
      int editableStart = 0,
      int? editableEnd}) {
    _prepare(value);
    if (!_valid(value) || _composing(value) || indentSize < 1) return value;
    final analysis = model ?? _analyze(value.text);
    final edits = <_Replacement>[];
    for (final line in analysis.lines) {
      final kind = line.kind.name;
      if (kind != 'code' && kind != 'continuation') continue;
      final oldWidth = pythonIndentColumns(line.indentPrefix);
      final target =
          (oldWidth ~/ _indentStep(analysis)) * (usesTabs ? 8 : indentSize) +
              oldWidth % _indentStep(analysis);
      edits.add(_Replacement(
          line.startOffset,
          line.startOffset + line.indentPrefix.length,
          _indentText(target, usesTabs)));
    }
    return _finish(value, _applyReplacements(value, edits), editableStart,
        editableEnd ?? value.text.length);
  }

  TextEditingValue cleanupOnCaretMove(
      TextEditingValue oldValue, TextEditingValue newValue,
      {int editableStart = 0, int? editableEnd}) {
    _prepare(oldValue);
    if (!_valid(oldValue) ||
        !_valid(newValue) ||
        _composing(newValue) ||
        oldValue.text != newValue.text) {
      return newValue;
    }
    final oldStart = _lineStart(oldValue.text, oldValue.selection.extentOffset);
    final newStart = _lineStart(newValue.text, newValue.selection.extentOffset);
    if (oldStart == newStart) {
      return _finish(oldValue, newValue, editableStart,
          editableEnd ?? oldValue.text.length);
    }
    final oldEnd = _lineEnd(oldValue.text, oldValue.selection.extentOffset);
    final oldLine = oldValue.text.substring(oldStart, oldEnd);
    if (oldLine.isEmpty || _whitespace(oldLine).length != oldLine.length) {
      return _finish(oldValue, newValue, editableStart,
          editableEnd ?? oldValue.text.length);
    }
    final result =
        _applyReplacements(newValue, [_Replacement(oldStart, oldEnd, '')]);
    return _finish(
        oldValue, result, editableStart, editableEnd ?? oldValue.text.length);
  }

  TextEditingValue _clauseDedent(TextEditingValue value) {
    final caret = value.selection.extentOffset;
    final start = _lineStart(value.text, caret);
    if (_dedentedLines.contains(start)) return value;
    final before = value.text.substring(start, caret);
    final match = RegExp(r'^([ \t]*)(else|elif|except|finally|case)([: ])$')
        .firstMatch(before);
    if (match == null) return value;
    final analysis = _analyze(value.text);
    final context = analysis.contextAt(start + match.group(1)!.length);
    final target = context.compatibleClauseTarget(match.group(2)!);
    final current = pythonIndentColumns(match.group(1)!);
    if (target == null || target >= current) return value;
    final stops = context.indentStops.where((stop) => stop < current).toList();
    final previous = stops.isEmpty
        ? math.max(0, current - _indentStep(analysis))
        : stops.last;
    final destination = math.max(target, previous);
    final replacement = _indentText(destination, analysis.usesTabs);
    return _replace(value, start, start + match.group(1)!.length, replacement,
        caret: caret + replacement.length - match.group(1)!.length);
  }

  PythonIndentModel _analyze(String text) =>
      PythonIndentModel.analyze(text, options: options);

  void _prepare(TextEditingValue value) {
    if (_lastText != null && _lastText != value.text) reset();
    _lastText = value.text;
  }

  TextEditingValue _finish(
      TextEditingValue oldValue, TextEditingValue result, int start, int end) {
    if (oldValue.text == result.text) {
      _lastText = result.text;
      return result;
    }
    start = start.clamp(0, oldValue.text.length);
    end = end.clamp(start, oldValue.text.length);
    final prefix = oldValue.text.substring(0, start);
    final suffix = oldValue.text.substring(end);
    if (result.text.length < prefix.length + suffix.length ||
        !result.text.startsWith(prefix) ||
        !result.text.endsWith(suffix)) {
      return oldValue;
    }
    final change = _TextChange.between(oldValue.text, result.text);
    final delta = result.text.length - oldValue.text.length;
    final updatedPairs = <_InsertedPair>[];
    for (final pair in _pairs) {
      if (change.end <= pair.open) {
        updatedPairs.add(
            pair.copyWith(open: pair.open + delta, close: pair.close + delta));
      } else if (change.start >= pair.open + pair.opening.length &&
          change.end <= pair.close) {
        updatedPairs.add(pair.copyWith(close: pair.close + delta));
      } else if (change.start >= pair.close + pair.closing.length) {
        updatedPairs.add(pair);
      }
    }
    _pairs
      ..clear()
      ..addAll(updatedPairs);
    final dedented = _dedentedLines.map((line) {
      // Inserting indentation at the start of this same line does not move its
      // identity. In particular, respect a user re-indenting a clause.
      final sameLineInsertion = change.start == line &&
          change.end == line &&
          !change.inserted.contains(RegExp(r'[\r\n]'));
      return change.end <= line && !sameLineInsertion ? line + delta : line;
    }).toSet();
    _dedentedLines
      ..clear()
      ..addAll(dedented);
    _lastText = result.text;
    return result;
  }

  _InsertedPair? _pairAt(int caret, String character) {
    for (final pair in _pairs) {
      if (pair.close == caret && pair.closing.startsWith(character)) {
        return pair;
      }
    }
    return null;
  }
}

// Python expands tabs to eight columns regardless of the visual tab width.
// The configured space width must never turn a tab-indented step into spaces.
int _indentStep(PythonIndentModel model) =>
    model.usesTabs ? 8 : model.effectiveIndentSize;

bool _canPairAt(String text, int caret, String opener) {
  if (opener != "'" && opener != '"') return true;
  bool word(String character) =>
      RegExp(r'[\w\u0080-\uffff]').hasMatch(character);
  if (caret < text.length && word(text[caret])) return false;
  if (caret == 0 || !word(text[caret - 1])) return true;
  // Python permits a small set of string prefixes. Ordinary identifiers and
  // contractions should not acquire an extra closing quote.
  final before = text.substring(0, caret);
  final prefix = RegExp(r'(?:^|[^\w\u0080-\uffff])([rRuUbBfFtT]{1,2})$')
      .firstMatch(before)
      ?.group(1)
      ?.toLowerCase();
  return const {'r', 'u', 'b', 'f', 't', 'br', 'rb', 'fr', 'rf', 'tr', 'rt'}
      .contains(prefix);
}

bool _valid(TextEditingValue value) =>
    value.selection.isValid &&
    value.selection.start >= 0 &&
    value.selection.end <= value.text.length;
bool _composing(TextEditingValue value) =>
    value.composing.isValid && !value.composing.isCollapsed;
String _whitespace(String text) =>
    RegExp(r'^[ \t]*').firstMatch(text)!.group(0)!;
String _lineEnding(String text) =>
    RegExp(r'\r\n|\r|\n').firstMatch(text)?.group(0) ?? '\n';
int _lineStart(String text, int caret) {
  var start = caret.clamp(0, text.length);
  while (start > 0 && text[start - 1] != '\n' && text[start - 1] != '\r') {
    start--;
  }
  return start;
}

int _lineEnd(String text, int caret) {
  var end = caret.clamp(0, text.length);
  while (end < text.length && text[end] != '\n' && text[end] != '\r') {
    end++;
  }
  return end;
}

int _newlineBefore(String text, int caret) {
  if (caret >= 2 && text.substring(caret - 2, caret) == '\r\n') return 2;
  if (caret > 0 && (text[caret - 1] == '\n' || text[caret - 1] == '\r')) {
    return 1;
  }
  return 0;
}

int _newlineAt(String text, int offset) =>
    text.startsWith('\r\n', offset) ? 2 : 1;
int _prefixLengthAtColumn(String prefix, int column) {
  var width = 0;
  var length = 0;
  while (length < prefix.length) {
    final next = width + (prefix[length] == '\t' ? 8 - width % 8 : 1);
    if (next > column) break;
    width = next;
    length++;
  }
  return length;
}

String _indentText(int column, bool tabs) =>
    tabs ? '${'\t' * (column ~/ 8)}${' ' * (column % 8)}' : ' ' * column;
String _prefixAtColumn(String prefix, int column, {required bool usesTabs}) =>
    _indentText(column, usesTabs);
String _normalizeLeadingSpaces(String text) {
  var end = 0;
  while (end < text.length &&
      RegExp(r'[ \t\u00a0\u200b\u200c\u200d\u2060\u3000\ufeff]')
          .hasMatch(text[end])) {
    end++;
  }
  return text.substring(0, end).replaceAll(
          RegExp(r'[\u00a0\u200b\u200c\u200d\u2060\u3000\ufeff]'), ' ') +
      text.substring(end);
}

bool _isSelectionReplacement(
    TextEditingValue oldValue, TextEditingValue newValue, _TextChange change) {
  final start = oldValue.selection.start;
  final end = oldValue.selection.end;
  final length = newValue.text.length - oldValue.text.length + end - start;
  return length >= 0 &&
      newValue.selection.isCollapsed &&
      newValue.selection.extentOffset == start + length &&
      newValue.text.substring(0, start) == oldValue.text.substring(0, start) &&
      newValue.text.substring(start + length) == oldValue.text.substring(end);
}

TextEditingValue _replace(
        TextEditingValue value, int start, int end, String inserted,
        {int? caret}) =>
    TextEditingValue(
        text: value.text.replaceRange(start, end, inserted),
        selection:
            TextSelection.collapsed(offset: caret ?? start + inserted.length));
TextEditingValue _applyReplacements(
    TextEditingValue value, List<_Replacement> edits) {
  edits.sort((a, b) => a.start.compareTo(b.start));
  int map(int offset) {
    var delta = 0;
    for (final edit in edits) {
      if (offset < edit.start) break;
      if (offset <= edit.end) return edit.start + delta + edit.text.length;
      delta += edit.text.length - (edit.end - edit.start);
    }
    return offset + delta;
  }

  var text = value.text;
  for (final edit in edits.reversed) {
    text = text.replaceRange(edit.start, edit.end, edit.text);
  }
  return TextEditingValue(
      text: text,
      selection: TextSelection(
          baseOffset: map(value.selection.baseOffset),
          extentOffset: map(value.selection.extentOffset)));
}

List<_SelectedRow> _selectedRows(TextEditingValue value) {
  final start = _lineStart(value.text, value.selection.start);
  var end = value.selection.end;
  if (!value.selection.isCollapsed &&
      end > start &&
      _lineStart(value.text, end) == end) {
    end -= _newlineBefore(value.text, end);
  }
  end = _lineEnd(value.text, end);
  final rows = <_SelectedRow>[];
  var position = start;
  while (position <= end) {
    final rowEnd = _lineEnd(value.text, position);
    rows.add(_SelectedRow(position, value.text.substring(position, rowEnd)));
    if (rowEnd >= end) break;
    position = rowEnd + _newlineAt(value.text, rowEnd);
  }
  return rows;
}

class _SelectedRow {
  const _SelectedRow(this.start, this.text);
  final int start;
  final String text;
}

class _Replacement {
  const _Replacement(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

class _TextChange {
  const _TextChange(this.start, this.end, this.removed, this.inserted);
  factory _TextChange.between(String oldText, String newText) {
    var start = 0;
    while (start < oldText.length &&
        start < newText.length &&
        oldText[start] == newText[start]) {
      start++;
    }
    var oldEnd = oldText.length;
    var newEnd = newText.length;
    while (oldEnd > start &&
        newEnd > start &&
        oldText[oldEnd - 1] == newText[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    return _TextChange(start, oldEnd, oldText.substring(start, oldEnd),
        newText.substring(start, newEnd));
  }
  final int start;
  final int end;
  final String removed;
  final String inserted;
}

class _InsertedPair {
  const _InsertedPair(
      {required this.open,
      required this.close,
      required this.opening,
      required this.closing});
  final int open;
  final int close;
  final String opening;
  final String closing;
  _InsertedPair copyWith({int? open, int? close, String? closing}) =>
      _InsertedPair(
          open: open ?? this.open,
          close: close ?? this.close,
          opening: opening,
          closing: closing ?? this.closing);
}
