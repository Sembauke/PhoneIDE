import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/editor/python_analysis_worker.dart';
import 'package:phone_ide/editor/python_indentation.dart';

void main() {
  test('background analysis coalesces queued edits and accepts only the latest',
      () async {
    final worker = PythonAnalysisWorker();
    addTearDown(worker.dispose);
    const options = PythonIndentOptions();
    final first = worker.analyze('if first:\n    work()', options: options);
    final middle = worker.analyze('if middle:\n    work()', options: options);
    final last = worker.analyze('if last:\n    work()', options: options);
    expect(await first, isNull);
    expect(await middle, isNull);
    final result = (await last)!;
    expect(result.text, 'if last:\n    work()');
    expect(result.lines[1].guideColumns, [0]);
    final next = await worker.analyze('if last:\n\twork()',
        options: const PythonIndentOptions(projectUsesTabs: true));
    expect(next!.lines[1].indentColumn, 8);
    expect(next.usesTabs, isTrue);
  });

  test('disposing an analysis worker resolves running and queued requests',
      () async {
    final worker = PythonAnalysisWorker();
    final first =
        worker.analyze('if first:', options: const PythonIndentOptions());
    final next =
        worker.analyze('if next:', options: const PythonIndentOptions());
    worker.dispose();
    expect(await first, isNull);
    expect(await next, isNull);
    expect(
        await worker.analyze('', options: const PythonIndentOptions()), isNull);
  });
}
