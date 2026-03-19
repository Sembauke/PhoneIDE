import 'dart:convert';

import 'package:flutter/services.dart';

enum AutocompleteLanguage { html, css, javascript, mixed }

class AutocompleteSuggestion {
  const AutocompleteSuggestion({
    required this.value,
    required this.category,
    String? label,
    this.insertText,
    this.language,
    this.detail,
    this.previewColor,
    this.priority = 0,
    this.whenBoost = 40,
    this.whenPattern,
    this.whenRegex,
  }) : label = label ?? value;

  final String value;
  final String label;
  final String? insertText;
  final String category;
  final String? detail;
  final AutocompleteLanguage? language;
  final Color? previewColor;
  final int priority;
  final int whenBoost;
  final String? whenPattern;
  final RegExp? whenRegex;
}

const String kDefaultAutocompleteAssetPath =
    'packages/phone_ide/assets/autocomplete/suggestions.json';
const String kDefaultJavascriptObjectsAssetPath =
    'packages/phone_ide/assets/autocomplete/javascript_objects.generated.json';

Future<List<AutocompleteSuggestion>> loadAutocompleteSuggestionsFromAsset({
  required String assetPath,
  AssetBundle? bundle,
}) async {
  final AssetBundle activeBundle = bundle ?? rootBundle;
  final String requestedPath = assetPath.trim();
  final bool useBundledObjectSchema =
      requestedPath.isEmpty || requestedPath == kDefaultAutocompleteAssetPath;
  final List<String> candidatePaths = <String>[
    if (requestedPath.isNotEmpty) requestedPath,
    if (requestedPath != kDefaultAutocompleteAssetPath)
      kDefaultAutocompleteAssetPath,
  ];

  String? resolvedPath;
  List<AutocompleteSuggestion> parsedBase = const <AutocompleteSuggestion>[];
  for (final String candidatePath in candidatePaths) {
    try {
      final String json = await activeBundle.loadString(candidatePath);
      final List<AutocompleteSuggestion> parsed =
          parseAutocompleteSuggestionsJson(json);
      if (parsed.isNotEmpty) {
        resolvedPath = candidatePath;
        parsedBase = parsed;
        break;
      }
    } catch (_) {
      // Fall through and try next candidate.
    }
  }

  final List<AutocompleteSuggestion> merged = <AutocompleteSuggestion>[
    ...parsedBase,
  ];

  if (useBundledObjectSchema || resolvedPath == kDefaultAutocompleteAssetPath) {
    try {
      final String jsObjectsJson =
          await activeBundle.loadString(kDefaultJavascriptObjectsAssetPath);
      final List<AutocompleteSuggestion> parsedObjectSchema =
          parseAutocompleteSuggestionsJson(jsObjectsJson);
      if (parsedObjectSchema.isNotEmpty) {
        merged.addAll(parsedObjectSchema);
      }
    } catch (_) {
      // Optional schema; keep base suggestions if unavailable.
    }
  }

  final List<AutocompleteSuggestion> deduped =
      _dedupeAutocompleteSuggestions(merged);
  if (deduped.isNotEmpty) {
    return deduped;
  }

  return kEditorAutocompleteSuggestions;
}

List<AutocompleteSuggestion> parseAutocompleteSuggestionsJson(
    String jsonString) {
  final dynamic decoded = jsonDecode(jsonString);
  final List<AutocompleteSuggestion> parsed = <AutocompleteSuggestion>[];

  void addSuggestion(
    dynamic rawSuggestion, {
    AutocompleteLanguage? inheritedLanguage,
  }) {
    if (rawSuggestion is! Map) {
      return;
    }

    final Map<String, dynamic> item = rawSuggestion.map(
      (dynamic key, dynamic value) => MapEntry(key.toString(), value),
    );

    final String? value = _stringOrNull(item['value']) ??
        _stringOrNull(item['prefix']) ??
        _firstString(item['prefixes']) ??
        _stringOrNull(item['insertText']) ??
        _stringOrNull(item['label']);
    if (value == null || value.trim().isEmpty) {
      return;
    }

    final String label =
        _stringOrNull(item['label']) ?? _stringOrNull(item['name']) ?? value;
    final String category = _stringOrNull(item['category']) ??
        _stringOrNull(item['kind']) ??
        _stringOrNull(item['type']) ??
        _stringOrNull(item['scope']) ??
        _stringOrNull(item['language']) ??
        'Suggestion';

    final String? insertText = _stringOrNull(item['insertText']) ??
        _stringOrNull(item['body']) ??
        _joinStringList(item['body']);
    final String? detail =
        _stringOrNull(item['detail']) ?? _stringOrNull(item['description']);
    final Color? previewColor = _parseHexColor(
        _stringOrNull(item['previewColor']) ?? _stringOrNull(item['color']));
    final int priority = _intOrDefault(item['priority'], 0);
    final int whenBoost = _intOrDefault(item['whenBoost'], 40);
    final String? whenPattern =
        _stringOrNull(item['when']) ?? _stringOrNull(item['contextPattern']);
    final RegExp? whenRegex = _parseContextRegex(
      whenPattern,
      caseSensitive: item['whenCaseSensitive'] == true,
      multiLine: item['whenMultiLine'] == true,
    );

    final AutocompleteLanguage? language = parseAutocompleteLanguage(
          _stringOrNull(item['language']) ?? _stringOrNull(item['scope']),
          allowMixed: false,
        ) ??
        inheritedLanguage;

    parsed.add(
      AutocompleteSuggestion(
        value: value,
        label: label,
        insertText: insertText,
        category: category,
        detail: detail,
        language: language,
        previewColor: previewColor,
        priority: priority,
        whenBoost: whenBoost,
        whenPattern: whenPattern,
        whenRegex: whenRegex,
      ),
    );
  }

  if (decoded is List) {
    for (final dynamic item in decoded) {
      addSuggestion(item);
    }
    return parsed;
  }

  if (decoded is! Map) {
    return parsed;
  }

  final Map<String, dynamic> root = decoded.map(
    (dynamic key, dynamic value) => MapEntry(key.toString(), value),
  );

  final dynamic suggestionsNode = root['suggestions'];
  bool parsedKnownSection = false;

  if (suggestionsNode is List) {
    for (final dynamic item in suggestionsNode) {
      addSuggestion(item);
    }
    parsedKnownSection = true;
  }

  final dynamic languagesNode = root['languages'];
  if (languagesNode is Map) {
    languagesNode.forEach((dynamic key, dynamic value) {
      final AutocompleteLanguage? inheritedLanguage =
          parseAutocompleteLanguage(key.toString(), allowMixed: false);
      if (value is List) {
        for (final dynamic item in value) {
          addSuggestion(
            item,
            inheritedLanguage: inheritedLanguage,
          );
        }
      }
    });
    parsedKnownSection = true;
  }

  final dynamic objectsNode = root['objects'];
  if (objectsNode is Map) {
    objectsNode.forEach((dynamic languageKey, dynamic objectMap) {
      if (objectMap is! Map) {
        return;
      }

      final AutocompleteLanguage? language = parseAutocompleteLanguage(
        languageKey.toString(),
        allowMixed: false,
      );
      if (language == null) {
        return;
      }

      objectMap.forEach((dynamic objectKey, dynamic objectValue) {
        final String objectName = objectKey.toString().trim();
        if (objectName.isEmpty) {
          return;
        }

        late final List<dynamic> rawMembers;
        if (objectValue is List) {
          rawMembers = objectValue;
        } else if (objectValue is Map && objectValue['members'] is List) {
          rawMembers = objectValue['members'] as List<dynamic>;
        } else {
          return;
        }

        final String defaultWhenPattern =
            '${_escapeRegexLiteral(objectName)}\\.[A-Za-z_\\\$]*\$';
        final RegExp? defaultWhenRegex = _parseContextRegex(defaultWhenPattern);

        for (final dynamic rawMember in rawMembers) {
          String? name;
          String? category;
          String? detail;
          String? insertText;
          int priority = 0;
          int whenBoost = 120;
          String whenPattern = defaultWhenPattern;
          RegExp? whenRegex = defaultWhenRegex;

          if (rawMember is String) {
            name = rawMember.trim();
          } else if (rawMember is Map) {
            final Map<String, dynamic> member = rawMember.map(
              (dynamic key, dynamic value) => MapEntry(key.toString(), value),
            );

            name = _stringOrNull(member['name']) ??
                _stringOrNull(member['value']) ??
                _stringOrNull(member['label']);
            final String? kind =
                _stringOrNull(member['kind']) ?? _stringOrNull(member['type']);
            final String? memberInsertText =
                _stringOrNull(member['insertText']);
            final bool isMethod = kind == 'method' ||
                (kind == null &&
                    memberInsertText != null &&
                    memberInsertText.contains('('));
            category = 'JavaScript ${isMethod ? 'method' : 'property'}';
            detail = _stringOrNull(member['detail']) ??
                _stringOrNull(member['description']) ??
                '$objectName member';
            insertText = memberInsertText;
            if (insertText == null && isMethod) {
              insertText = '${name ?? ''}()';
            }
            priority = _intOrDefault(member['priority'], 0);
            whenBoost = _intOrDefault(member['whenBoost'], 120);
            whenPattern = _stringOrNull(member['when']) ??
                _stringOrNull(member['contextPattern']) ??
                defaultWhenPattern;
            whenRegex = _parseContextRegex(
              whenPattern,
              caseSensitive: member['whenCaseSensitive'] == true,
              multiLine: member['whenMultiLine'] == true,
            );
          }

          if (name == null || name.trim().isEmpty) {
            continue;
          }

          parsed.add(
            AutocompleteSuggestion(
              value: name,
              label: '$objectName.$name',
              insertText: insertText ?? name,
              category: category ?? 'JavaScript member',
              detail: detail ?? '$objectName member',
              language: language,
              priority: priority,
              whenBoost: whenBoost,
              whenPattern: whenPattern,
              whenRegex: whenRegex,
            ),
          );
        }
      });
    });
    parsedKnownSection = true;
  }

  if (parsedKnownSection) {
    return parsed;
  }

  if (_looksLikeSuggestionMap(root)) {
    addSuggestion(root);
    return parsed;
  }

  root.forEach((String key, dynamic value) {
    if (value is! Map) {
      return;
    }

    final Map<String, dynamic> suggestionNode = value.map(
      (dynamic suggestionKey, dynamic suggestionValue) =>
          MapEntry(suggestionKey.toString(), suggestionValue),
    );
    suggestionNode.putIfAbsent('label', () => key);
    addSuggestion(suggestionNode);
  });

  return parsed;
}

AutocompleteLanguage? parseAutocompleteLanguage(
  String? rawLanguage, {
  bool allowMixed = true,
}) {
  if (rawLanguage == null || rawLanguage.trim().isEmpty) {
    return null;
  }

  final String value = rawLanguage.toLowerCase().trim();

  if (value == 'mixed' && allowMixed) {
    return AutocompleteLanguage.mixed;
  }

  if (_isJavascriptLanguage(value) ||
      value.contains('javascript') ||
      value.contains('typescript') ||
      value.contains('source.js') ||
      value.contains('source.ts')) {
    return AutocompleteLanguage.javascript;
  }

  if (_isCssLanguage(value) ||
      value.contains('source.css') ||
      value.contains('style.css')) {
    return AutocompleteLanguage.css;
  }

  if (_isHtmlLanguage(value) ||
      value.contains('text.html') ||
      value.contains('source.html')) {
    return AutocompleteLanguage.html;
  }

  return null;
}

AutocompleteLanguage resolveAutocompleteLanguage({
  required String defaultLanguage,
  required String path,
}) {
  final String normalizedPath = path.toLowerCase().trim();
  final int dotIndex = normalizedPath.lastIndexOf('.');
  final String extension = dotIndex >= 0 && dotIndex < normalizedPath.length - 1
      ? normalizedPath.substring(dotIndex + 1)
      : '';

  if (_isJavascriptExtension(extension)) {
    return AutocompleteLanguage.javascript;
  }

  if (_isCssExtension(extension)) {
    return AutocompleteLanguage.css;
  }

  if (_isHtmlExtension(extension)) {
    // HTML can embed CSS and JS, so we keep the broader merged behavior.
    return AutocompleteLanguage.mixed;
  }

  final String normalizedLanguage = defaultLanguage.toLowerCase().trim();

  if (_isJavascriptLanguage(normalizedLanguage)) {
    return AutocompleteLanguage.javascript;
  }

  if (_isCssLanguage(normalizedLanguage)) {
    return AutocompleteLanguage.css;
  }

  if (_isHtmlLanguage(normalizedLanguage)) {
    return AutocompleteLanguage.mixed;
  }

  return AutocompleteLanguage.mixed;
}

List<AutocompleteSuggestion> filterSuggestionsByLanguage({
  required List<AutocompleteSuggestion> suggestions,
  required AutocompleteLanguage language,
}) {
  if (language == AutocompleteLanguage.mixed) {
    return suggestions;
  }

  return suggestions.where((AutocompleteSuggestion suggestion) {
    final AutocompleteLanguage suggestionLanguage = suggestion.language ??
        _languageFromCategory(suggestion.category) ??
        AutocompleteLanguage.mixed;
    return suggestionLanguage == language ||
        suggestionLanguage == AutocompleteLanguage.mixed;
  }).toList(growable: false);
}

AutocompleteLanguage? _languageFromCategory(String category) {
  if (category.startsWith('HTML')) {
    return AutocompleteLanguage.html;
  }

  if (category.startsWith('CSS')) {
    return AutocompleteLanguage.css;
  }

  if (category.startsWith('JavaScript')) {
    return AutocompleteLanguage.javascript;
  }

  return null;
}

bool _looksLikeSuggestionMap(Map<String, dynamic> map) {
  return map.containsKey('value') ||
      map.containsKey('label') ||
      map.containsKey('prefix') ||
      map.containsKey('insertText') ||
      map.containsKey('body');
}

String? _stringOrNull(dynamic value) {
  if (value is String) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }

  return null;
}

String? _firstString(dynamic value) {
  if (value is List && value.isNotEmpty && value.first is String) {
    return value.first as String;
  }

  return null;
}

String? _joinStringList(dynamic value) {
  if (value is List &&
      value.isNotEmpty &&
      value.every((dynamic e) => e is String)) {
    return value.cast<String>().join('\n');
  }

  return null;
}

int _intOrDefault(dynamic value, int defaultValue) {
  if (value is int) {
    return value;
  }

  if (value is double) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value) ?? defaultValue;
  }

  return defaultValue;
}

List<AutocompleteSuggestion> _dedupeAutocompleteSuggestions(
    List<AutocompleteSuggestion> suggestions) {
  if (suggestions.isEmpty) {
    return const <AutocompleteSuggestion>[];
  }

  final Set<String> seen = <String>{};
  final List<AutocompleteSuggestion> deduped = <AutocompleteSuggestion>[];

  for (final AutocompleteSuggestion suggestion in suggestions) {
    final String key = [
      suggestion.language?.name ?? 'mixed',
      suggestion.value.toLowerCase(),
      suggestion.label.toLowerCase(),
      (suggestion.insertText ?? '').toLowerCase(),
      suggestion.category.toLowerCase(),
    ].join('|');

    if (!seen.add(key)) {
      continue;
    }

    deduped.add(suggestion);
  }

  return deduped;
}

RegExp? _parseContextRegex(
  String? pattern, {
  bool caseSensitive = false,
  bool multiLine = false,
}) {
  if (pattern == null || pattern.trim().isEmpty) {
    return null;
  }

  try {
    return RegExp(
      pattern,
      caseSensitive: caseSensitive,
      multiLine: multiLine,
    );
  } catch (_) {
    return null;
  }
}

String _escapeRegexLiteral(String value) {
  return value.replaceAllMapped(
    RegExp(r'([\\^$.*+?()[\]{}|])'),
    (Match match) => '\\${match.group(1)}',
  );
}

Color? _parseHexColor(String? value) {
  if (value == null) {
    return null;
  }

  final String normalized = value.trim().replaceAll('#', '');
  if (normalized.length != 6 && normalized.length != 8) {
    return null;
  }

  final int? intValue = int.tryParse(normalized, radix: 16);
  if (intValue == null) {
    return null;
  }

  if (normalized.length == 6) {
    return Color(0xFF000000 | intValue);
  }

  return Color(intValue);
}

bool _isJavascriptExtension(String extension) {
  return extension == 'js' ||
      extension == 'mjs' ||
      extension == 'cjs' ||
      extension == 'jsx' ||
      extension == 'ts' ||
      extension == 'tsx';
}

bool _isCssExtension(String extension) {
  return extension == 'css' ||
      extension == 'scss' ||
      extension == 'sass' ||
      extension == 'less';
}

bool _isHtmlExtension(String extension) {
  return extension == 'html' || extension == 'htm' || extension == 'xhtml';
}

bool _isJavascriptLanguage(String language) {
  return language == 'js' ||
      language == 'javascript' ||
      language == 'jsx' ||
      language == 'ts' ||
      language == 'typescript' ||
      language == 'tsx';
}

bool _isCssLanguage(String language) {
  return language == 'css' ||
      language == 'scss' ||
      language == 'sass' ||
      language == 'less';
}

bool _isHtmlLanguage(String language) {
  return language == 'html' || language == 'htm' || language == 'xhtml';
}

const List<AutocompleteSuggestion> kEditorAutocompleteSuggestions = [
  // HTML tags
  AutocompleteSuggestion(value: 'html', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'head', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'body', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'div', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'span', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'h1', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'h2', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'h3', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'p', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'a', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'img', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'button', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'input', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'label', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'form', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'script', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'style', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'section', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'article', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'header', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'footer', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'main', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'nav', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'ul', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'ol', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'li', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'table', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'tr', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'td', category: 'HTML tag'),
  AutocompleteSuggestion(value: 'th', category: 'HTML tag'),

  // HTML attributes
  AutocompleteSuggestion(value: 'class', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'id', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'href', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'src', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'alt', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'title', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'type', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'name', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'value', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'placeholder', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'disabled', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'checked', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'role', category: 'HTML attribute'),
  AutocompleteSuggestion(value: 'aria-label', category: 'HTML attribute'),

  // CSS properties
  AutocompleteSuggestion(value: 'color', category: 'CSS property'),
  AutocompleteSuggestion(value: 'background', category: 'CSS property'),
  AutocompleteSuggestion(value: 'background-color', category: 'CSS property'),
  AutocompleteSuggestion(value: 'font-size', category: 'CSS property'),
  AutocompleteSuggestion(value: 'font-weight', category: 'CSS property'),
  AutocompleteSuggestion(value: 'font-family', category: 'CSS property'),
  AutocompleteSuggestion(value: 'display', category: 'CSS property'),
  AutocompleteSuggestion(value: 'position', category: 'CSS property'),
  AutocompleteSuggestion(value: 'top', category: 'CSS property'),
  AutocompleteSuggestion(value: 'right', category: 'CSS property'),
  AutocompleteSuggestion(value: 'bottom', category: 'CSS property'),
  AutocompleteSuggestion(value: 'left', category: 'CSS property'),
  AutocompleteSuggestion(value: 'width', category: 'CSS property'),
  AutocompleteSuggestion(value: 'height', category: 'CSS property'),
  AutocompleteSuggestion(value: 'max-width', category: 'CSS property'),
  AutocompleteSuggestion(value: 'min-width', category: 'CSS property'),
  AutocompleteSuggestion(value: 'padding', category: 'CSS property'),
  AutocompleteSuggestion(value: 'margin', category: 'CSS property'),
  AutocompleteSuggestion(value: 'border', category: 'CSS property'),
  AutocompleteSuggestion(value: 'border-radius', category: 'CSS property'),
  AutocompleteSuggestion(value: 'box-shadow', category: 'CSS property'),
  AutocompleteSuggestion(value: 'opacity', category: 'CSS property'),
  AutocompleteSuggestion(value: 'z-index', category: 'CSS property'),
  AutocompleteSuggestion(value: 'overflow', category: 'CSS property'),
  AutocompleteSuggestion(value: 'align-items', category: 'CSS property'),
  AutocompleteSuggestion(value: 'justify-content', category: 'CSS property'),
  AutocompleteSuggestion(
      value: 'grid-template-columns', category: 'CSS property'),
  AutocompleteSuggestion(value: 'gap', category: 'CSS property'),
  AutocompleteSuggestion(value: 'transition', category: 'CSS property'),
  AutocompleteSuggestion(value: 'transform', category: 'CSS property'),

  // CSS values
  AutocompleteSuggestion(value: 'block', category: 'CSS value'),
  AutocompleteSuggestion(value: 'inline', category: 'CSS value'),
  AutocompleteSuggestion(value: 'inline-block', category: 'CSS value'),
  AutocompleteSuggestion(value: 'flex', category: 'CSS value'),
  AutocompleteSuggestion(value: 'grid', category: 'CSS value'),
  AutocompleteSuggestion(value: 'relative', category: 'CSS value'),
  AutocompleteSuggestion(value: 'absolute', category: 'CSS value'),
  AutocompleteSuggestion(value: 'fixed', category: 'CSS value'),
  AutocompleteSuggestion(value: 'sticky', category: 'CSS value'),
  AutocompleteSuggestion(value: 'none', category: 'CSS value'),
  AutocompleteSuggestion(value: 'auto', category: 'CSS value'),
  AutocompleteSuggestion(value: 'hidden', category: 'CSS value'),
  AutocompleteSuggestion(value: 'visible', category: 'CSS value'),
  AutocompleteSuggestion(value: 'center', category: 'CSS value'),
  AutocompleteSuggestion(value: 'space-between', category: 'CSS value'),
  AutocompleteSuggestion(value: 'space-around', category: 'CSS value'),
  AutocompleteSuggestion(value: 'space-evenly', category: 'CSS value'),
  AutocompleteSuggestion(value: 'bold', category: 'CSS value'),
  AutocompleteSuggestion(value: 'normal', category: 'CSS value'),

  // CSS colors
  AutocompleteSuggestion(
    value: 'orange',
    category: 'CSS color',
    previewColor: Color(0xFFFFA500),
  ),
  AutocompleteSuggestion(
    value: 'orangered',
    category: 'CSS color',
    previewColor: Color(0xFFFF4500),
  ),
  AutocompleteSuggestion(
    value: 'orchid',
    category: 'CSS color',
    previewColor: Color(0xFFDA70D6),
  ),
  AutocompleteSuggestion(
    value: 'olivedrab',
    category: 'CSS color',
    previewColor: Color(0xFF6B8E23),
  ),
  AutocompleteSuggestion(
    value: 'black',
    category: 'CSS color',
    previewColor: Color(0xFF000000),
  ),
  AutocompleteSuggestion(
    value: 'white',
    category: 'CSS color',
    previewColor: Color(0xFFFFFFFF),
  ),
  AutocompleteSuggestion(
    value: 'red',
    category: 'CSS color',
    previewColor: Color(0xFFFF0000),
  ),
  AutocompleteSuggestion(
    value: 'green',
    category: 'CSS color',
    previewColor: Color(0xFF008000),
  ),
  AutocompleteSuggestion(
    value: 'blue',
    category: 'CSS color',
    previewColor: Color(0xFF0000FF),
  ),
  AutocompleteSuggestion(
    value: 'yellow',
    category: 'CSS color',
    previewColor: Color(0xFFFFFF00),
  ),
  AutocompleteSuggestion(
    value: '#000000',
    category: 'CSS color',
    previewColor: Color(0xFF000000),
  ),
  AutocompleteSuggestion(
    value: '#ffffff',
    category: 'CSS color',
    previewColor: Color(0xFFFFFFFF),
  ),
  AutocompleteSuggestion(
    value: '#ffa500',
    category: 'CSS color',
    previewColor: Color(0xFFFFA500),
  ),

  // JavaScript keywords and globals
  AutocompleteSuggestion(value: 'const', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'let', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'var', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'function', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'return', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'if', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'else', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'for', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'while', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'switch', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'case', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'break', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'continue', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'try', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'catch', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'finally', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'async', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'await', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'class', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'new', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'this', category: 'JavaScript keyword'),
  AutocompleteSuggestion(value: 'console', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'document', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'window', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'setTimeout', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'setInterval', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'Promise', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'Array', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'Object', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'String', category: 'JavaScript global'),
  AutocompleteSuggestion(value: 'Number', category: 'JavaScript global'),
];
