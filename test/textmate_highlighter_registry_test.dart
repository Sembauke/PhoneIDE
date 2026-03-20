import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextMateHighlighterRegistry', () {
    test('canonicalizes supported language aliases', () {
      expect(TextMateHighlighterRegistry.canonicalizeLanguage('HTML'), 'html');
      expect(TextMateHighlighterRegistry.canonicalizeLanguage('htm'), 'html');
      expect(TextMateHighlighterRegistry.canonicalizeLanguage('css'), 'css');
      expect(
          TextMateHighlighterRegistry.canonicalizeLanguage('JS'), 'javascript');
      expect(
        TextMateHighlighterRegistry.canonicalizeLanguage('javascript'),
        'javascript',
      );
      expect(TextMateHighlighterRegistry.canonicalizeLanguage('dart'), isNull);
      expect(TextMateHighlighterRegistry.canonicalizeLanguage('  '), isNull);
    });

    test('unsupported language falls back to plain text and logs once', () {
      final logs = <String>[];
      final registry = TextMateHighlighterRegistry.createForTests(
        logger: logs.add,
      );

      final first = registry.buildTextSpan(
        text: 'print("hello")',
        language: 'python',
        style: const TextStyle(),
      );
      final second = registry.buildTextSpan(
        text: 'print("world")',
        language: 'python',
        style: const TextStyle(),
      );

      expect(first.toPlainText(), 'print("hello")');
      expect(second.toPlainText(), 'print("world")');
      expect(
        logs.where((line) => line.contains('Unsupported language')).length,
        1,
      );
    });

    test('invalid regex is replaced by grammar sanitizer', () {
      final sanitized = TextMateHighlighterRegistry.sanitizeGrammar(
        _grammarWithPattern('([a-z'),
      );
      final decoded =
          jsonDecode(sanitized.sanitizedJson) as Map<String, Object?>;
      final patterns = decoded['patterns'] as List<Object?>;
      final matcher = patterns.first as Map<String, Object?>;

      expect(sanitized.replacedPatternCount, 1);
      expect(matcher['match'], r'^(?!x)x');
      expect(sanitized.invalidPatternSamples, contains('([a-z'));
    });

    test('patches html embedded css/js includes for this parser', () {
      final patched =
          TextMateHighlighterRegistry.patchHtmlGrammarForEmbeddedLanguages(
        htmlGrammarJson: _htmlGrammarWithEmbeddedIncludes(),
        cssGrammarJson: _cssGrammarWithLocalInclude(),
        jsGrammarJson: _jsGrammarWithLocalInclude(),
      );

      expect(patched.contains('source.css'), isFalse);
      expect(patched.contains('source.js'), isFalse);

      final decoded = jsonDecode(patched) as Map<String, Object?>;
      final scriptBegin = _findBeginPatternForMatcher(
        decoded,
        'meta.embedded.script.html',
      );
      final styleBegin = _findBeginPatternForMatcher(
        decoded,
        'meta.embedded.style.html',
      );

      expect(scriptBegin, r'(<script)(\s[^>]*?)?>');
      expect(styleBegin, r'(<style)(\s[^>]*?)?>');
    });

    test('patches javascript grammar with function call patterns', () {
      final patched =
          TextMateHighlighterRegistry.patchJavaScriptGrammarForFunctionCalls(
              _jsGrammarWithLocalInclude());
      final decoded = jsonDecode(patched) as Map<String, Object?>;
      final patterns = decoded['patterns'] as List<Object?>;

      expect(
        patterns.any((entry) {
          if (entry is! Map) return false;
          final map = entry.cast<String, Object?>();
          return map['name'] == 'entity.name.function.js';
        }),
        isTrue,
      );

      expect(
        patterns.any((entry) {
          if (entry is! Map) return false;
          final map = entry.cast<String, Object?>();
          return map['captures'] is Map;
        }),
        isTrue,
      );
    });

    test('patches css grammar selector regex to support commas', () {
      final patched = TextMateHighlighterRegistry.patchCssGrammarForSelectors(
        _cssGrammarWithLocalInclude(),
      );
      final decoded = jsonDecode(patched) as Map<String, Object?>;
      final begin = _findBeginPatternForMatcher(decoded, 'meta.rule-set.css');

      expect(
        begin,
        r'''([a-zA-Z0-9\-_*#.,:>+~\[\]\s"'()=|^$]+)\s*(\{)''',
      );
    });

    test('highlights embedded js and css inside html', () async {
      final registry = TextMateHighlighterRegistry.createForTests();

      await registry.initialize();

      final span = registry.buildTextSpan(
        text: '''
<script>
if (true) {}
// hello
console.log('hello world');
</script>
<style>
h1 { color: red; }
</style>
''',
        language: 'html',
        style: const TextStyle(color: Colors.white),
      );

      final leaves = _flattenTextSpans(span);

      final ifSpan = leaves.firstWhere((leaf) => leaf.text.contains('if'));
      final commentSpan =
          leaves.firstWhere((leaf) => leaf.text.contains('// hello'));
      final functionSpan =
          leaves.firstWhere((leaf) => leaf.text.contains('log'));
      final cssPropertySpan =
          leaves.firstWhere((leaf) => leaf.text.contains('color'));

      expect(ifSpan.style.color, const Color(0xFFC678DD));
      expect(commentSpan.style.color, const Color(0xFF5C6370));
      expect(functionSpan.style.color, const Color(0xFF61AFEF));
      expect(cssPropertySpan.style.color, const Color(0xFFD19A66));
    });

    test('highlights css selectors with selector color', () async {
      final registry = TextMateHighlighterRegistry.createForTests();
      await registry.initialize();

      final span = registry.buildTextSpan(
        text: '''
body {
  color: red;
}

.menu, h1 {
  text-align: center;
}
''',
        language: 'css',
        style: const TextStyle(color: Colors.white),
      );

      final leaves = _flattenTextSpans(span);
      final bodySelector =
          leaves.firstWhere((leaf) => leaf.text.contains('body'));
      final menuSelector =
          leaves.firstWhere((leaf) => leaf.text.contains('.menu'));

      expect(bodySelector.style.color, const Color(0xFFE5C07B));
      expect(menuSelector.style.color, const Color(0xFFE5C07B));
    });
  });
}

String _grammarWithPattern(String pattern) {
  return jsonEncode({
    'name': 'TestGrammar',
    'scopeName': 'source.test',
    'patterns': [
      {
        'name': 'keyword.control.test',
        'match': pattern,
      }
    ],
  });
}

String _htmlGrammarWithEmbeddedIncludes() {
  return jsonEncode({
    'name': 'HTML',
    'scopeName': 'text.html.basic',
    'patterns': [
      {'include': '#embeddedCode'}
    ],
    'repository': {
      'embeddedCode': {
        'patterns': [
          {
            'name': 'meta.embedded.script.html',
            'begin': r'(<script)(\s[^>]*?>)',
            'end': r'(</script>)',
            'patterns': [
              {'include': 'source.js'}
            ]
          },
          {
            'name': 'meta.embedded.style.html',
            'begin': r'(<style)(\s[^>]*?>)',
            'end': r'(</style>)',
            'patterns': [
              {'include': 'source.css'}
            ]
          }
        ]
      }
    }
  });
}

String _cssGrammarWithLocalInclude() {
  return jsonEncode({
    'name': 'CSS',
    'scopeName': 'source.css',
    'patterns': [
      {'include': '#rules'}
    ],
    'repository': {
      'rules': {
        'patterns': [
          {
            'name': 'meta.rule-set.css',
            'begin': r'([a-zA-Z0-9\-_*#.:\[\]\s]+)\s*(\{)',
            'end': r'\}',
            'patterns': [
              {'include': '#properties'}
            ],
          }
        ]
      },
      'properties': {
        'patterns': [
          {'name': 'support.type.property-name.css', 'match': r'\b[a-z-]+\b'},
        ]
      }
    }
  });
}

String _jsGrammarWithLocalInclude() {
  return jsonEncode({
    'name': 'JavaScript',
    'scopeName': 'source.js',
    'patterns': [
      {'include': '#keywords'}
    ],
    'repository': {
      'keywords': {
        'patterns': [
          {'name': 'keyword.control.js', 'match': r'\b(if|else|return)\b'}
        ]
      }
    }
  });
}

String? _findBeginPatternForMatcher(
  Object? value,
  String matcherName,
) {
  if (value is Map) {
    final name = value['name'];
    if (name == matcherName) {
      final begin = value['begin'];
      if (begin is String) {
        return begin;
      }
    }

    for (final entry in value.values) {
      final result = _findBeginPatternForMatcher(entry, matcherName);
      if (result != null) return result;
    }
  } else if (value is List) {
    for (final entry in value) {
      final result = _findBeginPatternForMatcher(entry, matcherName);
      if (result != null) return result;
    }
  }

  return null;
}

List<_TextLeaf> _flattenTextSpans(
  TextSpan span, {
  TextStyle inheritedStyle = const TextStyle(),
}) {
  final currentStyle = inheritedStyle.merge(span.style);
  final leaves = <_TextLeaf>[];

  final children = span.children;
  if (children != null && children.isNotEmpty) {
    for (final child in children) {
      if (child is TextSpan) {
        leaves.addAll(
          _flattenTextSpans(
            child,
            inheritedStyle: currentStyle,
          ),
        );
      }
    }
    return leaves;
  }

  final text = span.text;
  if (text != null && text.isNotEmpty) {
    leaves.add(_TextLeaf(text: text, style: currentStyle));
  }
  return leaves;
}

class _TextLeaf {
  const _TextLeaf({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;
}
