import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/file_backup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backed-up saves retain each workspace file owner', () async {
    final directory = await Directory.systemTemp.createTemp(
      'qfli_workspace_backup_',
    );
    final previousBase = FileBackup.baseOverride;
    final primary = Project.create(
      name: 'Primary owner',
      path: p.join(directory.path, 'primary'),
    );
    final secondary = Project.create(
      name: 'Secondary owner',
      path: p.join(directory.path, 'secondary'),
      type: 'cpp',
      language: 'C++',
    );
    final editor = EditorController(project: primary);
    FileBackup.baseOverride = p.join(directory.path, 'backups');
    addTearDown(() async {
      editor.dispose();
      FileBackup.baseOverride = previousBase;
      await directory.delete(recursive: true);
    });

    final primaryFile = File(p.join(primary.path, 'main.txt'));
    final secondaryFile = File(p.join(secondary.path, 'main.txt'));
    await primaryFile.parent.create(recursive: true);
    await secondaryFile.parent.create(recursive: true);
    await primaryFile.writeAsString('primary original');
    await secondaryFile.writeAsString('secondary original');

    expect(await editor.openPath(primaryFile.path), isNull);
    final primaryTab = editor.current!;
    expect(
      await editor.openPath(
        secondaryFile.path,
        ownerProjectName: secondary.name,
        ownerProjectPath: secondary.path,
        ownerProjectType: secondary.type,
      ),
      isNull,
    );
    final secondaryTab = editor.current!;
    primaryTab.controller.text = 'primary edited';
    secondaryTab.controller.text = 'secondary edited';

    // A tab's backup belongs to its owner even while another tab is selected.
    editor.select(0);
    expect(await editor.saveFile(secondaryTab, backup: true), isNull);
    expect(await secondaryFile.readAsString(), 'secondary edited');
    final secondaryVersions = await FileBackup.listVersions(
      secondaryFile,
      projectName: secondary.name,
    );
    expect(secondaryVersions, hasLength(1));
    expect(
      await secondaryVersions.single.file.readAsString(),
      'secondary original',
    );
    final metadata =
        jsonDecode(
              await File(
                '${secondaryVersions.single.file.path}.metadata.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(metadata['projectName'], secondary.name);
    expect(metadata['originalPath'], p.normalize(secondaryFile.absolute.path));
    expect(
      await FileBackup.listVersions(secondaryFile, projectName: primary.name),
      isEmpty,
    );

    expect(await editor.saveFile(primaryTab, backup: true), isNull);
    expect(await primaryFile.readAsString(), 'primary edited');
    final primaryVersions = await FileBackup.listVersions(
      primaryFile,
      projectName: primary.name,
    );
    expect(primaryVersions, hasLength(1));
    expect(
      await primaryVersions.single.file.readAsString(),
      'primary original',
    );
    expect(
      await FileBackup.listVersions(primaryFile, projectName: secondary.name),
      isEmpty,
    );
  });
}
