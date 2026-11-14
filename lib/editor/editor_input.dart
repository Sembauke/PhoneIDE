part of 'editor.dart';

class _EditorIndentFormatter extends TextInputFormatter {
  const _EditorIndentFormatter(
      {required this.language, required this.indentSize});

  final String language;
  final int indentSize;
  static final _leadingWhitespace = RegExp(r'^[ \t]*');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final selection = oldValue.selection;
    if (!selection.isValid ||
        selection.end > oldValue.text.length ||
        !newValue.selection.isValid ||
        !newValue.selection.isCollapsed ||
        (newValue.composing.isValid && !newValue.composing.isCollapsed)) {
      return newValue;
    }
    final dedented = _backspaceIndentation(oldValue, newValue);
    if (dedented != null) return dedented;
    final start = selection.start;
    final end = selection.end;
    final insertedLength =
        newValue.text.length - (oldValue.text.length - (end - start));
    if ((insertedLength != 1 && insertedLength != 2) ||
        newValue.selection.extentOffset != start + insertedLength ||
        start + insertedLength > newValue.text.length) {
      return newValue;
    }
    final inserted = newValue.text.substring(start, start + insertedLength);
    if ((inserted != '\n' && inserted != '\r\n') ||
        newValue.text.substring(0, start) !=
            oldValue.text.substring(0, start) ||
        newValue.text.substring(start + insertedLength) !=
            oldValue.text.substring(end)) {
      return newValue;
    }

    final beforeCaret = oldValue.text.substring(0, start);
    final line = beforeCaret.substring(beforeCaret.lastIndexOf('\n') + 1);
    var indentation = _leadingWhitespace.firstMatch(line)!.group(0)!;
    final openings = _blockOpeningLines(beforeCaret, language);
    if (openings.contains('\n'.allMatches(beforeCaret).length)) {
      indentation += indentation.contains('\t') ? '\t' : ' ' * indentSize;
    }
    if (indentation.isEmpty) return newValue;
    final caret = newValue.selection.extentOffset;
    return newValue.copyWith(
      text: newValue.text.replaceRange(caret, caret, indentation),
      selection: TextSelection.collapsed(
          offset: caret + indentation.length,
          affinity: newValue.selection.affinity),
      composing: TextRange.empty,
    );
  }

  TextEditingValue? _backspaceIndentation(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final caret = oldValue.selection.extentOffset;
    if (!oldValue.selection.isCollapsed ||
        caret == 0 ||
        newValue.text.length != oldValue.text.length - 1 ||
        newValue.selection.extentOffset != caret - 1 ||
        newValue.text != oldValue.text.replaceRange(caret - 1, caret, '')) {
      return null;
    }
    final lineStart = oldValue.text.lastIndexOf('\n', caret - 1) + 1;
    final prefix = oldValue.text.substring(lineStart, caret);
    if (prefix.isEmpty ||
        _leadingWhitespace.firstMatch(prefix)!.end != prefix.length) {
      return null;
    }

    var column = 0;
    for (final character in prefix.codeUnits) {
      column += character == 9 ? indentSize - column % indentSize : 1;
    }
    final targetColumn = ((column - 1) ~/ indentSize) * indentSize;
    var retainedLength = 0;
    column = 0;
    while (retainedLength < prefix.length) {
      column += prefix.codeUnitAt(retainedLength) == 9
          ? indentSize - column % indentSize
          : 1;
      if (column > targetColumn) break;
      retainedLength++;
    }
    final target = lineStart + retainedLength;
    return newValue.copyWith(
      text: oldValue.text.replaceRange(target, caret, ''),
      selection: TextSelection.collapsed(
          offset: target, affinity: newValue.selection.affinity),
      composing: TextRange.empty,
    );
  }
}
