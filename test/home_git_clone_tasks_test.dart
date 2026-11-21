import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/git/git_clone_progress.dart';
import 'package:qfli_studio_core/widgets/home_git_clone_tasks.dart';

void main() {
  testWidgets('bounds the clone list and keeps it scrollable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeGitCloneTasks(
            tasks: [
              for (var id = 0; id < 5; id++)
                HomeGitCloneTask(
                  id: id,
                  name: 'repository-$id',
                  progress: const GitCloneProgress(
                    stage: GitCloneStage.receiving,
                    completed: 1,
                    total: 2,
                  ),
                  onCancel: () {},
                ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('home-git-clone-task-0')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-git-clone-task-1')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-git-clone-task-2')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-git-clone-task-4')).hitTestable(),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-git-clone-tasks'))).height,
      lessThanOrEqualTo(HomeGitCloneTasks.defaultMaxHeight),
    );
    await tester.drag(
      find.byKey(const ValueKey('home-git-clone-tasks')),
      const Offset(0, -180),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('home-git-clone-task-4')).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('uses the remaining height supplied by Home', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeGitCloneTasks(
            maxHeight: 68,
            tasks: [
              for (var id = 0; id < 4; id++)
                HomeGitCloneTask(
                  id: id,
                  name: 'repository-$id',
                  progress: const GitCloneProgress(
                    stage: GitCloneStage.receiving,
                    completed: 1,
                    total: 2,
                  ),
                  onCancel: _noOp,
                ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('home-git-clone-tasks'))).height,
      lessThanOrEqualTo(68),
    );
    expect(
      find.byKey(const ValueKey('home-git-clone-task-0')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('home-git-clone-task-1')).hitTestable(),
      findsNothing,
    );
  });

  testWidgets('shows measured percentage and indeterminate connection stage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeGitCloneTasks(
            tasks: [
              HomeGitCloneTask(
                id: 10,
                name: 'measured',
                progress: GitCloneProgress(
                  stage: GitCloneStage.receiving,
                  completed: 1,
                  total: 4,
                ),
                onCancel: _noOp,
              ),
              HomeGitCloneTask(
                id: 11,
                name: 'connecting',
                progress: GitCloneProgress(stage: GitCloneStage.connecting),
                onCancel: _noOp,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('接收对象 · 25%'), findsOneWidget);
    expect(find.text('连接中'), findsOneWidget);
    final bars = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bars.map((bar) => bar.value), [0.25, null]);
  });

  testWidgets('does not offer cancellation during registration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HomeGitCloneTasks(
            tasks: [
              HomeGitCloneTask(
                id: 30,
                name: 'registering',
                progress: GitCloneProgress(stage: GitCloneStage.registering),
                onCancel: _noOp,
              ),
            ],
          ),
        ),
      ),
    );

    final cancel = tester.widget<TextButton>(
      find.byKey(const ValueKey('home-git-clone-cancel-30')),
    );
    expect(cancel.onPressed, isNull);
    expect(find.text('登记中…'), findsOneWidget);
  });

  testWidgets('cancels only the selected clone task', (tester) async {
    final cancelled = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeGitCloneTasks(
            tasks: [
              for (final id in [20, 21])
                HomeGitCloneTask(
                  id: id,
                  name: 'repository-$id',
                  progress: const GitCloneProgress(
                    stage: GitCloneStage.resolving,
                    completed: 1,
                    total: 2,
                  ),
                  onCancel: () => cancelled.add(id),
                ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('home-git-clone-cancel-21')));
    expect(cancelled, [21]);
  });
}

void _noOp() {}
