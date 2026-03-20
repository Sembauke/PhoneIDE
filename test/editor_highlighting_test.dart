import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/editor.dart';
import 'package:phone_ide/editor/editor_options.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Editor highlighting', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TextMateHighlighterRegistry.instance.configureForTests();
    });

    testWidgets('highlights HTML/CSS/JS and remains editable', (tester) async {
      final samples = <String, String>{
        'html': '<div class="x">hello</div>',
        'css': 'body { color: red; }',
        'javascript': 'const value = 42;',
      };

      for (final entry in samples.entries) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Editor(
                options: EditorOptions(showLinebar: false),
                defaultLanguage: entry.key,
                defaultValue: entry.value,
                path: 'file.${entry.key}',
              ),
            ),
          ),
        );

        await _pumpUntilLoaded(tester);

        final state = tester.state<EditorState>(find.byType(Editor));
        final context = tester.element(find.byType(Editor));
        final span = state.inController.buildTextSpan(
          context: context,
          style: const TextStyle(),
          withComposing: false,
        );

        expect(_containsColorStyle(span), isTrue);

        final editorField = find.byWidgetPredicate(
          (widget) => widget is TextField && !widget.readOnly,
        );
        final newText = '${entry.value}\n// edited';
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

      await _pumpUntilLoaded(tester);

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

bool _containsColorStyle(TextSpan span) {
  if (span.style?.color != null) return true;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan && _containsColorStyle(child)) {
      return true;
    }
  }
  return false;
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

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  fail('Editor did not finish loading in test.');
}
