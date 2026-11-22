/// 每个用例都限时：流没收尾时要尽快报错。
@Timeout(Duration(seconds: 20))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/local/pty_process.dart';

/// 两个独立管道的最小假子进程，用来验证 stderr 也会被转发。
class _FakeChild implements PtyChildProcess {
  final StreamController<List<int>> out = StreamController<List<int>>();
  final StreamController<List<int>> err = StreamController<List<int>>();
  final Completer<int> exit = Completer<int>();
  final List<List<int>> writes = <List<int>>[];

  /// 真实的 stdin 管道；用 sink 记录收到的字节。
  @override
  late final StreamSink<List<int>> stdin = _RecordingSink(writes);
  int cancelCount = 0;

  @override
  int get pid => 4242;

  @override
  Stream<List<int>> get stdout => out.stream;

  @override
  Stream<List<int>> get stderr => err.stream;

  @override
  Future<int> get exitCode => exit.future;

  @override
  Future<void> cancel() async {
    cancelCount++;
    if (!exit.isCompleted) exit.complete(0);
  }
}

/// 把写入原样记录下来，供断言使用。
class _RecordingSink implements StreamSink<List<int>> {
  _RecordingSink(this.writes);

  final List<List<int>> writes;

  @override
  void add(List<int> event) => writes.add(List<int>.of(event));

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      writes.add(List<int>.of(chunk));
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();
}

String _text(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

void main() {
  group('SupervisedPtyProcess', () {
    test('stdout 与 stderr 都进入 output', () async {
      final child = _FakeChild();
      final process = SupervisedPtyProcess(child);
      final chunks = <String>[];
      final subscription = process.output.listen(
        (Uint8List data) => chunks.add(_text(data)),
      );

      child.out.add(utf8.encode('正在编译\n'));
      child.err.add(utf8.encode('warning: unused variable\n'));
      await Future<void>.delayed(Duration.zero);

      expect(chunks, <String>['正在编译\n', 'warning: unused variable\n']);
      expect(process.pid, 4242);

      await subscription.cancel();
      await process.terminate();
    });

    test('terminate 幂等且写入在结束后被忽略', () async {
      final child = _FakeChild();
      final process = SupervisedPtyProcess(child);

      process.write(<int>[0x61]);
      expect(child.writes.single, <int>[0x61]);

      await process.terminate();
      await process.terminate();
      expect(child.cancelCount, 1);

      process.write(<int>[0x62]);
      expect(child.writes, hasLength(1));
    });

    test('两个管道都结束后才关闭 output', () async {
      final child = _FakeChild();
      final process = SupervisedPtyProcess(child);
      var done = false;
      final subscription = process.output.listen(
        (_) {},
        onDone: () => done = true,
      );

      await child.out.close();
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse, reason: 'stderr 尾巴仍可能到达');

      await child.err.close();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);

      await subscription.cancel();
      await process.terminate();
    });
  });
}
