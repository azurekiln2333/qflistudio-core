import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  AgentMessageView message({
    required String id,
    required String role,
    String text = '',
    String? toolName,
    bool isError = false,
    bool pending = false,
    List<String> changedPaths = const [],
  }) => AgentMessageView(
    id: id,
    role: role,
    text: text,
    toolName: toolName,
    isError: isError,
    pending: pending,
    changedPaths: changedPaths,
  );

  testWidgets('the empty state explains what to do next', (tester) async {
    await tester.pumpWidget(
      host(
        const ChatTranscript(
          messages: [],
          state: AgentRunState.idle,
          emptyTitle: '开始一个新的会话',
          emptyHint: '描述你想改什么。',
        ),
      ),
    );

    expect(find.text('开始一个新的会话'), findsOneWidget);
    expect(find.text('描述你想改什么。'), findsOneWidget);
  });

  testWidgets('user, assistant and tool entries all render', (tester) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [
            message(id: 'm0', role: 'user', text: '把输出改成大写'),
            message(id: 'm1', role: 'assistant', text: '先读一下文件。'),
            message(
              id: 'm2',
              role: 'tool',
              text: '12 行',
              toolName: 'read_file',
              changedPaths: ['src/Main.java'],
            ),
          ],
          state: AgentRunState.idle,
        ),
      ),
    );

    expect(find.text('把输出改成大写'), findsOneWidget);
    expect(find.text('先读一下文件。'), findsOneWidget);
    expect(find.text('读取文件'), findsOneWidget);
    expect(find.text('src/Main.java'), findsOneWidget);
  });

  testWidgets('a pending tool entry shows it is still running', (tester) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [
            message(
              id: 'm0',
              role: 'tool',
              toolName: 'run_command',
              pending: true,
            ),
          ],
          state: AgentRunState.running,
        ),
      ),
    );

    expect(find.text('执行中'), findsOneWidget);
  });

  testWidgets('the approval card allows a write', (tester) async {
    final decisions = <bool>[];
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'assistant', text: '准备写入')],
          state: AgentRunState.awaitingApproval,
          pendingApproval: const AgentWriteApproval(
            path: 'src/Main.java',
            summary: '新增 3 行',
          ),
          onApproval: decisions.add,
        ),
      ),
    );

    expect(find.text('需要确认写入'), findsOneWidget);
    expect(find.text('src/Main.java'), findsOneWidget);
    expect(find.text('新增 3 行'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('approval-allow')));
    await tester.pump();

    expect(decisions, [true]);
  });

  testWidgets('the approval card can refuse a write', (tester) async {
    final decisions = <bool>[];
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'assistant', text: '准备写入')],
          state: AgentRunState.awaitingApproval,
          pendingApproval: const AgentWriteApproval(
            path: 'src/Util.java',
            summary: '整体覆盖',
          ),
          onApproval: decisions.add,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('approval-deny')));
    await tester.pump();

    expect(decisions, [false]);
  });

  testWidgets('a failed run offers a retry next to the reason', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'user', text: '跑一下')],
          state: AgentRunState.failed,
          lastError: '网络请求失败，请检查连接后重试',
          onRetry: () => retried++,
        ),
      ),
    );

    expect(find.text('网络请求失败，请检查连接后重试'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-retry')));
    await tester.pump();

    expect(retried, 1);
  });

  testWidgets('no retry is offered while the run is still going', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [message(id: 'm0', role: 'user', text: '跑一下')],
          state: AgentRunState.running,
          lastError: '上一轮的旧错误',
          onRetry: () {},
        ),
      ),
    );

    expect(find.text('上一轮的旧错误'), findsNothing);
    expect(find.byKey(const ValueKey('chat-retry')), findsNothing);
  });

  testWidgets('a tool failure is marked as failed', (tester) async {
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [
            message(
              id: 'm0',
              role: 'tool',
              text: '路径超出项目目录',
              toolName: 'write_file',
              isError: true,
            ),
          ],
          state: AgentRunState.idle,
        ),
      ),
    );

    expect(find.text('失败'), findsOneWidget);
    expect(find.text('路径超出项目目录'), findsOneWidget);
  });
}
