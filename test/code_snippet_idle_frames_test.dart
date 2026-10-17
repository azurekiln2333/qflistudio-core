import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/widgets/code_snippet.dart';

const _example = ExampleCode(
  id: 'idle-code',
  type: 'java',
  title: 'Frame scheduling example',
  summary: 'Frame scheduling example',
  code: 'System.out.println("output");',
  output: 'output',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final platforms = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.ohos,
  });
  String? copiedText;

  setUp(() {
    copiedText = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') {
          return <String, String>{'text': copiedText ?? ''};
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('copying static code becomes idle after the snackbar', (
    tester,
  ) async {
    await _mount(tester, const CodeSnippet(example: _example));
    await _copyAndWait(tester);
    expect(await _sampleFrames(tester), 0);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets('copying editable code without input focus becomes idle', (
    tester,
  ) async {
    final controller = TextEditingController(text: _example.code);
    addTearDown(controller.dispose);
    await _mount(
      tester,
      CodeSnippet(example: _example, controller: controller),
    );
    await _copyAndWait(tester);
    expect(_input(tester).widget.focusNode.hasFocus, isFalse);
    expect(await _sampleFrames(tester), 0);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets(
    'copying empty focused code releases focus and becomes idle',
    (tester) async {
      final controller = TextEditingController(text: _example.code);
      addTearDown(controller.dispose);
      await _mount(
        tester,
        CodeSnippet(example: _example, controller: controller),
      );
      await tester.enterText(find.byType(TextField), '');
      expect(controller.text, isEmpty);
      final selection = controller.selection;
      // Activate the public action without a pointer event, so Copy itself must
      // release focus rather than relying on TextField.onTapOutside.
      await _copyAndWait(tester, withoutPointer: true);
      expect(copiedText, '');
      expect(controller.text, isEmpty);
      expect(controller.selection, selection);
      expect(_input(tester).widget.focusNode.hasFocus, isFalse);
      expect(await _sampleFrames(tester), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platforms,
  );

  testWidgets(
    'manually clearing code after copy keeps active editing usable',
    (tester) async {
      final controller = TextEditingController(text: _example.code);
      addTearDown(controller.dispose);
      await _mount(
        tester,
        CodeSnippet(example: _example, controller: controller),
      );
      await _copyAndWait(tester);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(_input(tester).widget.focusNode.hasFocus, isTrue);
      expect(await _sampleFrames(tester), greaterThan(0));
      await tester.enterText(find.byType(TextField), 'edited code');
      expect(controller.text, 'edited code');
      expect(_input(tester).widget.focusNode.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platforms,
  );

  testWidgets('tapping the code header releases the empty input focus', (
    tester,
  ) async {
    final controller = TextEditingController(text: _example.code);
    addTearDown(controller.dispose);
    await _mount(
      tester,
      CodeSnippet(example: _example, controller: controller),
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text(_example.type));
    await tester.pumpAndSettle();
    expect(_input(tester).widget.focusNode.hasFocus, isFalse);
    expect(await _sampleFrames(tester), 0);
    await tester.enterText(find.byType(TextField), 'editing still works');
    expect(controller.text, 'editing still works');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets(
    'a touch scroll outside the input stops its offscreen cursor',
    (tester) async {
      final controller = TextEditingController(text: _example.code);
      addTearDown(controller.dispose);
      await _mount(
        tester,
        ListView(
          children: [
            CodeSnippet(example: _example, controller: controller),
            const SizedBox(height: 1600),
            const Text('End of detail page'),
          ],
        ),
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      final focus = _input(tester).widget.focusNode;
      await tester.dragFrom(const Offset(300, 800), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(await _sampleFrames(tester), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platforms,
  );

  for (final lazyList in [false, true]) {
    testWidgets(
      'programmatic scroll releases fully hidden input (${lazyList ? 'lazy list' : 'single viewport'})',
      (tester) async {
        final controller = TextEditingController(text: _example.code);
        final scroll = ScrollController();
        addTearDown(controller.dispose);
        addTearDown(scroll.dispose);
        final children = [
          CodeSnippet(example: _example, controller: controller),
          const SizedBox(height: 1600),
          const Text('End of detail page'),
        ];
        await _mount(
          tester,
          lazyList
              ? ListView(controller: scroll, children: children)
              : SingleChildScrollView(
                  controller: scroll,
                  child: Column(children: children),
                ),
        );
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        final focus = _input(tester).widget.focusNode;
        final bottom = tester.getRect(find.byType(TextField)).bottom;
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(bottom));
        expect(focus.hasFocus, isFalse);
        expect(await _sampleFrames(tester), 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: platforms,
    );
  }

  testWidgets('a partially visible input retains active editing', (
    tester,
  ) async {
    final controller = TextEditingController(text: _example.code);
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    await _mount(
      tester,
      SingleChildScrollView(
        controller: scroll,
        child: Column(
          children: [
            CodeSnippet(example: _example, controller: controller),
            const SizedBox(height: 1600),
          ],
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    scroll.jumpTo(200);
    await tester.pumpAndSettle();
    final bounds = tester.getRect(find.byType(TextField));
    expect(bounds.top, lessThan(0));
    expect(bounds.bottom, greaterThan(0));
    expect(_input(tester).widget.focusNode.hasFocus, isTrue);
    expect(await _sampleFrames(tester), greaterThan(0));
    await tester.enterText(find.byType(TextField), 'editing still works');
    expect(controller.text, 'editing still works');
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platforms);

  testWidgets(
    'scroll listeners rebind and pending checks survive unmount',
    (tester) async {
      final controller = TextEditingController(text: _example.code);
      final firstScroll = ScrollController();
      final secondScroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(firstScroll.dispose);
      addTearDown(secondScroll.dispose);
      var activeScroll = firstScroll;
      late StateSetter rebuild;
      await _mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return SingleChildScrollView(
              controller: activeScroll,
              child: Column(
                children: [
                  CodeSnippet(example: _example, controller: controller),
                  const SizedBox(height: 1600),
                ],
              ),
            );
          },
        ),
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      final focus = _input(tester).widget.focusNode;
      rebuild(() => activeScroll = secondScroll);
      await tester.pumpAndSettle();
      expect(firstScroll.hasClients, isFalse);
      expect(secondScroll.hasClients, isTrue);
      expect(_input(tester).widget.focusNode, same(focus));
      expect(focus.hasFocus, isTrue);
      secondScroll.jumpTo(secondScroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      expect(await _sampleFrames(tester), 0);

      secondScroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      secondScroll.jumpTo(secondScroll.position.maxScrollExtent);
      // The visibility check is queued but the field is removed before it runs.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    variant: platforms,
  );

  testWidgets(
    'selecting expected output does not keep drawing idle frames',
    (tester) async {
      await _mount(
        tester,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CodeSnippet(example: _example),
            SizedBox(height: 16),
            SelectableText('expected output text'),
          ],
        ),
      );
      await _copyAndWait(tester);
      await tester.longPress(find.text('expected output text'));
      await tester.pumpAndSettle();
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                widget.data == 'expected output text',
          ),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.widget.focusNode.hasFocus, isTrue);
      expect(editable.widget.controller.selection.isCollapsed, isFalse);
      expect(await _sampleFrames(tester), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platforms,
  );

  testWidgets(
    'selecting expected output releases the editable code focus',
    (tester) async {
      final controller = TextEditingController(text: _example.code);
      addTearDown(controller.dispose);
      await _mount(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CodeSnippet(example: _example, controller: controller),
            const SizedBox(height: 16),
            const SelectableText('expected output text'),
          ],
        ),
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.longPress(find.text('expected output text'));
      await tester.pumpAndSettle();
      expect(_input(tester).widget.focusNode.hasFocus, isFalse);
      expect(await _sampleFrames(tester), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platforms,
  );
}

Future<void> _mount(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: StudioLocalizations.supportedLocales,
      localizationsDelegates: const [
        StudioLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(),
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _copyAndWait(
  WidgetTester tester, {
  bool withoutPointer = false,
}) async {
  final copy = find.byIcon(Icons.copy_outlined);
  if (withoutPointer) {
    tester
        .widget<IconButton>(
          find.ancestor(of: copy, matching: find.byType(IconButton)),
        )
        .onPressed!();
  } else {
    await tester.tap(copy);
  }
  await tester.pump();
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsOneWidget);
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  expect(find.byType(SnackBar), findsNothing);
}

EditableTextState _input(WidgetTester tester) =>
    tester.state<EditableTextState>(
      find.descendant(
        of: find.byType(TextField),
        matching: find.byType(EditableText),
      ),
    );

Future<int> _sampleFrames(WidgetTester tester) async {
  // pump advances the fake clock but only draws when a frame was requested.
  // Count real framework frame callbacks, including delayed cursor timers,
  // rather than just checking hasScheduledFrame at a single quiet instant.
  var frames = 0;
  var sampling = true;
  tester.binding.addPersistentFrameCallback((_) {
    if (sampling) frames++;
  });
  try {
    for (var sample = 0; sample < 120; sample++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  } finally {
    sampling = false;
  }
  expect(tester.takeException(), isNull);
  return frames;
}
