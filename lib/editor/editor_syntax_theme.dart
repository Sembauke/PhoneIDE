import 'package:flutter/material.dart';

/// Token colors for one editor, independent of other editors and the app theme.
@immutable
class EditorSyntaxTheme {
  const EditorSyntaxTheme({
    required this.foreground,
    required this.comment,
    required this.keyword,
    required this.string,
    required this.number,
    required this.type,
    required this.function,
    required this.tag,
    required this.attribute,
    required this.operator,
    required this.punctuation,
    required this.variable,
  });

  /// Atom One Dark, matching the editor's built-in palette.
  static const atomOneDark = EditorSyntaxTheme(
    foreground: Color(0xFFABB2BF),
    comment: Color(0xFF5C6370),
    keyword: Color(0xFFC678DD),
    string: Color(0xFF98C379),
    number: Color(0xFFD19A66),
    type: Color(0xFFE5C07B),
    function: Color(0xFF61AFEF),
    tag: Color(0xFFE06C75),
    attribute: Color(0xFFD19A66),
    operator: Color(0xFF56B6C2),
    punctuation: Color(0xFFABB2BF),
    variable: Color(0xFFE06C75),
  );

  final Color foreground;
  final Color comment;
  final Color keyword;
  final Color string;
  final Color number;
  final Color type;
  final Color function;
  final Color tag;
  final Color attribute;
  final Color operator;
  final Color punctuation;
  final Color variable;

  EditorSyntaxTheme copyWith({
    Color? foreground,
    Color? comment,
    Color? keyword,
    Color? string,
    Color? number,
    Color? type,
    Color? function,
    Color? tag,
    Color? attribute,
    Color? operator,
    Color? punctuation,
    Color? variable,
  }) =>
      EditorSyntaxTheme(
        foreground: foreground ?? this.foreground,
        comment: comment ?? this.comment,
        keyword: keyword ?? this.keyword,
        string: string ?? this.string,
        number: number ?? this.number,
        type: type ?? this.type,
        function: function ?? this.function,
        tag: tag ?? this.tag,
        attribute: attribute ?? this.attribute,
        operator: operator ?? this.operator,
        punctuation: punctuation ?? this.punctuation,
        variable: variable ?? this.variable,
      );

  @override
  bool operator ==(Object other) =>
      other is EditorSyntaxTheme &&
      foreground == other.foreground &&
      comment == other.comment &&
      keyword == other.keyword &&
      string == other.string &&
      number == other.number &&
      type == other.type &&
      function == other.function &&
      tag == other.tag &&
      attribute == other.attribute &&
      operator == other.operator &&
      punctuation == other.punctuation &&
      variable == other.variable;

  @override
  int get hashCode => Object.hash(
        foreground,
        comment,
        keyword,
        string,
        number,
        type,
        function,
        tag,
        attribute,
        operator,
        punctuation,
        variable,
      );
}
