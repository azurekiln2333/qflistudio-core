import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/chat_transcript.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

void main() {
  List<AgentMessageView> page(int start, int end) => [
    for (var i = start; i < end; i++)
      AgentMessageView(
        id: 'm$i',
        role: 'assistant',
        text: List.generate(
          1 + i % 9,
          (line) => 'Message $i, line $line',
        ).join('\n'),
      ),
  ];

  Widget host(List<AgentMessageView> messages, {String session = 'a'}) =>
      MaterialApp(
        home: Scaffold(
          body: ChatTranscript(
            sessionKey: session,
            messages: messages,
            state: AgentRunState.idle,
            hasEarlier: true,
          ),
        ),
      );

  ScrollPosition position(WidgetTester tester) => tester
      .widget<CustomScrollView>(find.byType(CustomScrollView))
      .controller!
      .position;

  Finder visibleMessage(WidgetTester tester) {
    for (final element in find.byType(ChatMessageTile).evaluate()) {
      final tile = find.byWidget(element.widget);
      final y = tester.getTopLeft(tile).dy;
      if (y >= 0 && y < 500) return tile;
    }
    throw StateError('No message in the viewport');
  }

  testWidgets(
    'prepending variable-height pages preserves the visible message',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var messages = page(40, 100);
      await tester.pumpWidget(host(messages));
      await tester.pumpAndSettle();
      position(tester).jumpTo(120);
      await tester.pumpAndSettle();
      final original = tester.widget<ChatMessageTile>(visibleMessage(tester));
      final originalFinder = find.byKey(original.key!);
      final originalY = tester.getTopLeft(originalFinder).dy;

      messages = [...page(10, 40), ...messages];
      await tester.pumpWidget(host(messages));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(originalFinder).dy, closeTo(originalY, 1));

      position(tester).jumpTo(-900);
      await tester.pumpAndSettle();
      final earlier = tester.widget<ChatMessageTile>(visibleMessage(tester));
      final earlierFinder = find.byKey(earlier.key!);
      final earlierY = tester.getTopLeft(earlierFinder).dy;
      messages = [...page(0, 10), ...messages];
      await tester.pumpWidget(host(messages));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(earlierFinder).dy, closeTo(earlierY, 1));

      messages = [...messages, ...page(100, 103)];
      await tester.pumpWidget(host(messages));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(earlierFinder).dy, closeTo(earlierY, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening variable-height history reaches the latest message', (
    tester,
  ) async {
    await tester.pumpWidget(host(page(0, 100)));
    await tester.pumpAndSettle();
    final latest = find.byKey(const ValueKey('chat-message-m99'));
    expect(latest, findsOneWidget);
    expect(tester.getTopLeft(latest).dy, lessThan(600));
    expect(position(tester).extentAfter, lessThan(1));
  });
}
