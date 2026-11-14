import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

void main() {
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<EditorState> mount(WidgetTester tester,
      {String source = '', EditorOptions? options}) async {
    final key = GlobalKey<EditorState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Editor(
      key: key,
      path: 'history.py',
      defaultLanguage: 'python',
      defaultValue: source,
      options: options ?? EditorOptions(),
    ))));
    await settleEditor(tester);
    return key.currentState!;
  }

  testWidgets(
      'adjacent native typing is one undo step; moving the caret splits it',
      (tester) async {
    final state = await mount(tester);
    final controller = state.inController;
    controller.selection = const TextSelection.collapsed(offset: 0);
    for (final text in ['a', 'ab', 'abc']) {
      controller.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    state.undo();
    expect(controller.text, '');
    state.redo();
    expect(controller.text, 'abc');
    controller.selection = const TextSelection.collapsed(offset: 1);
    controller.value = const TextEditingValue(
        text: 'axbc', selection: TextSelection.collapsed(offset: 2));
    state.undo();
    expect(controller.text, 'abc');
    state.undo();
    expect(controller.text, '');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('undo retains the latest 100 separate edits', (tester) async {
    final state = await mount(tester);
    for (var i = 0; i < 110; i++) {
      final text = 'entry$i\n';
      state.inController.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    for (var i = 0; i < 100; i++) {
      state.undo();
    }
    expect(state.inController.text, 'entry9\n');
    state.undo();
    expect(state.inController.text, 'entry9\n');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the memory budget also bounds history for large snapshots',
      (tester) async {
    final source = 'x' * 50000;
    final state = await mount(tester, source: source);
    for (var i = 0; i < 40; i++) {
      final text = '$source\n$i';
      state.inController.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    var steps = 0;
    while (steps < 100) {
      final previous = state.inController.text;
      state.undo();
      if (previous == state.inController.text) break;
      steps++;
    }
    expect(steps, inInclusiveRange(1, 20));
    expect(state.inController.text, '$source\n19');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
