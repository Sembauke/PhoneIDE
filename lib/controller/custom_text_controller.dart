import 'package:flutter/material.dart';
import 'package:phone_ide/editor/highlighter.dart';

class TextEditingControllerIDE extends TextEditingController {
  TextEditingControllerIDE({String? text, this.font}) : super(text: text) {
    _updateCachedText();
    addListener(_onTextChanged);
    _initializeHighlighter();
  }

  static String language = 'HTML';
  final CodeHighlighter highlighter = CodeHighlighter();
  final TextStyle? font;

  List<InlineSpan> _cached = const <InlineSpan>[];
  bool _isInitialized = false;

  void _updateCachedText() {
    _cached = [TextSpan(text: text, style: font ?? const TextStyle(color: Colors.white))];
  }

  Future<void> _initializeHighlighter() async {
    try {
      await highlighter.initialize();
      _isInitialized = true;
      _rehighlight();
    } catch (e) {
      debugPrint('Failed to initialize highlighter: $e');
    }
  }

  void _onTextChanged() {
    if (_isInitialized) {
      _rehighlight();
    } else {
      _updateCachedText();
    }
  }

  void _rehighlight() {
    if (!_isInitialized) {
      _updateCachedText();
      return;
    }

    final spans = highlighter.highlight(text);

    if (spans.isEmpty) {
      _cached = [TextSpan(text: text, style: font ?? const TextStyle(color: Colors.white))];
    } else {
      _cached = spans.cast<InlineSpan>();
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpan(style: style ?? font, children: _cached);
  }

  @override
  void dispose() {
    removeListener(_onTextChanged);
    super.dispose();
  }
}
