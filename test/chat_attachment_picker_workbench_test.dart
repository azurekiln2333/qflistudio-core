@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/attachment_picker.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/workspace/workspace_store.dart';

void main() {
  late Directory root;
  late WorkspaceStore workspaces;
  late LargeScreenController layout;

  setUp(() {
    root = Directory.systemTemp.createTempSync('attachment-menu-');
    File('${root.path}/main.dart').writeAsStringSync('void main() {}');
    File('${root.path}/other.dart').writeAsStringSync('// another file');
    workspaces = WorkspaceStore(root: Directory('${root.path}/.workspaces'));
    layout = LargeScreenController();
  });

  tearDown(() {
    layout.dispose();
    workspaces.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester, {
    required ValueChanged<List<String>?> onResult,
    bool workbench = true,
    AttachmentSource source = AttachmentSource.project,
    Brightness brightness = Brightness.light,
  }) async {
    final button = Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          onResult(
            await showAttachmentPicker(
              context,
              source: source,
              projectRoot: root.path,
              workspaces: workspaces,
            ),
          );
        },
        child: const Text('attach'),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 400,
              height: 200,
              child: workbench
                  ? LargeScreenScope(controller: layout, child: button)
                  : button,
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.tap(find.text('attach'));
    await tester.pump();
    // Keep the route/result callback in the widget test's zone. Only directory
    // readiness needs real async; opening there strands result delivery on its
    // event loop when the later fake-clock tap dismisses the menu.
    await tester.runAsync(() async {
      final watch = Stopwatch()..start();
      while (find
              .byKey(const ValueKey('attachment-main.dart'))
              .evaluate()
              .isEmpty &&
          find.text('没有找到工作区文件').evaluate().isEmpty &&
          watch.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  // CheckboxMenuButton forwards its key to an internal MenuItemButton. Match
  // the public control as well as its key instead of choosing an arbitrary hit.
  Finder menuFile(String path) => find.byWidgetPredicate(
    (widget) =>
        widget is CheckboxMenuButton &&
        widget.key == ValueKey('attachment-$path'),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'workbench uses MenuAnchor and returns multiple paths: $brightness',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1024, 768);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<String>? result;
        await mount(
          tester,
          brightness: brightness,
          onResult: (value) => result = value,
        );
        final anchor = find.byKey(const ValueKey('attachment-workbench-menu'));
        expect(anchor, findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(CheckboxMenuButton), findsNWidgets(2));
        final scheme = Theme.of(tester.element(anchor)).colorScheme;
        expect(
          tester.widget<MenuAnchor>(anchor).style!.backgroundColor!.resolve({}),
          scheme.surfaceContainer,
        );
        final cancel = tester.widget<MenuItemButton>(
          find.byKey(const ValueKey('attachment-menu-cancel')),
        );
        expect(
          cancel.shortcut,
          const SingleActivator(LogicalKeyboardKey.escape),
        );
        expect(
          find.text(
            MaterialLocalizations.of(tester.element(anchor)).keyboardKeyEscape,
          ),
          findsOneWidget,
          reason: 'The native menu displays its localized Escape shortcut.',
        );
        final confirm = find.byKey(const ValueKey('attachment-confirm'));
        expect(tester.widget<MenuItemButton>(confirm).onPressed, isNull);
        await tester.tap(menuFile('main.dart'));
        await tester.pump();
        await tester.tap(menuFile('other.dart'));
        await tester.pump();
        expect(
          find.byType(CheckboxMenuButton),
          findsNWidgets(2),
          reason: 'Selection must not close the menu.',
        );
        expect(
          tester.widget<CheckboxMenuButton>(menuFile('main.dart')).value,
          isTrue,
        );
        expect(
          tester
              .widget<CheckboxMenuButton>(menuFile('main.dart'))
              .style!
              .minimumSize!
              .resolve({})!
              .height,
          AppPaths.isDesktop ? 32 : 48,
        );
        final rect = tester.getRect(menuFile('main.dart'));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(1024));
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(result, ['main.dart', 'other.dart']);
        expect(anchor, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Escape cancels the menu without attaching a checked file', (
    tester,
  ) async {
    var completed = false;
    List<String>? result;
    await mount(
      tester,
      onResult: (value) {
        completed = true;
        result = value;
      },
    );
    await tester.tap(menuFile('main.dart'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(find.byType(MenuAnchor), findsNothing);
  });

  testWidgets('outside click cancels the menu', (tester) async {
    var completed = false;
    await mount(
      tester,
      onResult: (value) {
        completed = true;
        expect(value, isNull);
      },
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(find.byType(MenuAnchor), findsNothing);
  });

  testWidgets(
    'empty workspace menu remains cancellable and explains read-only scope',
    (tester) async {
      await mount(tester, source: AttachmentSource.workspace, onResult: (_) {});
      expect(find.text('工作区文件（只读）'), findsOneWidget);
      expect(find.text('没有找到工作区文件'), findsOneWidget);
      expect(
        tester
            .widget<MenuItemButton>(
              find.byKey(const ValueKey('attachment-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('attachment-menu-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(MenuAnchor), findsNothing);
    },
  );

  testWidgets('phone context still opens the existing bottom sheet', (
    tester,
  ) async {
    await mount(tester, workbench: false, onResult: (_) {});
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AttachmentPickerSheet), findsOneWidget);
    expect(find.byType(MenuAnchor), findsNothing);
    await tester.tap(find.byKey(const ValueKey('attachment-main.dart')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('attachment-confirm')));
    await tester.pumpAndSettle();
  });
}
