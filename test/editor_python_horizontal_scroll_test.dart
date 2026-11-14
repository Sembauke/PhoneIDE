import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await TextMateHighlighterRegistry.instance.initialize();
    await (FontLoader('RobotoMono')
          ..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf')))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'sub-row scrolling reuses guide geometry and updates on newly visible rows',
      (tester) async {
    final text = [
      'if ready:',
      for (var row = 0; row < 300; row++) '    pack($row)',
    ].join('\n');
    final key = GlobalKey<EditorState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 380,
          height: 600,
          child: Editor(
            key: key,
            defaultLanguage: 'python',
            defaultValue: text,
            path: 'vertical-guide-cache.py',
            options: EditorOptions(
              fontFamily: 'RobotoMono',
            ),
          ),
        ),
      ),
    ));
    await settleEditor(tester);
    final state = key.currentState!;
    final rowHeight = state.getTextHeight(tester.element(find.byType(Editor)));
    final start = rowHeight * 30 + 1;
    state.scrollController.jumpTo(start);
    await tester.pump();
    await tester.pump();
    final runs = state.debugGuideSnapshot!.geometry[RegionPosition.inner]!;
    expect(runs, isNotEmpty);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    for (final delta in [.1, .2, .3]) {
      state.scrollController.jumpTo(start + delta);
      await tester.pump();
      await tester.pump();
      expect(
          state.debugGuideSnapshot!.geometry[RegionPosition.inner], same(runs),
          reason: 'Sub-row scrolling must not rebuild the native guide paint.');
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editable));
    }

    state.scrollController.jumpTo(start + rowHeight * 10);
    await tester.pump();
    await tester.pump();
    final updated = state.debugGuideSnapshot!.geometry[RegionPosition.inner]!;
    expect(updated, isNot(same(runs)));
    final caret = editable.renderEditable.getLocalRectForCaret(
        TextPosition(offset: text.indexOf('    pack(45)')));
    final dpr = tester.view.devicePixelRatio;
    final snappedX = (caret.left * dpr).round() / dpr;
    expect(
        updated.any((run) =>
            (run.rect.left - snappedX).abs() < .01 &&
            run.rect.top <= caret.center.dy &&
            run.rect.bottom >= caret.center.dy),
        isTrue);
  });

  testWidgets('fractional horizontal scroll refreshes native pixel phase',
      (tester) async {
    const dpr = 2.625;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = const Size(1280, 2856);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final text =
        '${List.generate(24, (i) => '${'    ' * i}if level_$i:').join('\n')}\n${'    ' * 24}camp()';
    final key = GlobalKey<EditorState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 380,
          height: 600,
          child: Editor(
            key: key,
            defaultLanguage: 'python',
            defaultValue: text,
            path: 'horizontal-pixel-phase.py',
            options: EditorOptions(
              fontFamily: 'RobotoMono',
              fontSize: 17,
            ),
          ),
        ),
      ),
    ));
    await settleEditor(tester);
    final state = key.currentState!;
    state.scrollController
        .jumpTo(state.scrollController.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    final model = state.debugGuideSnapshot!.model;
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    final start = text.lastIndexOf('\n') + 1;
    final guidePainter = editable.renderEditable.painter;
    for (final scroll in [
      0.125,
      80.25,
      state.horizontalController.position.maxScrollExtent
    ]) {
      state.horizontalController.jumpTo(scroll);
      await tester.pump();
      await tester.pump();
      expect(identical(state.debugGuideSnapshot!.model, model), isTrue,
          reason: 'Horizontal scrolling must not rebuild the source model.');
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editable));
      expect(editable.renderEditable.painter, same(guidePainter),
          reason: 'Horizontal pixel-phase changes reuse the guide painter.');
      final runs = state.debugGuideSnapshot!.geometry[RegionPosition.inner]!;
      for (var column = 0; column < 96; column += 4) {
        final caret = editable.renderEditable
            .getLocalRectForCaret(TextPosition(offset: start + column));
        final snappedX = (caret.left * dpr).round() / dpr;
        expect(
            runs.any((run) =>
                (run.rect.left - snappedX).abs() < .01 &&
                run.rect.top <= caret.center.dy &&
                run.rect.bottom >= caret.center.dy),
            isTrue,
            reason: 'Scroll $scroll, column $column: native $caret, guide runs '
                '${runs.map((run) => run.rect).toList()}');
      }
    }
  });
}
