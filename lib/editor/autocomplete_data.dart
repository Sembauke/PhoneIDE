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

const String kDefaultJavascriptSuggestionsAssetPath =
    'packages/phone_ide/assets/autocomplete/javascript_suggestions.json';
const String kDefaultHtmlSuggestionsAssetPath =
    'packages/phone_ide/assets/autocomplete/html_suggestions.json';
const String kDefaultCssSuggestionsAssetPath =
    'packages/phone_ide/assets/autocomplete/css_suggestions.json';
const String kDefaultAutocompleteAssetPath =
    kDefaultJavascriptSuggestionsAssetPath;

Future<List<AutocompleteSuggestion>> loadAutocompleteSuggestionsFromAsset({
  required String assetPath,
  AssetBundle? bundle,
}) async {
  final AssetBundle activeBundle = bundle ?? rootBundle;
  final String requestedPath = assetPath.trim();
  final Set<String> candidatePaths = <String>{
    if (requestedPath.isNotEmpty) requestedPath,
    kDefaultHtmlSuggestionsAssetPath,
    kDefaultCssSuggestionsAssetPath,
    kDefaultJavascriptSuggestionsAssetPath,
  };

  final List<AutocompleteSuggestion> merged = <AutocompleteSuggestion>[];

  for (final String candidatePath in candidatePaths) {
    try {
      final String json = await activeBundle.loadString(candidatePath);
      final List<AutocompleteSuggestion> parsed =
          parseAutocompleteSuggestionsJson(json);
      if (parsed.isNotEmpty) {
        merged.addAll(parsed);
      }
    } catch (_) {
      // Optional source; keep suggestions gathered from available sources.
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

  if (!parsedKnownSection && _looksLikeFlatJavascriptSchema(root)) {
    _parseFlatJavascriptSchema(
      root: root,
      parsed: parsed,
      language: AutocompleteLanguage.javascript,
    );
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

const Set<String> _flatJavascriptRootMetaKeys = <String>{
  'keywords',
  'version',
  'source',
  'generatedAt',
};

const Set<String> _flatJavascriptNodeMetaKeys = <String>{
  'type',
  'detail',
  'description',
  'insertText',
};

bool _looksLikeFlatJavascriptSchema(Map<String, dynamic> root) {
  if (root['keywords'] is List) {
    return true;
  }

  int typedNodeCount = 0;
  root.forEach((String key, dynamic value) {
    if (_flatJavascriptRootMetaKeys.contains(key)) {
      return;
    }
    if (value is! Map) {
      return;
    }

    final String? type = _stringOrNull(value['type']);
    if (type == null || type.trim().isEmpty) {
      return;
    }

    typedNodeCount += 1;
  });

  return typedNodeCount >= 2;
}

void _parseFlatJavascriptSchema({
  required Map<String, dynamic> root,
  required List<AutocompleteSuggestion> parsed,
  required AutocompleteLanguage language,
}) {
  final dynamic keywordsNode = root['keywords'];
  if (keywordsNode is List) {
    for (final dynamic rawKeyword in keywordsNode) {
      if (rawKeyword is! String) {
        continue;
      }

      final String keyword = rawKeyword.trim();
      if (keyword.isEmpty) {
        continue;
      }

      parsed.add(
        AutocompleteSuggestion(
          value: keyword,
          category: 'JavaScript keyword',
          language: language,
        ),
      );
    }
  }

  root.forEach((String key, dynamic value) {
    if (_flatJavascriptRootMetaKeys.contains(key)) {
      return;
    }

    _appendJavascriptTreeSuggestion(
      nodeName: key,
      rawNode: value,
      parsed: parsed,
      language: language,
      parentPath: null,
    );
  });
}

void _appendJavascriptTreeSuggestion({
  required String nodeName,
  required dynamic rawNode,
  required List<AutocompleteSuggestion> parsed,
  required AutocompleteLanguage language,
  required String? parentPath,
}) {
  if (rawNode is! Map) {
    return;
  }

  final String trimmedName = nodeName.trim();
  if (trimmedName.isEmpty) {
    return;
  }

  final Map<String, dynamic> node = rawNode.map(
    (dynamic key, dynamic value) => MapEntry(key.toString(), value),
  );
  final String currentPath =
      parentPath == null ? trimmedName : '$parentPath.$trimmedName';
  final String? type = _stringOrNull(node['type'])?.toLowerCase();
  final bool isFunction = type == 'function';
  final bool isTopLevel = parentPath == null;
  final String? detail =
      _stringOrNull(node['detail']) ?? _stringOrNull(node['description']);
  final String? explicitInsertText = _stringOrNull(node['insertText']);
  final String insertText =
      explicitInsertText ?? (isFunction ? '$trimmedName()' : trimmedName);

  final String? whenPattern = isTopLevel
      ? null
      : '${_escapeRegexLiteral(parentPath)}\\.[A-Za-z_\\\$]*\$';
  final RegExp? whenRegex = _parseContextRegex(whenPattern);

  parsed.add(
    AutocompleteSuggestion(
      value: trimmedName,
      label: currentPath,
      insertText: insertText,
      category: isTopLevel
          ? 'JavaScript global'
          : 'JavaScript ${isFunction ? 'method' : 'member'}',
      detail: detail ??
          (isTopLevel
              ? 'JavaScript ${type ?? 'global'}'
              : '$parentPath ${isFunction ? 'method' : 'member'}'),
      language: language,
      whenPattern: whenPattern,
      whenRegex: whenRegex,
      whenBoost: isTopLevel ? 40 : 120,
    ),
  );

  node.forEach((String key, dynamic value) {
    if (_flatJavascriptNodeMetaKeys.contains(key)) {
      return;
    }

    _appendJavascriptTreeSuggestion(
      nodeName: key,
      rawNode: value,
      parsed: parsed,
      language: language,
      parentPath: currentPath,
    );
  });
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

const List<AutocompleteSuggestion> kEditorAutocompleteSuggestions =
    <AutocompleteSuggestion>[
  AutocompleteSuggestion(
    value: 'div',
    category: 'HTML tag',
    language: AutocompleteLanguage.html,
  ),
  AutocompleteSuggestion(
    value: 'color',
    category: 'CSS property',
    language: AutocompleteLanguage.css,
  ),
  AutocompleteSuggestion(
    value: 'const',
    category: 'JavaScript keyword',
    language: AutocompleteLanguage.javascript,
  ),
  AutocompleteSuggestion(
    value: 'console',
    category: 'JavaScript global',
    language: AutocompleteLanguage.javascript,
  ),
];
