import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'accepting initial structural guides preserves field and input client',
      (tester) async {
    final key = GlobalKey<EditorState>();
    final source =
        'if ready:\n${List.filled(4000, '    value = 1234567890').join('\n')}';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Editor(
      key: key,
      path: 'background-focus.py',
      defaultLanguage: 'python',
      defaultValue: source,
      options: EditorOptions(),
    ))));
    for (var attempt = 0; attempt < 100; attempt++) {
      if (find.byType(TextField).evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(find.byType(TextField), findsOneWidget);
    final state = key.currentState!;
    expect(state.debugGuideSnapshot, isNull,
        reason: 'The field must still be displaying initial fallback guides.');
    final fieldElement = tester.element(find.byType(TextField));
    final editableState =
        tester.state<EditableTextState>(find.byType(EditableText));
    await tester.showKeyboard(find.byType(TextField));
    state.inController.selection = const TextSelection.collapsed(offset: 14);
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue,
        reason: 'The fallback field has an active platform input client.');
    final inputClient = tester.testTextInput.setClientArgs;
    int connectionEvents() => tester.testTextInput.log
        .where((call) => const {'TextInput.setClient', 'TextInput.clearClient'}
            .contains(call.method))
        .length;
    final connectionEventsBefore = connectionEvents();
    for (var attempt = 0; attempt < 200; attempt++) {
      if (state.debugGuideSnapshot?.model.text == source) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(state.debugGuideSnapshot?.model.text, source);
    await tester.pump();
    await tester.pump();
    expect(tester.element(find.byType(TextField)), same(fieldElement));
    expect(tester.state<EditableTextState>(find.byType(EditableText)),
        same(editableState));
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.setClientArgs, inputClient,
        reason:
            'Background guide replacement must preserve the native input connection.');
    expect(connectionEvents(), connectionEventsBefore,
        reason: 'The platform client is neither cleared nor recreated.');
    expect(state.inController.selection,
        const TextSelection.collapsed(offset: 14));
    await tester.pumpWidget(const SizedBox());
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  });
}
