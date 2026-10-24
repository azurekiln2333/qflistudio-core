import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_debug_widgets.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/workspace/saved_workspace.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';
import 'package:re_editor/re_editor.dart';

const _source = 'def f():\r\n  value = 1\r\n  return value\r\nf()\r\n';

void main() {
  late _Fixture fixture;
  StudioProfile? previous;
  setUp(() {
    previous = StudioProfile.current;
    fixture = _Fixture();
  });
  tearDown(() => StudioProfile.current = previous);

  testWidgets(
    'actual page keeps missing debugger unavailable and launches no Run',
    (tester) async {
      await fixture.mount(tester, debugger: null);
      await _panel(tester, 'debug');
      expect(find.text('本产品未提供离线调试器'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('editor-debug-start')),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(EditorDebugGutter), findsNothing);
      expect(fixture.runner.calls, 0);
    },
  );

  testWidgets(
    'actual gutter, secondary snapshots, pause navigation, steps and cleanup stay connected',
    (tester) async {
      final provider = _Provider();
      await fixture.mount(tester, debugger: provider);
      await _panel(tester, 'debug');
      final debug = tester
          .widget<EditorDebugPanel>(find.byType(EditorDebugPanel))
          .debug;
      final secondary = Directory(p.join(fixture.directory.path, 'secondary'))
        ..createSync();
      final source = File(p.join(secondary.path, 'main.py'))
        ..writeAsStringSync(_source);
      await tester.runAsync(
        () => debug.editor.openPath(
          source.path,
          ownerProjectName: 'Second project',
          ownerProjectPath: secondary.path,
          ownerProjectType: 'python',
        ),
      );
      await tester.pump();
      final open = debug.editor.current!;
      const unsaved = 'def f():\r\n  value = 41\r\n  return value\r\nf()\r\n';
      open.controller.text = unsaved;
      open.controller.collapseChunk(0, 3);
      await tester.pump();
      await tester.pump();
      final gutter = tester.widget<EditorDebugGutter>(
        find.byType(EditorDebugGutter),
      );
      final point = gutter.lineBounds(4);
      expect(point, isNotNull);
      expect(gutter.lineAt(point!.center), 4);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(gutter.hitTargetKey)) + point.center,
      );
      await tester.pump();
      expect(debug.breakpoints.single.line, 4);

      await tester.tap(find.byKey(const ValueKey('editor-debug-start')));
      await _until(
        tester,
        () =>
            provider.requests.isNotEmpty &&
            debug.snapshot?.phase == DebugPhase.paused,
      );
      final request = provider.requests.single;
      expect(
        p.equals(request.projectPath, secondary.resolveSymbolicLinksSync()),
        isTrue,
      );
      expect(request.documents.single.text, unsaved);
      expect(request.breakpoints.single.line, 4);
      expect(fixture.runner.calls, 0);
      expect(source.readAsStringSync(), _source);
      await _until(tester, () => open.controller.selection.extentIndex == 2);
      expect(
        open.controller.codeLines.length,
        open.controller.codeLines.lineCount,
      );
      expect(debug.executionLocationFor(open)?.line, 3);
      expect(
        find.descendant(
          of: find.byKey(gutter.hitTargetKey),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('editor-debug-stepOver')));
      await _until(
        tester,
        () =>
            provider.session.commands.isNotEmpty &&
            debug.snapshot?.pauseToken?.generation == 2,
      );
      expect(provider.session.commands.single.$1, DebugCommand.stepOver);
      expect(provider.session.commands.single.$2?.generation, 1);
      expect(debug.selectedFrame!.locals.single.value, '42');
      await tester.tap(find.byKey(const ValueKey('editor-debug-stop')));
      await tester.pump();
      expect(debug.busy, isTrue);
      expect(debug.stopping, isTrue);
      final run = find.byTooltip('运行（长按运行当前文件）');
      expect(
        tester
            .widget<InkResponse>(
              find.descendant(of: run, matching: find.byType(InkResponse)),
            )
            .onTap,
        isNull,
      );
      provider.session.releaseStop();
      await _until(tester, () => !debug.busy);
      expect(provider.session.disposed, isTrue);
      expect(source.readAsStringSync(), _source);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'paused source shrink rejects stale gutter geometry and execution position',
    (tester) async {
      final provider = _Provider();
      await fixture.mount(tester, debugger: provider);
      await _panel(tester, 'debug');
      final debug = tester
          .widget<EditorDebugPanel>(find.byType(EditorDebugPanel))
          .debug;
      await tester.tap(find.byKey(const ValueKey('editor-debug-start')));
      await _until(
        tester,
        () =>
            debug.paused &&
            debug.editor.current?.controller.selection.extentIndex == 2,
      );
      final open = debug.editor.current!;
      final source = File(open.path);
      final originalBytes = source.readAsBytesSync();
      final gutter = tester.widget<EditorDebugGutter>(
        find.byType(EditorDebugGutter),
      );
      final oldPosition = gutter.lineBounds(3)!.center;
      expect(gutter.lineAt(oldPosition), 3);
      expect(debug.executionLocationFor(open)?.line, 3);

      // The controller changes before re_editor publishes its next layout.
      // Both the hit test and painter must reject the old third-line index.
      open.controller.text = 'pass';
      expect(gutter.lineAt(oldPosition), isNull);
      expect(gutter.lineBounds(3), isNull);
      expect(debug.executionLocationFor(open), isNull);
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
      }
      final updatedGutter = tester.widget<EditorDebugGutter>(
        find.byType(EditorDebugGutter),
      );
      expect(updatedGutter.lineBounds(3), isNull);
      expect(debug.executionLocationFor(open), isNull);
      expect(open.dirty, isTrue);
      expect(source.readAsBytesSync(), orderedEquals(originalBytes));
      provider.session.releaseStop();
      unawaited(debug.stop());
      await _until(tester, () => !debug.busy);
    },
  );

  testWidgets(
    'workspace removal keeps dirty source recoverable and rejects Run and Debug',
    (tester) async {
      final provider = _Provider();
      final secondary = Project.create(
        name: 'Removed owner',
        path: p.join(fixture.directory.path, 'secondary'),
        type: 'python',
      );
      Directory(secondary.path).createSync();
      final source = File(p.join(secondary.path, 'main.py'))
        ..writeAsStringSync(_source);
      final originalBytes = source.readAsBytesSync();
      late SavedWorkspace workspace;
      await tester.runAsync(() async {
        final created = await fixture.workspaceStore.save(
          name: 'Debug workbench',
          members: [fixture.primary, secondary],
          primary: fixture.primary,
        );
        expect(created.error, isNull);
        workspace = created.workspace!;
      });
      await fixture.mount(
        tester,
        debugger: provider,
        workspace: workspace,
        workspaceMembers: [fixture.primary, secondary],
        productKey: StudioProductCatalog.qfliStudioKey,
      );
      await _panel(tester, 'debug');
      final debug = tester
          .widget<EditorDebugPanel>(find.byType(EditorDebugPanel))
          .debug;
      await tester.runAsync(
        () => debug.editor.openPath(
          source.path,
          ownerProjectName: secondary.name,
          ownerProjectPath: secondary.path,
          ownerProjectType: secondary.type,
        ),
      );
      await tester.pump();
      final removed = debug.editor.current!;
      removed.controller.text = 'unsaved recovery text\r\n';
      await tester.pump();
      expect(removed.dirty, isTrue);

      WorkspaceSaveResult? shrunk;
      fixture.workspaceStore
          .save(
            existing: workspace,
            name: workspace.name,
            members: [fixture.primary],
            primary: fixture.primary,
          )
          .then((result) => shrunk = result);
      await _until(tester, () => shrunk != null);
      expect(shrunk!.error, isNull);
      fixture.members.value = [fixture.primary];
      await tester.pump();
      await tester.pump();
      expect(debug.editor.current, same(removed));
      expect(debug.editor.files, contains(removed));
      expect(Directory(secondary.path).existsSync(), isTrue);
      expect(find.textContaining('未保存的改动仍保留在编辑器中'), findsOneWidget);
      // Let the initial recovery notice finish before exercising the actions.
      // Any autosave timers must also preserve the still-existing source bytes.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.textContaining('未保存的改动仍保留在编辑器中'), findsNothing);
      expect(source.readAsBytesSync(), orderedEquals(originalBytes));

      await tester.tap(find.byTooltip('运行（长按运行当前文件）'));
      await _until(
        tester,
        () => find.textContaining('项目已从工作区移除').evaluate().isNotEmpty,
      );
      expect(find.textContaining('项目已从工作区移除'), findsOneWidget);
      expect(fixture.runner.calls, 0);
      expect(provider.requests, isEmpty);
      expect(removed.dirty, isTrue);
      expect(removed.controller.text, 'unsaved recovery text\r\n');
      expect(source.readAsBytesSync(), orderedEquals(originalBytes));

      // The Debug action must produce its own notice rather than matching the
      // preceding Run notice while that earlier Snackbar is still visible.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.textContaining('项目已从工作区移除'), findsNothing);
      final start = find.byKey(const ValueKey('editor-debug-start'));
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
      await tester.tap(start);
      await _until(
        tester,
        () => find.textContaining('项目已从工作区移除').evaluate().isNotEmpty,
      );
      expect(provider.requests, isEmpty);
      expect(debug.busy, isFalse);
      expect(fixture.runner.calls, 0);
      expect(source.readAsBytesSync(), orderedEquals(originalBytes));
      expect(debug.editor.current, same(removed));
      expect(removed.controller.text, 'unsaved recovery text\r\n');
      expect(find.textContaining('项目已从工作区移除'), findsOneWidget);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('另存为…（项目不可用）'), findsOneWidget);
      // Close the menu without invoking the platform Save As picker.
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final saveAction in ['manual', 'autosave', 'close', 'document']) {
    testWidgets(
      'queued $saveAction save preserves recovery text when its owner is removed',
      (tester) async {
        final provider = _Provider();
        DocumentToolRequest? documentRequest;
        final secondary = Project.create(
          name: 'Queued save owner',
          path: p.join(fixture.directory.path, 'secondary'),
          type: 'python',
        );
        Directory(secondary.path).createSync();
        final source = File(
          p.join(secondary.path, saveAction == 'document' ? 'main.md' : 'main.py'),
        )
          ..writeAsStringSync(_source);
        final originalBytes = source.readAsBytesSync();
        late SavedWorkspace workspace;
        await tester.runAsync(() async {
          final result = await fixture.workspaceStore.save(
            name: 'Queued save workbench',
            members: [fixture.primary, secondary],
            primary: fixture.primary,
          );
          expect(result.error, isNull);
          workspace = result.workspace!;
        });
        await fixture.mount(
          tester,
          debugger: provider,
          workspace: workspace,
          workspaceMembers: [fixture.primary, secondary],
          productKey: StudioProductCatalog.qfliStudioKey,
          documentToolBuilder: saveAction == 'document'
              ? (request) {
                  documentRequest = request;
                  return const Scaffold(body: Text('Document save test tool'));
                }
              : null,
        );
        await _panel(tester, 'debug');
        final debug = tester
            .widget<EditorDebugPanel>(find.byType(EditorDebugPanel))
            .debug;
        await tester.runAsync(
          () => debug.editor.openPath(
            source.path,
            ownerProjectName: secondary.name,
            ownerProjectPath: secondary.path,
            ownerProjectType: secondary.type,
          ),
        );
        await tester.pump();
        final removed = debug.editor.current!;
        final precedingSave = Completer<String?>();
        removed.pendingSave = precedingSave.future;
        addTearDown(() {
          if (!precedingSave.isCompleted) precedingSave.complete(null);
        });
        fixture.settings.autoSave = saveAction == 'autosave';
        const recoveryText = 'queued unsaved recovery text\r\n';
        removed.controller.text = recoveryText;
        await tester.pump();

        if (saveAction == 'manual') {
          await _panel(tester, 'save');
        } else if (saveAction == 'close') {
          await tester.longPress(find.byType(Tab).last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('关闭当前标签'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilledButton, '保存'));
          await tester.pump();
        } else if (saveAction == 'document') {
          await _panel(tester, 'content_tool');
          expect(documentRequest, isNotNull);
          unawaited(documentRequest!.save(recoveryText));
          await tester.pump();
        }
        final queuedSave = removed.pendingSave!;
        expect(identical(queuedSave, precedingSave.future), isFalse);
        expect(source.readAsBytesSync(), orderedEquals(originalBytes));

        // The save was authorized while the owner existed, then waited behind
        // earlier IO. The page must recheck membership before its actual write.
        fixture.members.value = [fixture.primary];
        await tester.pump();
        await tester.pump();
        expect(debug.editor.files, contains(removed));
        var completed = false;
        String? failure;
        queuedSave.then((result) {
          failure = result;
          completed = true;
        });
        precedingSave.complete(null);
        await _until(tester, () => completed);
        await tester.pump();

        expect(failure, isNotNull);
        expect(source.readAsBytesSync(), orderedEquals(originalBytes));
        expect(debug.editor.files, contains(removed));
        expect(debug.editor.current, same(removed));
        expect(removed.controller.text, recoveryText);
        expect(removed.dirty, isTrue);
        expect(provider.requests, isEmpty);
        expect(fixture.runner.calls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'removed clean project cannot be reopened through paused stack navigation',
    (tester) async {
      final provider = _Provider();
      final secondary = Project.create(
        name: 'Removed clean owner',
        path: p.join(fixture.directory.path, 'secondary'),
        type: 'python',
      );
      Directory(secondary.path).createSync();
      final source = File(p.join(secondary.path, 'main.py'))
        ..writeAsStringSync(_source);
      late SavedWorkspace workspace;
      await tester.runAsync(() async {
        workspace = (await fixture.workspaceStore.save(
          name: 'Clean owner workbench',
          members: [fixture.primary, secondary],
          primary: fixture.primary,
        )).workspace!;
      });
      await fixture.mount(
        tester,
        debugger: provider,
        workspace: workspace,
        workspaceMembers: [fixture.primary, secondary],
        productKey: StudioProductCatalog.qfliStudioKey,
      );
      await _panel(tester, 'debug');
      final debug = tester
          .widget<EditorDebugPanel>(find.byType(EditorDebugPanel))
          .debug;
      await tester.runAsync(
        () => debug.editor.openPath(
          source.path,
          ownerProjectName: secondary.name,
          ownerProjectPath: secondary.path,
          ownerProjectType: secondary.type,
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('editor-debug-start')));
      await _until(tester, () => debug.paused);
      final frame = debug.selectedFrame!;
      fixture.members.value = [fixture.primary];
      await tester.pump();
      expect(
        debug.editor.files.where((file) => file.path == source.path),
        isEmpty,
      );

      unawaited(debug.navigate(frame));
      await tester.pump();
      await tester.pump();
      expect(
        debug.editor.files.where((file) => file.path == source.path),
        isEmpty,
      );
      expect(debug.error, isNull);
      expect(source.readAsStringSync(), _source);
      expect(provider.requests, hasLength(1));
      provider.session.releaseStop();
      unawaited(debug.stop());
      await _until(tester, () => !debug.busy);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reopening a busy terminal cancels deferred panel removal', (
    tester,
  ) async {
    fixture.runner.exitGate = Completer<int>();
    await fixture.mount(tester, debugger: null);
    await tester.tap(find.byTooltip('运行（长按运行当前文件）'));
    await _until(tester, () => fixture.runner.calls == 1);
    final terminal = tester.state<TerminalPaneState>(find.byType(TerminalPane));
    await _until(tester, () => terminal.hasRunningWork);
    final close = find.descendant(
      of: find.byType(TerminalPane),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Icon && widget.icon == Icons.close && widget.size == 18,
      ),
    );
    await tester.tap(close);
    await tester.pump();
    expect(terminal.hasRunningWork, isTrue);
    await _panel(tester, 'terminal');
    expect(
      tester.state<TerminalPaneState>(find.byType(TerminalPane)),
      same(terminal),
    );
    fixture.runner.exitGate!.complete(7);
    await _until(tester, () => !terminal.hasRunningWork);
    await tester.pump();
    expect(find.byType(TerminalPane), findsOneWidget);
    expect(
      tester.state<TerminalPaneState>(find.byType(TerminalPane)),
      same(terminal),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Output uses actual run streams and replaces rolling debug snapshots',
    (tester) async {
      final provider = _Provider();
      await fixture.mount(tester, debugger: provider);
      await tester.tap(find.byTooltip('运行（长按运行当前文件）'));
      await _until(tester, () => fixture.runner.calls == 1);
      await _panel(tester, 'output');
      await _until(
        tester,
        () => find
            .byKey(const ValueKey('editor-run-output'))
            .evaluate()
            .isNotEmpty,
      );
      final runOutput = tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('editor-run-output')),
          )
          .data!;
      expect(runOutput, contains('stdout from real stream\n'));
      expect(runOutput, contains('[stderr] stderr from real stream\n'));
      expect(runOutput, contains('退出码 7'));
      await _panel(tester, 'debug');
      await tester.tap(find.byKey(const ValueKey('editor-debug-start')));
      final debug = tester
          .widget<EditorDebugPanel>(find.byType(EditorDebugPanel))
          .debug;
      await _until(tester, () => debug.snapshot != null);
      provider.session.output('old retained\n', 'transport first');
      await _panel(tester, 'output');
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('editor-debug-stdout')),
            )
            .data,
        'old retained\n',
      );
      provider.session.output('rolling tail\n', 'transport second');
      await tester.pump();
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('editor-debug-stdout')),
            )
            .data,
        'rolling tail\n',
      );
      await _panel(tester, 'debug_console');
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('editor-debug-console')),
            )
            .data,
        'transport second',
      );
      expect(find.byType(TextField), findsNothing);
      provider.session.releaseStop();
      unawaited(debug.stop());
      await _until(tester, () => !debug.busy);
    },
  );

  testWidgets(
    'focused editor disposal does not inspect a defunct focus context',
    (tester) async {
      await fixture.mount(tester, debugger: null);
      await _panel(tester, 'debug');
      final debug = tester
          .widget<EditorDebugPanel>(find.byType(EditorDebugPanel))
          .debug;
      debug.editor.current!.focusNode.requestFocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed debug cleanup retains the lane and offers a real Stop retry',
    (tester) async {
      final provider = _Provider();
      await fixture.mount(tester, debugger: provider);
      await _panel(tester, 'debug');
      final debug = tester
          .widget<EditorDebugPanel>(find.byType(EditorDebugPanel))
          .debug;
      await tester.tap(find.byKey(const ValueKey('editor-debug-start')));
      await _until(tester, () => debug.paused);
      provider.session.failNextStop = true;
      final stop = find.byKey(const ValueKey('editor-debug-stop'));
      await tester.tap(stop);
      await _until(
        tester,
        () => debug.error?.contains('cleanup retry') == true,
      );
      expect(debug.busy, isTrue);
      expect(debug.stopping, isTrue);
      expect(tester.widget<IconButton>(stop).onPressed, isNotNull);
      expect(provider.session.disposed, isFalse);
      provider.session.releaseStop();
      await tester.tap(stop);
      await _until(tester, () => !debug.busy);
      expect(provider.session.stopCalls, 2);
      expect(provider.session.disposed, isTrue);
      expect(fixture.runner.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow large-text panels keep close controls and honest empty ports',
    (tester) async {
      await fixture.mount(
        tester,
        debugger: null,
        size: const Size(390, 844),
        textScale: 2,
      );
      await _panel(tester, 'debug');
      expect(find.byTooltip('关闭调试面板'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _panel(tester, 'ports');
      expect(find.text('当前没有由应用启动的预览监听器'), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-preview-stop')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _panel(WidgetTester tester, String value) async {
  await tester.tap(find.byTooltip('更多'));
  // A running worker intentionally keeps an activity indicator animating.
  // Advance the route transition without requiring the whole editor to idle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final item = find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == value,
  );
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 160; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(ready(), isTrue, reason: 'Expected editor state did not arrive');
}

class _Fixture {
  final directory = Directory.systemTemp.createTempSync('qfli_debug_page_');
  final auth = AuthStore();
  final settings = SettingsStore();
  final store = ProjectStore();
  final runner = _Runner();
  late final primary = Project.create(
    name: 'Primary',
    path: p.join(directory.path, 'primary'),
    type: 'python',
  );
  late final workspaceStore = WorkspaceStore(
    root: Directory(p.join(directory.path, 'workspaces')),
  );
  final members = ValueNotifier<List<Project>>([]);

  Future<void> mount(
    WidgetTester tester, {
    required StudioDebugger? debugger,
    Size size = const Size(1100, 850),
    double textScale = 1,
    SavedWorkspace? workspace,
    List<Project> workspaceMembers = const [],
    String productKey = StudioProductCatalog.scriptKey,
    Widget Function(DocumentToolRequest request)? documentToolBuilder,
  }) async {
    final root = Directory(primary.path)..createSync();
    File(p.join(root.path, 'main.py')).writeAsStringSync(_source);
    members.value = workspaceMembers;
    StudioProfile.current = StudioProfile(
      id: 'debug-page',
      appTitle: 'Debug',
      templates: const [],
      productKey: productKey,
      offlineOnly: true,
      isOffline: true,
      debugger: debugger,
      runner: runner,
      entryFileNames: const ['main.py'],
      supportedFileExtensions: const ['.py', '.md'],
      documentToolBuilder: documentToolBuilder,
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      if (runner.exitGate case final gate?) {
        if (!gate.isCompleted) gate.complete(7);
      }
      if (debugger is _Provider) debugger.session.releaseStop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      var settled = false;
      workspaceStore.settle().then((_) => settled = true);
      await _until(tester, () => settled);
      auth.dispose();
      settings.dispose();
      store.dispose();
      workspaceStore.dispose();
      members.dispose();
      for (var attempt = 0; attempt < 60; attempt++) {
        try {
          directory.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
      }
      fail('Editor history did not release temporary files');
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ValueListenableBuilder<List<Project>>(
          valueListenable: members,
          builder: (context, currentMembers, _) => EditorPage(
            project: primary,
            auth: auth,
            settings: settings,
            store: store,
            initialOpenPath: 'main.py',
            workspace: workspace,
            workspaceMembers: currentMembers,
            workspaceStore: workspaceStore,
          ),
        ),
      ),
    );
    await _until(tester, () => find.byType(CodeEditor).evaluate().isNotEmpty);
  }
}

class _Runner implements ProgramRunner {
  int calls = 0;
  Completer<int>? exitGate;
  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    calls++;
    return ProgramRunResult(
      title: 'test run',
      stdout: Stream.value('stdout from real stream'),
      stderr: Stream.value('stderr from real stream'),
      exitCode: exitGate?.future ?? Future.value(7),
    );
  }
}

// These deterministic transports exercise shared UI wiring only. They do not
// establish native provider behavior or packaged OHOS debugger acceptance.
class _Provider implements StudioDebugger {
  final requests = <DebugLaunchRequest>[];
  final session = _Session();
  @override
  String get displayName => 'UI test debugger';
  @override
  DebugCapabilities get capabilities => const DebugCapabilities(
    breakpointUpdate: DebugBreakpointUpdate.paused,
    outputDelivery: DebugOutputDelivery.live,
    supportsDocumentSnapshots: true,
    supportsStepOver: true,
    supportsStackFrames: true,
    supportsVariables: true,
  );
  @override
  bool supportsLanguage(String language) => language == 'python';
  @override
  Future<DebugSession> launch(DebugLaunchRequest request) async {
    requests.add(request);
    session.path = request.entryFilePath;
    session.pause(1, 3);
    return session;
  }
}

class _Session implements DebugSession {
  final _updates = StreamController<DebugSnapshot>.broadcast(sync: true);
  final _done = Completer<void>();
  final _stopGate = Completer<void>();
  final commands = <(DebugCommand, DebugPauseToken?)>[];
  String path = '';
  bool disposed = false;
  bool failNextStop = false;
  int stopCalls = 0;
  int revision = 0;
  @override
  String get id => 'ui-session';
  @override
  late DebugSnapshot snapshot;
  @override
  Stream<DebugSnapshot> get updates => _updates.stream;
  @override
  Future<void> get done => _done.future;
  void emit(DebugSnapshot value) {
    snapshot = value;
    if (!_updates.isClosed) _updates.add(value);
  }

  void pause(int generation, int line) => emit(
    DebugSnapshot(
      sessionId: id,
      revision: revision++,
      phase: DebugPhase.paused,
      pauseToken: DebugPauseToken(sessionId: id, generation: generation),
      threads: const [DebugThread(id: 'main', name: 'Main', isPaused: true)],
      frames: [
        DebugFrame(
          id: 'frame',
          threadId: 'main',
          name: 'f',
          location: DebugSourceLocation(filePath: path, line: line),
          locals: [DebugVariable(name: 'sum', type: 'int', value: '42')],
        ),
      ],
    ),
  );
  void output(String text, String console) => emit(
    DebugSnapshot(
      sessionId: id,
      revision: revision++,
      phase: DebugPhase.paused,
      pauseToken: snapshot.pauseToken,
      threads: snapshot.threads,
      frames: snapshot.frames,
      stdout: text,
      console: console,
    ),
  );
  @override
  Future<List<DebugBreakpointResult>> setBreakpoints(
    List<DebugBreakpoint> breakpoints,
  ) async => [
    for (final point in breakpoints)
      DebugBreakpointResult(
        requested: point,
        status: DebugBreakpointStatus.pending,
      ),
  ];
  @override
  Future<void> command(
    DebugCommand command, {
    DebugPauseToken? pauseToken,
    String? threadId,
  }) async {
    commands.add((command, pauseToken));
    emit(
      DebugSnapshot(
        sessionId: id,
        revision: revision++,
        phase: DebugPhase.running,
      ),
    );
    pause(2, 4);
  }

  void releaseStop() {
    if (!_stopGate.isCompleted) _stopGate.complete();
  }

  @override
  Future<void> stop() async {
    if (_done.isCompleted) return;
    stopCalls++;
    if (failNextStop) {
      failNextStop = false;
      throw StateError('cleanup retry required');
    }
    emit(
      DebugSnapshot(
        sessionId: id,
        revision: revision++,
        phase: DebugPhase.stopping,
      ),
    );
    await _stopGate.future;
    emit(
      DebugSnapshot(
        sessionId: id,
        revision: revision++,
        phase: DebugPhase.terminated,
        exitCode: 0,
      ),
    );
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> dispose() async {
    await stop();
    disposed = true;
    await _updates.close();
  }
}
