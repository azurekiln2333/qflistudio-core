import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/attachment_picker.dart';
import 'package:qfli_studio_core/chat/composer_card.dart';
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

void main() {
  late ComposerState state;

  setUp(() => state = ComposerState());
  tearDown(() => state.dispose());

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  );

  testWidgets('the tool row carries plus, permission, model and reasoning', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          onPickAttachments: (_) async => null,
          models: const [
            AgentModelOption(
              id: 'model-a',
              label: 'Model A',
              reasoningEfforts: ['low', 'high'],
            ),
          ],
          skills: const [AgentSkillRef(name: 'style', description: '写法')],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('composer-input')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-plus')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-permission')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-model')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-reasoning')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-stop')), findsNothing);
  });

  testWidgets('the reasoning selector hides when the model has no efforts', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          models: const [AgentModelOption(id: 'plain', label: 'Plain')],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('composer-model')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-reasoning')), findsNothing);
  });

  testWidgets('running replaces send with stop in the same slot', (
    tester,
  ) async {
    var stopped = 0;
    final widget = ComposerCard(
      state: state,
      onSend: (text, attachments) async => true,
      onStop: () => stopped++,
    );

    await tester.pumpWidget(host(widget));
    final idleSlot = tester.getRect(
      find.byKey(const ValueKey('composer-send')),
    );
    expect(find.byKey(const ValueKey('composer-stop')), findsNothing);

    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          onStop: () => stopped++,
          running: true,
        ),
      ),
    );

    final stopFinder = find.byKey(const ValueKey('composer-stop'));
    expect(stopFinder, findsOneWidget);
    expect(find.byKey(const ValueKey('composer-send')), findsNothing);
    expect(tester.getRect(stopFinder), idleSlot);

    await tester.tap(stopFinder);
    await tester.pump();
    expect(stopped, 1);
  });

  testWidgets('sending passes text, attachments and the permission mode', (
    tester,
  ) async {
    String? sentText;
    List<String>? sentAttachments;
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async {
            sentText = text;
            sentAttachments = attachments;
            return true;
          },
          models: const [
            AgentModelOption(
              id: 'model-a',
              label: 'Model A',
              reasoningEfforts: ['high'],
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('composer-permission')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只读').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model A').last);
    await tester.pumpAndSettle();

    state.attach('src/Main.java');
    await tester.enterText(
      find.byKey(const ValueKey('composer-input')),
      '把输出改成大写',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();

    expect(sentText, '把输出改成大写');
    expect(sentAttachments, ['src/Main.java']);
    expect(state.permission, AgentPermissionMode.readOnly);
    expect(state.modelId, 'model-a');
    // 发送成功后输入被清空。
    expect(state.text, isEmpty);
    expect(state.attachments, isEmpty);
  });

  testWidgets('a refused send keeps the text for a retry', (tester) async {
    await tester.pumpWidget(
      host(
        ComposerCard(state: state, onSend: (text, attachments) async => false),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('composer-input')),
      '保留这一条',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pumpAndSettle();

    expect(state.text, '保留这一条');
  });

  testWidgets('attachments show as removable chips', (tester) async {
    state.attachAll(['src/Main.java', 'src/Util.java']);
    await tester.pumpWidget(
      host(ComposerCard(state: state, onSend: (text, list) async => true)),
    );

    expect(
      find.byKey(const ValueKey('composer-attachment-src/Main.java')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composer-attachment-src/Util.java')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('composer-attachment-src/Main.java')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(state.attachments, ['src/Util.java']);
  });

  testWidgets('an absolute attachment shows its tail, not the whole path', (
    tester,
  ) async {
    state.attachAll(['D:/work/other/src/Util.java']);
    await tester.pumpWidget(
      host(ComposerCard(state: state, onSend: (text, list) async => true)),
    );

    // 绝对路径只显示最后两段，完整路径在 tooltip 里。
    expect(find.text('src/Util.java'), findsOneWidget);
    expect(find.text('D:/work/other/src/Util.java'), findsNothing);
    expect(find.byTooltip('D:/work/other/src/Util.java'), findsOneWidget);
  });

  testWidgets('typing a slash lists skills and inserts the chosen one', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          skills: const [
            AgentSkillRef(name: 'style', description: '统一写法'),
            AgentSkillRef(name: 'review', description: '自查'),
          ],
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('composer-input')), '/st');
    await tester.pump();

    expect(find.byKey(const ValueKey('composer-skill-style')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-skill-review')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('composer-skill-style')));
    await tester.pump();

    expect(state.text, '/style ');
  });

  testWidgets('the plus button offers both attachment sources', (tester) async {
    final requested = <AttachmentSource>[];
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          onPickAttachments: (source) async {
            requested.add(source);
            return ['picked.txt'];
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('composer-plus')));
    await tester.pumpAndSettle();
    expect(find.text('项目文件'), findsOneWidget);
    expect(find.text('工作区文件'), findsOneWidget);

    await tester.tap(find.text('工作区文件'));
    await tester.pumpAndSettle();

    expect(requested, [AttachmentSource.workspace]);
    expect(state.attachments, ['picked.txt']);
  });

  testWidgets('every tool row target is at least 44 high', (tester) async {
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          onPickAttachments: (_) async => null,
          models: const [
            AgentModelOption(
              id: 'model-a',
              label: 'Model A',
              reasoningEfforts: ['high'],
            ),
          ],
        ),
      ),
    );

    for (final key in const [
      'composer-plus',
      'composer-permission',
      'composer-model',
      'composer-reasoning',
      'composer-send',
    ]) {
      final size = tester.getSize(find.byKey(ValueKey(key)));
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
    }
  });
}
