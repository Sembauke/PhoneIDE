import 'dart:async';

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

  for (final (ending, atEnd) in [
    ('\n', false),
    ('\r\n', true),
    ('\r', false)
  ]) {
    testWidgets(
        'virtual insertion undo/redo preserves ${ending.codeUnits} atEnd=$atEnd',
        (tester) async {
      final key = GlobalKey<EditorState>();
      final source = 'before${ending}after';
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Editor(
        key: key,
        defaultLanguage: 'python',
        defaultValue: source,
        path: 'virtual-undo.py',
        options: EditorOptions(
            regionOptions:
                EditorRegionOptions(start: atEnd ? 2 : 1, end: atEnd ? 3 : 2)),
      ))));
      await settleEditor(tester);
      final state = key.currentState!;
      final emitted = <String>[];
      final subscription = state.widget.onTextChange.stream.listen(emitted.add);
      state.inController.selection = const TextSelection.collapsed(offset: 0);
      state.insertText('value');
      await tester.pump();
      final inserted = atEnd
          ? '$source${ending}value'
          : 'before${ending}value${ending}after';
      expect(emitted.last, inserted);
      state.undo();
      await tester.pump();
      expect(state.inController.text, isEmpty);
      expect(emitted.last, source);
      expect(state.debugGuideSnapshot!.model.virtualLine, atEnd ? 2 : 1);
      state.redo();
      await tester.pump();
      expect(emitted.last, inserted);
      expect(state.debugGuideSnapshot!.model.virtualLine, isNull);
      state.undo();
      await tester.pump();
      expect(emitted.last, source);
      expect(state.beforeController.text, atEnd ? source : 'before');
      expect(state.afterController.text, atEnd ? '' : 'after');
      unawaited(subscription.cancel());
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a real blank row remains real after undo', (tester) async {
    final key = GlobalKey<EditorState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Editor(
      key: key,
      defaultLanguage: 'python',
      defaultValue: 'before\r\n\r\nafter',
      path: 'real-blank.py',
      options:
          EditorOptions(regionOptions: EditorRegionOptions(start: 1, end: 3)),
    ))));
    await settleEditor(tester);
    final state = key.currentState!;
    state.inController.selection = const TextSelection.collapsed(offset: 0);
    state.insertText('value');
    state.undo();
    await tester.pump();
    expect(state.debugGuideSnapshot!.model.virtualLine, isNull);
    expect(state.debugGuideSnapshot!.model.text, 'before\r\n\r\nafter');
    await tester.pumpWidget(const SizedBox());
  });
}
