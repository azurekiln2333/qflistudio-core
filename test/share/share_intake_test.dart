import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/share/share_inbox.dart';
import 'package:qfli_studio_core/share/share_intake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory projectRoot;
  late Project project;
  late Directory batchRoot;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('share_intake_test');
    projectRoot = Directory(p.join(temp.path, 'project'))..createSync();
    batchRoot = Directory(p.join(temp.path, 'batch'))..createSync();
    project = Project(
      id: 'p1',
      name: '示例项目',
      path: projectRoot.path,
      createdAt: DateTime(2025, 1, 1),
      lastOpenedAt: DateTime(2025, 1, 1),
    );
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  SharedIncomingFile writeFile(String name, String content) {
    final file = File(p.join(batchRoot.path, name))..writeAsStringSync(content);
    return SharedIncomingFile(
      path: file.path,
      name: name,
      bytes: content.length,
    );
  }

  ShareInboxBatch batchOf(List<SharedIncomingFile> files) {
    return ShareInboxBatch(
      id: 'b1',
      files: files,
      coldStart: false,
      source: 'send',
    );
  }

  test('文件复制进项目 inbox，返回相对路径', () async {
    final result = await copyBatchIntoProject(
      batch: batchOf(<SharedIncomingFile>[writeFile('a.txt', 'hello')]),
      project: project,
    );

    expect(result.isEmpty, isFalse);
    expect(result.relativePaths, <String>['inbox/a.txt']);
    expect(
      File(p.join(projectRoot.path, 'inbox', 'a.txt')).readAsStringSync(),
      'hello',
    );
  });

  test('重名文件改名为 name (1).ext', () async {
    final first = await copyBatchIntoProject(
      batch: batchOf(<SharedIncomingFile>[writeFile('a.txt', 'one')]),
      project: project,
    );
    final second = await copyBatchIntoProject(
      batch: batchOf(<SharedIncomingFile>[writeFile('a.txt', 'two')]),
      project: project,
    );

    expect(first.relativePaths, <String>['inbox/a.txt']);
    expect(second.relativePaths, <String>['inbox/a (1).txt']);
    expect(
      File(p.join(projectRoot.path, 'inbox', 'a (1).txt')).readAsStringSync(),
      'two',
    );
  });

  test('源文件不存在时记为跳过', () async {
    final missing = SharedIncomingFile(
      path: p.join(batchRoot.path, 'gone.txt'),
      name: 'gone.txt',
      bytes: 3,
    );

    final result = await copyBatchIntoProject(
      batch: batchOf(<SharedIncomingFile>[missing]),
      project: project,
    );

    expect(result.isEmpty, isTrue);
    expect(result.skipped, <String>['gone.txt']);
  });

  test('超过单文件上限的文件被跳过', () async {
    final file = writeFile('big.bin', 'x' * 32);

    final result = await copyBatchIntoProject(
      batch: batchOf(<SharedIncomingFile>[file]),
      project: project,
      maxFileBytes: 8,
    );

    expect(result.isEmpty, isTrue);
    expect(result.skipped, <String>['big.bin']);
    expect(Directory(p.join(projectRoot.path, 'inbox')).existsSync(), isFalse);
  });

  test('文件名里的路径分隔符被清掉', () {
    expect(sanitizeSharedFileName('../../etc/passwd'), 'passwd');
    expect(sanitizeSharedFileName(r'a\b:c.txt'), 'a_b_c.txt');
    expect(sanitizeSharedFileName('   '), 'shared-file');
  });

  test('子目录参数不能跳出项目', () async {
    final result = await copyBatchIntoProject(
      batch: batchOf(<SharedIncomingFile>[writeFile('a.txt', 'hello')]),
      project: project,
      subdirectory: '../outside',
    );

    expect(
      File(p.join(projectRoot.path, 'inbox', 'a.txt')).existsSync(),
      isTrue,
    );
    expect(result.relativePaths.single.startsWith('inbox/'), isTrue);
  });
}
