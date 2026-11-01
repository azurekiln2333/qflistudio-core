import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/models/project.dart';

/// Refreshing an open file after an AI tool wrote it must never replace text
/// the user typed but did not save.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late EditorController editor;
  late String filePath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vibe_reload_');
    filePath = p.join(root.path, 'main.py');
    await File(filePath).writeAsString('print(1)\n', flush: true);
    editor = EditorController(
      project: Project.create(name: 'demo', path: root.path),
    );
  });

  tearDown(() async {
    editor.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('reloads a clean buffer from disk', (tester) async {
    await tester.runAsync(() async {
      expect(await editor.openPath(filePath), isNull);
      await File(filePath).writeAsString('print(2)\n', flush: true);
      final open = editor.current!;
      expect(await editor.reloadFromDisk(open), isNull);
      expect(open.controller.text, 'print(2)\n');
      expect(open.dirty, isFalse);
    });
  });

  testWidgets('keeps a dirty buffer and reports it', (tester) async {
    await tester.runAsync(() async {
      expect(await editor.openPath(filePath), isNull);
      final open = editor.current!;
      open.controller.text = 'print("user")\n';
      await tester.pump();
      expect(open.dirty, isTrue);

      await File(filePath).writeAsString('print("agent")\n', flush: true);
      final error = await editor.reloadFromDisk(open);
      expect(error, contains('未保存'));
      expect(open.controller.text, 'print("user")\n');
      expect(open.dirty, isTrue);
    });
  });

  testWidgets('an unchanged file keeps the cursor selection', (tester) async {
    await tester.runAsync(() async {
      expect(await editor.openPath(filePath), isNull);
      final open = editor.current!;
      final before = open.controller.selection;
      expect(await editor.reloadFromDisk(open), isNull);
      expect(open.controller.selection, before);
      expect(open.controller.text, 'print(1)\n');
    });
  });
}
