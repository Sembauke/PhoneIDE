import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

typedef HighlighterLogger = void Function(String message);

class SanitizedGrammarResult {
  const SanitizedGrammarResult({
    required this.sanitizedJson,
    required this.replacedPatternCount,
    required this.invalidPatternSamples,
  });

  final String sanitizedJson;
  final int replacedPatternCount;
  final List<String> invalidPatternSamples;
}

class TextMateHighlighterRegistry {
  TextMateHighlighterRegistry._({
    AssetBundle? assetBundle,
    HighlighterLogger? logger,
  })  : _assetBundle = assetBundle ?? rootBundle,
        _logger = logger ?? debugPrint;

  static final TextMateHighlighterRegistry instance =
      TextMateHighlighterRegistry._();

  @visibleForTesting
  static TextMateHighlighterRegistry createForTests({
    AssetBundle? assetBundle,
    HighlighterLogger? logger,
  }) {
    return TextMateHighlighterRegistry._(
      assetBundle: assetBundle,
      logger: logger,
    );
  }

  static const Set<String> supportedLanguages = {
    'html',
    'css',
    'javascript',
  };

  static const Map<String, String> _languageAliases = {
    'html': 'html',
    'htm': 'html',
    'css': 'css',
    'javascript': 'javascript',
    'js': 'javascript',
  };

  static const Set<String> _regexKeys = {
    'match',
    'begin',
    'end',
    'while',
  };

  static const String _neverMatchingRegexPattern = r'^(?!x)x';
  static const String _scriptEmbedBeginPattern = r'(<script)(\s[^>]*?)?>';
  static const String _styleEmbedBeginPattern = r'(<style)(\s[^>]*?)?>';
  static const String _cssRuleSetBeginPattern =
      r'''([a-zA-Z0-9\-_*#.,:>+~\[\]\s"'()=|^$]+)\s*(\{)''';
  static final RegExp _embeddedBlockRegex = RegExp(
    r'(<script\b[^>]*>)([\s\S]*?)(</script\s*>)|(<style\b[^>]*>)([\s\S]*?)(</style\s*>)',
    caseSensitive: false,
    multiLine: true,
  );

  static String? canonicalizeLanguage(String language) {
    final normalized = language.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return _languageAliases[normalized];
  }

  bool _isInitialized = false;
  bool _initializationFailed = false;
  Future<void>? _initializeFuture;

  AssetBundle _assetBundle;
  HighlighterLogger _logger;
  HighlighterTheme? _theme;

  final Map<String, Highlighter> _highlighters = {};
  final Set<String> _loggedUnsupportedLanguages = {};
  final Set<String> _loggedFallbackKeys = {};

  bool get isInitialized => _isInitialized;
  bool get initializationFailed => _initializationFailed;

  Future<void> initialize() {
    return _initializeFuture ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    if (_isInitialized) return;
    _initializationFailed = false;

    try {
      final theme = _createTheme();
      _theme = theme;

      final rawGrammars = <String, String>{};
      for (final language in supportedLanguages) {
        rawGrammars[language] = await _assetBundle.loadString(
          'packages/syntax_highlight/grammars/$language.json',
        );
      }

      final patchedCssGrammar =
          patchCssGrammarForSelectors(rawGrammars['css']!);
      final preparedGrammars = <String, String>{
        ...rawGrammars,
        'css': patchedCssGrammar,
        'html': patchHtmlGrammarForEmbeddedLanguages(
          htmlGrammarJson: rawGrammars['html']!,
          cssGrammarJson: patchedCssGrammar,
          jsGrammarJson: rawGrammars['javascript']!,
        ),
        'javascript': patchJavaScriptGrammarForFunctionCalls(
          rawGrammars['javascript']!,
        ),
      };

      for (final language in supportedLanguages) {
        final grammarJson = preparedGrammars[language]!;
        final sanitized = sanitizeGrammar(grammarJson);
        if (sanitized.replacedPatternCount > 0) {
          _logger(
            'phone_ide: TextMate grammar "$language" replaced '
            '${sanitized.replacedPatternCount} unsupported regex patterns. '
            'Samples: ${sanitized.invalidPatternSamples.join(', ')}',
          );
        }

        Highlighter.addLanguage(language, sanitized.sanitizedJson);
        _highlighters[language] = Highlighter(language: language, theme: theme);
      }

      _isInitialized = true;
    } catch (error) {
      _initializationFailed = true;
      _logger(
        'phone_ide: TextMate initialization failed, falling back to plain text. '
        'Error: $error',
      );
    }
  }

  TextSpan buildTextSpan({
    required String text,
    required String language,
    TextStyle? style,
  }) {
    final canonicalLanguage = canonicalizeLanguage(language);

    if (canonicalLanguage == null) {
      _logUnsupportedLanguage(language);
      return TextSpan(style: style, text: text);
    }

    if (!_isInitialized || _initializationFailed) {
      _logFallback(
        'not-initialized:$canonicalLanguage',
        'phone_ide: TextMate not ready for "$canonicalLanguage", '
            'using plain text fallback.',
      );
      return TextSpan(style: style, text: text);
    }

    final highlighter = _highlighters[canonicalLanguage];
    if (highlighter == null || _theme == null) {
      _logFallback(
        'missing-highlighter:$canonicalLanguage',
        'phone_ide: Missing highlighter for "$canonicalLanguage", '
            'using plain text fallback.',
      );
      return TextSpan(style: style, text: text);
    }

    try {
      if (canonicalLanguage == 'html') {
        return _highlightHtmlWithEmbeddedBlocks(
          text: text,
          style: style,
          htmlHighlighter: highlighter,
        );
      }

      final highlighted = highlighter.highlight(text);
      return TextSpan(style: style, children: [highlighted]);
    } catch (error) {
      _logFallback(
        'highlight-error:$canonicalLanguage',
        'phone_ide: Highlight error for "$canonicalLanguage", '
            'using plain text fallback. Error: $error',
      );
      return TextSpan(style: style, text: text);
    }
  }

  TextSpan _highlightHtmlWithEmbeddedBlocks({
    required String text,
    required TextStyle? style,
    required Highlighter htmlHighlighter,
  }) {
    final jsHighlighter = _highlighters['javascript'];
    final cssHighlighter = _highlighters['css'];

    if (jsHighlighter == null || cssHighlighter == null) {
      final highlighted = htmlHighlighter.highlight(text);
      return TextSpan(style: style, children: [highlighted]);
    }

    final children = <InlineSpan>[];
    var cursor = 0;

    for (final match in _embeddedBlockRegex.allMatches(text)) {
      if (match.start > cursor) {
        final htmlSegment = text.substring(cursor, match.start);
        children.add(htmlHighlighter.highlight(htmlSegment));
      }

      if (match.group(1) != null) {
        final openTag = match.group(1)!;
        final scriptBody = match.group(2)!;
        final closeTag = match.group(3)!;

        children.add(htmlHighlighter.highlight(openTag));
        children.add(jsHighlighter.highlight(scriptBody));
        children.add(htmlHighlighter.highlight(closeTag));
      } else {
        final openTag = match.group(4)!;
        final styleBody = match.group(5)!;
        final closeTag = match.group(6)!;

        children.add(htmlHighlighter.highlight(openTag));
        children.add(cssHighlighter.highlight(styleBody));
        children.add(htmlHighlighter.highlight(closeTag));
      }

      cursor = match.end;
    }

    if (cursor < text.length) {
      children.add(htmlHighlighter.highlight(text.substring(cursor)));
    }

    return TextSpan(style: style, children: children);
  }

  void _logUnsupportedLanguage(String language) {
    final key = language.trim().toLowerCase();
    if (!_loggedUnsupportedLanguages.add(key)) return;
    _logger(
      'phone_ide: Unsupported language "$language". '
      'Supported languages: ${supportedLanguages.join(', ')}.',
    );
  }

  void _logFallback(String key, String message) {
    if (_loggedFallbackKeys.add(key)) {
      _logger(message);
    }
  }

  HighlighterTheme _createTheme() {
    final themeConfig = jsonEncode(_atomOneDarkThemeConfig);
    return HighlighterTheme.fromConfiguration(
      themeConfig,
      const TextStyle(),
    );
  }

  @visibleForTesting
  void configureForTests({
    AssetBundle? assetBundle,
    HighlighterLogger? logger,
  }) {
    _assetBundle = assetBundle ?? rootBundle;
    _logger = logger ?? debugPrint;
    _isInitialized = false;
    _initializationFailed = false;
    _initializeFuture = null;
    _theme = null;
    _highlighters.clear();
    _loggedUnsupportedLanguages.clear();
    _loggedFallbackKeys.clear();
  }

  @visibleForTesting
  static SanitizedGrammarResult sanitizeGrammar(String grammarJson) {
    final decoded = jsonDecode(grammarJson);
    final sanitization = _RegexSanitization();
    final sanitized = _sanitizeValue(decoded, sanitization);

    return SanitizedGrammarResult(
      sanitizedJson: jsonEncode(sanitized),
      replacedPatternCount: sanitization.replacedPatternCount,
      invalidPatternSamples: List.unmodifiable(sanitization.samples),
    );
  }

  @visibleForTesting
  static String patchHtmlGrammarForEmbeddedLanguages({
    required String htmlGrammarJson,
    required String cssGrammarJson,
    required String jsGrammarJson,
  }) {
    final htmlGrammar =
        (jsonDecode(htmlGrammarJson) as Map).cast<String, Object?>();
    final cssGrammar =
        (jsonDecode(cssGrammarJson) as Map).cast<String, Object?>();
    final jsGrammar =
        (jsonDecode(jsGrammarJson) as Map).cast<String, Object?>();

    final cssPatterns = _expandTopLevelPatterns(cssGrammar);
    final jsPatterns = _expandTopLevelPatterns(jsGrammar);

    final patched = _patchHtmlValue(
      htmlGrammar,
      cssPatterns: cssPatterns,
      jsPatterns: jsPatterns,
    );

    return jsonEncode(patched);
  }

  @visibleForTesting
  static String patchJavaScriptGrammarForFunctionCalls(String grammarJson) {
    final grammar = (jsonDecode(grammarJson) as Map).cast<String, Object?>();
    final patterns = ((grammar['patterns'] as List?) ?? const <Object?>[])
        .cast<Object?>()
        .toList();

    patterns.addAll(const <Object?>[
      <String, Object?>{
        'name': 'entity.name.function.js',
        'match': r'\b([A-Za-z_$][A-Za-z0-9_$]*)\s*(?=\()',
      },
      <String, Object?>{
        'match': r'(\.)\s*([A-Za-z_$][A-Za-z0-9_$]*)\b',
        'captures': <String, Object?>{
          '2': <String, Object?>{
            'name': 'support.function.js',
          },
        },
      },
    ]);

    final patched = <String, Object?>{
      ...grammar,
      'patterns': patterns,
    };

    return jsonEncode(patched);
  }

  @visibleForTesting
  static String patchCssGrammarForSelectors(String grammarJson) {
    final grammar = (jsonDecode(grammarJson) as Map).cast<String, Object?>();
    final patched = _patchCssValue(grammar);
    return jsonEncode(patched);
  }

  static List<Object?> _expandTopLevelPatterns(Map<String, Object?> grammar) {
    final patterns =
        ((grammar['patterns'] as List?) ?? const <Object?>[]).cast<Object?>();
    final repository =
        ((grammar['repository'] as Map?) ?? const <Object, Object>{})
            .cast<String, Object?>();
    return _expandPatternList(patterns, repository, <String>{});
  }

  static List<Object?> _expandPatternList(
    List<Object?> patterns,
    Map<String, Object?> repository,
    Set<String> includeStack,
  ) {
    final expanded = <Object?>[];
    for (final pattern in patterns) {
      if (pattern is! Map) continue;
      final map = pattern.cast<String, Object?>();
      expanded.addAll(
        _expandPatternMap(map, repository, includeStack),
      );
    }
    return expanded;
  }

  static List<Object?> _expandPatternMap(
    Map<String, Object?> pattern,
    Map<String, Object?> repository,
    Set<String> includeStack,
  ) {
    final includeValue = pattern['include'];
    if (includeValue is String) {
      if (!includeValue.startsWith('#')) {
        return <Object?>[_deepCopyMap(pattern)];
      }

      final includeKey = includeValue.substring(1);
      if (includeStack.contains(includeKey)) {
        return const <Object?>[];
      }

      final includedPattern = repository[includeKey];
      if (includedPattern is! Map) {
        return const <Object?>[];
      }

      return _expandPatternMap(
        includedPattern.cast<String, Object?>(),
        repository,
        {...includeStack, includeKey},
      );
    }

    final copy = _deepCopyMap(pattern);
    final nestedPatterns = copy['patterns'];
    if (nestedPatterns is List) {
      copy['patterns'] = _expandPatternList(
        nestedPatterns.cast<Object?>(),
        repository,
        includeStack,
      );
    }

    return <Object?>[copy];
  }

  static Object? _patchHtmlValue(
    Object? value, {
    required List<Object?> cssPatterns,
    required List<Object?> jsPatterns,
  }) {
    if (value is Map) {
      final map = <String, Object?>{};
      for (final entry in value.entries) {
        map[entry.key.toString()] = _patchHtmlValue(
          entry.value,
          cssPatterns: cssPatterns,
          jsPatterns: jsPatterns,
        );
      }

      final includeValue = map['include'];
      if (includeValue == 'source.css') {
        return <String, Object?>{
          'patterns': _deepCopyList(cssPatterns),
        };
      }
      if (includeValue == 'source.js') {
        return <String, Object?>{
          'patterns': _deepCopyList(jsPatterns),
        };
      }

      final matcherName = map['name'];
      if (matcherName == 'meta.embedded.script.html') {
        map['begin'] = _scriptEmbedBeginPattern;
      } else if (matcherName == 'meta.embedded.style.html') {
        map['begin'] = _styleEmbedBeginPattern;
      }

      return map;
    }

    if (value is List) {
      return value
          .map((entry) => _patchHtmlValue(
                entry,
                cssPatterns: cssPatterns,
                jsPatterns: jsPatterns,
              ))
          .toList();
    }

    return value;
  }

  static Object? _patchCssValue(Object? value) {
    if (value is Map) {
      final map = <String, Object?>{};
      for (final entry in value.entries) {
        map[entry.key.toString()] = _patchCssValue(entry.value);
      }

      if (map['name'] == 'meta.rule-set.css') {
        map['begin'] = _cssRuleSetBeginPattern;
      }
      return map;
    }

    if (value is List) {
      return value.map(_patchCssValue).toList();
    }

    return value;
  }

  static Map<String, Object?> _deepCopyMap(Map<String, Object?> source) {
    final copy = <String, Object?>{};
    for (final entry in source.entries) {
      copy[entry.key] = _deepCopyValue(entry.value);
    }
    return copy;
  }

  static List<Object?> _deepCopyList(List<Object?> source) {
    return source.map(_deepCopyValue).toList();
  }

  static Object? _deepCopyValue(Object? value) {
    if (value is Map) {
      return _deepCopyMap(value.cast<String, Object?>());
    }
    if (value is List) {
      return _deepCopyList(value.cast<Object?>());
    }
    return value;
  }

  static Object? _sanitizeValue(
      Object? value, _RegexSanitization sanitization) {
    if (value is Map) {
      final map = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final currentValue = entry.value;

        if (_regexKeys.contains(key) && currentValue is String) {
          if (_isValidRegex(currentValue)) {
            map[key] = currentValue;
          } else {
            sanitization.replacedPatternCount += 1;
            if (sanitization.samples.length < 3) {
              sanitization.samples.add(currentValue);
            }
            map[key] = _neverMatchingRegexPattern;
          }
          continue;
        }

        map[key] = _sanitizeValue(currentValue, sanitization);
      }
      return map;
    }

    if (value is List) {
      return value.map((entry) => _sanitizeValue(entry, sanitization)).toList();
    }

    return value;
  }

  static bool _isValidRegex(String pattern) {
    try {
      RegExp(pattern, multiLine: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _RegexSanitization {
  int replacedPatternCount = 0;
  final List<String> samples = [];
}

const Map<String, Object?> _atomOneDarkThemeConfig = {
  'name': 'phone_ide_atom_one_dark',
  'settings': [
    {
      'settings': {
        'foreground': '#ABB2BF',
      },
    },
    {
      'scope': [
        'comment',
        'punctuation.definition.comment',
      ],
      'settings': {
        'foreground': '#5C6370',
      },
    },
    {
      'scope': [
        'keyword',
        'keyword.control',
        'keyword.declaration',
        'storage',
      ],
      'settings': {
        'foreground': '#C678DD',
      },
    },
    {
      'scope': [
        'string',
        'constant.character',
      ],
      'settings': {
        'foreground': '#98C379',
      },
    },
    {
      'scope': [
        'constant.numeric',
        'constant.language',
      ],
      'settings': {
        'foreground': '#D19A66',
      },
    },
    {
      'scope': [
        'entity.name.type',
        'support.class',
      ],
      'settings': {
        'foreground': '#E5C07B',
      },
    },
    {
      'scope': [
        'entity.name.function',
        'support.function',
      ],
      'settings': {
        'foreground': '#61AFEF',
      },
    },
    {
      'scope': [
        'entity.name.tag',
        'entity.name.tag.script',
        'entity.name.tag.style',
      ],
      'settings': {
        'foreground': '#E06C75',
      },
    },
    {
      'scope': [
        'entity.other.attribute-name',
        'support.type.property-name',
        'meta.object-literal.key',
      ],
      'settings': {
        'foreground': '#D19A66',
      },
    },
    {
      'scope': [
        'string.quoted',
        'string.template',
        'support.constant.property-value',
        'support.type.media-query',
        'support.type.keyframes',
      ],
      'settings': {
        'foreground': '#98C379',
      },
    },
    {
      'scope': [
        'meta.selector',
        'entity.name.selector',
        'entity.name.selector.css',
      ],
      'settings': {
        'foreground': '#E5C07B',
      },
    },
    {
      'scope': [
        'constant.character.entity',
        'keyword.operator',
      ],
      'settings': {
        'foreground': '#56B6C2',
      },
    },
    {
      'scope': [
        'punctuation.definition.tag',
        'punctuation.definition.string',
        'punctuation.terminator',
        'meta.brace',
      ],
      'settings': {
        'foreground': '#ABB2BF',
      },
    },
    {
      'scope': [
        'variable.language',
        'variable.parameter',
        'variable',
      ],
      'settings': {
        'foreground': '#E06C75',
      },
    },
  ],
};
