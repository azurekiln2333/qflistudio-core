import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/new_file_dialog.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  testWidgets('cancel keeps both Navigators alive through the complete exit', (
    tester,
  ) async {
    final fixture = _Fixture(tester);
    await fixture.mount();
    final rootNavigator = fixture.rootNavigator.currentState;
    final editorNavigator = fixture.editorNavigator.currentState;
    await fixture.open();
    await tester.enterText(_field('新建文件'), 'Unsaved');
    await fixture.pump();

    await tester.tap(_button('新建文件', '取消'));
    await fixture.finishExit();

    expect(fixture.completions, 1);
    expect(fixture.result, isNull);
    expect(find.text('新建文件'), findsNothing);
    expect(fixture.rootNavigator.currentState, same(rootNavigator));
    expect(fixture.editorNavigator.currentState, same(editorNavigator));
    expect(rootNavigator!.mounted, isTrue);
    expect(editorNavigator!.mounted, isTrue);
    expect(rootNavigator.canPop(), isFalse);
    expect(editorNavigator.canPop(), isFalse);

    // Cancelling must leave the sidebar entry usable for the next operation.
    await fixture.open();
    await tester.tap(_button('新建文件', '取消'));
    await fixture.finishExit();
    expect(fixture.completions, 2);
  });

  for (final input in ['  Main  ', '  Main.java  ']) {
    testWidgets('create preserves filename normalization for "$input"', (
      tester,
    ) async {
      final fixture = _Fixture(tester);
      await fixture.mount();
      await fixture.open();
      await tester.enterText(_field('新建文件'), input);
      await fixture.pump();

      await tester.tap(_button('新建文件', '创建'));
      await fixture.finishExit();

      expect(fixture.completions, 1);
      expect(fixture.result, 'Main.java');
      expect(find.text('新建文件'), findsNothing);
    });
  }

  testWidgets('custom suffix cancel preserves the parent input and selection', (
    tester,
  ) async {
    final fixture = _Fixture(tester);
    await fixture.mount();
    await fixture.open();
    await tester.enterText(_field('新建文件'), 'Main');
    final nameController = tester.widget<TextField>(_field('新建文件')).controller;
    await fixture.openCustomSuffix();
    await tester.enterText(_field('自定义后缀'), 'proto');
    await fixture.pump();

    await tester.tap(_button('自定义后缀', '取消'));
    await fixture.finishExit();

    expect(find.text('自定义后缀'), findsNothing);
    final nameField = tester.widget<TextField>(_field('新建文件'));
    expect(nameField.controller, same(nameController));
    expect(nameField.controller!.text, 'Main');
    expect(nameField.decoration!.suffixText, '.java');
    expect(fixture.settings.customFileExts, isEmpty);
    expect(fixture.completions, 0);

    await tester.tap(_button('新建文件', '创建'));
    await fixture.finishExit();
    expect(fixture.result, 'Main.java');
    expect(fixture.completions, 1);
  });

  testWidgets(
    'custom suffix addition still updates settings and the filename',
    (tester) async {
      final fixture = _Fixture(tester);
      await fixture.mount();
      await fixture.open();
      await tester.enterText(_field('新建文件'), 'message');
      await fixture.openCustomSuffix();
      await tester.enterText(_field('自定义后缀'), 'proto');
      await fixture.pump();

      await tester.tap(_button('自定义后缀', '添加'));
      await fixture.finishExit();

      expect(fixture.settings.customFileExts, ['.proto']);
      expect(
        tester.widget<TextField>(_field('新建文件')).decoration!.suffixText,
        '.proto',
      );
      await tester.tap(_button('新建文件', '创建'));
      await fixture.finishExit();
      expect(fixture.result, 'message.proto');
      expect(fixture.completions, 1);
    },
  );
}

Finder _dialog(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(AlertDialog));

Finder _field(String title) =>
    find.descendant(of: _dialog(title), matching: find.byType(TextField));

Finder _button(String title, String text) =>
    find.descendant(of: _dialog(title), matching: find.text(text));

class _Fixture {
  _Fixture(this.tester);

  final WidgetTester tester;
  final settings = SettingsStore();
  final rootNavigator = GlobalKey<NavigatorState>();
  final editorNavigator = GlobalKey<NavigatorState>();
  final errors = <FlutterErrorDetails>[];
  String? result;
  int completions = 0;

  Future<void> mount() async {
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      // Keep the first causal exception even when later unmount failures would
      // otherwise leave only the aggregate "multiple exceptions" message.
      errors.add(details);
      previousErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      _expectNoErrors();
      settings.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigator,
        // Match the retained editor's topology: the editor Navigator is a
        // sibling of Home's root Navigator and owns its own dialog routes.
        builder: (context, child) => Stack(
          children: [
            child!,
            HeroControllerScope.none(
              child: Navigator(
                key: editorNavigator,
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () async {
                          result = await showNewFileDialog(
                            context,
                            settings: settings,
                            projectLanguage: 'Java',
                          );
                          completions++;
                        },
                        child: const Text('Sidebar: new file'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        home: const Scaffold(body: Text('Home stays mounted')),
      ),
    );
    _expectNoErrors();
    await pump();
  }

  Future<void> open() async {
    await tester.tap(find.text('Sidebar: new file'));
    await pump();
    await pump(const Duration(milliseconds: 300));
    expect(find.text('新建文件'), findsOneWidget);
    expect(rootNavigator.currentState!.canPop(), isFalse);
    expect(editorNavigator.currentState!.canPop(), isTrue);
  }

  Future<void> openCustomSuffix() async {
    await tester.dragUntilVisible(
      find.widgetWithText(ActionChip, '+ 自定义'),
      find.byType(ListView),
      const Offset(-300, 0),
    );
    await pump();
    await tester.tap(find.widgetWithText(ActionChip, '+ 自定义'));
    await pump();
    await pump(const Duration(milliseconds: 300));
    expect(find.text('自定义后缀'), findsOneWidget);
  }

  Future<void> pump([Duration duration = Duration.zero]) async {
    await tester.pump(duration);
    _expectNoErrors();
  }

  Future<void> finishExit() async {
    // showDialog completes on pop, while the TextField is still mounted.
    // Inspect every stage, including the final route unmount, for errors.
    await pump();
    await pump(const Duration(milliseconds: 16));
    await pump(const Duration(milliseconds: 80));
    await pump(const Duration(milliseconds: 240));
    await pump();
  }

  void _expectNoErrors() {
    final first = errors.isEmpty ? null : errors.first;
    final reason = first == null
        ? null
        : 'First Flutter error: ${first.exceptionAsString()}\n${first.stack}';
    expect(tester.takeException(), isNull, reason: reason);
    expect(errors, isEmpty, reason: reason);
  }
}
