import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/workbench_chrome.dart';
import 'package:qfli_studio_core/shell/workbench_explorer.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.label);
  final String label;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int count = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('${widget.label}: $count'),
  );
}

Future<void> _finishExplorerTransition(WidgetTester tester) async {
  await tester.pump();
  // Both pages stay onstage until the simulation is strictly past its duration.
  await tester.pump(
    WorkbenchExplorer.duration + const Duration(milliseconds: 16),
  );
}

void main() {
  testWidgets(
    'Explorer slides, keeps both page states and returns without closing',
    (tester) async {
      final controller = LargeScreenController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: WorkbenchExplorer(
                controller: controller,
                projectName: 'Alpha',
                projects: const _Probe('Projects'),
                files: const _Probe('Files'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Projects: 0'));
      final projects = tester.state(find.byType(_Probe));
      controller.showFiles();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final filesPage = find.byKey(
        const ValueKey('workbench-explorer-files-page'),
      );
      final transform = tester.widget<Transform>(
        find.descendant(of: filesPage, matching: find.byType(Transform)).first,
      );
      expect(transform.transform.storage[12], greaterThan(0));
      expect(transform.transform.storage[12], lessThan(300));
      await _finishExplorerTransition(tester);
      expect(find.text('Projects: 1'), findsNothing);
      expect(
        tester.state(
          find.byWidgetPredicate(
            (widget) => widget is _Probe && widget.label == 'Projects',
            skipOffstage: false,
          ),
        ),
        same(projects),
      );
      expect(find.text('Alpha'), findsOneWidget);
      await tester.tap(find.text('Files: 0'));
      final files = tester.state(find.byType(_Probe));
      final owner = Object();
      controller.activateFiles(owner);
      await tester.pump();
      await tester.tap(find.byKey(WorkbenchExplorer.backKey));
      await _finishExplorerTransition(tester);
      expect(controller.activeEditor, same(owner));
      expect(controller.activity, WorkbenchActivity.explorer);
      expect(controller.explorerPage, ExplorerPage.projects);
      expect(find.text('Projects: 1'), findsOneWidget);
      expect(tester.state(find.byType(_Probe)), same(projects));
      expect(find.text('Files: 1'), findsNothing);
      expect(
        tester.state(
          find.byWidgetPredicate(
            (widget) => widget is _Probe && widget.label == 'Files',
            skipOffstage: false,
          ),
        ),
        same(files),
      );
      controller.showFiles();
      await _finishExplorerTransition(tester);
      expect(tester.state(find.byType(_Probe)), same(files));
      expect(find.text('Files: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Explorer cannot show files when no project is open', (
    tester,
  ) async {
    final controller = LargeScreenController();
    addTearDown(controller.dispose);
    controller.showFiles();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkbenchExplorer(
            controller: controller,
            projectName: null,
            projects: const Text('Projects'),
            files: const Text('Files'),
          ),
        ),
      ),
    );
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Files'), findsNothing);
    expect(find.byKey(WorkbenchExplorer.backKey), findsNothing);
    expect(find.text('先打开一个项目'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden Explorer pages exclude focus, semantics and input', (
    tester,
  ) async {
    final controller = LargeScreenController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkbenchExplorer(
            controller: controller,
            projectName: 'Alpha',
            projects: const Text('Projects'),
            files: const TextField(),
          ),
        ),
      ),
    );
    final page = find.byKey(
      const ValueKey('workbench-explorer-files-page'),
      skipOffstage: false,
    );
    T descendant<T extends Widget>() => tester.widget<T>(
      find
          .descendant(
            of: page,
            matching: find.byType(T, skipOffstage: false),
            skipOffstage: false,
          )
          .first,
    );
    expect(tester.widget<Offstage>(page).offstage, isTrue);
    expect(descendant<ExcludeFocus>().excluding, isTrue);
    expect(descendant<ExcludeSemantics>().excluding, isTrue);
    expect(descendant<IgnorePointer>().ignoring, isTrue);
    expect(descendant<TickerMode>().enabled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
