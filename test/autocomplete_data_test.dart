import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/autocomplete_data.dart';

void main() {
  group('resolveAutocompleteLanguage', () {
    test('uses javascript language for js extension', () {
      final AutocompleteLanguage language = resolveAutocompleteLanguage(
        defaultLanguage: 'html',
        path: 'script.js',
      );

      expect(language, AutocompleteLanguage.javascript);
    });

    test('uses css language for css extension', () {
      final AutocompleteLanguage language = resolveAutocompleteLanguage(
        defaultLanguage: 'javascript',
        path: 'styles.css',
      );

      expect(language, AutocompleteLanguage.css);
    });

    test('keeps mixed language for html extension', () {
      final AutocompleteLanguage language = resolveAutocompleteLanguage(
        defaultLanguage: 'html',
        path: 'index.html',
      );

      expect(language, AutocompleteLanguage.mixed);
    });

    test('falls back to default language when extension is unknown', () {
      final AutocompleteLanguage language = resolveAutocompleteLanguage(
        defaultLanguage: 'javascript',
        path: 'README',
      );

      expect(language, AutocompleteLanguage.javascript);
    });
  });

  group('filterSuggestionsByLanguage', () {
    test('filters JavaScript-only suggestions', () {
      final List<AutocompleteSuggestion> filtered = filterSuggestionsByLanguage(
        suggestions: kEditorAutocompleteSuggestions,
        language: AutocompleteLanguage.javascript,
      );

      expect(filtered, isNotEmpty);
      expect(
        filtered.every(
            (AutocompleteSuggestion e) => e.category.startsWith('JavaScript')),
        isTrue,
      );
      expect(
        filtered.any((AutocompleteSuggestion e) => e.value == 'const'),
        isTrue,
      );
      expect(
        filtered.any((AutocompleteSuggestion e) => e.value == 'orange'),
        isFalse,
      );
    });
  });

  group('parseAutocompleteSuggestionsJson', () {
    test('parses languages map and structured fields', () {
      const String raw = r'''
{
  "languages": {
    "javascript": [
      {
        "value": "log",
        "label": "console.log",
        "insertText": "console.log()",
        "category": "JavaScript snippet",
        "detail": "Console output",
        "previewColor": "#123456",
        "priority": 7,
        "when": "console\\.[a-zA-Z]*$",
        "whenBoost": 120
      }
    ]
  }
}
''';

      final List<AutocompleteSuggestion> parsed =
          parseAutocompleteSuggestionsJson(raw);

      expect(parsed.length, 1);
      expect(parsed.first.value, 'log');
      expect(parsed.first.label, 'console.log');
      expect(parsed.first.insertText, 'console.log()');
      expect(parsed.first.category, 'JavaScript snippet');
      expect(parsed.first.detail, 'Console output');
      expect(parsed.first.language, AutocompleteLanguage.javascript);
      expect(parsed.first.previewColor, isNotNull);
      expect(parsed.first.priority, 7);
      expect(parsed.first.whenBoost, 120);
      expect(parsed.first.whenPattern, r'console\.[a-zA-Z]*$');
      expect(parsed.first.whenRegex, isNotNull);
      expect(parsed.first.whenRegex!.hasMatch('console.lo'), isTrue);
    });

    test('parses nested object-member schema', () {
      const String raw = r'''
{
  "objects": {
    "javascript": {
      "console": {
        "members": [
          { "name": "log", "kind": "method" },
          { "name": "error", "kind": "method", "insertText": "error()" }
        ]
      }
    }
  }
}
''';

      final List<AutocompleteSuggestion> parsed =
          parseAutocompleteSuggestionsJson(raw);

      expect(parsed.length, 2);
      expect(parsed.first.value, 'log');
      expect(parsed.first.label, 'console.log');
      expect(parsed.first.category, 'JavaScript method');
      expect(parsed.first.insertText, 'log()');
      expect(parsed.first.whenPattern, r'console\.[A-Za-z_\$]*$');
      expect(parsed.first.whenRegex?.hasMatch('console.lo'), isTrue);
      expect(parsed.first.language, AutocompleteLanguage.javascript);

      expect(parsed.last.value, 'error');
      expect(parsed.last.insertText, 'error()');
    });

    test('parses flat javascript type-tree schema', () {
      const String raw = r'''
{
  "keywords": ["const", "await"],
  "console": {
    "type": "object",
    "log": { "type": "function" },
    "clear": { "type": "function" }
  },
  "Object": {
    "type": "function",
    "prototype": {
      "type": "object",
      "toString": { "type": "function" }
    }
  }
}
''';

      final List<AutocompleteSuggestion> parsed =
          parseAutocompleteSuggestionsJson(raw);

      final AutocompleteSuggestion keyword = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.value == 'const' &&
            suggestion.category == 'JavaScript keyword',
      );
      expect(keyword.language, AutocompleteLanguage.javascript);

      final AutocompleteSuggestion consoleGlobal = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.value == 'console' && suggestion.label == 'console',
      );
      expect(consoleGlobal.category, 'JavaScript global');

      final AutocompleteSuggestion consoleLog = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.label == 'console.log',
      );
      expect(consoleLog.value, 'log');
      expect(consoleLog.insertText, 'log()');
      expect(consoleLog.whenPattern, r'console\.[A-Za-z_\$]*$');
      expect(consoleLog.whenRegex?.hasMatch('console.lo'), isTrue);

      final AutocompleteSuggestion objectProtoToString = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.label == 'Object.prototype.toString',
      );
      expect(objectProtoToString.value, 'toString');
      expect(objectProtoToString.insertText, 'toString()');
      expect(
        objectProtoToString.whenPattern,
        r'Object\.prototype\.[A-Za-z_\$]*$',
      );
    });

    test('parses css properties schema with keywords and at-rules', () {
      const String raw = r'''
{
  "keywords": ["block", "transparent"],
  "atRules": ["@media", "@supports"],
  "properties": {
    "display": ["block", "flex", "<length>"],
    "color": ["transparent", "#ffffff"]
  }
}
''';

      final List<AutocompleteSuggestion> parsed =
          parseAutocompleteSuggestionsJson(raw);

      final AutocompleteSuggestion displayProperty = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.value == 'display' &&
            suggestion.category == 'CSS property',
      );
      expect(displayProperty.language, AutocompleteLanguage.css);

      final AutocompleteSuggestion atRule = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.value == '@media' &&
            suggestion.category == 'CSS at-rule',
      );
      expect(atRule.language, AutocompleteLanguage.css);

      final AutocompleteSuggestion flexValue = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.value == 'flex' && suggestion.category == 'CSS value',
      );
      expect(flexValue.language, AutocompleteLanguage.css);
      expect(flexValue.whenPattern, contains('display'));
      expect(flexValue.whenRegex?.hasMatch('display: fl'), isTrue);

      expect(
        parsed.any((AutocompleteSuggestion suggestion) =>
            suggestion.value == '<length>'),
        isFalse,
      );
    });

    test('parses html tag-to-attributes schema', () {
      const String raw = r'''
{
  "globalAttributes": ["id", "class", "data-*"],
  "a": ["href", "target", "rel"],
  "img": ["src", "alt", "width", "height"],
  "div": []
}
''';

      final List<AutocompleteSuggestion> parsed =
          parseAutocompleteSuggestionsJson(raw);

      final AutocompleteSuggestion tag = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.value == 'a' && suggestion.category == 'HTML tag',
      );
      expect(tag.language, AutocompleteLanguage.html);

      final AutocompleteSuggestion hrefAttribute = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.value == 'href' &&
            suggestion.category == 'HTML attribute',
      );
      expect(hrefAttribute.language, AutocompleteLanguage.html);

      final AutocompleteSuggestion globalAttribute = parsed.firstWhere(
        (AutocompleteSuggestion suggestion) =>
            suggestion.value == 'class' &&
            suggestion.category == 'HTML attribute',
      );
      expect(globalAttribute.language, AutocompleteLanguage.html);
    });
  });

  group('loadAutocompleteSuggestionsFromAsset', () {
    test('loads html/css/js assets from static language files', () async {
      const String htmlSuggestions = r'''
{
  "languages": {
    "html": [
      { "value": "div", "category": "HTML tag" }
    ]
  }
}
''';

      const String cssSuggestions = r'''
{
  "languages": {
    "css": [
      { "value": "orange", "category": "CSS color", "previewColor": "#ffa500" }
    ]
  }
}
''';

      const String objectSchema = r'''
{
  "languages": {
    "javascript": [
      { "value": "let", "category": "JavaScript keyword" }
    ]
  },
  "objects": {
    "javascript": {
      "console": {
        "members": [
          { "name": "log", "kind": "method" }
        ]
      }
    }
  }
}
''';

      final _MapAssetBundle bundle = _MapAssetBundle(
        <String, String>{
          kDefaultHtmlSuggestionsAssetPath: htmlSuggestions,
          kDefaultCssSuggestionsAssetPath: cssSuggestions,
          kDefaultJavascriptSuggestionsAssetPath: objectSchema,
        },
      );

      final List<AutocompleteSuggestion> loaded =
          await loadAutocompleteSuggestionsFromAsset(
        assetPath: kDefaultAutocompleteAssetPath,
        bundle: bundle,
      );

      expect(
          loaded.any((AutocompleteSuggestion e) => e.value == 'let'), isTrue);
      expect(
          loaded.any((AutocompleteSuggestion e) => e.value == 'div'), isTrue);
      expect(loaded.any((AutocompleteSuggestion e) => e.value == 'orange'),
          isTrue);
      expect(
        loaded.any(
          (AutocompleteSuggestion e) =>
              e.label == 'console.log' && e.insertText == 'log()',
        ),
        isTrue,
      );
    });
  });
}

class _MapAssetBundle extends CachingAssetBundle {
  _MapAssetBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final String? content = _assets[key];
    if (content == null) {
      throw Exception('Asset not found: $key');
    }

    final Uint8List bytes = Uint8List.fromList(utf8.encode(content));
    return ByteData.view(bytes.buffer);
  }
}
