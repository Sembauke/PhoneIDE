part of 'editor.dart';

/// Geometry from the rendered fields, shared by every row decoration.
/// Only requested rows are sampled; scrolling never reshapes the document.
class _EditorTextLayout extends ChangeNotifier {
  final _regions = <RegionPosition, _RegionTextLayout>{};
  _EditorDocument? _document;

  void configure(_EditorDocument document) {
    _document = document;
    _regions.removeWhere((position, _) =>
        !document.regions.any((region) => region.position == position));
  }

  _RegionTextLayout? _measuredRegion(RegionPosition position) {
    final measured = _regions[position];
    final source = _document?.regions
        .where((source) => source.position == position)
        .firstOrNull;
    return measured != null && source?.text == measured.source.text
        ? measured
        : null;
  }

  _RegionTextLayout? region(RegionPosition position) {
    final measured = _measuredRegion(position);
    return measured != null && measured.render.attached ? measured : null;
  }

  Rect? box(RegionPosition position, int row) {
    final current = region(position);
    if (current != null && row >= 0 && row < current.source.lineCount) {
      return current.box(row);
    }
    // A pending edit or a lazily detached field must not erase geometry that
    // was already measured from Flutter's paragraph. Never query a stale
    // RenderEditable with offsets from the previous source.
    return _regions[position]?._boxes[row];
  }

  double? measuredOrigin(RegionPosition position) {
    var top = 0.0;
    for (final source in _document?.regions ?? const <_DocumentRegion>[]) {
      if (source.position == position) return top;
      final measured = _measuredRegion(source.position);
      if (measured == null) return null;
      top += measured.height;
    }
    return null;
  }

  void update(_DocumentRegion source, RenderEditable render) {
    final previous = _regions[source.position];
    if (previous != null &&
        identical(previous.render, render) &&
        identical(previous.source, source) &&
        previous.matches(render)) {
      return;
    }
    _regions[source.position] = _RegionTextLayout(source, render);
    notifyListeners();
  }

  double origin(RegionPosition position) {
    var top = 0.0;
    for (final source in _document?.regions ?? const <_DocumentRegion>[]) {
      if (source.position == position) break;
      top += _regions[source.position]?.height ?? 0;
    }
    return top;
  }

  double get height => (_document?.regions ?? const <_DocumentRegion>[]).fold(
      0.0, (sum, source) => sum + (_regions[source.position]?.height ?? 0));

  Rect? boxForLine(int line) {
    for (final source in _document?.regions ?? const <_DocumentRegion>[]) {
      final row = line - source.firstLine + 1;
      if (row >= 0 && row < source.lineCount) {
        return box(source.position, row)
            ?.shift(Offset(0, origin(source.position)));
      }
    }
    return null;
  }

  int? lineAt(double y) {
    final sources = _document?.regions ?? const <_DocumentRegion>[];
    for (final source in sources) {
      final measured = _regions[source.position];
      if (measured == null) return null;
      final local = y - origin(source.position);
      if (local < measured.height || identical(source, sources.last)) {
        final current = region(source.position);
        final row = current?.rowAt(local) ?? measured.cachedRowAt(local);
        return row == null ? null : source.firstLine - 1 + row;
      }
    }
    return null;
  }
}

class _RegionTextLayout {
  _RegionTextLayout(this.source, this.render)
      : size = render.size,
        textStyle = render.text?.style,
        scaler = render.textScaler,
        strut = render.strutStyle;
  final _DocumentRegion source;
  final RenderEditable render;
  final Size size;
  final TextStyle? textStyle;
  final TextScaler scaler;
  final StrutStyle? strut;
  // Inline tab placeholders are rebuilt as equivalent widgets. They can
  // invalidate Flutter's internal line-metrics identity without changing any
  // line boxes. Compare the actual layout inputs, not that transient identity.
  bool matches(RenderEditable next) =>
      size == next.size &&
      textStyle == next.text?.style &&
      scaler == next.textScaler &&
      strut == next.strutStyle;
  final _boxes = <int, Rect>{};
  double get height => size.height;

  Rect box(int row) {
    final cached = _boxes[row];
    if (cached != null) return cached;
    final result = _measureBox(row);
    return _boxes[row] = result;
  }

  int? cachedRowAt(double y) {
    // Cached native boxes keep the gutter aligned with read-only regions
    // whose fields have been disposed by the lazy viewport.
    int? match;
    for (final entry in _boxes.entries) {
      if (entry.value.top <= y &&
          entry.value.bottom > y &&
          (match == null || entry.key < match)) {
        match = entry.key;
      }
    }
    return match;
  }

  Rect _measureBox(int row) {
    final start = source.lineOffsets[row];
    final end = row + 1 < source.lineCount
        ? source.lineOffsets[row + 1]
        : source.text.length;
    final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end));
    if (boxes.isNotEmpty) {
      return Rect.fromLTRB(0, boxes.map((box) => box.top).reduce(math.min),
          size.width, boxes.map((box) => box.bottom).reduce(math.max));
    }
    // A trailing empty row has no selectable glyph or newline. The native
    // collapsed selection endpoint gives its unsnapped bottom position.
    // Caret rectangles snap to global physical pixels and cannot be cached in
    // document coordinates while the field scrolls through fractional offsets.
    final bottom = render
        .getEndpointsForSelection(TextSelection.collapsed(offset: start))
        .single
        .point
        .dy;
    return Rect.fromLTRB(
        0, bottom - render.preferredLineHeight, size.width, bottom);
  }

  int rowAt(double y) {
    // Caret hit testing chooses a character insertion row, which can change
    // before that row's preceding text has fully left the viewport. Fractional
    // line boxes can overlap even with a fixed strut. Find the first native
    // box that still has visible ink instead of using a caret midpoint.
    var low = 0, high = source.lineCount;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (box(middle).bottom <= y) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low.clamp(0, source.lineCount - 1);
  }
}

RenderEditable? _findRenderEditable(BuildContext? context) {
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

class _TextLayoutHost extends StatefulWidget {
  const _TextLayoutHost(
      {required this.layout,
      required this.region,
      required this.controller,
      required this.child});
  final _EditorTextLayout layout;
  final _DocumentRegion region;
  final TextEditingController controller;
  final Widget child;
  @override
  State<_TextLayoutHost> createState() => _TextLayoutHostState();
}

class _TextLayoutHostState extends State<_TextLayoutHost> {
  final _key = GlobalKey();
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_schedule);
  }

  @override
  void didUpdateWidget(_TextLayoutHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_schedule);
      widget.controller.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final render = _findRenderEditable(_key.currentContext);
      if (render != null && render.hasSize) {
        widget.layout.update(widget.region, render);
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, __) {
        _schedule();
        return KeyedSubtree(key: _key, child: widget.child);
      });
  @override
  void dispose() {
    widget.controller.removeListener(_schedule);
    super.dispose();
  }
}
