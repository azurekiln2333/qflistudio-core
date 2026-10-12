import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/models/tutorial.dart';
import 'package:qfli_studio_core/services/example_code_store.dart';

/// Structural/quality checks for the authored Python curriculum and the
/// emitted aggregate assets. This test does NOT run the code (that is the
/// job of `tool/verify_python_content.dart` against the real embedded runtime);
/// it guards counts, identity, pairing, non-triviality and line breaks.
void main() {
  final core = Directory.current;
  final tutorialsFile =
      File('${core.path}/assets/content/tutorials.json');
  final examplesFile = File('${core.path}/assets/content/examples.json');

  List<Map<String, Object?>> entries(File f, String language) {
    final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return (doc['entries'] as List)
        .cast<Map<String, dynamic>>()
        .where((e) => e['language'] == language)
        .map((e) => e.cast<String, Object?>())
        .toList();
  }

  group('Python 聚合内容', () {
    test('Python 教程与示例各 120 条', () {
      expect(entries(tutorialsFile, 'python'), hasLength(120));
      expect(entries(examplesFile, 'python'), hasLength(120));
    });

    test('id 唯一且 1..120 连续，示例与教程一一配对', () {
      final tutorials = entries(tutorialsFile, 'python');
      final examples = entries(examplesFile, 'python');

      final tutorialIds = tutorials.map((e) => e['id'] as String).toList();
      final exampleIds = examples.map((e) => e['id'] as String).toList();
      expect(tutorialIds.toSet(), hasLength(tutorialIds.length));
      expect(exampleIds.toSet(), hasLength(exampleIds.length));

      for (final ex in examples) {
        final source = ex['sourceLessonId'] as String?;
        expect(source, isNotNull, reason: '${ex['id']} 缺少 sourceLessonId');
        final expectedLesson = '${(ex['id'] as String).replaceFirst('example', 'tutorial')}-lesson';
        expect(source, expectedLesson, reason: '${ex['id']} 配对错误');
      }
    });

    test('标题唯一，代码体不重复，且非单行占位', () {
      final tutorials = entries(tutorialsFile, 'python');
      final titles = <String>{};
      final codes = <String>{};
      for (final t in tutorials) {
        final title = t['title'] as String;
        expect(titles.add(title), isTrue, reason: '重复标题：$title');

        final lessons = (t['lessons'] as List).cast<Map>();
        expect(lessons, hasLength(1), reason: '$title 必须恰好一课');
        final code = lessons.single['code'] as String;
        expect(code.split('\n').length, greaterThan(1),
            reason: '$title 的代码不是多行');
        expect(code.contains('weighted='), isFalse,
            reason: '$title 疑似旧占位内容');
        expect(codes.add(code), isTrue, reason: '$title 的代码体重复');
      }
    });

    test('每课含目标/前置/讲解/代码/输出/误区/练习，且练习答案非空', () {
      for (final t in entries(tutorialsFile, 'python')) {
        final lesson = (t['lessons'] as List).cast<Map>().single;
        final where = t['id'] as String;
        for (final field in [
          'objective',
          'explain',
          'code',
          'output',
        ]) {
          expect((lesson[field] as String).trim(), isNotEmpty,
              reason: '$where 缺 $field');
        }
        expect((lesson['prerequisites'] as List).isNotEmpty, isTrue,
            reason: '$where 缺前置（至少给一个或显式说明）');
        expect((lesson['pitfalls'] as List).isNotEmpty, isTrue,
            reason: '$where 缺常见误区');
        final exercises = (lesson['exercises'] as List).cast<Map>();
        expect(exercises, isNotEmpty, reason: '$where 缺练习');
        for (final e in exercises) {
          expect((e['prompt'] as String).trim(), isNotEmpty);
          expect((e['hint'] as String).trim(), isNotEmpty);
          expect((e['answer'] as String).trim(), isNotEmpty,
              reason: '$where 有练习但答案为空');
        }
      }
    });

    test('示例 code/output 与对应教程一致，运行时标记存在', () {
      final tutorials = {
        for (final t in entries(tutorialsFile, 'python')) t['id'] as String: t,
      };
      for (final ex in entries(examplesFile, 'python')) {
        final lesson = (tutorials[ex['sourceLessonId']!
                .toString()
                .replaceFirst('-lesson', '')]!['lessons'] as List)
            .cast<Map>()
            .single;
        expect(ex['code'], lesson['code'], reason: '${ex['id']} code 不一致');
        expect(ex['expectedOutput'], lesson['output'],
            reason: '${ex['id']} output 不一致');
        final concepts = (ex['concepts'] as List).cast<String>();
        expect(
          concepts.any((c) => c == '内置运行' || c == '需要外部 CPython 环境'),
          isTrue,
          reason: '${ex['id']} 缺少运行时标记',
        );
      }
    });

    test('代码保留真实换行', () {
      for (final t in entries(tutorialsFile, 'python')) {
        final lesson = (t['lessons'] as List).cast<Map>().single;
        expect((lesson['code'] as String).contains('\n'), isTrue);
      }
    });
  });

  // AC4 / R9: the refresh is provenance-safe. `ExampleCodeStore` has no
  // per-record built-in flag, so the design is refresh-only: re-seed defaults
  // and NEVER delete a persisted record by type. These tests prove user-created
  // Python records and other-language records survive, and reload is a no-op.
  group('Python 内容刷新（保留用户数据）', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('qfli_python_refresh_');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    ExampleCode py(String id, {String code = 'old'}) => ExampleCode(
      id: id,
      type: 'python',
      title: '自定义 $id',
      summary: '用户保存的记录',
      code: code,
      output: '',
    );

    ExampleCode dart(String id) => ExampleCode(
      id: id,
      type: 'dart',
      title: 'Dart $id',
      summary: 'unrelated',
      code: 'void main() {}',
      output: '',
    );

    Map<String, Object?> json(ExampleCode e) => <String, Object?>{
      'id': e.id,
      'type': e.type,
      'title': e.title,
      'summary': e.summary,
      'code': e.code,
      'output': e.output,
    };

    test('用户自建 Python 记录与其他语言记录都保留，旧内置不再作为默认', () async {
      final file = File(p.join(dir.path, 'examples.json'))
        ..writeAsStringSync(
          jsonEncode(<String, Object>{
            'schemaVersion': 1,
            // 旧版本，故意低于 contentVersion，模拟升级前的持久化文档。
            'contentVersion': 0,
            'examples': [
              // 用户自建的 Python 记录（必须保留）。
              json(py('my-own-python-snippet')),
              // 其他语言的用户记录（必须保留）。
              json(dart('dart-custom')),
            ],
          }),
        );

      final store = ExampleCodeStore(storageFile: file);
      addTearDown(store.dispose);

      // 新的内置默认集（只有新版 Python 内置），模拟随包刷新。
      await store.load(
        defaults: [
          py('python-example-001', code: 'print("new builtin")'),
          py('python-example-002', code: 'print("new builtin 2")'),
          dart('dart-default'),
        ],
      );

      // 用户自建记录仍在（不会被按 type==python 误删）。
      expect(store.items.any((e) => e.id == 'my-own-python-snippet'), isTrue,
          reason: '用户自建 Python 记录被删除，违反 R9');
      // 其他语言记录仍在。
      expect(store.items.any((e) => e.id == 'dart-custom'), isTrue);
      // 新的内置默认出现在列表中。
      expect(store.items.any((e) => e.id == 'python-example-002'), isTrue);

      // 持久化文件里用户记录仍在。
      final persisted =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final ids = (persisted['examples'] as List)
          .map((e) => (e as Map)['id'])
          .toSet();
      expect(ids, contains('my-own-python-snippet'));
      expect(ids, contains('dart-custom'));
    });

    test('用户对内置 id 的覆盖仍然胜出（用户数据优先）', () async {
      final file = File(p.join(dir.path, 'examples.json'))
        ..writeAsStringSync(
          jsonEncode(<String, Object>{
            'schemaVersion': 1,
            'contentVersion': 0,
            'examples': [
              json(py('python-example-001', code: '# user edited')) ,
            ],
          }),
        );
      final store = ExampleCodeStore(storageFile: file);
      addTearDown(store.dispose);
      await store.load(
        defaults: [py('python-example-001', code: 'print("new builtin")')],
      );
      final shown = store.items.firstWhere((e) => e.id == 'python-example-001');
      expect(shown.code, '# user edited',
          reason: '用户覆盖应优先于内置默认');
    });

    test('重复加载是 no-op（不会反复改写持久化文件）', () async {
      final file = File(p.join(dir.path, 'examples.json'))
        ..writeAsStringSync(
          jsonEncode(<String, Object>{
            'schemaVersion': 1,
            'contentVersion': 0,
            'examples': [json(py('my-own-python-snippet'))],
          }),
        );
      final store = ExampleCodeStore(storageFile: file);
      addTearDown(store.dispose);
      await store.load(defaults: [py('python-example-001')]);
      final first = file.readAsStringSync();
      final second = ExampleCodeStore(storageFile: file);
      addTearDown(second.dispose);
      await second.load(defaults: [py('python-example-001')]);
      expect(file.readAsStringSync(), first);
    });
  });
}
