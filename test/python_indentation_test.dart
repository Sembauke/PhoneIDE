import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/python_indentation.dart';

PythonIndentOptions _options(Map<String, dynamic> values) =>
    PythonIndentOptions(
      indentSize: values['indentSize'] as int? ?? 4,
      tabWidth: values['tabWidth'] as int? ?? 8,
      projectIndentSize: values['projectIndentSize'] as int?,
      projectTabWidth: values['projectTabWidth'] as int?,
      projectUsesTabs: values['projectUsesTabs'] as bool?,
      baseIndent: values['baseIndent'] as int? ?? 0,
      notebook: values['notebook'] as bool? ?? false,
    );
Object _snapshot(PythonIndentModel model) => [
      for (final line in model.lines)
        [
          line.kind.name,
          line.logicalStartLine,
          line.stackColumns,
          line.guideColumns,
          line.displayGuideColumns,
          line.opensBlock,
          line.headerEndLine,
          line.activeBlockId,
          line.nearestCodeAbove,
          line.nearestCodeBelow,
          for (final d in line.diagnostics) [d.code, d.startOffset, d.endOffset]
        ],
      for (final b in model.blocks)
        [
          b.id,
          b.parentId,
          b.headerStartLine,
          b.headerEndLine,
          b.bodyStartLine,
          b.endLine,
          b.guideColumn,
          b.bodyColumn,
          b.keyword
        ],
      model.effectiveIndentSize,
      model.usesTabs,
    ];
void main() {
  final fixtures = jsonDecode(
          File('test/fixtures/python_indent_cases.json').readAsStringSync())
      as List;
  for (final value in fixtures) {
    final fixture = value as Map<String, dynamic>;
    test(fixture['name'] as String, () {
      final model = PythonIndentModel.analyze(fixture['source'] as String,
          options: _options(
              (fixture['options'] as Map?)?.cast<String, dynamic>() ?? {}));
      for (final expected in fixture['lines'] as List) {
        final line = model.lines[expected['line'] as int];
        expect(line.guideColumns, expected['guides'],
            reason: 'line ${expected['line']} ${line.text}');
        if (expected['kind'] != null) expect(line.kind.name, expected['kind']);
      }
      if (fixture['opensBlock'] != null) {
        expect(model.lines.map((l) => l.opensBlock).toList(),
            fixture['opensBlock']);
      }
      if (fixture['displayGuideColumns'] != null) {
        expect(model.lines.map((l) => l.displayGuideColumns).toList(),
            fixture['displayGuideColumns']);
      }
      if (fixture['effectiveIndentSize'] != null) {
        expect(model.effectiveIndentSize, fixture['effectiveIndentSize']);
      }
      if (fixture['usesTabs'] != null) {
        expect(model.usesTabs, fixture['usesTabs']);
      }
      for (final d in fixture['diagnostics'] as List? ?? []) {
        expect(model.lines[d['line'] as int].diagnostics.map((v) => v.code),
            contains(d['code']));
      }
      final caret = fixture['caret'] as Map?;
      if (caret != null) {
        expect(
            model.guidesForLine(caret['line'] as int,
                caretOffset: caret['offset'] as int,
                readOnly: fixture['readOnly'] == true),
            caret['guides']);
      }
      if (fixture['readOnly'] == true) {
        for (var row = 0; row < model.lines.length; row++) {
          expect(model.activeBlockForLine(row, readOnly: true), isNull);
        }
      }
    });
  }
  test('a snippet may return below its configured base indentation', () {
    final model = PythonIndentModel.analyze(
        '    if ready:\n        work()\nafter()\nif again:\n    work()',
        options: const PythonIndentOptions(baseIndent: 4));
    expect(model.lines.expand((line) => line.diagnostics), isEmpty);
    expect(model.lines[2].stackColumns, [0]);
    expect(model.lines[4].guideColumns, [0]);
  });
  test('notebook magic inside Python literals stays literal', () {
    const source =
        'value = """\n%time value([\n!echo [\n"""\nif ready:\n    work()';
    final model = PythonIndentModel.analyze(source,
        options: const PythonIndentOptions(notebook: true));
    expect(model.lines[1].kind, PythonLineKind.stringInterior);
    expect(model.lines[2].kind, PythonLineKind.stringInterior);
    expect(model.lines[4].kind, PythonLineKind.code);
    expect(model.lines[5].guideColumns, [0]);
  });
  test('seeded incremental edits equal full recomputation', () {
    final random = Random(1874), cache = PythonIndentCache();
    var text = 'def f(x):\n    if x:\n        return f"{x}"\n    return 0\n';
    const inserts = [
      'a',
      '\n',
      '\r',
      '\r\n',
      ' ',
      '\t',
      '"',
      "'",
      '"""',
      '(',
      ')',
      '[',
      ']',
      '{',
      '}',
      '\\',
      '#',
      ':',
      'f',
      't',
      '\u00a0',
      '\ufeff',
      '😀'
    ];
    cache.update(text);
    for (var turn = 0; turn < 3000; turn++) {
      final at = random.nextInt(text.length + 1);
      final remove = min(random.nextInt(5), text.length - at);
      final inserted = inserts[random.nextInt(inserts.length)];
      text = text.replaceRange(at, at + remove, inserted);
      final actual = cache.update(text,
          changedStart: at,
          removedLength: remove,
          insertedLength: inserted.length);
      final expected = PythonIndentModel.analyze(text);
      expect(_snapshot(actual), _snapshot(expected),
          reason: 'seed1874 turn$turn text=${jsonEncode(text)}');
    }
    final long = List.generate(2000, (i) => 'value_$i = $i').join('\n');
    cache.update(long);
    cache.update(long.replaceFirst('value_1000 = 1000', 'value_1000 = 2000'));
    expect(cache.relexedLineCount, lessThan(5));
  });
  test('runtime configuration invalidates cached semantic/display results', () {
    final cache = PythonIndentCache();
    const source = 'if ready:\n\tif nested:\n\t\twork()';
    final old = cache.update(source);
    cache.options =
        const PythonIndentOptions(projectTabWidth: 3, projectIndentSize: 2);
    final next = cache.update(source);
    expect(old.lines.last.displayGuideColumns, [0, 8]);
    expect(next.lines.last.displayGuideColumns, [0, 3]);
    expect(next.effectiveIndentSize, 2);
    expect(cache.relexedLineCount, next.lines.length);
  });
  test('active lookup follows block and branch identity', () {
    final model = PythonIndentModel.analyze(
        'if ready:\n    first()\nelse:\n    second()');
    expect(model.activeBlockForLine(0)?.id, model.activeBlockForLine(1)?.id);
    expect(model.activeBlockForLine(2)?.id, model.activeBlockForLine(3)?.id);
    expect(model.activeBlockForLine(0)?.id,
        isNot(model.activeBlockForLine(2)?.id));
    expect(model.activeBlockForLine(1, focused: false), isNull);
    final multiline = PythonIndentModel.analyze(
        'if outer:\n    def f(\n0,\n):\n        work()');
    expect(multiline.activeBlockForLine(1)?.keyword, 'def');
    expect(multiline.activeBlockForLine(3)?.id,
        multiline.activeBlockForLine(4)?.id);
  });
  test('tab-ambiguous indentation increases are diagnosed', () {
    final sources = [
      'if a:\n    if b:\n\tpass\n',
      'if a:\n \tif b:\n\t\tpass\n',
      'if a:\n\tif b:\n        pass\n',
      'if a:\n\tif b:\n\t\tpass\n',
      'if a:\n    if b:\n        pass\n',
    ];
    const expectedRows = [
      [2],
      [2],
      [2],
      <int>[],
      <int>[],
    ];
    for (var index = 0; index < sources.length; index++) {
      final model = PythonIndentModel.analyze(sources[index]);
      final flagged = [
        for (var row = 0; row < model.lines.length; row++)
          if (model.lines[row].diagnostics
              .any((d) => d.code == 'ambiguousTabs'))
            row,
      ];
      expect(flagged, expectedRows[index]);
    }
  });

  test('virtual insertion row preserves explicit continuation', () {
    const source = 'if outer:\n    value = \\\n\n        call()\n    next()';
    final model = PythonIndentModel.analyze(source, virtualLine: 2);
    expect(model.virtualLine, 2);
    expect(model.lines[2].kind, PythonLineKind.continuation);
    expect(model.lines[2].endState.backslashContinuation, isTrue);
    expect(model.contextAt(model.lines[2].startOffset).explicitContinuation,
        isTrue);
    expect(model.lines[3].kind, PythonLineKind.continuation);
    expect(model.lines[3].logicalStartLine, 1);
    expect(model.lines[3].guideColumns, [0]);
    expect(model.lines[3].stackColumns, [0, 4]);
    final actualSource =
        PythonIndentModel.analyze(source.replaceFirst('\\\n\n', '\\\n'));
    expect(model.lines[3].kind, actualSource.lines[2].kind);
    expect(model.lines[3].stackColumns, actualSource.lines[2].stackColumns);
    expect(
        PythonIndentModel.analyze(source).lines[3].kind, PythonLineKind.code);
  });

  test('virtual rows preserve multiline strings and header anchors', () {
    final string = PythonIndentModel.analyze(
        'if a:\n    value = """\n\ntext\n"""',
        virtualLine: 2);
    expect(string.lines[3].kind, PythonLineKind.stringInterior);
    expect(string.lines[3].logicalStartLine, 1);
    expect(string.lines[3].guideColumns, [0]);
    expect(string.contextAt(string.lines[2].startOffset).inString, isTrue);
    final header = PythonIndentModel.analyze('if \\\n\n    ready:\n    call()',
        virtualLine: 1);
    expect(header.lines[2].kind, PythonLineKind.continuation);
    expect(header.lines[0].opensBlock, isTrue);
    expect(header.lines[0].headerEndLine, 2);
    expect(header.blocks.single.headerEndLine, 2);
    expect(header.lines[3].guideColumns, [0]);
  });

  test('virtual-row changes invalidate incremental classification', () {
    const source = 'value = \\\n\n    call()\nnext()';
    final cache = PythonIndentCache();
    final virtual = cache.update(source, virtualLine: 1);
    expect(virtual.lines[2].kind, PythonLineKind.continuation);
    expect(identical(cache.update(source, virtualLine: 1), virtual), isTrue);
    final real = cache.update(source);
    expect(real.lines[2].kind, PythonLineKind.code);
    expect(cache.relexedLineCount, real.lines.length);
    final restored = cache.update(source, virtualLine: 1);
    expect(_snapshot(restored), _snapshot(virtual));
    final shifted = '# added\n$source';
    expect(_snapshot(cache.update(shifted, virtualLine: 2)),
        _snapshot(PythonIndentModel.analyze(shifted, virtualLine: 2)));
    final edited = shifted.replaceFirst('call()', 'changed()');
    expect(_snapshot(cache.update(edited, virtualLine: 2)),
        _snapshot(PythonIndentModel.analyze(edited, virtualLine: 2)));
    final filled = edited.replaceFirst('\\\n\n', '\\\n# actual\n');
    expect(cache.update(filled, virtualLine: 2).virtualLine, isNull);
    expect(
        _snapshot(cache.model!), _snapshot(PythonIndentModel.analyze(filled)));
  });
}
