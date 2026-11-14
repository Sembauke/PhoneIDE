import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:phone_ide/editor/python_indentation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

Future<EditorState> _mount(WidgetTester tester, String source,
    {int start = 1, int end = 3}) async {
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
          path: 'region-endings.py',
          options: EditorOptions(
            regionOptions: EditorRegionOptions(start: start, end: end),
          ),
        ),
      ),
    ),
  ));
  await settleEditor(tester);
  return key.currentState!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, first, second) in [
    ('LF', '\n', '\n'),
    ('CRLF', '\r\n', '\r\n'),
    ('lone CR', '\r', '\r'),
    ('mixed CRLF and CR', '\r\n', '\r'),
  ]) {
    testWidgets('$name region boundaries preserve rows and offsets',
        (tester) async {
      final source = 'if ok:$first    first()$second    second()';
      final state = await _mount(tester, source);
      expect(state.beforeController.text, 'if ok:');
      expect(state.inController.text, '    first()');
      expect(state.afterController.text, '    second()');
      expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .map((field) => field.minLines),
          [1, 1, 1]);
      expect(state.debugGuideSnapshot!.model.text, source);
      expect(state.debugGuideSnapshot!.model.lines.length, 3);
      state.inController.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();
      expect(state.debugGuideSnapshot!.caretOffset,
          'if ok:'.length + first.length + 4);
      expect(state.debugGuideSnapshot!.columns(1), [0]);
      final emitted = <String>[];
      final subscription = state.widget.onTextChange.stream.listen(emitted.add);
      state.inController.value = const TextEditingValue(
          text: '    updated()',
          selection: TextSelection.collapsed(offset: 13));
      await tester.pump();
      expect(emitted.last, 'if ok:$first    updated()$second    second()');
      expect(state.debugGuideSnapshot!.model.text, emitted.last);
      unawaited(subscription.cancel());
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    });
  }

  testWidgets('multi-line regions retain internal CRLF endings',
      (tester) async {
    const source = 'if ok:\r\n    first()\r\n    second()\r\nlast()\r\n';
    final state = await _mount(tester, source, end: 4);
    expect(state.inController.text, '    first()\r\n    second()');
    expect(state.afterController.text, 'last()\r\n');
    expect(state.debugGuideSnapshot!.model.text, source);
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.minLines),
        [1, 2, 2]);
  });

  testWidgets('empty insertion does not add an emitted CRLF', (tester) async {
    const source = 'if ok:\r\n    work()';
    final state = await _mount(tester, source, end: 2);
    final emitted = <String>[];
    final subscription = state.widget.onTextChange.stream.listen(emitted.add);
    state.afterController.value = const TextEditingValue(
        text: '    updated()', selection: TextSelection.collapsed(offset: 13));
    await tester.pump();
    expect(emitted.last, 'if ok:\r\n    updated()');
    state.inController.value = const TextEditingValue(
        text: '    inserted()', selection: TextSelection.collapsed(offset: 14));
    await tester.pump();
    expect(emitted.last, 'if ok:\r\n    inserted()\r\n    updated()');
    unawaited(subscription.cancel());
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
  });

  testWidgets('legacy path cache restores bounds around host-supplied source',
      (tester) async {
    const source = 'if ok:\r\n    first()\rlast()';
    final state = await _mount(tester, source);
    final emitted = <String>[];
    final subscription = state.widget.onTextChange.stream.listen(emitted.add);
    state.beforeController.value = const TextEditingValue(
        text: '# added\nif ok:',
        selection: TextSelection.collapsed(offset: 15));
    await tester.pump();
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getString('region-endings.py'), '2:4');
    final hostSource = emitted.last;
    unawaited(subscription.cancel());
    await tester.pumpWidget(const SizedBox());
    final restored = await _mount(tester, hostSource);
    expect(restored.beforeController.text, '# added\nif ok:');
    expect(restored.inController.text, '    first()');
    expect(restored.afterController.text, 'last()');
    expect(restored.debugGuideSnapshot!.model.text,
        '# added\nif ok:\r\n    first()\rlast()');
    final restoredSubscription =
        restored.widget.onTextChange.stream.listen(emitted.add);
    restored.inController.value = const TextEditingValue(
        text: '    updated()', selection: TextSelection.collapsed(offset: 13));
    await tester.pump();
    expect(emitted.last, '# added\nif ok:\r\n    updated()\rlast()');
    unawaited(restoredSubscription.cancel());
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
  });
  for (final (name, ending) in [('LF', '\n'), ('CRLF', '\r\n'), ('CR', '\r')]) {
    testWidgets('empty $name insertion preserves surrounding logical lines',
        (tester) async {
      final source =
          'if outer:$ending    value = \\$ending        call()$ending    next()';
      final state = await _mount(tester, source, start: 2, end: 3);
      final model = state.debugGuideSnapshot!.model;
      expect(model.virtualLine, 2);
      expect(model.lines.length, 5);
      expect(model.lines[2].kind, PythonLineKind.continuation);
      expect(model.lines[3].kind, PythonLineKind.continuation);
      expect(model.lines[3].logicalStartLine, 1);
      expect(model.lines[3].stackColumns, [0, 4]);
      expect(model.lines[3].guideColumns, [0]);
      expect(model.contextAt(model.lines[2].startOffset).explicitContinuation,
          isTrue);
      final emitted = <String>[];
      final subscription = state.widget.onTextChange.stream.listen(emitted.add);
      state.afterController.value = TextEditingValue(
          text: '        changed()$ending    next()',
          selection: const TextSelection.collapsed(offset: 8));
      await tester.pump();
      expect(emitted.last, source.replaceFirst('call()', 'changed()'));
      expect(state.debugGuideSnapshot!.model.lines[3].kind,
          PythonLineKind.continuation);
      state.inController.value = const TextEditingValue(
          text: '        inserted()',
          selection: TextSelection.collapsed(offset: 8));
      await tester.pump();
      expect(state.debugGuideSnapshot!.model.virtualLine, isNull);
      expect(
          state.debugGuideSnapshot!.model.lines[3].kind, PythonLineKind.code);
      expect(emitted.last,
          'if outer:$ending    value = \\$ending        inserted()$ending        changed()$ending    next()');
      unawaited(subscription.cancel());
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    });
  }
}
