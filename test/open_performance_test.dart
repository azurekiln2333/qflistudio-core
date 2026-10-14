import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/editor/file_explorer.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/file_service.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';

/// Repeatable measurement harness for the project-open path.
///
/// Only the two `LocalStoreBackend`-free, IO-only paths are measured here.
/// `EditorPage` and `EditorController` could **not** be timed inside a widget
/// test: they do real file IO and keep timers alive, and every attempt to await
/// them hung the runner even with bounded pumps (see `notes/perf.md`). Their
/// timings are captured on device through the `QFLI_PERF` switch instead.
///
/// Run with `flutter test --timeout 60s test/open_performance_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform originalPaths;
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_perf_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TempPaths(root.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
    await TaskActivityService.instance.initialize();
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPaths;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A project with [files] Java sources spread over [nested] directories.
  Directory buildProject({required int files, required int nested}) {
    final directory = Directory(
      p.join(root.path, 'perf_${files}_$nested'),
    )..createSync(recursive: true);
    final perDir = (files ~/ nested).clamp(1, files);
    for (var i = 0; i < nested; i++) {
      final sub = Directory(p.join(directory.path, 'pkg$i'))
        ..createSync(recursive: true);
      for (var j = 0; j < perDir; j++) {
        File(p.join(sub.path, 'C${i}_$j.java')).writeAsStringSync(
          'class C${i}_$j {\n  void run() {}\n}\n',
        );
      }
    }
    File(p.join(directory.path, 'Main.java')).writeAsStringSync(
      'class Main {\n  public static void main(String[] a) {}\n}\n',
    );
    final config = File(ProjectConfig.configPath(directory.path));
    config.parent.createSync(recursive: true);
    config.writeAsStringSync('{"version":1,"entryFile":"Main.java"}');
    return directory;
  }

  testWidgets('MEASURE: file tree top-level listing', (tester) async {
    final directory = buildProject(files: 400, nested: 40);
    final stopwatch = Stopwatch()..start();
    final entries = FileService.listSortedSync(directory.path);
    stopwatch.stop();
    // ignore: avoid_print
    print(
      'MEASURE file-tree top-level list: ${stopwatch.elapsedMicroseconds} us '
      'for ${entries.length} entries',
    );
    expect(entries, isNotEmpty);
  });

  testWidgets('MEASURE: recursive file search', (tester) async {
    final directory = buildProject(files: 400, nested: 40);
    final stopwatch = Stopwatch()..start();
    final results = FileExplorer.searchFiles(directory.path, 'C1');
    stopwatch.stop();
    // ignore: avoid_print
    print(
      'MEASURE recursive search: ${stopwatch.elapsedMicroseconds} us '
      'for ${results.length} hits',
    );
  });
}

class _TempPaths extends PathProviderPlatform {
  _TempPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}
