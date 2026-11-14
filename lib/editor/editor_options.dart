import 'package:flutter/material.dart';
import 'package:phone_ide/editor/editor_syntax_theme.dart';

const _unchanged = Object();

@immutable
class EditorOptions {
  EditorOptions({
    this.backgroundColor = const Color(0xFF2A2A40),
    this.regionOptions,
    this.linebarColor = const Color(0xFF3B3B4F),
    this.linebarTextColor = Colors.white,
    this.linebarBorderColor = const Color(0xFF888888),
    this.textColor = const Color(0xDDFFFFFF),
    this.cursorColor,
    this.selectionColor,
    this.selectionHandleColor,
    this.activeLineColor,
    this.activeLineBorderColor,
    this.fontSize = 18,
    this.lineHeight = 1.5,
    this.linebarWidth = 28,
    this.syntaxTheme,
    this.showLinebar = true,
    this.takeFullHeight = true,
    this.isEditable = true,
    this.fontFamily,
  }) {
    if (!fontSize.isFinite || fontSize <= 0) {
      throw ArgumentError.value(
          fontSize, 'fontSize', 'Must be finite and positive');
    }
    if (!lineHeight.isFinite || lineHeight <= 0) {
      throw ArgumentError.value(
          lineHeight, 'lineHeight', 'Must be finite and positive');
    }
    if (!linebarWidth.isFinite || linebarWidth < 0) {
      throw ArgumentError.value(
          linebarWidth, 'linebarWidth', 'Must be finite and nonnegative');
    }
  }

  final Color backgroundColor;
  final Color linebarColor;
  final Color linebarTextColor;
  final Color linebarBorderColor;
  final Color textColor;
  final Color? cursorColor;
  final Color? selectionColor;
  final Color? selectionHandleColor;

  /// Optional background and 3 logical pixel leading stripe for the caret row.
  final Color? activeLineColor;
  final Color? activeLineBorderColor;

  final double fontSize;

  /// Line height as a multiple of [fontSize], before accessibility text scaling.
  final double lineHeight;

  /// Minimum gutter width. It grows to fit longer numbers and larger text.
  final double linebarWidth;

  /// Null retains the original Atom One Dark syntax colors.
  final EditorSyntaxTheme? syntaxTheme;
  final EditorRegionOptions? regionOptions;
  final bool takeFullHeight;
  final bool isEditable;
  final bool showLinebar;
  final String? fontFamily;
  EditorOptions copyWith({
    Color? backgroundColor,
    Color? linebarColor,
    Color? linebarTextColor,
    Color? linebarBorderColor,
    Color? textColor,
    Object? cursorColor = _unchanged,
    Object? selectionColor = _unchanged,
    Object? selectionHandleColor = _unchanged,
    Object? activeLineColor = _unchanged,
    Object? activeLineBorderColor = _unchanged,
    double? fontSize,
    double? lineHeight,
    double? linebarWidth,
    Object? syntaxTheme = _unchanged,
    Object? regionOptions = _unchanged,
    bool? takeFullHeight,
    bool? isEditable,
    bool? showLinebar,
    Object? fontFamily = _unchanged,
  }) =>
      EditorOptions(
        backgroundColor: backgroundColor ?? this.backgroundColor,
        linebarColor: linebarColor ?? this.linebarColor,
        linebarTextColor: linebarTextColor ?? this.linebarTextColor,
        linebarBorderColor: linebarBorderColor ?? this.linebarBorderColor,
        textColor: textColor ?? this.textColor,
        cursorColor: identical(cursorColor, _unchanged)
            ? this.cursorColor
            : cursorColor as Color?,
        selectionColor: identical(selectionColor, _unchanged)
            ? this.selectionColor
            : selectionColor as Color?,
        selectionHandleColor: identical(selectionHandleColor, _unchanged)
            ? this.selectionHandleColor
            : selectionHandleColor as Color?,
        activeLineColor: identical(activeLineColor, _unchanged)
            ? this.activeLineColor
            : activeLineColor as Color?,
        activeLineBorderColor: identical(activeLineBorderColor, _unchanged)
            ? this.activeLineBorderColor
            : activeLineBorderColor as Color?,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        linebarWidth: linebarWidth ?? this.linebarWidth,
        syntaxTheme: identical(syntaxTheme, _unchanged)
            ? this.syntaxTheme
            : syntaxTheme as EditorSyntaxTheme?,
        regionOptions: identical(regionOptions, _unchanged)
            ? this.regionOptions
            : regionOptions as EditorRegionOptions?,
        takeFullHeight: takeFullHeight ?? this.takeFullHeight,
        isEditable: isEditable ?? this.isEditable,
        showLinebar: showLinebar ?? this.showLinebar,
        fontFamily: identical(fontFamily, _unchanged)
            ? this.fontFamily
            : fontFamily as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is EditorOptions &&
      backgroundColor == other.backgroundColor &&
      linebarColor == other.linebarColor &&
      linebarTextColor == other.linebarTextColor &&
      linebarBorderColor == other.linebarBorderColor &&
      textColor == other.textColor &&
      cursorColor == other.cursorColor &&
      selectionColor == other.selectionColor &&
      selectionHandleColor == other.selectionHandleColor &&
      activeLineColor == other.activeLineColor &&
      activeLineBorderColor == other.activeLineBorderColor &&
      fontSize == other.fontSize &&
      lineHeight == other.lineHeight &&
      linebarWidth == other.linebarWidth &&
      syntaxTheme == other.syntaxTheme &&
      regionOptions == other.regionOptions &&
      takeFullHeight == other.takeFullHeight &&
      isEditable == other.isEditable &&
      showLinebar == other.showLinebar &&
      fontFamily == other.fontFamily;

  @override
  int get hashCode => Object.hashAll([
        backgroundColor,
        linebarColor,
        linebarTextColor,
        linebarBorderColor,
        textColor,
        cursorColor,
        selectionColor,
        selectionHandleColor,
        activeLineColor,
        activeLineBorderColor,
        fontSize,
        lineHeight,
        linebarWidth,
        syntaxTheme,
        regionOptions,
        takeFullHeight,
        isEditable,
        showLinebar,
        fontFamily,
      ]);
}

@immutable
class EditorRegionOptions {
  EditorRegionOptions({
    required this.start,
    required this.end,
    this.color = const Color(0xFF0A0A23),
    this.borderColor,
  });

  final int? start;
  final int? end;
  final Color color;

  /// Optional 3 logical pixel leading border across the entire editable region.
  /// It remains visible without focus and does not change the text's padding.
  final Color? borderColor;
  EditorRegionOptions copyWith({
    Object? start = _unchanged,
    Object? end = _unchanged,
    Color? color,
    Object? borderColor = _unchanged,
  }) =>
      EditorRegionOptions(
        start: identical(start, _unchanged) ? this.start : start as int?,
        end: identical(end, _unchanged) ? this.end : end as int?,
        color: color ?? this.color,
        borderColor: identical(borderColor, _unchanged)
            ? this.borderColor
            : borderColor as Color?,
      );

  @override
  bool operator ==(Object other) =>
      other is EditorRegionOptions &&
      start == other.start &&
      end == other.end &&
      color == other.color &&
      borderColor == other.borderColor;

  @override
  int get hashCode => Object.hashAll([
        start,
        end,
        color,
        borderColor,
      ]);
}
