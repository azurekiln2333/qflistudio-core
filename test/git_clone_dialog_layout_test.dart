import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/pages/git/git_clone_dialog.dart';
import 'package:qfli_studio_core/services/git_clone_service.dart';

void main() {
  testWidgets(
    'mobile clone waits for a field tap before opening the keyboard',
    (tester) async {
      final result = await _openClone(tester);

      expect(tester.testTextInput.isVisible, isFalse);
      for (final editable in tester.widgetList<EditableText>(
        find.byType(EditableText),
      )) {
        expect(editable.focusNode.hasFocus, isFalse);
      }
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(result.completed, isTrue);
      expect(result.request, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in [
    (size: const Size(390, 720), keyboard: 300.0, scale: 1.0),
    (size: const Size(320, 640), keyboard: 280.0, scale: 1.6),
  ]) {
    testWidgets(
      'clone stays above one keyboard inset at ${scenario.size.width}px and ${scenario.scale}x text',
      (tester) async {
        final result = await _openClone(
          tester,
          size: scenario.size,
          textScale: scenario.scale,
        );
        await _enter(
          tester,
          'git-clone-url',
          'https://github.com/user/repo.git',
        );
        tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
        await tester.pumpAndSettle();

        final surface = find.descendant(
          of: find.byKey(const ValueKey('git-clone-dialog')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.type == MaterialType.card,
          ),
        );
        expect(surface, findsOneWidget);
        final rect = tester.getRect(surface);
        final keyboardTop = scenario.size.height - scenario.keyboard;
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(keyboardTop));
        // The tall form should use the area above the keyboard. A second
        // keyboard padding would put its bottom hundreds of pixels higher.
        expect(rect.bottom, greaterThan(keyboardTop - 60));
        expect(rect.height, greaterThan(200));
        expect(
          find.byKey(const ValueKey('git-clone-confirm')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextButton, '取消').hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await _enter(tester, 'git-clone-name', 'Mobile clone');
        await _enter(tester, 'git-clone-username', 'git-user');
        await _enter(tester, 'git-clone-token', 'test-token');
        expect(
          find.byKey(const ValueKey('git-clone-token')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('git-clone-confirm')));
        await tester.pumpAndSettle();

        expect(result.completed, isTrue);
        expect(result.request?.url, 'https://github.com/user/repo.git');
        expect(result.request?.name, 'Mobile clone');
        expect(result.request?.username, 'git-user');
        expect(result.request?.token, 'test-token');
        expect(find.byKey(const ValueKey('git-clone-dialog')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _DialogResult {
  bool completed = false;
  GitCloneRequest? request;
}

Future<_DialogResult> _openClone(
  WidgetTester tester, {
  Size size = const Size(390, 720),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final result = _DialogResult();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-clone'),
            onPressed: () async {
              result.request = await showGitCloneDialog(
                context,
                desktop: false,
              );
              result.completed = true;
            },
            child: const Text('Open clone'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-clone')));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}
