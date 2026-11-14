part of 'editor.dart';

const _contentPadding = 10.0;
const _caretClearance = 4.0;
const _gutterPadding = 8.0;
const _minimumGutterNumber = 99;
const _leadingBorderWidth = 3.0;
const _editorTouchSlop = 8.0;

TextPainter _layoutText(
        String text, TextStyle style, TextScaler scaler, StrutStyle strut) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      strutStyle: strut,
    )..layout();

double _measureText(
    String text, TextStyle style, TextScaler scaler, StrutStyle strut) {
  final painter = _layoutText(text, style, scaler, strut);
  final width = painter.width;
  painter.dispose();
  return width;
}

class _ContentWidthCache {
  _EditorDocument? _document;
  TextStyle? _style;
  TextScaler? _scaler;
  double _width = 0;
  int? _tabWidth;
  final _lineWidths = <String, double>{};
  int measurements = 0;

  double measure(_EditorDocument document, TextStyle style, TextScaler scaler,
      {int? tabWidth}) {
    if (_style != style || _scaler != scaler || _tabWidth != tabWidth) {
      _lineWidths.clear();
      _document = null;
      _tabWidth = tabWidth;
      _style = style;
      _scaler = scaler;
    }
    if (!identical(document, _document)) {
      final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
      final used = <String>{};
      _width = 0;
      for (final region in document.regions) {
        for (final source in region.lines) {
          used.add(source);
          final width = _lineWidths.putIfAbsent(source, () {
            var line = source;
            if (tabWidth != null && line.contains('\t')) {
              var column = 0;
              line = line.replaceFirstMapped(RegExp(r'^[ \t]*'), (match) {
                final prefix = StringBuffer();
                for (final c in match[0]!.codeUnits) {
                  final count = c == 9 ? tabWidth - column % tabWidth : 1;
                  prefix.write(' ' * count);
                  column += count;
                }
                return prefix.toString();
              });
            }
            assert(() {
              measurements++;
              return true;
            }());
            return _measureText(line, style, scaler, strut).ceilToDouble() +
                _contentPadding * 2 +
                _caretClearance;
          });
          _width = math.max(_width, width);
        }
      }
      // Retain unchanged rows across edits, without retaining deleted source.
      _lineWidths.removeWhere((line, _) => !used.contains(line));
      _document = document;
    }
    return _width;
  }
}

class _Gutter extends StatefulWidget {
  const _Gutter(
      {required this.document,
      required this.controller,
      required this.width,
      required this.layout,
      required this.style,
      required this.options,
      this.pythonModel});
  final _EditorDocument document;
  final ScrollController controller;
  final double width;
  final _EditorTextLayout layout;
  final TextStyle style;
  final EditorOptions options;
  final PythonIndentModel? pythonModel;

  @override
  State<_Gutter> createState() => _GutterState();
}

class _GutterState extends State<_Gutter> {
  Widget? _content;
  int? _first, _last;

  @override
  void initState() {
    super.initState();
    widget.layout.addListener(_invalidate);
  }

  void _invalidate() => _content = null;

  @override
  void didUpdateWidget(_Gutter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) {
      oldWidget.layout.removeListener(_invalidate);
      widget.layout.addListener(_invalidate);
    }
    _invalidate();
  }

  @override
  void dispose() {
    widget.layout.removeListener(_invalidate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('phone-ide-gutter'),
        width: widget.width,
        decoration: BoxDecoration(
            color: widget.options.linebarColor,
            border: Border(
                right: BorderSide(color: widget.options.linebarBorderColor))),
        child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
                  animation:
                      Listenable.merge([widget.layout, widget.controller]),
                  builder: (_, __) {
                    final layout = widget.layout;
                    final controller = widget.controller;
                    final offset =
                        controller.hasClients ? controller.offset : 0.0;
                    final firstLine = layout.lineAt(offset);
                    final lastLine =
                        layout.lineAt(offset + constraints.maxHeight);
                    final first = math.max(
                        0, firstLine == null ? _first ?? 0 : firstLine - 2);
                    final last = math.min(widget.document.lineCount - 1,
                        lastLine == null ? _last ?? 0 : lastLine + 2);
                    // Sub-row scroll ticks only translate the existing
                    // viewport. Rebuild labels when the native row window
                    // changes, or when typography/source geometry changes.
                    if (_content != null && _first == first && _last == last) {
                      return _content!;
                    }
                    _first = first;
                    _last = last;
                    return _content = SingleChildScrollView(
                      controller: controller,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                          height: layout.height,
                          child: Stack(children: [
                            for (var index = first; index <= last; index++)
                              if (layout.boxForLine(index) case final Rect box)
                                Positioned(
                                    top: box.top,
                                    height: box.height,
                                    left: 0,
                                    right: 0,
                                    child: _number(index)),
                          ])),
                    );
                  },
                )),
      );

  Widget _number(int index) {
    final model = widget.pythonModel;
    final options = widget.options;
    final style = widget.style;
    final label = model != null && index < model.lines.length
        ? 'Line ${index + 1}, indentation ${model.lines[index].guideColumns.length}, ${model.lines[index].text.trimLeft()}'
        : 'Line ${widget.document.toFileLine(index + 1) ?? index + 1}';
    final invalid = model != null &&
        index < model.lines.length &&
        model.lines[index].diagnostics.isNotEmpty;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Align(
        key: ValueKey('phone-ide-line-${index + 1}'),
        alignment: Alignment.center,
        child: Text('${widget.document.toFileLine(index + 1) ?? ''}',
            textDirection: TextDirection.ltr,
            strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
            style: style.copyWith(
                color: invalid
                    ? const Color(0xffdc4b4b)
                    : options.linebarTextColor,
                fontWeight: invalid ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }
}

class _ActiveLine extends StatelessWidget {
  const _ActiveLine(
      {required this.line,
      required this.region,
      required this.layout,
      required this.color,
      required this.borderColor});
  final ValueListenable<int?> line;
  final _DocumentRegion region;
  final _EditorTextLayout layout;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([line, layout]),
        builder: (_, __) {
          final active = line.value;
          if (active == null ||
              active < region.firstLine ||
              active >= region.firstLine + region.lineCount ||
              (color == null && borderColor == null)) {
            return const SizedBox.shrink();
          }
          final box = layout.box(region.position, active - region.firstLine);
          if (box == null) return const SizedBox.shrink();
          return Positioned(
            top: box.top,
            left: 0,
            right: 0,
            height: box.height,
            child: IgnorePointer(
                child: Container(
              key: const ValueKey('phone-ide-active-line'),
              decoration: BoxDecoration(
                  color: color,
                  border: Border(
                      left: BorderSide(
                          color: borderColor ?? Colors.transparent,
                          width: _leadingBorderWidth))),
            )),
          );
        },
      );
}

class _CodeField extends StatelessWidget {
  const _CodeField(
      {required this.region,
      required this.controller,
      required this.focusNode,
      required this.options,
      required this.style,
      required this.layout,
      required this.activeLine,
      this.pythonModel,
      this.inputFormatter,
      required this.onCommand,
      this.debugOnGuideGeometry,
      required this.onPlainPaste,
      required this.editorFocused,
      required this.scrollController,
      required this.horizontalScrollController,
      required this.caretOffset,
      required this.indentGuides,
      required this.onChanged,
      required this.onTap});

  final _DocumentRegion region;
  final TextEditingControllerIDE controller;
  final FocusNode focusNode;
  final EditorOptions options;
  final TextStyle style;
  final _EditorTextLayout layout;
  final ValueListenable<int?> activeLine;
  final List<_IndentGuideSegment> indentGuides;
  final PythonIndentModel? pythonModel;
  final TextInputFormatter? inputFormatter;
  final ValueChanged<EditorCommand> onCommand;
  final ValueChanged<List<EditorGuideRun>>? debugOnGuideGeometry;
  final VoidCallback onPlainPaste;
  final ValueListenable<bool> editorFocused;
  final ScrollController scrollController;
  final ScrollController horizontalScrollController;
  final int? Function() caretOffset;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final regionOptions =
        region.position == RegionPosition.inner ? options.regionOptions : null;
    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final border = regionOptions?.borderColor;
    final textField = TextField(
      focusNode: focusNode,
      controller: controller,
      readOnly: !options.isEditable,
      smartQuotesType: SmartQuotesType.disabled,
      smartDashesType: SmartDashesType.disabled,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.none,
      textDirection: TextDirection.ltr,
      cursorColor: options.cursorColor,
      selectionHeightStyle: BoxHeightStyle.strut,
      strutStyle: strut,
      decoration: const InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
          fillColor: Colors.transparent,
          isCollapsed: true,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: _contentPadding)),
      maxLines: null,
      minLines: region.lineCount,
      style: style,
      onChanged: onChanged,
      onTap: onTap,
      contextMenuBuilder: (context, editable) =>
          AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editable.contextMenuAnchors,
              buttonItems: [
            ...editable.contextMenuButtonItems,
            if (options.isEditable && inputFormatter != null)
              ContextMenuButtonItem(
                  label: 'Paste without re-indenting',
                  onPressed: () {
                    editable.hideToolbar();
                    onPlainPaste();
                  }),
          ]),
      inputFormatters: [
        if (options.isEditable && inputFormatter != null) inputFormatter!,
        if (options.isEditable && inputFormatter == null)
          _EditorIndentFormatter(
              language: controller.language, indentSize: options.indentSize),
        if (inputFormatter == null)
          FilteringTextInputFormatter.deny(RegExp(r'[“”]'),
              replacementString: '"'),
        if (inputFormatter == null)
          FilteringTextInputFormatter.deny(RegExp(r'[‘’]'),
              replacementString: "'"),
      ],
    );
    final field = inputFormatter == null || !options.isEditable
        ? textField
        : CallbackShortcuts(bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                onCommand(EditorCommand.caretLeft),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                onCommand(EditorCommand.caretRight),
            const SingleActivator(LogicalKeyboardKey.tab): () =>
                onCommand(EditorCommand.indent),
            const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
                onCommand(EditorCommand.dedent),
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
                onCommand(EditorCommand.undo),
            const SingleActivator(LogicalKeyboardKey.keyZ,
                control: true,
                shift: true): () => onCommand(EditorCommand.redo),
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
                onCommand(EditorCommand.undo),
            const SingleActivator(LogicalKeyboardKey.keyZ,
                meta: true, shift: true): () => onCommand(EditorCommand.redo),
          }, child: textField);
    return _TextLayoutHost(
        layout: layout,
        region: region,
        controller: controller,
        child: DecoratedBox(
          key: ValueKey('phone-ide-region-${region.position.name}'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
              border: border == null
                  ? null
                  : Border(
                      left: BorderSide(
                          color: border, width: _leadingBorderWidth))),
          child: ColoredBox(
            color: regionOptions?.color ?? options.backgroundColor,
            child: Stack(children: [
              _ActiveLine(
                  line: activeLine,
                  region: region,
                  layout: layout,
                  color: options.activeLineColor,
                  borderColor: options.activeLineBorderColor),
              if (indentGuides.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _IndentGuidePainter(
                          segments: indentGuides,
                          layout: layout,
                          region: region,
                          color: options.indentGuideColor ??
                              options.textColor.withValues(alpha: .18),
                        ),
                      ),
                    ),
                  ),
                ),
              if (inputFormatter != null)
                _PythonGuideHost(
                    model: pythonModel,
                    region: region,
                    controller: controller,
                    focusNode: focusNode,
                    options: options,
                    layout: layout,
                    scroll: scrollController,
                    horizontalScroll: horizontalScrollController,
                    activeLine: activeLine,
                    caretOffset: caretOffset,
                    style: style,
                    debugOnGeometry: debugOnGuideGeometry,
                    editorFocused: editorFocused,
                    child: field)
              else
                field,
            ]),
          ),
        ));
  }
}
