import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

Future<EditorState> _open(WidgetTester tester, String source,
    {EditorRegionOptions? region}) async {
  final key = GlobalKey<EditorState>();
  final editor = Editor(
      key: key,
      path: 'native-geometry-regression.py',
      defaultLanguage: 'python',
      defaultValue: source,
      options: EditorOptions(
          fontFamily: 'RobotoMono',
          fontSize: 16.13,
          activeLineColor: const Color(0xff233344),
          regionOptions: region));
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
              body: SizedBox(width: 380, height: 240, child: editor)))));
  await settleEditor(tester);
  addTearDown(() async {
    await editor.onTextChange.close();
    await editor.textfieldData.close();
    await editor.editableRegion.close();
  });
  return key.currentState!;
}

Finder _field(TextEditingController controller) => find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.controller == controller);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await TextMateHighlighterRegistry.instance.initialize();
    await (FontLoader('RobotoMono')
          ..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf')))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('new rows never query stale native row offsets', (tester) async {
    final state = await _open(tester, 'value = 1');
    const edited = 'if ready:\n    work()\n    done()';
    state.inController.value = const TextEditingValue(
        text: edited,
        selection: TextSelection.collapsed(offset: edited.length));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'The first edit frame must reject stale one-row geometry.');
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(state.inController.text, edited);
    expect(find.byKey(const ValueKey('phone-ide-line-3')), findsOneWidget);
    expect(state.debugGuideSnapshot!.model.lines.length, 3);
  });

  testWidgets('cold split-region mount starts at the measured editable region',
      (tester) async {
    final source = [
      for (var row = 0; row < 199; row++) '# protected $row',
      'if ready:',
      '    work()',
      'finished()',
      for (var row = 0; row < 30; row++) '# after $row',
    ].join('\n');
    final state = await _open(tester, source,
        region: EditorRegionOptions(start: 200, end: 202));
    final initialOffset = state.scrollController.offset;
    expect(state.inController.text, '    work()');
    expect(initialOffset, greaterThan(1000));
    final inner = tester
        .state<EditableTextState>(_field(state.inController))
        .renderEditable;
    final editorTop = tester.getRect(find.byType(Editor)).top;
    expect(inner.localToGlobal(Offset.zero).dy, closeTo(editorTop, .5));
    // The prefix may already be unmounted by the lazy viewport. Reveal it to
    // independently compare the initial offset with its native measured size.
    state.scrollController.jumpTo(0);
    await settleEditor(tester);
    final before = tester
        .state<EditableTextState>(_field(state.beforeController))
        .renderEditable;
    expect(initialOffset, closeTo(before.size.height, .5),
        reason:
            'The first scroll waits for the actual protected-prefix height.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus recovery waits for an invalidated offscreen prefix',
      (tester) async {
    final source = [
      '# before',
      'editable()',
      for (var row = 0; row < 120; row++) '# after $row',
    ].join('\n');
    final state = await _open(tester, source,
        region: EditorRegionOptions(start: 1, end: 3));
    final focusNode =
        tester.widget<EditableText>(_field(state.inController)).focusNode;
    final after = state.afterController.text;
    state.scrollController
        .jumpTo(state.scrollController.position.maxScrollExtent);
    await settleEditor(tester);
    expect(_field(state.inController), findsNothing);
    expect(_field(state.beforeController), findsNothing);
    final changedPrefix = [
      for (var row = 0; row < 500; row++) '# updated protected $row',
    ].join('\n');
    state.beforeController.text = changedPrefix;
    await tester.pump();
    expect(_field(state.beforeController), findsNothing,
        reason: 'The requested focus must measure the invalidated prefix.');
    final editorRect = tester.getRect(find.byType(Editor));
    await tester.tapAt(Offset(editorRect.left + 10, editorRect.bottom - 20));
    await settleEditor(tester);
    expect(_field(state.inController), findsOneWidget);
    expect(focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(state.scrollController.offset, greaterThan(10000));
    expect(state.linebarController.offset,
        closeTo(state.scrollController.offset, .5));
    final inner = tester
        .state<EditableTextState>(_field(state.inController))
        .renderEditable;
    final visibleEditor = tester.getRect(find.byType(Editor));
    final innerTop = inner.localToGlobal(Offset.zero).dy;
    expect(innerTop, greaterThanOrEqualTo(visibleEditor.top));
    expect(
        innerTop + inner.size.height, lessThanOrEqualTo(visibleEditor.bottom));
    expect(state.beforeController.text, changedPrefix);
    expect(state.inController.text, 'editable()');
    expect(state.afterController.text, after);
    expect(tester.takeException(), isNull);
  });

  for (final source in ['', 'work()\r\n']) {
    testWidgets(
        'native caret box aligns the trailing empty row ${source.length}',
        (tester) async {
      final state = await _open(tester, source);
      await tester.showKeyboard(find.byType(TextField));
      state.inController.selection =
          TextSelection.collapsed(offset: source.length);
      await tester.pump();
      await tester.pump();
      final native = tester
          .state<EditableTextState>(_field(state.inController))
          .renderEditable;
      final caret =
          native.getLocalRectForCaret(TextPosition(offset: source.length));
      final top = native.localToGlobal(caret.topLeft).dy;
      final bottom = native.localToGlobal(caret.bottomRight).dy;
      final line = source.isEmpty ? 1 : 2;
      final gutter =
          tester.getRect(find.byKey(ValueKey('phone-ide-line-$line')));
      final active =
          tester.getRect(find.byKey(const ValueKey('phone-ide-active-line')));
      for (final box in [gutter, active]) {
        expect(box.top, closeTo(top, .5));
        expect(box.bottom, closeTo(bottom, .5));
      }
      expect(state.inController.text, source);
      expect(tester.takeException(), isNull);
    });
  }
}
