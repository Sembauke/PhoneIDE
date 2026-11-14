import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/phone_ide.dart';

void main() {
  testWidgets('public Python options configure editor indentation',
      (tester) async {
    final editor = Editor(
      path: 'public-options.py',
      defaultLanguage: 'python',
      defaultValue: 'work()',
      options: EditorOptions(
        indentSize: 8,
        pythonIndentOptions: const PythonIndentOptions(projectIndentSize: 2),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await editor.onTextChange.close();
      await editor.textfieldData.close();
      await editor.editableRegion.close();
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));
    for (var frame = 0; frame < 100; frame++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      if (find.byType(TextField).evaluate().isNotEmpty) break;
    }
    expect(find.byType(TextField), findsOneWidget);
    await tester.showKeyboard(find.byType(TextField));
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(controller.text, '  work()');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });
}
