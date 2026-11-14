import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flushes asset/platform work until the editor is ready, then settles UI work.
/// Unlike a fixed pump count this also handles a cold syntax-registry load.
Future<void> settleEditor(WidgetTester tester) async {
  for (var frame = 0; frame < 100; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 16),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      return;
    }
  }
  fail('Editor did not finish initialization.');
}
