import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

void main() {
  late _TerminalFixture fixture;

  setUp(() => fixture = _TerminalFixture());
  tearDown(() => fixture.dispose());

  testWidgets('empty prompt begins at the top of the terminal scrollback', (
    tester,
  ) async {
    await fixture.mount(tester);
    final transcript = find.byType(ListView);
    final prompt = find.byType(TextField);

    expect(find.ancestor(of: prompt, matching: transcript), findsOneWidget);
    expect(
      tester.getTopLeft(prompt).dy - tester.getTopLeft(transcript).dy,
      inInclusiveRange(6, 12),
    );
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('success preserves stdout and returns the next prompt silently', (
    tester,
  ) async {
    await fixture.mount(tester);
    const output = ['Hello', '用户输出：（运行结束，退出码 0）(JDK)'];

    final code = fixture.pane.attachOutput(
      title: 'java Main',
      stdout: Stream.fromIterable(output),
      stderr: const Stream.empty(),
      exitCode: Future.value(0),
    );
    await tester.pump();
    expect(await code, 0);
    await tester.pumpAndSettle();

    expect(_transcript(tester), ['${fixture.prompt} java Main', ...output]);
    final lastOutput = _line(output.last);
    final prompt = find.byType(TextField);
    expect(prompt, findsOneWidget);
    expect(
      tester.getTopLeft(prompt).dy - tester.getBottomLeft(lastOutput).dy,
      inInclusiveRange(0, 6),
    );
    expect(
      tester.getBottomRight(prompt).dx,
      closeTo(tester.getBottomRight(find.byType(ListView)).dx - 20, 1),
    );
  });

  testWidgets('preparation and running hide the prompt until streams drain', (
    tester,
  ) async {
    await fixture.mount(tester);
    fixture.pane.beginPreparation();
    await tester.pump();
    expect(fixture.pane.busy, isTrue);
    expect(find.byType(TextField), findsNothing);
    expect(_transcript(tester), isEmpty);

    fixture.pane.finishPreparation();
    final stdout = StreamController<String>();
    final stderr = StreamController<String>();
    final exit = Completer<int>();
    final code = fixture.pane.attachOutput(
      title: 'java Main',
      stdout: stdout.stream,
      stderr: stderr.stream,
      exitCode: exit.future,
    );
    stdout.add('first line');
    exit.complete(0);
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
    expect(fixture.pane.busy, isTrue);

    stdout.add('last buffered line');
    await stdout.close();
    await stderr.close();
    await tester.pump();
    expect(await code, 0);
    await tester.pumpAndSettle();

    expect(_line('last buffered line'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(fixture.pane.busy, isFalse);
    expect(_transcript(tester), [
      '${fixture.prompt} java Main',
      'first line',
      'last buffered line',
    ]);
  });

  for (final code in [7, 127]) {
    testWidgets('nonzero exit $code preserves diagnostics and its integer', (
      tester,
    ) async {
      await fixture.mount(tester);
      final result = fixture.pane.attachOutput(
        title: 'javac Main.java',
        stdout: Stream.value('compiler output'),
        stderr: Stream.value('Main.java:2: error: missing symbol'),
        exitCode: Future.value(code),
      );
      await tester.pump();
      expect(await result, code);
      await tester.pumpAndSettle();

      expect(_line('compiler output'), findsOneWidget);
      expect(_line('Main.java:2: error: missing symbol'), findsOneWidget);
      expect(_line('exit code $code'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  }

  testWidgets('long output and the prompt scroll together in a short pane', (
    tester,
  ) async {
    await fixture.mount(tester, size: const Size(360, 160));
    final result = fixture.pane.attachOutput(
      title: 'java Main',
      stdout: Stream.fromIterable(
        List.generate(80, (index) => 'output line $index'),
      ),
      stderr: const Stream.empty(),
      exitCode: Future.value(0),
    );
    await tester.pump();
    await result;
    await tester.pumpAndSettle();
    final transcript = find.byType(ListView);
    final controller = tester.widget<ListView>(transcript).controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.getBottomRight(find.byType(TextField)).dy,
      lessThanOrEqualTo(tester.getBottomRight(transcript).dy + 1),
    );

    controller.jumpTo(0);
    await tester.pump();
    expect(_line('output line 0'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stream output and exit status stay with their source session', (
    tester,
  ) async {
    await fixture.mount(tester);
    final stdout = StreamController<String>();
    final stderr = StreamController<String>();
    final exit = Completer<int>();
    final result = fixture.pane.attachOutput(
      title: 'java Main',
      stdout: stdout.stream,
      stderr: stderr.stream,
      exitCode: exit.future,
    );
    await tester.pump();
    await _newSession(tester);
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    stdout.add('only the first session');
    stderr.add('first session diagnostic');
    await stdout.close();
    await stderr.close();
    exit.complete(9);
    await tester.pump();
    expect(await result, 9);
    await tester.pumpAndSettle();
    expect(_transcript(tester), isEmpty);

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(_line('only the first session'), findsOneWidget);
    expect(_line('first session diagnostic'), findsOneWidget);
    expect(_line('exit code 9'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('session tabs support keyboard selection and accessible close', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await fixture.mount(tester);
    await _newSession(tester);

    // Labels are the session id alone, so a tab stays narrow.
    final first = find.text('1');
    final second = find.text('2');
    expect(tester.getSemantics(first).flagsCollection.isButton, isTrue);
    expect(
      tester.getSemantics(first).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    expect(
      tester.getSemantics(second).flagsCollection.isSelected,
      Tristate.isTrue,
    );

    Focus.of(tester.element(first)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      tester.getSemantics(first).flagsCollection.isSelected,
      Tristate.isTrue,
    );

    // Close buttons are present per tab and sized to stay tappable while
    // fitting inside the 30 px tab pill.
    final close = find.byTooltip('Close terminal 2');
    expect(tester.getSize(close).width, greaterThanOrEqualTo(24));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(24));
    final closeIcon = find.descendant(
      of: close,
      matching: find.byIcon(Icons.close),
    );
    expect(tester.getSemantics(closeIcon).flagsCollection.isButton, isTrue);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(second, findsNothing);
    expect(first, findsOneWidget);

    // The last remaining tab is closable too: closing it replaces the session
    // with a fresh one rather than refusing or emptying the pane.
    expect(find.byTooltip('Close terminal 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Close terminal 1'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('the stop action cancels an attached run and restores input', (
    tester,
  ) async {
    await fixture.mount(tester);
    final stdout = StreamController<String>();
    final stderr = StreamController<String>();
    final exit = Completer<int>();
    var cancellations = 0;
    final result = fixture.pane.attachOutput(
      title: 'java Main',
      stdout: stdout.stream,
      stderr: stderr.stream,
      exitCode: exit.future,
      cancel: () async {
        cancellations++;
        await stdout.close();
        await stderr.close();
        exit.complete(137);
      },
    );
    await tester.pump();

    await tester.tap(find.byTooltip('停止'));
    await tester.pump();
    expect(await result, 137);
    await tester.pumpAndSettle();

    expect(cancellations, 1);
    expect(_line('exit code 137'), findsOneWidget);
    expect(find.byTooltip('停止'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Enter executes a command and history stays with its session', (
    tester,
  ) async {
    await fixture.mount(tester);
    final prompt = find.byType(TextField);
    // The field must use `unspecified`: Flutter finalizes it with
    // `shouldUnfocus: false`, so `onSubmitted` fires while the platform keeps
    // the soft keyboard up. A terminating action (`send`) hides the keyboard on
    // Return, and `none` is dropped by the OHOS engine's `handleFunctionKey`
    // (it has no `NONE` branch). `receiveAction` alone cannot catch a
    // keyboard-hiding regression because it bypasses the action entirely,
    // which is how the previous `send` fix slipped through.
    expect(
      tester.widget<TextField>(prompt).textInputAction,
      TextInputAction.unspecified,
      reason: 'A terminating action hides the soft keyboard on Return; '
          '`unspecified` submits and keeps it up.',
    );
    await tester.enterText(prompt, 'echo terminal-check');
    await tester.testTextInput.receiveAction(TextInputAction.unspecified);
    await _pumpIoUntil(
      tester,
      () => !fixture.pane.busy && _line('terminal-check').evaluate().isNotEmpty,
    );

    expect(_transcript(tester), [
      '${fixture.prompt} echo terminal-check',
      'terminal-check',
    ]);
    await tester.tap(prompt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(
      tester.widget<TextField>(prompt).controller!.text,
      'echo terminal-check',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(tester.widget<TextField>(prompt).controller!.text, isEmpty);

    await tester.enterText(prompt, 'first session draft');
    await _newSession(tester);
    expect(tester.widget<TextField>(prompt).controller!.text, isEmpty);
    await tester.enterText(prompt, 'second session draft');
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(
      tester.widget<TextField>(prompt).controller!.text,
      'first session draft',
    );
    await tester.tap(prompt);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(
      tester.widget<TextField>(prompt).controller!.text,
      'echo terminal-check',
    );
    await tester.tap(find.text('2'));
    await tester.pump();
    expect(
      tester.widget<TextField>(prompt).controller!.text,
      'second session draft',
    );
  });

  testWidgets('Return keeps the input focused so the keyboard stays up', (
    tester,
  ) async {
    await fixture.mount(tester);
    final prompt = find.byType(TextField);
    final focusNode = tester.widget<TextField>(prompt).focusNode!;
    await tester.tap(prompt);
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.enterText(prompt, 'echo stays-focused');
    // Returning `unspecified` must not unfocus the field: that is what would
    // let the platform dismiss the soft keyboard.
    await tester.testTextInput.receiveAction(TextInputAction.unspecified);
    await _pumpIoUntil(
      tester,
      () =>
          !fixture.pane.busy &&
          _line('stays-focused').evaluate().isNotEmpty,
    );
    expect(
      focusNode.hasFocus,
      isTrue,
      reason: 'Return must not drop focus, or the soft keyboard collapses.',
    );
  });

  testWidgets('a hardware Return key submits the command', (tester) async {
    await fixture.mount(tester);
    final prompt = find.byType(TextField);
    await tester.tap(prompt);
    await tester.enterText(prompt, 'echo hardware-return');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pumpIoUntil(
      tester,
      () =>
          !fixture.pane.busy &&
          _line('hardware-return').evaluate().isNotEmpty,
    );

    expect(_line('hardware-return'), findsOneWidget);
    expect(tester.widget<TextField>(prompt).controller!.text, isEmpty);
  });

  testWidgets('a quiet successful command still bounds the transcript', (
    tester,
  ) async {
    await fixture.mount(tester);
    for (var index = 0; index < 500; index++) {
      fixture.pane.appendSystem('history $index');
    }
    await tester.pumpAndSettle();
    // A quiet, successful command whose only transcript effect is the echoed
    // command line; the 500-line bound must still apply after it completes.
    final command = 'echo -n';
    await tester.enterText(find.byType(TextField), command);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(
      tester,
      () => _line('${fixture.prompt} echo -n').evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();

    final transcript = find.byType(ListView);
    tester.widget<ListView>(transcript).controller!.jumpTo(0);
    await tester.pump();

    expect(_line('history 0'), findsNothing);
    expect(_line('history 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portable command errors keep cwd and stay quiet on success', (
    tester,
  ) async {
    await fixture.mount(tester);
    // A nonexistent directory is a portable-command error (nonzero is shown via
    // stderr text, not a synthetic exit line).
    await tester.enterText(find.byType(TextField), 'cd no-such-dir');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(
      tester,
      () => _line(
        'cd: 目录不存在: no-such-dir',
      ).evaluate().isNotEmpty,
    );

    expect(_line('cd: 目录不存在: no-such-dir'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ls lists real files in the session directory', (tester) async {
    await fixture.mount(tester);
    File(
      p.join(fixture.directory.path, 'real-file.txt'),
    ).writeAsStringSync('x');
    await tester.enterText(find.byType(TextField), 'ls');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(
      tester,
      () => _line('real-file.txt').evaluate().isNotEmpty,
    );
    expect(_line('real-file.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear empties the transcript but keeps the session and cwd', (
    tester,
  ) async {
    await fixture.mount(tester);
    await tester.enterText(find.byType(TextField), 'echo marker');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(
      tester,
      () => _line('marker').evaluate().isNotEmpty,
    );
    expect(_line('marker'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'clear');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(tester, () => _line('marker').evaluate().isEmpty);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(_line('marker'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the canvas focuses the input', (tester) async {
    await fixture.mount(tester);
    expect(find.byType(TextField), findsOneWidget);
    Focus.of(tester.element(find.byType(TextField))).unfocus();
    await tester.pump();
    final textField = find.byType(TextField);
    // Tap just below the prompt row, inside the transcript canvas but not on
    // the field itself, so the canvas focus path (not the field) is exercised.
    final listRect = tester.getRect(find.byType(ListView));
    final fieldBottom = tester.getBottomLeft(textField).dy;
    final target = Offset(
      listRect.left + 20,
      (fieldBottom + listRect.bottom) / 2,
    );
    await tester.tapAt(target);
    // The single-tap focus is deferred past the double-click window.
    await tester.pump(const Duration(milliseconds: 320));
    await _pumpFrames(tester, 4);
    expect(tester.widget<TextField>(textField).focusNode!.hasFocus, isTrue);
  });

  testWidgets('tapping the canvas while focused keeps the input focused', (
    tester,
  ) async {
    await fixture.mount(tester);
    final textField = find.byType(TextField);
    final focusNode = tester.widget<TextField>(textField).focusNode!;
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    // Tap the transcript canvas while already focused. This must not disturb
    // focus, and — the behaviour this test cannot observe — must not re-issue
    // `TextInput.show`, which is what made the keyboard pop on every tap.
    final listRect = tester.getRect(find.byType(ListView));
    final fieldBottom = tester.getBottomLeft(textField).dy;
    await tester.tapAt(
      Offset(listRect.left + 20, (fieldBottom + listRect.bottom) / 2),
    );
    await tester.pump(const Duration(milliseconds: 320));
    await _pumpFrames(tester, 4);
    expect(focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long output scrolls back while a stream still runs', (
    tester,
  ) async {
    await fixture.mount(tester, size: const Size(360, 200));
    final stdout = StreamController<String>();
    final exit = Completer<int>();
    final result = fixture.pane.attachOutput(
      title: 'java Main',
      stdout: stdout.stream,
      stderr: const Stream.empty(),
      exitCode: exit.future,
    );
    for (var i = 0; i < 60; i++) {
      stdout.add('line $i');
    }
    await tester.pump();
    // The running header spinner never settles, so pump a bounded number of
    // frames instead of pumpAndSettle.
    await _pumpFrames(tester, 5);
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    controller.jumpTo(0);
    await tester.pump();
    expect(_line('line 0'), findsOneWidget);

    // New output arrives while the user reads the top: it must not snap down.
    stdout.add('late line');
    await _pumpFrames(tester, 3);
    expect(controller.position.pixels, lessThan(1));
    expect(_line('line 0'), findsOneWidget);

    stdout.add('final line');
    exit.complete(0);
    await stdout.close();
    await tester.pump();
    await result;
    await _pumpFrames(tester, 5);
    expect(controller.position.pixels, lessThan(1));
  });

  testWidgets('session switches retain each scroll offset', (tester) async {
    await fixture.mount(tester, size: const Size(360, 200));
    for (var i = 0; i < 60; i++) {
      fixture.pane.appendSystem('first $i');
    }
    await _pumpFrames(tester, 5);
    final first = tester.widget<ListView>(find.byType(ListView)).controller!;
    first.jumpTo(0);
    await tester.pump();
    expect(first.position.pixels, lessThan(1));

    await _newSession(tester);
    for (var i = 0; i < 60; i++) {
      fixture.pane.appendSystem('second $i');
    }
    await _pumpFrames(tester, 5);
    final second = tester.widget<ListView>(find.byType(ListView)).controller!;
    second.jumpTo(second.position.maxScrollExtent);
    await tester.pump();

    await tester.tap(find.text('1'));
    await _pumpFrames(tester, 5);
    final restored = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(restored.position.pixels, lessThan(1));
    expect(_line('first 0'), findsOneWidget);
  });

  testWidgets('interruptActive forwards to the active session backend', (
    tester,
  ) async {
    await fixture.mount(tester);
    // No cancellable work is running; this must be a safe no-op that leaves a
    // usable prompt and does not throw.
    final session = tester.state<TerminalPaneState>(find.byType(TerminalPane));
    await session.interruptActive();
    await _pumpFrames(tester, 3);
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the Stop control cancels a running local command', (
    tester,
  ) async {
    // The unified sandbox has no external shell; cancellation is exercised via a
    // delegate command that blocks until cancelled (the same path a language
    // toolchain uses).
    final previous = StudioProfile.current;
    final cancel = Completer<void>();
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      supportedFileExtensions: const ['.java'],
      terminalCommandDelegate: (backend, command) async {
        if (!command.startsWith('slowcmd')) return false;
        await backend.runStreams(
          title: 'slowcmd',
          stdout: const Stream<String>.empty(),
          stderr: const Stream<String>.empty(),
          exitCode: cancel.future.then((_) => 130),
          cancel: () async => cancel.complete(),
        );
        return true;
      },
    );
    addTearDown(() => StudioProfile.current = previous);
    await fixture.mount(tester);
    await tester.enterText(find.byType(TextField), 'slowcmd');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(tester, () => fixture.pane.busy);
    expect(fixture.pane.busy, isTrue);
    // The header exposes a working Stop while a local command runs.
    final stop = find.byTooltip('停止');
    expect(stop, findsOneWidget);
    await tester.tap(stop);
    await _pumpIoUntil(tester, () => !fixture.pane.busy, attempts: 400);
    // The session is intact and usable afterwards.
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'echo alive-after-stop');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(
      tester,
      () => _line('alive-after-stop').evaluate().isNotEmpty,
    );
    expect(_line('alive-after-stop'), findsOneWidget);
  });

  testWidgets('partial output stays on its own line across commands', (
    tester,
  ) async {
    await fixture.mount(tester);
    await tester.enterText(find.byType(TextField), 'echo -n first');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(
      tester,
      () => _line('first').evaluate().isNotEmpty,
    );
    await tester.enterText(find.byType(TextField), 'echo second');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpIoUntil(
      tester,
      () => _line('second').evaluate().isNotEmpty,
    );
    final transcript = _transcript(tester);
    // Exact order: cmd1, first, cmd2, second. No merged `firstsecond` row.
    expect(transcript, [
      '${fixture.prompt} echo -n first',
      'first',
      '${fixture.prompt} echo second',
      'second',
    ]);
    expect(_line('firstsecond'), findsNothing);
  });

  testWidgets('double click on old output does not focus or jump to bottom', (
    tester,
  ) async {
    await fixture.mount(tester, size: const Size(360, 160));
    for (var i = 0; i < 80; i++) {
      fixture.pane.appendSystem('row $i');
    }
    await _pumpFrames(tester, 5);
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(0);
    await tester.pump();
    final before = controller.position.pixels;
    expect(before, lessThan(1));

    final word = find
        .byWidgetPredicate(
          (w) => w is SelectableText && (w.data ?? '').contains('row 1'),
        )
        .first;
    final center = tester.getCenter(word);
    // Double tap: two taps within the double-tap window must not focus.
    await tester.tapAt(center);
    await _pumpFrames(tester, 2);
    await tester.tapAt(center);
    await _pumpFrames(tester, 4);
    final field = find.byType(TextField);
    if (field.evaluate().isNotEmpty) {
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
    }
    expect(controller.position.pixels, before);
  });

  testWidgets('scrolling to the prompt can still focus the input', (
    tester,
  ) async {
    await fixture.mount(tester, size: const Size(360, 160));
    for (var i = 0; i < 80; i++) {
      fixture.pane.appendSystem('row $i');
    }
    await _pumpFrames(tester, 5);
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(0);
    await tester.pump();
    // A single tap on empty canvas scrolls to the prompt and focuses it.
    final listRect = tester.getRect(find.byType(ListView));
    await tester.tapAt(Offset(listRect.left + 20, listRect.bottom - 20));
    // Wait past the double-click window for the deferred focus, then let the
    // reveal-to-bottom happen.
    await tester.pump(const Duration(milliseconds: 320));
    await _pumpFrames(tester, 6);
    final prompt = find.byType(TextField);
    expect(prompt, findsOneWidget);
    expect(tester.widget<TextField>(prompt).focusNode!.hasFocus, isTrue);
  });
}

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Finder _line(String text) => find.byWidgetPredicate(
  (widget) => widget is SelectableText && widget.data == text,
);

List<String> _transcript(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((widget) => widget.data!)
    .toList();

Future<void> _newSession(WidgetTester tester) async {
  await tester.tap(find.byTooltip('终端操作'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String> && widget.value == 'new',
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

class _TerminalFixture {
  final directory = Directory.systemTemp.createTempSync('qfli_terminal_');
  final auth = AuthStore();
  final key = GlobalKey<TerminalPaneState>();

  TerminalPaneState get pane => key.currentState!;
  String get prompt {
    final name = p.basename(directory.path);
    return Platform.isWindows ? '$name>' : '$name\$';
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(600, 300),
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: TerminalPane(
                key: key,
                workingDirectory: directory.path,
                auth: auth,
                onlineEnabled: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void dispose() {
    auth.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

Future<void> _pumpIoUntil(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 300,
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
