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
      const List<AutocompleteSuggestion> suggestions = <AutocompleteSuggestion>[
        AutocompleteSuggestion(
          value: 'orange',
          category: 'CSS color',
          language: AutocompleteLanguage.css,
        ),
        AutocompleteSuggestion(
          value: 'orangered',
          category: 'CSS color',
          language: AutocompleteLanguage.css,
        ),
        AutocompleteSuggestion(
          value: 'orchid',
          category: 'CSS color',
          language: AutocompleteLanguage.css,
        ),
        AutocompleteSuggestion(
          value: 'const',
          category: 'JavaScript keyword',
          language: AutocompleteLanguage.javascript,
        ),
      ];

      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'ora',
        suggestions: suggestions,
        maxSuggestions: 6,
      );

      expect(matches.isNotEmpty, isTrue);
      expect(matches.map((AutocompleteSuggestion e) => e.value),
          contains('orange'));
      expect(matches.length <= 6, isTrue);
    });

    test('returns empty list when there are no matches', () {
      const List<AutocompleteSuggestion> suggestions = <AutocompleteSuggestion>[
        AutocompleteSuggestion(
          value: 'orange',
          category: 'CSS color',
        ),
        AutocompleteSuggestion(
          value: 'const',
          category: 'JavaScript keyword',
        ),
      ];
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'zzzz',
        suggestions: suggestions,
        maxSuggestions: 6,
      );

      expect(matches, isEmpty);
    });

    test('hides suggestion when token exactly matches value', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'console',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'console',
            category: 'JavaScript global',
          ),
        ],
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

    test(
      'keeps non-dotted suggestions even when they have dot-context regex',
      () {
        final List<AutocompleteSuggestion> matches =
            matchAutocompleteSuggestions(
          token: 'que',
          suggestions: <AutocompleteSuggestion>[
            AutocompleteSuggestion(
              value: 'querySelector',
              category: 'JavaScript DOM API',
              whenPattern: r'document\.[A-Za-z_]*$',
              whenRegex: RegExp(r'document\.[A-Za-z_]*$'),
              whenBoost: 80,
            ),
            const AutocompleteSuggestion(
              value: 'console.clear',
              category: 'console member',
            ),
          ],
          maxSuggestions: 6,
          contextBeforeCaret: 'que',
        );

        expect(matches.length, 1);
        expect(matches.first.value, 'querySelector');
      },
    );

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

    test('hides member suggestion when token exactly matches member tail', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'log',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'console.log',
            label: 'console.log',
            category: 'console member',
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: 'console.log',
      );

      expect(matches, isEmpty);
    });

    test('hides CSS property suggestions outside declaration blocks', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'dis',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'display',
            category: 'CSS property',
            language: AutocompleteLanguage.css,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '.card dis',
        contextLanguage: AutocompleteLanguage.css,
      );

      expect(matches, isEmpty);
    });

    test('shows CSS property suggestions inside declaration blocks', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'dis',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'display',
            category: 'CSS property',
            language: AutocompleteLanguage.css,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '.card { dis',
        contextLanguage: AutocompleteLanguage.css,
      );

      expect(matches.length, 1);
      expect(matches.first.value, 'display');
    });

    test('shows HTML tag selectors in CSS selector context', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'h',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'h1',
            category: 'HTML tag',
            language: AutocompleteLanguage.html,
          ),
          AutocompleteSuggestion(
            value: 'header',
            category: 'HTML tag',
            language: AutocompleteLanguage.html,
          ),
          AutocompleteSuggestion(
            value: 'height',
            category: 'CSS property',
            language: AutocompleteLanguage.css,
          ),
        ],
        maxSuggestions: 6,
        contextBeforeCaret: 'h',
        contextLanguage: AutocompleteLanguage.css,
      );

      expect(matches.length, 2);
      expect(
          matches.map((AutocompleteSuggestion suggestion) => suggestion.value),
          containsAll(<String>['h1', 'header']));
    });

    test('hides HTML tag selectors once inside CSS declaration block', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'h',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'h1',
            category: 'HTML tag',
            language: AutocompleteLanguage.html,
          ),
          AutocompleteSuggestion(
            value: 'height',
            category: 'CSS property',
            language: AutocompleteLanguage.css,
          ),
        ],
        maxSuggestions: 6,
        contextBeforeCaret: '.card { h',
        contextLanguage: AutocompleteLanguage.css,
      );

      expect(matches.length, 1);
      expect(matches.first.value, 'height');
    });

    test('shows CSS values only in value context after colon', () {
      final List<AutocompleteSuggestion> noValueMatches =
          matchAutocompleteSuggestions(
        token: 'fl',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'flex',
            category: 'CSS value',
            language: AutocompleteLanguage.css,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '.card { fl',
        contextLanguage: AutocompleteLanguage.css,
      );
      expect(noValueMatches, isEmpty);

      final List<AutocompleteSuggestion> valueMatches =
          matchAutocompleteSuggestions(
        token: 'fl',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'flex',
            category: 'CSS value',
            language: AutocompleteLanguage.css,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '.card { display: fl',
        contextLanguage: AutocompleteLanguage.css,
      );
      expect(valueMatches.length, 1);
      expect(valueMatches.first.value, 'flex');
    });

    test('uses mixed-language rules for style and script blocks', () {
      final List<AutocompleteSuggestion> styleMatches =
          matchAutocompleteSuggestions(
        token: 'dis',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'display',
            category: 'CSS property',
            language: AutocompleteLanguage.css,
          ),
          AutocompleteSuggestion(
            value: 'div',
            category: 'HTML tag',
            language: AutocompleteLanguage.html,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '<style>\n.card { dis',
        contextLanguage: AutocompleteLanguage.mixed,
      );
      expect(styleMatches.length, 1);
      expect(styleMatches.first.value, 'display');

      final List<AutocompleteSuggestion> scriptMatches =
          matchAutocompleteSuggestions(
        token: 'con',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'const',
            category: 'JavaScript keyword',
            language: AutocompleteLanguage.javascript,
          ),
          AutocompleteSuggestion(
            value: 'color',
            category: 'CSS property',
            language: AutocompleteLanguage.css,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '<script>\ncon',
        contextLanguage: AutocompleteLanguage.mixed,
      );
      expect(scriptMatches.length, 1);
      expect(scriptMatches.first.value, 'const');
    });

    test('shows HTML attributes only while typing inside a tag', () {
      final List<AutocompleteSuggestion> outsideTagMatches =
          matchAutocompleteSuggestions(
        token: 'cl',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'class',
            category: 'HTML attribute',
            language: AutocompleteLanguage.html,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: 'text cl',
        contextLanguage: AutocompleteLanguage.html,
      );
      expect(outsideTagMatches, isEmpty);

      final List<AutocompleteSuggestion> insideTagMatches =
          matchAutocompleteSuggestions(
        token: 'cl',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'class',
            category: 'HTML attribute',
            language: AutocompleteLanguage.html,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '<div cl',
        contextLanguage: AutocompleteLanguage.html,
      );
      expect(insideTagMatches.length, 1);
      expect(insideTagMatches.first.value, 'class');
    });

    test('hides HTML tag suggestions in mixed HTML text content', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'h',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'h1',
            category: 'HTML tag',
            language: AutocompleteLanguage.html,
          ),
          AutocompleteSuggestion(
            value: 'h2',
            category: 'HTML tag',
            language: AutocompleteLanguage.html,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '<!DOCTYPE html>\n<div>hello</div>\nh',
        contextLanguage: AutocompleteLanguage.mixed,
      );

      expect(matches, isEmpty);
    });

    test('shows HTML tag suggestions in mixed HTML tag context', () {
      final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
        token: 'h',
        suggestions: const <AutocompleteSuggestion>[
          AutocompleteSuggestion(
            value: 'h1',
            category: 'HTML tag',
            language: AutocompleteLanguage.html,
          ),
          AutocompleteSuggestion(
            value: 'h2',
            category: 'HTML tag',
            language: AutocompleteLanguage.html,
          ),
        ],
        maxSuggestions: 4,
        contextBeforeCaret: '<!DOCTYPE html>\n<',
        contextLanguage: AutocompleteLanguage.mixed,
      );

      expect(matches.length, 2);
      expect(matches.first.value, anyOf('h1', 'h2'));
    });

    test(
      'uses html fallback for mixed context and hides cross-language suggestions in plain text',
      () {
        final List<AutocompleteSuggestion> matches =
            matchAutocompleteSuggestions(
          token: 'p',
          suggestions: const <AutocompleteSuggestion>[
            AutocompleteSuggestion(
              value: 'Promise',
              category: 'JavaScript global',
              language: AutocompleteLanguage.javascript,
            ),
            AutocompleteSuggestion(
              value: 'padding',
              category: 'CSS property',
              language: AutocompleteLanguage.css,
            ),
            AutocompleteSuggestion(
              value: 'p',
              category: 'HTML tag',
              language: AutocompleteLanguage.html,
            ),
          ],
          maxSuggestions: 6,
          contextBeforeCaret: 'Welcome to freeCodeCamp\n\np',
          contextLanguage: AutocompleteLanguage.mixed,
          mixedContextFallbackLanguage: AutocompleteLanguage.html,
        );

        expect(matches, isEmpty);
      },
    );

    test(
      'keeps broad mixed matching when mixed fallback is not constrained',
      () {
        final List<AutocompleteSuggestion> matches =
            matchAutocompleteSuggestions(
          token: 'p',
          suggestions: const <AutocompleteSuggestion>[
            AutocompleteSuggestion(
              value: 'Promise',
              category: 'JavaScript global',
              language: AutocompleteLanguage.javascript,
            ),
            AutocompleteSuggestion(
              value: 'padding',
              category: 'CSS property',
              language: AutocompleteLanguage.css,
            ),
          ],
          maxSuggestions: 6,
          contextBeforeCaret: 'plain text p',
          contextLanguage: AutocompleteLanguage.mixed,
          mixedContextFallbackLanguage: AutocompleteLanguage.mixed,
        );

        expect(matches.length, 2);
      },
    );
  });

  group('isInsideQuotedText', () {
    test('returns true inside double quotes', () {
      expect(isInsideQuotedText('const a = "hel'), isTrue);
    });

    test('returns true inside single quotes', () {
      expect(isInsideQuotedText("const a = 'hel"), isTrue);
    });

    test('returns true inside backticks', () {
      expect(isInsideQuotedText('const a = `hel'), isTrue);
    });

    test('returns false after closed quotes', () {
      expect(isInsideQuotedText('const a = "hello"; con'), isFalse);
    });

    test('handles escaped quote characters', () {
      expect(isInsideQuotedText(r'const a = "he\"l'), isTrue);
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
