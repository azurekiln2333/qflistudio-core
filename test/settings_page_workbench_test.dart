import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qfli_studio_core/pages/settings_page.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/shell/large_screen_controller.dart';
import 'package:qfli_studio_core/shell/shortcut_label.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('workbench-settings-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    await AppPaths.storageDirectory();
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = previousPaths;
    await root.delete(recursive: true);
  });

  testWidgets('phone settings keep existing controls without workbench items', (
    tester,
  ) async {
    final settings = SettingsStore();
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: settings, showAi: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('外观与体验'), findsOneWidget);
    expect(find.text('界面缩放'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-large-screen-symbols')),
      findsNothing,
    );
    expect(find.text('快捷键'), findsNothing);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-large-screen-symbols')),
      findsNothing,
    );
    expect(find.text('快捷键'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('workbench zoom buttons, bounds, reset and tooltips', (
    tester,
  ) async {
    final settings = SettingsStore();
    final shell = LargeScreenController();
    await tester.pumpWidget(_app(settings, shell));
    await tester.pumpAndSettle();
    final zoomIn = find.byKey(const ValueKey('settings-ui-zoom-in'));
    final zoomOut = find.byKey(const ValueKey('settings-ui-zoom-out'));
    final reset = find.byKey(const ValueKey('settings-ui-zoom-reset'));
    expect(find.text('100%'), findsOneWidget);
    expect(tester.widget<TextButton>(reset).onPressed, isNull);
    expect(
      tester.widget<IconButton>(zoomIn).tooltip,
      '放大界面 (${shortcutLabel('Ctrl+= / Ctrl++')})',
    );
    expect(
      tester.widget<IconButton>(zoomOut).tooltip,
      '缩小界面 (${shortcutLabel('Ctrl+-')})',
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(zoomIn);
      await tester.pump();
    }
    expect(settings.uiScale, 1.3);
    expect(find.text('130%'), findsOneWidget);
    await tester.tap(zoomOut);
    await tester.pump();
    expect(settings.uiScale, 1.2);
    await tester.tap(reset);
    await tester.pump();
    expect(settings.uiScale, 1);
    await settings.setUiScale(2);
    await tester.pump();
    expect(tester.widget<IconButton>(zoomIn).onPressed, isNull);
    await settings.setUiScale(0.5);
    await tester.pump();
    expect(tester.widget<IconButton>(zoomOut).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    shell.dispose();
    settings.dispose();
  });

  testWidgets('symbols default off and update through the real switch', (
    tester,
  ) async {
    final settings = SettingsStore();
    final shell = LargeScreenController();
    await tester.pumpWidget(_app(settings, shell));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('settings-large-screen-symbols'));
    await tester.scrollUntilVisible(
      toggle,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pump();
    expect(settings.largeScreenSymbolBar, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pump();
    expect(settings.largeScreenSymbolBar, isFalse);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.pumpWidget(const SizedBox());
    shell.dispose();
    settings.dispose();
  });

  testWidgets('read-only shortcut reference covers every PRD binding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = SettingsStore();
    final shell = LargeScreenController();
    await tester.pumpWidget(_app(settings, shell));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('快捷键'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final expected = [
      'Ctrl+= / Ctrl++ / Ctrl+NumpadAdd',
      'Ctrl+- / Ctrl+NumpadSubtract',
      'Ctrl+0 / Ctrl+Numpad0',
      'Ctrl+B',
      'Ctrl+Shift+E',
      'Ctrl+Shift+A',
      'Ctrl+,',
      'Ctrl+`',
      'Ctrl+J',
      'Ctrl+L',
      'Ctrl+W',
      'Ctrl+Tab / Ctrl+Shift+Tab',
      'Ctrl+N',
      'F5',
      'Ctrl+S',
      'Ctrl+F',
      'Ctrl+G',
      'Ctrl+I',
    ];
    for (final key in expected) {
      final text = find.textContaining('${shortcutLabel(key)} ·');
      await tester.ensureVisible(text);
      final tile = tester.widget<ListTile>(
        find.ancestor(of: text, matching: find.byType(ListTile)),
      );
      expect(tile.onTap, isNull, reason: '$key must be read-only');
    }
    expect(find.text('终端获得焦点时，关闭标签、底部面板和 Agent 栏的快捷键交给终端。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    shell.dispose();
    settings.dispose();
  });
}

Widget _app(SettingsStore settings, LargeScreenController shell) => MaterialApp(
  home: LargeScreenScope(
    controller: shell,
    child: SettingsPage(settings: settings, showAi: false),
  ),
);

class _Paths extends PathProviderPlatform {
  _Paths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
