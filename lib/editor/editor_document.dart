part of 'editor.dart';

class _DocumentRegion {
  _DocumentRegion(this.position, this.text, this.firstLine) {
    final offsets = <int>[0];
    final rows = <String>[];
    final endings = <String>[];
    var start = 0;
    for (final ending in RegExp(r'\r\n|\r|\n').allMatches(text)) {
      rows.add(text.substring(start, ending.start));
      endings.add(ending.group(0)!);
      start = ending.end;
      offsets.add(start);
    }
    rows.add(text.substring(start));
    lines = List.unmodifiable(rows);
    lineOffsets = List.unmodifiable(offsets);
    lineEndings = List.unmodifiable(endings);
  }

  final RegionPosition position;
  final String text;
  final int firstLine;
  late final List<String> lines;
  late final List<int> lineOffsets;
  late final List<String> lineEndings;
  int get lineCount => lines.length;

  /// A physical-line slice without the separator shared with its next region.
  String sliceLines(int from, int to) {
    if (from == to) return '';
    final end = to == lineCount
        ? text.length
        : lineOffsets[to] - lineEndings[to - 1].length;
    return text.substring(lineOffsets[from], end);
  }

  String separatorAt(int boundary) => boundary > 0 && boundary < lineCount
      ? lineEndings[boundary - 1]
      : lineEndings.firstOrNull ?? '\n';

  int lineAtOffset(int offset) {
    var low = 0;
    var high = lineOffsets.length;
    while (low + 1 < high) {
      final middle = (low + high) ~/ 2;
      if (lineOffsets[middle] <= offset) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return firstLine + low;
  }
}

class _EditorDocument {
  _EditorDocument(Map<RegionPosition, String> parts,
      {required bool emptyInner,
      Map<RegionPosition, String> separators = const {}})
      : _separators = Map.unmodifiable(separators) {
    var firstLine = 1;
    final sections = <_DocumentRegion>[];
    for (final part in parts.entries) {
      final region = _DocumentRegion(part.key, part.value, firstLine);
      sections.add(region);
      firstLine += region.lineCount;
    }
    regions = List.unmodifiable(sections);
    lineCount = firstLine - 1;
    insertionLine = emptyInner ? region(RegionPosition.inner).firstLine : null;
    analysisText = _join(regions);
    sourceText = _join(regions.where(
        (region) => !emptyInner || region.position != RegionPosition.inner));
  }

  late final List<_DocumentRegion> regions;
  late final int lineCount;
  late final int? insertionLine;
  int? get virtualAnalysisLine =>
      insertionLine == null ? null : insertionLine! - 1;
  late final String sourceText;
  late final String analysisText;
  final Map<RegionPosition, String> _separators;

  String separatorAfter(RegionPosition position) =>
      _separators[position] ?? '\n';

  String _join(Iterable<_DocumentRegion> sections) {
    final buffer = StringBuffer();
    _DocumentRegion? previous;
    for (final section in sections) {
      if (previous != null) buffer.write(separatorAfter(previous.position));
      buffer.write(section.text);
      previous = section;
    }
    return buffer.toString();
  }

  int offsetOf(RegionPosition position) {
    var offset = 0;
    for (final section in regions) {
      if (section.position == position) return offset;
      offset += section.text.length + separatorAfter(section.position).length;
    }
    return offset;
  }

  _DocumentRegion region(RegionPosition position) =>
      regions.firstWhere((region) => region.position == position);

  int? toFileLine(int visualLine) {
    final insertion = insertionLine;
    if (insertion == null || visualLine < insertion) return visualLine;
    return visualLine == insertion ? null : visualLine - 1;
  }
}
