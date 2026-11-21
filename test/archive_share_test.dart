import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/archive_share_service.dart';
import 'package:qfli_studio_core/services/project_zip_service.dart';
import 'package:qfli_studio_core/services/share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late PathProviderPlatform original;
  const channel = MethodChannel('qflistudio/platform');

  setUp(() async {
    fixture = await Directory.systemTemp.createTemp('qfli-share-test-');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(p.join(fixture.path, 'support'));
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PathProviderPlatform.instance = original;
    await fixture.delete(recursive: true);
  });

  Future<String> file(String path, List<int> bytes) async {
    final target = File(p.join(fixture.path, path));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes);
    return target.path;
  }

  test(
    'selection ZIP contains selected binary only, not siblings or metadata',
    () async {
      final selected = await file('project/src/data.bin', [0, 255, 128, 0]);
      await file('project/private.txt', [9]);
      await file('project/.qfli/project.json', [123, 125]);
      final destination = p.join(fixture.path, 'file.zip');
      await ProjectZipService.exportSelectionToFile(
        projectRoot: p.join(fixture.path, 'project'),
        selectedPath: selected,
        destination: destination,
      );
      final zip = ZipDecoder().decodeBytes(
        await File(destination).readAsBytes(),
      );
      expect(zip.map((entry) => entry.name), ['data.bin']);
      expect(zip.single.content, [0, 255, 128, 0]);
    },
  );

  test(
    'folder ZIP preserves only its selected subtree and empty folders',
    () async {
      await file('project/src/one.bin', [1, 2, 3]);
      await file('project/other/two.bin', [4]);
      await Directory(p.join(fixture.path, 'project/src/empty')).create();
      final destination = p.join(fixture.path, 'folder.zip');
      await ProjectZipService.exportSelectionToFile(
        projectRoot: p.join(fixture.path, 'project'),
        selectedPath: p.join(fixture.path, 'project/src'),
        destination: destination,
      );
      final zip = ZipDecoder().decodeBytes(
        await File(destination).readAsBytes(),
      );
      expect(zip.find('src/one.bin')!.content, [1, 2, 3]);
      expect(zip.find('src/empty/')!.isDirectory, isTrue);
      expect(zip.find('other/two.bin'), isNull);
      expect(zip.find('.qfli/project.json'), isNull);
    },
  );

  test('outside selection and project-local output are rejected', () async {
    final selected = await file('project/one.bin', [1]);
    final outside = await file('outside.bin', [2]);
    final root = p.join(fixture.path, 'project');
    await expectLater(
      ProjectZipService.exportSelectionToFile(
        projectRoot: root,
        selectedPath: outside,
        destination: p.join(fixture.path, 'outside.zip'),
      ),
      throwsA(isA<ProjectZipException>()),
    );
    await expectLater(
      ProjectZipService.exportSelectionToFile(
        projectRoot: root,
        selectedPath: selected,
        destination: p.join(root, 'recursive.zip'),
      ),
      throwsA(isA<ProjectZipException>()),
    );
  });

  test(
    'links are rejected before ZIP handoff',
    () async {
      await file('project/keep', [1]);
      final outside = await file('outside/data', [99]);
      await Link(
        p.join(fixture.path, 'project/escape'),
      ).create(p.dirname(outside));
      await expectLater(
        ProjectZipService.exportSelectionToFile(
          projectRoot: p.join(fixture.path, 'project'),
          selectedPath: p.join(fixture.path, 'project/escape/data'),
          destination: p.join(fixture.path, 'escape.zip'),
        ),
        throwsA(isA<ProjectZipException>()),
      );
    },
    skip: Platform.isWindows
        ? 'Symlink creation requires host privileges.'
        : false,
  );

  test(
    'native ZIP handoff uses MIME and retains archive after dismissal',
    () async {
      await file('project/one.bin', [0, 255]);
      MethodCall? request;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            request = call;
            expect(
              await File((call.arguments as Map)['path'] as String).exists(),
              isTrue,
            );
            return true; // Handoff, not proof of recipient delivery.
          });
      final project = Project.create(
        name: 'project',
        path: p.join(fixture.path, 'project'),
      );
      final result = await ArchiveShareService.shareSelection(
        project,
        selectedPath: project.path,
      );
      expect(result.status, ArchiveShareStatus.shared);
      expect(request!.method, 'shareFile');
      expect((request!.arguments as Map)['mimeType'], 'application/zip');
      expect(result.path, endsWith('.zip'));
      expect(await File(result.path).exists(), isTrue);
      expect(await File(p.join(project.path, 'one.bin')).readAsBytes(), [
        0,
        255,
      ]);
    },
  );

  test(
    'unsupported retains ZIP for save and cloud without snapshot cannot share',
    () async {
      await file('project/one.bin', [7]);
      var shares = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            shares++;
            return false;
          });
      final project = Project.create(
        name: 'project',
        path: p.join(fixture.path, 'project'),
      );
      final result = await ArchiveShareService.shareSelection(
        project,
        selectedPath: project.path,
      );
      expect(result.status, ArchiveShareStatus.unsupported);
      expect(await File(result.path).exists(), isTrue);
      project.cloudId = 'proj_missing_snapshot';
      await expectLater(
        ArchiveShareService.shareSelection(project, selectedPath: project.path),
        throwsA(isA<ProjectZipException>()),
      );
      expect(
        shares,
        1,
        reason: 'An incomplete cloud export never opens native sharing.',
      );
    },
  );

  test('native failure is not silently reported as unsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'SHARE_FAILED', message: 'Unavailable');
        });
    await expectLater(
      ShareService.shareFile(path: '/prepared/file.zip', title: 'archive'),
      throwsA(isA<PlatformException>()),
    );
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}
