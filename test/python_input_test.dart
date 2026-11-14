import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/python_indentation.dart';
import 'package:phone_ide/editor/python_input.dart';

TextEditingValue _value(Map<String, dynamic> data) => TextEditingValue(
      text: data['text'] as String,
      selection: TextSelection(
        baseOffset: data['selectionStart'] as int,
        extentOffset: data['selectionEnd'] as int,
      ),
    );

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/typing_cases.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final raw in fixture['cases'] as List<dynamic>) {
    final sample = raw as Map<String, dynamic>;
    test(sample['name'] as String, () {
      final config = sample['options'] as Map<String, dynamic>? ?? {};
      final engine = PythonInputEngine(
        options: PythonIndentOptions(
          indentSize: config['indentSize'] as int? ?? 4,
          usesTabs: config['usesTabs'] as bool? ?? false,
          projectIndentSize: config['projectIndentSize'] as int?,
          projectUsesTabs: config['projectUsesTabs'] as bool?,
        ),
      );
      var value = _value(sample['initial'] as Map<String, dynamic>);
      final bounds = sample['bounds'] as Map<String, dynamic>?;
      final start = bounds?['start'] as int? ?? 0;
      var end = bounds?['end'] as int? ?? value.text.length;
      for (final rawOperation in sample['operations'] as List<dynamic>) {
        final operation = rawOperation as Map<String, dynamic>;
        final beforeLength = value.text.length;
        switch (operation['type']) {
          case 'insert':
            final inserted = operation['text'] as String;
            final selection = value.selection;
            final caret = selection.start + inserted.length;
            final candidate = TextEditingValue(
              text: value.text
                  .replaceRange(selection.start, selection.end, inserted),
              selection: TextSelection.collapsed(offset: caret),
              composing: operation['composing'] == true
                  ? TextRange(start: selection.start, end: caret)
                  : TextRange.empty,
            );
            value = engine.formatEditUpdate(value, candidate,
                editableStart: start, editableEnd: end);
          case 'deleteBackward':
            final count = operation['count'] as int;
            final caret = value.selection.extentOffset;
            final candidate = TextEditingValue(
              text: value.text.replaceRange(caret - count, caret, ''),
              selection: TextSelection.collapsed(offset: caret - count),
            );
            value = engine.formatEditUpdate(value, candidate,
                editableStart: start, editableEnd: end);
          case 'selection':
            final candidate = value.copyWith(
              selection: TextSelection(
                baseOffset: operation['start'] as int,
                extentOffset: operation['end'] as int,
              ),
            );
            value = engine.cleanupOnCaretMove(value, candidate,
                editableStart: start, editableEnd: end);
          case 'command':
            switch (operation['command']) {
              case 'enter':
                value =
                    engine.enter(value, editableStart: start, editableEnd: end);
              case 'backspace':
                value = engine.backspace(value,
                    count: operation['count'] as int? ?? 1,
                    editableStart: start,
                    editableEnd: end);
              case 'indent':
                value = engine.indent(value,
                    editableStart: start, editableEnd: end);
              case 'dedent':
                value = engine.dedent(value,
                    editableStart: start, editableEnd: end);
              case 'paste':
                value = engine.paste(value, operation['text'] as String,
                    reindent: operation['reindent'] as bool? ?? true,
                    editableStart: start,
                    editableEnd: end);
              case 'convertIndentation':
                value = engine.convertIndentation(value,
                    indentSize: operation['indentSize'] as int,
                    usesTabs: operation['usesTabs'] as bool,
                    editableStart: start,
                    editableEnd: end);
              default:
                fail('Unknown fixture command: ${operation['command']}');
            }
          default:
            fail('Unknown fixture operation: ${operation['type']}');
        }
        end += value.text.length - beforeLength;
        if (operation['expectedAfter'] case final Map<String, dynamic> after) {
          final expected = _value(after);
          expect(value.text, expected.text,
              reason:
                  'Required intermediate source after ${operation['type']}');
          expect(value.selection, expected.selection,
              reason: 'Required intermediate caret after ${operation['type']}');
        }
      }
      final expected = _value(sample['expected'] as Map<String, dynamic>);
      expect(value.text, expected.text);
      expect(value.selection, expected.selection);
      if (sample['expectedComposing']
          case final Map<String, dynamic> composing) {
        expect(
            value.composing,
            TextRange(
                start: composing['start'] as int,
                end: composing['end'] as int));
      } else {
        expect(value.composing, TextRange.empty);
      }
    });
  }
}
