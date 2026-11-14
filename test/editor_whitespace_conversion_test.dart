import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

Future<EditorState> _mount(WidgetTester tester,
    {String source = '    '}) async {
  final key = GlobalKey<EditorState>();
  final editor = Editor(
      key: key,
      path: 'convert.py',
      defaultLanguage: 'python',
      defaultValue: source,
      options: EditorOptions());
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
  await settleEditor(tester);
  addTearDown(() async {
    await editor.onTextChange.close();
    await editor.textfieldData.close();
    await editor.editableRegion.close();
  });
  await tester.showKeyboard(find.byType(TextField));
  final state = key.currentState!;
  state.inController.selection = TextSelection.collapsed(offset: source.length);
  await tester.pump();
  return state;
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.text('Convert indentation?'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, label));
  await tester.pumpAndSettle(const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final native in [true, false]) {
    testWidgets(
        '${native ? 'native' : 'public'} paste converts only after the visible choice and rebases once',
        (tester) async {
      final state = await _mount(tester);
      if (native) {
        tester.testTextInput.updateEditingValue(const TextEditingValue(
            text: '    \u00a0first\n\u3000second',
            selection: TextSelection.collapsed(offset: 18)));
      } else {
        state.paste('\u00a0first\n\u3000second');
      }
      expect(state.inController.text, '    \u00a0first\n\u3000second');
      await _choose(tester, 'Convert');
      expect(state.inController.text, '    first\n    second');
      expect(state.inController.selection.extentOffset, 20);
      state.undo();
      await tester.pump();
      expect(state.inController.text, '    ');
      expect(state.inController.selection.extentOffset, 4);
      state.redo();
      await tester.pump();
      expect(state.inController.text, '    first\n    second');
      expect(state.inController.selection.extentOffset, 20);
    });
  }

  testWidgets('identical explicit paste can be converted after Keep',
      (tester) async {
    final state = await _mount(tester, source: '');
    const pasted = '\u00a0value = "\u00a0literal"';
    state.paste(pasted, reindent: false);
    await _choose(tester, 'Keep text');
    expect(state.inController.text, pasted);
    expect(state.inController.selection.extentOffset, pasted.length);
    final selection = TextSelection(baseOffset: 0, extentOffset: pasted.length);
    state.inController.selection = selection;
    await tester.pump();
    state.paste(pasted, reindent: false);
    await _choose(tester, 'Convert');
    expect(state.inController.text, ' value = "\u00a0literal"');
    state.undo();
    await tester.pump();
    expect(state.inController.text, pasted);
    expect(state.inController.selection, selection);
    state.redo();
    await tester.pump();
    expect(state.inController.text, ' value = "\u00a0literal"');
  });

  testWidgets(
      'selecting and collapsing invalid source does not offer conversion',
      (tester) async {
    const source = '\u00a0value';
    final state = await _mount(tester, source: source);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: source,
        selection: TextSelection(baseOffset: 0, extentOffset: 6)));
    await tester.pump();
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: source, selection: TextSelection.collapsed(offset: 6)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Convert indentation?'), findsNothing);
    expect(state.inController.text, source);
  });

  testWidgets('a shorter native replacement still offers conversion',
      (tester) async {
    final state = await _mount(tester, source: '    replace_this_long_value');
    state.inController.selection =
        const TextSelection(baseOffset: 4, extentOffset: 27);
    await tester.pump();
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '    \u00a0first\n\u3000second',
        selection: TextSelection.collapsed(offset: 18)));
    await _choose(tester, 'Convert');
    expect(state.inController.text, '    first\n    second');
    expect(state.inController.selection.extentOffset, 20);
  });

  testWidgets('conversion preserves triple-string payload data',
      (tester) async {
    final state = await _mount(tester);
    state.paste('\u00a0message = """\n\u3000literal data\n"""\n\u00a0next()');
    await _choose(tester, 'Convert');
    expect(state.inController.text,
        '    message = """\n\u3000literal data\n"""\n    next()');
  });

  testWidgets('a conversion dialog cannot replace newer source',
      (tester) async {
    final state = await _mount(tester);
    state.paste('\u00a0first\n\u3000second');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    state.inController.value = const TextEditingValue(
        text: 'newer_source', selection: TextSelection.collapsed(offset: 12));
    await _choose(tester, 'Convert');
    expect(state.inController.text, 'newer_source');
  });
}
