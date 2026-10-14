import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/terminal_pane.dart';
import 'package:qfli_studio_core/store/auth_store.dart';

/// Regression guard for the OHOS "keyboard pops then immediately closes" bug.
///
/// The root cause is not the IME. When the soft keyboard opens, the available
/// body height shrinks. `EditorPage` computes `compactPanel` from that height
/// and passes `compact: true` to [TerminalPane]; the compact branch returns a
/// different subtree that does **not** contain the prompt's `TextField`. The
/// input's element is therefore unmounted, its `FocusNode` loses its element,
/// and the platform IME is closed.
///
/// The same inversion is reproducible here without the editor: mount the pane
/// with a normal height, focus the input, then rebuild at a height that makes
/// the pane compact (which is what a keyboard-driven shrink does) and assert
/// that the focused input survives.
///
/// Success is defined as: the focused `EditableText` element is the *same*
/// element after the height change, and it still holds focus.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late AuthStore auth;
  final key = GlobalKey<TerminalPaneState>();

  setUp(() {
    directory = Directory.systemTemp.createTempSync('terminal_compact_focus_');
    auth = AuthStore();
  });

  tearDown(() {
    auth.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    required Size size,
    bool compact = false,
  }) async {
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
                compact: compact,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'focusing the prompt then shrinking the pane keeps the same input element',
    (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      });

      // A comfortable height: the pane renders its normal (non-compact) body,
      // which is the state a user is in before the keyboard opens.
      await mount(tester, size: const Size(600, 300));

      final state = key.currentState!;
      state.focusInput();
      await tester.pump();

      final finder = find.byType(EditableText, skipOffstage: false);
      final before = tester.element(finder);
      final beforeFocusNode = tester.widget<EditableText>(finder).focusNode;
      expect(
        beforeFocusNode.hasFocus,
        isTrue,
        reason: 'the prompt input must hold focus before the shrink',
      );

      // Shrinking the pane is what a keyboard-driven body resize does. The
      // editor computes `compactPanel` from the reduced body height and passes
      // it down, so reproduce that exact transition: same widget identity (same
      // key), only `compact` flips and the size shrinks.
      await mount(tester, size: const Size(600, 90), compact: true);
      await tester.pump();

      // The pane is header-only now, so the input is deliberately offstage. It
      // must still be mounted: `skipOffstage: false` is required to observe it.
      expect(
        finder,
        findsOneWidget,
        reason:
            'the prompt input must stay mounted after the pane becomes compact; '
            'unmounting it detaches the FocusNode and closes the IME',
      );
      final after = tester.element(finder);

      expect(
        identical(before, after),
        isTrue,
        reason:
            'the input element must not be replaced when the pane becomes '
            'compact; replacing it unmounts the FocusNode and closes the IME',
      );
      expect(
        tester.widget<EditableText>(finder).focusNode.hasFocus,
        isTrue,
        reason: 'the input must keep focus across the height change',
      );

      // Expanding again must bring the input back on stage, with the same
      // element still holding focus.
      await mount(tester, size: const Size(600, 300));
      await tester.pump();
      expect(
        find.byType(EditableText),
        findsOneWidget,
        reason: 'the input must be visible again after expanding',
      );
      expect(
        identical(before, tester.element(find.byType(EditableText))),
        isTrue,
        reason: 'expanding must reuse the same input element',
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );
    },
  );
}
