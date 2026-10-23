import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/highlight_themes.dart';
import 'package:qfli_studio_core/editor/symbols_bar.dart';
import 'package:qfli_studio_core/editor/textmate_grammar.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/re_highlight.dart';

const _cppSource =
    'namespace demo {\r\ntemplate<class T> class Box {};\r\n}\r\n';
const _cSource = 'int template = 2;\r\n';

void main() {
  testWidgets(
    'same-name cross-project headers retain their owner grammar and symbols',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(Scaffold));
      final root = Directory.systemTemp.createTempSync('qfli_header_owners_');
      final primary = Project.create(
        name: 'C primary',
        path: p.join(root.path, 'c'),
        type: 'c',
        language: 'C',
      );
      final secondary = Project.create(
        name: 'C++ secondary',
        path: p.join(root.path, 'cpp'),
        type: 'cpp',
        language: 'C++',
      );
      final cHeader = File(p.join(primary.path, 'local.h'));
      final cppHeader = File(p.join(secondary.path, 'local.h'));
      for (final header in [cHeader, cppHeader]) {
        header.parent.createSync(recursive: true);
      }
      cHeader.writeAsStringSync(_cSource);
      cppHeader.writeAsStringSync(_cppSource);
      final editor = EditorController(project: primary);
      addTearDown(() {
        editor.dispose();
        root.deleteSync(recursive: true);
      });
      expect(
        await tester.runAsync(() => editor.openPath(cHeader.path)),
        isNull,
      );
      final cOpen = editor.current!;
      expect(
        await tester.runAsync(
          () => editor.openPath(
            cppHeader.path,
            ownerProjectName: secondary.name,
            ownerProjectPath: secondary.path,
            ownerProjectType: secondary.type,
          ),
        ),
        isNull,
      );
      final cppOpen = editor.current!;
      expect(cOpen.name, cppOpen.name);
      expect(cOpen.projectType, 'c');
      expect(cppOpen.projectType, 'cpp');
      expect(cppOpen.projectRootPath, secondary.path);

      final cTheme = HighlightThemes.themeFor(
        context,
        cOpen.name,
        cOpen.controller.text,
        ownerType: cOpen.projectType,
      )!;
      final cppTheme = HighlightThemes.themeFor(
        context,
        cppOpen.name,
        cppOpen.controller.text,
        ownerType: cppOpen.projectType,
      )!;
      expect(cTheme.language, 'c');
      expect(cppTheme.language, 'cpp');
      final cppTokens = _tokens(cppTheme, _cppSource);
      expect(cppTokens.source, _cppSource);
      expect(cppTokens.hasKeyword('template'), isTrue);
      expect(cppTokens.hasKeyword('namespace'), isTrue);
      final cTokens = _tokens(cTheme, _cSource);
      expect(cTokens.source, _cSource);
      expect(
        cTokens.hasKeyword('template'),
        isFalse,
        reason: 'template remains a valid C identifier',
      );
      expect(_tokens(cTheme, _cppSource).hasKeyword('template'), isFalse);

      final cppLanguage = languageForFileName(
        cppOpen.name,
        ownerType: cppOpen.projectType,
      );
      final cLanguage = languageForFileName(
        cOpen.name,
        ownerType: cOpen.projectType,
      );
      expect(cppLanguage, 'C++');
      expect(cLanguage, 'C');
      expect(kDefaultSymbolSets[cppLanguage], contains('::'));
      expect(kDefaultSymbolSets[cLanguage], isNot(contains('::')));
      expect(kDefaultSymbolSets[cLanguage], containsAll(['&', '*']));
      editor.select(0);
      // A preceding C++ header must not poison the cache for the primary C tab.
      expect(
        HighlightThemes.themeFor(
          context,
          editor.current!.name,
          null,
          ownerType: editor.current!.projectType,
        ),
        same(cTheme),
      );
      expect(cHeader.readAsStringSync(), _cSource);
      expect(cppHeader.readAsStringSync(), _cppSource);
      await tester.pump();
    },
  );

  testWidgets(
    'owner hints disambiguate h while explicit extensions and legacy defaults remain',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(Scaffold));
      const cases = <(String, String, String)>[
        ('local.h', '', 'c'),
        ('local.h', 'c', 'c'),
        ('local.H', ' CPP ', 'cpp'),
        ('local.h', 'C++', 'cpp'),
        ('local.h', 'python', 'c'),
        ('main.c', 'cpp', 'c'),
        ('local.hpp', 'c', 'cpp'),
        ('local.hh', 'c', 'cpp'),
        ('local.hxx', 'c', 'cpp'),
        ('local.inl', 'c', 'cpp'),
        ('main.cpp', 'c', 'cpp'),
        ('main.cc', 'c', 'cpp'),
        ('main.cxx', 'c', 'cpp'),
      ];
      for (final (name, owner, language) in cases) {
        expect(
          HighlightThemes.themeFor(
            context,
            name,
            null,
            ownerType: owner,
          )!.language,
          language,
          reason: '$name owned by $owner',
        );
        expect(
          languageForFileName(name, ownerType: owner),
          language == 'cpp' ? 'C++' : 'C',
          reason: '$name owned by $owner',
        );
      }
      expect(HighlightThemes.themeFor(context, 'local.h', null)!.language, 'c');
      expect(languageForFileName('local.h'), 'C');
      expect(languageForFileName('readme.unknown', ownerType: 'cpp'), isEmpty);
      expect(
        HighlightThemes.themeFor(
          context,
          'readme.unknown',
          null,
          ownerType: 'cpp',
        ),
        isNull,
      );
    },
  );

  testWidgets('custom header grammar keeps precedence over the owner hint', (
    tester,
  ) async {
    final settings = SettingsStore();
    addTearDown(settings.dispose);
    settings.customGrammars = [
      TextMateGrammar.parse(r'''{
      "name": "Header override", "scopeName": "source.custom-header", "fileTypes": ["h"],
      "patterns": [{"name": "keyword.control.header", "match": "\\bowner_keyword\\b"}]
    }'''),
    ];
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(Scaffold));
    for (final owner in ['c', 'cpp']) {
      final theme = HighlightThemes.themeFor(
        context,
        'local.h',
        null,
        settings: settings,
        ownerType: owner,
      )!;
      expect(theme.language, 'source.custom-header');
      final tokens = _tokens(theme, 'owner_keyword template');
      expect(tokens.source, 'owner_keyword template');
      expect(
        tokens.parts.any(
          (part) =>
              part.text == 'owner_keyword' &&
              settings.customGrammars.single.scopes[part.scope] ==
                  'keyword.control.header',
        ),
        isTrue,
      );
      expect(tokens.hasKeyword('template'), isFalse);
    }
  });

  testWidgets('C++ owned header symbol bar inserts the C++ scope operator', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('');
    addTearDown(controller.dispose);
    final language = languageForFileName('local.h', ownerType: 'cpp');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SymbolsBar(
              language: language,
              controller: controller,
              symbols: kDefaultSymbolSets[language]!,
              onSymbolsEdited: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('::'));
    await tester.tap(find.text('::'));
    expect(controller.text, '::');
    expect(controller.selection.extentOffset, 2);
  });
}

_Tokens _tokens(CodeHighlightTheme theme, String source) {
  final highlight = Highlight()
    ..debugMode()
    ..registerLanguages(
      theme.languages.map((name, value) => MapEntry(name, value.mode)),
    );
  final tokens = _Tokens();
  highlight.highlight(code: source, language: theme.language!).render(tokens);
  return tokens;
}

class _Tokens implements HighlightRenderer {
  final parts = <({String text, String? scope})>[];
  final _scopes = <String?>[];
  String get source => parts.map((part) => part.text).join();
  bool hasKeyword(String text) =>
      parts.any((part) => part.text == text && part.scope == 'keyword');
  @override
  void addText(String text) =>
      parts.add((text: text, scope: _scopes.isEmpty ? null : _scopes.last));
  @override
  void openNode(DataNode node) =>
      _scopes.add(node.scope ?? (_scopes.isEmpty ? null : _scopes.last));
  @override
  void closeNode(DataNode node) => _scopes.removeLast();
}
