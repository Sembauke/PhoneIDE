import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle, PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_ide/controller/custom_text_controller.dart';
import 'package:phone_ide/editor/editor_options.dart';
import 'package:phone_ide/editor/python_indentation.dart';
import 'package:phone_ide/editor/python_analysis_worker.dart';
import 'package:phone_ide/editor/python_input.dart';
import 'package:phone_ide/highlighting/textmate_highlighter_registry.dart';
import 'package:phone_ide/models/textfield_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'editor_document.dart';
part 'editor_history.dart';
part 'editor_indentation.dart';
part 'editor_input.dart';
part 'editor_layout.dart';
part 'editor_text_layout.dart';
part 'editor_syntax.dart';
part 'editor_python.dart';
part 'editor_python_rendering.dart';
part 'editor_commands.dart';
part 'editor_deferred_input.dart';

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

/// Claim a two-finger touch before a child scroll drag can win on its first move.
/// Single-pointer drags and trackpad gestures retain Flutter's normal arbitration.
class _EditorScaleGestureRecognizer extends ScaleGestureRecognizer {
  final Set<int> _touchPointers = {};

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerDownEvent && event.kind == PointerDeviceKind.touch) {
      _touchPointers.add(event.pointer);
    }
    super.handleEvent(event);
    if (event is PointerDownEvent &&
        event.kind == PointerDeviceKind.touch &&
        pointerCount >= 2 &&
        _touchPointers.length >= 2) {
      resolve(GestureDisposition.accepted);
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _touchPointers.remove(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _touchPointers.remove(pointer);
    super.rejectGesture(pointer);
  }
}

class EditorState extends State<Editor> {
  final ScrollController scrollController = ScrollController();
  final ScrollController horizontalController = ScrollController();
  final ScrollController linebarController = ScrollController();
  final _EditorTextLayout _textLayout = _EditorTextLayout();
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
  final _editorFocused = ValueNotifier<bool>(false);
  final _widthCache = _ContentWidthCache();
  @visibleForTesting
  int get debugContentWidthMeasurements => _widthCache.measurements;
  final _indentGuideCache = _IndentGuideCache();
  final _values = <RegionPosition, TextEditingValue>{
    for (final position in RegionPosition.values)
      position: TextEditingValue.empty,
  };
  final _controllerListeners = <RegionPosition, VoidCallback>{};
  _EditorDocument? _document;
  final _regionSeparators = <RegionPosition, String>{};
  bool _restoringValue = false;
  Map<RegionPosition, List<EditorGuideRun>>? _debugGuideGeometry;
  PythonIndentModel? _pythonModel;
  PythonIndentOptions? _modelOptions;
  int _modelRevision = 0;
  int _syncInputAnalyses = 0;
  int _analysisGeneration = 0;
  String? _backgroundText;
  int? _backgroundVirtualLine;
  PythonIndentModel? _pendingPythonModel;
  Timer? _guideDebounce;
  bool _whitespaceOfferOpen = false;
  double _zoomScale = 1, _zoomStart = 1;
  PythonIndentOptions? _backgroundOptions;
  final _pythonCache = PythonIndentCache();
  final _pythonAnalysisWorker = PythonAnalysisWorker();
  final _pythonInput = PythonInputEngine();
  final _deferredPythonInput = <RegionPosition, _DeferredPythonInput>{};
  final _undoHistory = {
    for (final p in RegionPosition.values) p: <TextEditingValue>[]
  };
  final _redoHistory = {
    for (final p in RegionPosition.values) p: <TextEditingValue>[]
  };
  // Whether each inner-region history entry omits its virtual source row.
  final _undoEmptyInner = <bool>[];
  final _redoEmptyInner = <bool>[];
  bool _performingHistory = false;
  final _historyGroups = {
    for (final p in RegionPosition.values) p: _UndoGroup()
  };
  void _acceptPythonModel(
      PythonIndentModel model, PythonIndentOptions options) {
    if (!mounted) return;
    setState(() {
      _pythonModel = model;
      _modelOptions = options;
      assert(() {
        _modelRevision++;
        return true;
      }());
    });
  }

  void executeCommand(EditorCommand command) => _executeCommand(command);
  void undo() => _restoreHistory(undo: true);
  void redo() => _restoreHistory(undo: false);
  void paste(String text, {bool reindent = true}) {
    if (!_isPython || !widget.options.isEditable) return;
    if (_deferPublicPythonPaste(text, reindent: reindent)) return;
    final controller = _controller(_activePosition);
    final previous = controller.value;
    _applyPythonCommand((value, start, end) => _pythonInput.paste(value, text,
        reindent: reindent && !_hasInvalidIndent(text),
        model: _inputPythonModel,
        editableStart: start,
        editableEnd: end));
    if (_hasInvalidIndent(text)) {
      _offerWhitespaceConversion(_activePosition,
          previousValue: previous,
          pastedValue: controller.value,
          explicitPaste: true,
          reindent: reindent);
    }
  }

  void convertIndentation({required int indentSize, required bool usesTabs}) {
    if (!_isPython || !widget.options.isEditable) return;
    if (_deferPythonInput) {
      _deferPythonCommand(_DeferredPythonOperation.convert,
          indentSize: indentSize, usesTabs: usesTabs);
      return;
    }
    _applyPythonCommand((value, start, end) => _pythonInput.convertIndentation(
        value,
        indentSize: indentSize,
        usesTabs: usesTabs,
        editableStart: start,
        editableEnd: end));
  }

  void insertText(String text) {
    if (!_isPython || !widget.options.isEditable) return;
    if (_deferPythonInput) {
      _deferPythonCommand(_DeferredPythonOperation.input, inserted: text);
      return;
    }
    _applyPythonCommand((value, start, end) {
      final selection = value.selection;
      final next = value.copyWith(
          text: value.text.replaceRange(selection.start, selection.end, text),
          selection:
              TextSelection.collapsed(offset: selection.start + text.length),
          composing: TextRange.empty);
      return _pythonInput.formatEditUpdate(value, next,
          model: _inputPythonModel, editableStart: start, editableEnd: end);
    });
  }

  /// Debug builds only: the same model used by the production painter.
  @visibleForTesting
  EditorGuideSnapshot? get debugGuideSnapshot {
    EditorGuideSnapshot? snapshot;
    assert(() {
      final model = _currentPythonModel;
      if (model != null) {
        snapshot = EditorGuideSnapshot(
            model: model,
            caretOffset: _globalCaretOffset,
            focused: _focusNodes.values.any((node) => node.hasFocus),
            readOnly: !widget.options.isEditable,
            revision: _modelRevision,
            syncInputAnalyses: _syncInputAnalyses,
            geometry: Map.unmodifiable(_debugGuideGeometry ?? const {}));
      }
      return true;
    }());
    return snapshot;
  }

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
        separators: _regionSeparators,
      );
  String get _sourceText => _currentDocument.sourceText;
  int _lineCount(RegionPosition position) =>
      _currentDocument.region(position).lineCount;

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
        _updateActiveLine();
        _editorFocused.value = _focusNodes.values.any((node) => node.hasFocus);
      });
    }
    scrollController.addListener(_syncGutter);
    _textLayout.addListener(_syncGutterAfterLayout);
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
        ..indentTabWidth = _isPython ? _pythonOptions.effectiveTabWidth : null
        ..language = widget.defaultLanguage
        ..syntaxTheme = widget.options.syntaxTheme;
    }
  }

  void _controllerChanged(RegionPosition position) {
    if (!mounted || _restoringValue) return;
    final controller = _controller(position);
    final previous = _values[position]!;
    var textChanged = previous.text != controller.text;
    if (!textChanged &&
        !isLoading &&
        _isPython &&
        widget.options.isEditable &&
        previous.selection != controller.selection) {
      final start = _regionOffset(position);
      final source = _analysisText;
      final prefix = source.substring(0, start);
      final suffix = source.substring(start + controller.text.length);
      final old = _fullValue(previous, prefix, suffix);
      final next = _fullValue(controller.value, prefix, suffix);
      final pending = _deferredPythonInput[position];
      if (pending != null && !pending.cancelled) {
        // Cleanup is an edit, too. Queue it after pending formatting instead
        // of changing its raw source and invalidating the worker's batch.
        if (!_performingHistory && pending.latest != next) {
          _queuePythonInput(position, old, next, prefix, suffix);
        }
      } else {
        final cleaned = _pythonInput.cleanupOnCaretMove(old, next,
            editableStart: start, editableEnd: start + controller.text.length);
        final local = _localValue(cleaned, prefix, suffix);
        if (local.text != controller.text) {
          _restoringValue = true;
          controller.value = local;
          _restoringValue = false;
          textChanged = true;
        }
      }
    }
    if (textChanged && !isLoading && !widget.options.isEditable) {
      // Host toolbar insertions use the same controllers as keyboard input.
      _restoringValue = true;
      controller.value = previous;
      _restoringValue = false;
      return;
    }
    _values[position] = controller.value;
    if (isLoading) return;
    if (!textChanged && previous.selection != controller.selection) {
      _breakUndoGroup();
    }
    if (textChanged) {
      if (!_performingHistory && _isPython && previous.composing.isCollapsed) {
        _recordUndo(position, previous, current: controller.value);
      }
      if (_emptyInner && inController.text.isNotEmpty) _emptyInner = false;
      _document = null;
      setState(() {});
      if (_isPython) {
        handleTextChange(
            controller.text, position, widget.options.regionOptions != null);
        _revealCaret();
      }
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

  void _syncGutterAfterLayout() {
    // Publication precedes the gutter's size update. Reconcile offsets after
    // that frame, including jumps into newly measured lazy regions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncGutter();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _pythonAnalysisWorker.dispose();
    _cancelDeferredPythonInputs();
    _guideDebounce?.cancel();
    unawaited(_textfieldDataSub.cancel());
    for (final position in RegionPosition.values) {
      _controller(position).removeListener(_controllerListeners[position]!);
      _controller(position).dispose();
      _focusNodes[position]!.dispose();
    }
    _activeLine.dispose();
    _editorFocused.dispose();
    scrollController.dispose();
    horizontalController.dispose();
    linebarController.dispose();
    _textLayout.dispose();
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
    _cancelDeferredPythonInputs();
    _breakUndoGroup();
    final generation = ++_initialization;
    await TextMateHighlighterRegistry.instance.initialize();
    final prefs = await _getPreferencesSafe();
    if (!mounted || generation != _initialization) return;
    final source =
        _DocumentRegion(RegionPosition.inner, widget.defaultValue, 1);
    final lines = source.lines;
    final region = widget.options.regionOptions;
    _regionSeparators.clear();
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
      beforeController.text = source.sliceLines(0, from);
      inController.text = source.sliceLines(from, to);
      afterController.text = source.sliceLines(to, lines.length);
      if (_hasBefore) {
        _regionSeparators[RegionPosition.before] = source.separatorAt(from);
      }
      if (_hasAfter) {
        _regionSeparators[RegionPosition.inner] = source.separatorAt(to);
      }
    }
    _document = null;
    _analysisGeneration++;
    _backgroundText = null;
    _guideDebounce?.cancel();
    _pendingPythonModel = null;
    _pythonCache.reset();
    _pythonModel = null;
    _pythonInput.reset();
    for (final history in [..._undoHistory.values, ..._redoHistory.values]) {
      history.clear();
    }
    _undoEmptyInner.clear();
    _redoEmptyInner.clear();
    _activePosition = RegionPosition.inner;
    _lastText = _sourceText;
    _applySyntaxTheme();
    setState(() => isLoading = false);
    _updateActiveLine();
    var initialScrollApplied = false;
    var initialScrollScheduled = false;
    void scrollToMeasuredRegion() {
      if (initialScrollApplied || initialScrollScheduled) return;
      initialScrollScheduled = true;
      // Native measurements are published after layout. Wait for the gutter
      // to rebuild with those heights before synchronizing the two offsets.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        initialScrollScheduled = false;
        if (!mounted || generation != _initialization) {
          initialScrollApplied = true;
          _textLayout.removeListener(scrollToMeasuredRegion);
          return;
        }
        final innerOrigin = _textLayout.measuredOrigin(RegionPosition.inner);
        if (!scrollController.hasClients ||
            !horizontalController.hasClients ||
            innerOrigin == null) {
          return;
        }
        initialScrollApplied = true;
        _textLayout.removeListener(scrollToMeasuredRegion);
        // A user gesture takes precedence if it starts before measurement.
        if (scrollController.position.userScrollDirection !=
                ScrollDirection.idle ||
            horizontalController.position.userScrollDirection !=
                ScrollDirection.idle) {
          return;
        }
        scrollController.jumpTo(
            innerOrigin.clamp(0.0, scrollController.position.maxScrollExtent));
        horizontalController.jumpTo(0);
      });
      WidgetsBinding.instance.scheduleFrame();
    }

    // The editable field can still be outside the lazy list's viewport. Only
    // its preceding regions need measurement before jumping to its origin.
    _textLayout.addListener(scrollToMeasuredRegion);
    scrollToMeasuredRegion();
  }

  Future<void> handleRegionCaching(String event, RegionPosition region) async {
    final path = widget.path;
    final before = _hasBefore ? _lineCount(RegionPosition.before) : 0;
    final end =
        before + (_emptyInner ? 0 : _lineCount(RegionPosition.inner)) + 1;
    final prefs = await _getPreferencesSafe();
    try {
      await prefs?.setString(path, '$before:$end');
    } catch (error) {
      debugPrint('phone_ide: Could not cache editable region bounds: $error');
    }
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
      final target = _textLayout.measuredOrigin(RegionPosition.inner);
      if (target == null) {
        var focusScheduled = false;
        void focusWhenMeasured() {
          if (focusScheduled) return;
          focusScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            focusScheduled = false;
            if (!mounted || generation != _initialization) {
              _textLayout.removeListener(focusWhenMeasured);
              return;
            }
            if (!scrollController.hasClients ||
                _textLayout.measuredOrigin(RegionPosition.inner) == null) {
              return;
            }
            _textLayout.removeListener(focusWhenMeasured);
            // A later gesture cancels the pending reveal. The native prefix
            // and gutter must both finish layout before the focus jump.
            if (scrollController.position.userScrollDirection !=
                ScrollDirection.idle) {
              return;
            }
            // A lazy sliver can correct its offset while laying out the
            // newly measured prefix without notifying the scroll listener.
            _syncGutter();
            _focusMainField();
          });
          WidgetsBinding.instance.scheduleFrame();
        }

        _textLayout.addListener(focusWhenMeasured);
        // Mount the first region so an invalidated/offscreen prefix can be
        // measured before the requested editable region is revealed.
        scrollController.jumpTo(0);
        return;
      }
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

  /// Nominal typography height retained for callers; not a native row advance.
  /// Editor row positions and extents come from [_textLayout] instead.
  double getTextHeight(BuildContext context, {double? fontSize}) =>
      MediaQuery.textScalerOf(context)
          .scale((fontSize ?? widget.options.fontSize) * _zoomScale) *
      widget.options.lineHeight;
  TextStyle _style(BuildContext context) {
    final theme = Theme.of(context);
    final inputStyle = theme.useMaterial3
        ? theme.textTheme.bodyLarge
        : theme.textTheme.titleMedium;
    final style = (inputStyle ?? const TextStyle()).merge(TextStyle(
      fontFamily: widget.options.fontFamily,
      fontSize: widget.options.fontSize * _zoomScale,
      height: widget.options.lineHeight,
      color: widget.options.textColor,
      letterSpacing: 0,
      wordSpacing: 0,
      fontWeight: FontWeight.w400,
    ));
    // Use the same resolved typography for text, gutters and guides. Prevent
    // TextField from merging another font/fallback after measuring whitespace.
    return style.copyWith(
        inherit: false,
        textBaseline: style.textBaseline ?? TextBaseline.alphabetic);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    final document = _currentDocument;
    _textLayout.configure(document);
    final options = widget.options;
    final style = _style(context);
    final scaler = MediaQuery.textScalerOf(context);
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final numberWidth = _measureText(
        math.max(_minimumGutterNumber, document.lineCount).toString(),
        style,
        scaler,
        strut);
    final gutterWidth =
        math.max(options.linebarWidth, numberWidth + _gutterPadding);
    final contentWidth = _widthCache.measure(document, style, scaler,
        tabWidth: _isPython ? _pythonOptions.effectiveTabWidth : null);
    final pythonModel = _currentPythonModel;
    final guides = options.showIndentGuides && pythonModel == null
        ? _indentGuideCache.measure(
            document, options.indentSize, widget.defaultLanguage, style, scaler)
        : const <RegionPosition, List<_IndentGuideSegment>>{};
    final selection = Theme.of(context).textSelectionTheme;
    final content = TextFieldTapRegion(
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        gestures: {
          if (options.isEditable)
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (recognizer) => recognizer.onTap = _focusMainField),
          if (_isPython)
            _EditorScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                    _EditorScaleGestureRecognizer>(
                _EditorScaleGestureRecognizer.new,
                (recognizer) => recognizer
                  ..onStart = (_) {
                    _zoomStart = _zoomScale;
                  }
                  ..onUpdate = (details) {
                    if (details.pointerCount < 2) return;
                    final next = (_zoomStart * details.scale).clamp(.5, 3.0);
                    if ((next - _zoomScale).abs() > .005) {
                      setState(() => _zoomScale = next);
                    }
                  }),
        },
        child: TextSelectionTheme(
          data: selection.copyWith(
              cursorColor: options.cursorColor,
              selectionColor: options.selectionColor,
              selectionHandleColor: options.selectionHandleColor),
          child: LayoutBuilder(builder: (context, constraints) {
            final viewportWidth =
                constraints.maxWidth - (options.showLinebar ? gutterWidth : 0);
            return AnimatedBuilder(
              animation: _textLayout,
              builder: (context, child) {
                final fullHeight = _textLayout.height;
                final height = constraints.hasBoundedHeight
                    ? options.takeFullHeight
                        ? constraints.maxHeight
                        : fullHeight == 0
                            ? constraints.maxHeight
                            : math.min(fullHeight, constraints.maxHeight)
                    : math.max(1.0, fullHeight);
                return SizedBox(height: height, child: child);
              },
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (options.showLinebar)
                      _Gutter(
                          document: document,
                          controller: linebarController,
                          width: gutterWidth,
                          layout: _textLayout,
                          style: style,
                          options: options,
                          pythonModel: pythonModel),
                    Expanded(
                        child: _codeViewport(
                            document,
                            guides,
                            style,
                            _textLayout,
                            math.max(
                                contentWidth, math.max(0.0, viewportWidth)))),
                  ]),
            );
          }),
        ),
      ),
    );
    return SafeArea(
        top: false,
        bottom: false,
        child: _isPython && options.isEditable
            ? DragTarget<String>(
                onAcceptWithDetails: (details) => paste(details.data),
                builder: (context, candidate, rejected) => content)
            : content);
  }

  Widget _codeViewport(
          _EditorDocument document,
          Map<RegionPosition, List<_IndentGuideSegment>> guides,
          TextStyle style,
          _EditorTextLayout layout,
          double width) =>
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
                          layout: layout,
                          activeLine: _activeLine,
                          pythonModel: _currentPythonModel,
                          scrollController: scrollController,
                          horizontalScrollController: horizontalController,
                          caretOffset: () => _globalCaretOffset,
                          inputFormatter: _isPython
                              ? _PythonInputFormatter(this, region.position)
                              : null,
                          onCommand: executeCommand,
                          onPlainPaste: () async {
                            final data =
                                await Clipboard.getData(Clipboard.kTextPlain);
                            if (mounted && data?.text != null) {
                              paste(data!.text!, reindent: false);
                            }
                          },
                          editorFocused: _editorFocused,
                          debugOnGuideGeometry: kDebugMode
                              ? (runs) => (_debugGuideGeometry ??=
                                  {})[region.position] = runs
                              : null,
                          indentGuides: guides[region.position] ?? const [],
                          onChanged: (text) => handleTextChange(
                              text,
                              region.position,
                              widget.options.regionOptions != null),
                          onTap: () {
                            _snapIndentTap(region.position);
                            handleCurrentFocusedTextfieldController(
                                region.position);
                          }),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
