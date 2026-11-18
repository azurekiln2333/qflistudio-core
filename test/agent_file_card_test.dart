@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

/// Agent 写入的文件在对话流里是一张可点的卡片；已删除的文件只显示禁用的卡片。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AgentMessageView toolMessage(List<String> changedPaths) => AgentMessageView(
    id: 'tool-1',
    role: 'tool',
    text: '已写入 src/main.dart',
    toolName: 'write_file',
    changedPaths: changedPaths,
  );

  Future<void> mount(
    WidgetTester tester, {
    required AgentMessageView message,
    required void Function(String path)? onOpenFile,
    required bool Function(String path)? fileExists,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatTranscript(
            messages: [message],
            state: AgentRunState.idle,
            onOpenFile: onOpenFile,
            fileExists: fileExists,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('点卡片把路径交给调用方打开', (tester) async {
    final opened = <String>[];
    await mount(
      tester,
      message: toolMessage(['src/main.dart']),
      onOpenFile: opened.add,
      fileExists: (_) => true,
    );

    final card = find.byKey(const ValueKey('chat-file-card-src/main.dart'));
    expect(card, findsOneWidget);
    expect(find.text('src/main.dart'), findsOneWidget);
    expect(find.text('已删除'), findsNothing);

    await tester.tap(card);
    await tester.pump();

    expect(opened, ['src/main.dart'], reason: '一次点击只打开那一个文件');
  });

  testWidgets('已删除的文件显示禁用的卡片', (tester) async {
    final opened = <String>[];
    await mount(
      tester,
      message: toolMessage(['src/gone.dart']),
      onOpenFile: opened.add,
      fileExists: (_) => false,
    );

    final card = find.byKey(const ValueKey('chat-file-card-src/gone.dart'));
    expect(card, findsOneWidget);
    expect(find.text('已删除'), findsOneWidget);

    await tester.tap(card);
    await tester.pump();

    expect(opened, isEmpty, reason: '已删除的文件不得打开');
  });

  testWidgets('没有回调时卡片只显示路径，不可点', (tester) async {
    await mount(
      tester,
      message: toolMessage(['a.txt']),
      onOpenFile: null,
      fileExists: (_) => true,
    );

    final inkWell = tester.widget<InkWell>(
      find.byKey(const ValueKey('chat-file-card-a.txt')),
    );
    expect(inkWell.onTap, isNull);
  });
}