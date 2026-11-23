import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/shell/workbench_chrome.dart';

/// 用真实主题与本地化层包住被测组件。
///
/// 导航条取值来自 [StudioLocalizations] 与 `Theme.of(context)`，
/// 裸 MaterialApp 也够用，但显式带上本地化委托才与线上渲染一致。
Widget _host(
  Widget child, {
  Locale locale = const Locale('en'),
  Size size = const Size(400, 800),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      StudioLocalizations.delegate,
      DefaultMaterialLocalizations.delegate,
      DefaultWidgetsLocalizations.delegate,
    ],
    supportedLocales: StudioLocalizations.supportedLocales,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(size: size),
        // 真正约束尺寸：只改 MediaQuery 数据不会限制布局，
        // 窄高场景就测不到溢出。
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    ),
  );
}

/// 记录回调的轻量宿主：把点击结果收进 [tapped]，不自己改选中态。
class _Recorder {
  final List<WorkbenchActivity> tapped = <WorkbenchActivity>[];

  void call(WorkbenchActivity activity) => tapped.add(activity);
}

void main() {
  group('WorkbenchActivityRail', () {
    testWidgets('每个图标点击都回传自己的枚举值', (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.projects,
            onSelected: recorder.call,
          ),
        ),
      );

      // 顶部三块主要去处逐个点过去。
      for (final activity in WorkbenchActivityRail.primary) {
        await tester.tap(
          find.byKey(WorkbenchActivityRail.activityKey(activity)),
        );
        await tester.pump();
      }

      expect(recorder.tapped, <WorkbenchActivity>[
        WorkbenchActivity.projects,
        WorkbenchActivity.files,
        WorkbenchActivity.agents,
      ]);
    });

    testWidgets('底部头像回传 profile，设置回传 settings', (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.projects,
            onSelected: recorder.call,
            accountLabel: 'Ada',
          ),
        ),
      );

      await tester.tap(find.byKey(WorkbenchActivityRail.avatarKey));
      await tester.pump();
      await tester.tap(
        find.byKey(
          WorkbenchActivityRail.activityKey(WorkbenchActivity.settings),
        ),
      );
      await tester.pump();

      expect(recorder.tapped, <WorkbenchActivity>[
        WorkbenchActivity.profile,
        WorkbenchActivity.settings,
      ]);
    });

    testWidgets('选中项在语义树里报告 selected，其余不报告', (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);

      await tester.pumpWidget(
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.files,
            onSelected: _Recorder().call,
          ),
        ),
      );

      // 选中项与未选中项都用 Semantics 暴露 selected 标志。
      // 用 isSemantics（子集匹配）而不是完全匹配：Tooltip 与 InkWell
      // 会补上自己的语义条目，严格匹配会在无关字段上误报。
      expect(
        tester.getSemantics(
          find.byKey(
            WorkbenchActivityRail.activityKey(WorkbenchActivity.files),
          ),
        ),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          label: 'Files',
        ),
      );
      expect(
        tester.getSemantics(
          find.byKey(
            WorkbenchActivityRail.activityKey(WorkbenchActivity.projects),
          ),
        ),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          label: 'All projects',
        ),
      );
    });

    testWidgets('宽度固定 52px，达到 44px 触控目标', (tester) async {
      await tester.pumpWidget(
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.projects,
            onSelected: _Recorder().call,
          ),
        ),
      );

      final rail = tester.getSize(find.byType(WorkbenchActivityRail));
      expect(rail.width, WorkbenchActivityRail.width);
      expect(rail.width, 52);

      for (final activity in <WorkbenchActivity>[
        ...WorkbenchActivityRail.primary,
        ...WorkbenchActivityRail.secondary,
        WorkbenchActivity.settings,
      ]) {
        final size = tester.getSize(
          find.byKey(WorkbenchActivityRail.activityKey(activity)),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(44),
          reason: '$activity 的触控高度不足 44px',
        );
      }

      final avatar = tester.getSize(
        find.byKey(WorkbenchActivityRail.avatarKey),
      );
      expect(avatar.height, greaterThanOrEqualTo(44));
    });

    testWidgets('文字放大到 2.0 时导航条不变宽也不溢出', (tester) async {
      await tester.pumpWidget(
        _host(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: WorkbenchActivityRail(
              selected: WorkbenchActivity.agents,
              onSelected: _Recorder().call,
              accountLabel: 'Ada',
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(WorkbenchActivityRail)).width,
        WorkbenchActivityRail.width,
      );
    });

    testWidgets('高度只有 240px 时不溢出，底部头像仍可点', (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.projects,
            onSelected: recorder.call,
          ),
          size: const Size(400, 240),
        ),
      );

      expect(tester.takeException(), isNull);
      // 上半部分滚动，底部两项固定：头像必须还在可视区内。
      expect(find.byKey(WorkbenchActivityRail.avatarKey), findsOneWidget);
      await tester.tap(find.byKey(WorkbenchActivityRail.avatarKey));
      await tester.pump();
      expect(recorder.tapped, <WorkbenchActivity>[WorkbenchActivity.profile]);
    });

    testWidgets('账号名首字作为头像回退', (tester) async {
      await tester.pumpWidget(
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.projects,
            onSelected: _Recorder().call,
            accountLabel: 'ada',
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('没有账号名时退回图标占位', (tester) async {
      await tester.pumpWidget(
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.projects,
            onSelected: _Recorder().call,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(WorkbenchActivityRail.avatarKey),
          matching: find.byIcon(Icons.person_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('中文界面使用中文标签', (tester) async {
      final semantics = tester.ensureSemantics();
      addTearDown(semantics.dispose);

      await tester.pumpWidget(
        _host(
          WorkbenchActivityRail(
            selected: WorkbenchActivity.files,
            onSelected: _Recorder().call,
          ),
          locale: const Locale('zh', 'CN'),
        ),
      );

      expect(
        tester.getSemantics(
          find.byKey(
            WorkbenchActivityRail.activityKey(WorkbenchActivity.files),
          ),
        ),
        isSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          label: '文件',
        ),
      );
    });
  });

  group('WorkbenchWelcome', () {
    testWidgets('打开项目按钮回调一次', (tester) async {
      var opens = 0;
      await tester.pumpWidget(
        _host(WorkbenchWelcome(onOpenProject: () => opens++)),
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(opens, 1);
    });

    testWidgets('只说明空状态，不出现统计数字', (tester) async {
      await tester.pumpWidget(_host(WorkbenchWelcome(onOpenProject: () {})));

      expect(find.text('No projects yet'), findsOneWidget);
      // 欢迎区不画指标卡：没有卡片与图表类组件。
      expect(find.byType(Card), findsNothing);
      expect(find.byType(DataTable), findsNothing);
    });

    testWidgets('窄而矮的容器里不溢出', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 200,
            height: 180,
            child: WorkbenchWelcome(onOpenProject: () {}),
          ),
          size: const Size(200, 180),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });
}
