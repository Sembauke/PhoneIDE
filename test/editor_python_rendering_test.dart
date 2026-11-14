import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'editor_test_helpers.dart';

Future<EditorState> mountEditor(WidgetTester tester, String source,
    {EditorOptions? options}) async {
  final key = GlobalKey<EditorState>();
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SizedBox(
              width: 380,
              height: 600,
              child: Editor(
                  key: key,
                  defaultLanguage: 'python',
                  defaultValue: source,
                  path: 'python-test.py',
                  options:
                      options ?? EditorOptions(fontFamily: 'RobotoMono'))))));
  await settleEditor(tester);
  return key.currentState!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await TextMateHighlighterRegistry.instance.initialize();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('caret movement reuses the model', (tester) async {
    final state =
        await mountEditor(tester, 'if ok:\n    first()\n    second()');
    final before = state.debugGuideSnapshot!;
    for (var i = 7; i < 16; i++) {
      state.inController.selection = TextSelection.collapsed(offset: i);
      await tester.pump();
    }
    expect(state.debugGuideSnapshot!.revision, before.revision);
    expect(identical(state.debugGuideSnapshot!.model, before.model), isTrue);
  });
  testWidgets('native selection, guides, glyphs and caret layer correctly',
      (tester) async {
    final state =
        await mountEditor(tester, 'if ok:\n    first()\n    second()');
    await tester.showKeyboard(find.byType(TextField));
    state.inController.selection =
        const TextSelection(baseOffset: 7, extentOffset: 18);
    await tester.pump();
    await tester.pump();
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    expect(render.painter, isNotNull);
    expect(render.foregroundPainter, isNull);
    expect(render.paintCursorAboveText, isTrue);
    final runs = state.debugGuideSnapshot!.geometry[RegionPosition.inner]!;
    expect(runs, isNotEmpty);
    expect(
        runs.any((run) =>
            run.rect.height >=
            state.getTextHeight(tester.element(find.byType(Editor))) * 2),
        isTrue);
  });
  testWidgets('header activity and focus', (tester) async {
    final state =
        await mountEditor(tester, 'if ok:\n    first()\n    second()');
    expect(state.debugGuideSnapshot!.activeBlock(0), isNull);
    await tester.showKeyboard(find.byType(TextField));
    state.inController.selection = const TextSelection.collapsed(offset: 1);
    await tester.pump();
    await tester.pump();
    expect(state.debugGuideSnapshot!.activeBlock(0)?.keyword, 'if');
    state.inController.selection = const TextSelection.collapsed(offset: 12);
    await tester.pump();
    expect(state.debugGuideSnapshot!.activeBlock(1)?.keyword, 'if');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(state.debugGuideSnapshot!.activeBlock(1), isNull);
  });
  testWidgets('Enter and autoindent undo together', (tester) async {
    final state = await mountEditor(tester, 'if ready:');
    await tester.showKeyboard(find.byType(TextField));
    state.inController.selection = const TextSelection.collapsed(offset: 9);
    state.executeCommand(EditorCommand.enter);
    expect(state.inController.text, 'if ready:\n    ');
    state.undo();
    expect(state.inController.text, 'if ready:');
    expect(state.inController.selection.extentOffset, 9);
    state.redo();
    expect(state.inController.text, 'if ready:\n    ');
  });
  testWidgets('caret commands snap in leading whitespace', (tester) async {
    final state = await mountEditor(tester, 'if a:\n    if b:\n        work()');
    state.inController.selection = const TextSelection.collapsed(offset: 24);
    state.executeCommand(EditorCommand.caretLeft);
    expect(state.inController.selection.extentOffset, 20);
    state.executeCommand(EditorCommand.caretRight);
    expect(state.inController.selection.extentOffset, 24);
  });
  testWidgets('disabled and readonly active guides', (tester) async {
    final state = await mountEditor(tester, 'if a:\n    work()',
        options: EditorOptions(isEditable: false, showIndentGuides: false));
    expect(state.debugGuideSnapshot!.activeBlock(1), isNull);
    expect(state.debugGuideSnapshot!.geometry[RegionPosition.inner], isEmpty);
  });
  testWidgets('each visible source line announces its indentation',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountEditor(tester, 'if a:\n    work()');
    expect(
        find.bySemanticsLabel('Line 2, indentation 1, work()'), findsOneWidget);
    semantics.dispose();
  });
  testWidgets('unclosed lexical state holds guides for a bounded debounce',
      (tester) async {
    const text = 'value = """ok"""\nif ready:\n    work()';
    final state = await mountEditor(tester, text);
    final before = state.debugGuideSnapshot!.model;
    state.inController.value = TextEditingValue(
        text: text.replaceFirst('ok"""', 'ok'),
        selection: const TextSelection.collapsed(offset: 13));
    await tester.pump();
    expect(identical(state.debugGuideSnapshot!.model, before), isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(identical(state.debugGuideSnapshot!.model, before), isTrue);
    await tester.pump(const Duration(milliseconds: 160));
    expect(
        state.debugGuideSnapshot!.model.lines[2].kind.name, 'stringInterior');
    expect(state.inController.text, text.replaceFirst('ok"""', 'ok'));
  });
  testWidgets(
      'typing inside an existing open bracket publishes guides without debounce',
      (tester) async {
    final state = await mountEditor(tester, 'print(a');
    var text = 'print(a';
    for (final suffix in [', b', ', c', ', d']) {
      text += suffix;
      state.inController.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
      await tester.pump();
      expect(state.debugGuideSnapshot!.model.text, text);
    }
  });
  testWidgets('invalid plain-paste indent is offered for conversion',
      (tester) async {
    final state = await mountEditor(tester, '');
    await tester.showKeyboard(find.byType(TextField));
    state.inController.selection = const TextSelection.collapsed(offset: 0);
    state.paste('\u00a0work()', reindent: false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Convert indentation?'), findsOneWidget);
    expect(state.inController.text, '\u00a0work()');
    await tester.tap(find.text('Convert'));
    await tester.pumpAndSettle();
    expect(state.inController.text, ' work()');
  });
}
