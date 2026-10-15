import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/app.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/retained_editor_restore_control.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

/// Integration coverage for the floating restore control inside the real app.
///
/// The component suite mounts the control in isolation, which cannot catch a
/// conditional host remount (the host used to wrap the control in an `if`, so a
/// modal or a visibility change rebuilt it from scratch) or a broken sibling
/// Overlay anchor (the selector menu is anchored through global coordinates
/// because the host is a sibling of the root Navigator). Only the real
/// `QfliApp` wiring exercises those paths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;
  StudioProfile? previousProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_restore_control_');
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

  testWidgets('drag and collapse survive a root modal, resume and minimize', (
    tester,
  ) async {
    final fixture = _Fixture(root);
    await fixture.mount(tester);
    await fixture.open(tester, 'Alpha');
    await _minimize(tester);

    final control = find.byKey(
      const ValueKey('retained-editor-restore-control'),
    );
    expect(control, findsOneWidget);
    final state = tester.state<RetainedEditorRestoreControlState>(control);

    // Drag the expanded bar to a known offset away from the default corner.
    final beforeDrag = tester.getRect(
      find.byKey(const ValueKey('restore-control-expanded')),
    );
    await _pan(tester, const Offset(-60, -80));
    final afterDrag = tester.getRect(
      find.byKey(const ValueKey('restore-control-expanded')),
    );
    expect(afterDrag.left, closeTo(beforeDrag.left - 60, 1));
    expect(afterDrag.top, closeTo(beforeDrag.top - 80, 1));
    final draggedPosition = state.position!;

    // Collapse to the circle.
    await tester.tap(find.byTooltip('收起为圆形按钮'));
    await _pumpFrames(tester);
    expect(state.mode, RestoreControlMode.collapsed);
    final collapsedRect = tester.getRect(
      find.byKey(const ValueKey('restore-control-collapsed')),
    );
    expect(collapsedRect.right, closeTo(afterDrag.right, 1));
    expect(collapsedRect.center.dy, closeTo(afterDrag.center.dy, 1));

    // Expand again by tapping the circle (not restoring).
    await tester.tap(find.byKey(const ValueKey('restore-control-collapsed')));
    await _pumpFrames(tester);
    expect(state.mode, RestoreControlMode.expanded);

    // A root modal must hide the control without remounting it: the same
    // State object and the same position/mode must come back.
    await tester.tap(find.byType(FloatingActionButton));
    await _pumpFrames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.byKey(const ValueKey('restore-control-expanded')),
      findsNothing,
    );
    expect(
      tester.state<RetainedEditorRestoreControlState>(control),
      same(state),
      reason: 'the modal must not remount the control',
    );

    // Cancel the dialog and confirm the control returns unchanged.
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('取消')),
    );
    await _pumpFrames(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester.state<RetainedEditorRestoreControlState>(control),
      same(state),
    );
    expect(state.mode, RestoreControlMode.expanded);
    expect(state.position, draggedPosition);
    final restoredRect = tester.getRect(
      find.byKey(const ValueKey('restore-control-expanded')),
    );
    expect(restoredRect.left, closeTo(draggedPosition.dx, 1));
    expect(restoredRect.top, closeTo(draggedPosition.dy, 1));

    // Resume the session, then minimize again: the position survives an
    // editor transition too.
    final editorState = tester.state(
      find.byWidgetPredicate(
        (widget) => widget is EditorPage && widget.project.name == 'Alpha',
        skipOffstage: false,
      ),
    );
    await tester.tap(find.textContaining('返回编辑器 ·'));
    await _pumpFrames(tester);
    expect(
      tester.state(
        find.byWidgetPredicate(
          (widget) => widget is EditorPage && widget.project.name == 'Alpha',
          skipOffstage: false,
        ),
      ),
      same(editorState),
    );

    await _minimize(tester);
    expect(
      tester.state<RetainedEditorRestoreControlState>(control),
      same(state),
      reason: 'the editor transition must not remount the control',
    );
    expect(state.mode, RestoreControlMode.expanded);
    expect(state.position, draggedPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the session selector still opens and selects from the host tab',
    (tester) async {
      // Regression guard for the sibling-Overlay anchor: the control passes its
      // own BuildContext, which the host converts through global coordinates.
      final fixture = _Fixture(root, projectNames: const ['Alpha', 'Beta']);
      await fixture.mount(tester);
      await fixture.open(tester, 'Alpha');
      await _minimize(tester);
      await fixture.open(tester, 'Beta');
      await _minimize(tester);

      final control = find.byKey(
        const ValueKey('retained-editor-restore-control'),
      );
      final state = tester.state<RetainedEditorRestoreControlState>(control);

      await tester.tap(find.byTooltip('切换编辑器'));
      await _pumpFrames(tester);
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Alpha'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Beta'),
        findsOneWidget,
      );
      // The control hides while its own selector is open.
      expect(
        find.byKey(const ValueKey('restore-control-expanded')),
        findsNothing,
      );

      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Alpha'));
      await _pumpFrames(tester);
      final page = tester.widget<EditorPage>(
        find.byWidgetPredicate(
          (widget) => widget is EditorPage && widget.project.name == 'Alpha',
          skipOffstage: false,
        ),
      );
      expect(page.project.name, 'Alpha');
      // And the control is back, still the same State.
      expect(
        tester.state<RetainedEditorRestoreControlState>(control),
        same(state),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

/// Drives a real pan: a single move can be swallowed by pan recognition.
Future<void> _pan(WidgetTester tester, Offset travel) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(const ValueKey('restore-control-expanded'))),
  );
  await gesture.moveBy(const Offset(-24, -24)); // consume touch slop
  await tester.pump();
  const steps = 8;
  final step = Offset(travel.dx / steps, travel.dy / steps);
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(step);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

Future<void> _minimize(WidgetTester tester) async {
  await tester.tap(find.byTooltip('暂时收起编辑器'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

class _Fixture {
  _Fixture(Directory root, {this.projectNames = const ['Alpha']})
    : directory = root.createTempSync('restore_control_') {
    store = ProjectStore(
      storageFile: File(p.join(directory.path, 'projects.json')),
    );
    for (final name in projectNames) {
      final path = Directory(p.join(directory.path, name))..createSync();
      File(p.join(path.path, 'Main.java')).writeAsStringSync('class Main {}\n');
      final config = File(p.join(path.path, '.qfli', 'project.json'));
      config.parent.createSync();
      config.writeAsStringSync(
        jsonEncode({'version': 1, 'entryFile': 'Main.java'}),
      );
    }
  }

  final Directory directory;
  final List<String> projectNames;
  final auth = AuthStore();
  final settings = SettingsStore();
  late final ProjectStore store;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
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
      for (final name in projectNames) {
        await store.addExisting(p.join(directory.path, name));
      }
    });
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Restore control test',
      templates: const [ProjectTemplate.java],
      isOffline: true,
      entryFileNames: const ['Main.java'],
      supportedFileExtensions: const ['.java'],
      runner: const _NoopRunner(),
      contentRepositoryFactory: () => const _Content(),
    );
    await tester.pumpWidget(
      QfliApp(store: store, auth: auth, settings: settings),
    );
    await _pumpFrames(tester);
  }

  Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    // The editor loads project files and restores its session through real
    // asynchronous I/O, so pump until its minimize control actually exists
    // instead of assuming a fixed number of frames is enough.
    await _pumpIoUntil(
      tester,
      () => find.byTooltip('暂时收起编辑器').evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Pumps frames while draining real I/O until [done] or the attempt budget runs
/// out. Returns whether [done] became true; never loops unbounded.
Future<bool> _pumpIoUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (done()) return true;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  return done();
}

class _NoopRunner implements ProgramRunner {
  const _NoopRunner();

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async => null;
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
    tutorials: [],
    examples: [],
  );

  @override
  Future<ContentCatalog> load() async => _catalog;
  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async => const [];
  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async => const [];
}
