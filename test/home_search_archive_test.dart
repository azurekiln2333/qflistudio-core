import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/picker_service.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/project_zip_service.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/widgets/project_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('qflistudio/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late PathProviderPlatform previousPaths;
  StudioProfile? previousProfile;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('qfli_home_archive_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    await AppPaths.storageDirectory();
    await AppPaths.projectsRoot(create: true);
  });

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'java',
      appTitle: 'QFLIJVMX',
      productKey: StudioProductCatalog.jvmxKey,
      templates: [ProjectTemplate.java],
      isOffline: true,
      showHomeTabs: false,
    );
    PickerService.forcePlatformChannel = true;
  });

  tearDown(() {
    StudioProfile.current = previousProfile;
    PickerService.forcePlatformChannel = false;
    messenger.setMockMethodCallHandler(channel, null);
  });

  tearDownAll(() {
    PathProviderPlatform.instance = previousPaths;
    root.deleteSync(recursive: true);
  });

  testWidgets(
    'search is aligned, unclipped and keeps filtering and clear on narrow large text',
    (tester) async {
      await _mount(tester, root, width: 320, textScale: 2);
      await tester.tap(find.byIcon(Icons.search));
      await _settle(tester);

      final field = find.byKey(const ValueKey('home-project-search-field'));
      final editable = tester
          .state<EditableTextState>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .renderEditable;
      final appBar = tester.getRect(find.byType(AppBar));
      final input = tester.getRect(field);
      expect(input.top, greaterThanOrEqualTo(appBar.top));
      expect(input.bottom, lessThanOrEqualTo(appBar.bottom));
      expect(
        editable.size.height,
        greaterThanOrEqualTo(editable.preferredLineHeight),
      );
      // The empty cursor starts at the leading inset, leaving the hint's text
      // space in front of it rather than inserting the caret through its middle.
      final caret = editable.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      expect(caret.left, lessThan(8));
      expect(tester.takeException(), isNull);

      await tester.enterText(field, 'no-match');
      await _settle(tester);
      expect(find.byType(ProjectCard).hitTestable(), findsNothing);
      await tester.tap(find.byIcon(Icons.close));
      await _settle(tester);
      expect(find.byType(ProjectCard).hitTestable(), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await _settle(tester);
      expect(field, findsNothing);
      expect(find.text('全部项目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final useUri in [false, true]) {
    testWidgets(
      'project menu exports a real .qsz through ${useUri ? 'native URI' : 'local path'}',
      (tester) async {
        final fixture = await _mount(tester, root);
        final destination = p.join(fixture.directory.path, 'exported');
        String? suggestedName;
        Uint8List? written;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'saveDocument') {
            suggestedName = (call.arguments as Map)['suggestedName'] as String;
            return useUri
                ? {'uri': 'content://export.qsz'}
                : {'path': destination};
          }
          if (call.method == 'writeUri') {
            expect((call.arguments as Map)['uri'], 'content://export.qsz');
            written = (call.arguments as Map)['bytes'] as Uint8List;
          }
          return null;
        });
        await _export(tester);
        await _waitFor(
          tester,
          () =>
              useUri ? written != null : File('$destination.qsz').existsSync(),
        );
        expect(suggestedName, 'Alpha.qsz');
        final bytes = written ?? File('$destination.qsz').readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);
        expect(
          archive.files.any((file) => file.name.endsWith('Main.java')),
          isTrue,
        );
        expect(
          File(p.join(fixture.project.path, 'Main.java')).existsSync(),
          isTrue,
        );
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey('project-archive-progress'))
              .evaluate()
              .isEmpty,
        );
        expect(find.text('已导出项目「Alpha」'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'imports .qsz through ${useUri ? 'native URI' : 'local path'} and immediately lists it without opening editor',
      (tester) async {
        final fixture = await _mount(tester, root);
        final imported = _makeProject(fixture.directory, 'Imported');
        final bytes = await tester.runAsync(
          () => ProjectZipService.exportProject(imported),
        );
        final archiveFile = File(p.join(fixture.directory.path, 'incoming.qsz'))
          ..writeAsBytesSync(bytes!);
        List<Object?>? extensions;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'pickDocument') {
            extensions = (call.arguments as Map)['extensions'] as List<Object?>;
            return useUri
                ? {'uri': 'content://incoming', 'name': 'incoming.qsz'}
                : {'path': archiveFile.path};
          }
          if (call.method == 'readUri') return bytes;
          return null;
        });
        // Import switches back to All so the new unstarred project is visible
        // even if the user starts the flow while browsing Favorites.
        await tester.tap(find.text('收藏项目'));
        await _settle(tester);
        await _import(tester);
        await _waitFor(tester, () => fixture.projects.projects.length == 2);
        await _waitFor(
          tester,
          () => find
              .byKey(const ValueKey('project-archive-progress'))
              .evaluate()
              .isEmpty,
        );
        await _settle(tester);
        expect(extensions, ['qsz']);
        expect(find.text('Imported').hitTestable(), findsOneWidget);
        expect(find.byType(EditorPage), findsNothing);
        final registered = fixture.projects.projects.singleWhere(
          (project) => project.name == 'Imported',
        );
        expect(registered.path, isNot(imported.path));
        expect(
          File(p.join(registered.path, 'Main.java')).readAsStringSync(),
          'class Main {}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'adding qsz suffix never overwrites an existing unconfirmed target',
    (tester) async {
      final fixture = await _mount(tester, root);
      final selectedPath = p.join(fixture.directory.path, 'existing');
      final destination = File('$selectedPath.qsz');
      const marker = [0, 255, 7, 66, 1];
      destination.writeAsBytesSync(marker);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'saveDocument') return {'path': selectedPath};
        return null;
      });

      await _export(tester);
      await _waitFor(
        tester,
        () => find.textContaining('目标文件已存在').evaluate().isNotEmpty,
      );

      expect(destination.readAsBytesSync(), marker);
      expect(File(selectedPath).existsSync(), isFalse);
      expect(find.textContaining('请直接选择 .qsz 文件并确认覆盖'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('project-archive-progress')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picker cancellation clears busy feedback and never changes registry',
    (tester) async {
      final fixture = await _mount(tester, root);
      final pending = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'saveDocument') return pending.future;
        return null;
      });
      await _export(tester);
      expect(
        find.byKey(const ValueKey('project-archive-progress')),
        findsOneWidget,
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await _settle(tester);
      final item = tester.widget<PopupMenuItem<String>>(
        find.ancestor(
          of: find.text('导入项目（.qsz）'),
          matching: find.byType(PopupMenuItem<String>),
        ),
      );
      expect(item.enabled, isFalse);
      await tester.tapAt(const Offset(10, 300));
      pending.complete(null);
      await _settle(tester);
      await _import(tester);
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('project-archive-progress')),
        findsNothing,
      );
      expect(find.textContaining('失败'), findsNothing);
      expect(fixture.projects.projects, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bad project archive gives readable feedback and keeps existing projects',
    (tester) async {
      final fixture = await _mount(tester, root);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickDocument') {
          return {'uri': 'content://bad', 'name': 'bad.qsz'};
        }
        if (call.method == 'readUri') return Uint8List.fromList([1, 2, 3]);
        return null;
      });
      await _import(tester);
      await _waitFor(
        tester,
        () => find.textContaining('导入失败：').evaluate().isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey('project-archive-progress')),
        findsNothing,
      );
      expect(fixture.projects.projects, hasLength(1));
      expect(find.text('Alpha').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final exporting in [false, true]) {
    testWidgets(
      'disposing during ${exporting ? 'export' : 'import'} picker skips file work',
      (tester) async {
        final fixture = await _mount(tester, root);
        final destination = p.join(
          fixture.directory.path,
          'must-not-exist.qsz',
        );
        final pending = Completer<Object?>();
        var readCalls = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'saveDocument' || call.method == 'pickDocument') {
            return pending.future;
          }
          if (call.method == 'readUri') readCalls++;
          return null;
        });
        if (exporting) {
          await _export(tester);
        } else {
          await _import(tester);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        pending.complete(
          exporting
              ? {'path': destination}
              : {'uri': 'content://incoming', 'name': 'incoming.qsz'},
        );
        await _settle(tester);
        expect(File(destination).existsSync(), isFalse);
        expect(readCalls, 0);
        expect(fixture.projects.projects, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('cloud and missing folders do not offer project archive export', (
    tester,
  ) async {
    final existing = _makeProject(root, 'MenuSource');
    final auth = AuthStore();
    addTearDown(auth.dispose);
    for (final project in [
      Project.create(name: 'Cloud', path: existing.path, cloudId: 'cloud'),
      Project.create(name: 'Missing', path: p.join(root.path, 'missing')),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectCard(
              key: ValueKey(project.id),
              project: project,
              onOpen: () {},
              onRemove: () {},
              onExport: () {},
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.tap(find.byTooltip('更多操作'));
      await _settle(tester);
      expect(find.text('压缩导出项目'), findsNothing);
      await tester.tapAt(const Offset(10, 500));
      await _settle(tester);
    }
    expect(tester.takeException(), isNull);
  });
}

Future<_Fixture> _mount(
  WidgetTester tester,
  Directory root, {
  double width = 600,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final directory = root.createTempSync('fixture_');
  final project = _makeProject(directory, 'Alpha');
  final registry = File(p.join(directory.path, 'projects.json'))
    ..writeAsStringSync(
      jsonEncode({
        'version': 1,
        'projects': [project.toJson()],
      }),
    );
  final fixture = _Fixture(
    directory,
    project,
    ProjectStore(storageFile: registry),
  );
  await tester.runAsync(fixture.projects.load);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.projects.dispose();
    fixture.auth.dispose();
    fixture.settings.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        StudioLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HomeTab(
        store: fixture.projects,
        auth: fixture.auth,
        settings: fixture.settings,
      ),
    ),
  );
  await _settle(tester);
  // TabBarView creates its visible list on a subsequent frame. Leave fake
  // async only after that frame so the card's asynchronous directory probe
  // can complete before the test opens its menu.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await _settle(tester);
  return fixture;
}

Project _makeProject(Directory root, String name) {
  final directory = Directory(p.join(root.path, name))..createSync();
  File(p.join(directory.path, 'Main.java')).writeAsStringSync('class Main {}');
  return Project.create(
    name: name,
    path: directory.path,
    language: 'Java',
    type: 'java',
  );
}

Future<void> _export(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多操作').hitTestable().first);
  await _settle(tester);
  await tester.tap(find.text('压缩导出项目'));
  await _settle(tester);
}

Future<void> _import(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await _settle(tester);
  await tester.tap(find.text('导入项目（.qsz）'));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _waitFor(WidgetTester tester, bool Function() completed) async {
  for (var i = 0; i < 200 && !completed(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(completed(), isTrue, reason: 'archive operation should complete');
  await _settle(tester);
}

class _Fixture {
  _Fixture(this.directory, this.project, this.projects);
  final Directory directory;
  final Project project;
  final ProjectStore projects;
  final auth = AuthStore();
  final settings = SettingsStore();
}

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
