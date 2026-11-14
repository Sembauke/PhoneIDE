part of 'editor.dart';

class _LineIndentation {
  const _LineIndentation(this.prefix, this.offsets, {this.isBlank = false});

  final String prefix;
  final List<int> offsets;
  final bool isBlank;

  static _LineIndentation fromLine(String line, int indentSize) {
    var index = 0;
    var column = 0;
    var levelStart = 0;
    final offsets = <int>[];
    while (index < line.length) {
      final character = line.codeUnitAt(index);
      if (character != 32 && character != 9) break;
      column += character == 9 ? indentSize - column % indentSize : 1;
      index++;
      if (column % indentSize == 0) {
        offsets.add(levelStart);
        levelStart = index;
      }
    }
    final isBlank = index == line.length ||
        (index == line.length - 1 && line.codeUnitAt(index) == 13);
    return _LineIndentation(line.substring(0, index), offsets,
        isBlank: isBlank);
  }
}

class _IndentGuideSegment {
  const _IndentGuideSegment(this.x, this.firstRow, this.endRow);

  final double x;
  final int firstRow;
  final int endRow;
}

class _IndentGuideCache {
  _EditorDocument? _document;
  int? _indentSize;
  String? _language;
  TextStyle? _style;
  TextScaler? _scaler;
  Map<RegionPosition, List<_IndentGuideSegment>> _segments = const {};
  final _prefixWidths = <String, List<double>>{};

  Map<RegionPosition, List<_IndentGuideSegment>> measure(
      _EditorDocument document,
      int indentSize,
      String language,
      TextStyle style,
      TextScaler scaler) {
    if (identical(document, _document) &&
        indentSize == _indentSize &&
        language == _language &&
        style == _style &&
        scaler == _scaler) {
      return _segments;
    }
    if (_style != style || _scaler != scaler) _prefixWidths.clear();

    final lines = [
      for (final region in document.regions) ...region.lines,
    ];
    final rows = [
      for (final line in lines) _LineIndentation.fromLine(line, indentSize),
    ];
    final openings = _blockOpeningLines(lines.join('\n'), language);
    final following = List<_LineIndentation?>.filled(rows.length, null);
    _LineIndentation? next;
    final closesBrace = List<bool>.filled(rows.length, false);
    var nextClosesBrace = false;
    final braceLanguage = const {
      'javascript',
      'js',
      'typescript',
      'ts',
      'java',
      'c',
      'cpp',
      'csharp',
      'dart',
      'css',
      'go',
      'rust'
    }.contains(language.toLowerCase());
    for (var row = rows.length - 1; row >= 0; row--) {
      following[row] = next;
      closesBrace[row] = nextClosesBrace;
      if (!rows[row].isBlank) {
        next = rows[row];
        nextClosesBrace = lines[row].trimLeft().startsWith('}');
      }
    }
    _LineIndentation? previous;
    for (var row = 0; row < rows.length; row++) {
      final indentation = rows[row];
      if (!indentation.isBlank) {
        previous = indentation;
        if (openings.contains(row)) {
          final unit =
              indentation.prefix.contains('\t') ? '\t' : ' ' * indentSize;
          previous =
              _LineIndentation.fromLine(indentation.prefix + unit, indentSize);
        }
        continue;
      }
      // Blank whitespace is not a new block. Use the surrounding code, including
      // the body of an opening block, and stop guides at a following dedent.
      final depth = math.min(
          previous?.offsets.length ?? 0,
          braceLanguage && closesBrace[row]
              ? (following[row]?.offsets.length ?? 0) + 1
              : following[row]?.offsets.length ??
                  previous?.offsets.length ??
                  0);
      rows[row] = _LineIndentation(
          previous?.prefix ?? '', previous?.offsets.take(depth).toList() ?? [],
          isBlank: true);
    }

    final strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true);
    final usedPrefixes = <String>{};
    final result = <RegionPosition, List<_IndentGuideSegment>>{};
    for (final region in document.regions) {
      final segments = <_IndentGuideSegment>[];
      final starts = <double, int>{};
      for (var row = 0; row < region.lineCount; row++) {
        final indentation = rows[region.firstLine - 1 + row];
        usedPrefixes.add(indentation.prefix);
        final positions = _prefixWidths.putIfAbsent(indentation.prefix, () {
          if (indentation.prefix.isEmpty) return const [];
          final painter = _layoutText(indentation.prefix, style, scaler, strut);
          // Measure every whitespace boundary so a blank row can reuse this
          // prefix at a shallower depth, including when it contains tabs.
          final widths = [
            for (var offset = 0; offset < indentation.prefix.length; offset++)
              _contentPadding +
                  painter
                      .getOffsetForCaret(
                          TextPosition(offset: offset), Rect.zero)
                      .dx,
          ];
          painter.dispose();
          return widths;
        });
        final xs = {
          for (final offset in indentation.offsets) positions[offset],
        };
        for (final x in starts.keys.toList()) {
          if (!xs.contains(x)) {
            segments.add(_IndentGuideSegment(x, starts.remove(x)!, row));
          }
        }
        for (final x in xs) {
          starts.putIfAbsent(x, () => row);
        }
      }
      for (final entry in starts.entries) {
        segments
            .add(_IndentGuideSegment(entry.key, entry.value, region.lineCount));
      }
      result[region.position] = List.unmodifiable(segments);
    }
    _document = document;
    _indentSize = indentSize;
    _language = language;
    _style = style;
    _scaler = scaler;
    _prefixWidths.removeWhere((prefix, _) => !usedPrefixes.contains(prefix));
    return _segments = Map.unmodifiable(result);
  }
}

class _IndentGuidePainter extends CustomPainter {
  _IndentGuidePainter({
    required this.segments,
    required this.layout,
    required this.region,
    required this.color,
  }) : super(repaint: layout);

  final List<_IndentGuideSegment> segments;
  final _EditorTextLayout layout;
  final _DocumentRegion region;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final measured = layout.region(region.position);
    if (measured == null) {
      canvas.restore();
      return;
    }
    for (final segment in segments) {
      canvas.drawRect(
          Rect.fromLTRB(segment.x, measured.box(segment.firstRow).top,
              segment.x + 1, measured.box(segment.endRow - 1).bottom),
          paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IndentGuidePainter oldDelegate) =>
      !identical(segments, oldDelegate.segments) ||
      layout != oldDelegate.layout ||
      region != oldDelegate.region ||
      color != oldDelegate.color;
}
