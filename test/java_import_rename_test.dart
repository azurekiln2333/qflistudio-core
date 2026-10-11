import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/services/code_import_service.dart';
import 'package:qfli_studio_core/services/java_source_renamer.dart';

void main() {
  group('JavaSourceRenamer', () {
    test('analyzes entry class, package and main', () {
      const source = '''
package demo;

public class Runner {
    public static void main(String[] args) {
        System.out.println("hi");
    }
}
''';
      final info = JavaSourceRenamer.analyze(source);
      expect(info.className, 'Runner');
      expect(info.packageName, 'demo');
      expect(info.hasMain, isTrue);
    });

    test('renames declaration, constructor and self references', () {
      const source = '''
public class Main {
    int value;

    Main(int value) {
        this.value = value;
    }

    Main copy() {
        return new Main(value);
    }

    public static void main(String[] args) {
        Main m = new Main(1);
        System.out.println(m.value);
    }
}
''';
      final renamed = JavaSourceRenamer.renameEntryClass(
        source,
        oldName: 'Main',
        newName: 'Demo',
      );
      expect(renamed, contains('public class Demo {'));
      expect(renamed, contains('Demo(int value) {'));
      expect(renamed, contains('Demo copy() {'));
      expect(renamed, contains('return new Demo(value);'));
      expect(renamed, contains('Demo m = new Demo(1);'));
      expect(renamed, isNot(contains('Main')));
    });

    test('preserves comments, strings, chars and text blocks', () {
      const source = '''
// Main is described in this comment
public class Main {
    String label = "Main";
    char c = 'M';
    String block = """
        Main inside a text block stays
        """;

    public static void main(String[] args) {
        // keep the Main word in comments
        System.out.println(new Main().label);
    }
}
''';
      final renamed = JavaSourceRenamer.renameEntryClass(
        source,
        oldName: 'Main',
        newName: 'Demo',
      );
      expect(renamed, contains('public class Demo {'));
      expect(renamed, contains('new Demo().label'));
      // Literals and comments are untouched.
      expect(renamed, contains('// Main is described in this comment'));
      expect(renamed, contains('String label = "Main";'));
      expect(renamed, contains("char c = 'M';"));
      expect(renamed, contains('Main inside a text block stays'));
      expect(renamed, contains('// keep the Main word in comments'));
    });

    test('preserves package statement and indentation', () {
      const source = '''
package a.b;

class Main {
    void go() {
        int x = 1;
    }
}
''';
      final renamed = JavaSourceRenamer.renameEntryClass(
        source,
        oldName: 'Main',
        newName: 'Tool',
      );
      expect(renamed, startsWith('package a.b;\n'));
      expect(renamed, contains('class Tool {'));
      expect(renamed, contains('        int x = 1;'));
    });

    test('throws when the entry class is not declared', () {
      expect(
        () => JavaSourceRenamer.renameEntryClass(
          'class Other {}',
          oldName: 'Main',
          newName: 'Demo',
        ),
        throwsA(isA<JavaSourceRenameException>()),
      );
    });

    test('renames every code-position self reference, including types', () {
      const source = '''
class Main {
    Main self() {
        return this;
    }

    public static void main(String[] args) {
        System.out.println(Main.class.getSimpleName());
    }
}
''';
      final renamed = JavaSourceRenamer.renameEntryClass(
        source,
        oldName: 'Main',
        newName: 'Demo',
      );
      expect(renamed, contains('class Demo {'));
      expect(renamed, contains('Demo self() {'));
      expect(renamed, contains('Demo.class.getSimpleName()'));
    });

    test('rejects source that binds the class name as a value', () {
      const source = '''
class Main {
    public static void main(String[] args) {
        int Main = 3;
        System.out.println(Main + new Main().hashCode());
    }
}
''';
      expect(
        () => JavaSourceRenamer.renameEntryClass(
          source,
          oldName: 'Main',
          newName: 'Demo',
        ),
        throwsA(isA<JavaSourceRenameException>()),
      );
    });

    test('accepts legitimate self-type field and parameter uses', () {
      const source = '''
class Main {
    Main next;
    Main[] peers;
    Main combine(Main other) {
        this.next = other;
        return this;
    }
}
''';
      final renamed = JavaSourceRenamer.renameEntryClass(
        source,
        oldName: 'Main',
        newName: 'Demo',
      );
      expect(renamed, contains('Demo next;'));
      expect(renamed, contains('Demo[] peers;'));
      expect(renamed, contains('Demo combine(Demo other) {'));
    });

    test('renames self-type uses: arrays, generics, static, factory, ::new', () {
      const source = '''
import java.util.List;

public class Main {
    Main[] items;
    List<Main> list;

    static Main create() {
        return new Main();
    }

    static Main factory() {
        return create();
    }

    public static void main(String[] args) {
        Main[] arr = new Main[1];
        List<Main> l = List.of(Main.factory());
        java.util.function.Supplier<Main> s = Main::new;
        System.out.println(arr.length + l.size() + (Main.class != null ? 1 : 0) + (s != null ? 1 : 0));
    }
}
''';
      final renamed = JavaSourceRenamer.renameEntryClass(
        source,
        oldName: 'Main',
        newName: 'Demo',
      );
      expect(renamed, contains('public class Demo {'));
      expect(renamed, contains('Demo[] items;'));
      expect(renamed, contains('List<Demo> list;'));
      expect(renamed, contains('static Demo create()'));
      expect(renamed, contains('static Demo factory()'));
      expect(renamed, contains('Demo[] arr = new Demo[1];'));
      expect(renamed, contains('List<Demo> l = List.of(Demo.factory());'));
      expect(renamed, contains('Supplier<Demo> s = Demo::new;'));
      expect(renamed, contains('Demo.class != null'));
      expect(renamed, isNot(contains('Main')));
    });

    test('rejects a rename that collides with an existing type name', () {
      const source = '''
class Main {}
class Demo {}
''';
      expect(
        () => JavaSourceRenamer.renameEntryClass(
          source,
          oldName: 'Main',
          newName: 'Demo',
        ),
        throwsA(isA<JavaSourceRenameException>()),
      );
    });

    test('rejects a rename whose new name is used as another type', () {
      const source = '''
class Main {
    Demo helper = new Demo();
}
class Demo {}
''';
      expect(
        () => JavaSourceRenamer.renameEntryClass(
          source,
          oldName: 'Main',
          newName: 'Demo',
        ),
        throwsA(isA<JavaSourceRenameException>()),
      );
    });
  });

  group('class-name import rules', () {
    test('suggests the entry class name, not a file name', () {
      expect(
        CodeImportService.suggestedClassName('public class HelloWorld {}'),
        'HelloWorld',
      );
      expect(CodeImportService.suggestedClassName(''), 'Main');
      expect(
        CodeImportService.suggestedClassName('not java at all'),
        'Main',
      );
    });

    test('validates simple Java identifiers and rejects keywords/traversal', () {
      expect(CodeImportService.isValidClassName('Main'), isTrue);
      expect(CodeImportService.isValidClassName(r'_Demo$1'), isTrue);
      expect(CodeImportService.isValidClassName('class'), isFalse);
      expect(CodeImportService.isValidClassName('null'), isFalse);
      expect(CodeImportService.isValidClassName('a/b'), isFalse);
      expect(CodeImportService.isValidClassName(r'a\b'), isFalse);
      expect(CodeImportService.isValidClassName('..'), isFalse);
      expect(CodeImportService.isValidClassName('1Abc'), isFalse);
      expect(CodeImportService.isValidClassName(' Main'), isFalse);
    });

    test('normalizes pasted .java suffix and path', () {
      expect(CodeImportService.normalizeClassNameInput('Demo'), 'Demo');
      expect(CodeImportService.normalizeClassNameInput('Demo.java'), 'Demo');
      expect(
        CodeImportService.normalizeClassNameInput(r'C:\tmp\Demo.java'),
        'Demo',
      );
      expect(
        () => CodeImportService.normalizeClassNameInput('1Bad'),
        throwsA(isA<CodeImportException>()),
      );
      expect(
        () => CodeImportService.normalizeClassNameInput('class'),
        throwsA(isA<CodeImportException>()),
      );
    });

    test('resolveImport renames the class and returns <Class>.java', () {
      const example = _javaExample;
      final resolved = CodeImportService.resolveImport(example, 'Demo');
      expect(resolved.fileName, 'Demo.java');
      expect(resolved.code, contains('public class Demo {'));
      expect(resolved.code, contains('Demo m = new Demo(1);'));
      expect(resolved.code, contains('String tag = "Main";'));
    });

    test('resolveImport tolerates a pasted .java suffix', () {
      final resolved = CodeImportService.resolveImport(_javaExample, 'Demo.java');
      expect(resolved.fileName, 'Demo.java');
    });
  });

  group('ASCII demo directory naming', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('qfli_ascii_'));
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('directory basename is ASCII demo_* and unique', () {
      final first = AppPaths.createAsciiDemoProjectDirectory(
        location: root.path,
        type: 'java',
        language: 'Java',
      );
      final second = AppPaths.createAsciiDemoProjectDirectory(
        location: root.path,
        type: 'java',
        language: 'Java',
      );
      expect(first.path, isNot(second.path));
      for (final dir in [first, second]) {
        final base = p.basename(dir.path);
        expect(base, startsWith('demo_'));
        expect(RegExp(r'^[A-Za-z0-9_]+$').hasMatch(base), isTrue);
        expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(base), isFalse);
      }
    });
  });
}

const _javaExample = ExampleCode(
  id: 'java-example-x',
  type: 'java',
  title: '中文教程标题',
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
