import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/external_folder_service.dart';

const MethodChannel _channel = MethodChannel('qflistudio/platform');

void _mockChannel(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ExternalFolderService.resetForTesting();
    ExternalFolderService.debugAssumeSupported = true;
  });

  test(
    'pick adopts the folder and read/write travel through the channel',
    () async {
      final calls = <MethodCall>[];
      _mockChannel((call) async {
        calls.add(call);
        switch (call.method) {
          case 'resolveFolders':
            return <Object?>[];
          case 'pickFolder':
            return <String, Object?>{
              'id': 'bookmark-1',
              'name': 'Obsidian',
              'path': '/private/var/mobile/Obsidian',
            };
          case 'coordinatedRead':
            return Uint8List.fromList(<int>[1, 2, 3]);
          case 'coordinatedWrite':
            return null;
          default:
            return null;
        }
      });

      final folder = await ExternalFolderService.pick();

      expect(folder?.id, 'bookmark-1');
      expect(folder?.name, 'Obsidian');
      expect(
        ExternalFolderService.isExternal(
          '/private/var/mobile/Obsidian/Notes/a.md',
        ),
        isTrue,
      );
      expect(
        ExternalFolderService.folderIdOf(
          '/private/var/mobile/Obsidian/Notes/a.md',
        ),
        'bookmark-1',
      );
      expect(
        ExternalFolderService.isExternal('/private/var/mobile/Other/a.md'),
        isFalse,
      );

      final bytes = await ExternalFolderService.read(
        '/private/var/mobile/Obsidian/Notes/a.md',
      );
      expect(bytes, <int>[1, 2, 3]);

      await ExternalFolderService.write(
        '/private/var/mobile/Obsidian/Notes/a.md',
        Uint8List.fromList(<int>[9]),
      );

      expect(calls.map((call) => call.method), <String>[
        'resolveFolders',
        'pickFolder',
        'coordinatedRead',
        'coordinatedWrite',
      ]);
      final written = calls.last.arguments as Map<Object?, Object?>;
      expect(written['path'], '/private/var/mobile/Obsidian/Notes/a.md');
      expect(written['bytes'], Uint8List.fromList(<int>[9]));
    },
  );

  test('restore replaces the registered roots', () async {
    _mockChannel((call) async {
      if (call.method == 'resolveFolders') {
        return <Object?>[
          <String, Object?>{
            'id': 'a',
            'name': 'A',
            'path': '/private/var/mobile/A',
            'stale': false,
          },
          <String, Object?>{'id': 'b', 'name': 'B', 'path': ''},
        ];
      }
      return null;
    });

    final folders = await ExternalFolderService.restore();

    expect(folders.map((folder) => folder.id), <String>['a']);
    expect(ExternalFolderService.isExternal('/private/var/mobile/A/x'), isTrue);
    expect(
      ExternalFolderService.isExternal('/private/var/mobile/B/x'),
      isFalse,
    );
  });

  test('release forgets the root before the channel answers', () async {
    final calls = <MethodCall>[];
    _mockChannel((call) async {
      calls.add(call);
      if (call.method == 'resolveFolders') {
        return <Object?>[
          <String, Object?>{
            'id': 'a',
            'name': 'A',
            'path': '/private/var/mobile/A',
          },
        ];
      }
      return null;
    });

    await ExternalFolderService.restore();
    await ExternalFolderService.release('a');

    expect(
      ExternalFolderService.isExternal('/private/var/mobile/A/x'),
      isFalse,
    );
    expect(calls.last.method, 'releaseFolder');
    expect(calls.last.arguments, <String, Object?>{'id': 'a'});
  });

  test('list keeps placeholder rows and marks them not downloaded', () async {
    _mockChannel((call) async {
      if (call.method == 'resolveFolders') {
        return <Object?>[
          <String, Object?>{
            'id': 'a',
            'name': 'A',
            'path': '/private/var/mobile/A',
          },
        ];
      }
      if (call.method == 'folderList') {
        return <Object?>[
          <String, Object?>{
            'name': 'Notes',
            'path': '/private/var/mobile/A/Notes',
            'isDirectory': true,
            'size': 0,
            'downloaded': true,
          },
          <String, Object?>{
            'name': 'todo.md',
            'path': '/private/var/mobile/A/todo.md',
            'isDirectory': false,
            'size': 12,
            'downloaded': false,
          },
        ];
      }
      return null;
    });

    await ExternalFolderService.restore();
    final entries = await ExternalFolderService.list('/private/var/mobile/A');

    expect(entries, hasLength(2));
    expect(entries.first.isDirectory, isTrue);
    expect(entries.last.name, 'todo.md');
    expect(entries.last.downloaded, isFalse);
    expect(entries.last.size, 12);
  });

  test('a missing native handler degrades without throwing', () async {
    // 没有注册处理器：通道抛 MissingPluginException。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);

    expect(await ExternalFolderService.ensureAvailable(), isFalse);
    expect(await ExternalFolderService.pick(), isNull);
    expect(await ExternalFolderService.restore(), isEmpty);
    expect(
      ExternalFolderService.isExternal('/private/var/mobile/A/x'),
      isFalse,
    );
    await expectLater(
      ExternalFolderService.list('/private/var/mobile/A'),
      throwsA(isA<StateError>()),
    );
    // 握手结果缓存：第二次仍然安静返回 false。
    expect(await ExternalFolderService.ensureAvailable(), isFalse);
  });

  test('unsupported platforms never touch the channel', () async {
    ExternalFolderService.debugAssumeSupported = false;
    var called = false;
    _mockChannel((call) async {
      called = true;
      return null;
    });

    expect(await ExternalFolderService.ensureAvailable(), isFalse);
    expect(await ExternalFolderService.pick(), isNull);
    expect(called, isFalse);
  });
}
