part of 'editor.dart';

/// A snapshot of the production guide model, available only in debug builds.
/// Positions are logical columns; pixel coordinates use the native text layout.
class EditorGuideSnapshot {
  const EditorGuideSnapshot(
      {required this.model,
      required this.caretOffset,
      required this.focused,
      required this.readOnly,
      required this.revision,
      required this.syncInputAnalyses,
      required this.geometry});
  final PythonIndentModel model;
  final int? caretOffset;
  final bool focused;
  final bool readOnly;
  final int revision;
  final int syncInputAnalyses;
  final Map<RegionPosition, List<EditorGuideRun>> geometry;

  List<int> columns(int line) => model.guidesForLine(line,
      caretOffset: caretOffset, focused: focused, readOnly: readOnly);
  PythonBlock? activeBlock(int line) =>
      model.activeBlockForLine(line, focused: focused, readOnly: readOnly);
}

class _PythonGuideHost extends StatefulWidget {
  const _PythonGuideHost(
      {required this.child,
      required this.model,
      required this.region,
      required this.controller,
      required this.focusNode,
      required this.options,
      required this.layout,
      required this.scroll,
      required this.horizontalScroll,
      required this.activeLine,
      required this.caretOffset,
      required this.style,
      this.debugOnGeometry,
      required this.editorFocused});
  final Widget child;
  final PythonIndentModel? model;
  final _DocumentRegion region;
  final TextEditingController controller;
  final FocusNode focusNode;
  final EditorOptions options;
  final _EditorTextLayout layout;
  final ScrollController scroll;
  final ScrollController horizontalScroll;
  final ValueListenable<int?> activeLine;
  final int? Function() caretOffset;
  final TextStyle style;
  final ValueListenable<bool> editorFocused;
  final ValueChanged<List<EditorGuideRun>>? debugOnGeometry;
  @override
  State<_PythonGuideHost> createState() => _PythonGuideHostState();
}

class _PythonGuideHostState extends State<_PythonGuideHost> {
  final _fieldKey = GlobalKey();
  _PythonGuidePainter? _painter;
  bool _scheduled = false;
  TextStyle? _attachmentStyle;
  TextScaler? _attachmentScaler;
  _RegionTextLayout? _attachmentLayout;

  void _listen(_PythonGuideHost host, {required bool add}) {
    void listen(Listenable source, VoidCallback listener) {
      if (add) {
        source.addListener(listener);
      } else {
        source.removeListener(listener);
      }
    }

    listen(host.controller, _schedule);
    listen(host.layout, _layoutChanged);
    listen(host.focusNode, _schedule);
    listen(host.activeLine, _schedule);
    listen(host.editorFocused, _schedule);
    listen(host.scroll, _refresh);
    listen(host.horizontalScroll, _schedule);
  }

  @override
  void initState() {
    super.initState();
    // Native caret positions snap through the final global transform. Refresh
    // after horizontal layout, when that transform has its new pixel phase.
    _listen(widget, add: true);
    _schedule();
  }

  @override
  void didUpdateWidget(_PythonGuideHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen(oldWidget, add: false);
    _listen(widget, add: true);
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  void _layoutChanged() {
    // Layout publication already happens after the native field was laid out.
    // Attach now so the very next paint includes newly inserted blank guides.
    final editable = _findEditable(_fieldKey.currentContext);
    if (mounted && editable != null) _attach(editable);
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final editable = _findEditable(_fieldKey.currentContext);
      if (editable == null) return;
      _attach(editable);
    });
  }

  void _attach(RenderEditable editable) {
    final model = widget.model;
    if (model == null) {
      editable.painter = null;
      _painter?.dispose();
      _painter = null;
      assert(() {
        widget.debugOnGeometry?.call(const []);
        return true;
      }());
      return;
    }
    // TextField reapplies its platform cursor default when rebuilding. Keep
    // the caret above the guides even when reusing the existing painter.
    editable.paintCursorAboveText = true;
    final previous = _painter;
    final scaler = MediaQuery.textScalerOf(context);
    final measured = widget.layout.region(widget.region.position);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final highContrast = MediaQuery.highContrastOf(context);
    if (previous != null &&
        identical(previous.render, editable) &&
        identical(previous.model, model) &&
        identical(previous.region, widget.region) &&
        previous.options == widget.options &&
        identical(previous.layout, widget.layout) &&
        identical(_attachmentLayout, measured) &&
        previous.devicePixelRatio == devicePixelRatio &&
        previous.highContrast == highContrast &&
        _attachmentStyle == widget.style &&
        _attachmentScaler == scaler) {
      previous.refreshPixelPhase();
      _refresh();
      return;
    }
    _attachmentStyle = widget.style;
    _attachmentScaler = scaler;
    _attachmentLayout = measured;
    final next = _PythonGuidePainter(
      render: editable,
      model: model,
      region: widget.region,
      options: widget.options,
      layout: widget.layout,
      devicePixelRatio: devicePixelRatio,
      highContrast: highContrast,
      spaceWidth: _measureText(' ', widget.style, scaler,
          StrutStyle.fromTextStyle(widget.style, forceStrutHeight: true)),
    );
    _painter = next;
    // Flutter's public background-painter slot runs after selection and before
    // glyphs. Put the native caret above glyphs so a guide cannot obscure it.
    editable.painter = next;
    next.refreshPixelPhase();
    _refresh();
    previous?.dispose();
  }

  RenderEditable? _findEditable(BuildContext? context) {
    if (context == null) return null;
    RenderEditable? found;
    void visit(Element element) {
      if (element.renderObject case final RenderEditable editable) {
        found = editable;
        return;
      }
      if (found == null) element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  void _refresh() {
    final editableHeight =
        widget.layout.region(widget.region.position)?.height ?? 0;
    _painter?.updateViewport(
      scrollOffset: widget.scroll.hasClients ? widget.scroll.offset : 0,
      viewportHeight: widget.scroll.hasClients
          ? widget.scroll.position.viewportDimension
          : editableHeight,
      caretOffset: widget.caretOffset(),
      activeLine: widget.activeLine.value,
      focused: widget.editorFocused.value,
    );
    assert(() {
      widget.debugOnGeometry?.call(_painter?._debugRuns ?? const []);
      return true;
    }());
  }

  @override
  void dispose() {
    _listen(widget, add: false);
    _painter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _fieldKey, child: widget.child);
}

class EditorGuideRun {
  const EditorGuideRun(this.rect, this.active);
  final Rect rect;
  final bool active;
}

class _PythonGuidePainter extends RenderEditablePainter {
  _PythonGuidePainter(
      {required this.render,
      required this.model,
      required this.region,
      required this.options,
      required this.layout,
      required this.devicePixelRatio,
      required this.highContrast,
      required this.spaceWidth})
      : _normalColor = options.indentGuideColor ??
            options.textColor.withValues(alpha: highContrast ? .85 : .65),
        _activeColor = options.activeIndentGuideColor ??
            options.cursorColor ??
            options.textColor;
  final RenderEditable render;
  final PythonIndentModel model;
  final _DocumentRegion region;
  final EditorOptions options;
  final _EditorTextLayout layout;
  final double devicePixelRatio;
  final bool highContrast;
  final double spaceWidth;
  final Color _normalColor;
  final Color _activeColor;
  List<EditorGuideRun> _debugRuns = const [];
  final Paint _paint = Paint()..isAntiAlias = false;
  Path _normalPath = Path();
  Path _activePath = Path();
  Path _warningPath = Path();
  Rect _viewport = Rect.zero;
  (int, int, int?, int?, bool, Size)? _viewportKey;
  final _caretXs = <int, double>{};
  double? _pixelPhase;

  void refreshPixelPhase() {
    final phase = (render.localToGlobal(Offset.zero).dx * devicePixelRatio) % 1;
    if (_pixelPhase != null && (phase - _pixelPhase!).abs() < .000001) return;
    _pixelPhase = phase;
    _caretXs.clear();
    _viewportKey = null;
  }

  // Vertical scrolling changes visible rows, not their horizontal geometry.
  // Text or typography changes replace the painter. Horizontal movement only
  // invalidates native caret positions if its physical-pixel phase changes.
  // Retain only offsets in the current overscan window.
  double _caretX(int offset) => _caretXs.putIfAbsent(offset,
      () => render.getLocalRectForCaret(TextPosition(offset: offset)).left);

  double _snap(double value) =>
      (value * devicePixelRatio).round() / devicePixelRatio;

  void updateViewport(
      {required double scrollOffset,
      required double viewportHeight,
      required int? caretOffset,
      required int? activeLine,
      required bool focused}) {
    if (!render.hasSize || !options.showIndentGuides) {
      assert(() {
        _debugRuns = const [];
        return true;
      }());
      notifyListeners();
      return;
    }
    final measured = layout.region(region.position);
    if (measured == null || !identical(measured.render, render)) return;
    final origin = layout.origin(region.position);
    final first = math.max(0, measured.rowAt(scrollOffset - origin) - 2);
    final end = math.min(region.lineCount,
        measured.rowAt(scrollOffset + viewportHeight - origin) + 3);
    final key = (first, end, caretOffset, activeLine, focused, render.size);
    if (_viewportKey == key) return;
    _viewportKey = key;
    // The outer scroll viewport clips fractional rows. Keep the guide clip in
    // document-row coordinates so a sub-row scroll can reuse the same paint.
    _viewport = Rect.fromLTRB(0, measured.box(first).top, render.size.width,
        measured.box(end - 1).bottom);
    final firstOffset = first < region.lineCount
        ? region.lineOffsets[first]
        : region.text.length;
    final endOffset =
        end < region.lineCount ? region.lineOffsets[end] : region.text.length;
    _caretXs
        .removeWhere((offset, _) => offset < firstOffset || offset > endOffset);
    final caretLine = activeLine == null ? null : activeLine - 1;
    final active = options.showActiveIndentGuide &&
            caretLine != null &&
            caretLine >= 0 &&
            caretLine < model.lines.length
        ? model.activeBlockForLine(caretLine,
            focused: focused, readOnly: !options.isEditable)
        : null;
    final runs = <EditorGuideRun>[];
    _warningPath = Path();
    final open = <(double, bool), int>{};
    for (var row = first; row < end; row++) {
      final lineNumber = region.firstLine - 1 + row;
      if (lineNumber >= model.lines.length) break;
      final line = model.lines[lineNumber];
      final columns = model.guidesForLine(lineNumber,
          caretOffset: caretOffset,
          focused: focused,
          readOnly: !options.isEditable);
      final display = model.displayGuidesForLine(lineNumber,
          caretOffset: caretOffset,
          focused: focused,
          readOnly: !options.isEditable);
      final positions = <(double, bool)>{};
      final blank = line.text.trim().isEmpty;
      final localStart = region.lineOffsets[row];
      for (final diagnostic in line.diagnostics) {
        final from = localStart + diagnostic.startOffset - line.startOffset;
        final to = localStart + diagnostic.endOffset - line.startOffset;
        final left = _caretX(from.clamp(0, region.text.length));
        final right = _caretX(to.clamp(0, region.text.length));
        _warningPath.addRect(Rect.fromLTRB(
            left,
            measured.box(row).bottom - 2 / devicePixelRatio,
            math.max(left + spaceWidth, right),
            measured.box(row).bottom));
      }
      for (var index = 0; index < columns.length; index++) {
        final column = columns[index];
        if (!blank && column >= line.indentColumn) continue;
        var sourceColumn = 0;
        var prefixOffset = 0;
        while (
            prefixOffset < line.indentPrefix.length && sourceColumn < column) {
          final character = line.indentPrefix.codeUnitAt(prefixOffset++);
          sourceColumn = character == 9
              ? sourceColumn + 8 - sourceColumn % 8
              : character == 12 || character == 0xfeff
                  ? 0
                  : sourceColumn + 1;
        }
        final double x;
        if (sourceColumn == column &&
            prefixOffset <= line.indentPrefix.length &&
            localStart + prefixOffset <= region.text.length) {
          x = _caretX(localStart + prefixOffset);
        } else {
          x = _caretX(localStart) + display[index] * spaceWidth;
        }
        final highlighted = active != null &&
            column == active.guideColumn &&
            lineNumber > active.headerEndLine &&
            lineNumber <= active.endLine;
        positions.add((_snap(x), highlighted));
      }
      for (final key in open.keys.toList()) {
        if (!positions.contains(key)) {
          runs.add(_run(key, open.remove(key)!, row));
        }
      }
      for (final position in positions) {
        open.putIfAbsent(position, () => row);
      }
    }
    for (final entry in open.entries) {
      runs.add(_run(entry.key, entry.value, end));
    }
    assert(() {
      _debugRuns = runs;
      return true;
    }());
    _normalPath = Path();
    _activePath = Path();
    for (final run in runs) {
      final path = run.active ? _activePath : _normalPath;
      if (options.indentGuideStyle == IndentGuideStyle.solid) {
        path.addRect(run.rect);
      } else {
        final dash =
            options.indentGuideStyle == IndentGuideStyle.dotted ? 1.0 : 5.0;
        final period = dash + 3;
        final documentOrigin = layout.origin(region.position);
        var y = ((run.rect.top + documentOrigin) / period).floor() * period -
            documentOrigin;
        while (y < run.rect.bottom) {
          final from = math.max(y, run.rect.top);
          final to = math.min(y + dash, run.rect.bottom);
          if (to > from) {
            path.addRect(
                Rect.fromLTRB(run.rect.left, from, run.rect.right, to));
          }
          y += period;
        }
      }
    }
    notifyListeners();
  }

  EditorGuideRun _run((double, bool) position, int first, int end) =>
      EditorGuideRun(
          Rect.fromLTRB(
              position.$1,
              layout.region(region.position)!.box(first).top,
              position.$1 + (position.$2 ? 2 : 1) / devicePixelRatio,
              layout.region(region.position)!.box(end - 1).bottom),
          position.$2);

  @override
  void paint(Canvas canvas, Size size, RenderEditable renderEditable) {
    canvas.save();
    // The editable origin can fall between physical pixels. Antialiasing this
    // clip would fade the column-zero guide even though its paint is crisp.
    canvas.clipRect(_viewport, doAntiAlias: false);
    _paint.color = _normalColor;
    canvas.drawPath(_normalPath, _paint);
    _paint.color = _activeColor;
    canvas.drawPath(_activePath, _paint);
    _paint.color = const Color(0xffdc4b4b);
    canvas.drawPath(_warningPath, _paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PythonGuidePainter oldDelegate) => true;
}
