import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/phone_ide.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

const _editorKey = ValueKey('layout-editor');
const _captureKey = ValueKey('layout-capture');
const _hostFill = Color(0xFFFF00FF);
const _hostBorder = Color(0xFF00FF00);
const _lightCode = Color(0xFFFFFFFF);
const _darkCode = Color(0xFF251E42);
const _activeFill = Color(0x33FFCC00);
const _activeBorder = Color(0xFF7654CC);
const _guideInk = Color(0xFF17A29B);

Finder get _fields => find.byType(TextField);
Finder _fieldFor(TextEditingController controller) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller == controller,
    );

({List<String> changes, List<String> regions, List<TextFieldData> focus})
    _recordEditorEvents(Editor editor) {
  final changes = <String>[];
  final regions = <String>[];
  final focus = <TextFieldData>[];
  final subscriptions = <StreamSubscription<Object?>>[
    editor.onTextChange.stream.listen(changes.add),
    editor.editableRegion.stream.listen(regions.add),
    editor.textfieldData.stream.listen(focus.add),
  ];
  addTearDown(() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  });
  return (changes: changes, regions: regions, focus: focus);
}

Offset _unusedEditorPoint(WidgetTester tester, {bool gutter = false}) {
  final rect = tester.getRect(find.byType(Editor));
  return Offset(gutter ? rect.left + 12 : rect.right - 30, rect.bottom - 30);
}

EditorOptions _options({
  bool dark = false,
  EditorRegionOptions? region,
  bool editable = true,
  bool activeLine = true,
  bool showIndentGuides = true,
  int indentSize = 4,
  String? fontFamily = 'RobotoMono',
}) =>
    EditorOptions(
      backgroundColor: dark ? _darkCode : _lightCode,
      linebarColor: dark ? const Color(0xFF2F2752) : const Color(0xFFFFF1D6),
      linebarTextColor:
          dark ? const Color(0xFFCFC6E6) : const Color(0xFF5E5470),
      textColor: dark ? const Color(0xFFFFF8EC) : const Color(0xFF2B2140),
      cursorColor: const Color(0xFF5B4BDB),
      selectionColor: const Color(0x665B4BDB),
      selectionHandleColor: const Color(0xFF5B4BDB),
      linebarBorderColor: const Color(0xFF3D3466),
      activeLineColor: activeLine ? _activeFill : null,
      activeLineBorderColor: activeLine ? _activeBorder : null,
      showIndentGuides: showIndentGuides,
      showActiveIndentGuide: false,
      indentSize: indentSize,
      indentGuideColor: _guideInk,
      fontFamily: fontFamily,
      fontSize: 14,
      lineHeight: 1.5,
      linebarWidth: 28,
      isEditable: editable,
      regionOptions: region,
    );

class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.code,
    this.path = 'layout.html',
    this.language = 'html',
    this.dark = false,
    this.scale = 1,
    this.region,
    this.editable = true,
    this.activeLine = true,
    this.showIndentGuides = true,
    this.indentSize = 4,
    this.editorFontFamily = 'RobotoMono',
    this.hostFontFamily,
    this.material3 = true,
  });

  final String code;
  final String path;
  final String language;
  final bool dark;
  final double scale;
  final EditorRegionOptions? region;
  final bool editable;
  final bool activeLine;
  final bool showIndentGuides;
  final int indentSize;
  final String? editorFontFamily;
  final String? hostFontFamily;
  final bool material3;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool dark = widget.dark;
  late bool showIndentGuides = widget.showIndentGuides;
  late int indentSize = widget.indentSize;
  late String? hostFontFamily = widget.hostFontFamily;

  void switchTheme() => setState(() => dark = !dark);
  void rebuild() => setState(() {});
  void setGuideVisibility(bool visible) =>
      setState(() => showIndentGuides = visible);
  void setIndentSize(int size) => setState(() => indentSize = size);
  void setHostFont(String font) => setState(() => hostFontFamily = font);

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderSide: BorderSide(color: _hostBorder, width: 6),
      borderRadius: BorderRadius.all(Radius.circular(30)),
    );
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: widget.material3,
        brightness: dark ? Brightness.dark : Brightness.light,
        platform: TargetPlatform.linux,
        textTheme: TextTheme(
          bodyLarge: TextStyle(
              fontFamily: hostFontFamily,
              letterSpacing: 3,
              wordSpacing: 5,
              fontWeight: FontWeight.w900),
          bodyMedium: TextStyle(
              fontFamily: hostFontFamily,
              letterSpacing: 3,
              wordSpacing: 5,
              fontWeight: FontWeight.w900),
          titleMedium: TextStyle(
              fontFamily: hostFontFamily,
              letterSpacing: 3,
              wordSpacing: 5,
              fontWeight: FontWeight.w900),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: _hostFill,
          border: border,
          enabledBorder: border,
          focusedBorder: border,
          disabledBorder: border,
          errorBorder: border,
          focusedErrorBorder: border,
          contentPadding: EdgeInsets.all(32),
        ),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 240),
          textScaler: TextScaler.linear(widget.scale),
        ),
        child: Scaffold(
          body: SizedBox(
            width: 320,
            height: 240,
            child: RepaintBoundary(
              key: _captureKey,
              child: Editor(
                key: _editorKey,
                options: _options(
                  dark: dark,
                  region: widget.region,
                  editable: widget.editable,
                  activeLine: widget.activeLine,
                  showIndentGuides: showIndentGuides,
                  indentSize: indentSize,
                  fontFamily: widget.editorFontFamily,
                ),
                defaultLanguage: widget.language,
                defaultValue: widget.code,
                path: widget.path,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<EditorState> _pump(
  WidgetTester tester, {
  String code = '<h1>Hello</h1>\n<p>World</p>',
  String path = 'layout.html',
  String language = 'html',
  bool dark = false,
  double scale = 1,
  EditorRegionOptions? region,
  bool editable = true,
  bool activeLine = true,
  bool showIndentGuides = true,
  int indentSize = 4,
  String? editorFontFamily = 'RobotoMono',
  String? hostFontFamily,
  bool material3 = true,
  GlobalKey<_HostState>? hostKey,
}) async {
  await tester.pumpWidget(
    _Host(
      key: hostKey,
      code: code,
      path: path,
      language: language,
      dark: dark,
      scale: scale,
      region: region,
      editable: editable,
      activeLine: activeLine,
      showIndentGuides: showIndentGuides,
      indentSize: indentSize,
      editorFontFamily: editorFontFamily,
      hostFontFamily: hostFontFamily,
      material3: material3,
    ),
  );
  await settleEditor(tester);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  return tester.state<EditorState>(find.byType(Editor));
}

Rect _codeGlyph(WidgetTester tester, Finder field, int offset) {
  final editable = tester
      .state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      )
      .renderEditable;
  final box = editable
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .single;
  return box.toRect().shift(editable.localToGlobal(Offset.zero));
}

Rect _gutterGlyph(WidgetTester tester, int line) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.text('$line'), matching: find.byType(RichText)),
  );
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: '$line'.length),
        boxHeightStyle: ui.BoxHeightStyle.strut,
      )
      .single;
  return box.toRect().shift(paragraph.localToGlobal(Offset.zero));
}

void _expectAligned(Rect code, Rect gutter) {
  expect(code.top, closeTo(gutter.top, 1));
  expect(code.bottom, closeTo(gutter.bottom, 1));
}

Finder _regionMarker(Finder field, EditorRegionOptions region) => find
    .ancestor(
      of: field,
      matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == region.color),
    )
    .first;

Future<List<Color>> _pixels(WidgetTester tester, List<Offset> points) async {
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final dpr = tester.view.devicePixelRatio;
    final image = await boundary.toImage(pixelRatio: dpr);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final colors = [
      for (final point in points)
        Color.fromARGB(
          bytes.getUint8(((point.dy * dpr).floor() * image.width +
                      (point.dx * dpr).floor()) *
                  4 +
              3),
          bytes.getUint8(((point.dy * dpr).floor() * image.width +
                  (point.dx * dpr).floor()) *
              4),
          bytes.getUint8(((point.dy * dpr).floor() * image.width +
                      (point.dx * dpr).floor()) *
                  4 +
              1),
          bytes.getUint8(((point.dy * dpr).floor() * image.width +
                      (point.dx * dpr).floor()) *
                  4 +
              2),
        ),
    ];
    image.dispose();
    return colors;
  }))!;
}

Future<bool> _hasGuideAt(WidgetTester tester, Offset point) async {
  final pixels = await _pixels(tester, [
    for (var x = point.dx.floor() - 1.0;
        x <= point.dx.ceil() + 1;
        x += 1 / tester.view.devicePixelRatio)
      for (var y = point.dy.floor() - 1; y <= point.dy.ceil() + 1; y++)
        Offset(x.toDouble(), y.toDouble()),
  ]);
  return pixels.contains(_guideInk);
}

Future<int> _guideCountAtRow(WidgetTester tester, double y) async {
  final rect = tester.getRect(find.byType(Editor));
  final pixels = await _pixels(tester, [
    for (var x = rect.left.ceilToDouble();
        x < rect.right.floor();
        x += 1 / tester.view.devicePixelRatio)
      Offset(x.toDouble(), y),
  ]);
  var count = 0;
  var wasGuide = false;
  for (final color in pixels) {
    final isGuide = color == _guideInk;
    if (isGuide && !wasGuide) count++;
    wasGuide = isGuide;
  }
  return count;
}

Offset _guidePoint(WidgetTester tester, Finder field, int whitespaceOffset) {
  final glyph = _codeGlyph(tester, field, whitespaceOffset);
  return Offset(glyph.left, glyph.center.dy);
}

Future<void> _replaceSelectionAsUser(
  WidgetTester tester,
  EditorState state,
  String inserted, {
  TextSelection? selection,
  bool composing = false,
  bool settle = true,
}) async {
  final controller = state.inController;
  final field = _fieldFor(controller);
  await tester.showKeyboard(field);
  await settleEditor(tester);
  final range =
      selection ?? TextSelection.collapsed(offset: controller.text.length);
  controller.selection = range;
  await tester.pump();
  final nextText =
      controller.text.replaceRange(range.start, range.end, inserted);
  final caret = range.start + inserted.length;
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: caret),
    composing:
        composing ? TextRange(start: 0, end: nextText.length) : TextRange.empty,
  ));
  if (settle) {
    await settleEditor(tester);
  } else {
    await tester.pump();
  }
}

Future<void> _deleteAsUser(
  WidgetTester tester,
  EditorState state, {
  TextSelection? selection,
  bool forward = false,
  bool composing = false,
}) async {
  final controller = state.inController;
  await tester.showKeyboard(_fieldFor(controller));
  await settleEditor(tester);
  final range =
      selection ?? TextSelection.collapsed(offset: controller.text.length);
  controller.selection = range;
  await tester.pump();
  final start = range.isCollapsed && !forward ? range.start - 1 : range.start;
  final end = range.isCollapsed && forward ? range.end + 1 : range.end;
  final nextText = controller.text.replaceRange(start, end, '');
  tester.testTextInput.updateEditingValue(TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: start),
    composing:
        composing ? TextRange(start: 0, end: nextText.length) : TextRange.empty,
  ));
  await settleEditor(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('RobotoMono')
          ..addFont(rootBundle.load('assets/fonts/RobotoMono-Regular.ttf')))
        .load();
    await TextMateHighlighterRegistry.instance.initialize();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Appearance and geometry', () {
    for (final (dark, editable) in [(false, true), (true, false)]) {
      testWidgets(
          'host field decoration does not leak dark=$dark editable=$editable',
          (tester) async {
        final state = await _pump(tester, dark: dark, editable: editable);
        expect(_fields, findsOneWidget);
        expect(find.text('1'), findsOneWidget);
        final field = tester.widget<TextField>(_fields);
        final decoration = tester
            .widget<InputDecorator>(
              find.descendant(
                  of: _fields, matching: find.byType(InputDecorator)),
            )
            .decoration;
        for (final border in [
          decoration.border,
          decoration.enabledBorder,
          decoration.focusedBorder,
          decoration.disabledBorder,
          decoration.errorBorder,
          decoration.focusedErrorBorder,
        ]) {
          expect(border, InputBorder.none);
        }
        expect(decoration.filled, isFalse);
        expect(field.style!.color, state.widget.options.textColor);
        expect(field.cursorColor, state.widget.options.cursorColor);
        field.focusNode!.requestFocus();
        await settleEditor(tester);
        final text = tester.widget<EditableText>(find.byType(EditableText));
        expect(text.selectionColor, state.widget.options.selectionColor);
        expect(text.style.letterSpacing, 0);
        expect(text.style.wordSpacing, 0);
        expect(text.style.fontWeight, FontWeight.w400);
      });
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('three-digit gutter expands without clipping at scale $scale',
          (tester) async {
        final code = List.generate(120, (i) => 'row ${i + 1}').join('\n');
        final state = await _pump(tester, code: code, scale: scale);
        state.scrollController
            .jumpTo(state.scrollController.position.maxScrollExtent);
        await tester.pump();
        final field = _fieldFor(state.inController);
        final gutterWidth = tester.getTopLeft(field).dx -
            tester.getTopLeft(find.byType(Editor)).dx;
        expect(gutterWidth, greaterThan(state.widget.options.linebarWidth));
        final number = _gutterGlyph(tester, 120);
        expect(number.left, greaterThanOrEqualTo(0));
        expect(number.right, lessThanOrEqualTo(gutterWidth));
        _expectAligned(
          _codeGlyph(tester, field, code.lastIndexOf('row 120')),
          number,
        );
      });

      testWidgets(
          'editable regions retain the gutter row rhythm at scale $scale',
          (tester) async {
        const code = 'before 1\nbefore 2\ninside 1\ninside 2\nafter 1\nafter 2';
        final state = await _pump(
          tester,
          code: code,
          scale: scale,
          region: EditorRegionOptions(start: 2, end: 5),
        );
        expect(_fields, findsNWidgets(3));
        _expectAligned(
          _codeGlyph(tester, _fieldFor(state.beforeController), 0),
          _gutterGlyph(tester, 1),
        );
        _expectAligned(
          _codeGlyph(tester, _fieldFor(state.inController), 0),
          _gutterGlyph(tester, 3),
        );
        state.scrollController
            .jumpTo(state.scrollController.position.maxScrollExtent);
        await tester.pump();
        _expectAligned(
          _codeGlyph(tester, _fieldFor(state.afterController), 0),
          _gutterGlyph(tester, 5),
        );
      });
    }

    testWidgets('horizontal scrolling moves code while gutter stays fixed',
        (tester) async {
      final state = await _pump(tester, code: 'A${' long line' * 100}\nB');
      final field = _fieldFor(state.inController);
      final codeBefore = _codeGlyph(tester, field, 0);
      final gutterBefore = _gutterGlyph(tester, 1);
      state.horizontalController.jumpTo(250);
      await tester.pump();
      expect(
          _codeGlyph(tester, field, 0).left, closeTo(codeBefore.left - 250, 1));
      expect(_gutterGlyph(tester, 1), gutterBefore);
    });
  });

  group('Editing and active line', () {
    testWidgets('typing and undo emit the current source', (tester) async {
      final state = await _pump(tester, code: 'original');
      final changes = _recordEditorEvents(state.widget).changes;
      await tester.showKeyboard(_fieldFor(state.inController));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(_fieldFor(state.inController), 'edited');
      await settleEditor(tester);
      expect(changes.last, 'edited');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settleEditor(tester);
      expect(state.inController.text, 'original');
      expect(changes.last, 'original');
    });

    testWidgets(
        'active row follows selection and retains the last caret on blur',
        (tester) async {
      final hostKey = GlobalKey<_HostState>();
      final state =
          await _pump(tester, hostKey: hostKey, code: 'first\nsecond');
      final field = _fieldFor(state.inController);
      final first = _codeGlyph(tester, field, 0);
      final second = _codeGlyph(tester, field, 6);
      final x = tester.getTopLeft(field).dx + 1;
      final points = [Offset(x, first.center.dy), Offset(x, second.center.dy)];
      await tester.showKeyboard(field);
      state.inController.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(await _pixels(tester, points), [_activeBorder, _lightCode]);
      state.inController.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();
      expect(await _pixels(tester, points), [_lightCode, _activeBorder]);

      FocusManager.instance.primaryFocus?.unfocus();
      // Force an Editor rebuild after losing focus; a retained old paint is not
      // proof that the last caret remains marked.
      hostKey.currentState!.rebuild();
      await settleEditor(tester);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      expect(await _pixels(tester, points), [_lightCode, _activeBorder]);
    });

    testWidgets('caret moves in a 400-line document do not rebuild the editor',
        (tester) async {
      final lines = List.generate(
          400, (index) => '${' ' * (4 * (index % 4 + 1))}line ${index + 1}');
      final state = await _pump(
        tester,
        code: lines.join('\n'),
        region: EditorRegionOptions(start: 199, end: 203),
      );
      final field = _fieldFor(state.inController);
      await tester.showKeyboard(field);
      await settleEditor(tester);
      final editorElement = tester.element(find.byType(Editor));
      final events = _recordEditorEvents(state.widget);
      final widthBefore = state.horizontalController.position.maxScrollExtent;
      var editorBuilds = 0;
      final previousCallback = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previousCallback?.call(element, builtOnce);
        if (element == editorElement) editorBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previousCallback);
      for (var offset = 0; offset <= state.inController.text.length; offset++) {
        state.inController.selection = TextSelection.collapsed(offset: offset);
        await tester.pump();
      }
      expect(editorBuilds, 0,
          reason: 'Selection must only update its small active-line overlay.');
      expect(state.horizontalController.position.maxScrollExtent, widthBefore);
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);

      // A real edit still has to update layout: make a line wider than the viewport.
      await tester.enterText(field, 'long identifier ${'wide ' * 100}');
      await settleEditor(tester);
      expect(editorBuilds, greaterThan(0));
      expect(state.horizontalController.position.maxScrollExtent,
          greaterThan(widthBefore));
      expect(events.changes.last, contains('long identifier'));
    });
  });

  group('Enter indentation', () {
    testWidgets(
        'Enter preserves leading indentation and emits the inserted spaces',
        (tester) async {
      const code = '    work';
      final state = await _pump(tester, code: code);
      final events = _recordEditorEvents(state.widget);
      await _replaceSelectionAsUser(tester, state, '\n');
      const expected = '    work\n    ';
      expect(state.inController.text, expected);
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: expected.length));
      expect(events.changes, [expected]);
      expect(events.regions, [expected]);
    });

    for (final sample in [
      (code: '\t\twork', indent: '\t\t', language: 'html'),
      (code: '\tif ready:', indent: '\t\t', language: 'python'),
    ]) {
      testWidgets('Enter keeps tabs for ${sample.language} indentation',
          (tester) async {
        final state =
            await _pump(tester, code: sample.code, language: sample.language);
        await _replaceSelectionAsUser(tester, state, '\n');
        final expected = '${sample.code}\n${sample.indent}';
        expect(state.inController.text, expected);
        expect(state.inController.selection,
            TextSelection.collapsed(offset: expected.length));
      });
    }

    for (final sample in [
      (code: '  if (ready) {', indent: '    '),
      (code: 'const values = [', indent: '  '),
      (code: 'call(', indent: '  '),
      (code: '// opening {', indent: ''),
      (code: 'const text = "{"', indent: ''),
      (code: 'function done() {}', indent: ''),
      (code: '/* comment\nopening {', indent: ''),
    ]) {
      testWidgets(
          'JavaScript Enter follows unclosed delimiters: ${sample.code}',
          (tester) async {
        final state = await _pump(tester,
            code: sample.code, language: 'javascript', indentSize: 2);
        await _replaceSelectionAsUser(tester, state, '\n');
        final expected = '${sample.code}\n${sample.indent}';
        expect(state.inController.text, expected);
        expect(state.inController.selection,
            TextSelection.collapsed(offset: expected.length));
      });
    }

    for (final replacing in [false, true]) {
      testWidgets(
          'Enter splits a line and places caret after indent, replacing=$replacing',
          (tester) async {
        final code = replacing ? '    firstREPLACEsecond' : '    firstsecond';
        final state = await _pump(tester, code: code);
        final events = _recordEditorEvents(state.widget);
        await _replaceSelectionAsUser(tester, state, '\n',
            selection:
                TextSelection(baseOffset: 9, extentOffset: replacing ? 16 : 9));
        const expected = '    first\n    second';
        expect(state.inController.text, expected);
        expect(state.inController.selection,
            const TextSelection.collapsed(offset: 14));
        expect(events.changes, [expected]);
        expect(events.regions, [expected]);
      });
    }

    testWidgets('Python multiline paste rebases existing whitespace',
        (tester) async {
      final state = await _pump(tester, code: '    work', language: 'python');
      final events = _recordEditorEvents(state.widget);
      const pasted = '\n  pasted\nnext';
      await _replaceSelectionAsUser(tester, state, pasted);
      const expected = '    work\n      pasted\n    next';
      expect(state.inController.text, expected);
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: expected.length));
      expect(events.changes, [expected]);
    });

    testWidgets('active IME composition is left untouched', (tester) async {
      final state = await _pump(tester, code: 'if ready:', language: 'python');
      final events = _recordEditorEvents(state.widget);
      await _replaceSelectionAsUser(tester, state, '\n', composing: true);
      const expected = 'if ready:\n';
      expect(state.inController.text, expected);
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: expected.length));
      expect(state.inController.value.composing,
          const TextRange(start: 0, end: expected.length));
      expect(events.changes, [expected]);
    });

    for (final beforeDedent in [false, true]) {
      testWidgets(
          'Enter keeps source indentation and follows blank-row context, beforeDedent=$beforeDedent',
          (tester) async {
        final code = beforeDedent ? '    work\ntail' : '    work';
        final state = await _pump(tester, code: code, activeLine: false);
        await _replaceSelectionAsUser(tester, state, '\n',
            selection: const TextSelection.collapsed(offset: 8));
        final expected =
            beforeDedent ? '    work\n    \ntail' : '    work\n    ';
        expect(state.inController.text, expected);
        expect(state.inController.selection,
            const TextSelection.collapsed(offset: 13));
        final field = _fieldFor(state.inController);
        final previousRow = _guidePoint(tester, field, 0);
        final blankRow =
            previousRow + Offset(0, state.getTextHeight(tester.element(field)));
        expect(await _hasGuideAt(tester, blankRow), !beforeDedent);
        if (beforeDedent) {
          expect(
              await _hasGuideAt(
                  tester, _guidePoint(tester, field, expected.indexOf('tail'))),
              isFalse);
        }
      });
    }
  });

  group('Backspace indentation', () {
    testWidgets(
        'Backspace steps eight spaces to four to zero and emits each source',
        (tester) async {
      final state = await _pump(tester, code: '        ');
      final events = _recordEditorEvents(state.widget);
      await _deleteAsUser(tester, state);
      expect(state.inController.text, '    ');
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: 4));
      await _deleteAsUser(tester, state);
      expect(state.inController.text, isEmpty);
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: 0));
      expect(events.changes, ['    ', '']);
      expect(events.regions, ['    ', '']);
    });

    for (final sample in [
      (code: '      ', caret: 6, size: 4, expected: '    ', next: 4),
      (code: '      ', caret: 6, size: 2, expected: '    ', next: 4),
      (code: '\t\t', caret: 2, size: 4, expected: '\t', next: 1),
      (code: ' \t    ', caret: 6, size: 4, expected: ' \t', next: 2),
      (code: '  \t', caret: 3, size: 4, expected: '', next: 0),
      (
        code: '        code',
        caret: 6,
        size: 4,
        expected: '      code',
        next: 4
      ),
    ]) {
      testWidgets(
          'Backspace reaches the preceding logical stop: ${sample.code.codeUnits}, caret=${sample.caret}, size=${sample.size}',
          (tester) async {
        final state =
            await _pump(tester, code: sample.code, indentSize: sample.size);
        final events = _recordEditorEvents(state.widget);
        await _deleteAsUser(tester, state,
            selection: TextSelection.collapsed(offset: sample.caret));
        expect(state.inController.text, sample.expected);
        expect(state.inController.selection,
            TextSelection.collapsed(offset: sample.next));
        expect(events.changes, [sample.expected]);
        expect(events.regions, [sample.expected]);
      });
    }

    for (final sample in [
      (code: '    work    ', caret: 12, expected: '    work   ', next: 11),
      (code: '    work', caret: 6, expected: '    wrk', next: 5),
    ]) {
      testWidgets('Backspace after code deletes one character: ${sample.code}',
          (tester) async {
        final state = await _pump(tester, code: sample.code);
        await _deleteAsUser(tester, state,
            selection: TextSelection.collapsed(offset: sample.caret));
        expect(state.inController.text, sample.expected);
        expect(state.inController.selection,
            TextSelection.collapsed(offset: sample.next));
      });
    }

    testWidgets('deleting one selected space does not behave like Backspace',
        (tester) async {
      final state = await _pump(tester, code: '        code');
      final events = _recordEditorEvents(state.widget);
      await _deleteAsUser(tester, state,
          selection: const TextSelection(baseOffset: 7, extentOffset: 8));
      expect(state.inController.text, '       code');
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: 7));
      expect(events.changes, ['       code']);
    });

    testWidgets('forward Delete removes just the next space', (tester) async {
      final state = await _pump(tester, code: '        code');
      await _deleteAsUser(tester, state,
          forward: true, selection: const TextSelection.collapsed(offset: 4));
      expect(state.inController.text, '       code');
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: 4));
    });

    testWidgets('composing deletion is not expanded to an indentation stop',
        (tester) async {
      final state = await _pump(tester, code: '        code');
      await _deleteAsUser(tester, state,
          composing: true, selection: const TextSelection.collapsed(offset: 8));
      expect(state.inController.text, '       code');
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: 7));
      expect(state.inController.value.composing,
          const TextRange(start: 0, end: 11));
    });

    testWidgets(
        'Backspace at column zero joins lines without removing their indentation',
        (tester) async {
      final state = await _pump(tester, code: 'first\n    second');
      await _deleteAsUser(tester, state,
          selection: const TextSelection.collapsed(offset: 6));
      expect(state.inController.text, 'first    second');
      expect(state.inController.selection,
          const TextSelection.collapsed(offset: 5));
    });
  });

  group('Blank-row block context', () {
    for (final sample in [
      (name: 'bounded spaces', unit: '    ', following: true),
      (name: 'bounded tabs', unit: '\t', following: true),
      (name: 'spaces at EOF', unit: '    ', following: false),
    ]) {
      testWidgets(
          'Backspace keeps surrounding guides through every indent stop: ${sample.name}',
          (tester) async {
        final before = '${sample.unit * 3}before';
        final after = '${sample.unit * 3}after';
        String source(int levels) => [
              before,
              sample.unit * levels,
              if (sample.following) after,
            ].join('\n');
        final state = await _pump(tester, code: source(3), activeLine: false);
        final events = _recordEditorEvents(state.widget);
        final field = _fieldFor(state.inController);
        final rowHeight = state.getTextHeight(tester.element(field));
        final points = [
          for (var level = 0; level < 3; level++)
            _guidePoint(tester, field, level * sample.unit.length) +
                Offset(0, rowHeight),
        ];
        Future<void> expectContextGuides(int blankLevels) async {
          for (var level = 0; level < points.length; level++) {
            expect(await _hasGuideAt(tester, points[level]), isTrue,
                reason:
                    'Surrounding block guide $level must remain with $blankLevels levels of blank-row whitespace.');
          }
        }

        await expectContextGuides(3);
        final blankStart = before.length + 1;
        for (var levels = 2; levels >= 0; levels--) {
          await _deleteAsUser(tester, state,
              selection: TextSelection.collapsed(
                  offset: blankStart + sample.unit.length * (levels + 1)));
          expect(state.inController.text, source(levels));
          expect(
              state.inController.selection,
              TextSelection.collapsed(
                  offset: blankStart + sample.unit.length * levels));
          // At each stop the opaque caret covers that guide column. Move only
          // the caret to existing code before sampling the unchanged blank row.
          state.inController.selection =
              TextSelection.collapsed(offset: before.length);
          await tester.pump();
          await expectContextGuides(levels);
        }
        expect(events.changes, [source(2), source(1), source(0)]);
        expect(events.regions, [source(2), source(1), source(0)]);
      });
    }

    testWidgets(
        'common blank context respects a following dedent and actual code',
        (tester) async {
      const before = '            before';
      const code = '$before\n\n    after';
      final state = await _pump(tester, code: code, activeLine: false);
      final field = _fieldFor(state.inController);
      final rowHeight = state.getTextHeight(tester.element(field));
      final points = [
        for (final column in [0, 4, 8])
          _guidePoint(tester, field, column) + Offset(0, rowHeight),
      ];
      expect(await _hasGuideAt(tester, points[0]), isTrue);
      expect(await _hasGuideAt(tester, points[1]), isFalse);
      expect(await _hasGuideAt(tester, points[2]), isFalse);
      await _replaceSelectionAsUser(tester, state, 'dedented',
          selection: const TextSelection.collapsed(offset: before.length + 1));
      for (final point in points) {
        expect(await _hasGuideAt(tester, point), isFalse,
            reason:
                'A real code row uses its own indentation instead of blank context.');
      }
      expect(state.inController.text, '$before\ndedented\n    after');
    });

    testWidgets('leading CRLF blank rows do not inherit a later block',
        (tester) async {
      const code = '\r\n    \r\n            first';
      final state = await _pump(tester, code: code, activeLine: false);
      final field = _fieldFor(state.inController);
      final rowHeight = state.getTextHeight(tester.element(field));
      final start = code.indexOf('            first');
      for (final column in [0, 4, 8]) {
        final codePoint = _guidePoint(tester, field, start + column);
        expect(await _hasGuideAt(tester, codePoint - Offset(0, 2 * rowHeight)),
            isFalse);
        expect(await _hasGuideAt(tester, codePoint - Offset(0, rowHeight)),
            isFalse);
      }
      expect(state.inController.text, code);
    });
  });

  group('Blank guides derive from code', () {
    testWidgets(
        'arbitrary blank spaces and tabs do not add guides during editing',
        (tester) async {
      const before = '        before';
      const after = '        after';
      String source(String whitespace) => '$before\n$whitespace\n$after';
      final state =
          await _pump(tester, code: source(' ' * 12), activeLine: false);
      final field = _fieldFor(state.inController);
      final first = _codeGlyph(tester, field, 0);
      final rowY = first.center.dy + state.getTextHeight(tester.element(field));
      final blankStart = before.length + 1;
      Future<void> expectOnlyCodeContext() async {
        state.inController.selection =
            const TextSelection.collapsed(offset: before.length);
        await tester.pump();
        expect(await _hasGuideAt(tester, Offset(first.left, rowY)), isTrue);
        expect(
            await _hasGuideAt(
                tester, Offset(first.left + 4 * first.width, rowY)),
            isTrue);
        expect(await _guideCountAtRow(tester, rowY), 2,
            reason:
                'Whitespace-only edits must not create additional guide columns.');
      }

      await expectOnlyCodeContext();
      await _replaceSelectionAsUser(tester, state, '${' ' * 8}\t',
          selection: TextSelection.collapsed(offset: blankStart + 12));
      expect(state.inController.text, source('${' ' * 20}\t'));
      await expectOnlyCodeContext();
      var currentLength = 21;
      for (final spaces in [20, 16, 12, 8, 4, 0]) {
        await _deleteAsUser(tester, state,
            selection:
                TextSelection.collapsed(offset: blankStart + currentLength));
        expect(state.inController.text, source(' ' * spaces));
        expect(state.inController.selection,
            TextSelection.collapsed(offset: blankStart + spaces));
        currentLength = spaces;
        await expectOnlyCodeContext();
      }
    });

    for (final following in [true, false]) {
      for (final spaces in [0, 24]) {
        testWidgets(
            'Python blank guides use structural columns and EOF outer level, following=$following spaces=$spaces',
            (tester) async {
          const header = '        if ready:';
          final code = [header, ' ' * spaces, if (following) '            body']
              .join('\n');
          final state = await _pump(tester,
              code: code, language: 'python', activeLine: false);
          final field = _fieldFor(state.inController);
          final first = _codeGlyph(tester, field, 0);
          final rowY =
              first.center.dy + state.getTextHeight(tester.element(field));
          final expectedColumns = following ? [0, 8] : <int>[];
          for (final column in [0, 4, 8]) {
            expect(
                await _hasGuideAt(
                    tester, Offset(first.left + column * first.width, rowY)),
                expectedColumns.contains(column));
          }
          expect(await _guideCountAtRow(tester, rowY), expectedColumns.length);
          expect(state.inController.text, code);
        });
      }
    }

    for (final sample in [
      (
        name: 'JavaScript multiline comment',
        language: 'javascript',
        code: '        /*\n        if (ready) {\n',
        count: 2,
      ),
      (
        name: 'JavaScript block opening',
        language: 'javascript',
        code: '        if (ready) {\n',
        count: 3,
      ),
    ]) {
      testWidgets('blank context recognizes actual syntax: ${sample.name}',
          (tester) async {
        final state = await _pump(tester,
            code: sample.code, language: sample.language, activeLine: false);
        final field = _fieldFor(state.inController);
        final previousStart =
            sample.code.lastIndexOf('\n', sample.code.length - 2) + 1;
        final first = _codeGlyph(tester, field, previousStart);
        final rowY =
            first.center.dy + state.getTextHeight(tester.element(field));
        expect(await _guideCountAtRow(tester, rowY), sample.count);
        for (var level = 0; level < sample.count; level++) {
          expect(
              await _hasGuideAt(
                  tester, Offset(first.left + level * 4 * first.width, rowY)),
              isTrue);
        }
        expect(state.inController.text, sample.code);
      });
    }

    testWidgets('a document containing only whitespace has no guides',
        (tester) async {
      const code = '            \t\n    \r\n';
      final state = await _pump(tester, code: code, activeLine: false);
      final field = _fieldFor(state.inController);
      final rowHeight = state.getTextHeight(tester.element(field));
      final top = tester.getRect(field).top;
      for (var row = 0; row < 3; row++) {
        expect(await _guideCountAtRow(tester, top + (row + .5) * rowHeight), 0);
      }
      expect(state.inController.text, code);
    });

    testWidgets(
        'typing actual code at extra indentation adds the corresponding guide',
        (tester) async {
      const before = '        before';
      const code = '$before\n            \n        after';
      final state = await _pump(tester, code: code, activeLine: false);
      final field = _fieldFor(state.inController);
      final first = _codeGlyph(tester, field, 0);
      final rowY = first.center.dy + state.getTextHeight(tester.element(field));
      expect(await _guideCountAtRow(tester, rowY), 2);
      await _replaceSelectionAsUser(tester, state, 'actual',
          selection:
              const TextSelection.collapsed(offset: before.length + 1 + 12));
      expect(await _guideCountAtRow(tester, rowY), 3);
      expect(
          await _hasGuideAt(tester, Offset(first.left + 8 * first.width, rowY)),
          isTrue);
      expect(state.inController.text,
          '$before\n            actual\n        after');
    });
  });

  group('Indentation guides', () {
    for (final dark in [false, true]) {
      testWidgets(
          'caret blank guides persist through cursor blinking and hide without focus, dark=$dark',
          (tester) async {
        const code = '    if ready:';
        final state =
            await _pump(tester, code: code, language: 'python', dark: dark);
        await _replaceSelectionAsUser(tester, state, '\n', settle: false);
        const expected = '    if ready:\n        ';
        expect(state.inController.text, expected);
        expect(state.inController.selection,
            const TextSelection.collapsed(offset: expected.length));
        final field = _fieldFor(state.inController);
        final initial = _codeGlyph(tester, field, 0);
        final rowHeight = state.getTextHeight(tester.element(field));
        final rowY = initial.center.dy + rowHeight;
        final guides = [
          Offset(initial.left, rowY),
          Offset(initial.left + 4 * initial.width, rowY),
        ];
        final cursorColumn = Offset(initial.left + 8 * initial.width, rowY);
        Future<void> expectDistinctGuides() async {
          for (final point in guides) {
            expect(await _hasGuideAt(tester, point), isTrue,
                reason:
                    'Both ancestor and new block guides must be painted, not just the caret.');
          }
          expect(await _hasGuideAt(tester, cursorColumn), isFalse,
              reason:
                  'The caret column is separate from indentation guide columns.');
        }

        await tester.pump();
        await expectDistinctGuides();
        await tester.pump(const Duration(milliseconds: 600));
        await expectDistinctGuides();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(state.debugGuideSnapshot!.focused, isFalse);
        expect(state.debugGuideSnapshot!.columns(1), isEmpty);
        expect(
            state.debugGuideSnapshot!.geometry[RegionPosition.inner]!.where(
                (run) =>
                    run.rect.top <= rowHeight * 1.5 &&
                    run.rect.bottom > rowHeight * 1.5),
            isEmpty);
        for (final point in guides) {
          expect(await _hasGuideAt(tester, point), isFalse);
        }
        await tester.showKeyboard(field);
        await tester.pump();
        await tester.pump();
        await expectDistinctGuides();
        expect(state.inController.text, expected);
      });
    }

    testWidgets('mixed tabs and spaces align guides with rendered whitespace',
        (tester) async {
      const code = 'root\n\t    nested\n  \t    mixed\ntail';
      final state = await _pump(tester, code: code, activeLine: false);
      final field = _fieldFor(state.inController);
      final tabFirst = code.indexOf('\t    nested');
      final spacesFirst = code.indexOf('  \t    mixed');
      for (final offset in [
        tabFirst,
        tabFirst + 1,
        spacesFirst,
        spacesFirst + 3
      ]) {
        expect(await _hasGuideAt(tester, _guidePoint(tester, field, offset)),
            isTrue);
      }
      expect(
          await _hasGuideAt(
              tester, _guidePoint(tester, field, code.indexOf('nested'))),
          isFalse);
      expect(
          await _hasGuideAt(
              tester, _guidePoint(tester, field, code.indexOf('mixed'))),
          isFalse);
    });

    testWidgets(
        'guide geometry updates after typography and indent size change',
        (tester) async {
      final hostKey = GlobalKey<_HostState>();
      const code = 'root\n  child\n    grandchild';
      final state = await _pump(tester,
          code: code, activeLine: false, hostKey: hostKey, indentSize: 2);
      final field = _fieldFor(state.inController);
      final nestedOffset = code.indexOf('    grandchild');
      final oldPoint = _guidePoint(tester, field, nestedOffset + 2);
      expect(await _hasGuideAt(tester, oldPoint), isTrue);
      await _pump(tester,
          code: code,
          activeLine: false,
          hostKey: hostKey,
          indentSize: 2,
          scale: 2);
      expect(tester.state<EditorState>(find.byType(Editor)), same(state));
      final scaledPoint = _guidePoint(tester, field, nestedOffset + 2);
      expect(scaledPoint.dx, greaterThan(oldPoint.dx));
      expect(scaledPoint.dy, greaterThan(oldPoint.dy));
      expect(await _hasGuideAt(tester, scaledPoint), isTrue);
      hostKey.currentState!.setIndentSize(4);
      await settleEditor(tester);
      expect(await _hasGuideAt(tester, scaledPoint), isFalse);
      expect(
          await _hasGuideAt(tester, _guidePoint(tester, field, nestedOffset)),
          isTrue);
      expect(state.inController.text, code);
    });

    for (final material3 in [true, false]) {
      testWidgets(
          'guides follow changing host fonts when unset, Material3=$material3',
          (tester) async {
        final hostKey = GlobalKey<_HostState>();
        const code = 'root\n    child\n        grandchild';
        final state = await _pump(tester,
            code: code,
            activeLine: false,
            hostKey: hostKey,
            editorFontFamily: null,
            hostFontFamily: 'Ahem',
            material3: material3);
        final field = _fieldFor(state.inController);
        final nested = code.indexOf('        grandchild');
        final initialGlyph = _codeGlyph(tester, field, nested + 4);
        final initialPoint = _guidePoint(tester, field, nested + 4);
        expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .style
                .fontFamily,
            'Ahem');
        expect(await _hasGuideAt(tester, initialPoint), isTrue);
        hostKey.currentState!.setHostFont('RobotoMono');
        await settleEditor(tester);
        final nextGlyph = _codeGlyph(tester, field, nested + 4);
        final nextPoint = _guidePoint(tester, field, nested + 4);
        expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .style
                .fontFamily,
            'RobotoMono');
        expect(nextGlyph.width, isNot(closeTo(initialGlyph.width, .1)),
            reason: 'The rendered font must actually change during this test.');
        expect(await _hasGuideAt(tester, nextPoint), isTrue);
        expect(await _hasGuideAt(tester, initialPoint), isFalse);
        expect(state.inController.text, code);
      });
    }

    testWidgets('CRLF blank rows retain common guides without changing source',
        (tester) async {
      final hostKey = GlobalKey<_HostState>();
      const code =
          'root\r\n    child\r\n\r\n  \t \r\n        grandchild\r\n\r\n    sibling\r\n\r\ntail';
      final state =
          await _pump(tester, code: code, activeLine: false, hostKey: hostKey);
      final events = _recordEditorEvents(state.widget);
      final field = _fieldFor(state.inController);
      final base = _guidePoint(tester, field, code.indexOf('    child'));
      final nested =
          _guidePoint(tester, field, code.indexOf('        grandchild') + 4);
      final rowHeight = state.getTextHeight(tester.element(field));
      final top = tester.getRect(field).top;
      for (final row in [2, 3, 5]) {
        final y = top + (row + .5) * rowHeight;
        expect(await _hasGuideAt(tester, Offset(base.dx, y)), isTrue,
            reason:
                'Empty and whitespace-only CRLF rows connect the surrounding block.');
        expect(await _hasGuideAt(tester, Offset(nested.dx, y)), isFalse);
      }
      expect(await _hasGuideAt(tester, Offset(base.dx, top + 7.5 * rowHeight)),
          isFalse);
      hostKey.currentState!.rebuild();
      await settleEditor(tester);
      expect(state.inController.text, code);
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);
    });

    testWidgets('guides scroll with code vertically and horizontally',
        (tester) async {
      final lines =
          List.generate(40, (index) => '${' ' * 24}row $index ${'wide ' * 12}');
      final code = lines.join('\n');
      final state = await _pump(tester, activeLine: false, code: code);
      final field = _fieldFor(state.inController);
      final firstPoint = _guidePoint(tester, field, 20);
      expect(await _hasGuideAt(tester, firstPoint), isTrue);
      final rowHeight = state.getTextHeight(tester.element(field));
      const horizontalOffset = 40.0;
      state.horizontalController.jumpTo(horizontalOffset);
      state.scrollController.jumpTo(8 * rowHeight);
      await tester.pump();
      final lineTenOffset = lines
          .take(10)
          .fold<int>(0, (length, line) => length + line.length + 1);
      final visiblePoint = _guidePoint(tester, field, lineTenOffset + 20);
      expect(visiblePoint.dx, closeTo(firstPoint.dx - horizontalOffset, 1));
      expect(visiblePoint.dy, closeTo(firstPoint.dy + 2 * rowHeight, 1));
      expect(await _hasGuideAt(tester, visiblePoint), isTrue);
    });

    testWidgets(
        'editing indentation repaints guides without changing the source',
        (tester) async {
      const original = 'root\n    child\ntail';
      final state = await _pump(tester, activeLine: false, code: original);
      final field = _fieldFor(state.inController);
      final events = _recordEditorEvents(state.widget);
      final outer = _guidePoint(tester, field, original.indexOf('    child'));
      expect(await _hasGuideAt(tester, outer), isTrue);
      const nested = 'root\n        child\ntail';
      await tester.enterText(field, nested);
      await settleEditor(tester);
      final inner =
          _guidePoint(tester, field, nested.indexOf('        child') + 4);
      expect(await _hasGuideAt(tester, outer), isTrue);
      expect(await _hasGuideAt(tester, inner), isTrue);
      const dedented = 'root\nchild\ntail';
      await tester.enterText(field, dedented);
      await settleEditor(tester);
      expect(await _hasGuideAt(tester, outer), isFalse);
      expect(await _hasGuideAt(tester, inner), isFalse);
      expect(state.inController.text, dedented);
      expect(events.changes, [nested, dedented]);
    });

    testWidgets('guides cross editable boundaries and empty insertion rows',
        (tester) async {
      const code = '    before\n    after';
      final state = await _pump(
        tester,
        activeLine: false,
        code: code,
        region: EditorRegionOptions(start: 1, end: 2),
      );
      final before = _fieldFor(state.beforeController);
      final inner = _fieldFor(state.inController);
      final after = _fieldFor(state.afterController);
      final first = _guidePoint(tester, before, 0);
      final last = _guidePoint(tester, after, 0);
      expect(await _hasGuideAt(tester, first), isTrue);
      expect(await _hasGuideAt(tester, last), isTrue);
      expect(
          await _hasGuideAt(
              tester, Offset(first.dx, tester.getRect(inner).center.dy)),
          isTrue);
      expect(first.dx, closeTo(last.dx, 1));
      expect(state.inController.text, isEmpty);
      await tester.enterText(inner, '        inserted');
      await settleEditor(tester);
      expect(await _hasGuideAt(tester, _guidePoint(tester, inner, 4)), isTrue);
      expect(await _hasGuideAt(tester, _guidePoint(tester, after, 0)), isTrue);
    });

    testWidgets('guides can be disabled and respect the configured indent size',
        (tester) async {
      final hostKey = GlobalKey<_HostState>();
      const code = 'root\n  child\n    grandchild';
      final state = await _pump(tester,
          activeLine: false, code: code, hostKey: hostKey, indentSize: 2);
      final field = _fieldFor(state.inController);
      final child = _guidePoint(tester, field, code.indexOf('  child'));
      final nested =
          _guidePoint(tester, field, code.indexOf('    grandchild') + 2);
      expect(await _hasGuideAt(tester, child), isTrue);
      expect(await _hasGuideAt(tester, nested), isTrue);
      hostKey.currentState!.setGuideVisibility(false);
      await settleEditor(tester);
      expect(await _hasGuideAt(tester, child), isFalse);
      expect(await _hasGuideAt(tester, nested), isFalse);
      expect(state.inController.text, code);
      hostKey.currentState!.setGuideVisibility(true);
      await settleEditor(tester);
      expect(await _hasGuideAt(tester, child), isTrue);
      expect(await _hasGuideAt(tester, nested), isTrue);
    });
  });

  group('Theme lifecycle', () {
    testWidgets('theme updates keep code and reconnect current widget streams',
        (tester) async {
      final hostKey = GlobalKey<_HostState>();
      final state = await _pump(tester, hostKey: hostKey, code: 'original');
      await tester.enterText(_fieldFor(state.inController), 'unsaved edit');
      await settleEditor(tester);
      hostKey.currentState!.switchTheme();
      await settleEditor(tester);
      expect(tester.state<EditorState>(find.byType(Editor)), same(state));
      expect(state.inController.text, 'unsaved edit');
      expect(tester.widget<TextField>(_fields).style!.color,
          const Color(0xFFFFF8EC));
      final events = _recordEditorEvents(state.widget);
      final (:changes, :regions, :focus) = events;
      await tester.tapAt(tester.getTopLeft(_fields) + const Offset(15, 10));
      await tester.enterText(_fields, 'updated after theme');
      await settleEditor(tester);
      expect(changes.last, 'updated after theme');
      expect(regions.last, 'updated after theme');
      expect(focus.last.controller, same(state.inController));
      final data = focus.last;
      data.controller.text = '${data.controller.text})';
      state.widget.textfieldData.add(data);
      await settleEditor(tester);
      expect(changes.last, 'updated after theme)');
      expect(regions.last, 'updated after theme)');
    });
  });

  group('Focus and host integration', () {
    testWidgets('focus is inert but host text updates emit the source',
        (tester) async {
      final state = await _pump(tester, code: 'original');
      final events = _recordEditorEvents(state.widget);
      final (:changes, :regions, :focus) = events;
      await tester.tapAt(tester.getTopLeft(_fields) + const Offset(15, 10));
      await settleEditor(tester);
      expect(focus, isNotEmpty);
      expect(changes, isEmpty);
      expect(regions, isEmpty);
      final data = focus.last;
      data.controller.text = '${data.controller.text})';
      state.widget.textfieldData.add(data);
      await settleEditor(tester);
      expect(changes, ['original)']);
      expect(regions, ['original)']);
    });

    for (final (bounded, gutter) in [(false, false), (true, true)]) {
      testWidgets(
          'unused editor tap focuses inner bounded=$bounded gutter=$gutter',
          (tester) async {
        final state = await _pump(
          tester,
          code: bounded ? 'before\neditable\nafter' : 'editable',
          region: bounded ? EditorRegionOptions(start: 1, end: 3) : null,
        );
        final events = _recordEditorEvents(state.widget);
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.tapAt(_unusedEditorPoint(tester, gutter: gutter));
        await settleEditor(tester);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(
            tester
                .widget<TextField>(_fieldFor(state.inController))
                .focusNode!
                .hasFocus,
            isTrue);
        expect(events.focus.last.position, RegionPosition.inner);
        expect(events.focus.last.controller, same(state.inController));
        expect(state.inController.text, 'editable');
        expect(state.beforeController.text, bounded ? 'before' : '');
        expect(state.afterController.text, bounded ? 'after' : '');
        expect(events.changes, isEmpty);
        expect(events.regions, isEmpty);
      });
    }

    testWidgets('blank editor tap focuses an empty insertion region',
        (tester) async {
      final state = await _pump(
        tester,
        code: 'before\nafter',
        region: EditorRegionOptions(start: 1, end: 2),
      );
      final events = _recordEditorEvents(state.widget);
      await tester.tapAt(_unusedEditorPoint(tester));
      await settleEditor(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
          tester
              .widget<TextField>(_fieldFor(state.inController))
              .focusNode!
              .hasFocus,
          isTrue);
      expect(events.focus.last.position, RegionPosition.inner);
      expect(state.inController.text, isEmpty);
      expect(state.beforeController.text, 'before');
      expect(state.afterController.text, 'after');
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);
    });

    testWidgets('gutter tap restores a lazily unmounted editable region',
        (tester) async {
      final state = await _pump(
        tester,
        code: [
          'before',
          'editable',
          for (var line = 1; line <= 120; line++) 'after $line',
        ].join('\n'),
        region: EditorRegionOptions(start: 1, end: 3),
      );
      final events = _recordEditorEvents(state.widget);
      final focusNode =
          tester.widget<TextField>(_fieldFor(state.inController)).focusNode!;
      state.scrollController
          .jumpTo(state.scrollController.position.maxScrollExtent);
      await settleEditor(tester);
      expect(_fieldFor(state.inController), findsNothing);
      expect(focusNode.context?.mounted ?? false, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tapAt(_unusedEditorPoint(tester, gutter: true));
      await settleEditor(tester);
      expect(_fieldFor(state.inController), findsOneWidget);
      expect(focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      final editorRect = tester.getRect(find.byType(Editor));
      final inputRect = tester.getRect(_fieldFor(state.inController));
      expect(inputRect.top, greaterThanOrEqualTo(editorRect.top));
      expect(inputRect.bottom, lessThanOrEqualTo(editorRect.bottom));
      expect(events.focus.last.position, RegionPosition.inner);
      expect(events.focus.last.controller, same(state.inController));
      expect(state.inController.text, 'editable');
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);
    });

    testWidgets('blank tap reopens a hidden keyboard without moving selection',
        (tester) async {
      final state = await _pump(tester, code: 'editable');
      final events = _recordEditorEvents(state.widget);
      await tester.tapAt(_unusedEditorPoint(tester));
      await settleEditor(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      const selection = TextSelection(baseOffset: 1, extentOffset: 5);
      state.inController.selection = selection;
      await tester.pump();
      tester.testTextInput.hide();
      expect(tester.widget<TextField>(_fields).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tapAt(_unusedEditorPoint(tester));
      await settleEditor(tester);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(state.inController.selection, selection);
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);
    });

    testWidgets('direct before and after code taps retain their own target',
        (tester) async {
      final state = await _pump(
        tester,
        code: 'before\neditable\nafter',
        region: EditorRegionOptions(start: 1, end: 3),
      );
      final events = _recordEditorEvents(state.widget);
      for (final entry in [
        (controller: state.beforeController, position: RegionPosition.before),
        (controller: state.afterController, position: RegionPosition.after),
      ]) {
        final field = _fieldFor(entry.controller);
        await tester.tapAt(tester.getTopLeft(field) + const Offset(15, 10));
        await settleEditor(tester);
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(
            tester
                .widget<TextField>(_fieldFor(state.inController))
                .focusNode!
                .hasFocus,
            isFalse);
        expect(events.focus.last.position, entry.position);
        expect(events.focus.last.controller, same(entry.controller));
        expect(tester.testTextInput.isVisible, isTrue);
      }
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);
    });

    testWidgets('dragging unused editor space does not focus or open keyboard',
        (tester) async {
      final state = await _pump(tester, code: 'editable');
      final events = _recordEditorEvents(state.widget);
      for (final offset in [const Offset(0, -90), const Offset(-90, 0)]) {
        await tester.dragFrom(_unusedEditorPoint(tester), offset);
        await settleEditor(tester);
        expect(tester.widget<TextField>(_fields).focusNode!.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
      }
      expect(events.focus, isEmpty);
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);
    });

    testWidgets('unused read-only editor taps do not summon the keyboard',
        (tester) async {
      final state = await _pump(tester, code: 'read only', editable: false);
      final events = _recordEditorEvents(state.widget);
      for (final gutter in [false, true]) {
        await tester.tapAt(_unusedEditorPoint(tester, gutter: gutter));
        await settleEditor(tester);
        expect(tester.widget<TextField>(_fields).focusNode!.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
      }
      expect(events.focus, isEmpty);
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);
      expect(state.inController.text, 'read only');
    });

    testWidgets('read-only code rejects platform text and host insertions',
        (tester) async {
      final state = await _pump(tester, code: 'read only', editable: false);
      final events = _recordEditorEvents(state.widget);
      final field = _fieldFor(state.inController);
      await tester.tap(field);
      await settleEditor(tester);
      final editable = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      // A read-only field has no input connection, so tester.enterText cannot
      // target it. Send the same platform update directly to test rejection.
      editable.updateEditingValue(const TextEditingValue(
        text: 'replaced from keyboard',
        selection: TextSelection.collapsed(offset: 3),
      ));
      await settleEditor(tester);
      expect(state.inController.text, 'read only');
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);

      state.inController.text = 'replaced from host';
      state.widget.textfieldData.add(TextFieldData(
        controller: state.inController,
        position: RegionPosition.inner,
      ));
      await settleEditor(tester);
      expect(state.inController.text, 'read only');
      expect(events.changes, isEmpty);
      expect(events.regions, isEmpty);
    });
  });

  group('Editable regions', () {
    for (final code in ['\ninside\nafter', 'before\ninside\n']) {
      testWidgets(
          'blank region boundary rows are preserved for ${code.codeUnits}',
          (tester) async {
        final state = await _pump(
          tester,
          code: code,
          region: EditorRegionOptions(start: 1, end: 3),
        );
        expect(find.text('3'), findsOneWidget);
        _expectAligned(
          _codeGlyph(tester, _fieldFor(state.inController), 0),
          _gutterGlyph(tester, 2),
        );
      });
    }

    for (final dark in [false, true]) {
      final scale = dark ? 2.0 : 1.0;
      testWidgets('whole editable region stays marked dark=$dark scale=$scale',
          (tester) async {
        final hostKey = GlobalKey<_HostState>();
        final region = EditorRegionOptions(
          start: 1,
          end: 4,
          color: dark ? const Color(0xFF29216C) : const Color(0xFFF6F6FE),
          borderColor: dark ? const Color(0xFFA99BFF) : const Color(0xFF5B4BDB),
        );
        final state = await _pump(
          tester,
          hostKey: hostKey,
          code: 'before\none\ntwo\nafter',
          dark: dark,
          scale: scale,
          region: region,
          activeLine: false,
        );
        final inner = _fieldFor(state.inController);
        final before = _fieldFor(state.beforeController);
        final after = _fieldFor(state.afterController);
        final marker = _regionMarker(inner, region);
        final rowHeight = state.getTextHeight(tester.element(inner));

        Future<void> expectRegion(int rows, Color background) async {
          final rect = tester.getRect(inner);
          expect(tester.getRect(marker), rect);
          expect(rect.height, closeTo(rows * rowHeight, .01));
          expect(rect.left, tester.getRect(before).left);
          expect(rect.left, tester.getRect(after).left);
          expect(tester.getRect(before).bottom, rect.top);
          expect(tester.getRect(after).top, rect.bottom);
          final rowSamples = [
            for (var row = 0; row < rows; row++) ...[
              Offset(rect.left + 1, rect.top + (row + .5) * rowHeight),
              Offset(tester.getRect(find.byType(Editor)).right - rowHeight,
                  rect.top + (row + .5) * rowHeight),
            ],
          ];
          expect(await _pixels(tester, rowSamples), [
            for (var row = 0; row < rows; row++) ...[
              region.borderColor!,
              region.color,
            ],
          ]);
          expect(
            await _pixels(tester, [
              Offset(tester.getRect(find.byType(Editor)).right - rowHeight,
                  tester.getRect(before).center.dy),
              Offset(tester.getRect(find.byType(Editor)).right - rowHeight,
                  tester.getRect(after).center.dy),
              Offset(rect.left + 1, tester.getRect(before).center.dy),
              Offset(rect.left + 1, tester.getRect(after).center.dy),
            ]),
            List.filled(4, background),
          );
          _expectAligned(_codeGlyph(tester, inner, 0), _gutterGlyph(tester, 2));
          _expectAligned(
            _codeGlyph(tester, after, 0),
            _gutterGlyph(tester, rows + 2),
          );
        }

        expect(tester.widget<TextField>(inner).focusNode!.hasFocus, isFalse);
        await expectRegion(2, dark ? _darkCode : _lightCode);

        await tester.showKeyboard(before);
        await settleEditor(tester);
        await expectRegion(2, dark ? _darkCode : _lightCode);
        await tester.enterText(inner, 'one\ntwo\nthree');
        await settleEditor(tester);
        await tester.showKeyboard(after);
        await settleEditor(tester);
        await expectRegion(3, dark ? _darkCode : _lightCode);
        FocusManager.instance.primaryFocus?.unfocus();
        await settleEditor(tester);
        await expectRegion(3, dark ? _darkCode : _lightCode);
        hostKey.currentState!.switchTheme();
        await settleEditor(tester);
        expect(state.inController.text, 'one\ntwo\nthree');
        await expectRegion(3, dark ? _lightCode : _darkCode);
      });

      testWidgets('empty insertion region is marked without focus dark=$dark',
          (tester) async {
        final region = EditorRegionOptions(
          start: 1,
          end: 2,
          color: dark ? const Color(0xFF29216C) : const Color(0xFFF6F6FE),
          borderColor: dark ? const Color(0xFFA99BFF) : const Color(0xFF5B4BDB),
        );
        final state = await _pump(
          tester,
          code: 'before\nafter',
          dark: dark,
          region: region,
          activeLine: false,
        );
        final field = _fieldFor(state.inController);
        final rect = tester.getRect(field);
        expect(state.inController.text, isEmpty);
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
        expect(rect.height, state.getTextHeight(tester.element(field)));
        expect(
          tester.getRect(_regionMarker(field, region)),
          rect,
        );
        expect(
          await _pixels(tester, [
            Offset(rect.left + 1, rect.center.dy),
            Offset(tester.getRect(find.byType(Editor)).right - rect.height,
                rect.center.dy),
          ]),
          [region.borderColor!, region.color],
        );
      });
    }

    for (final atEnd in [false, true]) {
      testWidgets('an empty editable region accepts insertion atEnd=$atEnd',
          (tester) async {
        final state = await _pump(
          tester,
          code: 'before\nafter',
          region: EditorRegionOptions(start: atEnd ? 2 : 1, end: atEnd ? 3 : 2),
        );
        expect(state.beforeController.text, atEnd ? 'before\nafter' : 'before');
        expect(state.inController.text, isEmpty);
        expect(state.afterController.text, atEnd ? '' : 'after');
        expect(find.text('3'), findsNothing);
        final changes = _recordEditorEvents(state.widget).changes;
        await tester.enterText(_fieldFor(state.inController), 'inserted');
        await settleEditor(tester);
        expect(changes.last,
            atEnd ? 'before\nafter\ninserted' : 'before\ninserted\nafter');
      });
    }

    testWidgets('untouched empty regions stay absent from source and cache',
        (tester) async {
      final state = await _pump(
        tester,
        code: 'before\nafter',
        region: EditorRegionOptions(start: 1, end: 2),
      );
      final changes = _recordEditorEvents(state.widget).changes;
      await tester.enterText(_fieldFor(state.beforeController), 'before\nmore');
      await settleEditor(tester);
      expect(changes.last, 'before\nmore\nafter');
      expect(state.inController.text, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('layout.html'), '2:3');
      await tester.enterText(_fieldFor(state.inController), 'inserted');
      await settleEditor(tester);
      expect(changes.last, 'before\nmore\ninserted\nafter');
      expect(prefs.getString('layout.html'), '2:4');
    });
  });

  group('Insertion row numbering', () {
    testWidgets('an empty insertion row keeps following source line numbers',
        (tester) async {
      final state = await _pump(
        tester,
        code: 'before\nafter',
        region: EditorRegionOptions(start: 1, end: 2),
      );
      expect(state.inController.text, isEmpty);
      expect(find.text('3'), findsNothing);
      _expectAligned(
        _codeGlyph(tester, _fieldFor(state.beforeController), 0),
        _gutterGlyph(tester, 1),
      );
      _expectAligned(
        _codeGlyph(tester, _fieldFor(state.afterController), 0),
        _gutterGlyph(tester, 2),
      );
    });
  });

  group('Lifecycle and reseeding', () {
    testWidgets('removing a focused editor releases its owned resources',
        (tester) async {
      final state = await _pump(tester);
      final editor = state.widget;
      await tester.showKeyboard(_fields);
      await tester.pumpWidget(const SizedBox.shrink());
      await settleEditor(tester);
      expect(editor.textfieldData.hasListener, isFalse);
      expect(() => state.inController.addListener(() {}), throwsFlutterError);
      expect(
          () => state.scrollController.addListener(() {}), throwsFlutterError);
      await editor.onTextChange.close();
      await editor.editableRegion.close();
      await editor.textfieldData.close();
    });

    testWidgets('removing an editor before initialization completes is safe',
        (tester) async {
      await tester.pumpWidget(const _Host(code: 'loading'));
      await tester.pumpWidget(const SizedBox.shrink());
      await settleEditor(tester);
    });

    testWidgets('new defaults reseed the existing editor state',
        (tester) async {
      final state = await _pump(tester, code: 'original');
      await tester.enterText(_fieldFor(state.inController), 'local edit');
      await settleEditor(tester);
      await _pump(tester, code: 'replacement');
      expect(tester.state<EditorState>(find.byType(Editor)), same(state));
      expect(state.inController.text, 'replacement');
      expect(state.beforeController.text, isEmpty);
      expect(state.afterController.text, isEmpty);
    });

    testWidgets("changing only path loads that file's cached region",
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'first.html': '1:3',
        'second.html': '2:4',
      });
      final region = EditorRegionOptions(start: 0, end: 5);
      const code = 'zero\none\ntwo\nthree';
      final state =
          await _pump(tester, code: code, path: 'first.html', region: region);
      expect(state.inController.text, 'one');
      await _pump(tester, code: code, path: 'second.html', region: region);
      expect(tester.state<EditorState>(find.byType(Editor)), same(state));
      expect(state.beforeController.text, 'zero\none');
      expect(state.inController.text, 'two');
      expect(state.afterController.text, 'three');
    });

    testWidgets('changing only region reseeds its controller boundaries',
        (tester) async {
      const code = 'zero\none\ntwo\nthree';
      final state = await _pump(
        tester,
        code: code,
        region: EditorRegionOptions(start: 1, end: 3),
      );
      expect(state.inController.text, 'one');
      await _pump(tester,
          code: code, region: EditorRegionOptions(start: 2, end: 4));
      expect(tester.state<EditorState>(find.byType(Editor)), same(state));
      expect(state.beforeController.text, 'zero\none');
      expect(state.inController.text, 'two');
      expect(state.afterController.text, 'three');
    });

    testWidgets(
        'late initialization cannot replace a newer document or its edits',
        (tester) async {
      final registry = TextMateHighlighterRegistry.instance;
      final delayedAssets = _DelayedAssetBundle();
      registry.configureForTests(assetBundle: delayedAssets);
      await tester
          .pumpWidget(const _Host(code: 'old document', path: 'old.html'));
      final oldInitialization = registry.initialize();
      try {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Allow the replacement to initialize while the obsolete request is pending.
        registry.configureForTests();
        final state =
            await _pump(tester, code: 'new document', path: 'new.html');
        await tester.enterText(
            _fieldFor(state.inController), 'new document edited');
        await settleEditor(tester);
        delayedAssets.release();
        await tester.runAsync(() => oldInitialization);
        await settleEditor(tester);
        expect(state.inController.text, 'new document edited');
        expect(state.widget.path, 'new.html');
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } finally {
        delayedAssets.release();
        await tester.runAsync(() => oldInitialization);
        registry.configureForTests();
        await tester.runAsync(registry.initialize);
      }
    });
  });
}

class _DelayedAssetBundle extends CachingAssetBundle {
  final _ready = Completer<void>();

  void release() {
    if (!_ready.isCompleted) _ready.complete();
  }

  @override
  Future<ByteData> load(String key) async {
    await _ready.future;
    return rootBundle.load(key);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    await _ready.future;
    return rootBundle.loadString(key, cache: cache);
  }
}
