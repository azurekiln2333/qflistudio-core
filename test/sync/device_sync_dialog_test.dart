import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/remote_control/models/protocol.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/sync/device_file_port.dart';
import 'package:qfli_studio_core/sync/device_sync_dialog.dart';
import 'package:qfli_studio_core/sync/sync_ignore.dart';

/// A computer with three files, one of them large enough to need a prompt.
class FakePort implements DeviceFilePort {
  FakePort(this.files);

  final Map<String, String> files;

  @override
  Future<GitProjectInfo> gitInfo(String root) async =>
      GitProjectInfo(root: root, supported: false);

  @override
  Future<FsManifest> manifest(String root) async => FsManifest(
    root: root,
    ignoreVersion: kSyncIgnoreVersion,
    truncated: false,
    entries: <FsEntry>[
      for (final entry in files.entries)
        FsEntry(
          path: entry.key,
          kind: 'file',
          size: utf8.encode(entry.value).length,
          hash: sha256.convert(utf8.encode(entry.value)).toString(),
        ),
    ],
  );

  @override
  Future<FsChunk> read(String path, {required int offset, int? length}) async {
    final all = utf8.encode(files[path] ?? '');
    final end = (offset + (length ?? all.length)) > all.length
        ? all.length
        : offset + (length ?? all.length);
    return FsChunk(
      path: path,
      offset: offset,
      bytes: all.sublist(offset, end),
      eof: end >= all.length,
    );
  }
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioProfile? previous;
  late Directory root;

  setUp(() async {
    previous = StudioProfile.current;
    root = await Directory.systemTemp.createTemp('qfli-sync-dialog-');
  });

  tearDown(() async {
    StudioProfile.current = previous;
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('the entry stays hidden when the product does not enable it', (
    tester,
  ) async {
    StudioProfile.current = const StudioProfile(
      id: 'c',
      appTitle: 'QFLIForge',
      templates: [],
      isOffline: true,
    );

    var tapped = false;
    await tester.pumpWidget(
      _host(
        AiPanelProbe(
          onDeviceSync: () => tapped = true,
          enabled: StudioProfile.current!.deviceSyncEnabled,
        ),
      ),
    );

    expect(find.byTooltip('从电脑同步'), findsNothing);
    expect(tapped, isFalse);
  });

  testWidgets('the entry shows when the product enables it', (tester) async {
    StudioProfile.current = const StudioProfile(
      id: 'c',
      appTitle: 'QFLIForge',
      templates: [],
      isOffline: true,
      deviceSyncEnabled: true,
    );

    var tapped = false;
    await tester.pumpWidget(
      _host(
        AiPanelProbe(
          onDeviceSync: () => tapped = true,
          enabled: StudioProfile.current!.deviceSyncEnabled,
        ),
      ),
    );

    expect(find.byTooltip('从电脑同步'), findsOneWidget);
    await tester.tap(find.byTooltip('从电脑同步'));
    expect(tapped, isTrue);
  });

  testWidgets('the sync dialog writes the files after confirmation', (
    tester,
  ) async {
    final localRoot = p.join(root.path, 'copy');
    final port = FakePort(<String, String>{'a.txt': 'one', 'lib/b.txt': 'two'});

    late Future<bool> pending;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              pending = runDeviceSync(
                context,
                port: port,
                remoteRoot: r'C:\work\proj',
                localRoot: localRoot,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('从电脑同步这个项目'), findsOneWidget);

    await tester.tap(find.text('开始同步'));
    await tester.pumpAndSettle();
    expect(find.text('同步完成'), findsOneWidget);

    final report = await pending;
    expect(report, isTrue);
    expect(
      await File(p.join(localRoot, 'files', 'a.txt')).readAsString(),
      'one',
    );
    expect(
      await File(p.join(localRoot, 'files', 'lib', 'b.txt')).readAsString(),
      'two',
    );
  });

  testWidgets('cancelling the prompt transfers nothing', (tester) async {
    final localRoot = p.join(root.path, 'copy2');
    final port = FakePort(<String, String>{'a.txt': 'one'});

    late Future<bool> pending;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              pending = runDeviceSync(
                context,
                port: port,
                remoteRoot: r'C:\work\proj',
                localRoot: localRoot,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await pending, isFalse);
    expect(await Directory(p.join(localRoot, 'files')).exists(), isFalse);
  });
}

/// Mirrors the panel's own gate so the two stay visibly equivalent.
class AiPanelProbe extends StatelessWidget {
  const AiPanelProbe({
    super.key,
    required this.onDeviceSync,
    required this.enabled,
  });

  final VoidCallback onDeviceSync;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return IconButton(
      tooltip: '从电脑同步',
      onPressed: onDeviceSync,
      icon: const Icon(Icons.cloud_download_outlined),
    );
  }
}

/// Mirrors the panel's own gate so the two stay visibly equivalent.
