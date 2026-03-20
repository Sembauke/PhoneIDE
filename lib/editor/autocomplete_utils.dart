import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:phone_ide/editor/autocomplete_data.dart';

class AutocompleteTokenMatch {
  const AutocompleteTokenMatch({
    required this.token,
    required this.range,
  });

  final String token;
  final TextRange range;
}

class _ScoredSuggestion {
  const _ScoredSuggestion({
    required this.suggestion,
    required this.score,
  });

  final AutocompleteSuggestion suggestion;
  final int score;
}

class _MemberAccessContext {
  const _MemberAccessContext({
    required this.objectName,
  });

  final String objectName;
}

class _CssRuleContext {
  const _CssRuleContext({
    required this.isInDeclarationBlock,
    required this.isInValueContext,
  });

  final bool isInDeclarationBlock;
  final bool isInValueContext;
}

class _HtmlRuleContext {
  const _HtmlRuleContext({
    required this.isInsideTag,
    required this.isTagNameContext,
    required this.isAttributeContext,
  });

  final bool isInsideTag;
  final bool isTagNameContext;
  final bool isAttributeContext;
}

class _AutocompleteRuleContext {
  const _AutocompleteRuleContext({
    required this.effectiveLanguage,
    required this.css,
    required this.html,
  });

  final AutocompleteLanguage effectiveLanguage;
  final _CssRuleContext css;
  final _HtmlRuleContext html;
}

// Builds a lightweight syntax context used to gate suggestions.
_AutocompleteRuleContext _buildRuleContext({
  required String contextBeforeCaret,
  required AutocompleteLanguage contextLanguage,
  required AutocompleteLanguage mixedContextFallbackLanguage,
}) {
  final AutocompleteLanguage effectiveLanguage = _resolveEffectiveLanguage(
    contextBeforeCaret,
    contextLanguage,
    mixedContextFallbackLanguage,
  );
  return _AutocompleteRuleContext(
    effectiveLanguage: effectiveLanguage,
    css: _analyzeCssRuleContext(contextBeforeCaret),
    html: _analyzeHtmlRuleContext(contextBeforeCaret),
  );
}

// Resolves the active language for this cursor position.
// In mixed files (e.g. HTML), this switches by nearest open <script>/<style>.
AutocompleteLanguage _resolveEffectiveLanguage(
  String contextBeforeCaret,
  AutocompleteLanguage contextLanguage,
  AutocompleteLanguage mixedContextFallbackLanguage,
) {
  if (contextLanguage != AutocompleteLanguage.mixed) {
    return contextLanguage;
  }

  if (contextBeforeCaret.trim().isEmpty) {
    return AutocompleteLanguage.mixed;
  }

  final String lower = contextBeforeCaret.toLowerCase();
  final int lastScriptOpen = lower.lastIndexOf('<script');
  final int lastScriptClose = lower.lastIndexOf('</script');
  if (lastScriptOpen > lastScriptClose) {
    return AutocompleteLanguage.javascript;
  }

  final int lastStyleOpen = lower.lastIndexOf('<style');
  final int lastStyleClose = lower.lastIndexOf('</style');
  if (lastStyleOpen > lastStyleClose) {
    return AutocompleteLanguage.css;
  }

  final int lastTagOpen = lower.lastIndexOf('<');
  final int lastTagClose = lower.lastIndexOf('>');
  if (lastTagOpen > lastTagClose) {
    return AutocompleteLanguage.html;
  }

  // In mixed documents that already contain HTML markup, default to HTML
  // outside explicit <script>/<style> blocks.
  final bool hasHtmlMarkers = lower.contains('<') || lower.contains('>');
  if (hasHtmlMarkers) {
    return AutocompleteLanguage.html;
  }

  return mixedContextFallbackLanguage;
}

// Detects whether the cursor is currently inside a CSS declaration block
// and whether the active declaration is in "value position" (after ':').
_CssRuleContext _analyzeCssRuleContext(String contextBeforeCaret) {
  int declarationDepth = 0;
  int lastOpenBraceIndex = -1;

  for (int i = 0; i < contextBeforeCaret.length; i += 1) {
    final String char = contextBeforeCaret[i];
    if (char == '{') {
      declarationDepth += 1;
      lastOpenBraceIndex = i;
    } else if (char == '}') {
      declarationDepth = math.max(0, declarationDepth - 1);
      if (declarationDepth == 0) {
        lastOpenBraceIndex = -1;
      }
    }
  }

  if (declarationDepth <= 0 || lastOpenBraceIndex < 0) {
    return const _CssRuleContext(
      isInDeclarationBlock: false,
      isInValueContext: false,
    );
  }

  // Limit value/property detection to only the active declaration segment.
  final String declarationSlice =
      contextBeforeCaret.substring(lastOpenBraceIndex + 1);
  final int lastSemicolon = declarationSlice.lastIndexOf(';');
  final String activeDeclaration = lastSemicolon >= 0
      ? declarationSlice.substring(lastSemicolon + 1)
      : declarationSlice;
  final bool isInValueContext = activeDeclaration.contains(':');

  return _CssRuleContext(
    isInDeclarationBlock: true,
    isInValueContext: isInValueContext,
  );
}

// Detects whether the cursor is in an HTML tag and whether we're typing
// a tag name or an attribute slot.
_HtmlRuleContext _analyzeHtmlRuleContext(String contextBeforeCaret) {
  final int lastTagOpenIndex = contextBeforeCaret.lastIndexOf('<');
  if (lastTagOpenIndex < 0) {
    return const _HtmlRuleContext(
      isInsideTag: false,
      isTagNameContext: false,
      isAttributeContext: false,
    );
  }

  final int lastTagCloseIndex = contextBeforeCaret.lastIndexOf('>');
  if (lastTagCloseIndex > lastTagOpenIndex) {
    return const _HtmlRuleContext(
      isInsideTag: false,
      isTagNameContext: false,
      isAttributeContext: false,
    );
  }

  final String rawTagContent = contextBeforeCaret.substring(lastTagOpenIndex);
  final String tagContentWithoutOpen = rawTagContent.substring(1);
  final String trimmedStart = tagContentWithoutOpen.trimLeft();

  if (trimmedStart.startsWith('!')) {
    return const _HtmlRuleContext(
      isInsideTag: true,
      isTagNameContext: false,
      isAttributeContext: false,
    );
  }

  final RegExp tagNamePattern = RegExp(r'^/?([A-Za-z][A-Za-z0-9-]*)');
  final RegExpMatch? tagNameMatch = tagNamePattern.firstMatch(trimmedStart);
  if (tagNameMatch == null) {
    return const _HtmlRuleContext(
      isInsideTag: true,
      isTagNameContext: true,
      isAttributeContext: false,
    );
  }

  final String afterTagName = trimmedStart.substring(tagNameMatch.end);
  if (afterTagName.trim().isEmpty && !trimmedStart.endsWith(' ')) {
    return const _HtmlRuleContext(
      isInsideTag: true,
      isTagNameContext: true,
      isAttributeContext: false,
    );
  }

  return const _HtmlRuleContext(
    isInsideTag: true,
    isTagNameContext: false,
    isAttributeContext: true,
  );
}

// Falls back to category naming when language is not explicitly set on item.
AutocompleteLanguage _suggestionLanguage(AutocompleteSuggestion suggestion) {
  final AutocompleteLanguage? explicitLanguage = suggestion.language;
  if (explicitLanguage != null) {
    return explicitLanguage;
  }

  final String category = suggestion.category.toLowerCase();
  if (category.startsWith('html')) {
    return AutocompleteLanguage.html;
  }
  if (category.startsWith('css')) {
    return AutocompleteLanguage.css;
  }
  if (category.startsWith('javascript')) {
    return AutocompleteLanguage.javascript;
  }

  return AutocompleteLanguage.mixed;
}

bool _matchesLanguageForContext({
  required AutocompleteSuggestion suggestion,
  required AutocompleteLanguage effectiveLanguage,
}) {
  // Keep current behavior when language cannot be inferred from context.
  if (effectiveLanguage == AutocompleteLanguage.mixed) {
    return true;
  }

  final AutocompleteLanguage suggestionLanguage =
      _suggestionLanguage(suggestion);
  if (effectiveLanguage == AutocompleteLanguage.css &&
      suggestionLanguage == AutocompleteLanguage.html &&
      _isHtmlTagSuggestion(suggestion)) {
    return true;
  }

  return suggestionLanguage == AutocompleteLanguage.mixed ||
      suggestionLanguage == effectiveLanguage;
}

bool _isCssPropertySuggestion(AutocompleteSuggestion suggestion) {
  return suggestion.category.toLowerCase().startsWith('css property');
}

bool _isCssValueSuggestion(AutocompleteSuggestion suggestion) {
  final String category = suggestion.category.toLowerCase();
  return category.startsWith('css value') || category.startsWith('css color');
}

bool _isHtmlTagSuggestion(AutocompleteSuggestion suggestion) {
  return suggestion.category.toLowerCase().startsWith('html tag');
}

bool _isHtmlAttributeSuggestion(AutocompleteSuggestion suggestion) {
  return suggestion.category.toLowerCase().startsWith('html attribute');
}

bool _matchesSuggestionRules({
  required AutocompleteSuggestion suggestion,
  required _AutocompleteRuleContext ruleContext,
}) {
  final AutocompleteLanguage effectiveLanguage = ruleContext.effectiveLanguage;

  // CSS rules:
  // - selector context (outside declaration blocks): allow HTML tag selectors
  // - properties only in declaration blocks, before ':'
  // - values/colors only in declaration blocks, after ':'
  if (effectiveLanguage == AutocompleteLanguage.css) {
    if (_isHtmlTagSuggestion(suggestion)) {
      return !ruleContext.css.isInDeclarationBlock;
    }

    if (_isHtmlAttributeSuggestion(suggestion)) {
      return false;
    }

    if (_isCssPropertySuggestion(suggestion)) {
      return ruleContext.css.isInDeclarationBlock &&
          !ruleContext.css.isInValueContext;
    }
    if (_isCssValueSuggestion(suggestion)) {
      return ruleContext.css.isInDeclarationBlock &&
          ruleContext.css.isInValueContext;
    }
  }

  // HTML rules:
  // - tags only while typing tag names
  // - attributes only while typing inside a tag's attribute area
  if (effectiveLanguage == AutocompleteLanguage.html) {
    if (_isHtmlTagSuggestion(suggestion)) {
      return ruleContext.html.isInsideTag && ruleContext.html.isTagNameContext;
    }
    if (_isHtmlAttributeSuggestion(suggestion)) {
      return ruleContext.html.isInsideTag &&
          ruleContext.html.isAttributeContext;
    }
  }

  return true;
}

bool _isTokenCharacter(String char) {
  if (char.isEmpty) {
    return false;
  }

  final int code = char.codeUnitAt(0);
  final bool isUppercase = code >= 65 && code <= 90;
  final bool isLowercase = code >= 97 && code <= 122;
  final bool isDigit = code >= 48 && code <= 57;
  return isUppercase ||
      isLowercase ||
      isDigit ||
      char == '-' ||
      char == '_' ||
      char == '#';
}

AutocompleteTokenMatch? extractAutocompleteToken({
  required String text,
  required int caretOffset,
}) {
  if (text.isEmpty || caretOffset < 0 || caretOffset > text.length) {
    return null;
  }

  int tokenStart = caretOffset;
  int tokenEnd = caretOffset;

  while (tokenStart > 0 && _isTokenCharacter(text[tokenStart - 1])) {
    tokenStart -= 1;
  }

  while (tokenEnd < text.length && _isTokenCharacter(text[tokenEnd])) {
    tokenEnd += 1;
  }

  if (tokenStart == tokenEnd) {
    return null;
  }

  final String token = text.substring(tokenStart, tokenEnd);
  if (token.trim().isEmpty) {
    return null;
  }

  return AutocompleteTokenMatch(
    token: token,
    range: TextRange(start: tokenStart, end: tokenEnd),
  );
}

_MemberAccessContext? _extractMemberAccessContext(String contextBeforeCaret) {
  if (contextBeforeCaret.isEmpty) {
    return null;
  }

  final RegExp trailingMemberPattern =
      RegExp(r'([A-Za-z_$][A-Za-z0-9_$]*)\.([A-Za-z0-9_#$-]*)$');
  final RegExpMatch? match =
      trailingMemberPattern.firstMatch(contextBeforeCaret);
  if (match == null) {
    return null;
  }

  final String? objectName = match.group(1);
  if (objectName == null || objectName.isEmpty) {
    return null;
  }

  return _MemberAccessContext(objectName: objectName);
}

bool _regexTargetsObject(String? pattern, String objectName) {
  if (pattern == null || pattern.isEmpty) {
    return false;
  }

  final String normalizedPattern = pattern.toLowerCase();
  final String escapedObjectName = RegExp.escape(objectName.toLowerCase());
  return normalizedPattern.contains('$escapedObjectName\\.');
}

bool _isDotNotationSuggestion(AutocompleteSuggestion suggestion) {
  return suggestion.label.contains('.') || suggestion.value.contains('.');
}

bool _matchesMemberContextByLabel({
  required AutocompleteSuggestion suggestion,
  required String normalizedObjectPrefix,
}) {
  final String normalizedLabel = suggestion.label.toLowerCase();
  final String normalizedValue = suggestion.value.toLowerCase();
  return normalizedLabel.startsWith(normalizedObjectPrefix) ||
      normalizedValue.startsWith(normalizedObjectPrefix);
}

String? _memberTailForContext({
  required AutocompleteSuggestion suggestion,
  required String normalizedObjectPrefix,
}) {
  final String normalizedLabel = suggestion.label.toLowerCase();
  if (normalizedLabel.startsWith(normalizedObjectPrefix)) {
    return normalizedLabel.substring(normalizedObjectPrefix.length);
  }

  final String normalizedValue = suggestion.value.toLowerCase();
  if (normalizedValue.startsWith(normalizedObjectPrefix)) {
    return normalizedValue.substring(normalizedObjectPrefix.length);
  }

  return null;
}

bool _matchesMemberToken({
  required String normalizedToken,
  required String normalizedValue,
  required String normalizedLabel,
  required String? memberTail,
}) {
  if (normalizedToken.isEmpty) {
    return true;
  }

  if (memberTail != null) {
    return memberTail.startsWith(normalizedToken);
  }

  return normalizedValue.startsWith(normalizedToken) ||
      normalizedLabel.startsWith(normalizedToken);
}

bool _isExactTypedSuggestion({
  required String normalizedToken,
  required String normalizedValue,
  required String normalizedLabel,
  required String normalizedInsert,
  required String? memberTail,
  required String normalizedObjectPrefix,
}) {
  if (normalizedToken.isEmpty) {
    return false;
  }

  if (memberTail != null && memberTail == normalizedToken) {
    return true;
  }

  if (normalizedValue == normalizedToken ||
      normalizedLabel == normalizedToken ||
      normalizedInsert == normalizedToken) {
    return true;
  }

  if (normalizedObjectPrefix.isNotEmpty) {
    if (normalizedValue.startsWith(normalizedObjectPrefix) &&
        normalizedValue.substring(normalizedObjectPrefix.length) ==
            normalizedToken) {
      return true;
    }
    if (normalizedLabel.startsWith(normalizedObjectPrefix) &&
        normalizedLabel.substring(normalizedObjectPrefix.length) ==
            normalizedToken) {
      return true;
    }
    if (normalizedInsert.startsWith(normalizedObjectPrefix) &&
        normalizedInsert.substring(normalizedObjectPrefix.length) ==
            normalizedToken) {
      return true;
    }
  }

  return false;
}

bool isInsideQuotedText(String textBeforeCaret) {
  if (textBeforeCaret.isEmpty) {
    return false;
  }

  bool inSingle = false;
  bool inDouble = false;
  bool inBacktick = false;
  bool escaped = false;

  for (int i = 0; i < textBeforeCaret.length; i += 1) {
    final String char = textBeforeCaret[i];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (inSingle || inDouble || inBacktick) {
      if (char == r'\') {
        escaped = true;
        continue;
      }
    }

    if (inSingle) {
      if (char == "'") {
        inSingle = false;
      }
      continue;
    }

    if (inDouble) {
      if (char == '"') {
        inDouble = false;
      }
      continue;
    }

    if (inBacktick) {
      if (char == '`') {
        inBacktick = false;
      }
      continue;
    }

    if (char == "'") {
      inSingle = true;
      continue;
    }

    if (char == '"') {
      inDouble = true;
      continue;
    }

    if (char == '`') {
      inBacktick = true;
    }
  }

  return inSingle || inDouble || inBacktick;
}

List<AutocompleteSuggestion> matchAutocompleteSuggestions({
  required String token,
  required List<AutocompleteSuggestion> suggestions,
  required int maxSuggestions,
  String contextBeforeCaret = '',
  int regexCandidateLimit = 40,
  AutocompleteLanguage contextLanguage = AutocompleteLanguage.mixed,
  AutocompleteLanguage mixedContextFallbackLanguage =
      AutocompleteLanguage.mixed,
}) {
  if (maxSuggestions <= 0) {
    return const [];
  }

  final String normalizedToken = token.trim().toLowerCase();
  final _MemberAccessContext? memberContext =
      _extractMemberAccessContext(contextBeforeCaret);
  final _AutocompleteRuleContext ruleContext = _buildRuleContext(
    contextBeforeCaret: contextBeforeCaret,
    contextLanguage: contextLanguage,
    mixedContextFallbackLanguage: mixedContextFallbackLanguage,
  );
  if (normalizedToken.isEmpty && memberContext == null) {
    return const [];
  }

  final String normalizedObjectName =
      memberContext?.objectName.toLowerCase() ?? '';
  final String normalizedObjectPrefix =
      normalizedObjectName.isEmpty ? '' : '$normalizedObjectName.';
  final Set<String> seenValues = <String>{};
  final List<_ScoredSuggestion> scoredMatches = <_ScoredSuggestion>[];
  final int shortlistLimit = math.max(maxSuggestions * 5, regexCandidateLimit);

  for (final AutocompleteSuggestion suggestion in suggestions) {
    // 1) Gate by effective language at cursor.
    if (!_matchesLanguageForContext(
      suggestion: suggestion,
      effectiveLanguage: ruleContext.effectiveLanguage,
    )) {
      continue;
    }

    // 2) Gate by syntax rules for the effective language.
    if (!_matchesSuggestionRules(
      suggestion: suggestion,
      ruleContext: ruleContext,
    )) {
      continue;
    }

    if (memberContext == null && _isDotNotationSuggestion(suggestion)) {
      continue;
    }

    final RegExp? whenRegex = suggestion.whenRegex;
    final bool whenRegexMatches = whenRegex != null &&
        contextBeforeCaret.isNotEmpty &&
        whenRegex.hasMatch(contextBeforeCaret);
    final String normalizedValue = suggestion.value.toLowerCase();
    final String normalizedLabel = suggestion.label.toLowerCase();
    final String normalizedInsert =
        (suggestion.insertText ?? suggestion.value).toLowerCase();
    final String? memberTail = memberContext == null
        ? null
        : _memberTailForContext(
            suggestion: suggestion,
            normalizedObjectPrefix: normalizedObjectPrefix,
          );

    if (memberContext != null) {
      final bool matchesByLabel = _matchesMemberContextByLabel(
        suggestion: suggestion,
        normalizedObjectPrefix: normalizedObjectPrefix,
      );
      final bool matchesByScopedRegex = whenRegexMatches &&
          _regexTargetsObject(suggestion.whenPattern, normalizedObjectName);
      if (!matchesByLabel && !matchesByScopedRegex) {
        continue;
      }
      if (!_matchesMemberToken(
        normalizedToken: normalizedToken,
        normalizedValue: normalizedValue,
        normalizedLabel: normalizedLabel,
        memberTail: memberTail,
      )) {
        continue;
      }
    }

    final String tokenTarget = memberTail ?? normalizedValue;
    final bool valueStartsWithToken =
        normalizedToken.isEmpty || tokenTarget.startsWith(normalizedToken);
    final bool labelStartsWithToken =
        normalizedToken.isEmpty || normalizedLabel.startsWith(normalizedToken);
    if (memberContext == null &&
        !valueStartsWithToken &&
        !labelStartsWithToken) {
      continue;
    }

    if (_isExactTypedSuggestion(
      normalizedToken: normalizedToken,
      normalizedValue: normalizedValue,
      normalizedLabel: normalizedLabel,
      normalizedInsert: normalizedInsert,
      memberTail: memberTail,
      normalizedObjectPrefix: normalizedObjectPrefix,
    )) {
      continue;
    }

    if (seenValues.contains(normalizedValue)) {
      continue;
    }

    seenValues.add(normalizedValue);
    int score = valueStartsWithToken ? 80 : 70;
    if (normalizedValue == normalizedToken ||
        normalizedLabel == normalizedToken) {
      score += 20;
    }
    if (memberTail != null && memberTail == normalizedToken) {
      score += 20;
    }
    score += suggestion.priority;

    if (whenRegexMatches) {
      score += suggestion.whenBoost;
    }

    if (memberContext != null) {
      score += 90;
    }

    scoredMatches.add(
      _ScoredSuggestion(
        suggestion: suggestion,
        score: score,
      ),
    );

    if (scoredMatches.length >= shortlistLimit) {
      break;
    }
  }

  scoredMatches.sort((a, b) {
    final int byScore = b.score.compareTo(a.score);
    if (byScore != 0) {
      return byScore;
    }

    return a.suggestion.value.compareTo(b.suggestion.value);
  });

  return scoredMatches
      .take(maxSuggestions)
      .map((entry) => entry.suggestion)
      .toList(growable: false);
}

TextEditingValue applyAutocompleteSuggestion({
  required TextEditingValue originalValue,
  required TextRange replaceRange,
  required String replacement,
}) {
  if (!replaceRange.isValid ||
      replaceRange.start < 0 ||
      replaceRange.end > originalValue.text.length ||
      replaceRange.start > replaceRange.end) {
    return originalValue;
  }

  final String updatedText = originalValue.text.replaceRange(
    replaceRange.start,
    replaceRange.end,
    replacement,
  );

  final int newOffset = replaceRange.start + replacement.length;

  return TextEditingValue(
    text: updatedText,
    selection: TextSelection.collapsed(offset: newOffset),
    composing: TextRange.empty,
  );
}
