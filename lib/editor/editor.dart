import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:phone_ide/controller/custom_text_controller.dart';
import 'package:phone_ide/editor/autocomplete_data.dart';
import 'package:phone_ide/editor/autocomplete_dropdown.dart';
import 'package:phone_ide/editor/autocomplete_utils.dart';
import 'package:phone_ide/editor/editor_options.dart';
import 'package:phone_ide/editor/linebar.dart';
import 'package:phone_ide/models/textfield_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Editor extends StatefulWidget {
  Editor({
    Key? key,
    required this.options,
    required this.defaultLanguage,
    required this.defaultValue,
    required this.path,
  }) : super(key: key);

  // Stream that holds the entire editor content.
  final StreamController<String> onTextChange =
      StreamController<String>.broadcast();

  final StreamController<TextFieldData> textfieldData =
      StreamController<TextFieldData>.broadcast();

  // Stream that holds the contents of the editable region.
  final StreamController<String> editableRegion =
      StreamController<String>.broadcast();

  final EditorOptions options;

  // The starting value of the editor
  final String defaultValue;

  // The starting language of the editor
  final String defaultLanguage;

  // The path e.g. file name "index.html"
  final String path;

  @override
  State<StatefulWidget> createState() => EditorState();
}

class EditorState extends State<Editor> {
  static const double _dropdownMinWidth = 120;
  static const double _dropdownMaxWidth = 280;
  static const double _dropdownMaxHeight = 240;
  static const double _dropdownEdgePadding = 8;
  static const double _dropdownVerticalGap = 6;
  static const double _dropdownItemHeight = 40;
  static const double _dropdownVerticalPadding = 10;
  static const Duration _autocompleteCommitNewlineGuardDuration =
      Duration(milliseconds: 180);

  ScrollController scrollController = ScrollController();
  ScrollController horizontalController = ScrollController();
  ScrollController linebarController = ScrollController();

  TextEditingControllerIDE beforeController = TextEditingControllerIDE();
  TextEditingControllerIDE inController = TextEditingControllerIDE();
  TextEditingControllerIDE afterController = TextEditingControllerIDE();
  late final FocusNode beforeFocusNode;
  late final FocusNode inFocusNode;
  late final FocusNode afterFocusNode;

  late StreamSubscription<TextFieldData> _textfieldDataSub;

  int _currNumLines = 1;

  double _initialWidth = 28;

  String currentFileName = '';
  RegionPosition _activeRegion = RegionPosition.inner;
  TextRange? _activeTokenRange;
  List<AutocompleteSuggestion> _activeSuggestions = const [];
  List<AutocompleteSuggestion> _autocompleteSourceSuggestions =
      kEditorAutocompleteSuggestions;
  bool _showAutocomplete = false;
  double _autocompleteLeft = 10;
  double _autocompleteTop = 12;
  Size? _autocompleteViewportSize;
  bool _isInteractingWithAutocomplete = false;
  int _highlightedAutocompleteIndex = 0;
  String? _activeMemberObjectName;
  bool _autocompleteKeyboardFocused = false;
  bool _autocompleteSuppressedByEscape = false;
  RegionPosition? _autocompleteCommitNewlineGuardRegion;
  DateTime? _autocompleteCommitNewlineGuardUntil;
  bool _pendingFormatterAutocompleteAccept = false;

  @override
  void initState() {
    super.initState();
    _initFocusNodes();
    handleFileInit();
    _attachFocusListeners();
    _loadAutocompleteSuggestions();

    _textfieldDataSub = widget.textfieldData.stream.listen((event) {
      handleTextChange(
        event.controller.text,
        event.position,
        widget.options.regionOptions != null,
      );
    });

    scrollController.addListener(() {
      linebarController.jumpTo(scrollController.offset);
      _refreshAutocompletePosition();
    });
    horizontalController.addListener(() {
      _refreshAutocompletePosition();
    });
  }

  void _initFocusNodes() {
    beforeFocusNode = FocusNode(
      onKeyEvent: (_, KeyEvent event) =>
          _handleAutocompleteKeyEvent(event, RegionPosition.before),
    );
    inFocusNode = FocusNode(
      onKeyEvent: (_, KeyEvent event) =>
          _handleAutocompleteKeyEvent(event, RegionPosition.inner),
    );
    afterFocusNode = FocusNode(
      onKeyEvent: (_, KeyEvent event) =>
          _handleAutocompleteKeyEvent(event, RegionPosition.after),
    );
  }

  @override
  void didUpdateWidget(covariant Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.autocompleteAssetPath !=
            widget.options.autocompleteAssetPath ||
        oldWidget.options.enableSimpleAutocomplete !=
            widget.options.enableSimpleAutocomplete) {
      _loadAutocompleteSuggestions();
    }
  }

  @override
  void dispose() {
    super.dispose();
    scrollController.dispose();
    horizontalController.dispose();
    linebarController.dispose();
    beforeFocusNode.dispose();
    inFocusNode.dispose();
    afterFocusNode.dispose();
    _textfieldDataSub.cancel();
  }

  bool isLoading = false;

  void updateLineCount(String event, RegionPosition region) async {
    if (!mounted) return;
    late String lines;

    if (widget.options.regionOptions != null) {
      switch (region) {
        case RegionPosition.before:
          lines = event +
              (event.isNotEmpty ? '\n' : '') +
              inController.text +
              (afterController.text.isNotEmpty ? '\n' : '') +
              afterController.text;
          break;
        case RegionPosition.inner:
          lines = beforeController.text +
              (beforeController.text.isNotEmpty ? '\n' : '') +
              event +
              (afterController.text.isNotEmpty ? '\n' : '') +
              afterController.text;
          break;
        case RegionPosition.after:
          lines = beforeController.text +
              (beforeController.text.isNotEmpty ? '\n' : '') +
              inController.text +
              (event.isNotEmpty ? '\n' : '') +
              event;
          break;
      }
    } else {
      lines = event;
    }

    setState(() {
      _currNumLines = lines.split('\n').length;
    });
  }

  double getTextHeight(BuildContext context, {double fontSize = 18}) {
    TextScaler textScaler = MediaQuery.of(context).textScaler;

    double calculatedFontSize = textScaler.scale(fontSize);

    Size textHeight = Linebar.calculateTextSize(
      'L',
      style: TextStyle(
        color: widget.options.linebarTextColor,
        fontSize: calculatedFontSize,
        fontFamily: widget.options.fontFamily,
      ),
      context: context,
    );

    return textHeight.height;
  }

  double getFontSize(BuildContext context, {double fontSize = 18}) {
    TextScaler textScaler = MediaQuery.of(context).textScaler;

    double calculatedFontSize = textScaler.scale(fontSize);

    return calculatedFontSize;
  }

  handleFileInit() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String fileContent = widget.defaultValue;
    EditorRegionOptions? region = widget.options.regionOptions;

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      handleRegionFields();

      if (region != null) {
        int regionStart = region.start!;
        if (prefs.get(widget.path) != null) {
          regionStart = int.parse(
            prefs.getString(widget.path)?.split(':')[0] ?? '',
          );
        }

        if (fileContent.split('\n').length > 7) {
          Future.delayed(const Duration(milliseconds: 250), () {
            if (!mounted) return;
            double offset = fileContent
                    .split('\n')
                    .sublist(0, regionStart - 1 < 0 ? 0 : regionStart - 1)
                    .length *
                getTextHeight(context);
            scrollController.animateTo(
              offset,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
            );
          });
        }
      }

      if (scrollController.hasClients && linebarController.hasClients) {
        linebarController.jumpTo(0);
        scrollController.jumpTo(0);
      }
      isLoading = false;
    });

    beforeController.language = widget.defaultLanguage;
    inController.language = widget.defaultLanguage;
    afterController.language = widget.defaultLanguage;
  }

  handleRegionFields() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    EditorRegionOptions? region = widget.options.regionOptions;
    String path = widget.path;
    String fileContent = widget.defaultValue;

    if (region != null) {
      int regionStart = region.start!;
      int regionEnd = region.end!;

      if (prefs.get(path) != null) {
        regionStart = int.parse(prefs.getString(path)?.split(':')[0] ?? '');
        regionEnd = int.parse(prefs.getString(path)?.split(':')[1] ?? '');
      }

      int lines = fileContent.split('\n').length;

      if (lines >= 1) {
        String beforeEditableRegionText =
            fileContent.split('\n').sublist(0, regionStart).join('\n');

        String inEditableRegionText = fileContent
            .split('\n')
            .sublist(regionStart, regionEnd - 1)
            .join('\n');

        String afterEditableRegionText = fileContent
            .split('\n')
            .sublist(regionEnd - 1, fileContent.split('\n').length)
            .join('\n');
        beforeController.text = beforeEditableRegionText;
        inController.text = inEditableRegionText;
        afterController.text = afterEditableRegionText;
      }
    } else {
      beforeController.text = '';
      inController.text = fileContent;
      afterController.text = '';
    }

    updateLineCount(inController.text, RegionPosition.inner);
  }

  handleRegionCaching(String event, RegionPosition region) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    late int beforeRegionLines;
    late int inRegionLines;
    late int newRegionlines;

    if (region == RegionPosition.before) {
      beforeRegionLines = event.split('\n').length;
      inRegionLines = inController.text.split('\n').length + 1;
      newRegionlines = inRegionLines + beforeRegionLines;
    } else if (region == RegionPosition.inner) {
      beforeRegionLines = beforeController.text.split('\n').length;
      inRegionLines = event.split('\n').length + 1;
      newRegionlines = inRegionLines + beforeRegionLines;
    }

    prefs.setString(
      widget.path,
      '$beforeRegionLines:$newRegionlines',
    );
  }

  handleTextChange(String event, RegionPosition region, bool hasRegion) {
    if (!mounted) return;
    updateLineCount(event, region);

    late String text;

    switch (region) {
      case RegionPosition.before:
        text = '$event\n${inController.text}\n${afterController.text}';
        break;
      case RegionPosition.inner:
        if (hasRegion) {
          text = '${beforeController.text}\n$event\n${afterController.text}';
        } else {
          text = event;
        }
        widget.editableRegion.sink.add(event);
        break;
      case RegionPosition.after:
        text = '${beforeController.text}\n${inController.text}\n$event';
        break;
    }

    widget.onTextChange.sink.add(text);
  }

  handleCurrentFocusedTextfieldController(RegionPosition position) {
    if (!mounted) return;

    if (position == RegionPosition.before) {
      widget.textfieldData.sink.add(
        TextFieldData(
          controller: beforeController,
          position: RegionPosition.before,
        ),
      );
    } else if (position == RegionPosition.inner) {
      widget.textfieldData.sink.add(
        TextFieldData(
          controller: inController,
          position: RegionPosition.inner,
        ),
      );
    } else if (position == RegionPosition.after) {
      widget.textfieldData.sink.add(
        TextFieldData(
          controller: afterController,
          position: RegionPosition.after,
        ),
      );
    }
  }

  void _attachFocusListeners() {
    beforeFocusNode.addListener(() {
      _handleFocusChange(RegionPosition.before, beforeFocusNode);
    });
    inFocusNode.addListener(() {
      _handleFocusChange(RegionPosition.inner, inFocusNode);
    });
    afterFocusNode.addListener(() {
      _handleFocusChange(RegionPosition.after, afterFocusNode);
    });
  }

  void _handleFocusChange(RegionPosition position, FocusNode focusNode) {
    if (!mounted || !widget.options.enableSimpleAutocomplete) {
      return;
    }

    if (focusNode.hasFocus) {
      _activeRegion = position;
      _updateAutocompleteSuggestions(position);
      return;
    }

    if (!beforeFocusNode.hasFocus &&
        !inFocusNode.hasFocus &&
        !afterFocusNode.hasFocus) {
      if (_isInteractingWithAutocomplete) {
        return;
      }
      _hideAutocomplete();
    }
  }

  TextEditingControllerIDE _controllerForRegion(RegionPosition position) {
    switch (position) {
      case RegionPosition.before:
        return beforeController;
      case RegionPosition.inner:
        return inController;
      case RegionPosition.after:
        return afterController;
    }
  }

  FocusNode _focusNodeForRegion(RegionPosition position) {
    switch (position) {
      case RegionPosition.before:
        return beforeFocusNode;
      case RegionPosition.inner:
        return inFocusNode;
      case RegionPosition.after:
        return afterFocusNode;
    }
  }

  void _handleEditorChanged(
    String event,
    RegionPosition position, {
    bool refreshAutocomplete = true,
  }) {
    if (widget.options.regionOptions != null &&
        position != RegionPosition.after) {
      handleRegionCaching(event, position);
    }

    handleTextChange(event, position, widget.options.regionOptions != null);
    _activeRegion = position;
    if (refreshAutocomplete) {
      _updateAutocompleteSuggestions(position);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        if (_focusNodeForRegion(position).hasFocus) {
          _updateAutocompleteSuggestions(position);
        }
      });
    }
  }

  TextStyle _editorTextStyle(BuildContext context) {
    return TextStyle(
      fontSize: getFontSize(context, fontSize: 18),
      fontFamily: widget.options.fontFamily,
      color: Colors.white.withValues(alpha: 0.87),
    );
  }

  int _countLines(String text) {
    if (text.isEmpty) {
      return 0;
    }

    return '\n'.allMatches(text).length + 1;
  }

  int _lineOffsetForRegion(RegionPosition position) {
    if (position == RegionPosition.before) {
      return 0;
    }

    if (position == RegionPosition.inner) {
      return _countLines(beforeController.text);
    }

    return _countLines(beforeController.text) + _countLines(inController.text);
  }

  Future<void> _loadAutocompleteSuggestions() async {
    if (!widget.options.enableSimpleAutocomplete) {
      return;
    }

    final List<AutocompleteSuggestion> loadedSuggestions =
        await loadAutocompleteSuggestionsFromAsset(
      assetPath: widget.options.autocompleteAssetPath,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _autocompleteSourceSuggestions = loadedSuggestions;
    });

    if (_showAutocomplete) {
      _updateAutocompleteSuggestions(_activeRegion);
    }
  }

  List<AutocompleteSuggestion> _suggestionsForCurrentFile() {
    final AutocompleteLanguage language = resolveAutocompleteLanguage(
      defaultLanguage: widget.defaultLanguage,
      path: widget.path,
    );

    return filterSuggestionsByLanguage(
      suggestions: _autocompleteSourceSuggestions,
      language: language,
    );
  }

  Size _editorViewportSize() {
    final Size? viewportSize = _autocompleteViewportSize;
    if (viewportSize != null &&
        viewportSize.width > 0 &&
        viewportSize.height > 0) {
      return viewportSize;
    }

    final Size mediaQuerySize = MediaQuery.of(context).size;
    final double width =
        mediaQuerySize.width - (widget.options.showLinebar ? _initialWidth : 0);
    return Size(width, mediaQuerySize.height);
  }

  double _estimatedDropdownHeight(int suggestionCount) {
    if (suggestionCount <= 0) {
      return _dropdownItemHeight;
    }

    final int separatorCount = suggestionCount > 0 ? suggestionCount - 1 : 0;
    final double estimatedHeight = _dropdownVerticalPadding +
        (suggestionCount * _dropdownItemHeight) +
        separatorCount;
    return estimatedHeight.clamp(_dropdownItemHeight, _dropdownMaxHeight);
  }

  String? _memberObjectNameFromContext(String contextBeforeCaret) {
    if (contextBeforeCaret.isEmpty) {
      return null;
    }

    final RegExp trailingMemberPattern =
        RegExp(r'([A-Za-z_$][A-Za-z0-9_$]*)\.([A-Za-z0-9_#$-]*)$');
    final RegExpMatch? match =
        trailingMemberPattern.firstMatch(contextBeforeCaret);
    if (match == null) {
      return null;
    }

    final String? objectName = match.group(1);
    if (objectName == null || objectName.isEmpty) {
      return null;
    }

    return objectName;
  }

  double _measureSingleLineTextWidth(String text, TextStyle style) {
    if (text.isEmpty) {
      return 0;
    }

    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout();

    return textPainter.width;
  }

  double _estimatedDropdownWidth(Size viewportSize) {
    const TextStyle labelStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
    );

    double maxRowWidth = 0;
    for (final AutocompleteSuggestion suggestion in _activeSuggestions) {
      final String displayLabel = _displayLabelForSuggestion(suggestion);
      final double labelWidth =
          _measureSingleLineTextWidth(displayLabel, labelStyle);
      final double rowWidth = 20 + // row horizontal padding
          20 + // icon slot + spacing
          labelWidth +
          8; // right breathing room
      if (rowWidth > maxRowWidth) {
        maxRowWidth = rowWidth;
      }
    }

    final double contentEstimate = maxRowWidth + 4; // borders/safe slop
    final double viewportCap = (viewportSize.width - (_dropdownEdgePadding * 2))
        .clamp(120.0, _dropdownMaxWidth)
        .toDouble();
    final double maxAllowed =
        (viewportSize.width * 0.76).clamp(140.0, viewportCap).toDouble();
    final double minAllowed =
        _dropdownMinWidth > maxAllowed ? maxAllowed : _dropdownMinWidth;

    return contentEstimate.clamp(minAllowed, maxAllowed).toDouble();
  }

  String _displayLabelForSuggestion(AutocompleteSuggestion suggestion) {
    final String? objectName = _activeMemberObjectName;
    if (objectName == null || objectName.isEmpty) {
      return suggestion.label;
    }

    final String objectPrefix = '$objectName.';
    final String normalizedPrefix = objectPrefix.toLowerCase();
    final String label = suggestion.label;
    final String normalizedLabel = label.toLowerCase();
    if (!normalizedLabel.startsWith(normalizedPrefix)) {
      return label;
    }

    final String tail = label.substring(objectPrefix.length);
    String insertion = suggestion.insertText ?? suggestion.value;
    final String normalizedInsertion = insertion.toLowerCase();
    if (normalizedInsertion.startsWith(normalizedPrefix) &&
        insertion.length > objectPrefix.length) {
      insertion = insertion.substring(objectPrefix.length);
    }

    if (insertion.startsWith(tail)) {
      return '.$insertion';
    }

    return '.$tail';
  }

  String _replacementTextForSuggestion(AutocompleteSuggestion suggestion) {
    String replacement = suggestion.insertText ?? suggestion.value;
    final String? objectName = _activeMemberObjectName;
    if (objectName == null || objectName.isEmpty) {
      return replacement;
    }

    final String objectPrefix = '$objectName.';
    final String normalizedReplacement = replacement.toLowerCase();
    final String normalizedPrefix = objectPrefix.toLowerCase();
    if (normalizedReplacement.startsWith(normalizedPrefix) &&
        replacement.length > objectPrefix.length) {
      return replacement.substring(objectPrefix.length);
    }

    return replacement;
  }

  double _estimatedEditorLineHeight() {
    final double glyphHeight = getTextHeight(context);
    final double fontSize = getFontSize(context, fontSize: 18);
    final double paddedHeight = fontSize + 12;
    return paddedHeight > glyphHeight ? paddedHeight : glyphHeight;
  }

  bool _hasNonEmptyLineAt(List<String> lines, int index) {
    if (index < 0 || index >= lines.length) {
      return false;
    }

    return lines[index].trim().isNotEmpty;
  }

  Offset _calculateAutocompleteOffset(
    RegionPosition position,
    TextRange tokenRange,
    int suggestionCount,
  ) {
    final TextEditingControllerIDE controller = _controllerForRegion(position);
    final String controllerText = controller.text;
    final int safeTokenStart = tokenRange.start.clamp(0, controllerText.length);
    final int lineStartIndex = safeTokenStart <= 0
        ? 0
        : controllerText.lastIndexOf('\n', safeTokenStart - 1) + 1;
    final String currentLinePrefix =
        controllerText.substring(lineStartIndex, safeTokenStart);
    final int localLineIndex =
        '\n'.allMatches(controllerText.substring(0, safeTokenStart)).length;
    final int globalLineIndex = _lineOffsetForRegion(position) + localLineIndex;
    final List<String> lines = controllerText.split('\n');
    final bool hasNonEmptyLineAbove =
        _hasNonEmptyLineAt(lines, localLineIndex - 1);
    final bool hasNonEmptyLineBelow =
        _hasNonEmptyLineAt(lines, localLineIndex + 1);

    final double linePrefixWidth = Linebar.calculateTextSize(
      currentLinePrefix,
      style: _editorTextStyle(context),
      context: context,
    ).width;

    double left = 10 + linePrefixWidth - horizontalController.offset;
    final double lineHeight = _estimatedEditorLineHeight();
    final double lineTop =
        (globalLineIndex * lineHeight) - scrollController.offset;
    final double lineBottom = lineTop + lineHeight;

    final Size viewportSize = _editorViewportSize();
    final double viewportWidth = viewportSize.width;
    final double viewportHeight = viewportSize.height;
    final double dropdownHeight = _estimatedDropdownHeight(suggestionCount);
    final double dropdownWidth = _estimatedDropdownWidth(viewportSize);

    final double maxLeft =
        (viewportWidth - dropdownWidth - _dropdownEdgePadding)
            .clamp(_dropdownEdgePadding, double.infinity)
            .toDouble();
    left = left.clamp(_dropdownEdgePadding, maxLeft).toDouble();

    final double spaceBelow =
        viewportHeight - lineBottom - _dropdownEdgePadding;
    final double spaceAbove = lineTop - _dropdownEdgePadding;
    final bool canPlaceBelow = spaceBelow >= dropdownHeight;
    final bool canPlaceAbove = spaceAbove >= dropdownHeight;

    late double top;
    if (canPlaceBelow && canPlaceAbove) {
      if (hasNonEmptyLineBelow && !hasNonEmptyLineAbove) {
        top = lineTop - dropdownHeight - _dropdownVerticalGap;
      } else {
        top = lineBottom + _dropdownVerticalGap;
      }
    } else if (canPlaceBelow) {
      top = lineBottom + _dropdownVerticalGap;
    } else if (canPlaceAbove) {
      top = lineTop - dropdownHeight - _dropdownVerticalGap;
    } else {
      top = spaceBelow >= spaceAbove
          ? viewportHeight - dropdownHeight - _dropdownEdgePadding
          : _dropdownEdgePadding;
    }

    final double maxTop =
        (viewportHeight - dropdownHeight - _dropdownEdgePadding)
            .clamp(_dropdownEdgePadding, double.infinity)
            .toDouble();
    top = top.clamp(_dropdownEdgePadding, maxTop).toDouble();

    return Offset(left, top);
  }

  void _refreshAutocompletePosition() {
    if (!_shouldShowAutocomplete()) {
      return;
    }

    final TextRange? tokenRange = _activeTokenRange;
    if (tokenRange == null) {
      return;
    }

    final Offset offset = _calculateAutocompleteOffset(
        _activeRegion, tokenRange, _activeSuggestions.length);
    if ((_autocompleteLeft - offset.dx).abs() < 0.1 &&
        (_autocompleteTop - offset.dy).abs() < 0.1) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _autocompleteLeft = offset.dx;
      _autocompleteTop = offset.dy;
    });
  }

  void _updateAutocompleteSuggestions(RegionPosition position) {
    if (!mounted ||
        !widget.options.enableSimpleAutocomplete ||
        !widget.options.isEditable) {
      _hideAutocomplete();
      return;
    }

    if (_autocompleteSuppressedByEscape) {
      _hideAutocomplete();
      return;
    }

    final TextEditingControllerIDE controller = _controllerForRegion(position);
    final TextSelection selection = controller.selection;
    final String text = controller.text;

    final bool hasExplicitRangeSelection = selection.isValid &&
        !selection.isCollapsed &&
        selection.start >= 0 &&
        selection.end >= 0;
    if (hasExplicitRangeSelection) {
      _hideAutocomplete();
      return;
    }

    final int caretOffset = _safeCaretOffset(selection, text);
    AutocompleteTokenMatch? tokenMatch = extractAutocompleteToken(
      text: text,
      caretOffset: caretOffset,
    );

    if (tokenMatch == null &&
        caretOffset > 0 &&
        caretOffset <= text.length &&
        text[caretOffset - 1] == '.') {
      tokenMatch = AutocompleteTokenMatch(
        token: '',
        range: TextRange(start: caretOffset, end: caretOffset),
      );
    }

    if (tokenMatch == null) {
      _hideAutocomplete();
      return;
    }

    final String contextBeforeCaret = _contextWindowBeforeCaret(
      text,
      caretOffset,
    );

    final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
      token: tokenMatch.token,
      suggestions: _suggestionsForCurrentFile(),
      maxSuggestions: widget.options.maxAutocompleteSuggestions < 1
          ? 1
          : widget.options.maxAutocompleteSuggestions,
      contextBeforeCaret: contextBeforeCaret,
    );

    if (matches.isEmpty) {
      _hideAutocomplete();
      return;
    }

    final TextRange tokenRange = tokenMatch.range;
    final String? memberObjectName =
        _memberObjectNameFromContext(contextBeforeCaret);
    setState(() {
      _activeRegion = position;
      _activeTokenRange = tokenRange;
      _activeSuggestions = matches;
      _showAutocomplete = true;
      _highlightedAutocompleteIndex = 0;
      _activeMemberObjectName = memberObjectName;
      _autocompleteKeyboardFocused = false;
      final Offset offset = _calculateAutocompleteOffset(
        position,
        tokenRange,
        matches.length,
      );
      _autocompleteLeft = offset.dx;
      _autocompleteTop = offset.dy;
    });
  }

  int _safeCaretOffset(TextSelection selection, String text) {
    final int length = text.length;

    final int extentOffset = selection.extentOffset;
    if (extentOffset >= 0 && extentOffset <= length) {
      return extentOffset;
    }

    final int baseOffset = selection.baseOffset;
    if (baseOffset >= 0 && baseOffset <= length) {
      return baseOffset;
    }

    return length;
  }

  String _contextWindowBeforeCaret(String text, int caretOffset) {
    final int safeOffset = caretOffset.clamp(0, text.length);
    final int lineStartIndex =
        safeOffset <= 0 ? 0 : text.lastIndexOf('\n', safeOffset - 1) + 1;
    final int hardWindowStart = safeOffset > 180 ? safeOffset - 180 : 0;
    final int start =
        hardWindowStart > lineStartIndex ? hardWindowStart : lineStartIndex;
    return text.substring(start, safeOffset);
  }

  void _hideAutocomplete() {
    if (!_showAutocomplete && _activeSuggestions.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _activeTokenRange = null;
      _activeSuggestions = const [];
      _showAutocomplete = false;
      _highlightedAutocompleteIndex = 0;
      _activeMemberObjectName = null;
      _autocompleteKeyboardFocused = false;
    });
  }

  bool _shouldShowAutocomplete() {
    return widget.options.enableSimpleAutocomplete &&
        widget.options.isEditable &&
        _showAutocomplete &&
        _activeTokenRange != null &&
        _activeSuggestions.isNotEmpty;
  }

  KeyEventResult _handleAutocompleteKeyEvent(
    KeyEvent event,
    RegionPosition position,
  ) {
    final bool isDownOrRepeat =
        event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isDownOrRepeat) {
      return KeyEventResult.ignored;
    }

    final LogicalKeyboardKey key = event.logicalKey;
    final bool isEscapeKey = _isEscapeDismissKey(key);
    if (_autocompleteSuppressedByEscape) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space) {
        setState(() {
          _autocompleteSuppressedByEscape = false;
        });
        return KeyEventResult.ignored;
      }

      if (isEscapeKey) {
        return KeyEventResult.handled;
      }
    }

    if (isEscapeKey && _shouldShowAutocomplete() && position == _activeRegion) {
      _dismissAutocompleteFromKeyboard();
      return KeyEventResult.handled;
    }

    if (!_shouldShowAutocomplete() || position != _activeRegion) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.tab) {
      _focusAutocompleteFromKeyboard();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveAutocompleteSelection(1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _moveAutocompleteSelection(-1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _armAutocompleteCommitNewlineGuard(position);
      _acceptAutocompleteSelection();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _isEscapeDismissKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.navigatePrevious ||
        key == LogicalKeyboardKey.exit;
  }

  void _dismissAutocompleteFromKeyboard() {
    if (!_shouldShowAutocomplete()) {
      return;
    }
    setState(() {
      _autocompleteSuppressedByEscape = true;
    });
    _hideAutocomplete();
  }

  void _armAutocompleteCommitNewlineGuard(RegionPosition position) {
    _autocompleteCommitNewlineGuardRegion = position;
    _autocompleteCommitNewlineGuardUntil =
        DateTime.now().add(_autocompleteCommitNewlineGuardDuration);
  }

  bool _consumeAutocompleteCommitNewlineGuardIfActive(RegionPosition position) {
    if (_autocompleteCommitNewlineGuardRegion != position) {
      return false;
    }

    final DateTime? until = _autocompleteCommitNewlineGuardUntil;
    if (until == null || DateTime.now().isAfter(until)) {
      _clearAutocompleteCommitNewlineGuard(position);
      return false;
    }

    _clearAutocompleteCommitNewlineGuard(position);
    return true;
  }

  void _clearAutocompleteCommitNewlineGuard(RegionPosition position) {
    if (_autocompleteCommitNewlineGuardRegion != position) {
      return;
    }
    _autocompleteCommitNewlineGuardRegion = null;
    _autocompleteCommitNewlineGuardUntil = null;
  }

  bool _shouldBlockAutocompleteNewline(RegionPosition position) {
    if (_shouldShowAutocomplete() && _activeRegion == position) {
      return true;
    }

    return _consumeAutocompleteCommitNewlineGuardIfActive(position);
  }

  void _handleBlockedAutocompleteNewline(RegionPosition position) {
    if (!_shouldShowAutocomplete() || _activeRegion != position) {
      return;
    }

    if (_pendingFormatterAutocompleteAccept) {
      return;
    }

    _pendingFormatterAutocompleteAccept = true;
    _armAutocompleteCommitNewlineGuard(position);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendingFormatterAutocompleteAccept = false;
      if (!mounted) {
        return;
      }

      if (!_shouldShowAutocomplete() || _activeRegion != position) {
        return;
      }

      _acceptAutocompleteSelection();
    });
  }

  void _focusAutocompleteFromKeyboard() {
    if (!_shouldShowAutocomplete()) {
      return;
    }
    setState(() {
      _autocompleteKeyboardFocused = true;
    });
  }

  void _moveAutocompleteSelection(int delta) {
    if (!_shouldShowAutocomplete()) {
      return;
    }
    final int suggestionCount = _activeSuggestions.length;
    if (suggestionCount <= 0) {
      return;
    }
    setState(() {
      _autocompleteKeyboardFocused = true;
      _highlightedAutocompleteIndex =
          (_highlightedAutocompleteIndex + delta + suggestionCount) %
              suggestionCount;
    });
  }

  void _acceptAutocompleteSelection() {
    if (!_shouldShowAutocomplete()) {
      return;
    }
    final int suggestionCount = _activeSuggestions.length;
    if (suggestionCount <= 0) {
      return;
    }
    final int safeIndex = _highlightedAutocompleteIndex.clamp(
      0,
      suggestionCount - 1,
    );
    _applySuggestion(_activeSuggestions[safeIndex]);
  }

  void _applySuggestion(AutocompleteSuggestion suggestion) {
    _isInteractingWithAutocomplete = false;

    if (!_shouldShowAutocomplete()) {
      return;
    }

    final TextRange? tokenRange = _activeTokenRange;
    if (tokenRange == null) {
      return;
    }

    final TextEditingControllerIDE controller =
        _controllerForRegion(_activeRegion);
    final TextEditingValue updatedValue = applyAutocompleteSuggestion(
      originalValue: controller.value,
      replaceRange: tokenRange,
      replacement: _replacementTextForSuggestion(suggestion),
    );

    controller.value = updatedValue;
    _hideAutocomplete();
    _handleEditorChanged(
      controller.text,
      _activeRegion,
      refreshAutocomplete: false,
    );
    _focusNodeForRegion(_activeRegion).requestFocus();
  }

  Widget _autocompleteDropdown() {
    final Size viewportSize = _editorViewportSize();
    final double targetWidth = _estimatedDropdownWidth(viewportSize);

    return AutocompleteDropdown(
      left: _autocompleteLeft,
      top: _autocompleteTop,
      width: targetWidth,
      maxHeight: _dropdownMaxHeight,
      itemHeight: _dropdownItemHeight,
      suggestions: _activeSuggestions,
      highlightedIndex: _highlightedAutocompleteIndex,
      showKeyboardFocusBorder: _autocompleteKeyboardFocused,
      displayLabelBuilder: _displayLabelForSuggestion,
      onSuggestionTap: _applySuggestion,
      onSuggestionTapDown: (int index) {
        setState(() {
          _highlightedAutocompleteIndex = index;
        });
        _isInteractingWithAutocomplete = true;
      },
      onSuggestionTapCancel: () {
        _isInteractingWithAutocomplete = false;
        if (!beforeFocusNode.hasFocus &&
            !inFocusNode.hasFocus &&
            !afterFocusNode.hasFocus) {
          _hideAutocomplete();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        if (isLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final mediaQueryData = MediaQuery.of(context);

        return MediaQuery(
          data: mediaQueryData.copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: TapRegion(
            onTapOutside: (_) {
              _hideAutocomplete();
            },
            child: Row(
              children: [
                if (widget.options.showLinebar)
                  Container(
                    constraints: BoxConstraints(
                      minWidth: 1,
                      maxWidth: _initialWidth,
                    ),
                    decoration: BoxDecoration(
                      color: widget.options.linebarColor,
                      border: const Border(
                        right: BorderSide(
                          color: Color.fromRGBO(0x88, 0x88, 0x88, 1),
                        ),
                      ),
                    ),
                    child: linecountBar(),
                  ),
                Expanded(
                  child: Container(
                    color: widget.options.backgroundColor,
                    child: MediaQuery(
                      data: const MediaQueryData(
                        gestureSettings: DeviceGestureSettings(touchSlop: 8.0),
                      ),
                      child: editorView(context),
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget editorView(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: horizontalController,
      child: Container(
        width: !widget.options.isEditable
            ? MediaQuery.of(context).size.width + 600
            : 5000,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double fallbackHeight = MediaQuery.of(context).size.height;
            final double maxHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : fallbackHeight;
            _autocompleteViewportSize = Size(constraints.maxWidth, maxHeight);

            return Stack(
              children: [
                ListView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  shrinkWrap: !widget.options.takeFullHeight,
                  children: [
                    if (widget.options.regionOptions != null &&
                        beforeController.text.isNotEmpty)
                      editorField(context, RegionPosition.before),
                    editorField(context, RegionPosition.inner),
                    if (widget.options.regionOptions != null &&
                        afterController.text.isNotEmpty)
                      editorField(context, RegionPosition.after),
                  ],
                ),
                if (_shouldShowAutocomplete()) _autocompleteDropdown(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget editorField(
    BuildContext context,
    RegionPosition position,
  ) {
    final TextField textField = TextField(
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      enabled: widget.options.isEditable,
      controller: _controllerForRegion(position),
      focusNode: _focusNodeForRegion(position),
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        border: InputBorder.none,
        filled: true,
        fillColor: widget.options.regionOptions != null &&
                position == RegionPosition.inner
            ? widget.options.regionOptions!.color
            : widget.options.backgroundColor,
        contentPadding: const EdgeInsets.only(
          left: 10,
        ),
        isDense: true,
      ),
      maxLines: null,
      style: TextStyle(
        fontSize: getFontSize(context, fontSize: 18),
        fontFamily: widget.options.fontFamily,
        color: Colors.white.withValues(alpha: 0.87),
      ),
      onChanged: (String event) => _handleEditorChanged(event, position),
      onSubmitted: (_) {
        if (!_shouldShowAutocomplete() || _activeRegion != position) {
          return;
        }
        _armAutocompleteCommitNewlineGuard(position);
        _acceptAutocompleteSelection();
      },
      onTap: () {
        _activeRegion = position;
        handleCurrentFocusedTextfieldController(position);
        _updateAutocompleteSuggestions(position);
      },
      inputFormatters: [
        _AutocompleteNewlineBlockFormatter(
          shouldBlock: () => _shouldBlockAutocompleteNewline(position),
          onBlocked: () => _handleBlockedAutocompleteNewline(position),
        ),
        FilteringTextInputFormatter.deny(RegExp(r'[“”]'),
            replacementString: '"'),
        FilteringTextInputFormatter.deny(RegExp(r'[‘’]'),
            replacementString: "'")
      ],
    );
    return textField;
  }

  linecountBar() {
    return Column(
      mainAxisSize:
          widget.options.takeFullHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            controller: linebarController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _currNumLines == 0 ? 1 : _currNumLines,
            itemBuilder: (_, i) {
              TextEditingController lineController = TextEditingController();
              lineController.text = (i + 1).toString();
              return Linebar(
                calculateBarWidth: () {
                  if (i + 1 > 9) {
                    SchedulerBinding.instance.addPostFrameCallback(
                      (timeStamp) {
                        if (!mounted) return;
                        setState(() {
                          _initialWidth = getTextHeight(context) +
                              (8 * (i + 1).toString().length);
                        });
                      },
                    );
                  }
                },
                child: TextField(
                  readOnly: true,
                  enableInteractiveSelection: false,
                  controller: lineController,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: getFontSize(context, fontSize: 18),
                    fontWeight: FontWeight.w500,
                    fontFamily: widget.options.fontFamily,
                    color: widget.options.linebarTextColor,
                  ),
                  maxLines: null,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              );
            },
          ),
        )
      ],
    );
  }
}

class _AutocompleteNewlineBlockFormatter extends TextInputFormatter {
  _AutocompleteNewlineBlockFormatter({
    required this.shouldBlock,
    this.onBlocked,
  });

  final bool Function() shouldBlock;
  final VoidCallback? onBlocked;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!shouldBlock()) {
      return newValue;
    }

    final RegExp lineBreakPattern = RegExp(r'[\r\n]');
    final int oldBreakCount = lineBreakPattern.allMatches(oldValue.text).length;
    final int newBreakCount = lineBreakPattern.allMatches(newValue.text).length;

    if (newBreakCount > oldBreakCount) {
      onBlocked?.call();
      return oldValue;
    }

    return newValue;
  }
}
