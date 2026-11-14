import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

enum PythonLineKind { code, blank, comment, continuation, stringInterior }

class PythonIndentOptions {
  const PythonIndentOptions({
    this.indentSize = 4,
    this.tabWidth = 8,
    this.usesTabs = false,
    this.projectIndentSize,
    this.projectTabWidth,
    this.projectUsesTabs,
    this.baseIndent = 0,
    this.maxDepth = 100,
    this.notebook = false,
  })  : assert(indentSize > 0),
        assert(tabWidth > 0),
        assert(projectIndentSize == null || projectIndentSize > 0),
        assert(projectTabWidth == null || projectTabWidth > 0),
        assert(maxDepth > 0),
        assert(baseIndent >= 0);

  final int indentSize;
  final int tabWidth;
  final bool usesTabs;
  final int? projectIndentSize;
  final int? projectTabWidth;
  final bool? projectUsesTabs;
  final int baseIndent;
  final int maxDepth;
  final bool notebook;
  int get effectiveTabWidth => projectTabWidth ?? tabWidth;

  @override
  bool operator ==(Object other) =>
      other is PythonIndentOptions &&
      indentSize == other.indentSize &&
      tabWidth == other.tabWidth &&
      usesTabs == other.usesTabs &&
      projectIndentSize == other.projectIndentSize &&
      projectTabWidth == other.projectTabWidth &&
      projectUsesTabs == other.projectUsesTabs &&
      baseIndent == other.baseIndent &&
      maxDepth == other.maxDepth &&
      notebook == other.notebook;
  @override
  int get hashCode => Object.hash(
      indentSize,
      tabWidth,
      usesTabs,
      projectIndentSize,
      projectTabWidth,
      projectUsesTabs,
      baseIndent,
      maxDepth,
      notebook);
}

int pythonIndentColumns(String prefix, {int tabWidth = 8}) {
  var column = 0;
  for (final c in prefix.codeUnits) {
    if (c == 32) column++;
    if (c == 9) column += tabWidth - column % tabWidth;
    if (c == 12) column = 0;
  }
  return column;
}

class PythonIndentDiagnostic {
  const PythonIndentDiagnostic(
      this.code, this.startOffset, this.endOffset, this.message);
  final String code;
  final int startOffset;
  final int endOffset;
  final String message;
}

class PythonBlock {
  const PythonBlock(
      {required this.id,
      required this.parentId,
      required this.headerStartLine,
      required this.headerEndLine,
      required this.bodyStartLine,
      required this.endLine,
      required this.guideColumn,
      required this.displayGuideColumn,
      required this.bodyColumn,
      required this.keyword});
  final int id;
  final int? parentId;
  final int headerStartLine;
  final int headerEndLine;
  final int bodyStartLine;
  final int endLine;
  final int guideColumn;
  final int displayGuideColumn;
  final int bodyColumn;
  final String keyword;
}

class PythonLineInfo {
  PythonLineInfo(
      {required this.text,
      required this.startOffset,
      required this.endOffset,
      required this.leadingWhitespaceEnd,
      required this.indentPrefix,
      required this.kind,
      required this.logicalStartLine,
      required this.indentColumn,
      required this.displayIndentColumn,
      required this.guideColumns,
      required this.displayGuideColumns,
      required this.stackColumns,
      required this.opensBlock,
      required this.headerEndLine,
      required this.activeBlockId,
      required this.nearestCodeAbove,
      required this.nearestCodeBelow,
      required this.endState,
      required this.diagnostics,
      required this.blockIds,
      required this.keyword});
  final String text;
  final int startOffset;
  final int endOffset;
  final int leadingWhitespaceEnd;
  final String indentPrefix;
  final PythonLineKind kind;
  final int logicalStartLine;
  final int indentColumn;
  final int displayIndentColumn;
  final List<int> guideColumns;
  final List<int> displayGuideColumns;
  final List<int> stackColumns;
  final bool opensBlock;
  final int headerEndLine;
  final int? activeBlockId;
  final int nearestCodeAbove;
  final int nearestCodeBelow;
  final PythonLexState endState;
  final List<PythonIndentDiagnostic> diagnostics;
  final List<int> blockIds;
  final String keyword;
}

/// Sizes of the model's actual numeric buffers, excluding source text, blocks,
/// sparse diagnostics and synthetic token strings (not a retained-heap estimate).
class PythonIndentStorageStats {
  const PythonIndentStorageStats(
      this.lineBytes,
      this.recordBytes,
      this.vectorBytes,
      this.codeIndexBytes,
      this.lexicalBytes,
      this.recordCount,
      this.lexicalStateCount);
  final int lineBytes;
  final int recordBytes;
  final int vectorBytes;
  final int codeIndexBytes;
  final int lexicalBytes;
  final int recordCount;
  final int lexicalStateCount;
  int get numericBytes =>
      lineBytes + recordBytes + vectorBytes + codeIndexBytes + lexicalBytes;
}

class PythonCaretContext {
  const PythonCaretContext(
      {required this.lineStartOffset,
      required this.lineEndOffset,
      required this.leadingWhitespaceEnd,
      required this.indentPrefix,
      required this.kind,
      required this.inString,
      required this.inComment,
      required this.opensBlock,
      required this.terminalStatement,
      required this.bracketDepth,
      required this.explicitContinuation,
      required this.indentColumn,
      required this.displayIndentColumn,
      required this.logicalIndentColumn,
      required this.indentStops,
      required Map<String, int> clauseTargets})
      : _clauseTargets = clauseTargets;
  final int lineStartOffset;
  final int lineEndOffset;
  final int leadingWhitespaceEnd;
  final String indentPrefix;
  final PythonLineKind kind;
  final bool inString;
  final bool inComment;
  final bool opensBlock;
  final bool terminalStatement;
  final int bracketDepth;
  final bool explicitContinuation;
  final int indentColumn;
  final int displayIndentColumn;
  final int logicalIndentColumn;
  final List<int> indentStops;
  final Map<String, int> _clauseTargets;
  bool get isContinuation => bracketDepth > 0 || explicitContinuation;
  int? compatibleClauseTarget(String keyword) => _clauseTargets[keyword];
}

class PythonLexState {
  const PythonLexState._(
      {List<_Mode> modes = const [],
      this.brackets = '',
      this.backslashContinuation = false,
      this.logicalStartLine = -1,
      this.firstWords = const [],
      this.lastToken = '',
      this.comment = false})
      : _modes = modes;
  final List<_Mode> _modes;
  final String brackets;
  final bool backslashContinuation;
  final int logicalStartLine;
  final List<String> firstWords;
  final String lastToken;
  final bool comment;
  int get bracketDepth => brackets.length;
  String? get openString {
    for (final m in _modes.reversed) {
      if (m.kind == _ModeKind.string) return m.quote;
    }
    return null;
  }

  bool get inString => _modes.any((m) => m.kind == _ModeKind.string);
  bool get continued =>
      _modes.isNotEmpty || brackets.isNotEmpty || backslashContinuation;

  /// Whether editing changed the modes that can reclassify following rows.
  /// Token spelling and logical anchors are relevant to incremental lexing,
  /// but must not restart the visual debounce on every ordinary keystroke.
  bool sameContinuationModes(PythonLexState other) =>
      brackets == other.brackets &&
      backslashContinuation == other.backslashContinuation &&
      _same(_modes, other._modes);
  PythonLexState shifted(int delta) => PythonLexState._(
      modes: _modes,
      brackets: brackets,
      backslashContinuation: backslashContinuation,
      logicalStartLine: logicalStartLine < 0 ? -1 : logicalStartLine + delta,
      firstWords: firstWords,
      lastToken: lastToken,
      comment: comment);
  bool same(PythonLexState other, {int lineDelta = 0}) =>
      brackets == other.brackets &&
      backslashContinuation == other.backslashContinuation &&
      (logicalStartLine < 0
              ? logicalStartLine
              : logicalStartLine + lineDelta) ==
          other.logicalStartLine &&
      _same(firstWords, other.firstWords) &&
      lastToken == other.lastToken &&
      _same(_modes, other._modes);
}

enum _ModeKind { string, field, format }

class _Mode {
  const _Mode(this.kind,
      {this.quote = '',
      this.raw = false,
      this.interpolated = false,
      this.baseDepth = 0});
  final _ModeKind kind;
  final String quote;
  final bool raw;
  final bool interpolated;
  final int baseDepth;
  @override
  bool operator ==(Object o) =>
      o is _Mode &&
      kind == o.kind &&
      quote == o.quote &&
      raw == o.raw &&
      interpolated == o.interpolated &&
      baseDepth == o.baseDepth;
  @override
  int get hashCode => Object.hash(kind, quote, raw, interpolated, baseDepth);
}

bool _same<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _SourceLine {
  const _SourceLine(this.text, this.start, this.end, this.next);
  final String text;
  final int start, end, next;
}

List<_SourceLine> _sourceLines(String text) {
  final lines = <_SourceLine>[];
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c != 10 && c != 13) continue;
    final end = i;
    if (c == 13 && i + 1 < text.length && text.codeUnitAt(i + 1) == 10) i++;
    lines.add(_SourceLine(text.substring(start, end), start, end, i + 1));
    start = i + 1;
  }
  lines
      .add(_SourceLine(text.substring(start), start, text.length, text.length));
  return lines;
}

class _RawLine {
  const _RawLine(
      {required this.kind,
      required this.logicalStart,
      required this.before,
      required this.after,
      required this.indentLength,
      required this.column,
      required this.displayColumn,
      required this.alternateColumn,
      required this.opener,
      required this.keyword,
      required this.commentOffset,
      required this.invalidWhitespace,
      required this.structuralStack});
  final PythonLineKind kind;
  final int logicalStart;
  final PythonLexState before, after;
  final int indentLength, column, displayColumn, alternateColumn;
  final bool opener;
  final String keyword;
  final int commentOffset;
  final List<int> invalidWhitespace;
  final List<int> structuralStack;
  _RawLine shifted(int delta) => _RawLine(
      kind: kind,
      logicalStart: logicalStart + delta,
      before: before.shifted(delta),
      after: after.shifted(delta),
      indentLength: indentLength,
      column: column,
      displayColumn: displayColumn,
      alternateColumn: alternateColumn,
      opener: opener,
      keyword: keyword,
      commentOffset: commentOffset,
      invalidWhitespace: invalidWhitespace,
      structuralStack: structuralStack);
}

const _prefixes = {'r', 'u', 'b', 'f', 't', 'br', 'rb', 'fr', 'rf', 'tr', 'rt'};
const _headers = {
  'def',
  'class',
  'if',
  'elif',
  'else',
  'for',
  'while',
  'try',
  'except',
  'finally',
  'with',
  'match',
  'case'
};
bool _nameStart(int c) =>
    c == 95 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c >= 128;
bool _namePart(int c) => _nameStart(c) || c >= 48 && c <= 57;
bool _oddSpace(int c) =>
    c == 0xa0 ||
    c == 0x3000 ||
    c == 0x200b ||
    c == 0x200c ||
    c == 0x200d ||
    c == 0x2060 ||
    c == 0xfeff ||
    c >= 0x2000 && c <= 0x200a;

_RawLine _scan(String text, int line, PythonLexState before,
    PythonIndentOptions options, List<int> previousStack,
    {bool prefixOnly = false, bool virtual = false}) {
  if (virtual && text.isEmpty) {
    // A visual insertion slot has no source newline. In particular it must not
    // consume an explicit continuation or advance an open string's lexer state.
    return _RawLine(
        kind: before.inString
            ? PythonLineKind.stringInterior
            : before.continued
                ? PythonLineKind.continuation
                : PythonLineKind.blank,
        logicalStart: before.continued ? before.logicalStartLine : line,
        before: before,
        after: before,
        indentLength: 0,
        column: 0,
        displayColumn: 0,
        alternateColumn: 0,
        opener: false,
        keyword: '',
        commentOffset: -1,
        invalidWhitespace: const [],
        structuralStack: previousStack);
  }
  var lead = 0;
  final odd = <int>[];
  while (lead < text.length) {
    final c = text.codeUnitAt(lead);
    if (c == 32 || c == 9 || c == 12 || line == 0 && lead == 0 && c == 0xfeff) {
      lead++;
    } else if (_oddSpace(c)) {
      odd.add(lead++);
    } else {
      break;
    }
  }
  final prefix = text.substring(0, lead);
  final column = pythonIndentColumns(prefix);
  final display =
      pythonIndentColumns(prefix, tabWidth: options.effectiveTabWidth);
  final alternate = pythonIndentColumns(prefix, tabWidth: 1);
  final kind = before.inString
      ? PythonLineKind.stringInterior
      : before.continued
          ? PythonLineKind.continuation
          : lead == text.length
              ? PythonLineKind.blank
              : text.codeUnitAt(lead) == 35
                  ? PythonLineKind.comment
                  : PythonLineKind.code;
  final logical = before.continued ? before.logicalStartLine : line;
  final modes = [...before._modes];
  var brackets = before.brackets;
  final words = before.continued ? [...before.firstWords] : <String>[];
  var last = before.continued ? before.lastToken : '';
  var backslash = false;
  var commentOffset = -1;
  var stringEscapedNewline = false;
  var i = line == 0 && text.startsWith('\ufeff') ? 1 : 0;
  // Notebook commands are opaque, non-Python code at this indentation. A
  // shell bracket, quote or backslash must not consume following Python lines.
  final notebookCommand = options.notebook &&
      kind == PythonLineKind.code &&
      lead < text.length &&
      (text[lead] == '%' || text[lead] == '!');
  if (notebookCommand) i = text.length;
  void token(String value) {
    if (modes.isNotEmpty) return;
    if (words.length < 3) words.add(value);
    last = value;
  }

  while (i < text.length) {
    final mode = modes.isEmpty ? null : modes.last;
    final char = text[i];
    if (mode?.kind == _ModeKind.string || mode?.kind == _ModeKind.format) {
      if (mode!.kind == _ModeKind.string && text.startsWith(mode.quote, i)) {
        i += mode.quote.length;
        modes.removeLast();
        continue;
      }
      if (char == '\\' && mode.kind == _ModeKind.string) {
        if (i + 1 == text.length) stringEscapedNewline = true;
        // A backslash can quote a delimiter, but cannot quote an f/t brace.
        if (mode.interpolated &&
            i + 1 < text.length &&
            (text[i + 1] == '{' || text[i + 1] == '}')) {
          i++;
        } else if (!mode.raw && text.startsWith(r'\N{', i)) {
          final end = text.indexOf('}', i + 3);
          i = end < 0 ? text.length : end + 1;
        } else {
          i += math.min(2, text.length - i);
        }
        continue;
      }
      if ((mode.interpolated || mode.kind == _ModeKind.format) && char == '{') {
        if (mode.kind == _ModeKind.string && text.startsWith('{{', i)) {
          i += 2;
          continue;
        }
        modes.add(_Mode(_ModeKind.field, baseDepth: brackets.length));
        i++;
        continue;
      }
      if (char == '}' && mode.kind == _ModeKind.format) {
        modes.removeLast();
        if (modes.isNotEmpty && modes.last.kind == _ModeKind.field) {
          modes.removeLast();
        }
        i++;
        continue;
      }
      if (mode.interpolated && text.startsWith('}}', i)) {
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (char == '#') {
      commentOffset = i;
      break;
    }
    if (char == ' ' ||
        char == '\t' ||
        char == '\f' ||
        _oddSpace(text.codeUnitAt(i))) {
      i++;
      continue;
    }
    if (char == '\\' && i == text.length - 1) {
      backslash = true;
      i++;
      continue;
    }
    if (mode?.kind == _ModeKind.field && brackets.length == mode!.baseDepth) {
      if (char == '}') {
        modes.removeLast();
        i++;
        continue;
      }
      if (char == ':') {
        modes.add(const _Mode(_ModeKind.format));
        i++;
        continue;
      }
    }
    var prefixEnd = i;
    var stringPrefix = '';
    if (_nameStart(text.codeUnitAt(i))) {
      prefixEnd++;
      while (prefixEnd < text.length && _namePart(text.codeUnitAt(prefixEnd))) {
        prefixEnd++;
      }
      final name = text.substring(i, prefixEnd);
      if (prefixEnd < text.length &&
          (text[prefixEnd] == '"' || text[prefixEnd] == "'") &&
          _prefixes.contains(name.toLowerCase())) {
        stringPrefix = name.toLowerCase();
      } else {
        token(name);
        i = prefixEnd;
        continue;
      }
    }
    final quoteAt = stringPrefix.isEmpty ? i : prefixEnd;
    if (text[quoteAt] == '"' || text[quoteAt] == "'") {
      final q = text[quoteAt];
      final quote = text.startsWith(q * 3, quoteAt) ? q * 3 : q;
      token('STRING');
      modes.add(_Mode(_ModeKind.string,
          quote: quote,
          raw: stringPrefix.contains('r'),
          interpolated:
              stringPrefix.contains('f') || stringPrefix.contains('t')));
      i = quoteAt + quote.length;
      continue;
    }
    if ('([{'.contains(char)) {
      token(char);
      brackets += char;
      i++;
      continue;
    }
    if (')]}'.contains(char)) {
      token(char);
      if (brackets.isNotEmpty) {
        brackets = brackets.substring(0, brackets.length - 1);
      }
      i++;
      continue;
    }
    if (i + 1 < text.length &&
        const {':=', '==', '!=', '<=', '>='}
            .contains(text.substring(i, i + 2))) {
      token(text.substring(i, i + 2));
      i += 2;
      continue;
    }
    token(char);
    i++;
  }
  var keyword = words.isEmpty ? '' : words.first;
  if (keyword == 'async' && words.length > 1) keyword = words[1];
  final continued = modes.isNotEmpty || brackets.isNotEmpty || backslash;
  final opener = !continued && last == ':' && _headers.contains(keyword);
  if (!prefixOnly &&
      modes.isNotEmpty &&
      modes.last.kind == _ModeKind.string &&
      modes.last.quote.length == 1 &&
      !stringEscapedNewline) {
    modes.removeLast();
  }
  final staysOpen = modes.isNotEmpty || brackets.isNotEmpty || backslash;
  final after = PythonLexState._(
      modes: List.unmodifiable(modes),
      brackets: brackets,
      backslashContinuation: backslash,
      logicalStartLine: staysOpen ? logical : -1,
      firstWords: staysOpen || prefixOnly ? List.unmodifiable(words) : const [],
      lastToken: staysOpen || prefixOnly ? last : '',
      comment: commentOffset >= 0);
  var stack = previousStack;
  if (kind == PythonLineKind.code) {
    final next = [...stack];
    while (next.length > 1 && column < next.last) {
      next.removeLast();
    }
    if (next.length == 1 && column < next.first) next[0] = column;
    if (column > next.last && next.length <= options.maxDepth) next.add(column);
    if (!_same(next, stack)) stack = List.unmodifiable(next);
  }
  return _RawLine(
      kind: kind,
      logicalStart: logical,
      before: before,
      after: after,
      indentLength: lead,
      column: column,
      displayColumn: display,
      alternateColumn: alternate,
      opener: opener,
      keyword: keyword,
      commentOffset: commentOffset,
      invalidWhitespace: List.unmodifiable(odd),
      structuralStack: stack);
}

class _BlockBuilder {
  _BlockBuilder(this.id, this.parent, this.headerStart, this.headerEnd,
      this.bodyStart, this.guide, this.displayGuide, this.body, this.keyword);
  final int id, headerStart, headerEnd, bodyStart, guide, displayGuide, body;
  final int? parent;
  final String keyword;
  int end = -1;
  PythonBlock freeze() => PythonBlock(
      id: id,
      parentId: parent,
      headerStartLine: headerStart,
      headerEndLine: headerEnd,
      bodyStartLine: bodyStart,
      endLine: end,
      guideColumn: guide,
      displayGuideColumn: displayGuide,
      bodyColumn: body,
      keyword: keyword);
}

class _Level {
  const _Level(this.column, this.display, this.alternate, this.block);
  final int column, display, alternate;
  final int? block;
}

// Source and line metadata live in numeric buffers. Public line objects are
// short-lived views: neither source substrings nor PythonLineInfo/_RawLine
// objects are retained once construction finishes. Repeated lexical/indent
// records share a table entry; block chains are represented by their last ID.
// There are four 32-bit slots per line (start, record, scope, lexer state), plus
// the sorted code-line index used for logarithmic nearest-code lookup.
class _PackedPythonLines extends ListBase<PythonLineInfo> {
  _PackedPythonLines(
      this.text,
      this.options,
      List<_SourceLine> source,
      List<_RawLine> raw,
      List<List<int>> blockIds,
      Map<int, int> headerEnds,
      Map<int, List<PythonIndentDiagnostic>> diagnostics,
      this.blocks)
      : _starts = Uint32List(source.length + 1),
        _recordIds = Uint32List(source.length),
        _lexicalIds = Uint32List(source.length + 1),
        _scopes = Int32List(source.length) {
    final records = <int>[];
    final recordIds = <_NumericKey, int>{};
    final vectors = _VectorPool();
    final states = _LexicalPool(text, source);
    final codeRows = <int>[];
    for (var row = 0; row < source.length; row++) {
      final line = raw[row];
      if (row == 0) {
        _lexicalIds[0] = states.intern(line.before, row, line.logicalStart);
      }
      _lexicalIds[row + 1] = states.intern(line.after, row, line.logicalStart);
      _starts[row] = source[row].start;
      _scopes[row] = blockIds[row].isEmpty ? -1 : blockIds[row].last;
      if (line.kind == PythonLineKind.code) codeRows.add(row);
      if (diagnostics[row]?.isNotEmpty ?? false) {
        _diagnostics[row] = List.unmodifiable(diagnostics[row]!);
      }
      final origin = source[line.logicalStart.clamp(0, row)].text;
      var keywordOffset = origin.indexOf(line.keyword);
      if (keywordOffset < 0) {
        final id = states.tokens.intern(line.keyword, row, line.logicalStart);
        keywordOffset = -id - 1;
      }
      final record = <int>[
        line.kind.index,
        line.indentLength,
        line.column,
        line.displayColumn,
        line.alternateColumn,
        line.opener ? 1 : 0,
        keywordOffset,
        line.keyword.length,
        line.commentOffset,
        vectors.intern(line.invalidWhitespace),
        vectors.intern(line.structuralStack),
        headerEnds.containsKey(row) ? headerEnds[row]! - row : -1,
      ];
      _recordIds[row] = recordIds.putIfAbsent(_NumericKey(record), () {
        final id = records.length ~/ _stride;
        records.addAll(record);
        return id;
      });
    }
    _starts[source.length] = text.length;
    _records = Int32List.fromList(records);
    _vectors = vectors.freeze();
    _states = states.freeze();
    _codeRows = Uint32List.fromList(codeRows);
  }

  static const _stride = 12;
  final String text;
  final PythonIndentOptions options;
  final List<PythonBlock> blocks;
  final Uint32List _starts;
  final Uint32List _recordIds;
  final Uint32List _lexicalIds;
  final Int32List _scopes;
  late final Int32List _records;
  late final _PackedVectors _vectors;
  late final _PackedLexicalStates _states;
  late final Uint32List _codeRows;
  final Map<int, List<PythonIndentDiagnostic>> _diagnostics = {};

  PythonIndentStorageStats get storageStats => PythonIndentStorageStats(
      _starts.lengthInBytes +
          _recordIds.lengthInBytes +
          _scopes.lengthInBytes +
          _lexicalIds.lengthInBytes,
      _records.lengthInBytes,
      _vectors.bytes,
      _codeRows.lengthInBytes,
      _states.bytes,
      _records.length ~/ _stride,
      _states.length);

  int _value(int row, int field) => _records[_recordIds[row] * _stride + field];
  int _end(int row) {
    var end = _starts[row + 1];
    if (row + 1 == length) return end;
    if (end > _starts[row] && text.codeUnitAt(end - 1) == 10) end--;
    if (end > _starts[row] && text.codeUnitAt(end - 1) == 13) end--;
    return end;
  }

  String _text(int row) => text.substring(_starts[row], _end(row));
  int _logicalStart(int row) {
    final kind = PythonLineKind.values[_value(row, 0)];
    return kind == PythonLineKind.continuation ||
            kind == PythonLineKind.stringInterior
        ? _nearestCode(row, above: true).clamp(0, row)
        : row;
  }

  String _keyword(int row) {
    final offset = _value(row, 6);
    if (offset < 0) return _states.tokens.at(-offset - 1);
    final start = _starts[_logicalStart(row).clamp(0, row)] + offset;
    return text.substring(start, start + _value(row, 7));
  }

  PythonLexState _state(int row, {bool before = false}) =>
      _states.at(_lexicalIds[before ? row : row + 1], _logicalStart(row));
  List<int> _blockIds(int row) {
    final result = <int>[];
    int? id = _scopes[row];
    while (id != null && id >= 0) {
      result.add(id);
      id = blocks[id].parentId;
    }
    return List.unmodifiable(result.reversed);
  }

  int? _activeBlock(int row) {
    var low = 0, high = blocks.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (blocks[mid].headerStartLine <= row) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0 && blocks[low - 1].headerEndLine >= row) return low - 1;
    return _scopes[row] < 0 ? null : _scopes[row];
  }

  int _nearestCode(int row, {required bool above}) {
    var low = 0, high = _codeRows.length;
    final target = above ? row : row + 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_codeRows[mid] < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final index = above ? low - 1 : low;
    return index < 0 || index >= _codeRows.length ? -1 : _codeRows[index];
  }

  _RawLine _raw(int row) => _RawLine(
      kind: PythonLineKind.values[_value(row, 0)],
      logicalStart: _logicalStart(row),
      before: _state(row, before: true),
      after: _state(row),
      indentLength: _value(row, 1),
      column: _value(row, 2),
      displayColumn: _value(row, 3),
      alternateColumn: _value(row, 4),
      opener: _value(row, 5) != 0,
      keyword: _keyword(row),
      commentOffset: _value(row, 8),
      invalidWhitespace: _vectors.at(_value(row, 9)),
      structuralStack: _vectors.at(_value(row, 10)));
  @override
  int get length => _recordIds.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable Python model');
  @override
  PythonLineInfo operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _PackedLineInfo(this, index);
  }

  @override
  void operator []=(int index, PythonLineInfo value) =>
      throw UnsupportedError('Immutable Python model');
}

class _PackedLineInfo implements PythonLineInfo {
  const _PackedLineInfo(this._data, this._row);
  final _PackedPythonLines _data;
  final int _row;
  @override
  String get text => _data._text(_row);
  @override
  int get startOffset => _data._starts[_row];
  @override
  int get endOffset => _data._end(_row);
  @override
  int get leadingWhitespaceEnd => startOffset + _data._value(_row, 1);
  @override
  String get indentPrefix =>
      _data.text.substring(startOffset, leadingWhitespaceEnd);
  @override
  PythonLineKind get kind => PythonLineKind.values[_data._value(_row, 0)];
  @override
  int get logicalStartLine => _data._logicalStart(_row);
  @override
  int get indentColumn => _data._value(_row, 2);
  @override
  int get displayIndentColumn => _data._value(_row, 3);
  @override
  List<int> get guideColumns =>
      List.unmodifiable(blockIds.map((id) => _data.blocks[id].guideColumn));
  @override
  List<int> get displayGuideColumns => List.unmodifiable(
      blockIds.map((id) => _data.blocks[id].displayGuideColumn));
  @override
  List<int> get stackColumns => List.unmodifiable([
        _data._vectors.at(_data._value(_row, 10)).first,
        for (final id in blockIds) _data.blocks[id].bodyColumn
      ]);
  @override
  bool get opensBlock => _data._value(_row, 11) >= 0;
  @override
  int get headerEndLine => opensBlock ? _row + _data._value(_row, 11) : -1;
  @override
  int? get activeBlockId => _data._activeBlock(_row);
  @override
  int get nearestCodeAbove => _data._nearestCode(_row, above: true);
  @override
  int get nearestCodeBelow => _data._nearestCode(_row, above: false);
  @override
  PythonLexState get endState => _data._state(_row);
  @override
  List<PythonIndentDiagnostic> get diagnostics =>
      _data._diagnostics[_row] ?? const [];
  @override
  List<int> get blockIds => _data._blockIds(_row);
  @override
  String get keyword => _data._keyword(_row);
}

class _NumericKey {
  _NumericKey(this.values) : _hash = Object.hashAll(values);
  final List<int> values;
  final int _hash;
  @override
  int get hashCode => _hash;
  @override
  bool operator ==(Object other) =>
      other is _NumericKey && _same(values, other.values);
}

// Lexical states also use compact records. Tokens refer to source slices;
// only synthetic lexer tokens (for example STRING or a bracket stack assembled
// across lines) need separate strings. Interning maps are construction scratch
// space and are discarded with the builder.
class _LexicalPool {
  _LexicalPool(String text, List<_SourceLine> source)
      : tokens = _TokenPool(text, source);
  final _TokenPool tokens;
  final _VectorPool _vectors = _VectorPool();
  final _records = <int>[];
  final _ids = <_NumericKey, int>{};
  int intern(PythonLexState state, int row, int logicalStart) {
    int token(String value) => tokens.intern(value, row, logicalStart);
    final words = _vectors.intern(state.firstWords.map(token).toList());
    final modes = _vectors.intern([
      for (final mode in state._modes) ...[
        mode.kind.index,
        token(mode.quote),
        mode.raw ? 1 : 0,
        mode.interpolated ? 1 : 0,
        mode.baseDepth,
      ],
    ]);
    final record = [
      token(state.brackets),
      (state.backslashContinuation ? 1 : 0) |
          (state.logicalStartLine >= 0 ? 2 : 0) |
          (state.comment ? 4 : 0),
      words,
      token(state.lastToken),
      modes
    ];
    return _ids.putIfAbsent(_NumericKey(record), () {
      final id = _records.length ~/ 5;
      _records.addAll(record);
      return id;
    });
  }

  _PackedLexicalStates freeze() => _PackedLexicalStates(
      Int32List.fromList(_records), _vectors.freeze(), tokens.freeze());
}

class _PackedLexicalStates {
  const _PackedLexicalStates(this.records, this.vectors, this.tokens);
  final Int32List records;
  final _PackedVectors vectors;
  final _PackedTokens tokens;
  int get length => records.length ~/ 5;
  int get bytes => records.lengthInBytes + vectors.bytes + tokens.bytes;
  PythonLexState at(int id, int logicalStart) {
    final offset = id * 5, flags = records[offset + 1];
    if (flags & 3 == 0 &&
        tokens.isEmpty(records[offset]) &&
        vectors.isEmpty(records[offset + 2]) &&
        tokens.isEmpty(records[offset + 3]) &&
        vectors.isEmpty(records[offset + 4])) {
      return flags & 4 == 0
          ? const PythonLexState._()
          : const PythonLexState._(comment: true);
    }
    final modes = vectors.at(records[offset + 4]);
    return PythonLexState._(
      brackets: tokens.at(records[offset]),
      backslashContinuation: flags & 1 != 0,
      logicalStartLine: flags & 2 != 0 ? logicalStart : -1,
      firstWords:
          List.unmodifiable(vectors.at(records[offset + 2]).map(tokens.at)),
      lastToken: tokens.at(records[offset + 3]),
      comment: flags & 4 != 0,
      modes: List.unmodifiable([
        for (var i = 0; i < modes.length; i += 5)
          _Mode(_ModeKind.values[modes[i]],
              quote: tokens.at(modes[i + 1]),
              raw: modes[i + 2] != 0,
              interpolated: modes[i + 3] != 0,
              baseDepth: modes[i + 4]),
      ]),
    );
  }
}

class _TokenPool {
  _TokenPool(this.text, this.source);
  final String text;
  final List<_SourceLine> source;
  final _ids = <String, int>{};
  final _spans = <int>[];
  final _synthetic = <String>[];
  int intern(String value, int row, int logicalStart) =>
      _ids.putIfAbsent(value, () {
        final id = _spans.length ~/ 2;
        var offset = source[row].text.indexOf(value);
        if (offset >= 0) {
          offset += source[row].start;
        } else {
          final origin = source[logicalStart.clamp(0, row)];
          offset = origin.text.indexOf(value);
          if (offset >= 0) offset += origin.start;
        }
        if (offset < 0) {
          _synthetic.add(value);
          offset = -_synthetic.length;
        }
        _spans.addAll([offset, value.length]);
        return id;
      });
  _PackedTokens freeze() => _PackedTokens(
      text, Int32List.fromList(_spans), List.unmodifiable(_synthetic));
}

class _PackedTokens {
  const _PackedTokens(this.text, this.spans, this.synthetic);
  final String text;
  final Int32List spans;
  final List<String> synthetic;
  int get bytes => spans.lengthInBytes;
  bool isEmpty(int id) => spans[id * 2 + 1] == 0;
  String at(int id) {
    final offset = spans[id * 2];
    return offset < 0
        ? synthetic[-offset - 1]
        : text.substring(offset, offset + spans[id * 2 + 1]);
  }
}

class _VectorPool {
  final _ids = <_NumericKey, int>{};
  final _offsets = <int>[];
  final _values = <int>[];
  int intern(List<int> values) => _ids.putIfAbsent(_NumericKey(values), () {
        final id = _offsets.length;
        _offsets.add(_values.length);
        _values.addAll(values);
        return id;
      });
  _PackedVectors freeze() => _PackedVectors(
      Uint32List.fromList([..._offsets, _values.length]),
      Int32List.fromList(_values));
}

class _PackedVectors {
  const _PackedVectors(this.offsets, this.values);
  final Uint32List offsets;
  final Int32List values;
  int get bytes => offsets.lengthInBytes + values.lengthInBytes;
  bool isEmpty(int id) => offsets[id] == offsets[id + 1];
  List<int> at(int id) => isEmpty(id)
      ? const []
      : UnmodifiableListView(
          Int32List.sublistView(values, offsets[id], offsets[id + 1]));
}

class _SourceLineView extends ListBase<_SourceLine> {
  _SourceLineView(this.data);
  final _PackedPythonLines data;
  @override
  int get length => data.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable Python model');
  @override
  _SourceLine operator [](int index) => _SourceLine(data._text(index),
      data._starts[index], data._end(index), data._starts[index + 1]);
  @override
  void operator []=(int index, _SourceLine value) =>
      throw UnsupportedError('Immutable Python model');
}

class _RawLineView extends ListBase<_RawLine> {
  _RawLineView(this.data);
  final _PackedPythonLines data;
  @override
  int get length => data.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable Python model');
  @override
  _RawLine operator [](int index) => data._raw(index);
  @override
  void operator []=(int index, _RawLine value) =>
      throw UnsupportedError('Immutable Python model');
}

class PythonIndentModel {
  PythonIndentModel._(
      this.text,
      this.options,
      this._source,
      this._raw,
      this._lines,
      this.blocks,
      this.effectiveIndentSize,
      this.usesTabs,
      this.hasMixedIndentWidths,
      this.virtualLine);

  factory PythonIndentModel.analyze(String text,
      {PythonIndentOptions options = const PythonIndentOptions(),
      int? virtualLine}) {
    final source = _sourceLines(text);
    virtualLine = _validVirtualLine(source, virtualLine);
    final raw = <_RawLine>[];
    var state = const PythonLexState._();
    var stack = <int>[options.baseIndent];
    for (var i = 0; i < source.length; i++) {
      final line = _scan(source[i].text, i, state, options, stack,
          virtual: i == virtualLine);
      raw.add(line);
      state = line.after;
      stack = line.structuralStack;
    }
    return PythonIndentModel._build(text, options, source, raw, virtualLine);
  }

  /// Processes lexical state in bounded batches. Call in a background isolate;
  /// the final structural projection remains one linear pass in that isolate.
  static Future<PythonIndentModel> analyzeInChunks(String text,
      {PythonIndentOptions options = const PythonIndentOptions(),
      int? virtualLine,
      int chunkSize = 512,
      void Function(int)? onChunk}) async {
    if (chunkSize < 1) throw ArgumentError.value(chunkSize, 'chunkSize');
    final source = _sourceLines(text);
    virtualLine = _validVirtualLine(source, virtualLine);
    final raw = <_RawLine>[];
    var state = const PythonLexState._();
    var stack = <int>[options.baseIndent];
    for (var start = 0; start < source.length; start += chunkSize) {
      final end = math.min(source.length, start + chunkSize);
      for (var row = start; row < end; row++) {
        final line = _scan(source[row].text, row, state, options, stack,
            virtual: row == virtualLine);
        raw.add(line);
        state = line.after;
        stack = line.structuralStack;
      }
      onChunk?.call(end - start);
      if (onChunk != null && end < source.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return PythonIndentModel._build(text, options, source, raw, virtualLine);
  }

  final String text;
  final PythonIndentOptions options;
  final _SourceLineView _source;
  final _RawLineView _raw;
  final _PackedPythonLines _lines;
  List<PythonLineInfo> get lines => _lines;
  PythonIndentStorageStats get storageStats => _lines.storageStats;
  final List<PythonBlock> blocks;
  final int effectiveIndentSize;
  final bool usesTabs;
  final bool hasMixedIndentWidths;

  /// Zero-based visual insertion row absent from the actual source document.
  final int? virtualLine;
  String get indentUnit => usesTabs ? '\t' : ' ' * effectiveIndentSize;

  static PythonIndentModel _build(String text, PythonIndentOptions options,
      List<_SourceLine> source, List<_RawLine> raw, int? virtualLine) {
    final count = raw.length;
    final builders = <_BlockBuilder>[];
    final levels = <_Level>[
      _Level(options.baseIndent, options.baseIndent, options.baseIndent, null)
    ];
    final ids = List<List<int>>.filled(count, const []);
    final diagnostics = <int, List<PythonIndentDiagnostic>>{};
    final above = List<int>.filled(count, -1),
        below = List<int>.filled(count, -1);
    final headerBlocks = <int, int>{};
    final headerEnds = <int, int>{};
    final increases = <int, int>{};
    var tabLines = 0, spaceLines = 0;
    var previousCode = -1, pendingHeader = -1;
    var currentIds = const <int>[];
    void diagnose(int row, String code, String message) {
      (diagnostics[row] ??= []).add(PythonIndentDiagnostic(
          code,
          source[row].start,
          source[row].start + raw[row].indentLength,
          message));
    }

    for (var row = 0; row < count; row++) {
      final line = raw[row];
      above[row] = previousCode;
      for (final offset in line.kind == PythonLineKind.stringInterior
          ? const <int>[]
          : line.invalidWhitespace) {
        (diagnostics[row] ??= []).add(PythonIndentDiagnostic(
            'invalidWhitespace',
            source[row].start + offset,
            source[row].start + offset + 1,
            'This character is not Python indentation.'));
      }
      if (line.kind == PythonLineKind.code) {
        final prefix = source[row].text.substring(0, line.indentLength);
        if (prefix.contains('\t')) {
          tabLines++;
        } else if (line.column > options.baseIndent) {
          spaceLines++;
        }
        if (prefix.contains('\t') && prefix.contains(' ')) {
          diagnose(
              row, 'mixedIndentation', 'Indentation mixes tabs and spaces.');
        }
        if (previousCode >= 0) {
          final increase = line.column - raw[previousCode].column;
          if (increase > 0) {
            increases.update(increase, (v) => v + 1, ifAbsent: () => 1);
          }
        }
        final oldTop = levels.last.column;
        while (levels.length > 1 && line.column < levels.last.column) {
          levels.removeLast();
        }
        // A base indent describes the snippet's initial context, not a lower
        // bound on legal source. A later top-level row establishes a new base.
        if (levels.length == 1 && line.column < levels.first.column) {
          levels[0] = _Level(
              line.column, line.displayColumn, line.alternateColumn, null);
        }
        if (line.column < oldTop && line.column != levels.last.column) {
          diagnose(row, 'inconsistentDedent',
              'Dedent does not match an open indentation level.');
        }
        if (line.column > levels.last.column) {
          if (line.alternateColumn <= levels.last.alternate) {
            diagnose(
                row, 'ambiguousTabs', 'Indentation depends on the tab width.');
          }
          if (levels.length > options.maxDepth) {
            diagnose(row, 'depthLimit',
                'Indentation exceeds the guide depth limit.');
          } else {
            final header = pendingHeader >= 0 &&
                    raw[raw[pendingHeader].logicalStart].column ==
                        levels.last.column
                ? pendingHeader
                : -1;
            final headerStart = header < 0 ? row : raw[header].logicalStart;
            final block = _BlockBuilder(
                builders.length,
                levels.last.block,
                headerStart,
                header < 0 ? row - 1 : header,
                header < 0 ? row : header + 1,
                levels.last.column,
                levels.last.display,
                line.column,
                header < 0 ? '' : raw[header].keyword);
            builders.add(block);
            levels.add(_Level(line.column, line.displayColumn,
                line.alternateColumn, block.id));
            if (header >= 0) {
              for (var h = headerStart; h <= header; h++) {
                headerBlocks[h] = block.id;
              }
            }
          }
        } else if (line.alternateColumn != levels.last.alternate) {
          diagnose(
              row, 'ambiguousTabs', 'Indentation depends on the tab width.');
        }
        if ((currentIds.isEmpty ? null : currentIds.last) !=
            levels.last.block) {
          currentIds = List.unmodifiable([
            for (final level in levels)
              if (level.block != null) level.block!
          ]);
        }
        ids[row] = currentIds;
        previousCode = row;
        pendingHeader = -1;
      } else if (line.kind == PythonLineKind.continuation ||
          line.kind == PythonLineKind.stringInterior) {
        final origin = line.logicalStart.clamp(0, row);
        ids[row] = ids[origin];
      }
      if (line.opener) {
        pendingHeader = row;
        headerEnds[line.logicalStart] = row;
      }
      if (line.kind == PythonLineKind.code ||
          line.kind == PythonLineKind.continuation ||
          line.kind == PythonLineKind.stringInterior) {
        for (final id in ids[row]) {
          builders[id].end = row;
        }
      }
    }
    var nextCode = -1;
    for (var row = count - 1; row >= 0; row--) {
      below[row] = nextCode;
      if (raw[row].kind == PythonLineKind.code) nextCode = row;
    }
    for (var row = 0; row < count; row++) {
      final line = raw[row];
      if (line.kind != PythonLineKind.blank &&
          line.kind != PythonLineKind.comment) {
        continue;
      }
      final previous = above[row], next = below[row];
      final upper = previous < 0 ? const <int>[] : ids[previous];
      final lower = next < 0 ? const <int>[] : ids[next];
      final blankDepth = math.min(upper.length + 1, lower.length);
      var chosen = lower.take(blankDepth).toList();
      if (line.kind == PythonLineKind.comment) {
        final open = [...upper];
        final opened = headerBlocks[previous];
        if (opened != null && !open.contains(opened)) open.add(opened);
        final atIndent =
            open.takeWhile((id) => builders[id].body <= line.column).toList();
        if (atIndent.length > chosen.length) chosen = atIndent;
        for (final id in chosen) {
          builders[id].end = math.max(builders[id].end, row);
        }
      }
      ids[row] = List.unmodifiable(chosen);
    }
    final detected = increases.entries.toList()
      ..sort((a, b) {
        final frequency = b.value.compareTo(a.value);
        return frequency == 0 ? a.key.compareTo(b.key) : frequency;
      });
    final unit = options.projectIndentSize ??
        (detected.isEmpty ? options.indentSize : detected.first.key);
    final tabs = options.projectUsesTabs ??
        (tabLines == 0 && spaceLines == 0
            ? options.usesTabs
            : tabLines > spaceLines);
    final frozenBlocks =
        List<PythonBlock>.unmodifiable(builders.map((b) => b.freeze()));
    final packed = _PackedPythonLines(
        text, options, source, raw, ids, headerEnds, diagnostics, frozenBlocks);
    return PythonIndentModel._(
        text,
        options,
        _SourceLineView(packed),
        _RawLineView(packed),
        packed,
        frozenBlocks,
        unit,
        tabs,
        increases.length > 1,
        virtualLine);
  }

  int lineAtOffset(int offset) {
    final target = offset.clamp(0, text.length);
    var low = 0, high = lines.length;
    while (low + 1 < high) {
      final mid = (low + high) ~/ 2;
      if (_lines._starts[mid] <= target) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return low;
  }

  List<int> guidesForLine(int line,
          {int? caretOffset, bool focused = true, bool readOnly = false}) =>
      _guides(line, caretOffset, focused, readOnly, false);
  List<int> displayGuidesForLine(int line,
          {int? caretOffset, bool focused = true, bool readOnly = false}) =>
      _guides(line, caretOffset, focused, readOnly, true);
  List<int> _guides(
      int index, int? caret, bool focused, bool readOnly, bool display) {
    final line = lines[index];
    if (!readOnly &&
        focused &&
        caret != null &&
        lineAtOffset(caret) == index &&
        line.kind == PythonLineKind.blank) {
      final actual = line.indentColumn;
      final previous = line.nearestCodeAbove;
      final known = previous < 0
          ? <int>[options.baseIndent]
          : [...lines[previous].stackColumns];
      final columns = known.where((c) => c < actual).toList();
      var next = known.isEmpty ? options.baseIndent : known.last;
      while (next < actual && columns.length < options.maxDepth) {
        if (!columns.contains(next)) columns.add(next);
        next += effectiveIndentSize;
      }
      if (!display) return List.unmodifiable(columns);
      return List.unmodifiable(
          columns.map((c) => _displayColumn(line.indentPrefix, c)));
    }
    return display ? line.displayGuideColumns : line.guideColumns;
  }

  int _displayColumn(String prefix, int semantic) {
    var logical = 0, display = 0;
    for (final c in prefix.codeUnits) {
      if (logical >= semantic) return display;
      if (c == 32) {
        logical++;
        display++;
      }
      if (c == 9) {
        logical += 8 - logical % 8;
        display +=
            options.effectiveTabWidth - display % options.effectiveTabWidth;
      }
      if (c == 12) {
        logical = display = 0;
      }
    }
    return display + math.max(0, semantic - logical);
  }

  PythonBlock? activeBlockForLine(int line,
      {bool focused = true, bool readOnly = false}) {
    if (!focused || readOnly) return null;
    final id = lines[line].activeBlockId;
    return id == null ? null : blocks[id];
  }

  PythonCaretContext contextAt(int offset) {
    final row = lineAtOffset(offset), line = lines[row];
    final length = (offset - line.startOffset).clamp(0, line.text.length);
    final prefix = line.text.substring(0, length);
    final scanned = _scan(prefix, row, _raw[row].before, options,
        row == 0 ? [options.baseIndent] : _raw[row - 1].structuralStack,
        prefixOnly: true, virtual: row == virtualLine);
    final clauses = <String, int>{};
    const compatible = {
      'else': {'if', 'elif', 'for', 'while', 'try', 'except'},
      'elif': {'if', 'elif'},
      'except': {'try', 'except'},
      'finally': {'try', 'except', 'else'},
      'case': {'case'},
    };
    final blockIds = line.blockIds;
    for (final block in blocks.reversed) {
      if (block.headerStartLine >= row ||
          block.guideColumn >= line.indentColumn) {
        continue;
      }
      if (block.endLine < row - 1 && !blockIds.contains(block.id)) {
        continue;
      }
      for (final entry in compatible.entries) {
        if (entry.value.contains(block.keyword)) {
          clauses.putIfAbsent(entry.key, () => block.guideColumn);
        }
      }
    }
    final word = scanned.keyword;
    // This is a lexical completion check, not Python syntax validation. An
    // unfinished operator/keyword must not trigger the Enter dedent, while a
    // tuple's trailing comma and bare return/raise are complete enough.
    final needsOperand = const {
      '+',
      '-',
      '*',
      '/',
      '%',
      '<',
      '>',
      '<=',
      '>=',
      '==',
      '!=',
      '=',
      '&',
      '|',
      '^',
      '~',
      ':',
      ':=',
      'and',
      'or',
      'not',
      'in',
      'is',
      'if',
      'else',
      'for',
      'from',
      'await',
      'lambda',
      'yield',
    }.contains(scanned.after.lastToken);
    final terminates =
        const {'return', 'pass', 'break', 'continue', 'raise'}.contains(word) &&
            !needsOperand &&
            !scanned.after.continued &&
            !scanned.after.inString;
    return PythonCaretContext(
        lineStartOffset: line.startOffset,
        lineEndOffset: line.endOffset,
        leadingWhitespaceEnd: line.leadingWhitespaceEnd,
        indentPrefix: line.indentPrefix,
        kind: line.kind,
        inString: scanned.after.inString,
        inComment: scanned.commentOffset >= 0,
        opensBlock: scanned.opener,
        terminalStatement: terminates,
        bracketDepth: scanned.after.bracketDepth,
        explicitContinuation: scanned.after.backslashContinuation,
        indentColumn: line.indentColumn,
        displayIndentColumn: line.displayIndentColumn,
        logicalIndentColumn:
            lines[scanned.logicalStart.clamp(0, row)].indentColumn,
        indentStops: line.stackColumns,
        clauseTargets: Map.unmodifiable(clauses));
  }
}

class PythonIndentCache {
  PythonIndentCache({this.options = const PythonIndentOptions()});
  PythonIndentOptions options;
  PythonIndentModel? _model;
  // Populated only when assertions are enabled.
  int relexedLineCount = 0;
  PythonIndentModel? get model => _model;
  void reset() {
    _model = null;
    assert(() {
      relexedLineCount = 0;
      return true;
    }());
  }

  PythonIndentModel update(String text,
      {int? changedStart,
      int? removedLength,
      int? insertedLength,
      int? virtualLine}) {
    final old = _model;
    if (text == old?.text &&
        old!.options == options &&
        old.virtualLine == virtualLine) {
      assert(() {
        relexedLineCount = 0;
        return true;
      }());
      return old;
    }
    final source = _sourceLines(text);
    virtualLine = _validVirtualLine(source, virtualLine);
    if (old == null ||
        old.options != options ||
        old.virtualLine != virtualLine) {
      final result = PythonIndentModel.analyze(text,
          options: options, virtualLine: virtualLine);
      assert(() {
        relexedLineCount = result.lines.length;
        return true;
      }());
      return _model = result;
    }
    // Use a supplied edit range to avoid decoding each unchanged prefix row.
    // Validate it before trusting it: external callers may pass stale ranges.
    final hasEditRange = changedStart != null &&
        removedLength != null &&
        insertedLength != null &&
        changedStart >= 0 &&
        removedLength >= 0 &&
        insertedLength >= 0 &&
        changedStart + removedLength <= old.text.length &&
        changedStart + insertedLength <= text.length &&
        old.text.length - removedLength + insertedLength == text.length &&
        text.startsWith(old.text.substring(0, changedStart)) &&
        text.endsWith(old.text.substring(changedStart + removedLength));
    // Start one character earlier so edits on either side of CRLF relex both
    // affected physical rows.
    var prefix =
        hasEditRange ? old.lineAtOffset(math.max(0, changedStart - 1)) : 0;
    while (prefix < source.length &&
        prefix < old._source.length &&
        source[prefix].text == old._source[prefix].text &&
        source[prefix].next == old._source[prefix].next) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < source.length - prefix &&
        suffix < old._source.length - prefix &&
        source[source.length - 1 - suffix].text ==
            old._source[old._source.length - 1 - suffix].text) {
      suffix++;
    }
    final raw = <_RawLine>[...old._raw.take(prefix)];
    var state = raw.isEmpty ? const PythonLexState._() : raw.last.after;
    var stack =
        raw.isEmpty ? <int>[options.baseIndent] : raw.last.structuralStack;
    final delta = source.length - old._source.length;
    assert(() {
      relexedLineCount = 0;
      return true;
    }());
    for (var row = prefix; row < source.length; row++) {
      final next = _scan(source[row].text, row, state, options, stack,
          virtual: row == virtualLine);
      raw.add(next);
      assert(() {
        relexedLineCount++;
        return true;
      }());
      state = next.after;
      stack = next.structuralStack;
      final previousRow = row - delta;
      if (row >= source.length - suffix &&
          previousRow >= 0 &&
          previousRow < old._raw.length) {
        final previous = old._raw[previousRow];
        if (previous.after.same(next.after, lineDelta: delta) &&
            _same(previous.structuralStack, next.structuralStack) &&
            previous.opener == next.opener &&
            previous.keyword == next.keyword) {
          raw.addAll(old._raw
              .skip(previousRow + 1)
              .map((l) => delta == 0 ? l : l.shifted(delta)));
          break;
        }
      }
    }
    return _model =
        PythonIndentModel._build(text, options, source, raw, virtualLine);
  }
}

int? _validVirtualLine(List<_SourceLine> source, int? line) => line != null &&
        line >= 0 &&
        line < source.length &&
        source[line].text.isEmpty
    ? line
    : null;
