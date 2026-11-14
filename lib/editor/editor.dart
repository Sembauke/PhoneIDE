import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_ide/controller/custom_text_controller.dart';
import 'package:phone_ide/editor/editor_options.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/models/textfield_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'editor_document.dart';
part 'editor_layout.dart';

class Editor extends StatefulWidget {
  Editor({
    super.key,
    required this.options,
    required this.defaultLanguage,
    required this.defaultValue,
    required this.path,
  });

  final StreamController<String> onTextChange =
      StreamController<String>.broadcast();
  final StreamController<TextFieldData> textfieldData =
      StreamController<TextFieldData>.broadcast();
  final StreamController<String> editableRegion =
      StreamController<String>.broadcast();
  final EditorOptions options;
  final String defaultValue;
  final String defaultLanguage;
  final String path;

  @override
  EditorState createState() => EditorState();
}

class EditorState extends State<Editor> {
  final ScrollController scrollController = ScrollController();
  final ScrollController horizontalController = ScrollController();
  final ScrollController linebarController = ScrollController();
  final TextEditingControllerIDE beforeController = TextEditingControllerIDE();
  final TextEditingControllerIDE inController = TextEditingControllerIDE();
  final TextEditingControllerIDE afterController = TextEditingControllerIDE();
  final _focusNodes = {
    for (final position in RegionPosition.values) position: FocusNode()
  };
  late StreamSubscription<TextFieldData> _textfieldDataSub;
  bool isLoading = true;
  bool _hasBefore = false;
  bool _hasAfter = false;
  bool _emptyInner = false;
  int _initialization = 0;
  RegionPosition _activePosition = RegionPosition.inner;
  String _lastText = '';
  final _activeLine = ValueNotifier<int?>(null);
  final _widthCache = _ContentWidthCache();
  final _values = <RegionPosition, TextEditingValue>{
    for (final position in RegionPosition.values)
      position: TextEditingValue.empty,
  };
  final _controllerListeners = <RegionPosition, VoidCallback>{};
  _EditorDocument? _document;
  bool _restoringValue = false;

  TextEditingControllerIDE _controller(RegionPosition position) =>
      switch (position) {
        RegionPosition.before => beforeController,
        RegionPosition.inner => inController,
        RegionPosition.after => afterController,
      };

  List<RegionPosition> get _positions => [
        if (_hasBefore) RegionPosition.before,
        RegionPosition.inner,
        if (_hasAfter) RegionPosition.after,
      ];

  _EditorDocument get _currentDocument => _document ??= _EditorDocument(
        {
          for (final position in _positions)
            position: _controller(position).text
        },
        emptyInner: _emptyInner,
      );
  String get _sourceText => _currentDocument.sourceText;
  int _lineCount(RegionPosition position) =>
      _currentDocument.region(position).lineCount;
  int _firstLine(RegionPosition position) =>
      _currentDocument.region(position).firstLine;

  @override
  void initState() {
    super.initState();
    _bindStream();
    for (final position in RegionPosition.values) {
      void listener() => _controllerChanged(position);
      _controllerListeners[position] = listener;
      _controller(position).addListener(listener);
      _focusNodes[position]!.addListener(() {
        if (_focusNodes[position]!.hasFocus) {
          _activePosition = position;
          _updateActiveLine();
          handleCurrentFocusedTextfieldController(position);
        }
      });
    }
    scrollController.addListener(_syncGutter);
    _initializeEditor();
  }

  void _bindStream() {
    _textfieldDataSub = widget.textfieldData.stream.listen((event) {
      if (!mounted || _controller(event.position) != event.controller) return;
      handleTextChange(event.controller.text, event.position,
          widget.options.regionOptions != null);
    });
  }

  @override
  void didUpdateWidget(Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textfieldData != oldWidget.textfieldData) {
      unawaited(_textfieldDataSub.cancel());
      _bindStream();
    }
    if (widget.path != oldWidget.path ||
        widget.defaultValue != oldWidget.defaultValue ||
        widget.options.regionOptions?.start !=
            oldWidget.options.regionOptions?.start ||
        widget.options.regionOptions?.end !=
            oldWidget.options.regionOptions?.end) {
      isLoading = true;
      _initializeEditor();
    }
    _applySyntaxTheme();
  }

  void _applySyntaxTheme() {
    for (final position in RegionPosition.values) {
      _controller(position)
        ..language = widget.defaultLanguage
        ..syntaxTheme = widget.options.syntaxTheme;
    }
  }

  void _controllerChanged(RegionPosition position) {
    if (!mounted || _restoringValue) return;
    final controller = _controller(position);
    final previous = _values[position]!;
    final textChanged = previous.text != controller.text;
    if (textChanged && !isLoading && !widget.options.isEditable) {
      // Host toolbar insertions use the same controllers as keyboard input.
      _restoringValue = true;
      controller.value = previous;
      _restoringValue = false;
      return;
    }
    _values[position] = controller.value;
    if (isLoading) return;
    if (textChanged) {
      if (_emptyInner && inController.text.isNotEmpty) _emptyInner = false;
      _document = null;
      setState(() {});
    }
    _updateActiveLine();
  }

  void _updateActiveLine() {
    if (isLoading) return;
    final controller = _controller(_activePosition);
    _activeLine.value = controller.selection.isValid
        ? _currentDocument.region(_activePosition).lineAtOffset(
            controller.selection.extentOffset.clamp(0, controller.text.length))
        : null;
  }

  void _syncGutter() {
    if (scrollController.hasClients && linebarController.hasClients) {
      linebarController.jumpTo(scrollController.offset
          .clamp(0.0, linebarController.position.maxScrollExtent));
    }
  }

  @override
  void dispose() {
    unawaited(_textfieldDataSub.cancel());
    for (final position in RegionPosition.values) {
      _controller(position).removeListener(_controllerListeners[position]!);
      _controller(position).dispose();
      _focusNodes[position]!.dispose();
    }
    _activeLine.dispose();
    scrollController.dispose();
    horizontalController.dispose();
    linebarController.dispose();
    super.dispose();
  }

  Future<SharedPreferences?> _getPreferencesSafe() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('phone_ide: SharedPreferences unavailable: $error');
      return null;
    }
  }

  Future<void> _initializeEditor() async {
    final generation = ++_initialization;
    await TextMateHighlighterRegistry.instance.initialize();
    final prefs = await _getPreferencesSafe();
    if (!mounted || generation != _initialization) return;
    final lines = widget.defaultValue.split('\n');
    final region = widget.options.regionOptions;
    if (region == null) {
      _hasBefore = _hasAfter = _emptyInner = false;
      beforeController.clear();
      afterController.clear();
      inController.text = widget.defaultValue;
    } else {
      final cached = prefs?.getString(widget.path)?.split(':');
      final start = (cached != null && cached.length == 2
              ? int.tryParse(cached[0])
              : null) ??
          region.start ??
          0;
      final end = (cached != null && cached.length == 2
              ? int.tryParse(cached[1])
              : null) ??
          region.end ??
          lines.length + 1;
      final from = start.clamp(0, lines.length);
      final to = (end - 1).clamp(from, lines.length);
      _emptyInner = to == from;
      _hasBefore = from > 0;
      _hasAfter = to < lines.length;
      beforeController.text = lines.take(from).join('\n');
      inController.text = lines.sublist(from, to).join('\n');
      afterController.text = lines.skip(to).join('\n');
    }
    _document = null;
    _activePosition = RegionPosition.inner;
    _lastText = _sourceText;
    _applySyntaxTheme();
    setState(() => isLoading = false);
    _updateActiveLine();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _initialization) return;
      if (scrollController.hasClients) {
        final target =
            (_firstLine(RegionPosition.inner) - 1) * getTextHeight(context);
        scrollController.jumpTo(
            target.clamp(0.0, scrollController.position.maxScrollExtent));
      }
      if (horizontalController.hasClients) horizontalController.jumpTo(0);
    });
  }

  Future<void> handleRegionCaching(String event, RegionPosition region) async {
    final path = widget.path;
    final before = _hasBefore ? _lineCount(RegionPosition.before) : 0;
    final end =
        before + (_emptyInner ? 0 : _lineCount(RegionPosition.inner)) + 1;
    final prefs = await _getPreferencesSafe();
    await prefs?.setString(path, '$before:$end');
  }

  void handleTextChange(String event, RegionPosition region, bool hasRegion) {
    if (!mounted || !widget.options.isEditable) return;
    final text = _sourceText;
    // Focus notifications use the same public stream as toolbar insertions.
    // Only actual edits should be saved or invalidate the host's test results.
    if (text == _lastText) return;
    _lastText = text;
    if (hasRegion && region != RegionPosition.after) {
      unawaited(handleRegionCaching(event, region));
    }
    if (region == RegionPosition.inner) widget.editableRegion.add(event);
    widget.onTextChange.add(text);
  }

  void handleCurrentFocusedTextfieldController(RegionPosition position) {
    if (!mounted) return;
    widget.textfieldData.add(
        TextFieldData(controller: _controller(position), position: position));
  }

  void _focusMainField({bool reveal = true}) {
    if (isLoading || !widget.options.isEditable) return;
    final focusNode = _focusNodes[RegionPosition.inner]!;
    final targetContext = focusNode.context;
    final editable = targetContext != null && targetContext.mounted
        ? targetContext.findAncestorStateOfType<EditableTextState>()
        : null;
    // requestKeyboard also reopens a dismissed keyboard when focus was retained.
    if (editable != null) {
      editable.requestKeyboard();
    } else if (reveal && scrollController.hasClients) {
      // A long before/after region can scroll the main field out of the list.
      final generation = _initialization;
      final target =
          (_firstLine(RegionPosition.inner) - 1) * getTextHeight(context);
      scrollController
          .jumpTo(target.clamp(0.0, scrollController.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _initialization) {
          _focusMainField(reveal: false);
        }
      });
    } else {
      focusNode.requestFocus();
    }
  }

  double getTextHeight(BuildContext context, {double? fontSize}) =>
      MediaQuery.textScalerOf(context)
          .scale(fontSize ?? widget.options.fontSize) *
      widget.options.lineHeight;
  TextStyle get _style => TextStyle(
        fontFamily: widget.options.fontFamily,
        fontSize: widget.options.fontSize,
        height: widget.options.lineHeight,
        color: widget.options.textColor,
        letterSpacing: 0,
        wordSpacing: 0,
        fontWeight: FontWeight.w400,
      );
  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    final document = _currentDocument;
    final options = widget.options;
    final style = _style;
    final scaler = MediaQuery.textScalerOf(context);
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final rowHeight = getTextHeight(context);
    final numberWidth = _measureText(
        math.max(_minimumGutterNumber, document.lineCount).toString(),
        style,
        scaler,
        strut);
    final gutterWidth =
        math.max(options.linebarWidth, numberWidth + _gutterPadding);
    final contentWidth = _widthCache.measure(document, style, scaler);
    final selection = Theme.of(context).textSelectionTheme;
    return TextFieldTapRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: options.isEditable ? _focusMainField : null,
        child: TextSelectionTheme(
          data: selection.copyWith(
              cursorColor: options.cursorColor,
              selectionColor: options.selectionColor,
              selectionHandleColor: options.selectionHandleColor),
          child: LayoutBuilder(builder: (context, constraints) {
            final fullHeight = document.lineCount * rowHeight;
            final height = constraints.hasBoundedHeight
                ? options.takeFullHeight
                    ? constraints.maxHeight
                    : math.min(fullHeight, constraints.maxHeight)
                : fullHeight;
            final viewportWidth =
                constraints.maxWidth - (options.showLinebar ? gutterWidth : 0);
            return SizedBox(
              height: height,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (options.showLinebar)
                      _Gutter(
                          document: document,
                          controller: linebarController,
                          width: gutterWidth,
                          rowHeight: rowHeight,
                          style: style,
                          options: options),
                    Expanded(
                        child: _codeViewport(
                            document,
                            style,
                            rowHeight,
                            math.max(
                                contentWidth, math.max(0.0, viewportWidth)))),
                  ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _codeViewport(_EditorDocument document, TextStyle style,
          double rowHeight, double width) =>
      ColoredBox(
        color: widget.options.backgroundColor,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
              gestureSettings:
                  const DeviceGestureSettings(touchSlop: _editorTouchSlop)),
          child: Scrollbar(
            controller: horizontalController,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: horizontalController,
              child: SizedBox(
                width: width,
                child: ListView(
                  padding: EdgeInsets.zero,
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    for (final region in document.regions)
                      _CodeField(
                          region: region,
                          controller: _controller(region.position),
                          focusNode: _focusNodes[region.position]!,
                          options: widget.options,
                          style: style,
                          rowHeight: rowHeight,
                          activeLine: _activeLine,
                          onChanged: (text) => handleTextChange(
                              text,
                              region.position,
                              widget.options.regionOptions != null),
                          onTap: () => handleCurrentFocusedTextfieldController(
                              region.position)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
