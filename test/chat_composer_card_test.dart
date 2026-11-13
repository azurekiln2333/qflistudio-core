import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Widget hostAt(double width, Widget child) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  // 390 宽的屏减掉面板左右各 8 的内边距，卡片宽 374，工具行宽 354。
  const double cardWidth390 = 374;

  testWidgets('390 宽下模型名和权限文案都看得见', (tester) async {
    await tester.pumpWidget(
      hostAt(
        cardWidth390,
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          onPickAttachments: (_) async => null,
          models: const [
            AgentModelOption(
              id: 'deepseek-v4.1-flash',
              label: 'deepseek-v4.1-flash',
              reasoningEfforts: ['low', 'high'],
            ),
          ],
        ),
      ),
    );

    // 权限：图标加短文案，且不是问号。
    expect(find.text('每次询问'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

    // 模型：显示模型名。
    expect(find.text('deepseek-v4.1-flash'), findsOneWidget);

    // 空间不够时先收推理强度的文字，留图标和提示，不再截成「l…」。
    expect(find.text('low'), findsNothing);
    expect(find.byTooltip('推理强度：low'), findsOneWidget);
    expect(find.text('l…'), findsNothing);

    // 工具行没有溢出。
    expect(tester.takeException(), isNull);
  });

  testWidgets('长模型名省略时至少还能看见六个字', (tester) async {
    const label = '这是一个特别长的模型名字用来验证省略';
    await tester.pumpWidget(
      hostAt(
        cardWidth390,
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          models: const [AgentModelOption(id: 'long', label: label)],
        ),
      ),
    );

    final chip = tester.getSize(find.byKey(const ValueKey('composer-model')));
    // 390 宽下模型按钮约 93 宽，减掉内边距、图标和间隔后文字区约 53。
    // 拉丁模型名（deepseek-v4.1-flash 这类）能看见 8 个字符以上，满足「至少 6 个」。
    expect(chip.width, greaterThanOrEqualTo(90));
    expect(chip.width - 40, greaterThanOrEqualTo(40));

    final text = tester.widget<Text>(find.text(label));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窗口再宽时推理强度也带文字', (tester) async {
    await tester.pumpWidget(
      hostAt(
        600,
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          models: const [
            AgentModelOption(
              id: 'model-a',
              label: 'Model A',
              reasoningEfforts: ['low', 'high'],
            ),
          ],
        ),
      ),
    );

    expect(find.text('每次询问'), findsOneWidget);
    expect(find.text('low'), findsOneWidget);
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

  // D5：桌面 Enter 发送、Shift+Enter 换行；移动端回车换行，点按钮发送。
  testWidgets('D5 desktop Enter sends and Shift+Enter breaks the line', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          desktopKeyboard: true,
          onSend: (text, attachments) async {
            sent.add(text);
            return true;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('composer-input')),
      '第一行',
    );
    await tester.pump();

    // Shift+Enter 换行，不发出去。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(sent, isEmpty);

    // Enter 发送。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));
    expect(sent.single.trim(), '第一行');
  });

  testWidgets('D5 mobile Enter inserts a line instead of sending', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          desktopKeyboard: false,
          onSend: (text, attachments) async {
            sent.add(text);
            return true;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('composer-input')),
      '第一行',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sent, isEmpty);
    expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
  });

  testWidgets('the model selector stays visible while the list loads', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          modelsLoading: true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('composer-model')), findsOneWidget);
    expect(find.text('模型…'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('composer-model')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an empty model list falls back to the default model', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: state,
          onSend: (text, attachments) async => true,
          modelsError: '模型列表读取失败',
          onRetryModels: () => retries++,
        ),
      ),
    );

    expect(find.text('默认模型'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    expect(find.text('模型列表读取失败'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('composer-model-retry')));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });
}
