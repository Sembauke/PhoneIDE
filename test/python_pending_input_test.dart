import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'caret cleanup while a worker is pending retains paired formatting',
      (tester) async {
    final source = _largeSource('result = ');
    final state = await _openLarge(tester, source);
    _nativeInsert(tester, state, '(');
    _nativeInsert(tester, state, '\n');
    _nativeInsert(tester, state, '  ');
    state.inController.selection = const TextSelection.collapsed(offset: 0);
    await _until(tester, () => state.inController.text == '$source(\n\n)');
    expect(state.inController.selection.extentOffset, 0);
    await _closeLarge(tester);
  });

  testWidgets('deferred arrow commands leave indentation and blank lines',
      (tester) async {
    final prefix = _largeSource('');
    final source = '${prefix}a\n    b\n\nc';
    final state = await _openLarge(tester, source);
    for (final sample in [
      (6, EditorCommand.caretRight, 7),
      (2, EditorCommand.caretLeft, 1),
      (8, EditorCommand.caretLeft, 7),
      (8, EditorCommand.caretRight, 9),
    ]) {
      state.inController.selection =
          TextSelection.collapsed(offset: prefix.length + sample.$1);
      state.executeCommand(sample.$2);
      await _until(
          tester,
          () =>
              state.inController.selection.extentOffset ==
              prefix.length + sample.$3);
    }
    await _closeLarge(tester);
  });

  testWidgets(
      'pending undo follows formatted pair boundaries, not raw grouping',
      (tester) async {
    final source = _largeSource('result = ');
    final state = await _openLarge(tester, source);
    _nativeInsert(tester, state, '(');
    _nativeInsert(tester, state, 'a');
    state.undo();
    state.undo();
    await _until(tester, () => state.inController.text == source);
    state.redo();
    await _until(tester, () => state.inController.text == '$source()');
    state.redo();
    await _until(tester, () => state.inController.text == '$source(a)');
    await _closeLarge(tester);
  });

  testWidgets(
      'a second edit during large invalidation stays off the UI scanner',
      (tester) async {
    final key = GlobalKey<EditorState>();
    final source =
        'value = 0\nif ready:\n${List.filled(4000, '    value = 1234567890').join('\n')}';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Editor(
      key: key,
      path: 'pending-large-input.py',
      defaultLanguage: 'python',
      defaultValue: source,
      options: EditorOptions(),
    ))));
    await settleEditor(tester);
    final state = key.currentState!;
    for (var attempt = 0; attempt < 200; attempt++) {
      if (state.debugGuideSnapshot?.model.text == source) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(state.debugGuideSnapshot?.model.text, source,
        reason:
            'The initial large model must be ready before exercising invalidation.');
    await tester.pump();
    await tester.pump();
    await tester.showKeyboard(find.byType(TextField).first);
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    final before = state.debugGuideSnapshot!.syncInputAnalyses;
    final invalidated = source.replaceFirst('value = 0', 'value = """');
    state.inController.value = TextEditingValue(
      text: invalidated,
      selection: TextSelection.collapsed(offset: invalidated.length),
    );
    expect(state.debugGuideSnapshot!.model.text, source,
        reason:
            'The quote edit retains previous guides while a worker starts.');
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: '${invalidated}x',
      selection: TextSelection.collapsed(offset: invalidated.length + 1),
    ));
    await tester.pump();
    await tester.pump();
    final after = state.debugGuideSnapshot!.syncInputAnalyses;
    expect(state.inController.text, '${invalidated}x',
        reason:
            'The second edit must pass through the real TextField formatter.');
    await tester.pumpWidget(const SizedBox());
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(after, before,
        reason:
            'Typing before background reconvergence must not rescan the whole large file on the UI isolate.');
  });

  testWidgets(
      'large pending context applies Enter and quotes inside new string',
      (tester) async {
    final source = _largeSource('    if ready:');
    final state = await _openLarge(tester, source);
    final invalidated = source.replaceFirst('value = 0', 'value = """');
    state.inController.value = TextEditingValue(
        text: invalidated,
        selection: TextSelection.collapsed(offset: invalidated.length));
    _nativeInsert(tester, state, '\n');
    _nativeInsert(tester, state, '"');
    _nativeInsert(tester, state, 'x');
    final expected = '$invalidated\n    "x';
    await _until(tester, () => state.inController.text == expected);
    expect(state.inController.selection.extentOffset, expected.length);
    expect(state.debugGuideSnapshot!.syncInputAnalyses, 0);
    await _closeLarge(tester);
  });

  testWidgets(
      'repeated Backspace uses corrected indentation stops while pending',
      (tester) async {
    final source = _largeSource('if ready:\n        work()');
    final state = await _openLarge(tester, source);
    final caret = source.lastIndexOf('work()');
    state.inController.selection = TextSelection.collapsed(offset: caret);
    _nativeBackspace(tester, state);
    _nativeBackspace(tester, state);
    final expected = source.replaceFirst('        work()', 'work()');
    await _until(tester, () => state.inController.text == expected);
    expect(state.inController.selection.extentOffset,
        expected.lastIndexOf('work()'));
    state.undo();
    expect(state.inController.text,
        source.replaceFirst('        work()', '    work()'));
    state.undo();
    expect(state.inController.text, source);
    await _closeLarge(tester);
  });

  testWidgets(
      'pending Enter preserves IME composition and Backspace until commit',
      (tester) async {
    final source = _largeSource('if ready:');
    final state = await _openLarge(tester, source);
    _nativeInsert(tester, state, '\n');
    final raw = state.inController.value;
    final composing = TextEditingValue(
        text: '${raw.text}word',
        selection: TextSelection.collapsed(offset: raw.text.length + 4),
        composing: TextRange(start: raw.text.length, end: raw.text.length + 4));
    tester.testTextInput.updateEditingValue(composing);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(state.inController.value, composing);
    final shortened = composing.copyWith(
        text: '${raw.text}wor',
        selection: TextSelection.collapsed(offset: raw.text.length + 3),
        composing: TextRange(start: raw.text.length, end: raw.text.length + 3));
    tester.testTextInput.updateEditingValue(shortened);
    tester.testTextInput
        .updateEditingValue(shortened.copyWith(composing: TextRange.empty));
    await _until(tester, () => state.inController.text == '$source\n    wor');
    expect(state.inController.value.composing, TextRange.empty);
    await _closeLarge(tester);
  });

  testWidgets('pending undo preserves earlier Enter and subsequent typing',
      (tester) async {
    final source = _largeSource('if ready:');
    final state = await _openLarge(tester, source);
    _nativeInsert(tester, state, '\n');
    _nativeInsert(tester, state, 'x');
    state.undo();
    _nativeInsert(tester, state, 'y');
    await _until(tester, () => state.inController.text == '$source\n    y');
    state.undo();
    expect(state.inController.text, '$source\n    ');
    state.redo();
    expect(state.inController.text, '$source\n    y');
    await _closeLarge(tester);
  });

  testWidgets(
      'external text replacement and pending undo discard stale results',
      (tester) async {
    final source = _largeSource('if ready:');
    final state = await _openLarge(tester, source);
    _nativeInsert(tester, state, '\n');
    state.undo();
    expect(state.inController.text, source);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(state.inController.text, source);
    _nativeInsert(tester, state, '\n');
    state.inController.value = const TextEditingValue(
        text: 'replacement = True',
        selection: TextSelection.collapsed(offset: 18));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(state.inController.text, 'replacement = True');
    await _closeLarge(tester);
  });

  testWidgets('pending formatting respects a moved caret and protected regions',
      (tester) async {
    final source = _largeSource('if ready:\n    value = 1\nprotected = True');
    final state = await _openLarge(tester, source,
        region: EditorRegionOptions(start: 4202, end: 4204));
    final before = state.beforeController.text;
    final after = state.afterController.text;
    expect(state.inController.text, '    value = 1');
    _nativeInsert(tester, state, '\n');
    for (final letter in 'work()'.split('')) {
      _nativeInsert(tester, state, letter);
    }
    state.inController.selection = const TextSelection.collapsed(offset: 4);
    await _until(
        tester, () => state.inController.text == '    value = 1\n    work()');
    expect(state.beforeController.text, before);
    expect(state.afterController.text, after);
    expect(state.inController.selection.extentOffset, 4);
    await _closeLarge(tester);
  });

  for (final convert in [false, true]) {
    testWidgets(
        'pending Enter survives ${convert ? "native Convert" : "public Keep"} whitespace paste',
        (tester) async {
      final source = _largeSource('if ready:');
      final state = await _openLarge(tester, source);
      _nativeInsert(tester, state, '\n');
      if (convert) {
        _nativeInsert(tester, state, '\u00a0work()');
      } else {
        state.paste('\u00a0work()');
      }
      await _until(tester, () => find.text('Keep text').evaluate().isNotEmpty);
      expect(state.inController.text, '$source\n    \u00a0work()');
      await tester.tap(find.text(convert ? 'Convert' : 'Keep text'));
      final expected = '$source\n    ${convert ? "" : "\u00a0"}work()';
      await _until(tester, () => state.inController.text == expected);
      await tester.pumpAndSettle();
      await _closeLarge(tester);
    });
  }

  testWidgets('public Enter, typing and paste wait for worker formatting',
      (tester) async {
    final source = _largeSource('if ready:');
    final state = await _openLarge(tester, source);
    state.executeCommand(EditorCommand.enter);
    state.insertText('print("ok")');
    await _until(
        tester, () => state.inController.text == '$source\n    print("ok")');
    state.executeCommand(EditorCommand.enter);
    state.paste('first()\nsecond()');
    final expected = '$source\n    print("ok")\n    first()\n    second()';
    await _until(tester, () => state.inController.text == expected);
    expect(state.debugGuideSnapshot!.syncInputAnalyses, 0);
    await _closeLarge(tester);
  });
}

String _largeSource(String tail) =>
    'value = 0\n${List.filled(4200, '# retained lexical context').join('\n')}\n$tail';

Future<EditorState> _openLarge(WidgetTester tester, String source,
    {EditorRegionOptions? region}) async {
  final key = GlobalKey<EditorState>();
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Editor(
    key: key,
    path: 'pending-input-regression.py',
    defaultLanguage: 'python',
    defaultValue: source,
    options: EditorOptions(
        regionOptions: region,
        pythonIndentOptions: const PythonIndentOptions(projectIndentSize: 4)),
  ))));
  await settleEditor(tester);
  final state = key.currentState!;
  await _until(tester, () => state.debugGuideSnapshot?.model.text == source);
  await tester.showKeyboard(find.byWidgetPredicate((widget) =>
      widget is TextField && widget.controller == state.inController));
  state.inController.selection =
      TextSelection.collapsed(offset: state.inController.text.length);
  await tester.pump();
  return state;
}

void _nativeInsert(WidgetTester tester, EditorState state, String text) {
  final value = state.inController.value;
  tester.testTextInput.updateEditingValue(TextEditingValue(
      text: value.text
          .replaceRange(value.selection.start, value.selection.end, text),
      selection: TextSelection.collapsed(
          offset: value.selection.start + text.length)));
}

void _nativeBackspace(WidgetTester tester, EditorState state) {
  final value = state.inController.value;
  final caret = value.selection.extentOffset;
  tester.testTextInput.updateEditingValue(TextEditingValue(
      text: value.text.replaceRange(caret - 1, caret, ''),
      selection: TextSelection.collapsed(offset: caret - 1)));
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 250 && !done(); attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'The worker result must be published.');
}

Future<void> _closeLarge(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
}
