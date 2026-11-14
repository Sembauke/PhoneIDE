import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/editor.dart';
import 'package:phone_ide/editor/editor_options.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editor_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Editor highlighting', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TextMateHighlighterRegistry.instance.configureForTests();
    });

    testWidgets('highlights HTML/CSS/JS and remains editable', (tester) async {
      final samples = [
        (
          language: 'html',
          code: '<div class="x">hello</div>',
          tokens: {
            'div': const Color(0xFFE06C75),
            'x': const Color(0xFF98C379)
          },
        ),
        (
          language: 'css',
          code: 'body { color: red; }',
          tokens: {
            'body': const Color(0xFFE5C07B),
            'red': const Color(0xFF98C379)
          },
        ),
        (
          language: 'javascript',
          code: 'const value = 42;',
          tokens: {
            'const': const Color(0xFFC678DD),
            '42': const Color(0xFFD19A66)
          },
        ),
      ];

      for (final sample in samples) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Editor(
                options: EditorOptions(showLinebar: false),
                defaultLanguage: sample.language,
                defaultValue: sample.code,
                path: 'file.${sample.language}',
              ),
            ),
          ),
        );

        await settleEditor(tester);

        final state = tester.state<EditorState>(find.byType(Editor));
        final context = tester.element(find.byType(Editor));
        final span = state.inController.buildTextSpan(
          context: context,
          style: const TextStyle(),
          withComposing: false,
        );

        expect(span.toPlainText(), sample.code);
        final colors = _characterColors(span);
        for (final token in sample.tokens.entries) {
          final start = sample.code.indexOf(token.key);
          expect(colors.sublist(start, start + token.key.length),
              everyElement(token.value),
              reason:
                  '${sample.language} token ${token.key} must use its syntax color.');
        }

        final editorField = find.byWidgetPredicate(
          (widget) => widget is TextField && !widget.readOnly,
        );
        final newText = '${sample.code}\n// edited';
        await tester.enterText(editorField, newText);
        await tester.pump();

        expect(state.inController.text, newText);
      }
    });

    testWidgets('falls back to plain text when initialization fails',
        (tester) async {
      final logs = <String>[];
      TextMateHighlighterRegistry.instance.configureForTests(
        assetBundle: _FailingAssetBundle(),
        logger: logs.add,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Editor(
              options: EditorOptions(showLinebar: false),
              defaultLanguage: 'html',
              defaultValue: '<p>hello</p>',
              path: 'index.html',
            ),
          ),
        ),
      );

      await settleEditor(tester);

      final state = tester.state<EditorState>(find.byType(Editor));
      final context = tester.element(find.byType(Editor));
      final span = state.inController.buildTextSpan(
        context: context,
        style: const TextStyle(),
        withComposing: false,
      );

      expect(span.toPlainText(), state.inController.text);
      expect(
        logs.any((line) => line.contains('initialization failed')),
        isTrue,
      );

      final editorField = find.byWidgetPredicate(
        (widget) => widget is TextField && !widget.readOnly,
      );
      await tester.enterText(editorField, '<p>fallback still editable</p>');
      await tester.pump();

      expect(state.inController.text, '<p>fallback still editable</p>');
    });
  });
}

List<Color?> _characterColors(TextSpan span, [TextStyle? inherited]) {
  final style = (inherited ?? const TextStyle()).merge(span.style);
  return [
    ...List<Color?>.filled(span.text?.length ?? 0, style.color),
    for (final child in span.children ?? const <InlineSpan>[])
      if (child is TextSpan) ..._characterColors(child, style),
  ];
}

class _FailingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    return Future<ByteData>.error(
      StateError('Simulated load failure for $key'),
    );
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    return Future<String>.error(
      StateError('Simulated load failure for $key'),
    );
  }
}
