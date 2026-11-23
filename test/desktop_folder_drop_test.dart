@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/desktop_folder_drop.dart';
import 'package:qfli_studio_core/store/project_store.dart';

/// A store with no disk backing, so registration is deterministic.
///
/// [addExisting] is scripted per test: it either succeeds, returns an error,
/// or throws. Successful registrations are remembered so a repeated drop can
/// reuse them the way the real store would.
class _FakeStore extends ProjectStore {
  _FakeStore();

  final List<Project> _registered = <Project>[];
  final List<String> addExistingCalls = <String>[];

  /// Number of upcoming calls that should fail before succeeding.
  int failuresRemaining = 0;

  /// When true every call throws instead of returning an error record.
  bool throwOnAdd = false;

  @override
  List<Project> get projects => List<Project>.unmodifiable(_registered);

  @override
  Future<ProjectResult> addExisting(String rawPath) async {
    addExistingCalls.add(rawPath);
    if (throwOnAdd) throw StateError('disk unavailable');
    if (failuresRemaining > 0) {
      failuresRemaining--;
      return (error: '目录不存在：$rawPath', project: null);
    }
    final project = Project.create(name: 'p', path: rawPath);
    _registered.add(project);
    return (error: null, project: project);
  }
}

const MethodChannel _channel = MethodChannel('qflistudio/folder_drop.test');

Map<String, Object?> _batch(String id, List<String> paths) => <String, Object?>{
  'id': id,
  'paths': paths,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStore store;
  late List<Project> opened;
  late List<String> errors;

  setUp(() {
    store = _FakeStore();
    opened = <Project>[];
    errors = <String>[];
  });

  tearDown(() {
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// Installs the native side of the channel.
  ///
  /// [backlog] is what `takePending` returns. [onTakePending] may complete
  /// later to simulate a slow handshake.
  void serve(
    List<Object?> backlog, {
    Future<void> Function()? beforeTakePendingReply,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          switch (call.method) {
            case 'takePending':
              if (beforeTakePendingReply != null) {
                await beforeTakePendingReply();
              }
              return backlog;
          }
          return null;
        });
  }

  DesktopFolderDrop build() => DesktopFolderDrop(
    store: store,
    onOpen: (project) async => opened.add(project),
    onError: errors.add,
    channel: _channel,
  );

  /// Sends a native `incoming` call through the messenger.
  Future<void> emitIncoming(Object? argument) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('incoming', argument),
          ),
          (_) {},
        );
  }

  test('start consumes the backlog', () async {
    serve([
      _batch('1', ['C:\\work\\alpha']),
    ]);
    final drop = build();
    addTearDown(drop.dispose);

    await drop.start();

    expect(opened.map((p) => p.path), ['C:\\work\\alpha']);
    expect(store.addExistingCalls, ['C:\\work\\alpha']);
  });

  test('repeated drops reopen the existing project', () async {
    serve(const <Object?>[]);
    final drop = build();
    addTearDown(drop.dispose);
    await drop.start();

    await emitIncoming(_batch('1', ['C:\\work\\alpha']));
    await emitIncoming(_batch('2', ['C:\\work\\alpha']));

    // The second drop must not register again, but must still open.
    expect(store.addExistingCalls, ['C:\\work\\alpha']);
    expect(opened.length, 2);
    expect(opened[0].id, opened[1].id);
  });

  test('a replayed batch id is ignored', () async {
    serve(const <Object?>[]);
    final drop = build();
    addTearDown(drop.dispose);
    await drop.start();

    await emitIncoming(_batch('same', ['C:\\work\\alpha']));
    await emitIncoming(_batch('same', ['C:\\work\\alpha']));

    expect(opened.length, 1);
  });

  test('duplicate paths inside one batch open once', () async {
    serve(const <Object?>[]);
    final drop = build();
    addTearDown(drop.dispose);
    await drop.start();

    await emitIncoming(
      _batch('1', ['C:\\work\\alpha', 'C:\\work\\alpha', 'C:\\work\\beta']),
    );

    expect(opened.map((p) => p.path), ['C:\\work\\alpha', 'C:\\work\\beta']);
    expect(store.addExistingCalls.length, 2);
  });

  test('a failed registration does not block a later retry', () async {
    serve(const <Object?>[]);
    final drop = build();
    addTearDown(drop.dispose);
    await drop.start();

    store.failuresRemaining = 1;
    await emitIncoming(_batch('1', ['C:\\work\\alpha']));
    expect(opened, isEmpty);
    expect(errors.single, contains('目录不存在'));

    // Same directory again: not remembered as seen, so it retries.
    await emitIncoming(_batch('2', ['C:\\work\\alpha']));
    expect(opened.map((p) => p.path), ['C:\\work\\alpha']);
    expect(store.addExistingCalls.length, 2);
  });

  test('a throwing registration is reported and survives the queue', () async {
    serve(const <Object?>[]);
    final drop = build();
    addTearDown(drop.dispose);
    await drop.start();

    store.throwOnAdd = true;
    await emitIncoming(_batch('1', ['C:\\work\\alpha']));
    expect(errors, isNotEmpty);
    expect(opened, isEmpty);

    store.throwOnAdd = false;
    await emitIncoming(_batch('2', ['C:\\work\\beta']));
    expect(opened.map((p) => p.path), ['C:\\work\\beta']);
  });

  test('malformed payloads are rejected without throwing', () async {
    serve(const <Object?>[]);
    final drop = build();
    addTearDown(drop.dispose);
    await drop.start();

    await emitIncoming('not a map');
    await emitIncoming(<String, Object?>{
      'paths': ['C:\\work\\a'],
    });
    await emitIncoming(<String, Object?>{
      'id': '',
      'paths': ['C:\\work\\a'],
    });
    await emitIncoming(<String, Object?>{'id': 'x', 'paths': 'nope'});
    await emitIncoming(<String, Object?>{
      'id': 'y',
      'paths': <Object?>[1, 2],
    });

    expect(store.addExistingCalls, isEmpty);
    expect(opened, isEmpty);
    // Each rejected payload is surfaced rather than silently dropped.
    expect(errors, isNotEmpty);
  });

  test('relative paths are refused', () async {
    serve(const <Object?>[]);
    final drop = build();
    addTearDown(drop.dispose);
    await drop.start();

    await emitIncoming(_batch('1', ['relative\\dir']));
    expect(opened, isEmpty);
    expect(errors, isNotEmpty);
  });

  test(
    'Windows path casing and separators reuse an existing project',
    () async {
      serve(const <Object?>[]);
      final drop = build();
      addTearDown(drop.dispose);
      await drop.start();

      await emitIncoming(_batch('1', [r'C:\work\alpha']));
      await emitIncoming(_batch('2', ['c:/work/alpha/']));

      expect(store.addExistingCalls, [r'C:\work\alpha']);
      expect(opened.length, 2);
      expect(opened.last, same(opened.first));
    },
  );

  test('dispose stops callbacks', () async {
    serve(const <Object?>[]);
    final drop = build();
    await drop.start();
    drop.dispose();

    await emitIncoming(_batch('1', ['C:\\work\\alpha']));

    expect(opened, isEmpty);
    expect(store.addExistingCalls, isEmpty);
  });

  test('dispose during start discards the backlog', () async {
    final gate = Completer<void>();
    serve([
      _batch('1', ['C:\\work\\alpha']),
    ], beforeTakePendingReply: () => gate.future);

    final drop = build();
    final starting = drop.start();
    drop.dispose();
    gate.complete();
    await starting;

    expect(opened, isEmpty);
  });

  test(
    'a live drop arriving before the handshake reply runs after the backlog',
    () async {
      final gate = Completer<void>();
      serve([
        _batch('backlog', ['C:\\work\\first']),
      ], beforeTakePendingReply: () => gate.future);

      final drop = build();
      addTearDown(drop.dispose);
      final starting = drop.start();

      // Live drop arrives while `takePending` is still outstanding.
      await emitIncoming(_batch('live', ['C:\\work\\second']));

      gate.complete();
      await starting;

      // Backlog first, then the live drop, in that order.
      expect(opened.map((p) => p.path), [
        'C:\\work\\first',
        'C:\\work\\second',
      ]);
    },
  );

  test('a missing native adapter leaves start harmless', () async {
    // No handler installed: the channel reports MissingPluginException.
    final drop = build();
    addTearDown(drop.dispose);

    await drop.start();

    expect(opened, isEmpty);
    expect(errors, isEmpty);
  });

  test('a native error is reported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (MethodCall call) async {
          if (call.method == 'takePending') {
            throw PlatformException(code: 'UNAVAILABLE', message: 'no drop');
          }
          return null;
        });
    final drop = build();
    addTearDown(drop.dispose);

    await drop.start();

    expect(errors, ['no drop']);
    expect(opened, isEmpty);
  });

  test('start is idempotent', () async {
    serve([
      _batch('1', ['C:\\work\\alpha']),
    ]);
    final drop = build();
    addTearDown(drop.dispose);

    await drop.start();
    await drop.start();

    expect(opened.length, 1);
  });
}
