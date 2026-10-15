import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/app.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_selection_toolbar.dart';
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/content_tools_pages.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:re_editor/re_editor.dart';

const _sample =
    'public class Sample { '
    'public static void main(String[] args) {} }';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;
  StudioProfile? previousProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_retained_editor_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    await AppPaths.storageDirectory();
    await TaskActivityService.instance.initialize();
  });

  setUp(() => previousProfile = StudioProfile.current);
  tearDown(() => StudioProfile.current = previousProfile);
  tearDownAll(() async {
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  testWidgets('live editor survives Home, tools, content and restore', (
    tester,
  ) async {
    final fixture = _Fixture(root);
    await fixture.mount(tester);
    await fixture.open(tester, 'Alpha');
    final state = tester.state(find.byType(EditorPage));
    final controller = _editor(tester);
    final host = RetainedEditorScope.maybeOf(
      tester.element(find.byType(EditorPage)),
    )!;
    final files = List.of(controller.files);

    await tester.tap(find.byTooltip('运行（长按运行当前文件）'));
    await _pumpIoUntil(tester, () => fixture.runner.runs.length == 1);
    final terminal = tester.state<TerminalPaneState>(find.byType(TerminalPane));
    final run = fixture.runner.runs.single;
    run.stdout.add('before minimize');
    await tester.pump();
    expect(terminal.busy, isTrue);

    final open = controller.current!;
    final code = tester.widget<CodeEditor>(find.byType(CodeEditor));
    open.controller.text = List.generate(
      240,
      (i) => '// unsaved line $i',
    ).join('\n');
    const selection = CodeLineSelection(
      baseIndex: 30,
      baseOffset: 3,
      extentIndex: 31,
      extentOffset: 8,
    );
    open.controller.selection = selection;
    open.focusNode.requestFocus();
    await tester.pump();
    open.scrollController.verticalScroller.jumpTo(450);
    await tester.pump();
    final scroll = open.scrollController.verticalScroller.offset;
    final text = open.controller.text;
    expect(scroll, greaterThan(0));
    expect(open.dirty, isTrue);

    // Back at the editor root hides it even while the selection toolbar owns
    // the AppBar. No route or controller is disposed.
    await _back(tester);
    expect(host.isVisible, isFalse);
    expect(state.mounted, isTrue);
    expect(find.byType(EditorPage), findsNothing);
    expect(find.byType(EditorPage, skipOffstage: false), findsOneWidget);
    expect(open.focusNode.hasFocus, isFalse);
    open.focusNode.requestFocus();
    await tester.pump();
    expect(open.focusNode.hasFocus, isFalse);
    expect(run.cancelCount, 0);
    run.stdout.add('output while hidden');
    await tester.pump();

    await _tab(tester, Icons.apps_outlined);
    final jsonCard = find.text('JSON 格式化');
    await tester.ensureVisible(jsonCard);
    await tester.tap(jsonCard);
    await _pumpFrames(tester);
    expect(find.byType(JsonToolPage), findsOneWidget);
    await tester.enterText(find.byType(TextField), '{"kept":true}');
    final l10n = StudioLocalizations.of(
      tester.element(find.byType(JsonToolPage)),
    );
    await tester.tap(find.text(l10n.jsonFormat));
    await tester.pump();
    final formatted = tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .text;
    expect(formatted, contains('\n'));

    // Restore is available above pushed tool routes as well as on Home.
    await _restore(tester);
    expect(tester.state(find.byType(EditorPage)), same(state));
    expect(_editor(tester), same(controller));
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller,
      same(code.controller),
    );
    expect(
      tester.state<TerminalPaneState>(find.byType(TerminalPane)),
      same(terminal),
    );
    expect(controller.files, orderedEquals(files));
    expect(open.controller.text, text);
    expect(open.controller.selection, selection);
    expect(open.scrollController.verticalScroller.offset, scroll);
    expect(open.dirty, isTrue);
    expect(find.text('before minimize'), findsOneWidget);
    expect(find.text('output while hidden'), findsOneWidget);
    expect(terminal.busy, isTrue);
    expect(fixture.runner.runs.single, same(run));

    await _back(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      formatted,
    );
    await _back(tester);
    await _tab(tester, Icons.menu_book_outlined);
    await _pumpIoUntil(
      tester,
      () => find.text('Retained lesson').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Retained lesson'));
    await _pumpFrames(tester);
    expect(find.text('Read while the editor is hidden.'), findsOneWidget);
    await _back(tester);
    await _tab(tester, Icons.code_outlined);
    await _pumpIoUntil(
      tester,
      () => find.text('Retained example').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Retained example'));
    await _pumpFrames(tester);
    await tester.enterText(
      find.byType(TextField),
      _sample.replaceFirst('Sample', 'Edited'),
    );
    await _restore(tester);
    expect(_editor(tester), same(controller));
    expect(open.controller.text, text);
    expect(open.controller.selection, selection);
    expect(open.scrollController.verticalScroller.offset, scroll);
    expect(open.dirty, isTrue);
    expect(run.cancelCount, 0);
    await run.finish();
    await _pumpIoUntil(tester, () => !terminal.busy);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'same-project imports finish and open new files without replacing dirty tabs',
    (tester) async {
      final fixture = _Fixture(root);
      await fixture.mount(tester);
      await fixture.open(tester, 'Alpha');
      final state = tester.state(find.byType(EditorPage));
      final controller = _editor(tester);
      final original = controller.current!;
      original.controller.text = '// keep original dirty text';
      await tester.pump();
      await _minimize(tester);
      await _tab(tester, Icons.code_outlined);
      await _pumpIoUntil(
        tester,
        () => find.text('Retained example').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Retained example'));
      await _pumpFrames(tester);
      final l10n = StudioLocalizations.of(
        tester.element(find.byType(TextField)),
      );

      Future<void> importCode(String name, {bool replace = false}) async {
        final action = find.byTooltip(l10n.importCodeProject);
        final button = find.ancestor(
          of: action,
          matching: find.byType(IconButton),
        );
        expect(tester.widget<IconButton>(button.first).onPressed, isNotNull);
        await tester.tap(action);
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const ValueKey('import-target-project')));
        await _pumpFrames(tester);
        await tester.tap(find.text('Alpha').last);
        await _pumpFrames(tester);
        await tester.enterText(
          find.byKey(const ValueKey('import-file-name')),
          name,
        );
        await tester.tap(find.byKey(const ValueKey('import-code-confirm')));
        if (replace) {
          await _pumpIoUntil(
            tester,
            () => find.text(l10n.replaceResource).evaluate().isNotEmpty,
          );
          await tester.tap(find.text(l10n.replaceResource));
        }
        await _pumpIoUntil(
          tester,
          () => find.byType(EditorPage).evaluate().isNotEmpty,
        );
        await _pumpIoUntil(
          tester,
          () => controller.current?.name == '$name.java',
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.state(find.byType(EditorPage)), same(state));
        expect(_editor(tester), same(controller));
        expect(original.controller.text, '// keep original dirty text');
        expect(original.dirty, isTrue);
      }

      await importCode('FirstImported');
      final first = controller.current!;
      first.controller.text = '// keep imported dirty text';
      await tester.pump();
      await _minimize(tester);
      await importCode('SecondImported');
      expect(controller.files, hasLength(4));
      await _minimize(tester);
      await importCode('FirstImported', replace: true);
      expect(controller.current, same(first));
      expect(first.controller.text, '// keep imported dirty text');
      expect(first.dirty, isTrue);
      expect(controller.files, hasLength(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'multiple projects switch via selector; explicit close confirms and disposes only one',
    (tester) async {
      final fixture = _Fixture(root);
      await fixture.mount(tester);
      await fixture.open(tester, 'Alpha');
      final alphaState = tester.state(find.byType(EditorPage));
      final alpha = _editor(tester);
      final alphaMessenger = ScaffoldMessenger.of(
        tester.element(find.byType(EditorPage)),
      );
      final homeMessenger = ScaffoldMessenger.of(
        tester.element(find.byType(NavigationRail, skipOffstage: false)),
      );
      expect(alphaMessenger, isNot(same(homeMessenger)));
      await tester.tap(find.byTooltip('运行（长按运行当前文件）'));
      await _pumpIoUntil(tester, () => fixture.runner.runs.length == 1);
      final run = fixture.runner.runs.single;
      alpha.current!.controller.text = '// alpha unsaved';
      await tester.pump();
      await _minimize(tester);
      await fixture.open(tester, 'Beta');
      final betaState = tester.state(find.byType(EditorPage));
      final beta = _editor(tester);
      final betaMessenger = ScaffoldMessenger.of(
        tester.element(find.byType(EditorPage)),
      );
      expect(betaMessenger, isNot(same(alphaMessenger)));
      expect(betaMessenger, isNot(same(homeMessenger)));
      alphaMessenger.showSnackBar(
        const SnackBar(content: Text('Alpha-only message')),
      );
      betaMessenger.showSnackBar(
        const SnackBar(content: Text('Beta-only message')),
      );
      await tester.pump();
      expect(find.text('Alpha-only message'), findsNothing);
      expect(find.text('Beta-only message'), findsOneWidget);
      beta.current!.controller.text = '// beta unsaved';
      await tester.pump();
      expect(beta, isNot(same(alpha)));
      expect(find.byType(EditorPage, skipOffstage: false), findsNWidgets(2));
      await _minimize(tester);

      // The restore selector lives above the root Navigator. Its popup must use
      // that Navigator's overlay context and resume the chosen live session.
      await tester.tap(find.byTooltip('切换编辑器'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final alphaItem = find.widgetWithText(PopupMenuItem<String>, 'Alpha');
      expect(alphaItem, findsOneWidget);
      await tester.tap(alphaItem);
      await tester.pump();
      await _pumpFrames(tester);
      expect(tester.state(find.byType(EditorPage)), same(alphaState));
      expect(_editor(tester), same(alpha));
      expect(alpha.current!.controller.text, '// alpha unsaved');
      expect(betaState.mounted, isTrue);
      expect(beta.current!.controller.text, '// beta unsaved');
      expect(tester.takeException(), isNull);
      await _minimize(tester);

      // Opening the same Home card reuses the same live instance.
      await fixture.open(tester, 'Alpha');
      expect(tester.state(find.byType(EditorPage)), same(alphaState));
      expect(_editor(tester), same(alpha));
      expect(alpha.current!.controller.text, '// alpha unsaved');
      expect(run.cancelCount, 0);

      await _menu(tester, 'close_editor');
      expect(find.text('有未保存的更改'), findsOneWidget);
      expect(find.text('1 个文件未保存，丢弃并继续吗？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _pumpFrames(tester);
      expect(alphaState.mounted, isTrue);
      expect(run.cancelCount, 0);
      await _menu(tester, 'close_editor');
      await tester.tap(find.text('丢弃'));
      await tester.pump();
      await _pumpIoUntil(tester, () => run.cancelCount == 1);
      expect(alphaState.mounted, isFalse);
      expect(betaState.mounted, isTrue);
      expect(find.byType(EditorPage, skipOffstage: false), findsOneWidget);
      await _restore(tester);
      expect(tester.state(find.byType(EditorPage)), same(betaState));
      expect(_editor(tester), same(beta));
      expect(beta.current!.controller.text, '// beta unsaved');
      // App teardown owns the remaining retained editor and its resources.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(betaState.mounted, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor dialogs and child routes consume Back before the editor hides',
    (tester) async {
      final fixture = _Fixture(root);
      await fixture.mount(tester);
      await fixture.open(tester, 'Alpha');
      final state = tester.state(find.byType(EditorPage));
      await _menu(tester, 'goto');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(EditorPage), findsOneWidget);
      await _back(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(EditorPage), findsOneWidget);
      await _menu(tester, 'settings');
      expect(find.byType(SettingsPage), findsOneWidget);
      await _back(tester);
      expect(find.byType(SettingsPage), findsNothing);
      expect(tester.state(find.byType(EditorPage)), same(state));
      await _back(tester);
      expect(find.byType(EditorPage), findsNothing);
      expect(state.mounted, isTrue);
      await _restore(tester);
      expect(tester.state(find.byType(EditorPage)), same(state));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'terminal sessions retain drafts, controllers and output and cannot focus while hidden',
    (tester) async {
      final fixture = _Fixture(root);
      await fixture.mount(tester);
      await fixture.open(tester, 'Alpha');
      await _menu(tester, 'terminal');
      final terminal = tester.state<TerminalPaneState>(
        find.byType(TerminalPane),
      );
      await tester.enterText(find.byType(TextField), 'echo first-output');
      await tester.testTextInput.receiveAction(TextInputAction.unspecified);
      await _pumpIoUntil(
        tester,
        () => find.text('first-output').evaluate().isNotEmpty,
      );
      final firstInput = tester.widget<TextField>(find.byType(TextField));
      await _menu(tester, 'new', tooltip: '终端操作');
      expect(terminal.sessionCount, 2);
      await tester.enterText(find.byType(TextField), 'second session draft');
      final secondInput = tester.widget<TextField>(find.byType(TextField));
      expect(secondInput.controller, isNot(same(firstInput.controller)));
      expect(secondInput.focusNode!.hasFocus, isTrue);
      await _minimize(tester);
      expect(secondInput.focusNode!.hasFocus, isFalse);
      terminal.requestInputFocus();
      await tester.pump();
      expect(secondInput.focusNode!.hasFocus, isFalse);
      await _restore(tester);
      expect(
        tester.state<TerminalPaneState>(find.byType(TerminalPane)),
        same(terminal),
      );
      expect(terminal.sessionCount, 2);
      final restored = tester.widget<TextField>(find.byType(TextField));
      expect(restored.controller, same(secondInput.controller));
      expect(restored.focusNode, same(secondInput.focusNode));
      expect(restored.controller!.text, 'second session draft');
      final firstTab = find.descendant(
        of: find.byType(TerminalPane),
        matching: find.text('1'),
      );
      await tester.tap(firstTab);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(firstInput.controller),
      );
      expect(find.text('first-output'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening without a host retains standalone EditorPage navigation',
    (tester) async {
      final fixture = _Fixture(root);
      await fixture.mount(tester, standalone: true);
      await tester.tap(find.text('Open standalone'));
      await _pumpIoUntil(
        tester,
        () => find.byType(CodeEditor).evaluate().isNotEmpty,
      );
      final state = tester.state(find.byType(EditorPage));
      expect(find.byTooltip('暂时收起编辑器'), findsNothing);
      await _back(tester);
      expect(state.mounted, isFalse);
      expect(find.text('Open standalone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

EditorController _editor(WidgetTester tester) =>
    tester
            .widget<SelectionToolbarScope>(find.byType(SelectionToolbarScope))
            .editor
        as EditorController;

Future<void> _tab(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon).first);
  await _pumpFrames(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  // A live process has an animated progress indicator; avoid pumpAndSettle.
  await _pumpFrames(tester);
}

Future<void> _minimize(WidgetTester tester) async {
  await tester.tap(find.byTooltip('暂时收起编辑器'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _restore(WidgetTester tester) async {
  await tester.tap(find.textContaining('返回编辑器 ·'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _menu(
  WidgetTester tester,
  String value, {
  String tooltip = '更多',
}) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
  await _pumpFrames(tester);
  final item = find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == value,
  );
  await tester.ensureVisible(item);
  await _pumpFrames(tester);
  await tester.tap(item);
  await tester.pump();
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // Advance bounded frames: running processes and real-I/O loaders may keep
  // scheduling frames, so global pumpAndSettle is not a completion signal.
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _pumpIoUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    done(),
    isTrue,
    reason: 'The retained editor operation did not finish.',
  );
}

class _Fixture {
  _Fixture(Directory root) : directory = root.createTempSync('case_') {
    store = ProjectStore(
      storageFile: File(p.join(directory.path, 'projects.json')),
    );
    for (final name in ['Alpha', 'Beta']) {
      final path = Directory(p.join(directory.path, name))..createSync();
      File(p.join(path.path, 'Main.java')).writeAsStringSync('class Main {}\n');
      File(
        p.join(path.path, 'Other.java'),
      ).writeAsStringSync('class Other {}\n');
      final config = File(p.join(path.path, '.qfli', 'project.json'));
      config.parent.createSync();
      config.writeAsStringSync(
        jsonEncode({'version': 1, 'entryFile': 'Main.java'}),
      );
      File(p.join(path.path, 'history.json')).writeAsStringSync(
        jsonEncode({
          'openFiles': ['Other.java', 'Main.java'],
          'activeFile': 'Main.java',
          'files': <String, Object>{},
        }),
      );
    }
  }

  final Directory directory;
  final auth = AuthStore();
  final settings = SettingsStore();
  final runner = _LiveRunner();
  late final ProjectStore store;

  Future<void> mount(WidgetTester tester, {bool standalone = false}) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await runner.finish();
      // Drain FakeAsync continuations and real history.json I/O before deleting
      // this fixture. A wall-clock deletion retry cannot drain editor writes.
      for (var round = 0; round < 4; round++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      auth.dispose();
      settings.dispose();
      store.dispose();
      FileSystemException? lastError;
      for (var round = 0; round < 50; round++) {
        final error = await tester.runAsync<FileSystemException?>(() async {
          try {
            if (directory.existsSync()) await directory.delete(recursive: true);
            return null;
          } on FileSystemException catch (error) {
            return error;
          }
        });
        if (error == null) return;
        lastError = error;
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      throw lastError!;
    });
    await tester.runAsync(() async {
      await store.load();
      await store.addExisting(p.join(directory.path, 'Alpha'));
      await store.addExisting(p.join(directory.path, 'Beta'));
    });
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Retained editor test',
      templates: const [ProjectTemplate.java],
      isOffline: true,
      entryFileNames: const ['Main.java'],
      supportedFileExtensions: const ['.java'],
      runner: runner,
      contentRepositoryFactory: () => const _Content(),
    );
    if (standalone) {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openEditorPage(
                  context,
                  project: store.projects.first,
                  auth: auth,
                  store: store,
                  settings: settings,
                ),
                child: const Text('Open standalone'),
              ),
            ),
          ),
        ),
      );
    } else {
      await tester.pumpWidget(
        QfliApp(store: store, auth: auth, settings: settings),
      );
    }
    await _pumpFrames(tester);
  }

  Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await _pumpIoUntil(
      tester,
      () =>
          find.byType(EditorPage).evaluate().isNotEmpty &&
          _editor(tester).files.length >= 2,
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
}

class _LiveRunner implements ProgramRunner {
  final runs = <_LiveRun>[];

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    final run = _LiveRun();
    runs.add(run);
    return ProgramRunResult(
      title: 'java Main',
      stdout: run.stdout.stream,
      stderr: const Stream.empty(),
      exitCode: run.exit.future,
      cancel: run.cancel,
    );
  }

  Future<void> finish() async {
    for (final run in runs) {
      await run.finish();
    }
  }
}

class _LiveRun {
  final stdout = StreamController<String>();
  final exit = Completer<int>();
  int cancelCount = 0;
  bool _finished = false;

  Future<void> cancel() async {
    cancelCount++;
    await finish();
  }

  Future<void> finish() async {
    if (_finished) return;
    _finished = true;
    if (!exit.isCompleted) exit.complete(0);
    unawaited(stdout.close());
  }
}

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
}

class _Content implements ContentRepository {
  const _Content();

  static const _catalog = ContentCatalog(
    schemaVersion: 1,
    tutorials: [
      TutorialContent(
        id: 'retained-tutorial',
        language: 'java',
        type: 'java',
        locale: 'zh-CN',
        level: 'beginner',
        title: 'Retained chapter',
        summary: '',
        concepts: [],
        source: 'test',
        license: 'test',
        updatedAt: '2026-10-15',
        lessons: [
          TutorialLessonContent(
            id: 'retained-lesson',
            title: 'Retained lesson',
            summary: '',
            concepts: [],
            explain: 'Read while the editor is hidden.',
            code: _sample,
            output: '',
            exercises: [],
          ),
        ],
      ),
    ],
    examples: [
      ExampleContent(
        id: 'retained-example',
        language: 'java',
        type: 'java',
        locale: 'zh-CN',
        level: 'beginner',
        title: 'Retained example',
        summary: '',
        concepts: [],
        source: 'test',
        license: 'test',
        updatedAt: '2026-10-15',
        code: _sample,
        expectedOutput: '',
        inputFixtures: {},
        templateType: 'java',
      ),
    ],
  );

  @override
  Future<ContentCatalog> load() async => _catalog;
  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async => _catalog.tutorials.where(filter.matches).toList();
  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async => _catalog.examples.where(filter.matches).toList();
}
