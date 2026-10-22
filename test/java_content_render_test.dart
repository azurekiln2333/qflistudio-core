import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/content/asset_content_repository.dart';
import 'package:qfli_studio_core/content/local_content_adapter.dart';
import 'package:qfli_studio_core/editor/editor_fonts.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/demo_run_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/widgets/code_snippet.dart';

/// Renders the ACTUAL Java tutorial and example pages plus a lesson/example
/// detail page at phone width using the real new assets, and writes PNGs.
///
/// Real `dart:io` asset reads are preloaded in `setUpAll` (real async) and all
/// widget-side waits use the `runAsync` boundary, so nothing awaits real I/O in
/// the fake-async zone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ExampleCode> javaExamples;
  late Tutorial javaTutorial;

  setUpAll(() async {
    _installAssetHandler();
    await _loadFonts();
    final scratch = Directory.systemTemp.createTempSync('qfli_render_run_');
    DemoRunService.scratchRootOverride = scratch.path;
    addTearDown(() {
      DemoRunService.scratchRootOverride = null;
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });
    javaExamples = await LocalContentAdapter.loadExamples(
      repository: AssetContentRepository(),
      language: 'java',
    );
    javaTutorial = (await LocalContentAdapter.loadTutorial(
      repository: AssetContentRepository(),
      language: 'java',
      displayName: 'Java',
    ))!;
  });

  Future<void> renderPage(
    WidgetTester tester,
    String name,
    Widget page,
    Future<void> Function(WidgetTester tester) navigate,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = ProjectStore();
    final auth = AuthStore();
    final settings = SettingsStore();
    addTearDown(() {
      store.dispose();
      auth.dispose();
      settings.dispose();
    });
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: StudioLocalizations.supportedLocales,
          localizationsDelegates: const [
            StudioLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _renderTheme(),
          home: page,
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find.byType(ListTile).evaluate().isNotEmpty,
      'catalog $name',
    );
    await _capture(tester, captureKey, '$name-list');
    await navigate(tester);
    await _waitFor(
      tester,
      () => find.byType(SelectableText).evaluate().isNotEmpty ||
          find.byType(TextField).evaluate().isNotEmpty,
      'detail $name',
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, captureKey, '$name-detail');
  }

  testWidgets('render java example page', (tester) async {
    StudioProfile.current = const StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: [],
      isOffline: true,
      supportedFileExtensions: ['.java'],
    );
    await renderPage(
      tester,
      'example-beginner',
      const ExampleCodeTab(language: 'java'),
      (tester) async {
        await tester.tap(find.text(javaExamples.first.title));
      },
    );
  });

  for (final sample in <({String name, int index})>[
    (name: 'example-intermediate', index: 45),
    (name: 'example-advanced', index: 95),
  ]) {
    testWidgets('render java ${sample.name} detail', (tester) async {
      StudioProfile.current = const StudioProfile(
        id: 'java',
        appTitle: 'Java',
        templates: [],
        isOffline: true,
        supportedFileExtensions: ['.java'],
      );
      final title = javaExamples[sample.index].title;
      await renderPage(
        tester,
        sample.name,
        const ExampleCodeTab(language: 'java'),
        (tester) async {
          await tester.scrollUntilVisible(
            find.text(title),
            400,
            scrollable: find
                .ancestor(
                  of: find.byType(ListTile).first,
                  matching: find.byType(Scrollable),
                )
                .first,
            maxScrolls: 300,
          );
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(find.text(title), warnIfMissed: false);
        },
      );
    });
  }

  testWidgets('render java tutorial page', (tester) async {
    StudioProfile.current = const StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: [],
      isOffline: true,
      supportedFileExtensions: ['.java'],
    );
    final lesson = javaTutorial.allLessons.first;
    await renderPage(
      tester,
      'tutorial-beginner',
      const LocalTutorialsTab(language: 'java'),
      (tester) async {
        await tester.tap(find.byType(ListTile).first);
      },
    );
    // S1: the real detail page renders the authored objective and pitfalls.
    await _waitFor(
      tester,
      () => find.text(lesson.objective).evaluate().isNotEmpty,
      'objective on detail page',
    );
    expect(find.text(lesson.objective), findsOneWidget);
    expect(find.text(lesson.pitfalls.first), findsOneWidget);
    expect(javaTutorial.allLessons, hasLength(280));
  });

  // Inline-run render on the ACTUAL detail routes. The runner here is a
  // deterministic LAYOUT FIXTURE (labelled `fixture-runner`), so these images
  // prove layout/provenance on the real pages, not real JDK output. Real-runner
  // captures live in qfli_java (terminal harness) where the JDK runner exists.
  testWidgets('render example detail route with inline output (layout fixture)', (
    tester,
  ) async {
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: _FixtureRunner(),
      supportedFileExtensions: const ['.java'],
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final example = javaExamples.firstWhere((e) => e.id == 'java-example-001');
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: StudioLocalizations.supportedLocales,
          localizationsDelegates: const [
            StudioLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _renderTheme(),
          home: const ExampleCodeTab(language: 'java'),
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find.text(example.title).evaluate().isNotEmpty,
      'example list',
    );
    await tester.tap(find.text(example.title));
    await _waitFor(
      tester,
      () => find.byTooltip('运行示例').evaluate().isNotEmpty,
      'example detail',
    );
    await tester.tap(find.byTooltip('运行示例'));
    await _waitFor(
      tester,
      () =>
          find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty &&
          find.textContaining('fixture-runner-output').evaluate().isNotEmpty,
      'example inline completion',
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    final output = find.textContaining('fixture-runner-output').first;
    expect(
      tester.getTopLeft(output).dy,
      greaterThan(tester.getTopLeft(find.text(example.code)).dy),
    );
    await _capture(tester, captureKey, 'inline-run-example-route');
  });

  testWidgets('render tutorial lesson route with inline output (layout fixture)', (
    tester,
  ) async {
    StudioProfile.current = StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: const [],
      isOffline: true,
      runner: _FixtureRunner(),
      supportedFileExtensions: const ['.java'],
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: StudioLocalizations.supportedLocales,
          localizationsDelegates: const [
            StudioLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _renderTheme(),
          home: const LocalTutorialsTab(language: 'java'),
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find.byType(ListTile).evaluate().isNotEmpty,
      'tutorial list',
    );
    await tester.tap(find.byType(ListTile).first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(
      tester,
      () => find.byTooltip('运行示例').evaluate().isNotEmpty,
      'lesson detail',
    );
    await tester.tap(find.byTooltip('运行示例'));
    await _waitFor(
      tester,
      () =>
          find.byIcon(Icons.play_arrow_outlined).evaluate().isNotEmpty &&
          find.textContaining('fixture-runner-output').evaluate().isNotEmpty,
      'tutorial inline completion',
    );
    expect(find.byType(AlertDialog), findsNothing);
    await _capture(tester, captureKey, 'inline-run-tutorial-route');
  });
  // Import dialog render: Java shows the class-name field (no `.java`).
  testWidgets('render java import dialog shows class name only', (tester) async {
    StudioProfile.current = const StudioProfile(
      id: 'java',
      appTitle: 'Java',
      templates: [],
      isOffline: true,
      supportedFileExtensions: ['.java'],
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = ProjectStore();
    final auth = AuthStore();
    final settings = SettingsStore();
    addTearDown(() {
      store.dispose();
      auth.dispose();
      settings.dispose();
    });
    final example = javaExamples.firstWhere(
      (e) => e.id == 'java-example-001',
    );
    final captureKey = GlobalKey();
    // Root boundary wraps MaterialApp so the Navigator overlay (the import
    // dialog) is inside the captured subtree.
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: StudioLocalizations.supportedLocales,
          localizationsDelegates: const [
            StudioLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _renderTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CodeSnippet(
                example: example,
                store: store,
                auth: auth,
                settings: settings,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('导入项目').first, warnIfMissed: false);
    await _waitFor(
      tester,
      () => find.byKey(const ValueKey('import-file-name')).evaluate().isNotEmpty,
      'import dialog',
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Assert the dialog and class-name field are visible BEFORE capture, so the
    // image cannot silently be just the code block again.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('类名'), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('import-file-name')),
    );
    expect(CodeImportService.isValidClassName(field.controller!.text), isTrue);
    expect(field.controller!.text, isNot(endsWith('.java')));
    await _capture(tester, captureKey, 'import-dialog-java');
  });
}

/// Deterministic LAYOUT-FIXTURE runner used only by the render tests on the
/// real pages. Its output is clearly labelled so no final image pretends this
/// came from the displayed program's real runtime.
class _FixtureRunner implements ProgramRunner {
  @override
  Future<ProgramRunResult?> run({
    required String projectPath,
    required String entryFile,
  }) async {
    return ProgramRunResult(
      title: 'fixture-runner java Main',
      stdout: Stream<String>.fromIterable(const [
        'fixture-runner-output line 1',
        'fixture-runner-output line 2',
      ]),
      stderr: const Stream.empty(),
      exitCode: Future<int>.value(0),
    );
  }
}

/// App theme with a CJK fallback so Chinese UI labels and Chinese inside Java
/// string literals render in the harness (test-only; production unchanged).
ThemeData _renderTheme() => AppTheme.light.copyWith(
  textTheme: AppTheme.light.textTheme.apply(
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: const ['Noto Sans SC'],
  ),
);

Future<void> _capture(
  WidgetTester tester,
  GlobalKey captureKey,
  String name,
) async {
  final boundary =
      captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        '../qfli_java/.trellis/tasks/10-09-java-tutorial-rewrite/research/screenshots',
      );
      directory.createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String description,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (condition()) {
      // Settle fake-time animations (route/dialog transitions) and paint a
      // final frame so a later capture is not mid-transition nor needsPaint.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        if (!tester.binding.hasScheduledFrame) break;
      }
      await tester.pump();
      return;
    }
  }
  fail('Timed out waiting for $description');
}

Future<void> _loadFonts() async {
  final loader = FontLoader(EditorFonts.bundledFamily)
    ..addFont(
      _fontBytes('assets/fonts/roboto_mono/static/RobotoMono-Regular.ttf'),
    );
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      _fontBytes(
        'D:/ProgramFiles/flutter_ohos/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  // Real Chinese UI font so CJK UI labels and Chinese inside Java string
  // literals render instead of Ahem tofu. Also registered under the generic
  // `monospace` family, which `EditorFonts.fallbacks` uses for the code/output
  // style, so program stdout containing CJK renders too. TEST-harness only;
  // production fonts are unchanged.
  final cjk = FontLoader('Noto Sans SC')
    ..addFont(_fontBytes('C:/Windows/Fonts/NotoSansSC-VF.ttf'));
  final monoCjk = FontLoader('monospace')
    ..addFont(_fontBytes('C:/Windows/Fonts/NotoSansSC-VF.ttf'));
  try {
    await Future.wait([
      loader.load(),
      icons.load(),
      cjk.load(),
      monoCjk.load(),
    ]);
  } on Exception {
    // Fonts are optional for layout verification.
  }
}

Future<ByteData> _fontBytes(String path) async {
  final file = File(path);
  return ByteData.sublistView(await file.readAsBytes());
}

void _installAssetHandler() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (message) async {
    if (message == null) return null;
    final key = utf8.decode(
      message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
    );
    final file = File(
      key.startsWith('packages/')
          ? key.substring('packages/qfli_studio_core/'.length)
          : key,
    );
    if (!file.existsSync()) return null;
    return ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync()));
  });
}
