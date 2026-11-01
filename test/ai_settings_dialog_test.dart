import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/ai_panel.dart';
import 'package:qfli_studio_core/services/ai_service.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qfli-ai-settings-');
    file = File(p.join(dir.path, 'settings.json'));
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  SettingsStore store() => SettingsStore(storageFile: file);

  test('a settings file without aiProtocol loads as chat', () async {
    file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'aiBaseUrl': 'https://api.old.example',
        'aiApiKey': 'sk-old',
        'aiModel': 'old-model',
      }),
    );
    final settings = store();
    await settings.load();
    expect(settings.aiProtocol, AiProtocol.chat);
    expect(settings.aiBaseUrl, 'https://api.old.example');
    expect(settings.aiApiKey, 'sk-old');
    expect(settings.aiModel, 'old-model');
    // Chat 就是引入协议前的唯一行为，端点推导保持不变。
    expect(
      AiService.endpointFor(settings.aiBaseUrl, settings.aiProtocol),
      'https://api.old.example/v1/chat/completions',
    );
  });

  test('an unknown protocol id falls back to chat instead of throwing', () async {
    file.writeAsStringSync(
      jsonEncode({'version': 1, 'aiProtocol': 'gemini-live'}),
    );
    final settings = store();
    await settings.load();
    expect(settings.aiProtocol, AiProtocol.chat);
  });

  test('protocol persists across a reload', () async {
    final first = store();
    await first.load();
    for (final protocol in AiProtocol.values) {
      await first.saveAi(
        baseUrl: 'https://api.test',
        apiKey: 'sk-1',
        model: 'm',
        protocol: protocol,
      );
      final reloaded = store();
      await reloaded.load();
      expect(reloaded.aiProtocol, protocol, reason: protocol.id);
      expect(reloaded.aiApiKey, 'sk-1');
    }
    final raw = jsonDecode(file.readAsStringSync()) as Map;
    expect(raw['aiProtocol'], 'messages');
  });

  test('saveAi keeps the current protocol when none is given', () async {    final settings = store();
    await settings.load();
    await settings.saveAi(
      baseUrl: 'b',
      apiKey: 'k',
      model: 'm',
      protocol: AiProtocol.responses,
    );
    await settings.saveAi(baseUrl: 'b2', apiKey: 'k2', model: 'm2');
    expect(settings.aiProtocol, AiProtocol.responses);
  });

  /// 推进测试时钟，让对话框与路由完成构建和退场。
  ///
  /// 不用 pumpAndSettle：真实文件 IO 跑在 fake async 时钟上会永久挂起，
  /// 且任何常驻动画都会让 settle 无限等待。
  Future<void> pumpDialog(WidgetTester tester, [int frames = 20]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  for (final width in [320.0, 360.0]) {
    testWidgets('AI dialog lays out at phone width $width', (tester) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 本用例只验证布局：不加载、不保存，避免在 fake async 时钟里做真实 IO。
      final settings = SettingsStore(
        storageFile: File(p.join(dir.path, 'unused.json')),
      );
      late BuildContext dialogContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => dialogContext = context,
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      // 未铺开对话框前先记下可用的 context。
      expect(dialogContext.mounted, isTrue);

      final opened = editAiSettings(dialogContext, settings);
      await pumpDialog(tester);

      expect(find.text('AI 接口设置'), findsOneWidget);
      for (final protocol in AiProtocol.values) {
        expect(find.text(protocol.label), findsOneWidget);
      }
      // 窄屏下三个协议标签必须完整可见，不能溢出裁切。
      for (final protocol in AiProtocol.values) {
        final rect = tester.getRect(find.text(protocol.label));
        expect(rect.width, greaterThan(0));
        expect(rect.right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);

      // 取消退出：不触发写盘，只验证弹窗能正常关闭。
      await tester.tap(find.text('取消'));
      await pumpDialog(tester);
      await opened;
      expect(find.text('AI 接口设置'), findsNothing);
    });
  }
}
