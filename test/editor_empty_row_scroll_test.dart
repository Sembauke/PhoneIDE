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

  for (final dpr in [1.0, 2.625]) {
    testWidgets('trailing blank row keeps native geometry while scrolling $dpr',
        (tester) async {
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = [
        for (var row = 0; row < 120; row++) 'value = $row',
        '',
      ].join('\n');
      final key = GlobalKey<EditorState>();
      final editor = Editor(
          key: key,
          path: 'empty-row-scroll-$dpr.py',
          defaultLanguage: 'python',
          defaultValue: source,
          options: EditorOptions(
              fontFamily: 'RobotoMono',
              fontSize: 16.13,
              activeLineColor: const Color(0xff233344)));
      addTearDown(() async {
        await editor.onTextChange.close();
        await editor.textfieldData.close();
        await editor.editableRegion.close();
      });
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  devicePixelRatio: dpr,
                  textScaler: const TextScaler.linear(1.3)),
              child: Scaffold(
                  body: Padding(
                      padding: const EdgeInsets.only(top: .37),
                      child:
                          SizedBox(width: 380, height: 240, child: editor))))));
      await settleEditor(tester);
      final state = key.currentState!;
      await tester.showKeyboard(find.byType(TextField));
      state.inController.selection =
          TextSelection.collapsed(offset: source.length);
      await tester.pump();
      await tester.pump();
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final selection = TextSelection.collapsed(offset: source.length);
      final endpoint = render.getEndpointsForSelection(selection).single.point;
      final lineHeight = render.preferredLineHeight;
      expect(render.getBoxesForSelection(selection), isEmpty);
      expect(
          state.scrollController.position.maxScrollExtent, greaterThan(1000));
      for (final delta in [0.0, .17, .43, .79, 1.13]) {
        state.scrollController
            .jumpTo(state.scrollController.position.maxScrollExtent - delta);
        await tester.pump();
        await tester.pump();
        final currentEndpoint =
            render.getEndpointsForSelection(selection).single.point;
        expect(currentEndpoint.dy, closeTo(endpoint.dy, .0001),
            reason: 'Native paragraph coordinates do not depend on scrolling.');
        final nativeTop =
            render.localToGlobal(Offset(0, currentEndpoint.dy - lineHeight)).dy;
        final nativeBottom =
            render.localToGlobal(Offset(0, currentEndpoint.dy)).dy;
        final gutter =
            tester.getRect(find.byKey(const ValueKey('phone-ide-line-121')));
        final highlight =
            tester.getRect(find.byKey(const ValueKey('phone-ide-active-line')));
        for (final box in [gutter, highlight]) {
          expect(box.top, closeTo(nativeTop, .0001),
              reason:
                  'DPR $dpr, fractional scroll $delta: native empty-row top');
          expect(box.bottom, closeTo(nativeBottom, .0001),
              reason:
                  'DPR $dpr, fractional scroll $delta: native empty-row bottom');
        }
      }
      expect(state.inController.text, source);
      expect(tester.takeException(), isNull);
    });
  }
}
