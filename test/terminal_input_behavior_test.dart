import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/terminal/widgets/terminal_input.dart';

/// Contract tests for the shared terminal soft-keyboard behaviour.
///
/// The OHOS Return path is subtle (it arrives as `performAction`, not a key
/// event), so these lock down the decisions that must not silently regress:
/// the non-dismissing action, the platform predicate, and the difference
/// between raising the keyboard passively and restoring it after a steal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the action submits without dismissing the keyboard', () {
    // `unspecified` is the only action that both reaches onSubmitted and keeps
    // the keyboard up on OHOS; see the class doc for why `send` and `none` fail.
    expect(TerminalInputBehavior.action, TextInputAction.unspecified);
  });

  group('isOhosPlatform', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is true only for the ohos target', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.ohos;
      expect(TerminalInputBehavior.isOhosPlatform, isTrue);

      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          TerminalInputBehavior.isOhosPlatform,
          isFalse,
          reason: '$platform must not be treated as ohos',
        );
      }
    });
  });

  group('restoreKeyboard', () {
    testWidgets('focuses an unfocused node', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(home: Focus(focusNode: node, child: const SizedBox())),
      );

      expect(node.hasFocus, isFalse);
      TerminalInputBehavior.restoreKeyboard(node);
      await tester.pump();
      expect(node.hasFocus, isTrue);
    });

    testWidgets('re-shows the IME when the node is already focused', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: Focus(focusNode: node, child: const SizedBox())),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasFocus, isTrue);

      calls.clear();
      TerminalInputBehavior.restoreKeyboard(node);
      await tester.pump();

      // The node already had Flutter focus, so this must reach the platform and
      // re-show the keyboard rather than returning early.
      expect(
        calls.map((call) => call.method),
        contains('TextInput.show'),
      );
    });

    testWidgets('does nothing when the node cannot request focus', (
      tester,
    ) async {
      final node = FocusNode(canRequestFocus: false);
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(home: Focus(focusNode: node, child: const SizedBox())),
      );

      TerminalInputBehavior.restoreKeyboard(node);
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });
  });
}
