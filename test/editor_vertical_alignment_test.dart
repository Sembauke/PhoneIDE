import 'dart:math' as math;

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
    await (FontLoader('RobotoMono')
          ..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf')))
        .load();
    await TextMateHighlighterRegistry.instance.initialize();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'real line boxes align guides, highlight and gutter through 2000 lines',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final measurements = <Map<String, Object?>>[];
    for (final fontSize in [14.0, 16.13, 21.0]) {
      for (final scale in [1.0, 1.3]) {
        final lines = List.generate(2000, (row) => 'value = $row');
        lines[0] = '    first()';
        for (final line in [100, 1000, 2000]) {
          lines[line - 2] = 'if ready:';
          lines[line - 1] = line == 100
              ? '    '
              : line == 1000
                  ? '    name = "café 漢字 😀"'
                  : '    last()';
        }
        final key = GlobalKey<EditorState>();
        final editor = Editor(
          key: key,
          defaultLanguage: 'python',
          defaultValue: lines.join('\n'),
          path: 'vertical-$fontSize-$scale.py',
          options: EditorOptions(
            fontFamily: 'RobotoMono',
            fontSize: fontSize,
            activeLineColor: const Color(0xff233344),
          ),
        );
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
                body: SizedBox(width: 380, height: 1700, child: editor)),
          ),
        ));
        await settleEditor(tester);
        await tester.showKeyboard(find.byType(TextField));
        final state = key.currentState!;
        final render = tester
            .state<EditableTextState>(find.byType(EditableText))
            .renderEditable;
        for (final line in [1, 100, 1000, 2000]) {
          var source = state.inController.text;
          var offsets = [
            0,
            for (final m in RegExp('\n').allMatches(source)) m.end
          ];
          var start = offsets[line - 1];
          var end = line < offsets.length ? offsets[line] - 1 : source.length;
          state.inController.selection =
              TextSelection.collapsed(offset: start + 4);
          await tester.pump();
          await tester.pump();
          source = state.inController.text;
          offsets = [0, for (final m in RegExp('\n').allMatches(source)) m.end];
          start = offsets[line - 1];
          end = line < offsets.length ? offsets[line] - 1 : source.length;
          // This oracle comes directly from RenderEditable's shaped paragraph,
          // never the editor's guide model, nominal height or row arithmetic.
          final boxes = render.getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: end));
          expect(boxes, isNotEmpty,
              reason: 'Native line box for source line $line');
          final textTop = boxes.map((box) => box.top).reduce(math.min);
          final textBottom = boxes.map((box) => box.bottom).reduce(math.max);
          state.scrollController.jumpTo((textTop - 120)
              .clamp(0.0, state.scrollController.position.maxScrollExtent));
          await tester.pump();
          await tester.pump();
          final globalTop = render.localToGlobal(Offset(0, textTop)).dy;
          final globalBottom = render.localToGlobal(Offset(0, textBottom)).dy;
          final highlight = tester
              .getRect(find.byKey(const ValueKey('phone-ide-active-line')));
          final gutterFinder = find.byKey(ValueKey('phone-ide-line-$line'));
          final gutter = gutterFinder.evaluate().isEmpty
              ? null
              : tester.getRect(gutterFinder);
          final runs =
              state.debugGuideSnapshot!.geometry[RegionPosition.inner]!;
          // Each target has a one-row body, so its guide must end at this row,
          // rather than accidentally passing through it on its way elsewhere.
          final candidates = runs.toList()
            ..sort((a, b) => (a.rect.center.dy - (textTop + textBottom) / 2)
                .abs()
                .compareTo(
                    (b.rect.center.dy - (textTop + textBottom) / 2).abs()));
          final guide = candidates.firstOrNull?.rect;
          final errors = <String, double>{
            'guide_top': guide == null ? 999999 : guide.top - textTop,
            'guide_bottom': guide == null ? 999999 : guide.bottom - textBottom,
            'highlight_top': highlight.top - globalTop,
            'highlight_bottom': highlight.bottom - globalBottom,
            'gutter_top': gutter == null ? 999999 : gutter.top - globalTop,
            'gutter_bottom':
                gutter == null ? 999999 : gutter.bottom - globalBottom,
          };
          measurements.add({
            'font_size': fontSize,
            'system_scale': scale,
            'line': line,
            'nominal_row_height':
                state.getTextHeight(tester.element(find.byType(Editor))),
            'native_top': textTop,
            'native_bottom': textBottom,
            'errors': errors,
            'gutter_present': gutter != null,
            'guide_present': guide != null,
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await editor.onTextChange.close();
        await editor.textfieldData.close();
        await editor.editableRegion.close();
      }
    }
    final failures = [
      for (final sample in measurements)
        for (final error in (sample['errors']! as Map<String, double>).entries)
          if (error.value.abs() > .5)
            'font=${sample['font_size']} scale=${sample['system_scale']} line=${sample['line']} ${error.key}=${error.value}',
    ];
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
