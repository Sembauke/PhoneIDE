import 'package:flutter/material.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';

class TextEditingControllerIDE extends TextEditingController {
  TextEditingControllerIDE({Key? key, this.font, this.language = 'HTML'});

  String language;
  final TextStyle? font;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextMateHighlighterRegistry.instance.buildTextSpan(
      text: text,
      language: language,
      style: style,
    );
  }
}
