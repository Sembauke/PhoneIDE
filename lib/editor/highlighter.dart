import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

class CodeHighlighter {
  static final CodeHighlighter _instance = CodeHighlighter._internal();
  factory CodeHighlighter() => _instance;
  CodeHighlighter._internal();

  Highlighter? _highlighter;
  bool _isInitialized = false;
  Completer<void>? _initCompleter;

  Future<void> initialize() async {
    if (_isInitialized) return;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      await Highlighter.initialize(['html', 'css', 'javascript']);

      final theme = await HighlighterTheme.loadDarkTheme();

      _highlighter = Highlighter(
        language: 'html',
        theme: theme,
      );

      _isInitialized = true;
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  Future<void> dispose() async {
    _isInitialized = false;
    _initCompleter = null;
    _highlighter = null;
  }

  List<TextSpan> highlight(String code) {
    if (!_isInitialized || _highlighter == null) {
      return [TextSpan(text: code, style: const TextStyle(color: Colors.white))];
    }

    try {
      final result = _highlighter!.highlight(code);
      return [result];
    } catch (e) {
      return [TextSpan(text: code, style: const TextStyle(color: Colors.white))];
    }
  }
}
