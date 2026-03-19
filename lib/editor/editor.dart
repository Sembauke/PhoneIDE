import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:phone_ide/controller/custom_text_controller.dart';
import 'package:phone_ide/editor/autocomplete_data.dart';
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
  static const double _dropdownMinWidth = 220;
  static const double _dropdownMaxWidth = 360;
  static const double _dropdownMaxHeight = 240;
  static const double _dropdownEdgePadding = 8;
  static const double _dropdownVerticalGap = 6;
  static const double _dropdownItemHeight = 44;
  static const double _dropdownVerticalPadding = 12;

  ScrollController scrollController = ScrollController();
  ScrollController horizontalController = ScrollController();
  ScrollController linebarController = ScrollController();

  TextEditingControllerIDE beforeController = TextEditingControllerIDE();
  TextEditingControllerIDE inController = TextEditingControllerIDE();
  TextEditingControllerIDE afterController = TextEditingControllerIDE();
  FocusNode beforeFocusNode = FocusNode();
  FocusNode inFocusNode = FocusNode();
  FocusNode afterFocusNode = FocusNode();

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

  @override
  void initState() {
    super.initState();
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

    final double maxLeft =
        (viewportWidth - _dropdownMinWidth - _dropdownEdgePadding)
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

    final TextEditingControllerIDE controller = _controllerForRegion(position);
    final TextSelection selection = controller.selection;

    if (!selection.isValid || !selection.isCollapsed) {
      _hideAutocomplete();
      return;
    }

    AutocompleteTokenMatch? tokenMatch = extractAutocompleteToken(
      text: controller.text,
      caretOffset: selection.extentOffset,
    );

    if (tokenMatch == null &&
        selection.extentOffset > 0 &&
        selection.extentOffset <= controller.text.length &&
        controller.text[selection.extentOffset - 1] == '.') {
      final int caretOffset = selection.extentOffset;
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
      controller.text,
      selection.extentOffset,
    );

    final List<AutocompleteSuggestion> matches = matchAutocompleteSuggestions(
      token: tokenMatch.token,
      suggestions: _suggestionsForCurrentFile(),
      maxSuggestions: widget.options.maxAutocompleteSuggestions,
      contextBeforeCaret: contextBeforeCaret,
    );

    if (matches.isEmpty) {
      _hideAutocomplete();
      return;
    }

    final TextRange tokenRange = tokenMatch.range;
    setState(() {
      _activeRegion = position;
      _activeTokenRange = tokenRange;
      _activeSuggestions = matches;
      _showAutocomplete = true;
      final Offset offset = _calculateAutocompleteOffset(
        position,
        tokenRange,
        matches.length,
      );
      _autocompleteLeft = offset.dx;
      _autocompleteTop = offset.dy;
    });
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
    });
  }

  bool _shouldShowAutocomplete() {
    return widget.options.enableSimpleAutocomplete &&
        widget.options.isEditable &&
        _showAutocomplete &&
        _activeTokenRange != null &&
        _activeSuggestions.isNotEmpty;
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
      replacement: suggestion.insertText ?? suggestion.value,
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
    final double safeAvailableWidth =
        (viewportSize.width - (_dropdownEdgePadding * 2))
            .clamp(180, double.infinity)
            .toDouble();
    final double maxWidth = safeAvailableWidth
        .clamp(_dropdownMinWidth, _dropdownMaxWidth)
        .toDouble();
    final double minWidth =
        maxWidth < _dropdownMinWidth ? maxWidth : _dropdownMinWidth;

    return Positioned(
      left: _autocompleteLeft,
      top: _autocompleteTop,
      child: Material(
        elevation: 8,
        color: const Color.fromRGBO(0x1f, 0x23, 0x2d, 1),
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minWidth,
            maxWidth: maxWidth,
            maxHeight: _dropdownMaxHeight,
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            itemCount: _activeSuggestions.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              color: Color.fromRGBO(0x2f, 0x34, 0x44, 1),
            ),
            itemBuilder: (_, index) {
              final AutocompleteSuggestion suggestion =
                  _activeSuggestions[index];
              final String trailingText =
                  suggestion.detail ?? suggestion.category;
              return InkWell(
                onTapDown: (_) {
                  _isInteractingWithAutocomplete = true;
                },
                onTapCancel: () {
                  _isInteractingWithAutocomplete = false;
                  if (!beforeFocusNode.hasFocus &&
                      !inFocusNode.hasFocus &&
                      !afterFocusNode.hasFocus) {
                    _hideAutocomplete();
                  }
                },
                onTap: () => _applySuggestion(suggestion),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      if (suggestion.previewColor != null)
                        Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: suggestion.previewColor,
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 22),
                      Expanded(
                        child: Text(
                          suggestion.label,
                          style: const TextStyle(
                            color: Color.fromRGBO(0xd8, 0xe7, 0xff, 1),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        trailingText,
                        style: const TextStyle(
                          color: Color.fromRGBO(0x92, 0x9f, 0xb6, 1),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
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

  TextField editorField(
    BuildContext context,
    RegionPosition position,
  ) {
    return TextField(
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      enabled: widget.options.isEditable,
      controller: _controllerForRegion(position),
      focusNode: _focusNodeForRegion(position),
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
      onTap: () {
        _activeRegion = position;
        handleCurrentFocusedTextfieldController(position);
        _updateAutocompleteSuggestions(position);
      },
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'[“”]'),
            replacementString: '"'),
        FilteringTextInputFormatter.deny(RegExp(r'[‘’]'),
            replacementString: "'")
      ],
    );
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
