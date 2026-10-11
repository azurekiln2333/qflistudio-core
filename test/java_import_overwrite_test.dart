import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';

/// P1: existing-project import must resolve the class input to the actual
/// `<Class>.java` target once, so the overwrite pre-check and the write agree.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('qfli_overwrite_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Project project() => Project.create(
    name: '中文示例项目',
    path: root.path,
    type: 'java',
    language: 'Java',
  );

  test('destinationPath resolves the bare class input to <Class>.java', () {
    final target = CodeImportService.destinationPath(
      project: project(),
      example: _example,
      fileName: 'Demo.java',
    );
    expect(p.basename(target), 'Demo.java');
  });

  test('rejects import when the resolved file already exists', () async {
    final existing = File(p.join(root.path, 'src', 'Demo.java'))
      ..createSync(recursive: true)
      ..writeAsStringSync('class Demo {}');
    await expectLater(
      CodeImportService.importIntoProject(
        project: project(),
        example: _example,
        fileName: 'Demo',
      ),
      throwsA(
        isA<CodeImportException>().having(
          (e) => e.reason,
          'reason',
          CodeImportFailure.fileExists,
        ),
      ),
    );
    expect(await existing.readAsString(), 'class Demo {}');
  });

  test('accepted replacement writes the renamed class and keeps content', () async {
    final existing = File(p.join(root.path, 'src', 'Demo.java'))
      ..createSync(recursive: true)
      ..writeAsStringSync('class Demo { /* old */ }');
    final result = await CodeImportService.importIntoProject(
      project: project(),
      example: _example,
      fileName: 'Demo',
      overwrite: true,
    );
    expect(p.basename(result.path), 'Demo.java');
    final written = await File(result.path).readAsString();
    expect(written, contains('public class Demo {'));
    expect(written, contains('Demo m = new Demo(1);'));
    expect(written, contains('String tag = "Main";'));
    expect(existing.existsSync(), isTrue);
  });

  test('uninterpretable Java source fails clearly instead of renaming stale code', () {
    const broken = ExampleCode(
      id: 'bad',
      type: 'java',
      title: 'bad',
      summary: '',
      code: '// no class declaration here\nint x = 1;',
      output: '',
    );
    expect(
      () => CodeImportService.resolveImport(broken, 'Demo'),
      throwsA(isA<CodeImportException>()),
    );
  });
}

const _example = ExampleCode(
  id: 'java-example-import',
  type: 'java',
  title: '中文示例标题',
  summary: '',
  code: '''
public class Main {
    int value;

    Main(int value) {
        this.value = value;
    }

    public static void main(String[] args) {
        Main m = new Main(1);
        String tag = "Main";
        System.out.println(m.value + tag);
    }
}
''',
  output: '1Main',
);
