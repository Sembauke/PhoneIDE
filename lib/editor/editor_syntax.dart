part of 'editor.dart';

final _pythonBlock = RegExp(
    r'^(?:(?:async\s+)?(?:def|for|with)|class|if|elif|else|while|try|except|finally|match|case)\b');

// Basic block-opening detection shared by Enter and blank-row guides. Scan
// once, retaining quote/comment state between rows; indices are zero-based.
Set<int> _blockOpeningLines(String text, String language) {
  final normalized = language.toLowerCase();
  final python = normalized == 'python' || normalized == 'py';
  if (!python &&
      !const {'javascript', 'js', 'css', 'json'}.contains(normalized)) {
    return const {};
  }

  final openings = <int>{};
  final line = StringBuffer();
  var row = 0;
  var quote = '';
  var escaped = false;
  var lineComment = false;
  var blockComment = false;

  void recordLine() {
    if (quote.isNotEmpty || blockComment) return;
    final code = line.toString().trim();
    if (code.endsWith('{') ||
        code.endsWith('[') ||
        code.endsWith('(') ||
        (python && code.endsWith(':') && _pythonBlock.hasMatch(code))) {
      openings.add(row);
    }
  }

  for (var index = 0; index < text.length; index++) {
    final character = text[index];
    if (character == '\n') {
      recordLine();
      line.clear();
      row++;
      lineComment = false;
      if (quote.length == 1 && quote != '`' && !escaped) quote = '';
      escaped = false;
      continue;
    }
    if (lineComment) continue;
    if (blockComment) {
      if (text.startsWith('*/', index)) {
        blockComment = false;
        index++;
      }
      continue;
    }
    if (quote.isNotEmpty) {
      if (escaped) {
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else if (text.startsWith(quote, index)) {
        index += quote.length - 1;
        quote = '';
      }
      continue;
    }
    if ((python && character == '#') ||
        (!python && text.startsWith('//', index))) {
      lineComment = true;
    } else if (!python && text.startsWith('/*', index)) {
      blockComment = true;
      index++;
      line.write(' ');
    } else if (character == '"' ||
        character == "'" ||
        (!python && character == '`')) {
      quote = python && text.startsWith(character * 3, index)
          ? character * 3
          : character;
      index += quote.length - 1;
      line.write(' ');
    } else {
      line.write(character);
    }
  }
  recordLine();
  return openings;
}
