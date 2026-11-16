import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/content/content_repository.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/services/example_code_store.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/widgets/collapsed_search_field.dart';
import 'package:qfli_studio_core/widgets/language_badge.dart';

import 'support/content_catalog_fixture.dart';

/// Pins requirement R6: tutorials and example code are one page.
///
/// The merged page owns one title, one shared language bar and one
/// single-line section switch. Each section keeps its own lazy list.
void main() {
  StudioProfile? originalProfile;

  setUp(() {
    originalProfile = StudioProfile.current;
    // No profile means the shared catalog and no product post-filter, which
    // keeps the language chips driven purely by the fixture content.
    StudioProfile.current = null;
  });

  tearDown(() => StudioProfile.current = originalProfile);

  testWidgets('the merged page titles itself 教程 and shares one language bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CountingRepository(fixtureCatalog());

    await tester.pumpWidget(
      _app(TutorialCenterPage(language: 'java', repository: repository)),
    );
    await tester.pumpAndSettle();

    final l10n = StudioLocalizations.of(
      tester.element(find.byType(TutorialCenterPage)),
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text(l10n.tutorial), findsWidgets);
    expect(find.text(l10n.examples), findsOneWidget);
    // One language bar, in the shared filter header.
    expect(
      find.byKey(const ValueKey('content-language-row')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('content-language-cpp')), findsNothing);
    expect(find.byKey(const ValueKey('content-language-java')), findsOneWidget);
    // The tutorial section is the initial one.
    expect(find.text('Java lesson 0-0'), findsOneWidget);
    expect(find.text('Java example 0'), findsNothing);
    expect(repository.tutorialRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('many languages stay one line at width 360', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The main product ships many subjects; this is the case that used to wrap
    // the chip bar over the whole screen.
    StudioProfile.current = const StudioProfile(
      id: StudioProductCatalog.qfliStudioKey,
      appTitle: StudioProductCatalog.qfliStudio,
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
    );

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: StudioProductCatalog.qfliStudioKey,
          repository: _CountingRepository(
            ContentCatalog.fromJson(
              tutorialsSource: _manyTutorials,
              examplesSource: _manyExamples,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('content-language-row'));
    expect(row, findsOneWidget);
    // Eight languages are far wider than 360dp; without the single-line bar
    // they would wrap into at least two rows and cover the content.
    final chips = find.descendant(of: row, matching: find.byType(ChoiceChip));
    expect(chips.evaluate().length, greaterThan(6));
    final rowRect = tester.getRect(row);
    final firstChip = tester.getRect(chips.first);
    // One line: the row is no taller than a chip plus its padding, and every
    // chip (including offstage ones) shares that vertical band.
    expect(rowRect.height, lessThan(firstChip.height * 2));
    for (final element in chips.evaluate()) {
      final box = element.renderObject! as RenderBox;
      expect(box.localToGlobal(Offset.zero).dy + box.size.height,
          lessThanOrEqualTo(rowRect.bottom + 1));
    }
    // Too wide to fit, so the bar scrolls instead of wrapping.
    expect(rowRect.width, lessThanOrEqualTo(360));
    final scrollable = find.descendant(
      of: row,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollable, findsOneWidget);
    final view = tester.widget<SingleChildScrollView>(scrollable);
    expect(view.scrollDirection, Axis.horizontal);
    // The bar really can be scrolled, so the offscreen languages stay
    // reachable; the row itself is never wider than the screen.
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: row, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(
      position.maxScrollExtent,
      greaterThanOrEqualTo(tester.getRect(chips.last).right - rowRect.right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the section switch keeps the chosen language', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: 'java',
          repository: FixtureContentRepository(fixtureCatalog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The fixture has no Python lessons or examples for the java page, so add
    // one language to the shared bar through the tutorial chip row first.
    final languageChip = find.byKey(const ValueKey('content-language-java'));
    expect(languageChip, findsOneWidget);
    await tester.tap(languageChip);
    await tester.pumpAndSettle();
    expect(find.text('Java lesson 0-0'), findsOneWidget);

    await tester.tap(find.byKey(TutorialCenterPage.examplesSectionKey));
    await tester.pumpAndSettle();

    expect(find.text('Java example 0'), findsOneWidget);
    expect(find.text('Java lesson 0-0'), findsNothing);
    // The section switch reused the selection: the java chip is still active.
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('content-language-java')),
    );
    expect(chip.selected, isTrue);
    expect(find.text('100 examples'), findsOneWidget);

    await tester.tap(find.byKey(TutorialCenterPage.tutorialSectionKey));
    await tester.pumpAndSettle();
    expect(find.text('Java lesson 0-0'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('content-language-java')),
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('one language selection filters both sections', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The main product carries every subject: its own product id is the page
    // language, so the adapter admits all languages instead of post-filtering.
    StudioProfile.current = const StudioProfile(
      id: StudioProductCatalog.qfliStudioKey,
      appTitle: StudioProductCatalog.qfliStudio,
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
    );
    final repository = _CountingRepository(
      ContentCatalog.fromJson(
        tutorialsSource: _tutorials,
        examplesSource: _examples,
      ),
    );

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: StudioProductCatalog.qfliStudioKey,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('content-language-java'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('content-language-cpp')), findsOneWidget);
    expect(find.byKey(const ValueKey('content-language-python')), findsOneWidget);

    // Both sections were loaded when the page opened, one request each. The
    // tutorial adapter asks for examples too: lessons resolve their input
    // fixtures from the paired examples.
    expect(repository.tutorialRequests, 1);
    expect(repository.exampleRequests, 2);

    await tester.tap(find.byKey(const ValueKey('content-language-cpp')));
    await tester.pumpAndSettle();
    expect(find.text('C++ lesson'), findsOneWidget);
    expect(find.text('Java lesson'), findsNothing);
    expect(find.text('Python lesson'), findsNothing);

    await tester.tap(find.byKey(TutorialCenterPage.examplesSectionKey));
    await tester.pumpAndSettle();
    expect(find.text('C++ example'), findsOneWidget);
    expect(find.text('Java example'), findsNothing);
    expect(find.text('Python example'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(
            // The shared bar scrolled horizontally after selecting C++; ask the
            // offstage-inclusive tree for the retained chip.
            find.byKey(
              const ValueKey('content-language-cpp'),
              skipOffstage: false,
            ),
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('both sections keep opening their detail pages', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: 'java',
          repository: FixtureContentRepository(fixtureCatalog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A lesson still opens its own route from the tutorial section.
    await tester.tap(find.text('Java lesson 0-0'));
    await tester.pumpAndSettle();
    expect(find.byType(ExampleDetailPage), findsNothing);
    expect(find.text('Explanation 0-0'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // An example still opens its detail route from the example section.
    await tester.tap(find.byKey(TutorialCenterPage.examplesSectionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Java example 0'));
    await tester.pumpAndSettle();
    expect(find.byType(ExampleDetailPage), findsOneWidget);
    final badge = tester.widget<LanguageBadge>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(LanguageBadge),
      ),
    );
    expect(languageLabel(badge.language), 'Java');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved examples stay editable from the merged page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('qfli_merge_examples_'),
    ))!;
    final examples = ExampleCodeStore(
      storageFile: File('${directory.path}/examples.json'),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      examples.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    });

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: 'java',
          repository: FixtureContentRepository(fixtureCatalog()),
          examples: examples,
        ),
      ),
    );
    await _waitFor(
      tester,
      () => find.text('Java lesson 0-0').evaluate().isNotEmpty,
      'merged tutorial catalog',
    );
    await tester.tap(find.byKey(TutorialCenterPage.examplesSectionKey));
    await _waitFor(
      tester,
      () => find.text('Java example 0').evaluate().isNotEmpty,
      'merged example catalog',
    );
    // The store was loaded from the same page, so saving stays available.
    await tester.tap(find.text('Java example 0'));
    await _waitFor(
      tester,
      () => find.byType(ExampleDetailPage).evaluate().isNotEmpty,
      'example detail',
    );
    final l10n = StudioLocalizations.of(
      tester.element(find.byType(ExampleDetailPage)),
    );
    expect(find.byTooltip(l10n.saveExample), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a section can start on example code', (tester) async {
    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: 'java',
          repository: FixtureContentRepository(fixtureCatalog()),
          initialSection: TutorialCenterSection.examples,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Java example 0'), findsOneWidget);
    expect(find.text('Java lesson 0-0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the search collapses to an icon like Home', (tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: 'java',
          repository: FixtureContentRepository(fixtureCatalog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = StudioLocalizations.of(
      tester.element(find.byType(TutorialCenterPage)),
    );
    // Collapsed: the title, a magnifier action and no field anywhere.
    expect(find.byType(CollapsedSearchButton), findsOneWidget);
    expect(find.byType(CollapsedSearchField), findsNothing);
    expect(find.byKey(const ValueKey('content-query')), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l10n.tutorial), findsWidgets);

    await tester.tap(find.byType(CollapsedSearchButton));
    await tester.pumpAndSettle();

    // Expanded: the shared field sits in the app bar, the title steps aside,
    // and the filter bar keeps only the chips.
    expect(find.byType(CollapsedSearchField), findsOneWidget);
    final field = find.byKey(const ValueKey('content-query'));
    expect(field, findsOneWidget);
    final bar = tester.getRect(find.byType(AppBar));
    final input = tester.getRect(field);
    expect(input.top, greaterThanOrEqualTo(bar.top));
    expect(input.bottom, lessThanOrEqualTo(bar.bottom));
    expect(find.byType(CollapsedSearchButton), findsNothing);
    expect(find.byKey(const ValueKey('content-language-row')), findsOneWidget);

    await tester.enterText(field, '0-0');
    await tester.pumpAndSettle();
    expect(find.text('Java lesson 0-0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsing the search clears the query', (tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: 'java',
          repository: _CountingRepository(
            ContentCatalog.fromJson(
              tutorialsSource: _tutorials,
              examplesSource: _examples,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('content-language-java')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CollapsedSearchButton));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('content-query'));
    await tester.enterText(field, 'java');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field).controller!.text,
      'java',
    );

    final l10n = StudioLocalizations.of(
      tester.element(find.byType(TutorialCenterPage)),
    );
    await tester.tap(find.byTooltip(l10n.exitSearch));
    await tester.pumpAndSettle();

    // Collapsed again, and the search words are gone with the field. The
    // language chip stays selected: collapsing clears the query only.
    expect(find.byType(CollapsedSearchField), findsNothing);
    expect(find.byKey(const ValueKey('content-no-results')), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('content-language-java')),
          )
          .selected,
      isTrue,
    );

    // Reopening starts from an empty field, the same as Home.
    await tester.tap(find.byType(CollapsedSearchButton));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the search and the section switch share one query', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StudioProfile.current = const StudioProfile(
      id: StudioProductCatalog.qfliStudioKey,
      appTitle: StudioProductCatalog.qfliStudio,
      templates: [],
      productKey: StudioProductCatalog.qfliStudioKey,
    );

    await tester.pumpWidget(
      _app(
        TutorialCenterPage(
          language: StudioProductCatalog.qfliStudioKey,
          repository: _CountingRepository(
            ContentCatalog.fromJson(
              tutorialsSource: _tutorials,
              examplesSource: _examples,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CollapsedSearchButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('content-query')),
      'C++',
    );
    await tester.pumpAndSettle();
    expect(find.text('C++ lesson'), findsOneWidget);
    expect(find.text('Java lesson'), findsNothing);

    // Switching sections keeps the query: the example list is filtered by it.
    await tester.tap(find.byKey(TutorialCenterPage.examplesSectionKey));
    await tester.pumpAndSettle();
    expect(find.text('C++ example'), findsOneWidget);
    expect(find.text('Java example'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('content-query')))
          .controller!
          .text,
      'C++',
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String description,
) async {
  // Real I/O needs real time; pumpAndSettle advances only the fake clock.
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    if (condition()) return;
  }
  fail('Timed out waiting for $description');
}

MaterialApp _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  supportedLocales: StudioLocalizations.supportedLocales,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light,
  home: home,
);

/// Counts how often each section asks the repository for content.
class _CountingRepository extends FixtureContentRepository {
  _CountingRepository(super.catalog);

  int tutorialRequests = 0;
  int exampleRequests = 0;

  @override
  Future<List<TutorialContent>> tutorials({
    ContentFilter filter = const ContentFilter(),
  }) async {
    tutorialRequests++;
    return super.tutorials(filter: filter);
  }

  @override
  Future<List<ExampleContent>> examples({
    ContentFilter filter = const ContentFilter(),
  }) async {
    exampleRequests++;
    return super.examples(filter: filter);
  }
}

const _subjects = <(String, String, String)>[
  ('java', 'Java', 'Print a value'),
  ('cpp', 'C++', 'Own a vector'),
  ('python', 'Python', 'Iterate a list'),
];

String get _tutorials {
  final entries = [
    for (final (type, label, summary) in _subjects)
      {
        'id': '$type-chapter',
        'language': type,
        'type': type,
        'locale': 'en',
        'level': 'beginner',
        'title': '$label chapter',
        'summary': summary,
        'concepts': ['output'],
        'source': 'test-fixture',
        'license': 'CC BY 4.0',
        'updatedAt': '2026-10-15',
        'lessons': [
          {
            'id': '$type-lesson',
            'title': '$label lesson',
            'summary': summary,
            'explain': 'Explanation',
            'code': 'print(1);',
            'output': '1',
          },
        ],
      },
  ];
  return _encode(entries);
}

String get _examples {
  final entries = [
    for (final (type, label, summary) in _subjects)
      {
        'id': '$type-example',
        'language': type,
        'type': type,
        'locale': 'en',
        'level': 'beginner',
        'title': '$label example',
        'summary': summary,
        'concepts': ['output'],
        'source': 'test-fixture',
        'license': 'CC BY 4.0',
        'updatedAt': '2026-10-15',
        'code': 'print(1);',
        'expectedOutput': '1',
        'templateType': type,
      },
  ];
  return _encode(entries);
}

String _encode(List<Map<String, Object>> entries) => jsonEncode({
  'schemaVersion': 1,
  'entries': entries,
});

/// The subject set the main product actually ships, in catalog order.
const _allSubjects = <String>[
  'c',
  'cpp',
  'lua',
  'javascript',
  'typescript',
  'shell',
  'rust',
  'go',
  'java',
  'html',
  'css',
  'python',
  'dart',
  'sql',
  'json',
  'markdown',
];

Map<String, Object> _entry(String type) => {
  'language': type,
  'type': type,
  'locale': 'en',
  'level': 'beginner',
  'summary': 'Summary',
  'concepts': <String>['output'],
  'source': 'test-fixture',
  'license': 'CC BY 4.0',
  'updatedAt': '2026-10-15',
};

final _manyTutorials = _encode([
  for (final type in _allSubjects)
    {
      ..._entry(type),
      'id': '$type-chapter',
      'title': '$type chapter',
      'lessons': [
        {
          'id': '$type-lesson',
          'title': '$type lesson',
          'summary': 'Summary',
          'explain': 'Explanation',
          'code': 'code',
          'output': 'out',
        },
      ],
    },
]);

final _manyExamples = _encode([
  for (final type in _allSubjects)
    {
      ..._entry(type),
      'id': '$type-example',
      'title': '$type example',
      'code': 'code',
      'expectedOutput': 'out',
      'templateType': type,
    },
]);
