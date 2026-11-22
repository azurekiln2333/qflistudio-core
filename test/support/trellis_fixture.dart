import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 一个最小 Trellis 夹具项目：工作流、开发者、两个活跃任务、一层规范。
///
/// 只能在测试体内调用：它用 `addTearDown` 删除临时目录。
Directory makeTrellisProject() {
  final root = Directory.systemTemp.createTempSync('trellis-project-');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  writeFixture(
    root,
    '.trellis/workflow.md',
    '## Phase Index\n\nPhase 1: Plan\n',
  );
  writeFixture(
    root,
    '.trellis/.developer',
    'name=lichengyu\ninitialized_at=now\n',
  );
  writeFixture(root, '.trellis/spec/frontend/index.md', '# Frontend\n');
  writeFixture(root, '.trellis/spec/backend/index.md', '# Backend\n');
  writeFixtureTask(root, '11-22-harness-hub', {
    'id': 'harness-hub',
    'title': 'Studio 内置完整 harness 体验',
    'description': '统一本机与远程会话',
    'status': 'in_progress',
    'priority': 'P2',
    'assignee': 'lichengyu',
    'creator': 'lichengyu',
    'createdAt': '2026-11-22',
    'children': ['11-22-child'],
  });
  writeFixtureTask(root, '11-22-child', {
    'id': 'child',
    'title': '子任务',
    'status': 'planning',
    'assignee': 'lichengyu',
    'parent': '11-22-harness-hub',
  });
  writeFixtureTask(root, '11-30-archived', {
    'id': 'done-one',
    'title': '已归档任务',
    'status': 'completed',
    'assignee': 'other',
  });
  writeFixture(root, '.trellis/tasks/11-22-harness-hub/prd.md', '# PRD\n');
  writeFixture(
    root,
    '.trellis/tasks/11-22-harness-hub/design.md',
    '# Design\n',
  );
  writeFixture(
    root,
    '.trellis/.runtime/sessions/pi_1.json',
    jsonEncode({
      'platform': 'pi',
      'last_seen_at': '2026-11-22T10:00:00Z',
      'current_task': '.trellis/tasks/11-22-harness-hub',
    }),
  );
  writeFixture(
    root,
    '.trellis/.runtime/sessions/claude_1.json',
    jsonEncode({
      'platform': 'claude',
      'last_seen_at': '2026-11-21T10:00:00Z',
      'current_task': '.trellis/tasks/11-22-child',
    }),
  );
  return root;
}

/// 在夹具项目里写一个文件，自动建父目录。
void writeFixture(Directory root, String relative, String text) {
  final file = File(p.joinAll([root.path, ...relative.split('/')]));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

/// 在夹具项目里写一份 `task.json`。
void writeFixtureTask(Directory root, String name, Map<String, Object?> json) =>
    writeFixture(root, '.trellis/tasks/$name/task.json', jsonEncode(json));
