import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

void main() {
  test('sourceText and attachedPaths survive a round trip', () {
    const view = AgentMessageView(
      id: 'm1',
      role: 'user',
      text: '看下 @lib/a.dart 这里',
      sourceText: '看下这里',
      attachedPaths: ['lib/a.dart', 'lib/b.dart'],
    );

    final restored = AgentMessageView.fromJson(view.toJson())!;

    expect(restored.text, '看下 @lib/a.dart 这里');
    expect(restored.sourceText, '看下这里');
    expect(restored.attachedPaths, ['lib/a.dart', 'lib/b.dart']);
  });

  test('an old record without the new fields loads with empty defaults', () {
    // 旧会话文件没有这两个字段：不能因为读不到就报错，也不能从 text 反推。
    final restored = AgentMessageView.fromJson({
      'id': 'm1',
      'role': 'user',
      'text': '看下 @lib/a.dart 这里',
      'isError': false,
      'pending': false,
      'aiGenerated': false,
    })!;

    expect(restored.sourceText, isNull);
    expect(restored.attachedPaths, isEmpty);
  });

  test('an explicit empty source survives an attachment-only round trip', () {
    const view = AgentMessageView(
      id: 'm1',
      role: 'user',
      text: 'Attached files: notes.txt',
      sourceText: '',
      attachedPaths: ['notes.txt'],
    );

    final restored = AgentMessageView.fromJson(view.toJson())!;
    expect(restored.sourceText, '');
    expect(restored.attachedPaths, ['notes.txt']);
  });

  test('empty lists are not persisted', () {
    const view = AgentMessageView(id: 'm1', role: 'assistant', text: '好的');
    final json = view.toJson();

    expect(json.containsKey('sourceText'), isFalse);
    expect(json.containsKey('attachedPaths'), isFalse);
  });

  test('non-string attachment entries are dropped', () {
    final restored = AgentMessageView.fromJson({
      'id': 'm1',
      'role': 'user',
      'text': '甲',
      'attachedPaths': ['lib/a.dart', 42, '', 'lib/b.dart'],
    })!;

    expect(restored.attachedPaths, ['lib/a.dart', 'lib/b.dart']);
  });
}
