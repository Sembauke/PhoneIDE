import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('focused editor has no toolbar and keeps host editing commands',
      (tester) async {
    final key = GlobalKey<EditorState>();
    final editor = Editor(
      key: key,
      path: 'host-commands.py',
      defaultLanguage: 'python',
      defaultValue: 'work',
      options: EditorOptions(),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
    await settleEditor(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await editor.onTextChange.close();
      await editor.textfieldData.close();
      await editor.editableRegion.close();
    });
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    final state = key.currentState!;
    final focus = tester.widget<TextField>(find.byType(TextField)).focusNode!;
    expect(focus.hasFocus, isTrue);
    for (final label in [
      'Indent',
      'Dedent',
      'Previous indent stop',
      'Next indent stop',
      'Undo',
      'Redo',
    ]) {
      expect(find.byTooltip(label), findsNothing);
    }
    expect(find.byType(TextButton), findsNothing);

    state.inController.selection = const TextSelection.collapsed(offset: 4);
    state.executeCommand(EditorCommand.indent);
    expect(state.inController.text, '    work');
    state.undo();
    expect(state.inController.text, 'work');
    expect(state.inController.selection.extentOffset, 4);
    state.insertText('()');
    expect(state.inController.text, 'work()');
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('hardware Tab and Shift+Tab preserve focus and caret',
      (tester) async {
    final key = GlobalKey<EditorState>();
    final editor = Editor(
      key: key,
      path: 'hardware-commands.py',
      defaultLanguage: 'python',
      defaultValue: 'work',
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
    final focus = tester.widget<TextField>(find.byType(TextField)).focusNode!;
    state.inController.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(state.inController.text, '    work');
    expect(state.inController.selection.baseOffset, 6);
    expect(state.inController.selection.extentOffset, 6);
    expect(focus.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(state.inController.text, 'work');
    expect(state.inController.selection.baseOffset, 2);
    expect(state.inController.selection.extentOffset, 2);
    expect(focus.hasFocus, isTrue);

    // Releasing Shift must restore the unmodified shortcut on the next press.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(state.inController.text, '    work');
    expect(state.inController.selection.extentOffset, 6);
    expect(focus.hasFocus, isTrue);
  });
}
