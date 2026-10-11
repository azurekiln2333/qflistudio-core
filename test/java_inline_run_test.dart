import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/demo_run_service.dart';
import 'package:qfli_studio_core/services/runner_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/widgets/code_snippet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  StudioProfile? previous;
  late Directory scratch;

  setUp(() {
    previous = StudioProfile.current;
    scratch = Directory.systemTemp.createTempSync('qfli_inline_run_');
    DemoRunService.scratchRootOverride = scratch.path;
  });
  tearDown(() {
    StudioProfile.current = previous;
    DemoRunService.scratchRootOverride = null;
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  testWidgets('run output renders inline below the code, without a dialog', (
    tester,
  ) async {
    final runner = _RecordingRunner();
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: runner,
      supportedFileExtensions: const ['.java'],
    );

    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    // No dialog and no output area before running.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('inline-output-line'), findsNothing);

    await tester.tap(find.byTooltip('运行示例'));
    // Real dart:io (scratch file write) only completes inside runAsync.
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text('inline-output-line').evaluate().isNotEmpty) break;
    }

    // Output appears inline; nothing modal opened and no route was pushed.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('inline-output-line'), findsOneWidget);
    expect(runner.entries, hasLength(1));
    // The run wrote a real <Class>.java for the lesson.
    expect(runner.entries.single, endsWith('Main.java'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second tap while running does not double-launch', (
    tester,
  ) async {
    final runner = _RecordingRunner(holdOpen: true);
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: runner,
      supportedFileExtensions: const ['.java'],
    );
    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    await tester.tap(find.byTooltip('运行示例'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    // While running the button is disabled (spinner shown).
    expect(find.byIcon(Icons.play_arrow_outlined), findsNothing);
    runner.exit.complete(0);
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty) break;
    }
    expect(runner.entries, hasLength(1));
  });

  testWidgets('spinner clears on exit without another tap; rerun works', (
    tester,
  ) async {
    final runner = _RecordingRunner(holdOpen: true, lines: ['done-line']);
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: runner,
      supportedFileExtensions: const ['.java'],
    );
    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(tester, () => runner.entries.length == 1);

    // Running: spinner replaces the play button, Stop is available.
    expect(find.byIcon(Icons.play_arrow_outlined), findsNothing);

    // Program exits. Pump WITHOUT tapping again.
    runner.exit.complete(0);
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    // Spinner gone, output remains below the code, Run re-enabled.
    expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
    expect(find.text('done-line'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    // Rerun starts a fresh run and completes.
    runner.resetForRerun();
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(tester, () => runner.entries.length == 2);
    runner.exit2.complete(0);
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    expect(runner.entries, hasLength(2));
    expect(find.text('done-line'), findsOneWidget);
  });

  testWidgets('startup failure shows an error and re-enables Run', (
    tester,
  ) async {
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: _FailingRunner(),
      supportedFileExtensions: const ['.java'],
    );
    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel clears running state without another tap', (
    tester,
  ) async {
    final runner = _RecordingRunner(holdOpen: true);
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: runner,
      supportedFileExtensions: const ['.java'],
    );
    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(tester, () => runner.entries.length == 1);
    // The Stop control is present while running.
    await tester.tap(find.byTooltip('取消'));
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
    // A late exit from the cancelled run must not resurrect the spinner.
    if (!runner.exit.isCompleted) runner.exit.complete(137);
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
    expect(runner.entries, hasLength(1));
  });

  testWidgets('U1: a raw startup throw clears the spinner and shows error', (
    tester,
  ) async {
    DemoRunService.startOverride = (_) async =>
        throw const FileSystemException('scratch write denied');
    addTearDown(() => DemoRunService.startOverride = null);
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: _RecordingRunner(),
      supportedFileExtensions: const ['.java'],
    );
    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    expect(find.textContaining('scratch write denied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('U2: a rejecting exitCode future clears the spinner', (
    tester,
  ) async {
    final exit = Completer<int>();
    DemoRunService.startOverride = (example) async {
      final dir = Directory.systemTemp.createTempSync('qfli_u2_');
      return DemoRunSession.forTest(
        RunResult(
          title: 'java Main',
          stdout: const Stream<String>.empty(),
          stderr: const Stream<String>.empty(),
          exitCode: exit.future,
        ),
        dir,
      );
    };
    addTearDown(() => DemoRunService.startOverride = null);
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: _RecordingRunner(),
      supportedFileExtensions: const ['.java'],
    );
    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isEmpty,
    );
    // Reject the exit future; the spinner must clear with no unhandled error.
    exit.completeError(StateError('monitor failure'));
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('U3: a cleanup failure still publishes completion', (
    tester,
  ) async {
    final exit = Completer<int>();
    DemoRunService.startOverride = (example) async {
      final dir = Directory.systemTemp.createTempSync('qfli_u3_');
      return DemoRunSession.forTest(
        RunResult(
          title: 'java Main',
          stdout: Stream<String>.value('u3-output'),
          stderr: const Stream<String>.empty(),
          exitCode: exit.future,
          // A cancel that throws must not suppress the completion rebuild.
          cancel: () async => throw StateError('cancel failed'),
        ),
        dir,
      );
    };
    addTearDown(() => DemoRunService.startOverride = null);
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: _RecordingRunner(),
      supportedFileExtensions: const ['.java'],
    );
    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(tester, () => find.text('u3-output').evaluate().isNotEmpty);
    exit.complete(0);
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    expect(find.byIcon(Icons.play_arrow_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale old-run callback cannot overwrite a newer run', (
    tester,
  ) async {
    final firstExit = Completer<int>();
    final secondExit = Completer<int>();
    var calls = 0;
    DemoRunService.startOverride = (example) async {
      calls++;
      final dir = Directory.systemTemp.createTempSync('qfli_stale_');
      return DemoRunSession.forTest(
        RunResult(
          title: 'java Main',
          stdout: Stream<String>.value('run-$calls'),
          stderr: const Stream<String>.empty(),
          exitCode: calls == 1 ? firstExit.future : secondExit.future,
        ),
        dir,
      );
    };
    addTearDown(() => DemoRunService.startOverride = null);
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: _RecordingRunner(),
      supportedFileExtensions: const ['.java'],
    );
    await tester.pumpWidget(_app(CodeSnippet(example: _example)));
    await tester.pump();
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(tester, () => find.text('run-1').evaluate().isNotEmpty);
    // Cancel the first run and start a second before the first exit arrives.
    await tester.tap(find.byTooltip('取消'));
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('运行示例'));
    await _awaitRealIo(tester, () => find.text('run-2').evaluate().isNotEmpty);
    // The stale first exit must not clear the second run's running state.
    firstExit.complete(0);
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byIcon(Icons.play_arrow_outlined), findsNothing);
    secondExit.complete(0);
    await _awaitRealIo(
      tester,
      () => find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-Java code blocks show no run button', (tester) async {
    StudioProfile.current = StudioProfile(
      id: 'dart',
      appTitle: 'Dart',
      templates: const [],
      isOffline: true,
    );
    await tester.pumpWidget(
      _app(
        const CodeSnippet(
          example: ExampleCode(
            id: 'dart-x',
            type: 'dart',
            title: 'dart',
            summary: '',
            code: 'void main() {}',
            output: '',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('运行示例'), findsNothing);
  });
}

MaterialApp _app(Widget home) => MaterialApp(
  locale: const Locale('zh'),
  supportedLocales: StudioLocalizations.supportedLocales,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: home)),
);

const _example = ExampleCode(
  id: 'java-example-run',
  type: 'java',
  title: 'Java run',
  summary: '',
  code: '''
public class Main {
    public static void main(String[] args) {
        System.out.println("real");
    }
}
''',
  output: 'real',
);

class _RecordingRunner implements ProgramRunner {
  _RecordingRunner({
    this.holdOpen = false,
    this.lines = const ['inline-output-line'],
  });

  final bool holdOpen;
  final List<String> lines;
  final entries = <String>[];
  final exit = Completer<int>();
  final exit2 = Completer<int>();

  void resetForRerun() {
    if (!exit.isCompleted) exit.complete(0);
  }

  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    entries.add(entryFile);
    final isRerun = entries.length > 1;
    return ProgramRunResult(
      title: 'java Main',
      stdout: Stream<String>.fromIterable(lines),
      stderr: const Stream.empty(),
      exitCode: !holdOpen
          ? Future<int>.value(0)
          : (isRerun ? exit2.future : exit.future),
    );
  }
}

class _FailingRunner implements ProgramRunner {
  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    throw const ProcessException('javac', [], 'not found');
  }
}

Future<void> _awaitRealIo(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
  }
  fail('Timed out waiting for condition');
}
