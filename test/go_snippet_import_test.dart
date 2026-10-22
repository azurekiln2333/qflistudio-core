import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/project_config.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/widgets/code_snippet.dart';

const _program = 'package main\nfunc main() {}\n';
const _test = '''
package main
import "testing"
func TestAdd(t *testing.T) { t.Log(1 + 1) }
''';
const _example = ExampleCode(
  id: 'go-filename',
  type: 'go',
  title: 'Go test example',
  summary: 'An editable Go source example.',
  code: _program,
  output: '',
);

void main() {
  group('source-aware Go defaults', () {
    final tests = <String, String>{
      'ordinary test': _test,
      'grouped import': '''
package main
import (
  "fmt"
  "testing"
)
func TestAdd(t *testing.T) { fmt.Println(1) }
''',
      'aliased import and comments': '''
package main
import check /* import alias */ "testing"
func /* declaration */ TestAdd(t /* parameter */ *check.T) {}
''',
      'dot import and unnamed parameter': '''
package main
import . "testing"
func TestAdd(*T) {}
''',
      'benchmark':
          'package main\nimport "testing"\n'
          'func BenchmarkAdd(b *testing.B) {}',
      'fuzz':
          'package main\nimport "testing"\n'
          'func FuzzAdd(f *testing.F) {}',
      'TestMain':
          'package main\nimport "testing"\n'
          'func TestMain(m *testing.M) {}',
      'trailing parameter comma':
          'package main\nimport "testing"\n'
          'func TestAdd(\n t *testing.T,\n) {}',
      'Unicode uppercase suffix':
          'package main\nimport "testing"\n'
          'func Test世界(t *testing.T) {}',
      'bare Test name':
          'package main\nimport "testing"\n'
          'func Test(t *testing.T) {}',
      'raw import path':
          'package main\nimport `testing`\n'
          'func TestAdd(t *testing.T) {}',
      'escaped import path':
          r'package main; import "tes\x74ing"; '
          'func TestAdd(t *testing.T) {}',
    };
    for (final entry in tests.entries) {
      test(entry.key, () {
        expect(
          CodeImportService.suggestedFileName('go', code: entry.value),
          'snippet_test.go',
        );
      });
    }

    final programs = <String, String>{
      'ordinary program': _program,
      'helper with lowercase suffix':
          'package main; import "testing"; '
          'func Testhelper(t *testing.T) {}',
      'Unicode lowercase suffix':
          'package main; import "testing"; '
          'func Testé(t *testing.T) {}',
      'missing import': 'package main; func TestAdd(t *testing.T) {}',
      'wrong import':
          'package main; import "example/testing"; '
          'func TestAdd(t *testing.T) {}',
      'blank import':
          'package main; import _ "testing"; '
          'func TestAdd(t *testing.T) {}',
      'wrong qualifier':
          'package main; import check "testing"; '
          'func TestAdd(t *testing.T) {}',
      'wrong parameter type':
          'package main; import "testing"; '
          'func TestAdd(b *testing.B) {}',
      'wrong benchmark type':
          'package main; import "testing"; '
          'func BenchmarkAdd(t *testing.T) {}',
      'extra parameter':
          'package main; import "testing"; '
          'func TestAdd(t *testing.T, n int) {}',
      'return value':
          'package main; import "testing"; '
          'func TestAdd(t *testing.T) int { return 1 }',
      'receiver method':
          'package main; import "testing"; '
          'func (suite Suite) TestAdd(t *testing.T) {}',
      'generic function':
          'package main; import "testing"; '
          'func TestAdd[V any](t *testing.T) {}',
      'line comment':
          'package main\nimport "testing"\n'
          '// func TestAdd(t *testing.T) {}\nfunc main() {}',
      'block comment':
          'package main; import "testing"; '
          '/* func TestAdd(t *testing.T) {} */ func main() {}',
      'commented import':
          'package main; /* import "testing" */ '
          'func TestAdd(t *testing.T) {}',
      'interpreted string': r'''package main; import "testing"
var text = "func TestAdd(t *testing.T) {\"quoted\"}"
func main() {}''',
      'raw string':
          'package main; import "testing"; '
          'var text = `func TestAdd(t *testing.T) {}`; func main() {}',
      'nested function literal':
          'package main; import "testing"; '
          'func main() { TestAdd := func(t *testing.T) {}; _ = TestAdd }',
      'unfinished literal':
          'package main; import "testing"; '
          'var text = `func TestAdd(t *testing.T) {}',
    };
    for (final entry in programs.entries) {
      test(entry.key, () {
        expect(
          CodeImportService.suggestedFileName('go', code: entry.value),
          'main.go',
        );
      });
    }

    test('missing source and other language defaults stay compatible', () {
      expect(CodeImportService.suggestedFileName('go'), 'main.go');
      expect(
        CodeImportService.suggestedFileName('GO', code: _test),
        'snippet_test.go',
      );
      expect(
        CodeImportService.suggestedFileName('dart', code: _test),
        'main.dart',
      );
      expect(
        CodeImportService.suggestedFileName('unknown', code: _test),
        'snippet.txt',
      );
    });
  });

  test('test import materializes the chosen name and exact source', () async {
    final root = await Directory.systemTemp.createTemp('qfli_go_import_');
    addTearDown(() => root.delete(recursive: true));
    for (final name in [
      CodeImportService.suggestedFileName('go', code: _test),
      'chosen_test.go',
      'explicit.go',
    ]) {
      final imported = await CodeImportService.openInEditor(
        example: _example.copyWith(code: _test),
        fileName: name,
        location: root.path,
      );
      expect(p.basename(imported.path), name);
      expect(await File(imported.path).readAsString(), _test);
      expect(
        File(p.join(imported.project.path, 'src', 'main.go')).existsSync(),
        isFalse,
      );
      expect(
        ProjectConfig.read(imported.project.path)?['entryFile'],
        p.join('src', name),
      );
    }
  });

  for (final intoProject in [false, true]) {
    testWidgets(
      '${intoProject ? 'project' : 'editor'} import dialog uses currently edited Go source',
      (tester) async {
        final store = ProjectStore();
        final auth = AuthStore();
        final settings = SettingsStore();
        final controller = TextEditingController(text: _test);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              StudioLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: StudioLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: CodeSnippet(
                  example: _example,
                  controller: controller,
                  store: store,
                  auth: auth,
                  settings: settings,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.byIcon(
          intoProject
              ? Icons.drive_file_move_outlined
              : Icons.edit_note_outlined,
        );
        await tester.tap(action);
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('import-file-name'));
        expect(
          tester.widget<TextFormField>(field).controller!.text,
          'snippet_test.go',
        );
        final context = tester.element(find.byType(AlertDialog));
        await tester.tap(find.text(StudioLocalizations.of(context).cancel));
        await tester.pumpAndSettle();
        controller.text = _program;
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(field).controller!.text, 'main.go');
        expect(controller.text, _program);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        store.dispose();
        auth.dispose();
        settings.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
