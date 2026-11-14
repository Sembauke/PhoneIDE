import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/python_indentation.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

Future<EditorState> _mount(
    WidgetTester tester, String source, int caret) async {
  final key = GlobalKey<EditorState>();
  final editor = Editor(
    key: key,
    path: 'context-actions.py',
    defaultLanguage: 'python',
    defaultValue: source,
    options: EditorOptions(),
  );
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
  await settleEditor(tester);
  addTearDown(() async {
    await editor.onTextChange.close();
    await editor.textfieldData.close();
    await editor.editableRegion.close();
  });
  await tester.showKeyboard(find.byType(TextField));
  final state = key.currentState!;
  state.inController.selection = TextSelection.collapsed(offset: caret);
  await tester.pump();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the visible plain-paste action preserves clipboard bytes',
      (tester) async {
    var clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String;
          return null;
        case 'Clipboard.getData':
          return {'text': clipboard};
        case 'Clipboard.hasStrings':
          return {'value': clipboard.isNotEmpty};
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final state = await _mount(tester, '    ', 4);
    await Clipboard.setData(const ClipboardData(text: '  one\r\n\tsecond'));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.hideToolbar();
    editable.toggleToolbar();
    await tester.pumpAndSettle(const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    final action = find.text('Paste without re-indenting');
    expect(state.inController.text, '    ');
    expect(state.inController.selection.baseOffset, 4);
    expect(state.inController.selection.extentOffset, 4);
    if (action.hitTestable().evaluate().isEmpty) {
      await tester.tap(find.byTooltip('More').hitTestable());
      await tester.pumpAndSettle(const Duration(milliseconds: 16),
          EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    }
    expect(action.hitTestable(), findsOneWidget);
    await tester.tap(action.hitTestable());
    await tester.pumpAndSettle(const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(state.inController.text, '      one\r\n\tsecond');
    expect(state.inController.selection.extentOffset, 18);
    state.undo();
    await tester.pump();
    expect(state.inController.text, '    ');
    expect(state.inController.selection.extentOffset, 4);
    state.redo();
    await tester.pump();
    expect(state.inController.text, '      one\r\n\tsecond');
    expect(state.inController.selection.extentOffset, 18);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('external column-zero comments retain block structure',
      (tester) async {
    const source =
        'if ready:\n    first()\n# external comment\n    second()\nfinished()';
    final state = await _mount(tester, source, 22);
    final snapshot = state.debugGuideSnapshot!;
    expect(snapshot.model.lines[2].kind, PythonLineKind.comment);
    final rowHeight = state.getTextHeight(tester.element(find.byType(Editor)));
    final rendered = snapshot.geometry.values.expand((runs) => runs).toList();
    expect(
        rendered.any((run) =>
            run.rect.top < rowHeight * 2.5 &&
            run.rect.bottom > rowHeight * 2.5),
        isFalse);
    expect(
        rendered.any((run) =>
            run.rect.top < rowHeight * 1.5 &&
            run.rect.bottom > rowHeight * 1.5),
        isTrue);
    expect(snapshot.columns(1), [0]);
    expect(snapshot.columns(3), [0]);
    expect(snapshot.model.lines[1].blockIds, snapshot.model.lines[3].blockIds);
  });
}
