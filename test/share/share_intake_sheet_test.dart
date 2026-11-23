import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/session/agent_session.dart';
import 'package:qfli_studio_core/share/share_inbox.dart';
import 'package:qfli_studio_core/share/share_intake_sheet.dart';

void main() {
  final project = Project(
    id: 'p1',
    name: '示例项目',
    path: 'demo',
    createdAt: DateTime(2025, 1, 1),
    lastOpenedAt: DateTime(2025, 1, 1),
  );

  final batch = ShareInboxBatch(
    id: 'b1',
    files: const <SharedIncomingFile>[
      SharedIncomingFile(path: '/tmp/a.txt', name: 'a.txt', bytes: 3),
    ],
    coldStart: false,
    source: 'send',
  );

  final session = AgentSessionMeta(
    id: 's1',
    projectId: 'p1',
    title: '上次的会话',
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime(2025, 1, 1),
    messageCount: 2,
    preview: '继续',
  );

  Future<List<ShareIntakeChoice?>> pumpSheet(
    WidgetTester tester, {
    List<AgentSessionMeta> sessions = const <AgentSessionMeta>[],
  }) async {
    final choices = <ShareIntakeChoice?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  choices.add(
                    await showShareIntakeSheet(
                      context,
                      batch: batch,
                      projects: <Project>[project],
                      sessionsOf: (_) => sessions,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return choices;
  }

  testWidgets('默认面板列出两个去处', (tester) async {
    await pumpSheet(tester);

    expect(find.byKey(const ValueKey('share-intake-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('share-intake-files')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('share-intake-into-project')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('share-intake-into-session')),
      findsOneWidget,
    );
  });

  testWidgets('选「放进项目」需要再选项目', (tester) async {
    final choices = await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('share-intake-into-project')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('share-intake-project-p1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('share-intake-project-p1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('share-intake-subdir-inbox')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('share-intake-subdir-root')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('share-intake-subdir-inbox')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('share-intake-sheet')), findsNothing);
    final choice = choices.single;
    expect(choice, isA<ShareIntakeIntoProject>());
    expect((choice as ShareIntakeIntoProject).subdirectory, 'inbox');
  });

  testWidgets('附到已有会话能选出会话', (tester) async {
    final choices = await pumpSheet(
      tester,
      sessions: <AgentSessionMeta>[session],
    );

    await tester.tap(find.byKey(const ValueKey('share-intake-into-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-intake-project-p1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('share-intake-session-s1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('share-intake-new-session')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('share-intake-session-s1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-intake-sheet')), findsNothing);
    final choice = choices.single;
    expect(choice, isA<ShareIntakeIntoSession>());
    expect((choice as ShareIntakeIntoSession).sessionId, 's1');
  });

  testWidgets('取消不产生选择', (tester) async {
    final choices = await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('share-intake-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('share-intake-sheet')), findsNothing);
    expect(choices.single, isNull);
  });
}
