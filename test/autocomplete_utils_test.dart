import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/autocomplete_data.dart';
import 'package:phone_ide/editor/autocomplete_utils.dart';

void main() {
  group('extractAutocompleteToken', () {
    test('extracts token in the middle of a line', () {
      const String text = 'color: ora;';
      final AutocompleteTokenMatch? match = extractAutocompleteToken(
        text: text,
        caretOffset: text.indexOf('ora') + 2,
      );

      expect(match, isNotNull);
      expect(match!.token, 'ora');
      expect(match.range, const TextRange(start: 7, end: 10));
    });

    test('extracts token at the start of a line', () {
      const String text = 'orange is nice';
      final AutocompleteTokenMatch? match = extractAutocompleteToken(
        text: text,
        caretOffset: 2,
      );

      expect(match, isNotNull);
      expect(match!.token, 'orange');
      expect(match.range, const TextRange(start: 0, end: 6));
    });

    test('extracts token at the end of a line', () {
      const String text = 'setTimeout';
      final AutocompleteTokenMatch? match = extractAutocompleteToken(
        text: text,
        caretOffset: text.length,
      );

      expect(match, isNotNull);
      expect(match!.token, 'setTimeout');
      expect(match.range, const TextRange(start: 0, end: 10));
    });

    test('handles punctuation-adjacent token', () {
      const String text = 'background-color:#ffa';
      final AutocompleteTokenMatch? match = extractAutocompleteToken(
        text: text,
        caretOffset: text.length,
      );

      expect(match, isNotNull);
      expect(match!.token, '#ffa');
      expect(match.range, const TextRange(start: 17, end: 21));
    });
  });

  group('matchAutocompleteSuggestions', () {
    test('matches orange suggestions with prefix search', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'ora',
        suggestions: kEditorAutocompleteSuggestions,
        maxSuggestions: 6,
      );

      expect(matches.isNotEmpty, isTrue);
      expect(matches.map((AutocompleteSuggestion e) => e.value),
          contains('orange'));
      expect(matches.length <= 6, isTrue);
    });

    test('returns empty list when there are no matches', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'zzzz',
        suggestions: kEditorAutocompleteSuggestions,
        maxSuggestions: 6,
      );

      expect(matches, isEmpty);
    });

    test('matches by label prefix when value differs', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'but',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'btn',
            label: 'button',
            category: 'HTML tag',
          ),
        ],
        maxSuggestions: 6,
      );

      expect(matches.length, 1);
      expect(matches.first.value, 'btn');
      expect(matches.first.label, 'button');
    });

    test('hides dotted child suggestions before dot notation', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'cons',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'console',
            category: 'JavaScript global',
          ),
          AutocompleteSuggestion(
            value: 'clear',
            label: 'console.clear',
            category: 'console member',
          ),
        ],
        maxSuggestions: 6,
      );

      expect(matches.length, 1);
      expect(matches.first.value, 'console');
    });

    test('boosts regex-matching suggestions with context', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'l',
        suggestions: <AutocompleteSuggestion>[
          const AutocompleteSuggestion(
            value: 'let',
            category: 'JavaScript keyword',
          ),
          AutocompleteSuggestion(
            value: 'log',
            label: 'console.log',
            category: 'JavaScript snippet',
            whenPattern: 'console\\.[a-zA-Z]*\$',
            whenRegex: RegExp('console\\.[a-zA-Z]*\$'),
            whenBoost: 120,
          ),
        ],
        maxSuggestions: 2,
        contextBeforeCaret: 'console.l',
      );

      expect(matches.length, 1);
      expect(matches.first.value, 'log');
    });

    test('matches member tail when value contains object prefix', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'l',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'console.log',
            label: 'console.log',
            category: 'JavaScript snippet',
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: 'console.l',
      );

      expect(matches.length, 1);
      expect(matches.first.label, 'console.log');
    });

    test('shows only child suggestions after dot notation', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'c',
        suggestions: <AutocompleteSuggestion>[
          const AutocompleteSuggestion(
            value: 'class',
            category: 'JavaScript keyword',
          ),
          const AutocompleteSuggestion(
            value: 'console',
            category: 'JavaScript global',
          ),
          AutocompleteSuggestion(
            value: 'clear',
            label: 'console.clear',
            category: 'console member',
            whenPattern: r'console\.[A-Za-z_]*$',
            whenRegex: RegExp(r'console\.[A-Za-z_]*$'),
            whenBoost: 120,
          ),
          const AutocompleteSuggestion(
            value: 'console.log',
            label: 'console.log',
            category: 'JavaScript snippet',
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: 'console.c',
      );

      expect(matches.length, 1);
      expect(matches.first.label, 'console.clear');
    });

    test('supports empty token immediately after dot', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: '',
        suggestions: <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'clear',
            label: 'console.clear',
            category: 'console member',
            whenPattern: r'console\.[A-Za-z_]*$',
            whenRegex: RegExp(r'console\.[A-Za-z_]*$'),
            whenBoost: 120,
          ),
          const AutocompleteSuggestion(
            value: 'const',
            category: 'JavaScript keyword',
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: 'console.',
      );

      expect(matches.length, 1);
      expect(matches.first.label, 'console.clear');
    });
  });

  group('applyAutocompleteSuggestion', () {
    test('replaces current token in middle of line and moves cursor', () {
      const String text = 'color: ora;';
      final TextEditingValue updated = applyAutocompleteSuggestion(
        originalValue: const TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: 10),
        ),
        replaceRange: const TextRange(start: 7, end: 10),
        replacement: 'orange',
      );

      expect(updated.text, 'color: orange;');
      expect(updated.selection.baseOffset, 13);
      expect(updated.selection.extentOffset, 13);
    });
  });
}
