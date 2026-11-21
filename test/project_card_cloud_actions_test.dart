// UI regressions for cloud CI. Do not execute tests locally.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/widgets/project_card.dart';
import 'package:qfli_studio_core/widgets/project_dialogs.dart';

void main() {
  Project cloud() => Project.create(
    name: 'Cloud repository',
    path: '/cache/workspace',
    cloudId: 'proj_cloud',
    cloudOrigin: 'https://qfli.suanxiwanjie.cn',
    cloudAccountId: 'account-a',
  );

  Future<void> mount(
    WidgetTester tester, {
    bool busy = false,
    VoidCallback? remove,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            child: ProjectCard(
              project: cloud(),
              onOpen: () {},
              onRemove: remove ?? () {},
              cloudBusy: busy,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('R3 busy cloud deletion cannot be duplicated', (tester) async {
    await mount(tester, busy: true);
    await tester.tap(find.byType(PopupMenuButton<ProjectCardAction>));
    await tester.pumpAndSettle();
    for (final action in [ProjectCardAction.remove]) {
      final item = tester
          .widgetList<PopupMenuItem<ProjectCardAction>>(
            find.byType(PopupMenuItem<ProjectCardAction>),
          )
          .singleWhere((item) => item.value == action);
      expect(item.enabled, isFalse);
    }
  });

  testWidgets(
    'R3 server delete confirmation promises no recycle-bin recovery',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () =>
                        showDeleteCloudProjectConfirm(context, cloud()),
                    child: const Text('delete'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('delete'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cloud-project-delete-confirm')),
        findsOneWidget,
      );
      expect(find.textContaining('无法从本地回收站恢复'), findsOneWidget);
      expect(find.text('永久删除'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    },
  );
}
