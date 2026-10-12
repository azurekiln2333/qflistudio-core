import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/content/asset_content_repository.dart';
import 'package:qfli_studio_core/content/local_content_adapter.dart';
import 'package:qfli_studio_core/services/tutorial_service.dart';

/// Smoke tests proving the two offline page entry points really render the
/// authored Python curriculum (tutorials via the aggregate catalog, examples
/// via the editable example list), and that the legacy bundle is consistent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('教程页数据源：聚合教程渲染出 120 课', () async {
    final tutorial = await LocalContentAdapter.loadTutorial(
      repository: AssetContentRepository(),
      language: 'python',
      displayName: 'Python',
      productKey: 'pyflow',
    );
    expect(tutorial, isNotNull);
    expect(tutorial!.lessonCount, 120);
    expect(tutorial.chapters, isNotEmpty);
    for (final lesson in tutorial.allLessons) {
      expect(lesson.explain.trim(), isNotEmpty);
      expect(lesson.code.trim(), isNotEmpty);
      expect(lesson.output.trim(), isNotEmpty);
      expect(lesson.tasks, isNotEmpty);
    }
  });

  test('示例页数据源：聚合示例渲染出 120 条', () async {
    final examples = await LocalContentAdapter.loadExamples(
      repository: AssetContentRepository(),
      language: 'python',
      productKey: 'pyflow',
    );
    expect(examples, hasLength(120));
    for (final e in examples) {
      expect(e.code.trim(), isNotEmpty);
      expect(e.output.trim(), isNotEmpty);
      expect(e.sourceLessonId, isNotNull);
    }
  });

  test('legacy python 教程与聚合一致（120 课、运行时可用）', () async {
    TutorialService.clearCache();
    final t = await TutorialService.load('python');
    expect(t, isNotNull);
    expect(t!.lessonCount, 120);
    expect(t.examples, hasLength(120));
    expect(t.runtime.status, 'available');
    expect(t.isRunnable, isTrue);
  });
}
