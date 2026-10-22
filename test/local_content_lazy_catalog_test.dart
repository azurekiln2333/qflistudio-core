import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/pages/local_content_pages.dart';
import 'package:qfli_studio_core/services/example_code_store.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/widgets/code_snippet.dart';

import 'support/content_catalog_fixture.dart';

void main() {
  StudioProfile? originalProfile;

  setUp(() {
    originalProfile = StudioProfile.current;
    // Exercise the language filter as well as grouped row indexing.
    StudioProfile.current = null;
  });

  tearDown(() => StudioProfile.current = originalProfile);

  testWidgets('tutorial groups build lazily and the final lesson opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LocalTutorialsTab(
          language: 'java',
          repository: FixtureContentRepository(fixtureCatalog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    // An eager ListView(children: ...) also mounts only visible elements. The
    // builder delegate check additionally rules out constructing every Widget.
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    // One shared filter header, two chapter rows and one hundred lazy lessons.
    expect(list.childrenDelegate.estimatedChildCount, 103);
    expect(find.byType(ListTile).evaluate().length, lessThan(100));
    expect(find.text('Java chapter 0'), findsOneWidget);
    expect(find.text('Java lesson 0-0'), findsOneWidget);
    expect(find.text('Lesson summary 0-0'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Java chapter 0')).dy,
      lessThan(tester.getTopLeft(find.text('Java lesson 0-0')).dy),
    );
    expect(find.text('Java chapter 1'), findsNothing);
    expect(find.text('Java lesson 1-49'), findsNothing);
    expect(find.text('Python chapter', skipOffstage: false), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Java chapter 1'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 100,
    );
    expect(find.text('Java chapter 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Java lesson 1-49'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 100,
    );
    expect(find.text('Lesson summary 1-49'), findsOneWidget);
    await tester.tap(find.text('Java lesson 1-49'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Java lesson 1-49'), findsOneWidget);
    expect(find.text('Explanation 1-49'), findsOneWidget);
    final snippet = tester.widget<CodeSnippet>(find.byType(CodeSnippet));
    expect(snippet.example.id, 'java-lesson-1-49');
    expect(snippet.example.type, 'java');
    expect(snippet.example.code, 'System.out.println("1-49");');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'examples build lazily and the final saved example stays editable',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('qfli_lazy_examples_'),
      ))!;
      final examples = ExampleCodeStore(
        storageFile: File('${directory.path}/examples.json'),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        examples.dispose();
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      const savedCode = 'System.out.println("my saved example");';
      await tester.runAsync(() async {
        await examples.load();
        await examples.upsert(
          const ExampleCode(
            id: 'java-example-99',
            type: 'java',
            title: 'Java example 99',
            summary: 'Example summary 99',
            code: savedCode,
            output: 'example 99',
          ),
        );
      });
      await tester.pumpWidget(
        _app(
          ExampleCodeTab(
            language: 'java',
            repository: FixtureContentRepository(fixtureCatalog()),
            examples: examples,
          ),
        ),
      );
      await _waitFor(
        tester,
        () => find.text('Java example 0').evaluate().isNotEmpty,
        'example catalog',
      );

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
      expect(list.childrenDelegate.estimatedChildCount, 101);
      expect(find.byType(ListTile).evaluate().length, lessThan(100));
      final l10n = StudioLocalizations.of(
        tester.element(find.byType(ExampleCodeTab)),
      );
      expect(find.text(l10n.examplesCount(100)), findsOneWidget);
      expect(find.text('Java example 0'), findsOneWidget);
      expect(find.text('Example summary 0'), findsOneWidget);
      expect(find.text('Java example 99'), findsNothing);
      expect(find.text('Python example', skipOffstage: false), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Java example 99'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 100,
      );
      expect(find.text('Example summary 99'), findsOneWidget);
      await tester.tap(find.text('Java example 99'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Java example 99'), findsOneWidget);
      final snippet = tester.widget<CodeSnippet>(find.byType(CodeSnippet));
      expect(snippet.example.id, 'java-example-99');
      final codeField = find.descendant(
        of: find.byType(CodeSnippet),
        matching: find.byType(TextField),
      );
      final field = tester.widget<TextField>(codeField);
      expect(field.controller!.text, savedCode);
      await tester.enterText(codeField, 'System.out.println("edit");');
      expect(field.controller!.text, 'System.out.println("edit");');
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition,
  String description,
) async {
  // Real I/O needs real time; pumpAndSettle advances only the fake frame clock.
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
