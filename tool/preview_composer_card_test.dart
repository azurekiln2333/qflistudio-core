import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/chat/composer_card.dart';
import 'package:qfli_studio_core/chat/composer_state.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_agent_facade.dart';

// 输入卡片的预览截图，用于核对左右内边距、三组控件和窄屏表现。
//
//   flutter test --no-pub tool/preview_composer_card_test.dart
//
// 输出到任务目录的 check/screens/pi-C-composer/。可用
// --dart-define=UI_FONT_PATH=... 指定含中文字形的本地字体。
const String _outDir =
    'D:/MyNewProjects/qflistudio/.trellis/tasks/11-15-agent-chat-usability/'
    'check/screens/pi-C-composer';

void main() {
  const fontPath = String.fromEnvironment(
    'UI_FONT_PATH',
    defaultValue: 'C:/Windows/Fonts/msyh.ttc',
  );

  const models = [
    AgentModelOption(
      id: 'deepseek-v4.1-flash',
      label: 'deepseek-v4.1-flash',
      reasoningEfforts: ['low', 'high'],
    ),
  ];

  Future<void> loadFonts(WidgetTester tester) async {
    await tester.runAsync(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      if (await File(fontPath).exists()) {
        final bytes = await File(fontPath).readAsBytes();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
  }

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required double width,
    required double textScale,
    required Brightness brightness,
    bool running = false,
    bool withAttachments = false,
    String text = '',
  }) async {
    final state = ComposerState();
    if (withAttachments) state.attachAll(['src/Main.java']);
    if (text.isNotEmpty) state.text = text;
    addTearDown(state.dispose);

    tester.view.physicalSize = Size(width, 220);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 220),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ComposerCard(
                  state: state,
                  running: running,
                  onSend: (text, attachments) async => true,
                  onStop: () {},
                  onPickAttachments: (_) async => null,
                  models: models,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets('composer previews', (tester) async {
    await loadFonts(tester);
    for (final width in const [320.0, 360.0, 424.0, 600.0]) {
      for (final scale in const [1.0, 1.3]) {
        for (final brightness in const [Brightness.light, Brightness.dark]) {
          final theme = brightness == Brightness.dark ? 'dark' : 'light';
          await capture(
            tester,
            name: 'composer-${width.toInt()}-${scale}_$theme',
            width: width,
            textScale: scale,
            brightness: brightness,
          );
        }
      }
    }
    // 有内容时发送键是主色圆：两种主题都要看清箭头。
    for (final brightness in const [Brightness.light, Brightness.dark]) {
      final theme = brightness == Brightness.dark ? 'dark' : 'light';
      await capture(
        tester,
        name: 'composer-ready-360_$theme',
        width: 360,
        textScale: 1,
        brightness: brightness,
        text: '把输出改成大写',
        withAttachments: true,
      );
      // 运行态：停止键的底色是容器色，图形必须与它成对比。
      await capture(
        tester,
        name: 'composer-running-360_$theme',
        width: 360,
        textScale: 1,
        brightness: brightness,
        running: true,
        text: '正在跑',
      );
    }
  });
}
