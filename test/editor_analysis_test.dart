import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_analysis_controller.dart';
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_diagnostics.dart';
import 'package:qfli_studio_core/editor/editor_problems_bar.dart';
import 'package:qfli_studio_core/editor/open_file.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/code_analysis.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  late Directory root;
  late EditorController editor;
  setUp(() {
    root = Directory.systemTemp.createTempSync('qfli_analysis_');
    editor = EditorController(
      project: Project.create(
        name: 'Analysis',
        path: root.path,
        type: 'dart',
        language: 'Dart',
      ),
    );
  });
  tearDown(() {
    editor.dispose();
    root.deleteSync(recursive: true);
  });

  Future<OpenFile> open(
    WidgetTester tester,
    String name,
    String text, {
    String? owner,
    String? ownerType,
    bool readOnly = false,
  }) async {
    final path = p.join(owner ?? root.path, name);
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(text);
    expect(
      await tester.runAsync(
        () => editor.openPath(
          path,
          ownerProjectPath: owner,
          ownerProjectType: ownerType,
          readOnly: readOnly,
        ),
      ),
      isNull,
    );
    return editor.current!;
  }

  testWidgets(
    'requests preserve unsaved UTF-16/CRLF and every open owner-root buffer',
    (tester) async {
      final first = await open(tester, 'main.dart', '😀\r\nbad()\r\n');
      final header = await open(tester, 'local.h', 'int saved;');
      header.controller.text = 'int unsaved;';
      final foreignRoot = Directory(p.join(root.path, 'other'))..createSync();
      await open(tester, 'other.dart', 'foreign', owner: foreignRoot.path);
      editor.select(editor.files.indexOf(first));
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
      );
      addTearDown(analysis.dispose);
      await tester.pump(const Duration(milliseconds: 301));
      final request = provider.requests.single;
      expect(request.language, 'dart');
      expect(request.projectPath, root.path);
      expect(request.documents.map((doc) => doc.path), [
        first.path,
        header.path,
      ]);
      expect(request.documents.first.text, '😀\r\nbad()\r\n');
      expect(request.documents.last.text, 'int unsaved;');
      expect(request.documents.last.revision, 1);
      expect(() => request.documents.clear(), throwsUnsupportedError);
      final diagnostic = CodeDiagnostic(
        filePath: first.path,
        startOffset: 4,
        endOffset: 7,
        message: 'Unknown call',
        source: 'test',
      );
      provider.results.single.complete(
        CodeAnalysisResult(diagnostics: [diagnostic]),
      );
      await tester.pump();
      expect(analysis.checked, isTrue);
      expect(analysis.location(diagnostic), 'main.dart:2:1');
      await analysis.navigate(diagnostic);
      expect(first.controller.selection.baseIndex, 1);
      expect(first.controller.selection.baseOffset, 0);
      expect(first.controller.selection.extentOffset, 3);
      expect(File(header.path).readAsStringSync(), 'int saved;');
    },
  );

  testWidgets(
    'selection and unchanged line objects do not check or dirty a file',
    (tester) async {
      final file = await open(tester, 'main.dart', 'first\nsecond');
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
      );
      addTearDown(analysis.dispose);
      await tester.pump(const Duration(milliseconds: 301));
      provider.results.single.complete(const CodeAnalysisResult());
      await tester.pump();
      file.controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 3,
      );
      file.controller.codeLines = CodeLines.fromText(file.controller.text);
      await tester.pump(const Duration(seconds: 1));
      expect(provider.requests, hasLength(1));
      expect(file.revision, 0);
      expect(file.dirty, isFalse);
      expect(analysis.checked, isTrue);
    },
  );

  testWidgets(
    'editing any captured buffer discards the whole stale result and queues once',
    (tester) async {
      final first = await open(tester, 'main.dart', 'bad');
      final header = await open(tester, 'local.h', 'old');
      editor.select(0);
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
      );
      addTearDown(analysis.dispose);
      await tester.pump(const Duration(milliseconds: 301));
      header.controller.text = 'new';
      header.controller.text = 'newest';
      await tester.pump(const Duration(milliseconds: 301));
      expect(provider.requests, hasLength(1));
      provider.results.first.complete(
        CodeAnalysisResult(
          diagnostics: [
            CodeDiagnostic(
              filePath: first.path,
              startOffset: 0,
              endOffset: 3,
              message: 'stale',
            ),
          ],
        ),
      );
      await tester.pump();
      expect(provider.requests, hasLength(2));
      expect(analysis.problems, isEmpty);
      expect(first.diagnostics!.problems, isEmpty);
      expect(provider.requests.last.documents.last.text, 'newest');
      final valid = CodeDiagnostic(
        filePath: first.path,
        startOffset: 0,
        endOffset: 3,
        message: 'current',
      );
      provider.results.last.complete(
        CodeAnalysisResult(
          diagnostics: [
            valid,
            CodeDiagnostic(
              filePath: p.join(root.parent.path, 'foreign.dart'),
              startOffset: 0,
              endOffset: 1,
              message: 'foreign',
            ),
            CodeDiagnostic(
              filePath: first.path,
              startOffset: -1,
              endOffset: 1,
              message: 'negative',
            ),
            CodeDiagnostic(
              filePath: first.path,
              startOffset: 0,
              endOffset: 999,
              message: 'out of range',
            ),
            const CodeDiagnostic(
              filePath: 'relative.dart',
              startOffset: 0,
              endOffset: 1,
              message: 'relative',
            ),
          ],
        ),
      );
      await tester.pump();
      expect(analysis.problems, [valid]);
      first.controller.text = 'fixed';
      expect(first.diagnostics!.problems, isEmpty);
      expect(analysis.checked, isFalse);
      await tester.pump(const Duration(milliseconds: 301));
      provider.results.last.complete(const CodeAnalysisResult());
      await tester.pump();
    },
  );

  testWidgets(
    'timeout keeps backend concurrency bounded and unavailable distinct from clean',
    (tester) async {
      final file = await open(tester, 'main.dart', 'bad');
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
        debounce: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 1),
      );
      addTearDown(analysis.dispose);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(analysis.checked, isFalse);
      expect(analysis.pending, isFalse);
      expect(analysis.unavailableReason, contains('超时'));
      file.controller.text = 'fixed';
      await tester.pump(const Duration(milliseconds: 2));
      expect(provider.requests, hasLength(1));
      provider.results.first.complete(const CodeAnalysisResult());
      await tester.pump();
      expect(provider.requests, hasLength(2));
      provider.results.last.completeError(StateError('compiler missing'));
      await tester.pump();
      expect(analysis.checked, isFalse);
      expect(analysis.unavailableReason, contains('compiler missing'));
      expect(file.diagnostics!.problems, isEmpty);
    },
  );

  testWidgets(
    'closing/switching owner root invalidates in-flight diagnostics',
    (tester) async {
      final first = await open(tester, 'main.dart', 'bad');
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
      );
      addTearDown(analysis.dispose);
      await tester.pump(const Duration(milliseconds: 301));
      final otherRoot = Directory(p.join(root.path, 'other'))..createSync();
      final other = await open(
        tester,
        'main.lua',
        'local x = 1',
        owner: otherRoot.path,
      );
      analysis.requestAnalysis(immediate: true);
      await tester.pump(const Duration(milliseconds: 1));
      provider.results.first.complete(
        CodeAnalysisResult(
          diagnostics: [
            CodeDiagnostic(
              filePath: first.path,
              startOffset: 0,
              endOffset: 3,
              message: 'stale',
            ),
          ],
        ),
      );
      await tester.pump();
      expect(provider.requests.last.projectPath, otherRoot.path);
      expect(provider.requests.last.documents.single.path, other.path);
      editor.closeAll();
      provider.results.last.complete(const CodeAnalysisResult());
      await tester.pump();
      expect(analysis.problems, isEmpty);
      expect(analysis.checked, isFalse);
    },
  );

  testWidgets(
    'read-only history and missing analyzers never claim successful checks',
    (tester) async {
      await open(tester, 'history.dart', 'bad', readOnly: true);
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
      );
      final missing = EditorAnalysisController(editor: editor, analyzer: null);
      addTearDown(analysis.dispose);
      addTearDown(missing.dispose);
      await tester.pump(const Duration(seconds: 1));
      expect(provider.requests, isEmpty);
      expect(analysis.checked, isFalse);
      expect(missing.checked, isFalse);
      expect(missing.unavailableReason, isNotNull);
    },
  );

  testWidgets(
    'wavy ranges preserve syntax colors and complete Unicode characters',
    (tester) async {
      final file = await open(tester, 'main.dart', 'let 😀x\r\nbad()');
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(Scaffold));
      file.diagnostics!.update(file.controller.text, [
        CodeDiagnostic(
          filePath: file.path,
          startOffset: 5,
          endOffset: 7,
          message: 'range',
        ),
      ]);
      const tokens = TextSpan(
        children: [
          TextSpan(
            text: 'let ',
            style: TextStyle(color: Colors.blue),
          ),
          TextSpan(
            text: '😀x',
            style: TextStyle(color: Colors.green),
          ),
        ],
      );
      final decorated = file.diagnostics!.decorate(
        context: context,
        index: 0,
        codeLine: file.controller.codeLines[0],
        textSpan: tokens,
        style: const TextStyle(),
      );
      expect(decorated.toPlainText(), 'let 😀x');
      final leaves = <({String text, TextStyle style})>[];
      void visit(TextSpan span, TextStyle style) {
        final effective = style.merge(span.style);
        if (span.text != null) leaves.add((text: span.text!, style: effective));
        for (final child in span.children ?? const <InlineSpan>[]) {
          if (child is TextSpan) visit(child, effective);
        }
      }

      visit(decorated, const TextStyle());
      expect(leaves.first.text, 'let ');
      expect(leaves.first.style.color, Colors.blue);
      expect(leaves.last.text, '😀x');
      expect(leaves.last.style.color, Colors.green);
      expect(leaves.last.style.decorationStyle, TextDecorationStyle.wavy);
      expect(leaves.first.style.decoration, isNull);
    },
  );

  testWidgets(
    'a queued request receives its own timeout after the previous lane finishes',
    (tester) async {
      final file = await open(tester, 'main.dart', 'first');
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
        debounce: const Duration(milliseconds: 1),
        timeout: const Duration(seconds: 1),
      );
      addTearDown(analysis.dispose);
      await tester.pump(const Duration(milliseconds: 2));
      file.controller.text = 'second';
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(provider.requests, hasLength(1));
      expect(analysis.unavailableReason, contains('超时'));
      provider.results.first.complete(const CodeAnalysisResult());
      await tester.pump();
      expect(provider.requests, hasLength(2));
      expect(analysis.pending, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(analysis.pending, isFalse);
      expect(analysis.checked, isFalse);
      expect(analysis.unavailableReason, contains('超时'));
    },
  );

  testWidgets('C++ header analysis uses the active owner project type', (
    tester,
  ) async {
    final file = await open(
      tester,
      'local.h',
      'template<class T> struct Box {};',
      ownerType: 'cpp',
    );
    final provider = _Analyzer();
    final analysis = EditorAnalysisController(
      editor: editor,
      analyzer: provider,
    );
    addTearDown(analysis.dispose);
    await tester.pump(const Duration(milliseconds: 301));
    expect(file.projectType, 'cpp');
    expect(provider.requests.single.language, 'cpp');
    provider.results.single.complete(const CodeAnalysisResult());
    await tester.pump();
  });

  testWidgets(
    'oversized snapshots never dispatch and returned problems are bounded',
    (tester) async {
      final file = await open(tester, 'main.dart', 'x');
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
      );
      addTearDown(analysis.dispose);
      file.controller.text =
          'x' * (EditorAnalysisController.maxSourceUnits + 1);
      await tester.pump(const Duration(milliseconds: 301));
      expect(provider.requests, isEmpty);
      expect(analysis.unavailableReason, contains('超出'));
      file.controller.text = 'small';
      await tester.pump(const Duration(milliseconds: 301));
      provider.results.single.complete(
        CodeAnalysisResult(
          diagnostics: [
            for (
              var i = 0;
              i < EditorAnalysisController.maxDiagnostics + 20;
              i++
            )
              CodeDiagnostic(
                filePath: file.path,
                startOffset: 0,
                endOffset: 1,
                message: 'problem $i',
              ),
          ],
        ),
      );
      await tester.pump();
      expect(
        analysis.problems,
        hasLength(EditorAnalysisController.maxDiagnostics),
      );
    },
  );

  testWidgets('disposing during analysis ignores the late provider response', (
    tester,
  ) async {
    final file = await open(tester, 'main.dart', 'bad');
    final provider = _Analyzer();
    final analysis = EditorAnalysisController(
      editor: editor,
      analyzer: provider,
    );
    var notifications = 0;
    analysis.addListener(() => notifications++);
    await tester.pump(const Duration(milliseconds: 301));
    analysis.dispose();
    final before = notifications;
    provider.results.single.complete(
      CodeAnalysisResult(
        diagnostics: [
          CodeDiagnostic(
            filePath: file.path,
            startOffset: 0,
            endOffset: 3,
            message: 'late',
          ),
        ],
      ),
    );
    await tester.pump(const Duration(seconds: 20));
    expect(notifications, before);
    expect(file.diagnostics!.problems, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final source in ['', 'first\r\n\r\nlast']) {
    testWidgets(
      'gutter paints insertion on empty source line: ${source.length}',
      (tester) async {
        final file = await open(tester, 'main.dart', source);
        final offset = source.isEmpty ? 0 : 7;
        file.diagnostics!.update(source, [
          CodeDiagnostic(
            filePath: file.path,
            startOffset: offset,
            endOffset: offset,
            message: 'insert',
          ),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CodeEditor(
                controller: file.controller,
                indicatorBuilder: (context, controller, chunks, notifier) =>
                    EditorDiagnosticGutter(
                      diagnostics: file.diagnostics!,
                      notifier: notifier,
                    ),
              ),
            ),
          ),
        );
        await tester.pump();
        final paintFinder = find.descendant(
          of: find.byType(EditorDiagnosticGutter),
          matching: find.byType(CustomPaint),
        );
        final painter = tester.widget<CustomPaint>(paintFinder).painter!;
        expect(tester.getSize(paintFinder).height, greaterThan(0));
        expect(
          (Canvas canvas) => painter.paint(canvas, const Size(10, 600)),
          paints..circle(),
        );
        expect(file.controller.text, source);
        expect(file.dirty, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'folded diagnostic navigation expands source lines before selecting',
    (tester) async {
      final file = await open(tester, 'main.dart', '{\nfirst\nbad\n}\n');
      final diagnostic = CodeDiagnostic(
        filePath: file.path,
        startOffset: 8,
        endOffset: 11,
        message: 'inside',
      );
      file.diagnostics!.update(file.controller.text, [diagnostic]);
      file.controller.collapseChunk(0, 3);
      expect(file.diagnostics!.gutterSeverity(0), CodeDiagnosticSeverity.error);
      expect(file.diagnostics!.navigate(diagnostic), isTrue);
      expect(file.controller.selection.baseIndex, 2);
      expect(file.controller.selection.baseOffset, 0);
      expect(file.controller.selection.extentOffset, 3);
      expect(file.controller.text, '{\nfirst\nbad\n}\n');
      expect(file.dirty, isFalse);
    },
  );

  testWidgets(
    'mounted editor can shrink CRLF lines while invalidating diagnostics',
    (tester) async {
      final file = await open(
        tester,
        'main.js',
        '// saved 😀\r\nconst saved = 1;\r\n',
      );
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
      );
      addTearDown(analysis.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CodeEditor(controller: file.controller)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 301));
      provider.results.single.complete(const CodeAnalysisResult());
      await tester.pump();
      await tester.pump();
      file.controller.text = '// 😀\r\nconst broken = ;';
      expect(analysis.problems, isEmpty);
      await tester.pump(const Duration(milliseconds: 301));
      provider.results.last.complete(
        CodeAnalysisResult(
          diagnostics: [
            CodeDiagnostic(
              filePath: file.path,
              startOffset: file.controller.text.length - 1,
              endOffset: file.controller.text.length,
              message: 'missing expression',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(analysis.problems.single.message, 'missing expression');
      expect(file.controller.codeLines.length, 2);
      expect(file.dirty, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Problems remains usable at 320px and 2x text with long messages',
    (tester) async {
      final file = await open(tester, 'main.dart', 'bad');
      final provider = _Analyzer();
      final analysis = EditorAnalysisController(
        editor: editor,
        analyzer: provider,
      );
      addTearDown(analysis.dispose);
      await tester.pump(const Duration(milliseconds: 301));
      provider.results.single.complete(
        CodeAnalysisResult(
          diagnostics: [
            CodeDiagnostic(
              filePath: file.path,
              startOffset: 0,
              endOffset: 3,
              message:
                  'Unknown method with a long descriptive compiler message',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  height: 220,
                  child: EditorProblemsPanel(
                    analysis: analysis,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('editor-problems-list')),
        findsOneWidget,
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(ListTile)) + const Offset(24, 20),
      );
      await tester.pump();
      expect(file.controller.selection.extentOffset, 3);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Analyzer implements CodeAnalyzer {
  final requests = <CodeAnalysisRequest>[];
  final results = <Completer<CodeAnalysisResult>>[];
  @override
  Future<CodeAnalysisResult> analyze(CodeAnalysisRequest request) {
    requests.add(request);
    final result = Completer<CodeAnalysisResult>();
    results.add(result);
    return result.future;
  }
}
