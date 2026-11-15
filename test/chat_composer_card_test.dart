import 'dart:async';

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
    // 发送与停止占同一个区域，两者都量到外框，不量内部的圆。
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

  // 发送跨了会话切换：回来的那次发送不能清新会话的草稿。
  testWidgets(
    'a send that returns after a session switch keeps the new draft',
    (tester) async {
      final first = ComposerState()..text = '第一条';
      final second = ComposerState()..text = '新会话的草稿';
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final gate = Completer<bool>();

      await tester.pumpWidget(
        host(
          ComposerCard(
            state: first,
            onSend: (text, attachments) => gate.future,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();

      // 发送还没返回就换了会话。
      await tester.pumpWidget(
        host(
          ComposerCard(
            state: second,
            onSend: (text, attachments) async => true,
          ),
        ),
      );
      await tester.pump();

      gate.complete(true);
      await tester.pumpAndSettle();

      expect(second.text, '新会话的草稿');
      expect(second.attachments, isEmpty);
    },
  );

  // 选择器跨了会话切换：回来时不能把附件加到新会话。
  testWidgets('a picker that returns after a session switch is dropped', (
    tester,
  ) async {
    final first = ComposerState();
    final second = ComposerState();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final gate = Completer<List<String>?>();

    await tester.pumpWidget(
      host(
        ComposerCard(
          state: first,
          onSend: (text, attachments) async => true,
          onPickAttachments: (_) => gate.future,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('composer-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目文件'));
    await tester.pump();

    // 等选择器的时候换了会话。
    await tester.pumpWidget(
      host(
        ComposerCard(
          state: second,
          onSend: (text, attachments) async => true,
          onPickAttachments: (_) async => null,
        ),
      ),
    );
    await tester.pump();

    gate.complete(['src/late.java']);
    await tester.pumpAndSettle();

    expect(second.attachments, isEmpty);
    expect(first.attachments, isEmpty);
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

  Widget hostAt(double width, Widget child, {double textScale = 1}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(width: width, child: child),
            ),
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

    // 空间不够时先收推理强度的文字，留图标和提示；有空间就带完整文字，
    // 但任何情况下都不会截成「l…」。
    expect(find.text('l…'), findsNothing);
    expect(find.byTooltip('推理强度：low'), findsOneWidget);

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
      // 可点范围也要够宽，不是只有高度够。
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
    }
  });

  // 加号靠左、选择器分开、发送键小且离右边有余量。
  testWidgets(
    'the send control is compact with a full 44 target and a right inset',
    (tester) async {
      await tester.pumpWidget(
        hostAt(
          424,
          ComposerCard(
            state: state,
            onSend: (text, attachments) async => true,
            onPickAttachments: (_) async => null,
          ),
        ),
      );

      final panel = tester.getRect(find.byType(ComposerCard));
      final send = tester.getRect(find.byKey(const ValueKey('composer-send')));
      // 手势区（IconButton 本身）不小于 44。
      expect(send.width, greaterThanOrEqualTo(44));
      expect(send.height, greaterThanOrEqualTo(44));
      // 可见图标比手势区小：控件看起来轻，可点范围不变。
      final icon = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('composer-send')),
          matching: find.byIcon(Icons.arrow_upward),
        ),
      );
      expect(icon.width, lessThanOrEqualTo(send.width - 10));
      // 与右边框之间留出内边距，不是贴着边。
      expect(panel.right - send.right, greaterThanOrEqualTo(12));
    },
  );

  testWidgets(
    'the plus icon sits at the left text edge, not centred in a slot',
    (tester) async {
      await tester.pumpWidget(
        hostAt(
          424,
          ComposerCard(
            state: state,
            onSend: (text, attachments) async => true,
            onPickAttachments: (_) async => null,
          ),
        ),
      );

      final panel = tester.getRect(find.byType(ComposerCard));
      final plusIcon = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('composer-plus')),
          matching: find.byIcon(Icons.add),
        ),
      );
      final input = tester.getRect(
        find.byKey(const ValueKey('composer-input')),
      );
      // 加号图标与输入框文字左边基本对齐。Material 图标自带一点内边，
      // 允许 12 像素以内的偏差；原来的居中摆放差出 12 像素以上。
      expect(
        (plusIcon.left - panel.left) - (input.left - panel.left),
        lessThan(12),
      );
      // 且明显靠左，占位不超过 24 像素。
      expect(plusIcon.left - panel.left, lessThan(32));
      // 整个加号按钮的左边就是内容区的左边，没有额外的空槽。
      expect(input.left - panel.left, lessThan(24));
    },
  );

  testWidgets('a real gap stays between plus and the selectors when narrow', (
    tester,
  ) async {
    // 320 宽 + 1.3 缩放是最挤的情况：原来 Spacer 会缩成 0，两个 chip 贴着。
    await tester.pumpWidget(
      hostAt(
        320,
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
        textScale: 1.3,
      ),
    );

    final plus = tester.getRect(find.byKey(const ValueKey('composer-plus')));
    final permission = tester.getRect(
      find.byKey(const ValueKey('composer-permission')),
    );
    final model = tester.getRect(find.byKey(const ValueKey('composer-model')));

    // 附件与选择器组之间留出真正的空隙，不被挤成 0。
    expect(permission.left - plus.right, greaterThanOrEqualTo(8));
    // 它仍然大于组内间距，两层关系分得开。
    expect(
      permission.left - plus.right,
      greaterThan(model.left - permission.right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the selector group is separated from plus and from send', (
    tester,
  ) async {
    await tester.pumpWidget(
      hostAt(
        424,
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

    final plus = tester.getRect(find.byKey(const ValueKey('composer-plus')));
    final permission = tester.getRect(
      find.byKey(const ValueKey('composer-permission')),
    );
    final reasoning = tester.getRect(
      find.byKey(const ValueKey('composer-reasoning')),
    );
    final send = tester.getRect(find.byKey(const ValueKey('composer-send')));
    // 附件组与选择器组之间的空隙大于组内间距。
    final outerGap = permission.left - plus.right;
    final innerGap =
        tester.getRect(find.byKey(const ValueKey('composer-model'))).left -
        permission.right;
    expect(outerGap, greaterThan(innerGap));
    // 选择器组与发送键也看得出分开。
    expect(send.left - reasoning.right, greaterThan(innerGap));
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

    await tester.enterText(find.byKey(const ValueKey('composer-input')), '第一行');
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

    await tester.enterText(find.byKey(const ValueKey('composer-input')), '第一行');
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

  group('工具行按可用宽度决定文字', () {
    const models = [
      AgentModelOption(
        id: 'deepseek-v4.1-flash',
        label: 'deepseek-v4.1-flash',
        reasoningEfforts: ['low', 'high'],
      ),
    ];

    testWidgets('宽 424、缩放 1.0：权限显示「每次询问」，不留大片空白', (tester) async {
      await tester.pumpWidget(
        hostAt(
          424,
          ComposerCard(
            state: state,
            onSend: (text, attachments) async => true,
            onPickAttachments: (_) async => null,
            models: models,
          ),
        ),
      );

      // 真机上权限只剩图标，是因为按屏幕宽度分档，而不是按可用宽度。
      expect(find.text('每次询问'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 模型按钮把剩下的宽度吃掉：工具行末尾没有大片空档。
      // 推理强度收成图标后仍占 44，落在模型和发送键之间。
      final send = tester.getRect(find.byKey(const ValueKey('composer-send')));
      final trailing = tester.getRect(
        find.byKey(const ValueKey('composer-reasoning')),
      );
      // 发送键与选择器组之间留出固定的分隔间距，不是零贴边，也不是大片空档。
      expect(send.left - trailing.right, greaterThanOrEqualTo(8));
      expect(send.left - trailing.right, lessThanOrEqualTo(20));
      // 剩余宽度给了模型名，不是空着。
      expect(
        tester.getRect(find.byKey(const ValueKey('composer-model'))).width,
        greaterThan(106),
      );
    });

    testWidgets('宽 424 减掉面板内边距后也显示权限文字', (tester) async {
      // 编辑器面板左右各留 8，卡片实际宽 408。
      await tester.pumpWidget(
        hostAt(
          408,
          ComposerCard(
            state: state,
            onSend: (text, attachments) async => true,
            onPickAttachments: (_) async => null,
            models: models,
          ),
        ),
      );

      expect(find.text('每次询问'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('宽 360 不溢出', (tester) async {
      await tester.pumpWidget(
        hostAt(
          360,
          ComposerCard(
            state: state,
            onSend: (text, attachments) async => true,
            onPickAttachments: (_) async => null,
            models: models,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // 每个按钮仍然可点，高度不小于 44。
      for (final key in const [
        'composer-permission',
        'composer-model',
        'composer-send',
      ]) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.height, greaterThanOrEqualTo(44), reason: key);
      }
    });

    testWidgets('缩放 1.3 且宽 360 不溢出', (tester) async {
      await tester.pumpWidget(
        hostAt(
          360,
          ComposerCard(
            state: state,
            onSend: (text, attachments) async => true,
            onPickAttachments: (_) async => null,
            models: models,
          ),
          textScale: 1.3,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
    });

    testWidgets('放不下时先收推理强度，再收权限，模型名最后', (tester) async {
      await tester.pumpWidget(
        hostAt(
          320,
          ComposerCard(
            state: state,
            onSend: (text, attachments) async => true,
            onPickAttachments: (_) async => null,
            models: models,
          ),
          textScale: 1.3,
        ),
      );

      expect(tester.takeException(), isNull);
      // 收掉文字后仍有图标和提示，不是空白。
      expect(find.byTooltip('权限模式：每次询问'), findsOneWidget);
      expect(find.byTooltip('推理强度：low'), findsOneWidget);
      expect(find.byTooltip('模型：deepseek-v4.1-flash'), findsOneWidget);
    });
  });
}
