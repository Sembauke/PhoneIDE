import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_ide/phone_ide.dart';

void main() {
  test('copyWith can explicitly clear nullable editor options', () {
    final original = EditorOptions(
        cursorColor: Colors.red,
        regionOptions: EditorRegionOptions(start: 2, end: 5));
    expect(original.copyWith(cursorColor: null).cursorColor, isNull);
    expect(original.copyWith(regionOptions: null).regionOptions, isNull);
    expect(original.regionOptions!.copyWith(start: null).start, isNull);
  });
}
