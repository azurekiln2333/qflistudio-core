import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/share/share_inbox.dart';
import 'package:qfli_studio_core/share/share_inbox_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kShareInboxChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory root;
  late ShareInboxStore store;
  late List<MethodCall> calls;

  setUp(() {
    root = Directory.systemTemp.createTempSync('share_inbox_test');
    store = ShareInboxStore(root: root);
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'takePending') return null;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Map<String, Object?> batchPayload({
    String id = 'b1',
    bool coldStart = true,
    String source = 'send',
  }) {
    return <String, Object?>{
      'id': id,
      'coldStart': coldStart,
      'source': source,
      'files': <Object?>[
        <String, Object?>{
          'path': p.join(root.path, id, '0001-a.txt'),
          'name': 'a.txt',
          'bytes': 3,
          'mimeType': 'text/plain',
        },
      ],
    };
  }

  test('takePending 为空时不发事件', () async {
    final inbox = PlatformShareInbox(store: store, channel: channel);
    final received = <ShareInboxBatch>[];
    inbox.incoming.listen(received.add);
    await inbox.start();
    await Future<void>.delayed(Duration.zero);

    expect(calls.map((call) => call.method), contains('takePending'));
    expect(received, isEmpty);
    inbox.dispose();
  });

  test('冷启动批次由 takePending 送回 incoming', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'takePending' ? batchPayload() : null;
    });
    final inbox = PlatformShareInbox(store: store, channel: channel);
    final received = <ShareInboxBatch>[];
    inbox.incoming.listen(received.add);
    await inbox.start();
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.id, 'b1');
    expect(received.single.coldStart, isTrue);
    expect(received.single.files.single.name, 'a.txt');
    expect(received.single.totalBytes, 3);
    inbox.dispose();
  });

  test('原生主动推 incoming 会转成事件', () async {
    final inbox = PlatformShareInbox(store: store, channel: channel);
    final received = <ShareInboxBatch>[];
    inbox.incoming.listen(received.add);
    await inbox.start();

    await messenger.handlePlatformMessage(
      kShareInboxChannel,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('incoming', batchPayload(id: 'b2', coldStart: false)),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received.single.id, 'b2');
    expect(received.single.coldStart, isFalse);
    inbox.dispose();
  });

  test('非法载荷被忽略', () async {
    final inbox = PlatformShareInbox(store: store, channel: channel);
    final received = <ShareInboxBatch>[];
    inbox.incoming.listen(received.add);
    await inbox.start();

    await messenger.handlePlatformMessage(
      kShareInboxChannel,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('incoming', <String, Object?>{
          'id': '../escape',
          'files': <Object?>[],
        }),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    inbox.dispose();
  });

  test('discard 会删目录并通知原生', () async {
    final directory = Directory(p.join(root.path, 'b3'))
      ..createSync(recursive: true);
    File(p.join(directory.path, 'x.txt')).writeAsStringSync('x');

    final inbox = PlatformShareInbox(store: store, channel: channel);
    await inbox.start();
    await inbox.discard('b3');

    expect(directory.existsSync(), isFalse);
    expect(calls.where((call) => call.method == 'discard'), isNotEmpty);
    inbox.dispose();
  });

  test('sweep 删掉超期批次，保留新批次', () async {
    final now = DateTime.now();
    void writeBatch(String id) {
      Directory(p.join(root.path, id)).createSync(recursive: true);
      File(
        p.join(root.path, id, 'f.bin'),
      ).writeAsBytesSync(List<int>.filled(4, 0));
    }

    writeBatch('fresh');
    final sweeping = ShareInboxStore(
      root: root,
      maxAge: const Duration(days: 7),
      // 时钟往后拨 8 天：现有批次都算超期。
      clock: () => now.add(const Duration(days: 8)),
    );

    await sweeping.sweep();

    expect(Directory(p.join(root.path, 'fresh')).existsSync(), isFalse);
  });

  test('sweep 把总量压到上限以内', () async {
    void writeBatch(String id) {
      Directory(p.join(root.path, id)).createSync(recursive: true);
      File(
        p.join(root.path, id, 'f.bin'),
      ).writeAsBytesSync(List<int>.filled(4, 0));
    }

    for (final id in <String>['a', 'b', 'c']) {
      writeBatch(id);
    }
    final sweeping = ShareInboxStore(
      root: root,
      maxBytes: 4,
      maxAge: const Duration(days: 3650),
    );

    await sweeping.sweep();

    final remaining = root
        .listSync()
        .whereType<Directory>()
        .where((dir) => dir.listSync().isNotEmpty)
        .length;
    expect(remaining, 1);
  });

  test('非法批次 id 不拼进路径', () {
    expect(ShareInboxStore.isValidBatchId('../etc'), isFalse);
    expect(ShareInboxStore.isValidBatchId('Ab-1_2'), isTrue);
  });
}
