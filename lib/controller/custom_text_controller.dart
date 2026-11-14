import 'package:flutter/material.dart';
import 'package:phone_ide/editor/editor_syntax_theme.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';

class TextEditingControllerIDE extends TextEditingController {
  TextEditingControllerIDE({
    Key? key,
    this.font,
    this.language = 'HTML',
    EditorSyntaxTheme? syntaxTheme,
  }) : _syntaxTheme = syntaxTheme;

  String language;
  final TextStyle? font;
  EditorSyntaxTheme? _syntaxTheme;

  EditorSyntaxTheme? get syntaxTheme => _syntaxTheme;

  set syntaxTheme(EditorSyntaxTheme? value) {
    if (_syntaxTheme == value) return;
    _syntaxTheme = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final highlighted = TextMateHighlighterRegistry.instance.buildTextSpan(
      text: text,
      language: language,
      style: style,
      syntaxTheme: syntaxTheme,
    );
    if (!withComposing ||
        !value.isComposingRangeValid ||
        value.composing.isCollapsed) {
      return highlighted;
    }

    var offset = 0;
    final spans = <InlineSpan>[];
    final composing = value.composing;
    void visit(TextSpan span, TextStyle inherited) {
      final resolvedStyle = inherited.merge(span.style);
      final text = span.text;
      if (text != null && text.isNotEmpty) {
        final end = offset + text.length;
        final startInText = (composing.start - offset).clamp(0, text.length);
        final endInText = (composing.end - offset).clamp(0, text.length);
        if (startInText < endInText) {
          if (startInText > 0) {
            spans.add(TextSpan(
                text: text.substring(0, startInText), style: resolvedStyle));
          }
          spans.add(TextSpan(
            text: text.substring(startInText, endInText),
            style: resolvedStyle.copyWith(
              decoration: TextDecoration.combine([
                if (resolvedStyle.decoration != null) resolvedStyle.decoration!,
                TextDecoration.underline,
              ]),
            ),
          ));
          if (endInText < text.length) {
            spans.add(TextSpan(
                text: text.substring(endInText), style: resolvedStyle));
          }
        } else {
          spans.add(TextSpan(text: text, style: resolvedStyle));
        }
        offset = end;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (child is TextSpan) visit(child, resolvedStyle);
      }
    }

    visit(highlighted, const TextStyle());
    return TextSpan(children: spans);
  }
}
