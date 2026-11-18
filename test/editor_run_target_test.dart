import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_runner.dart';
import 'package:qfli_studio_core/interop/interop_sibling_memory.dart';
import 'package:qfli_studio_core/interop/interop_targets.dart';
import 'package:qfli_studio_core/interop/interop_transport.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

/// The Run button has one gesture owner but two destinations.
///
/// Product decision: Run sends the run straight to the sibling app that owns the
/// entry's toolchain, and the start call reports a missing app as `app_missing`.
/// Nothing probes first, because the probe was a real ability start and the run
/// sent after it was refused with error 201. These tests fire the real button
/// and record which path was taken, so a future change cannot move the decision
/// without failing here.
///
/// The contract under test:
///
///   1. an installed sibling app takes the run, with no probe at all;
///   2. a missing sibling app falls back to Studio's own path for this run and
///      is remembered, so later runs and the tooltip use that path at once;
///   3. any other failure is shown to the user and nothing runs twice.
void main() {
  late _Fixture fixture;

  setUp(() {
    InteropSiblingMemory.instance.clear();
    fixture = _Fixture();
  });

  tearDown(() async {
    StudioProfile.current = null;
    InteropSiblingMemory.instance.clear();
    await fixture.dispose();
  });

  testWidgets('the sibling app takes the run tap without a probe', (
    tester,
  ) async {
    fixture.install();
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip(fixture.runTooltip));
    await _pumpUntil(tester, () => fixture.transport.started);

    expect(fixture.transport.started, isTrue);
    // No probe: the probe itself was the ability start that caused error 201.
    expect(fixture.transport.probedLanguages, isEmpty);
    // The local runner must not have run: one gesture, one destination.
    expect(fixture.runner.entries, isEmpty);
    // The dialog names the app, so the target of the run is never ambiguous.
    await _pumpUntil(
      tester,
      () => find.textContaining('QFLIJVMX').evaluate().isNotEmpty,
    );
    expect(find.textContaining('QFLIJVMX'), findsWidgets);
  });

  testWidgets('a missing sibling app falls back and is remembered', (
    tester,
  ) async {
    fixture.install(
      startFailure: const InteropException(
        InteropErrorCode.appMissing,
        '未检测到 QFLIJVMX（com.azurekiln.qfli.java）。',
      ),
    );
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip(fixture.runTooltip));
    // The app is not installed, so this run falls back to the local path.
    await _pumpUntil(tester, () => fixture.runner.entries.isNotEmpty);
    expect(fixture.transport.started, isTrue);
    expect(fixture.runner.entries, hasLength(1));
    await _waitForRunToFinish(tester);

    // The answer outlives the run: the tooltip no longer names the absent app.
    await _pumpUntil(
      tester,
      () => find.byTooltip(_plainTooltip).evaluate().isNotEmpty,
    );
    expect(find.byTooltip(_plainTooltip), findsOneWidget);

    // A later run takes the local path at once, without trying the app again.
    await tester.tap(find.byTooltip(_plainTooltip));
    await _pumpUntil(tester, () => fixture.runner.entries.length == 2);
    expect(fixture.transport.startCount, 1);
    expect(fixture.runner.entries, hasLength(2));
  });

  testWidgets('any other start failure is shown and never runs twice', (
    tester,
  ) async {
    fixture.install(
      startFailure: const InteropException(
        InteropErrorCode.transportFailure,
        '跨应用启动被拒绝（201）',
      ),
    );
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip(fixture.runTooltip));
    // A refusal is a real failure of a run the user asked for: it is shown, and
    // nothing quietly runs a second time in the background.
    await _pumpUntil(
      tester,
      () => find.textContaining('201').evaluate().isNotEmpty,
    );
    expect(find.textContaining('201'), findsWidgets);
    expect(fixture.runner.entries, isEmpty);

    await tester.tap(find.text('关闭'));
    await tester.pump();
    expect(fixture.transport.startCount, 1);
    expect(fixture.runner.entries, isEmpty);
    // The tooltip still names the app: a refusal is not proof it is missing.
    expect(find.byTooltip(_plainTooltip), findsNothing);
  });

  testWidgets('no sibling app for the entry means no probe at all', (
    tester,
  ) async {
    fixture.projectEntry = 'main.go';
    fixture.install();
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip(_plainTooltip));
    await _pumpUntil(tester, () => fixture.runner.entries.isNotEmpty);

    expect(fixture.transport.probedLanguages, isEmpty);
    expect(fixture.transport.started, isFalse);
    expect(fixture.runner.entries, hasLength(1));
  });
}

const String _plainTooltip = '运行（长按运行当前文件）';

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(condition(), isTrue, reason: 'the editor operation did not finish');
}

/// Waits until the local fallback run has released the editor, so the next tap
/// is not swallowed by the running-project guard.
Future<void> _waitForRunToFinish(WidgetTester tester) async {
  final paneFinder = find.byType(TerminalPane);
  if (paneFinder.evaluate().isEmpty) return;
  final pane = tester.state<TerminalPaneState>(paneFinder);
  await _pumpUntil(tester, () => !pane.hasRunningWork);
}

class _RecordingTransport implements InteropTransport {
  _RecordingTransport({this.startFailure});

  /// Thrown by [start] when set, which is how the platform reports a missing
  /// app (`app_missing`) or a refusal (`transport_failure`).
  final InteropException? startFailure;

  final List<String> probedLanguages = <String>[];
  int startCount = 0;

  bool get started => startCount > 0;

  @override
  bool get isSupported => true;

  @override
  Future<InteropProbe> probe(InteropTarget target) async {
    probedLanguages.add(target.language);
    return const InteropProbe.installed(protocol: kInteropProtocol);
  }

  @override
  Future<InteropLaunch> start(
    InteropTarget target,
    InteropRequest request,
  ) async {
    startCount++;
    final failure = startFailure;
    if (failure != null) throw failure;
    // A run that never finishes keeps the dialog open, which is what the test
    // inspects: the user needs to see which app is running.
    final controller = StreamController<InteropEvent>();
    return InteropLaunch(
      request: request,
      events: controller.stream,
      cancel: () async {
        if (!controller.isClosed) await controller.close();
      },
    );
  }
}

class _RecordingRunner implements ProgramRunner {
  final List<String> entries = <String>[];

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    entries.add(entryFile);
    return ProgramRunResult(
      title: 'local $entryFile',
      stdout: Stream.value('local run'),
      stderr: const Stream.empty(),
      exitCode: Future.value(0),
    );
  }
}

class _Fixture {
  _Fixture() {
    final root = Directory(p.join(directory.path, 'project'))..createSync();
    project = Project.create(name: 'run target', path: root.path);
    File(p.join(root.path, 'Main.java')).writeAsStringSync('class Main {}\n');
    File(p.join(root.path, 'main.go')).writeAsStringSync('package main\n');
    final config = File(ProjectConfig.configPath(project.path));
    config.parent.createSync();
    config.writeAsStringSync(
      jsonEncode({'version': 1, 'entryFile': 'Main.java'}),
    );
  }

  final directory = Directory.systemTemp.createTempSync('qfli_run_target_');
  final runner = _RecordingRunner();
  final auth = AuthStore();
  final store = ProjectStore();
  final settings = SettingsStore();
  late final Project project;

  _RecordingTransport transport = _RecordingTransport();

  /// Entry file written into the project config, chosen per test.
  String projectEntry = 'Main.java';

  /// Tooltip of the Run button. It names the sibling app unless this session
  /// already found that app missing.
  String get runTooltip {
    if (InteropSiblingMemory.instance.isMissing('java')) return _plainTooltip;
    return '运行（在 QFLIJVMX 中，长按运行当前文件）';
  }

  void install({InteropException? startFailure}) {
    transport = _RecordingTransport(startFailure: startFailure);
    final config = File(ProjectConfig.configPath(project.path));
    config.writeAsStringSync(
      jsonEncode({'version': 1, 'entryFile': projectEntry}),
    );
    StudioProfile.current = StudioProfile(
      id: 'run-target-test',
      appTitle: 'Run target',
      templates: const [],
      runner: runner,
      isOffline: true,
      entryFileNames: const ['Main.java', 'main.go'],
      supportedFileExtensions: const ['.java', '.go'],
      interopRunner: InteropRunner(transport: transport),
    );
  }

  Widget app() => MaterialApp(
    home: EditorPage(
      project: project,
      auth: auth,
      store: store,
      settings: settings,
    ),
  );

  Future<void> dispose() async {
    auth.dispose();
    store.dispose();
    settings.dispose();
    if (directory.existsSync()) {
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // A retained history.json handle must not fail the test result.
      }
    }
  }
}
