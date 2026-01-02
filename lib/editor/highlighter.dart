import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_ide/editor/highlighter_server.dart';

class TokenColorGroup {
  final List<String> scopes;
  final TextStyle style;

  factory TokenColorGroup.fromJson(Map<String, dynamic> data) {
    final color = data['settings']['foreground'] == null
        ? '#FF0000'
        : data['settings']['foreground'] as String;

    return TokenColorGroup(
      scopes: ScopeSelector.fromJson(data['scope']).toList(),
      style: TextStyle(
        color: Color(
          int.parse(color.substring(1, 7), radix: 16) + 0xFF000000,
        ),
      ),
    );
  }

  TokenColorGroup({
    required this.scopes,
    required this.style,
  });
}

class TokenColors {
  final List<TokenColorGroup> groups;

  TokenColors({required this.groups});

  factory TokenColors.fromJson(List<dynamic> data) {
    List<TokenColorGroup> groups = data.map((item) {
      return TokenColorGroup.fromJson(Map<String, dynamic>.from(item as Map));
    }).toList();

    return TokenColors(groups: groups);
  }
}

sealed class ScopeSelector {
  const ScopeSelector();

  List<String> toList();

  factory ScopeSelector.fromJson(Object? raw) => switch (raw) {
        String s => ScopeSingle(s),
        List l => ScopeMany(l.map((e) => e.toString()).toList(growable: false)),
        null => const ScopeMany(<String>[]),
        _ => throw FormatException('Invalid scope type: ${raw.runtimeType}'),
      };
}

final class ScopeSingle extends ScopeSelector {
  final String value;
  const ScopeSingle(this.value);

  @override
  List<String> toList() => <String>[value];
}

final class ScopeMany extends ScopeSelector {
  final List<String> values;
  const ScopeMany(this.values);

  @override
  List<String> toList() => values;
}

class ScopeCapture {
  final double startIndex;
  final double endIndex;
  final ScopeSelector scopes;

  ScopeCapture({
    required this.startIndex,
    required this.endIndex,
    required this.scopes,
  });

  factory ScopeCapture.fromJson(Map<String, dynamic> data) {
    return ScopeCapture(
      startIndex: (data['startIndex'] as num).toDouble(),
      endIndex: (data['endIndex'] as num).toDouble(),
      scopes: ScopeSelector.fromJson(data['scopes']),
    );
  }
}

class CodeHighlighter {
  // Singleton pattern
  static final CodeHighlighter _instance = CodeHighlighter._internal();
  factory CodeHighlighter() => _instance;
  CodeHighlighter._internal();

  TokenColors? tokenColors;
  SyntaxHighlightingServer? _server;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  final notInTokenGroups = [];

  TextStyle calculateHighlightPriority(
    List<String> specScopes,
    List<TokenColorGroup> incScopesGroups,
  ) {
    int priority = -1;

    TextStyle outGoingTextStlye = const TextStyle(color: Colors.white);

    for (final specScope in specScopes.reversed) {
      bool matchedThisScope = false;

      groups:
      for (final incScopeGroup in incScopesGroups) {
        // If we've already proven this specScope can never match anything, skip it
        if (notInTokenGroups.contains(specScope)) {
          continue;
        }

        for (final incScope in incScopeGroup.scopes) {
          final matches =
              (specScope == incScope) || specScope.startsWith('$incScope.');
          if (!matches) {
            continue;
          }

          matchedThisScope = true;

          if (specScope == incScope) {
            outGoingTextStlye = incScopeGroup.style;
            break groups;
          }

          final localPriority = incScope.split('.').length;

          if (localPriority >= priority) {
            priority = localPriority;
            outGoingTextStlye = incScopeGroup.style;
          }
        }
      }

      if (!matchedThisScope) {
        notInTokenGroups.add(specScope);
      }
    }

    return outGoingTextStlye;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      // Load theme
      if (tokenColors == null) {
        final themeFile = await rootBundle.loadString(
          'packages/phone_ide/assets/highlighter/dark.json',
        );
        final tokenColorObjects = jsonDecode(themeFile)['tokenColors'];

        tokenColors = TokenColors.fromJson(
          List<dynamic>.from(tokenColorObjects as List),
        );
      }

      // Initialize server
      _server = SyntaxHighlightingServer();
      await _server!.initialize();

      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_server != null) {
      await _server!.dispose();
      _server = null;
    }
    _isInitialized = false;
    _initCompleter = null;
  }

  Future<List<TextSpan>> highlight(String code) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_server == null || tokenColors == null) {
      return [TextSpan(text: code, style: const TextStyle(color: Colors.white))];
    }

    try {
      final rawScopes = await _server!.tokenizeLine(code);

      if (rawScopes.isEmpty) {
        return [TextSpan(text: code, style: const TextStyle(color: Colors.white))];
      }

      final scopes = rawScopes.map((obj) {
        return ScopeCapture.fromJson(Map<String, dynamic>.from(obj as Map));
      }).toList();

      final textSpans = scopes.map((scope) {
        return TextSpan(
          text: code.substring(
            scope.startIndex.toInt(),
            scope.endIndex.toInt(),
          ),
          style: calculateHighlightPriority(
            scope.scopes.toList(),
            tokenColors!.groups,
          ),
        );
      }).toList();

      // Check if tokens cover the entire code string
      // If not, append remaining characters as plain text
      final lastTokenEnd = scopes.isEmpty ? 0 : scopes.last.endIndex.toInt();
      if (lastTokenEnd < code.length) {
        textSpans.add(TextSpan(
          text: code.substring(lastTokenEnd),
          style: const TextStyle(color: Colors.white),
        ));
      }

      return textSpans;
    } catch (e) {
      log('Error highlighting: $e');
      return [TextSpan(text: code, style: const TextStyle(color: Colors.white))];
    }
  }
}

// SyntaxHighlightingServer moved to highlighter_server.dart