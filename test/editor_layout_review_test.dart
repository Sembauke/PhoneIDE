import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

Future<EditorState> _mount(WidgetTester tester, String source,
    {EditorOptions? options,
    String language = 'python',
    Widget? trailing}) async {
  final key = GlobalKey<EditorState>();
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Column(children: [
    SizedBox(
        width: 380,
        height: 240,
        child: Editor(
            key: key,
            defaultLanguage: language,
            defaultValue: source,
            path: 'layout-review.$language',
            options: options ?? EditorOptions())),
    if (trailing != null) trailing,
  ]))));
  await settleEditor(tester);
  return key.currentState!;
}

void main() {
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('editing a scrolled document preserves the gutter offset',
      (tester) async {
    final state = await _mount(tester,
        List.generate(300, (index) => 'value_$index = $index').join('\n'));
    state.scrollController.jumpTo(7500);
    await tester.pumpAndSettle();
    expect(state.linebarController.offset, closeTo(7500, .5));
    final old = state.inController.text;
    final offset = old.indexOf('value_280');
    state.inController.value = TextEditingValue(
        text: old.replaceRange(offset, offset, '#'),
        selection: TextSelection.collapsed(offset: offset + 1));
    await tester.pump();
    expect(state.linebarController.offset, greaterThan(7000),
        reason: 'The replacement measurement must not collapse the gutter.');
    await tester.pumpAndSettle();
    expect(state.scrollController.offset, greaterThan(7000));
    expect(state.linebarController.offset,
        closeTo(state.scrollController.offset, .5));
    expect(find.byKey(const ValueKey('phone-ide-line-281')), findsOneWidget);
  });

  testWidgets('read-only Python lets Tab move to the next focus target',
      (tester) async {
    final next = FocusNode();
    addTearDown(next.dispose);
    final state = await _mount(tester, 'value = 1',
        options: EditorOptions(isEditable: false),
        trailing: TextField(focusNode: next));
    final field = find.byWidgetPredicate((widget) =>
        widget is EditableText && widget.controller == state.inController);
    tester.widget<EditableText>(field).focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(next.hasFocus, isTrue);
    expect(state.inController.text, 'value = 1');
  });

  testWidgets('non-Python gutter exposes source line numbers to semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester, 'const answer = 42;', language: 'javascript');
      expect(find.bySemanticsLabel('Line 1'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('one changed row only remeasures that row for content width',
      (tester) async {
    final lines = List.generate(500, (index) => 'value_$index = $index');
    final state = await _mount(tester, lines.join('\n'));
    final before = state.debugContentWidthMeasurements;
    lines[250] += ' + 1';
    state.inController.text = lines.join('\n');
    await tester.pumpAndSettle();
    expect(state.debugContentWidthMeasurements - before, 1);
  });

  testWidgets('publishing native row geometry does not rebuild the code field',
      (tester) async {
    final state =
        await _mount(tester, 'const answer = 42;', language: 'javascript');
    state.inController.text = 'const answer = 43;\nconst next = 44;';
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)), same(field));
  });
}
