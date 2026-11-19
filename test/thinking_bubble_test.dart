import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/chat/thinking_bubble.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_widgets.dart';

/// 思考气泡（任务 11-19-agent-thinking-stream 的 R5、R7、R10、R15）。
void main() {
  Widget host(
    Widget child, {
    double textScale = 1,
    ThemeMode mode = ThemeMode.light,
  }) => MaterialApp(
    theme: ThemeData(brightness: Brightness.light),
    darkTheme: ThemeData(brightness: Brightness.dark),
    themeMode: mode,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: child),
    ),
  );

  AgentMessageView reasoning({
    String id = 'r0',
    String text = '先看看这个文件里有什么。',
    bool pending = true,
    int? durationMs,
  }) => AgentMessageView(
    id: id,
    role: 'reasoning',
    text: text,
    pending: pending,
    aiGenerated: true,
    durationMs: durationMs,
  );

  /// 只有标题行和 AI 标记，没有正文。
  void expectCollapsed(String id) {
    expect(find.byKey(ValueKey('thinking-title-$id')), findsOneWidget);
    expect(find.byKey(ValueKey('thinking-body-$id')), findsNothing);
    expect(find.byType(ChunkedText), findsNothing);
  }

  void expectExpanded(String id) {
    expect(find.byKey(ValueKey('thinking-body-$id')), findsOneWidget);
  }

  testWidgets('a streaming bubble is open and counts seconds', (tester) async {
    await tester.pumpWidget(host(ThinkingBubble(message: reasoning())));

    expectExpanded('r0');
    expect(find.text('思考中… 0 秒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('思考中… 1 秒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('思考中… 3 秒'), findsOneWidget);

    // 计时器随销毁停止，不留悬挂的定时器。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a finished bubble collapses and shows the final duration', (
    tester,
  ) async {
    await tester.pumpWidget(host(ThinkingBubble(message: reasoning())));
    expectExpanded('r0');

    await tester.pumpWidget(
      host(
        ThinkingBubble(message: reasoning(pending: false, durationMs: 18000)),
      ),
    );
    await tester.pump();

    expect(find.text('已思考 18 秒'), findsOneWidget);
    // 结束后自动收起，正文不进树（design §6.1）。
    expectCollapsed('r0');
  });

  testWidgets('a cancelled bubble says only that it thought', (tester) async {
    await tester.pumpWidget(
      host(ThinkingBubble(message: reasoning(pending: false))),
    );

    expect(find.text('已思考'), findsOneWidget);
    expectCollapsed('r0');
  });

  testWidgets('a user choice survives the end of the stream (prd AC7)', (
    tester,
  ) async {
    await tester.pumpWidget(host(ThinkingBubble(message: reasoning())));
    expectExpanded('r0');

    // 用户手动收起，流式结束后不自动展开。
    await tester.tap(find.byKey(const ValueKey('thinking-header-r0')));
    await tester.pump();
    expectCollapsed('r0');

    await tester.pumpWidget(
      host(
        ThinkingBubble(message: reasoning(pending: false, durationMs: 4000)),
      ),
    );
    await tester.pump();
    expectCollapsed('r0');

    // 用户手动展开后，后续重建不会把它收起。
    await tester.tap(find.byKey(const ValueKey('thinking-header-r0')));
    await tester.pump();
    expectExpanded('r0');

    await tester.pumpWidget(
      host(
        ThinkingBubble(message: reasoning(pending: false, durationMs: 5000)),
      ),
    );
    await tester.pump();
    expectExpanded('r0');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the transcript keeps a user expand after the stream ends', (
    tester,
  ) async {
    final notifier = ValueNotifier<String>('读文件，');
    addTearDown(notifier.dispose);
    List<AgentMessageView> messages({required bool pending, int? durationMs}) =>
        [
          AgentMessageView(
            id: 'r0',
            role: 'reasoning',
            text: pending ? '' : '读文件，然后改大小写。',
            pending: pending,
            aiGenerated: true,
            durationMs: durationMs,
          ),
        ];

    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: messages(pending: true),
          state: AgentRunState.running,
          liveTextOf: (id) => id == 'r0' ? notifier : null,
        ),
      ),
    );
    await tester.pump();
    expectExpanded('r0');

    // 用户手动展开一个结束的气泡后，后续增量不再把它收起（prd AC7）。
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: messages(pending: false, durationMs: 3000),
          state: AgentRunState.idle,
          liveTextOf: (id) => id == 'r0' ? notifier : null,
        ),
      ),
    );
    await tester.pump();
    expectCollapsed('r0');

    await tester.tap(find.byKey(const ValueKey('thinking-header-r0')));
    await tester.pump();
    expectExpanded('r0');

    notifier.value = '读文件，然后改大小写。';
    await tester.pump();
    expectExpanded('r0');
    // 结束后正文换成可选中的文本。
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('a restored bubble starts collapsed (prd AC3)', (tester) async {
    // 恢复的历史消息 pending 恒为 false，所以直接就是收起状态。
    await tester.pumpWidget(
      host(
        ChatTranscript(
          messages: [
            reasoning(
              id: 'r0',
              text: '恢复的思考内容',
              pending: false,
              durationMs: 12000,
            ),
          ],
          state: AgentRunState.idle,
        ),
      ),
    );
    await tester.pump();

    expectCollapsed('r0');
    expect(find.text('已思考 12 秒'), findsOneWidget);
    expect(find.textContaining('恢复的思考内容'), findsNothing);
  });

  testWidgets('the AI badge shows while collapsed (prd AC8)', (tester) async {
    await tester.pumpWidget(
      host(
        ThinkingBubble(message: reasoning(pending: false, durationMs: 2000)),
      ),
    );

    expectCollapsed('r0');
    expect(find.byType(AiGeneratedBadge), findsOneWidget);
    expect(find.text(kAiGeneratedLabel), findsOneWidget);
  });

  testWidgets('the whole header is a 44 pixel tap target', (tester) async {
    await tester.pumpWidget(host(ThinkingBubble(message: reasoning())));

    final header = find.byKey(const ValueKey('thinking-header-r0'));
    expect(tester.getSize(header).height, greaterThanOrEqualTo(44));

    // 点标题行即可切换，不必点箭头。
    await tester.tap(header);
    await tester.pump();
    expectCollapsed('r0');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('text scale 1.3 does not overflow', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 280,
          child: ThinkingBubble(
            message: reasoning(
              pending: false,
              durationMs: 65000,
              text: List.generate(12, (line) => '第 $line 行思考内容').join('\n'),
            ),
            expanded: true,
          ),
        ),
        textScale: 1.3,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('thinking-body-r0')), findsOneWidget);
  });

  testWidgets('the dark theme renders the bubble', (tester) async {
    await tester.pumpWidget(
      host(
        ThinkingBubble(
          message: reasoning(pending: false, durationMs: 3000),
          expanded: true,
        ),
        mode: ThemeMode.dark,
      ),
    );
    await tester.pump();

    expect(find.text('已思考 3 秒'), findsOneWidget);
    expect(find.byType(ChunkedText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a streaming bubble stops at 240 pixels and follows the tail', (
    tester,
  ) async {
    final notifier = ValueNotifier<String>(
      List.generate(80, (line) => '第 $line 行：思考内容会一直增长。').join('\n'),
    );
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 320,
          child: ThinkingBubble(
            message: reasoning(),
            liveText: notifier,
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pump();

    final body = tester.widget<ConstrainedBox>(
      find.byKey(const ValueKey('thinking-body-r0')),
    );
    expect(body.constraints.maxHeight, 240);

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('thinking-body-r0')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    await tester.pump();
    final before = position.pixels;

    notifier.value += '\n又多了几行。';
    await tester.pump();
    await tester.pump();

    expect(position.maxScrollExtent, greaterThan(0));
    // 没有往上看时贴着末尾。
    expect(position.pixels, greaterThan(before));
    expect(position.maxScrollExtent - position.pixels, lessThanOrEqualTo(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('scrolling up stops the automatic tail follow', (tester) async {
    final notifier = ValueNotifier<String>(
      List.generate(80, (line) => '第 $line 行：思考内容会一直增长。').join('\n'),
    );
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 320,
          child: ThinkingBubble(
            message: reasoning(),
            liveText: notifier,
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('thinking-body-r0')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));

    // 用户往上滚。
    position.jumpTo(0);
    await tester.pump();

    notifier.value += '\n用户看上面的内容时又多了几行。';
    await tester.pump();
    await tester.pump();

    expect(position.pixels, 0);

    // 滚回底部后恢复跟随。
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    notifier.value += '\n恢复跟随后又多了一行。';
    await tester.pump();
    await tester.pump();

    expect(position.maxScrollExtent - position.pixels, lessThanOrEqualTo(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('chunked text (prd R15)', () {
    /// 每块的目标长度。和组件默认值一致。
    const chunkSize = ChunkedText.defaultChunkSize;

    /// 大约 [size] 个字符的长文本，每行三十来个字符。
    String longText({int size = 300 * 1024, String tag = 'x'}) {
      final buffer = StringBuffer();
      var line = 0;
      while (buffer.length < size) {
        buffer.writeln('第 ${line.toString().padLeft(6, '0')} 行思考内容 $tag');
        line++;
      }
      return buffer.toString();
    }

    test('splits on newlines and keeps the joins lossless', () {
      final text = longText(size: chunkSize * 2);
      final chunks = <String>[];
      var start = 0;
      while (start < text.length) {
        final end = ChunkedText.debugBoundaryOf(text, start, chunkSize);
        chunks.add(text.substring(start, end));
        start = end;
      }

      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.join(), text);
      for (var index = 0; index < chunks.length; index++) {
        final chunk = chunks[index];
        expect(chunk.length, lessThanOrEqualTo(chunkSize * 2));
        // 最后一块是还没长满的尾巴。
        if (index < chunks.length - 1) {
          expect(chunk.length, greaterThanOrEqualTo(chunkSize - 1));
        }
      }
    });

    testWidgets('only the growing chunk rebuilds for 300 KB of text', (
      tester,
    ) async {
      final notifier = ValueNotifier<String>('');
      addTearDown(notifier.dispose);
      final text = longText(tag: '三百 KB 的压力样本');
      expect(text.length, greaterThan(300 * 1024));

      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            height: 300,
            child: SingleChildScrollView(
              child: ValueListenableBuilder<String>(
                valueListenable: notifier,
                builder: (context, value, _) =>
                    ChunkedText(text: value, keyPrefix: 'stress'),
              ),
            ),
          ),
        ),
      );

      /// 当前树里的块，按 key 索引。
      Map<ValueKey<String>, Widget> chunks() => {
        for (final element
            in find
                .descendant(
                  of: find.byType(ChunkedText),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Text && widget.key is ValueKey<String>,
                  ),
                )
                .evaluate())
          element.widget.key! as ValueKey<String>: element.widget,
      };

      // 分 30 段推入，每段约 10 KB。
      final step = (text.length / 30).ceil();
      var previous = <ValueKey<String>, Widget>{};
      for (var end = step; end < text.length + step; end += step) {
        final cut = end > text.length ? text.length : end;
        notifier.value = text.substring(0, cut);
        await tester.pump();
        final current = chunks();
        final keys = previous.keys.toList();
        // 除上一帧的最后一块外，其余块的 widget 实例原样复用，
        // 所以它们不会重新布局。
        for (final key in keys) {
          if (key == keys.last) continue;
          if (!current.containsKey(key)) continue;
          expect(
            identical(current[key], previous[key]),
            isTrue,
            reason: '$key',
          );
        }
        previous = current;
        if (cut == text.length) break;
      }

      expect(previous, isNotEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a collapsed bubble builds no body at all', (tester) async {
      await tester.pumpWidget(
        host(ThinkingBubble(message: reasoning(pending: false))),
      );

      expect(find.byType(ChunkedText), findsNothing);
      expect(find.textContaining('先看看这个文件里有什么。'), findsNothing);
      // 展开后才出现正文。
      await tester.tap(find.byKey(const ValueKey('thinking-header-r0')));
      await tester.pump();
      expect(find.byType(ChunkedText), findsOneWidget);
    });
  });
}
