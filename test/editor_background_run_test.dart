import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
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

import 'support/ohos_target.dart';

void main() {
  late _Fixture fixture;
  setUp(() {
    debugDefaultTargetPlatformOverride = ohosPlatform;
    fixture = _Fixture();
  });
  tearDown(() async {
    StudioProfile.current = null;
    debugDefaultTargetPlatformOverride = null;
    await fixture.dispose();
  });

  _backgroundTest(
    'background action is optional and ordinary Run keeps legacy target',
    (tester) async {
      fixture.install();
      await tester.pumpWidget(fixture.app());
      await _pumpUntil(
        tester,
        () => find.byTooltip('更多').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('后台运行（实验）'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('运行（在 QFLIJVMX 中，长按运行当前文件）'));
      await _pumpUntil(tester, () => fixture.legacy.requests.isNotEmpty);
      expect(fixture.background.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  _backgroundTest('enabling background does not redirect ordinary Run', (
    tester,
  ) async {
    fixture.install(background: true);
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byTooltip('更多').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('运行（在 QFLIJVMX 中，长按运行当前文件）'));
    await _pumpUntil(tester, () => fixture.legacy.requests.isNotEmpty);
    expect(fixture.background.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  _backgroundTest(
    'background menu owns terminal output and Stop uses only new runner',
    (tester) async {
      fixture.background.keepRunning = true;
      fixture.install(background: true);
      await tester.pumpWidget(fixture.app());
      await _pumpUntil(
        tester,
        () => find.byTooltip('更多').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('后台运行（实验）'));
      await _pumpUntil(tester, () => fixture.background.requests.isNotEmpty);
      await _pumpUntil(
        tester,
        () => find.textContaining('background output').evaluate().isNotEmpty,
      );
      expect(fixture.legacy.requests, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      final pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));
      expect(pane.hasRunningWork, isTrue);
      final stop = pane.interruptActive();
      await _pumpUntil(tester, () => fixture.background.cancelled);
      await stop;
      await _pumpUntil(tester, () => !pane.hasRunningWork);
      expect(fixture.legacy.cancelled, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  _backgroundTest(
    'background run leaves online tab and page disposal cancels it',
    (tester) async {
      fixture.install(background: true, online: true);
      await tester.pumpWidget(fixture.app());
      await _pumpUntil(
        tester,
        () => find.byTooltip('更多').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('后台运行（实验）'));
      await _pumpUntil(tester, () => fixture.background.requests.isNotEmpty);
      final pane = tester.state<TerminalPaneState>(find.byType(TerminalPane));
      await _pumpUntil(tester, () => !pane.hasRunningWork);
      await pane.showOnline(initialize: false);
      await tester.pump();
      expect(pane.onlineSelected, isTrue);
      fixture.background.keepRunning = true;
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('后台运行（实验）'));
      await _pumpUntil(tester, () => fixture.background.requests.length == 2);
      await _pumpUntil(tester, () => pane.hasRunningWork);
      expect(pane.onlineSelected, isFalse);
      expect(fixture.background.cancelled, isFalse);
      await tester.pumpWidget(const SizedBox());
      await _pumpUntil(tester, () => fixture.background.cancelled);
      await tester.pumpAndSettle();
      expect(fixture.legacy.cancelled, isFalse);
    },
  );

  _backgroundTest('background action is hidden for non-Java and non-OHOS', (
    tester,
  ) async {
    fixture.install(background: true, entry: 'main.go');
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byTooltip('更多').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('后台运行（实验）'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    fixture.install(background: true);
    await tester.pumpWidget(fixture.app());
    await _pumpUntil(tester, () => find.byTooltip('更多').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('后台运行（实验）'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

void _backgroundTest(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(condition(), isTrue, reason: 'editor operation did not finish');
}

class _Transport implements InteropTransport {
  final requests = <InteropRequest>[];
  bool keepRunning = false;
  bool cancelled = false;
  @override
  bool get isSupported => true;
  @override
  Future<InteropProbe> probe(InteropTarget target) async =>
      const InteropProbe.unknown('not probed');
  @override
  Future<InteropLaunch> start(
    InteropTarget target,
    InteropRequest request,
  ) async {
    requests.add(request);
    final output = StreamController<InteropEvent>();
    output.add(
      InteropEvent(
        sessionId: request.sessionId,
        seq: 1,
        kind: InteropEventKind.stdout,
        text: 'background output',
      ),
    );
    if (!keepRunning) {
      output.add(
        InteropEvent(
          sessionId: request.sessionId,
          seq: 2,
          kind: InteropEventKind.done,
          exitCode: 0,
        ),
      );
      unawaited(output.close());
    }
    return InteropLaunch(
      request: request,
      events: output.stream,
      cancel: () async {
        cancelled = true;
        if (!output.isClosed) {
          output.add(
            InteropEvent(
              sessionId: request.sessionId,
              seq: 2,
              kind: InteropEventKind.done,
              exitCode: 130,
            ),
          );
          await output.close();
        }
      },
    );
  }
}

class _Fixture {
  _Fixture() {
    final root = Directory(p.join(directory.path, 'project'))..createSync();
    project = Project.create(name: 'background run', path: root.path);
    File(p.join(root.path, 'Main.java')).writeAsStringSync('class Main {}');
    File(p.join(root.path, 'main.go')).writeAsStringSync('package main');
    Directory(
      p.dirname(ProjectConfig.configPath(root.path)),
    ).createSync(recursive: true);
  }
  final directory = Directory.systemTemp.createTempSync('qfli_background_ui_');
  final legacy = _Transport();
  final background = _Transport();
  final auth = AuthStore();
  final store = ProjectStore();
  final settings = SettingsStore();
  late final Project project;

  void install({
    bool background = false,
    String entry = 'Main.java',
    bool online = false,
  }) {
    File(
      ProjectConfig.configPath(project.path),
    ).writeAsStringSync(jsonEncode({'version': 1, 'entryFile': entry}));
    StudioProfile.current = StudioProfile(
      id: 'background-test',
      appTitle: 'Background test',
      templates: const [],
      isOffline: !online,
      entryFileNames: const ['Main.java', 'main.go'],
      supportedFileExtensions: const ['.java', '.go'],
      interopRunner: InteropRunner(transport: legacy),
      backgroundInteropRunner: background
          ? InteropRunner(transport: this.background)
          : null,
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
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
