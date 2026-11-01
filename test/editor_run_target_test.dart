import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/interop/interop_protocol.dart';
import 'package:qfli_studio_core/interop/interop_runner.dart';
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
/// Product decision: when the project entry's language has a sibling app that
/// answers, Run compiles and runs there; every other case keeps the previous
/// path. These tests fire the real button and record which path was taken, so
/// a future change cannot move the decision without failing here.
void main() {
  late _Fixture fixture;

  setUp(() {
    fixture = _Fixture();
  });

  tearDown(() async {
    StudioProfile.current = null;
    await fixture.dispose();
  });

  testWidgets('an installed sibling app takes the run tap', (tester) async {
    fixture.install(probe: const InteropProbe.installed(protocol: kInteropProtocol));
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip(fixture.runTooltip));
    await _pumpUntil(tester, () => fixture.transport.started);

    expect(fixture.transport.started, isTrue);
    expect(fixture.transport.probedLanguages, contains('java'));
    // The local runner must not have run: one gesture, one destination.
    expect(fixture.runner.entries, isEmpty);
    // The dialog names the app, so the target of the run is never ambiguous.
    await _pumpUntil(
      tester,
      () => find.textContaining('QFLIJVMX').evaluate().isNotEmpty,
    );
    expect(find.textContaining('QFLIJVMX'), findsWidgets);
  });

  testWidgets('a missing sibling app keeps the original path', (tester) async {
    fixture.install(probe: const InteropProbe.missing('未安装 QFLIJVMX'));
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip(fixture.runTooltip));
    await _pumpUntil(tester, () => fixture.runner.entries.isNotEmpty);

    expect(fixture.transport.started, isFalse);
    expect(fixture.runner.entries, hasLength(1));
  });

  testWidgets('an unknown probe keeps the original path', (tester) async {
    fixture.install(probe: const InteropProbe.unknown('无法确认是否已安装'));
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip(fixture.runTooltip));
    await _pumpUntil(tester, () => fixture.runner.entries.isNotEmpty);

    expect(fixture.transport.started, isFalse);
    expect(fixture.runner.entries, hasLength(1));
  });

  testWidgets('no sibling app for the entry means no probe at all', (
    tester,
  ) async {
    fixture.projectEntry = 'main.go';
    fixture.install();
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byType(EditorPage).evaluate().isNotEmpty);

    await tester.tap(find.byTooltip(fixture.runTooltip));
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

class _RecordingTransport implements InteropTransport {
  _RecordingTransport(this.answer);

  final InteropProbe answer;
  final List<String> probedLanguages = <String>[];
  bool started = false;

  @override
  bool get isSupported => true;

  @override
  Future<InteropProbe> probe(InteropTarget target) async {
    probedLanguages.add(target.language);
    return answer;
  }

  @override
  Future<InteropLaunch> start(
    InteropTarget target,
    InteropRequest request,
  ) async {
    started = true;
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

  _RecordingTransport transport = _RecordingTransport(
    const InteropProbe.missing('未安装'),
  );

  /// Entry file written into the project config, chosen per test.
  String projectEntry = 'Main.java';

  /// Tooltip of the Run button. It names the sibling app once a probe confirmed
  /// it, so the finder depends on the recorded probe answer.
  String get runTooltip {
    if (!transport.answer.isInstalled) return _plainTooltip;
    return '运行（在 QFLIJVMX 中，长按运行当前文件）';
  }

  void install({InteropProbe? probe}) {
    if (probe != null) transport = _RecordingTransport(probe);
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
    home: EditorPage(project: project, auth: auth, store: store, settings: settings),
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
