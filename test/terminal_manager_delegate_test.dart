import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/pages/terminax_terminal_page.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/terminal/widgets/terminal_input.dart';

/// Verifies the app-level terminal (`TerminaxTerminalPage`, shared by the home
/// built-in terminal and quick-tools local terminal) wires the host profile's
/// [StudioProfile.terminalCommandDelegate] into its [TerminalManager].
///
/// This is the app-level counterpart of the editor terminal assertion in
/// `terminal_pane_test.dart`: without the wiring the sandbox backend receives
/// `delegate: null` and `java`/`javac` fall through to the unsupported branch.
///
/// Kept as a single test body because [AppPaths] caches its storage-directory
/// probe in static futures; a second mounted page in the same file would hang
/// on that stale future, which is a harness artifact, not product behaviour.
void main() {
  late StudioProfile? previous;
  late ProjectStore store;

  setUp(() {
    previous = StudioProfile.current;
    store = ProjectStore();
  });

  tearDown(() {
    StudioProfile.current = previous;
    store.dispose();
  });

  testWidgets('app terminal sessions receive the profile delegate', (
    tester,
  ) async {
    final executed = <String>[];
    StudioProfile.current = _profileRecordingInto(executed);

    await _mount(tester, store);
    // The page resolves its working directory asynchronously and then creates
    // the first session; wait for its input to appear.
    await _pumpIoUntil(tester, () => _hasInput(tester));

    // The field must use `unspecified`: Flutter finalizes it with
    // `shouldUnfocus: false`, so `onSubmitted` fires while the platform keeps
    // the soft keyboard up. A terminating action (`send`) hides the keyboard on
    // Return, and `none` is dropped by the OHOS engine's `handleFunctionKey`
    // (it has no `NONE` branch). `onSubmitted` therefore stays wired.
    // Kept inside this test body because `AppPaths` caches its
    // storage-directory probe in static futures; a second mounted page in the
    // same file hangs on that stale future (a harness artifact, not product
    // behaviour).
    final inputField = tester.widget<TextField>(find.byType(TextField).last);
    expect(
      inputField.textInputAction,
      TerminalInputBehavior.action,
      reason: 'A terminating action hides the soft keyboard on Return; '
          '`unspecified` submits and keeps it up.',
    );
    expect(inputField.textInputAction, TextInputAction.unspecified);
    expect(inputField.onSubmitted, isNotNull);

    await _drive(tester, 'javac Main.java');
    await _pumpIoUntil(tester, () => executed.isNotEmpty);
    expect(executed, ['javac Main.java']);

    // The `+` action goes through `_newSession`, the same creation path used by
    // the auto-recreate after the last tab closes. The PageView only builds the
    // visible page, so the field count stays at one.
    await tester.tap(find.byIcon(Icons.add));
    await _pumpIoUntil(
      tester,
      () => find.text('终端 2').evaluate().isNotEmpty,
    );
    await _pumpIo(tester, 40);

    await _drive(tester, 'javac Second.java');
    await _pumpIoUntil(tester, () => executed.length == 2);
    expect(executed, ['javac Main.java', 'javac Second.java']);

    expect(tester.takeException(), isNull);
  });
}

/// A profile whose terminal hook records every `javac` it is asked to run.
StudioProfile _profileRecordingInto(List<String> executed) => StudioProfile(
  id: 'test',
  appTitle: 'TestToolchain',
  templates: const [],
  isOffline: true,
  supportedFileExtensions: const ['.java'],
  terminalCommandDelegate: (backend, command) async {
    if (!command.startsWith('javac ')) return false;
    executed.add(command);
    await backend.runStreams(
      title: 'javac',
      stdout: const Stream<String>.empty(),
      stderr: const Stream<String>.empty(),
      exitCode: Future<int>.value(0),
    );
    return true;
  },
);

Future<void> _mount(WidgetTester tester, ProjectStore store) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  });
  await tester.pumpWidget(MaterialApp(home: TerminaxTerminalPage(store: store)));
  await tester.pump();
}

Future<void> _drive(WidgetTester tester, String command) async {
  // Exactly one field is built (the visible session's input).
  final field = find.byType(TextField).last;
  await tester.showKeyboard(field);
  await tester.enterText(field, command);
  await tester.testTextInput.receiveAction(TextInputAction.done);
}

bool _hasInput(WidgetTester tester) => tester.any(find.byType(TextField));

/// Pumps [cycles] frames while letting real async work (working-directory
/// resolution, backend spin-up) progress, mirroring the editor-terminal harness.
Future<void> _pumpIo(WidgetTester tester, int cycles) async {
  for (var i = 0; i < cycles; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Future<void> _pumpIoUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 400,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(condition(), isTrue, reason: 'The terminal operation did not finish.');
}
