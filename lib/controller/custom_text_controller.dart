import 'package:flutter/material.dart';
import 'package:phone_ide/editor/highlighter.dart';

class TextEditingControllerIDE extends TextEditingController {
  TextEditingControllerIDE({String? text, this.font}) : super(text: text) {
    // Initialize with plain text immediately so text is visible
    _updateCachedText();
    // Add listener before async init so we capture text changes
    addListener(_onTextChanged);
    _initializeHighlighter();
  }

  static String language = 'HTML';
  final CodeHighlighter highlighter = CodeHighlighter();
  final TextStyle? font;

  List<InlineSpan> _cached = const <InlineSpan>[];
  int _req = 0;
  bool _isInitialized = false;
  bool _isHighlighting = false;

  void _updateCachedText() {
    _cached = [TextSpan(text: text, style: font ?? const TextStyle(color: Colors.white))];
  }

  Future<void> _initializeHighlighter() async {
    try {
      debugPrint('Starting highlighter initialization...');
      await highlighter.initialize();
      _isInitialized = true;
      debugPrint('Highlighter initialized successfully, triggering rehighlight');

      // Do initial highlight now that highlighter is ready
      _rehighlight();
    } catch (e) {
      debugPrint('Failed to initialize highlighter: $e');
    }
  }

  void _onTextChanged() {
    // Prevent infinite loop - don't rehighlight if we're currently highlighting
    if (!_isHighlighting) {
      if (!_isInitialized) {
        // Update plain text immediately if highlighter not ready
        _updateCachedText();
      } else {
        _rehighlight();
      }
    }
  }

  void _rehighlight() {
    if (!_isInitialized) {
      // Show plain text if highlighter not ready
      _updateCachedText();
      return;
    }

    final int request = ++_req;

    debugPrint('Rehighlighting text of length: ${text.length}');
    highlighter.highlight(text).then((spans) {
      if (request != _req) return;

      debugPrint('Received ${spans.length} spans from highlighter');
      _isHighlighting = true;
      if (spans.isEmpty) {
        // Fallback to plain text if no spans returned
        debugPrint('No spans returned, using plain text');
        _cached = [TextSpan(text: text, style: font ?? const TextStyle(color: Colors.white))];
      } else {
        debugPrint('Applying ${spans.length} highlighted spans');
        _cached = spans.cast<InlineSpan>();
      }
      notifyListeners();
      _isHighlighting = false;
    }).catchError((e) {
      debugPrint('Error highlighting: $e');
      // Fallback to plain text on error
      _cached = [TextSpan(text: text, style: font ?? const TextStyle(color: Colors.white))];
      _isHighlighting = false;
      notifyListeners();
    });
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
    // Don't dispose the highlighter since it's a singleton shared across all controllers
    // The highlighter will be disposed when the app closes
    removeListener(_onTextChanged);
    super.dispose();
  }
}
