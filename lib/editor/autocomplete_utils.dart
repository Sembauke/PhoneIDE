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
  if (suggestion.label.contains('.') || suggestion.value.contains('.')) {
    return true;
  }

  final String? whenPattern = suggestion.whenPattern;
  if (whenPattern == null || whenPattern.isEmpty) {
    return false;
  }

  return whenPattern.contains(r'\.');
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

List<AutocompleteSuggestion> matchAutocompleteSuggestions({
  required String token,
  required List<AutocompleteSuggestion> suggestions,
  required int maxSuggestions,
  String contextBeforeCaret = '',
  int regexCandidateLimit = 40,
}) {
  if (maxSuggestions <= 0) {
    return const [];
  }

  final String normalizedToken = token.trim().toLowerCase();
  final _MemberAccessContext? memberContext =
      _extractMemberAccessContext(contextBeforeCaret);
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
    if (memberContext == null && _isDotNotationSuggestion(suggestion)) {
      continue;
    }

    final RegExp? whenRegex = suggestion.whenRegex;
    final bool whenRegexMatches = whenRegex != null &&
        contextBeforeCaret.isNotEmpty &&
        whenRegex.hasMatch(contextBeforeCaret);
    final String normalizedValue = suggestion.value.toLowerCase();
    final String normalizedLabel = suggestion.label.toLowerCase();
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
