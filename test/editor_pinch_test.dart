import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

Future<EditorState> _mount(WidgetTester tester, String source) async {
  final key = GlobalKey<EditorState>();
  final editor = Editor(
    key: key,
    defaultLanguage: 'python',
    defaultValue: source,
    path: 'pinch.py',
    options: EditorOptions(
      fontSize: 18,
    ),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 390, height: 700, child: editor),
    ),
  ));
  await settleEditor(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await editor.onTextChange.close();
    await editor.textfieldData.close();
    await editor.editableRegion.close();
  });
  return key.currentState!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TextMateHighlighterRegistry.instance.initialize());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final longLine in [false, true]) {
    testWidgets(
        'two-finger zoom grows real text with horizontal overflow=$longLine',
        (tester) async {
      final source = 'if ready:\n    if warm:\n'
          '        ${longLine ? 'payload ' * 100 : 'camp()'}\n        rest()';
      final state = await _mount(tester, source);
      final render = tester
          .state<EditableTextState>(find.byType(EditableText).first)
          .renderEditable;
      final before = render.preferredLineHeight;
      if (longLine) {
        expect(state.horizontalController.position.maxScrollExtent,
            greaterThan(0));
      }
      final center =
          render.localToGlobal(Offset(150, render.preferredLineHeight * 2.5));
      final first =
          await tester.startGesture(center - const Offset(35, 0), pointer: 31);
      final second =
          await tester.startGesture(center + const Offset(35, 0), pointer: 32);
      await tester.pump(const Duration(milliseconds: 350));
      await first.moveTo(center - const Offset(90, 0));
      await second.moveTo(center + const Offset(90, 0));
      await tester.pump(const Duration(milliseconds: 350));
      await first.up();
      await second.up();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(render.preferredLineHeight, greaterThan(before));
      expect(state.horizontalController.offset, 0,
          reason: 'A two-finger scale must not become a horizontal scroll.');
      final guide = render.getLocalRectForCaret(
          TextPosition(offset: source.indexOf('        ') + 4));
      expect(
          state.debugGuideSnapshot!.geometry[RegionPosition.inner]!.any((run) =>
              (run.rect.left - guide.left).abs() <= 1 &&
              run.rect.top <= guide.center.dy &&
              run.rect.bottom >= guide.center.dy),
          isTrue,
          reason: 'Guide geometry follows the enlarged native text.');
      expect(state.inController.text, source);
    });
  }

  testWidgets('zoom arbitration preserves scrolling and caret taps',
      (tester) async {
    final source = 'if ready:\n    ${'payload ' * 100}\n    done()';
    final state = await _mount(tester, source);
    final render = tester
        .state<EditableTextState>(find.byType(EditableText).first)
        .renderEditable;
    final height = render.preferredLineHeight;
    // Blank viewport space allows scrolling without invoking text selection.
    final center = tester.getCenter(find.byType(Editor));
    await tester.dragFrom(center, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(state.horizontalController.offset, greaterThan(0));
    final beforeWheel = state.horizontalController.offset;
    await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(80, 0)));
    await tester.pumpAndSettle();
    expect(state.horizontalController.offset, greaterThan(beforeWheel));

    final beforeTrackpad = state.horizontalController.offset;
    final trackpad =
        await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await trackpad.panZoomStart(center);
    await trackpad.panZoomUpdate(center, pan: const Offset(-100, 0));
    await trackpad.panZoomUpdate(center, pan: const Offset(-160, 0));
    await trackpad.panZoomEnd();
    await tester.pumpAndSettle();
    expect(state.horizontalController.offset, greaterThan(beforeTrackpad));
    expect(render.preferredLineHeight, height,
        reason:
            'One-finger, wheel and trackpad pans must not change font size.');

    state.horizontalController.jumpTo(0);
    state.scrollController.jumpTo(0);
    await tester.pumpAndSettle();
    final caret = render.getLocalRectForCaret(const TextPosition(offset: 3));
    await tester.tapAt(render.localToGlobal(caret.center));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .focusNode!
            .hasFocus,
        isTrue);
    expect(state.inController.selection.isValid, isTrue);
    expect(state.inController.text, source);
  });

  testWidgets('zoom arbitration preserves vertical touch scrolling',
      (tester) async {
    final source = 'if ready:\n'
        '${List.generate(80, (row) => '    step_$row()').join('\n')}';
    final state = await _mount(tester, source);
    final render = tester
        .state<EditableTextState>(find.byType(EditableText).first)
        .renderEditable;
    final height = render.preferredLineHeight;
    await tester.dragFrom(
        tester.getCenter(find.byType(Editor)), const Offset(0, -140));
    await tester.pumpAndSettle();
    expect(state.scrollController.offset, greaterThan(0));
    expect(render.preferredLineHeight, height);
    expect(state.inController.text, source);
  });
}
