import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_controller.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_panel.dart';
import 'package:qfli_studio_core/vibe_coding/vibe_coding_widgets.dart';

/// Minimal controller stand-in that exposes an injectable plan so the panel
/// can be tested without a backend round.
class _PlanController extends VibeCodingController {
  _PlanController({
    required super.api,
    required super.tokenProvider,
    required super.projectRoot,
    required super.projectName,
    required super.language,
    required List<VibePlanItem> Function() plan,
    required List<String> Function() used,
  }) : _planProvider = plan,
       _usedProvider = used;

  final List<VibePlanItem> Function() _planProvider;
  final List<String> Function() _usedProvider;

  @override
  List<VibePlanItem> get plan => _planProvider();

  @override
  List<String> get usedSkills => List.unmodifiable(_usedProvider());

  void markPlanChanged() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  VibeToolCall tool({
    VibeToolStatus status = VibeToolStatus.ok,
    String? output,
    int? exitCode,
    String? result,
  }) => VibeToolCall(
    id: 'c1',
    toolName: 'run_command',
    summary: 'python main.py',
    status: status,
    result: result,
    commandOutput: output,
    exitCode: exitCode,
  );

  group('VibeMessageTile', () {
    testWidgets('renders a tool call with real output and exit code', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          VibeMessageTile(
            message: VibeMessage(
              isUser: false,
              text: '',
              tool: tool(
                status: VibeToolStatus.error,
                output: 'Traceback: boom',
                exitCode: 1,
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('运行命令'), findsOneWidget);
      expect(find.textContaining('python main.py'), findsOneWidget);
      expect(find.text('失败'), findsOneWidget);
      expect(find.textContaining('Traceback: boom'), findsOneWidget);

      await tester.tap(find.byTooltip('展开输出'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Traceback: boom'), findsWidgets);
      expect(find.textContaining('退出码 1'), findsOneWidget);
    });

    testWidgets('labels a conflict without claiming success', (tester) async {
      await tester.pumpWidget(
        wrap(
          VibeMessageTile(
            message: VibeMessage(
              isUser: false,
              text: '未写入',
              tool: tool(status: VibeToolStatus.conflict, result: '已拒绝覆盖'),
            ),
          ),
        ),
      );
      expect(find.text('冲突，已拒绝覆盖'), findsOneWidget);
      expect(find.text('未写入'), findsOneWidget);
    });

    testWidgets('renders a user bubble verbatim', (tester) async {
      await tester.pumpWidget(
        wrap(
          const VibeMessageTile(
            message: VibeMessage(isUser: true, text: '给我一个网页'),
          ),
        ),
      );
      expect(find.text('给我一个网页'), findsOneWidget);
    });
  });

  group('VibeCodingPanel', () {
    late Directory root;
    late _PlanController controller;
    var planItems = <VibePlanItem>[];
    var usedSkills = <String>[];

    setUp(() async {
      root = await Directory.systemTemp.createTemp('vibe_panel_');
      planItems = <VibePlanItem>[];
      usedSkills = <String>[];
      controller = _PlanController(
        api: ApiClient.instance,
        tokenProvider: () => null,
        projectRoot: root.path,
        projectName: 'demo',
        language: 'dart',
        plan: () => planItems,
        used: () => usedSkills,
      );
    });

    tearDown(() async {
      controller.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    });

    testWidgets('shows the login gate and hides the prompt', (tester) async {
      await tester.pumpWidget(
        wrap(
          VibeCodingPanel(
            controller: controller,
            loggedIn: false,
            onSend: (_) async => true,
          ),
        ),
      );
      expect(find.textContaining('需要登录'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('sends trimmed text and clears the input', (tester) async {
      String? sent;
      await tester.pumpWidget(
        wrap(
          VibeCodingPanel(
            controller: controller,
            loggedIn: true,
            projectName: 'demo',
            onSend: (text) async {
              sent = text;
              return true;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '  写一个脚本  ');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(sent, '写一个脚本');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });

    testWidgets('keeps the text when a protected save refuses the send', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          VibeCodingPanel(
            controller: controller,
            loggedIn: true,
            onSend: (_) async => false,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '别丢');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '别丢',
      );
    });

    testWidgets('collapses to a header without overflow', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            height: 360,
            child: VibeCodingPanel(
              controller: controller,
              loggedIn: true,
              onSend: (_) async => true,
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byTooltip('收起'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('展开'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports prompt focus so the editor can keep it mounted', (
      tester,
    ) async {
      final focusStates = <bool>[];
      await tester.pumpWidget(
        wrap(
          VibeCodingPanel(
            controller: controller,
            loggedIn: true,
            onSend: (_) async => true,
            onInputFocusChanged: focusStates.add,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focusStates.contains(true), isTrue);
    });

    testWidgets('lays out without overflow on a narrow short viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrap(
          VibeCodingPanel(
            controller: controller,
            loggedIn: true,
            onSend: (_) async => true,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('发送'), findsOneWidget);
    });

    testWidgets('lists plan items and toggles them on a phone viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrap(
          VibeCodingPanel(
            controller: controller,
            loggedIn: true,
            onSend: (_) async => true,
          ),
        ),
      );
      expect(find.textContaining('计划'), findsNothing);

      planItems = const [
        VibePlanItem(
          id: '1',
          title: '创建 index.html',
          status: VibePlanStatus.done,
        ),
        VibePlanItem(
          id: '2',
          title: '写 styles.css 并适配窄屏布局',
          status: VibePlanStatus.doing,
        ),
      ];
      controller.markPlanChanged();
      await tester.pumpAndSettle();

      expect(find.text('计划 1/2'), findsOneWidget);
      expect(find.text('创建 index.html'), findsOneWidget);
      expect(find.text('写 styles.css 并适配窄屏布局'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('计划 1/2'));
      await tester.pumpAndSettle();
      expect(find.text('创建 index.html'), findsNothing);

      await tester.tap(find.byTooltip('收起'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the skill that the agent loaded', (tester) async {
      await tester.pumpWidget(
        wrap(
          VibeCodingPanel(
            controller: controller,
            loggedIn: true,
            onSend: (_) async => true,
          ),
        ),
      );
      usedSkills = ['web-app-scaffold'];
      controller.markPlanChanged();
      await tester.pumpAndSettle();

      expect(find.text('web-app-scaffold'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
