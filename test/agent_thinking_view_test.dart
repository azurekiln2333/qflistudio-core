import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

void main() {
  test('思考条目带用时往返', () {
    const view = AgentMessageView(
      id: 'm1',
      role: 'reasoning',
      text: '想了很久',
      pending: false,
      aiGenerated: true,
      durationMs: 18000,
    );

    final json = view.toJson();
    expect(json['role'], 'reasoning');
    expect(json['durationMs'], 18000);

    final restored = AgentMessageView.fromJson(json);
    expect(restored, isNotNull);
    expect(restored!.role, 'reasoning');
    expect(restored.text, '想了很久');
    expect(restored.durationMs, 18000);
    expect(restored.aiGenerated, isTrue);
    // 恢复的消息一律不 pending（prd R10）。
    expect(restored.pending, isFalse);
  });

  test('没有 durationMs 的旧数据照常读取', () {
    final restored = AgentMessageView.fromJson({
      'id': 'm1',
      'role': 'assistant',
      'text': '旧消息',
      'aiGenerated': true,
    });

    expect(restored, isNotNull);
    expect(restored!.role, 'assistant');
    expect(restored.text, '旧消息');
    expect(restored.durationMs, isNull);
  });

  test('取消的思考条目没有用时也能往返', () {
    const view = AgentMessageView(
      id: 'm2',
      role: 'reasoning',
      text: '想到一半',
      aiGenerated: true,
    );

    final json = view.toJson();
    expect(json.containsKey('durationMs'), isFalse);

    final restored = AgentMessageView.fromJson(json);
    expect(restored, isNotNull);
    expect(restored!.durationMs, isNull);
    expect(restored.text, '想到一半');
  });
}
