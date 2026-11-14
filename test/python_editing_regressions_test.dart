import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/python_input.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

TextEditingValue value(String text, [int? caret]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret ?? text.length));
TextEditingValue insert(
        PythonInputEngine engine, TextEditingValue before, String text) =>
    engine.formatEditUpdate(
        before,
        value(
            before.text.replaceRange(
                before.selection.start, before.selection.end, text),
            before.selection.start + text.length));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('single-line input preserves spaces within code', () {
    expect(insert(PythonInputEngine(), value('print(a,'), '  b').text,
        'print(a,  b');
    expect(PythonInputEngine().paste(value('print(a,'), '  b').text,
        'print(a,  b');
  });
  test('pasting a complete block preserves body indentation', () {
    expect(PythonInputEngine().paste(value(''), 'def f():\n    return 1').text,
        'def f():\n    return 1');
    expect(
        PythonInputEngine()
            .paste(value('if ready:\n    '), 'def f():\n    return 1')
            .text,
        'if ready:\n    def f():\n        return 1');
  });
  for (final column in [0, 2, 4]) {
    test('whole-line paste preserves destination indentation at column $column',
        () {
      const text = 'def f():\n    return 1';
      expect(
          PythonInputEngine()
              .paste(value(text, 9 + column), 'x = 1\ny = 2\n')
              .text,
          'def f():\n    x = 1\n    y = 2\n    return 1');
    });
  }
  test('Tab and Enter both use real tabs in an initially unindented file', () {
    final engine =
        PythonInputEngine(options: const PythonIndentOptions(usesTabs: true));
    expect(engine.indent(value('x = 1')).text, '\tx = 1');
    expect(engine.enter(value('if x:')).text, 'if x:\n\t');
    expect(
        engine.enter(value('if x:\n\treturn 1')).text, 'if x:\n\treturn 1\n');
  });
  test(
      'indentation conversion uses tab columns rather than configured space width',
      () {
    final engine = PythonInputEngine();
    expect(
        engine
            .convertIndentation(value('if x:\n    work()'),
                indentSize: 4, usesTabs: true)
            .text,
        'if x:\n\twork()');
  });
  test('mixed selection dedents each row independently', () {
    const text = 'first\n    second\n        third';
    final selected = value(text).copyWith(
        selection:
            const TextSelection(baseOffset: 0, extentOffset: text.length));
    expect(
        PythonInputEngine().dedent(selected).text, 'first\nsecond\n    third');
  });
  for (final sample in [('don', 3, "'", "don'"), ('abc', 0, '"', '"abc')]) {
    test('quotes do not pair against word text ${sample.$1}', () {
      expect(
          insert(PythonInputEngine(), value(sample.$1, sample.$2), sample.$3)
              .text,
          sample.$4);
    });
  }
  testWidgets('hardware arrows leave indentation boundaries and blank lines',
      (tester) async {
    final state = await open(tester, 'a\n    b\n\nc');
    for (final sample in [
      (6, LogicalKeyboardKey.arrowRight, 7),
      (2, LogicalKeyboardKey.arrowLeft, 1),
      (8, LogicalKeyboardKey.arrowLeft, 7),
      (8, LogicalKeyboardKey.arrowRight, 9)
    ]) {
      state.inController.selection = TextSelection.collapsed(offset: sample.$1);
      await tester.sendKeyEvent(sample.$2);
      expect(state.inController.selection.extentOffset, sample.$3,
          reason: 'Caret ${sample.$1} and ${sample.$2}');
    }
  });
  testWidgets('arrow fallback stays inside an editable region', (tester) async {
    final state = await open(tester, 'if ready:\n    work()\nafter()',
        region: EditorRegionOptions(start: 1, end: 3));
    expect(state.inController.text, '    work()');
    for (final sample in [
      (0, LogicalKeyboardKey.arrowLeft),
      (state.inController.text.length, LogicalKeyboardKey.arrowRight),
    ]) {
      state.inController.selection = TextSelection.collapsed(offset: sample.$1);
      await tester.sendKeyEvent(sample.$2);
      expect(state.inController.selection.extentOffset, sample.$1);
    }
  });

  testWidgets('composing text retains inserted bracket ownership',
      (tester) async {
    final state = await open(tester, '');
    tester.testTextInput.updateEditingValue(value('('));
    expect(state.inController.text, '()');
    tester.testTextInput.updateEditingValue(value('(foo)', 4)
        .copyWith(composing: const TextRange(start: 1, end: 4)));
    tester.testTextInput.updateEditingValue(value('(foo)', 4));
    tester.testTextInput.updateEditingValue(value('(foo))', 5));
    expect(state.inController.text, '(foo)');
    expect(state.inController.selection.extentOffset, 5);
  });
}

Future<EditorState> open(WidgetTester tester, String source,
    {EditorRegionOptions? region}) async {
  final key = GlobalKey<EditorState>();
  final editor = Editor(
      key: key,
      path: 'editing-review.py',
      defaultLanguage: 'python',
      defaultValue: source,
      options: EditorOptions(regionOptions: region));
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
  await settleEditor(tester);
  final state = key.currentState!;
  await tester.showKeyboard(find.byWidgetPredicate((widget) =>
      widget is TextField && widget.controller == state.inController));
  state.inController.selection =
      TextSelection.collapsed(offset: state.inController.text.length);
  await tester.pump();
  addTearDown(() async {
    await editor.onTextChange.close();
    await editor.textfieldData.close();
    await editor.editableRegion.close();
  });
  return state;
}
