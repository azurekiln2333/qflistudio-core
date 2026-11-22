import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_input.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  const translator = HerdrInputTranslator();

  test('printable typing becomes one text operation', () {
    final ops = translator.translate(bytes('git status'));
    expect(ops, hasLength(1));
    expect(ops.single, isA<HerdrSendTextOp>());
    expect((ops.single as HerdrSendTextOp).text, 'git status');
  });

  test('Enter, Tab and Backspace are keys, not text', () {
    final ops = translator.translate(bytes('\r\t\u007f'));
    expect(
      ops.whereType<HerdrSendKeysOp>().map((op) => op.keys.single).toList(),
      <String>['enter', 'tab', 'backspace'],
    );
  });

  test('control bytes map to Ctrl combinations', () {
    final ops = translator.translate(bytes('\u0003'));
    expect((ops.single as HerdrSendKeysOp).keys, <String>['ctrl+c']);
    final letter = translator.translate(bytes('\u0006'));
    expect((letter.single as HerdrSendKeysOp).keys, <String>['ctrl+f']);
  });

  test('arrow escape sequences become named keys', () {
    final ops = translator.translate(bytes('\u001b[A\u001b[B\u001b[C\u001b[D'));
    expect(
      ops.whereType<HerdrSendKeysOp>().map((op) => op.keys.single).toList(),
      <String>['up', 'down', 'right', 'left'],
    );
  });

  test('application-mode arrows (ESC O) are understood', () {
    final ops = translator.translate(bytes('\u001bOA'));
    expect((ops.single as HerdrSendKeysOp).keys, <String>['up']);
  });

  test('a lone Escape reports Escape', () {
    final ops = translator.translate(bytes('\u001b'));
    expect((ops.single as HerdrSendKeysOp).keys, <String>['esc']);
  });

  test('text and keys keep their order', () {
    final ops = translator.translate(bytes('ls\r'));
    expect(ops, hasLength(2));
    expect((ops[0] as HerdrSendTextOp).text, 'ls');
    expect((ops[1] as HerdrSendKeysOp).keys, <String>['enter']);
  });

  test('unknown CSI sequences are dropped rather than typed literally', () {
    final ops = translator.translate(bytes('\u001b[15~'));
    expect(ops, isEmpty);
  });

  test('Alt+letter keeps the ESC prefix as literal text', () {
    // Herdr has no `alt+x` key name, but `pane send-text` writes literal bytes,
    // so ESC+char still reaches the app as the same Alt combination.
    final ops = translator.translate(bytes('\u001bb'));
    expect(ops, hasLength(1));
    expect(ops.single, isA<HerdrSendTextOp>());
    expect((ops.single as HerdrSendTextOp).text, '\u001bb');
  });

  test('Alt between typed text keeps its place', () {
    final ops = translator.translate(bytes('ab\u001bxc'));
    expect(
      ops.whereType<HerdrSendTextOp>().map((op) => op.text).toList(),
      <String>['ab', '\u001bx', 'c'],
    );
  });

  test('Delete, PageUp and PageDown use herdr names', () {
    final ops = translator.translate(bytes('\u001b[3~\u001b[5~\u001b[6~'));
    expect(
      ops.whereType<HerdrSendKeysOp>().map((op) => op.keys.single).toList(),
      <String>['delete', 'pageup', 'pagedown'],
    );
  });

  test('Chinese input is sent as text, not split into bytes', () {
    final ops = translator.translate(bytes('修复登录'));
    expect((ops.single as HerdrSendTextOp).text, '修复登录');
  });
}
