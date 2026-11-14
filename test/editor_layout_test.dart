import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/models/textfield_data.dart';
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
      fontFamily: 'RobotoMono',
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
    this.dark = false,
    this.scale = 1,
    this.region,
    this.editable = true,
    this.activeLine = true,
  });

  final String code;
  final String path;
  final bool dark;
  final double scale;
  final EditorRegionOptions? region;
  final bool editable;
  final bool activeLine;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool dark = widget.dark;

  void switchTheme() => setState(() => dark = !dark);
  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderSide: BorderSide(color: _hostBorder, width: 6),
      borderRadius: BorderRadius.all(Radius.circular(30)),
    );
    return MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        platform: TargetPlatform.linux,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
              letterSpacing: 3, wordSpacing: 5, fontWeight: FontWeight.w900),
          bodyMedium: TextStyle(
              letterSpacing: 3, wordSpacing: 5, fontWeight: FontWeight.w900),
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
                ),
                defaultLanguage: 'html',
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
  bool dark = false,
  double scale = 1,
  EditorRegionOptions? region,
  bool editable = true,
  bool activeLine = true,
  GlobalKey<_HostState>? hostKey,
}) async {
  await tester.pumpWidget(
    _Host(
      key: hostKey,
      code: code,
      path: path,
      dark: dark,
      scale: scale,
      region: region,
      editable: editable,
      activeLine: activeLine,
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
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final colors = [
      for (final point in points)
        Color.fromARGB(
          bytes.getUint8(
              (point.dy.floor() * image.width + point.dx.floor()) * 4 + 3),
          bytes.getUint8(
              (point.dy.floor() * image.width + point.dx.floor()) * 4),
          bytes.getUint8(
              (point.dy.floor() * image.width + point.dx.floor()) * 4 + 1),
          bytes.getUint8(
              (point.dy.floor() * image.width + point.dx.floor()) * 4 + 2),
        ),
    ];
    image.dispose();
    return colors;
  }))!;
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
    for (final dark in [false, true]) {
      for (final editable in [false, true]) {
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
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('gutter and code rows align at text scale $scale',
          (tester) async {
        final code = List.generate(20, (i) => 'row ${i + 1}').join('\n');
        final state = await _pump(tester, code: code, scale: scale);
        final field = _fieldFor(state.inController);
        final gutterWidth = tester.getTopLeft(field).dx -
            tester.getTopLeft(find.byType(Editor)).dx;
        expect(gutterWidth,
            greaterThanOrEqualTo(state.widget.options.linebarWidth));
        _expectAligned(_codeGlyph(tester, field, 0), _gutterGlyph(tester, 1));
        _expectAligned(_codeGlyph(tester, field, 6), _gutterGlyph(tester, 2));
        state.scrollController
            .jumpTo(state.scrollController.position.maxScrollExtent);
        await tester.pump();
        expect(state.linebarController.offset, state.scrollController.offset);
        final number = _gutterGlyph(tester, 20);
        expect(number.left, greaterThanOrEqualTo(0));
        expect(number.right, lessThanOrEqualTo(gutterWidth));
      });

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
      // evidence that the last caret remains marked.
      hostKey.currentState!.rebuild();
      await settleEditor(tester);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
      expect(await _pixels(tester, points), [_lightCode, _activeBorder]);
    });

    testWidgets('caret moves in a 400-line document do not rebuild the editor',
        (tester) async {
      final lines = List.generate(400, (index) => 'line ${index + 1}');
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

    for (final bounded in [false, true]) {
      for (final gutter in [false, true]) {
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
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'whole editable region stays marked dark=$dark scale=$scale',
            (tester) async {
          final hostKey = GlobalKey<_HostState>();
          final region = EditorRegionOptions(
            start: 1,
            end: 4,
            color: dark ? const Color(0xFF29216C) : const Color(0xFFF6F6FE),
            borderColor:
                dark ? const Color(0xFFA99BFF) : const Color(0xFF5B4BDB),
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
            _expectAligned(
                _codeGlyph(tester, inner, 0), _gutterGlyph(tester, 2));
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
      }

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
