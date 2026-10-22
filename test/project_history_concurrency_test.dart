import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/project_history.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qfli_history_queue_');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  const cursor = FileCursor(
    baseIndex: 3,
    baseOffset: 2,
    extentIndex: 3,
    extentOffset: 5,
  );

  Future<void> saveSession(String path, String file) => ProjectHistory.save(
    path,
    cursors: {file: cursor},
    openFiles: [file],
    activeFile: file,
  );

  for (final expansionFirst in [true, false]) {
    test(
      'concurrent updates preserve both fields, expansionFirst=$expansionFirst',
      () async {
        await saveSession(root.path, 'old.json');
        final updates = expansionFirst
            ? [
                ProjectHistory.saveExpandedDirs(root.path, ['src', 'src/data']),
                saveSession(root.path, 'new.json'),
              ]
            : [
                saveSession(root.path, 'new.json'),
                ProjectHistory.saveExpandedDirs(root.path, ['src', 'src/data']),
              ];
        await Future.wait(updates);

        final session = await ProjectHistory.load(root.path);
        expect(session.openFiles, ['new.json']);
        expect(session.activeFile, 'new.json');
        expect(session.cursors['new.json']?.extentOffset, 5);
        expect(session.expandedDirs, ['src', 'src/data']);
      },
    );
  }

  test(
    'load observes queued writes and each field keeps the latest update',
    () async {
      final pending = <Future<void>>[];
      for (var index = 0; index < 12; index++) {
        pending.add(saveSession(root.path, 'file-$index.json'));
        pending.add(ProjectHistory.saveExpandedDirs(root.path, ['dir-$index']));
      }

      // Call before awaiting the writes, as a reopened sidebar does.
      final session = await ProjectHistory.load(root.path);
      expect(session.openFiles, ['file-11.json']);
      expect(session.activeFile, 'file-11.json');
      expect(session.expandedDirs, ['dir-11']);
      await Future.wait(pending);
    },
  );

  test('queued writes capture collections when save is called', () async {
    final files = ['data.json'];
    final cursors = {'data.json': cursor};
    final dirs = ['src'];
    final save = ProjectHistory.save(
      root.path,
      cursors: cursors,
      openFiles: files,
      activeFile: 'data.json',
      expandedDirs: dirs,
    );
    files.clear();
    cursors.clear();
    dirs.clear();
    await save;

    final expanded = ['src/data'];
    final expansionSave = ProjectHistory.saveExpandedDirs(root.path, expanded);
    expanded.clear();
    await expansionSave;

    final session = await ProjectHistory.load(root.path);
    expect(session.openFiles, ['data.json']);
    expect(session.cursors['data.json']?.baseIndex, 3);
    expect(session.expandedDirs, ['src/data']);
  });

  test(
    'normalized aliases serialize updates to the same history file',
    () async {
      await Directory(p.join(root.path, 'nested')).create();
      final alias = p.join(root.path, 'nested', '..');
      await Future.wait([
        saveSession(root.path, 'data.json'),
        ProjectHistory.saveExpandedDirs(alias, ['src']),
      ]);

      final session = await ProjectHistory.load(root.path);
      expect(session.openFiles, ['data.json']);
      expect(session.expandedDirs, ['src']);
    },
  );

  test('physical directory aliases share the history write lane', () async {
    final real = await Directory(p.join(root.path, 'real')).create();
    final alias = Link(p.join(root.path, 'alias'));
    try {
      await alias.create(real.path);
    } on FileSystemException catch (error) {
      markTestSkipped('Directory links unavailable: ${error.osError}');
      return;
    }
    final pending = <Future<void>>[];
    for (var index = 0; index < 12; index++) {
      pending.add(saveSession(real.path, 'file-$index.json'));
      pending.add(ProjectHistory.saveExpandedDirs(alias.path, ['dir-$index']));
      pending.add(ProjectHistory.saveWorkspaceRoots(alias.path, [real.path]));
    }
    final session = await ProjectHistory.load(alias.path);
    expect(session.openFiles, ['file-11.json']);
    expect(session.expandedDirs, ['dir-11']);
    expect(session.workspaceRoots, [real.path]);
    await Future.wait(pending);
    expect((await ProjectHistory.load(real.path)).openFiles, ['file-11.json']);
  });

  test('different projects keep independent sessions and expansions', () async {
    final other = p.join(root.path, 'other');
    await Future.wait([
      saveSession(root.path, 'one.json'),
      saveSession(other, 'two.json'),
      ProjectHistory.saveExpandedDirs(root.path, ['one']),
      ProjectHistory.saveExpandedDirs(other, ['two']),
    ]);

    final first = await ProjectHistory.load(root.path);
    final second = await ProjectHistory.load(other);
    expect(first.openFiles, ['one.json']);
    expect(first.expandedDirs, ['one']);
    expect(second.openFiles, ['two.json']);
    expect(second.expandedDirs, ['two']);
  });

  test(
    'legacy sessions default to an expanded root and no extra workspace roots',
    () async {
      await ProjectHistory.historyFile(root.path).writeAsString(
        jsonEncode({
          'version': 1,
          'openFiles': ['data.json'],
          'activeFile': 'data.json',
          'expandedDirs': ['src'],
          'files': {},
        }),
      );
      final session = await ProjectHistory.load(root.path);
      expect(session.treeRootExpanded, isTrue);
      expect(session.workspaceRoots, isEmpty);
      expect(session.openFiles, ['data.json']);
      expect(session.expandedDirs, ['src']);
    },
  );

  test(
    'workspace, root expansion and editor updates merge without lost fields',
    () async {
      final roots = [root.path, p.join(root.path, 'other')];
      final membership = ProjectHistory.saveWorkspaceRoots(root.path, roots);
      roots.clear();
      await Future.wait([
        membership,
        ProjectHistory.saveExpandedDirs(root.path, [
          'src',
        ], treeRootExpanded: false),
        saveSession(root.path, 'data.json'),
      ]);
      final session = await ProjectHistory.load(root.path);
      expect(session.workspaceRoots, [root.path, p.join(root.path, 'other')]);
      expect(session.treeRootExpanded, isFalse);
      expect(session.expandedDirs, ['src']);
      expect(session.openFiles, ['data.json']);
      expect(session.cursors['data.json']?.baseIndex, 3);
    },
  );

  test(
    'malformed workspace rows do not discard valid tabs or legacy history',
    () async {
      final document = ProjectDocumentSession(
        projectPath: root.path,
        relativePath: 'valid.dart',
        cursor: cursor,
        isActive: true,
      );
      await ProjectHistory.historyFile(root.path).writeAsString(
        jsonEncode({
          'openFiles': ['legacy.dart'],
          'activeFile': 'legacy.dart',
          'files': {},
          'documents': [
            null,
            {'projectPath': root.path},
            {
              'projectPath': root.path,
              'relativePath': 'bad.dart',
              'cursor': {'baseIndex': 'bad'},
            },
            document.toJson(),
          ],
        }),
      );
      final session = await ProjectHistory.load(root.path);
      expect(session.openFiles, ['legacy.dart']);
      expect(session.documents.single.relativePath, 'valid.dart');
      expect(session.documents.single.cursor.extentOffset, 5);
    },
  );

  test(
    'workspace document snapshots merge with concurrent tree and membership writes',
    () async {
      final documents = [
        ProjectDocumentSession(
          projectPath: p.join(root.path, 'other'),
          relativePath: 'src/main.cpp',
          cursor: cursor,
          isActive: true,
        ),
      ];
      final save = ProjectHistory.save(
        root.path,
        cursors: {},
        openFiles: [],
        activeFile: null,
        documents: documents,
      );
      documents.clear();
      await Future.wait([
        save,
        ProjectHistory.saveExpandedDirs(root.path, [
          'src',
        ], treeRootExpanded: false),
        ProjectHistory.saveWorkspaceRoots(root.path, [
          root.path,
          p.join(root.path, 'other'),
        ]),
        saveSession(root.path, 'legacy.json'),
      ]);
      final session = await ProjectHistory.load(root.path);
      expect(session.documents.single.relativePath, 'src/main.cpp');
      expect(session.documents.single.cursor.extentOffset, 5);
      expect(session.documents.single.isActive, isTrue);
      expect(session.workspaceRoots, hasLength(2));
      expect(session.expandedDirs, ['src']);
      expect(session.treeRootExpanded, isFalse);
      expect(session.openFiles, ['legacy.json']);
    },
  );
}
