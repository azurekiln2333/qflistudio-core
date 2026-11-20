import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/editor/symbols_bar.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets('keyboard button hides the input method without editing code', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('hello world');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: CodeEditor(controller: controller, focusNode: focus),
              ),
              SymbolsBar(
                language: 'Dart',
                controller: controller,
                symbols: const [';', '{}'],
                onSymbolsEdited: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    const selection = CodeLineSelection(
      baseIndex: 0,
      baseOffset: 1,
      extentIndex: 0,
      extentOffset: 5,
    );
    controller.selection = selection;
    await tester.pump();
    tester.testTextInput.log.clear();

    await tester.tap(find.byTooltip('收起键盘'));
    await tester.pump();

    expect(
      tester.testTextInput.log.any((call) => call.method == 'TextInput.hide'),
      isTrue,
    );
    expect(tester.testTextInput.isVisible, isFalse);
    expect(focus.hasFocus, isFalse);
    expect(controller.text, 'hello world');
    expect(controller.selection, selection);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard button stays at the right while symbols scroll', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('');
    addTearDown(controller.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 296,
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SymbolsBar(
                  language: 'Dart',
                  controller: controller,
                  symbols: kDefaultSymbolSets['Dart']!,
                  onSymbolsEdited: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final keyboard = find.byKey(const ValueKey('symbols-hide-keyboard'));
    final before = tester.getRect(keyboard);
    expect(before.width, 44);
    expect(before.height, 44);
    expect(before.right, 296);

    await tester.drag(find.byType(ListView), const Offset(-900, 0));
    await tester.pumpAndSettle();

    expect(tester.getRect(keyboard), before);
    expect(keyboard.hitTestable(), findsOneWidget);
    expect(find.byTooltip('编辑快捷符号').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.text('_'));
    await tester.tap(find.text('_'));
    expect(controller.text, '_');
    expect(tester.takeException(), isNull);
  });
}
