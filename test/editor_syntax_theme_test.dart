import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/controller/custom_text_controller.dart';
import 'package:phone_ide/editor/editor_syntax_theme.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom themes remain independent of each other and the default',
      () async {
    final registry = TextMateHighlighterRegistry.createForTests();
    await registry.initialize();
    final light = _theme(0xFF101000);
    final dark = _theme(0xFFF0F000);
    const code = 'const value = 42;';

    TextSpan highlight(EditorSyntaxTheme? theme) => registry.buildTextSpan(
          text: code,
          language: 'JS',
          syntaxTheme: theme,
        );
    expect(
        _styleAt(highlight(light), code.indexOf('const')).color, light.keyword);
    expect(
        _styleAt(highlight(dark), code.indexOf('const')).color, dark.keyword);
    expect(_styleAt(highlight(light), code.indexOf('42')).color, light.number);
    expect(_styleAt(highlight(null), 0).color, const Color(0xFFC678DD));

    // Returning to an evicted theme must rebuild its engines without changing defaults.
    for (var i = 0; i < 12; i++) {
      final theme = _theme(0xFF202000 + i * 0x100);
      expect(_styleAt(highlight(theme), 0).color, theme.keyword);
    }
    expect(_styleAt(highlight(light), 0).color, light.keyword);
    expect(_styleAt(highlight(null), 0).color, const Color(0xFFC678DD));
  });

  test('plain fallback uses the requested foreground', () {
    final registry = TextMateHighlighterRegistry.createForTests(logger: (_) {});
    final theme = _theme(0xFF101000);
    for (final language in ['javascript', 'unknown']) {
      final span = registry.buildTextSpan(
        text: 'untouched text',
        language: language,
        syntaxTheme: theme,
        style: const TextStyle(fontSize: 19),
      );
      expect(span.toPlainText(), 'untouched text');
      expect(_styleAt(span, 0).color, theme.foreground);
      expect(_styleAt(span, 0).fontSize, 19);
    }
  });

  test('custom token colors retain independent alpha with identical RGB',
      () async {
    final registry = TextMateHighlighterRegistry.createForTests();
    await registry.initialize();
    const rgb = Color(0xFF123456);
    final theme = EditorSyntaxTheme(
      foreground: rgb.withValues(alpha: .1),
      comment: rgb.withValues(alpha: .37),
      keyword: rgb.withValues(alpha: 0),
      string: rgb.withValues(alpha: .3),
      number: rgb.withValues(alpha: .4),
      type: rgb.withValues(alpha: .5),
      function: rgb.withValues(alpha: .6),
      tag: rgb.withValues(alpha: .7),
      attribute: rgb.withValues(alpha: .8),
      operator: rgb.withValues(alpha: .9),
      punctuation: rgb.withValues(alpha: .2),
      variable: rgb,
    );
    const html = '<div class="box">text</div>\n'
        '<script>const value = 42; console.log("hello"); // comment\n</script>\n'
        '<style>.menu { color: red; }</style>';
    final span = registry.buildTextSpan(
      text: html,
      language: 'html',
      syntaxTheme: theme,
    );
    expect(span.toPlainText(), html);
    for (final entry in {
      'text': theme.foreground,
      'div': theme.tag,
      'class': theme.attribute,
      'box': theme.string,
      'const': theme.keyword,
      '42': theme.number,
      'log': theme.function,
      '// comment': theme.comment,
      '.menu': theme.type,
      'color': theme.attribute,
      '(': theme.punctuation,
    }.entries) {
      expect(_styleAt(span, html.indexOf(entry.key)).color, entry.value,
          reason: 'The ${entry.key} token retains its exact custom color');
    }
    const python = 'if self.value == 3:\n    return "hello" # comment';
    final py = registry.buildTextSpan(
      text: python,
      language: 'python',
      syntaxTheme: theme,
    );
    expect(py.toPlainText(), python);
    expect(_styleAt(py, 0).color, theme.keyword);
    expect(_styleAt(py, python.indexOf('self')).color, theme.variable);
    expect(_styleAt(py, python.indexOf('==')).color, theme.operator);
    expect(_styleAt(py, python.indexOf('3')).color, theme.number);
    expect(_styleAt(py, python.indexOf('hello')).color, theme.string);
    expect(_styleAt(py, python.indexOf('# comment')).color, theme.comment);
  });

  test('custom foreground is preserved when it matches an internal marker',
      () async {
    final registry = TextMateHighlighterRegistry.createForTests();
    await registry.initialize();
    final theme = _theme(0xFF000001);
    final span = registry.buildTextSpan(
      text: 'plain text',
      language: 'html',
      syntaxTheme: theme,
      style: const TextStyle(fontSize: 19),
    );
    expect(span.style!.color, theme.foreground);
    expect(_styleAt(span, 0).color, theme.foreground);
    expect(_styleAt(span, 0).fontSize, 19);
  });

  test(
      'custom punctuation replaces rainbow brackets but preserves literal tokens',
      () async {
    final registry = TextMateHighlighterRegistry.createForTests();
    await registry.initialize();
    final theme = _theme(0xFF101000);
    const code = 'console.log([1, {a: 2}]);\nconst text = "([{}])"; // ([{}])';
    final custom = registry.buildTextSpan(
      text: code,
      language: 'js',
      syntaxTheme: theme,
    );
    final defaultSpan = registry.buildTextSpan(text: code, language: 'js');
    final stringStart = code.indexOf('"');
    final commentStart = code.indexOf('//');
    for (var i = 0; i < code.length; i++) {
      if (!'()[]{}'.contains(code[i])) continue;
      expect(
        _styleAt(custom, i).color,
        i >= commentStart
            ? theme.comment
            : i > stringStart
                ? theme.string
                : theme.punctuation,
      );
    }
    expect(_styleAt(defaultSpan, code.indexOf('(')).color,
        const Color(0xFF5CAEEF));
    expect(custom.toPlainText(), code);
  });

  testWidgets(
      'controllers preserve composition and live themes without editing text',
      (tester) async {
    final registry = TextMateHighlighterRegistry.instance;
    registry.configureForTests();
    await tester.runAsync(registry.initialize);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    final light = _theme(0xFF101000);
    final dark = _theme(0xFFF0F000);
    final first = TextEditingControllerIDE(language: 'js', syntaxTheme: light);
    final second = TextEditingControllerIDE(language: 'js', syntaxTheme: dark);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    const code = 'const value = "hello";';
    const editingValue = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: 15),
      composing: TextRange(start: 3, end: 15),
    );
    first.value = editingValue;
    second.text = code;

    TextSpan render(TextEditingControllerIDE controller,
            {bool composing = true}) =>
        controller.buildTextSpan(
          context: context,
          style: const TextStyle(
              fontSize: 18, decoration: TextDecoration.lineThrough),
          withComposing: composing,
        );
    final firstSpan = render(first);
    expect(firstSpan.toPlainText(), code);
    for (var i = 0; i < code.length; i++) {
      final style = _styleAt(firstSpan, i);
      expect(style.decoration!.contains(TextDecoration.underline),
          i >= 3 && i < 15);
      expect(style.decoration!.contains(TextDecoration.lineThrough), isTrue);
      expect(style.fontSize, 18);
    }
    expect(_styleAt(firstSpan, 0).color, light.keyword);
    expect(_styleAt(render(second), 0).color, dark.keyword);
    expect(_styleAt(render(first, composing: false), 4).decoration,
        TextDecoration.lineThrough);

    var changes = 0;
    first.addListener(() => changes++);
    first.syntaxTheme = dark;
    expect(changes, 1);
    expect(first.value, editingValue);
    expect(_styleAt(render(first), 0).color, dark.keyword);
    first.syntaxTheme = _theme(0xFFF0F000);
    expect(changes, 1);
    first.syntaxTheme = null;
    expect(_styleAt(render(first), 0).color, const Color(0xFFC678DD));
    expect(first.value, editingValue);
  });
}

EditorSyntaxTheme _theme(int base) => EditorSyntaxTheme(
      foreground: Color(base + 1),
      comment: Color(base + 2),
      keyword: Color(base + 3),
      string: Color(base + 4),
      number: Color(base + 5),
      type: Color(base + 6),
      function: Color(base + 7),
      tag: Color(base + 8),
      attribute: Color(base + 9),
      operator: Color(base + 10),
      punctuation: Color(base + 11),
      variable: Color(base + 12),
    );

TextStyle _styleAt(TextSpan span, int position) {
  var offset = 0;
  TextStyle? result;
  void visit(TextSpan span, TextStyle inherited) {
    final style = inherited.merge(span.style);
    final length = span.text?.length ?? 0;
    if (position >= offset && position < offset + length) result = style;
    offset += length;
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) visit(child, style);
    }
  }

  visit(span, const TextStyle());
  return result ?? (throw StateError('No text at $position'));
}
