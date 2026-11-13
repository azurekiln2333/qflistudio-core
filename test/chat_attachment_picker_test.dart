import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/chat/attachment_picker.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('qfli-attachments-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File write(String relative) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('x');
    return file;
  }

  group('project files', () {
    test(
      'lists nested files as relative paths and skips build output',
      () async {
        write('src/Main.java');
        write('src/util/Util.java');
        write('build/app.dll');
        write('.hidden/secret.txt');

        final files = await listProjectAttachments(root.path);

        expect(files.map((file) => file.label), [
          'src/Main.java',
          'src/util/Util.java',
        ]);
        // 项目内文件传相对路径：agent 的 read_file 只接受相对路径。
        expect(files.map((file) => file.path), [
          'src/Main.java',
          'src/util/Util.java',
        ]);
        expect(files.every((file) => file.readOnly), isFalse);
      },
    );

    test(
      'a missing directory yields an empty list instead of throwing',
      () async {
        final files = await listProjectAttachments(p.join(root.path, 'nope'));
        expect(files, isEmpty);
      },
    );

    test('the limit caps a large tree', () async {
      for (var i = 0; i < 12; i++) {
        write('src/F$i.java');
      }
      final files = await listProjectAttachments(root.path, limit: 5);
      expect(files, hasLength(5));
    });
  });

  group('workspace files', () {
    test('lists the other members of the same workspace', () async {
      final other = Directory.systemTemp.createTempSync('qfli-ws-other-');
      addTearDown(() {
        if (other.existsSync()) other.deleteSync(recursive: true);
      });
      File(p.join(other.path, 'Util.java')).writeAsStringSync('x');
      write('Main.java');

      final workspace = SavedWorkspace(
        id: 'w1',
        name: '示例工作区',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        members: [
          WorkspaceMember(
            projectId: 'p1',
            path: root.path,
            name: '本项目',
            primary: true,
          ),
          WorkspaceMember(projectId: 'p2', path: other.path, name: '另一个项目'),
        ],
      );

      final files = await listWorkspaceAttachments(
        projectRoot: root.path,
        workspaces: [workspace],
      );

      expect(files, hasLength(1));
      expect(files.single.label, 'Util.java');
      expect(files.single.group, '另一个项目');
      // 跨项目文件不在项目根内，只能传绝对路径，agent 读得到但只能读。
      expect(files.single.path, p.join(other.path, 'Util.java'));
      expect(files.single.readOnly, isTrue);
    });

    test('a project outside every workspace has no workspace files', () async {
      final files = await listWorkspaceAttachments(
        projectRoot: root.path,
        workspaces: const [],
      );
      expect(files, isEmpty);
    });
  });

  group('picker sheet', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('selection is returned when confirming', (tester) async {
      List<String>? picked;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showModalBottomSheet<List<String>>(
                  context: context,
                  builder: (context) => AttachmentPickerSheet(
                    source: AttachmentSource.project,
                    load: () async => const [
                      AttachmentFile(
                        label: 'src/Main.java',
                        path: '/p/src/Main.java',
                        group: 'p',
                      ),
                      AttachmentFile(
                        label: 'src/Util.java',
                        path: '/p/src/Util.java',
                        group: 'p',
                      ),
                    ],
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('项目文件'), findsOneWidget);
      expect(find.text('src/Main.java'), findsOneWidget);

      await tester.tap(find.text('src/Util.java'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('attachment-confirm')));
      await tester.pumpAndSettle();

      expect(picked, ['/p/src/Util.java']);
    });

    testWidgets('an empty source explains what to do instead', (tester) async {
      await tester.pumpWidget(
        host(
          AttachmentPickerSheet(
            source: AttachmentSource.workspace,
            load: () async => const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('没有找到工作区文件'), findsOneWidget);
      expect(find.textContaining('加入同一工作区'), findsOneWidget);
    });

    testWidgets('the workspace note explains the files are read only', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AttachmentPickerSheet(
            source: AttachmentSource.workspace,
            load: () async => const [
              AttachmentFile(
                label: 'Util.java',
                path: '/other/Util.java',
                group: '另一个项目',
                readOnly: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('只读'), findsOneWidget);
      // 旧文案已撑销：跨项目文件现在读得到。
      expect(find.textContaining('取不到正文'), findsNothing);
      expect(find.textContaining('只能看到路径'), findsNothing);
    });
  });
}
