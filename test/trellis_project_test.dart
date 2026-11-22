import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/trellis/trellis_panel.dart';
import 'package:qfli_studio_core/trellis/trellis_project.dart';

import 'support/trellis_fixture.dart';

void main() {
  group('detection', () {
    test('requires a normal, nonempty workflow file', () {
      final root = Directory.systemTemp.createTempSync('trellis-detect-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      expect(TrellisProject.hasWorkflow(root.path), isFalse);
      Directory(p.join(root.path, '.trellis')).createSync();
      expect(TrellisProject.hasWorkflow(root.path), isFalse);
      File(
        p.join(root.path, '.trellis', 'workflow.md'),
      ).writeAsStringSync('  \n');
      expect(TrellisProject.hasWorkflow(root.path), isFalse);
      File(
        p.join(root.path, '.trellis', 'workflow.md'),
      ).writeAsStringSync('# w');
      expect(TrellisProject.hasWorkflow(root.path), isTrue);
    });

    test('a linked .trellis directory is not a project', () {
      final root = Directory.systemTemp.createTempSync('trellis-detect-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final real = Directory(p.join(root.path, 'real'))..createSync();
      File(p.join(real.path, 'workflow.md')).writeAsStringSync('# w');
      final link = Link(p.join(root.path, '.trellis'));
      try {
        link.createSync(real.path);
      } on FileSystemException {
        // 没有建链接权限的宿主跳过这条断言。
        return;
      }
      expect(TrellisProject.hasWorkflow(root.path), isFalse);
    });

    test('load returns null without a workflow', () async {
      final root = Directory.systemTemp.createTempSync('trellis-detect-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      expect(await TrellisProject.load(root.path), isNull);
    });
  });

  group('task reading', () {
    test('reads tasks, developer, docs and spec indexes', () async {
      final root = makeTrellisProject();
      final project = await TrellisProject.load(root.path);
      expect(project, isNotNull);
      expect(project!.developer, 'lichengyu');
      expect(project.tasks.map((task) => task.dirName), [
        '11-22-child',
        '11-22-harness-hub',
        '11-30-archived',
      ]);
      expect(project.specIndexes.map((index) => index.layer), [
        'backend',
        'frontend',
      ]);
      final hub = project.taskNamed('11-22-harness-hub')!;
      expect(hub.title, 'Studio 内置完整 harness 体验');
      expect(hub.status, 'in_progress');
      expect(hub.phase, TrellisTaskPhase.executing);
      expect(hub.phase.step, '2.1');
      expect(hub.existingDocs, ['prd.md', 'design.md']);
      expect(hub.relativePath, '.trellis/tasks/11-22-harness-hub');
      expect(hub.docs.map((doc) => doc.exists), [true, true, false]);
      expect(hub.children, ['11-22-child']);
    });

    test('skips broken task files without failing the project', () async {
      final root = makeTrellisProject();
      writeFixture(root, '.trellis/tasks/99-broken/task.json', '{not json');
      writeFixture(root, '.trellis/tasks/98-empty/task.json', '{"id":"x"}');
      final project = await TrellisProject.load(root.path);
      expect(project!.tasks.map((task) => task.dirName), [
        '11-22-child',
        '11-22-harness-hub',
        '11-30-archived',
      ]);
    });

    test('keeps completed tasks out of the active list', () async {
      final project = await TrellisProject.load(makeTrellisProject().path);
      expect(project!.activeTasks.map((task) => task.dirName), [
        '11-22-child',
        '11-22-harness-hub',
      ]);
      expect(project.activeTasksOf('lichengyu').map((task) => task.dirName), [
        '11-22-child',
        '11-22-harness-hub',
      ]);
      expect(
        project.taskNamed('11-30-archived')!.phase,
        TrellisTaskPhase.finishing,
      );
    });
  });

  group('current task', () {
    test('takes the newest runtime pointer', () async {
      final project = await TrellisProject.load(makeTrellisProject().path);
      expect(project!.currentTask?.dirName, '11-22-harness-hub');
    });

    test('honors an explicit override', () async {
      final project = await TrellisProject.load(
        makeTrellisProject().path,
        currentTaskName: '11-22-child',
      );
      expect(project!.currentTask?.dirName, '11-22-child');
    });

    test('normalizes a task reference to its directory name', () {
      expect(
        taskNameOfRef('.trellis/tasks/11-22-harness-hub'),
        '11-22-harness-hub',
      );
      expect(taskNameOfRef('11-22-harness-hub/'), '11-22-harness-hub');
      expect(taskNameOfRef(''), isNull);
      expect(taskNameOfRef(null), isNull);
    });
  });

  group('panel', () {
    test('puts parents before children and keeps my tasks', () async {
      final project = await TrellisProject.load(makeTrellisProject().path);
      final panel = buildTrellisTaskPanel(project!);
      expect(panel.developer, 'lichengyu');
      expect(panel.currentTask?.dirName, '11-22-harness-hub');
      expect(panel.activeTasks.map((row) => row.task.dirName), [
        '11-22-harness-hub',
        '11-22-child',
      ]);
      expect(panel.activeTasks.last.indent, 1);
      expect(panel.myTasks.length, 2);
      expect(panel.workflowPath, '.trellis/workflow.md');
      expect(panel.isEmpty, isFalse);
    });

    test('survives a task graph whose children point at each other', () async {
      final root = Directory.systemTemp.createTempSync('trellis-loop-')
        ..createSync(recursive: true);
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      writeFixture(root, '.trellis/workflow.md', '# Workflow\n');
      writeFixtureTask(root, 'a', {
        'id': 'a',
        'title': '父任务',
        'status': 'in_progress',
        'children': ['b'],
      });
      // b 把自己当作子任务：不设环保护时 append 会一直递归。
      writeFixtureTask(root, 'b', {
        'id': 'b',
        'title': '自指任务',
        'status': 'planning',
        'children': ['b'],
      });

      final project = await TrellisProject.load(root.path);
      final panel = buildTrellisTaskPanel(project!);

      expect(panel.activeTasks.map((row) => row.task.dirName).toList(), [
        'a',
        'b',
      ]);
    });

    test('a project with only spec indexes is not empty', () async {
      final root = Directory.systemTemp.createTempSync('trellis-spec-')
        ..createSync(recursive: true);
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      writeFixture(root, '.trellis/workflow.md', '# Workflow\n');
      writeFixture(root, '.trellis/spec/frontend/index.md', '# Frontend\n');

      final project = await TrellisProject.load(root.path);
      final panel = buildTrellisTaskPanel(project!);

      expect(panel.specIndexes, isNotEmpty);
      expect(panel.isEmpty, isFalse);
    });
  });
}
