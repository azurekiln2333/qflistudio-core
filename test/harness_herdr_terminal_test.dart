import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/herdr/herdr_terminal.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// Snapshot terminal with a controllable sender: every call is recorded and can
/// be held open, so a test can prove one call finishes before the next starts.
class _Recorder {
  _Recorder();

  final List<String> calls = <String>[];
  Completer<void>? gate;

  Future<void> sendText(String text) async {
    calls.add('text:$text');
    final pending = gate;
    if (pending != null) await pending.future;
  }

  Future<void> sendKeys(List<String> keys) async {
    calls.add('keys:${keys.join(',')}');
    final pending = gate;
    if (pending != null) await pending.future;
  }

  HerdrSnapshotTerminal terminal() => HerdrSnapshotTerminal(
    readPane: () async => '',
    sendText: sendText,
    sendKeys: sendKeys,
  );
}

void main() {
  test('a key typed after text waits for the text call', () async {
    final recorder = _Recorder()..gate = Completer<void>();
    final terminal = recorder.terminal();

    terminal.write(bytes('hello'));
    terminal.write(bytes('\r'));
    // The first call is in flight; the Enter behind it must not start yet, or
    // `pane send-keys enter` can overtake `pane send-text hello`.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(recorder.calls, <String>['text:hello']);

    recorder.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(recorder.calls, <String>['text:hello', 'keys:enter']);

    await terminal.close();
  });

  test('a burst of chunks becomes one send-text and one key', () async {
    final recorder = _Recorder();
    final terminal = recorder.terminal();

    for (final chunk in <String>['h', 'el', 'lo']) {
      terminal.write(bytes(chunk));
    }
    terminal.write(bytes('\r'));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(recorder.calls, <String>['text:hello', 'keys:enter']);

    await terminal.close();
  });

  test('a failed call is reported and does not block the next one', () async {
    final errors = <Object>[];
    final calls = <String>[];
    final terminal = HerdrSnapshotTerminal(
      readPane: () async => '',
      sendText: (text) async {
        calls.add('text:$text');
        throw StateError('pane gone');
      },
      sendKeys: (keys) async => calls.add('keys:${keys.join(',')}'),
      onError: errors.add,
    );

    terminal.write(bytes('x'));
    terminal.write(bytes('\r'));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(calls, <String>['text:x', 'keys:enter']);
    expect(errors, hasLength(1));

    await terminal.close();
  });

  test('writing after close is dropped', () async {
    final recorder = _Recorder();
    final terminal = recorder.terminal();
    await terminal.close();
    terminal.write(bytes('late'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(recorder.calls, isEmpty);
  });
}
