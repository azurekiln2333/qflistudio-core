import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qfli_studio_core/editor/editor_controller.dart';
import 'package:qfli_studio_core/editor/editor_page.dart';
import 'package:qfli_studio_core/editor/editor_selection_toolbar.dart';
import 'package:qfli_studio_core/editor/retained_editor_host.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  testWidgets('first open, Back exit and resume animate the same live editor', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester);
    await tester.tap(find.text('Open Alpha'));
    await tester.pump();
    final editor = _page(fixture.alpha);
    final state = tester.state(editor);
    final controller = _editorController(tester, editor);
    final navigator = Navigator.of(tester.element(editor));
    final initialSlide = _slide(tester, editor);
    expect(initialSlide, greaterThan(0));
    expect(_opacity(tester, editor), lessThan(1));
    expect(
      _offstage(tester, find.byKey(const ValueKey('home-action'))),
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(_slide(tester, editor), lessThan(initialSlide));
    expect(_slide(tester, editor), greaterThan(0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_slide(tester, editor), 0);
    expect(_opacity(tester, editor), 1);
    expect(
      _offstage(
        tester,
        find.byKey(const ValueKey('home-action'), skipOffstage: false),
      ),
      isTrue,
    );

    // Platform Back changes logical visibility and focus policy immediately;
    // the retained visual then exits over Home.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(fixture.host.isVisible, isFalse);
    expect(
      tester.widget<EditorPage>(editor).retainedVisibility!.value,
      isFalse,
    );
    expect(_offstage(tester, editor), isFalse);
    // The nested Navigator propagates the new inherited mode on its next frame.
    await tester.pump();
    expect(TickerMode.valuesOf(tester.element(editor)).enabled, isFalse);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(of: editor, matching: find.byType(IgnorePointer))
                .last,
          )
          .ignoring,
      isTrue,
    );
    expect(
      tester
          .widget<ExcludeFocus>(
            find.ancestor(of: editor, matching: find.byType(ExcludeFocus)).last,
          )
          .excluding,
      isTrue,
    );
    expect(
      tester
          .widget<ExcludeSemantics>(
            find
                .ancestor(of: editor, matching: find.byType(ExcludeSemantics))
                .last,
          )
          .excluding,
      isTrue,
    );
    expect(find.textContaining('返回编辑器 ·'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-action')));
    expect(fixture.homeActions, 1);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_slide(tester, editor), greaterThan(0));
    expect(_opacity(tester, editor), lessThan(1));
    expect(find.textContaining('返回编辑器 ·'), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_offstage(tester, editor), isTrue);
    expect(_opacity(tester, editor), 0);
    expect(state.mounted, isTrue);
    expect(find.textContaining('返回编辑器 ·'), findsOneWidget);

    await tester.tap(find.textContaining('返回编辑器 ·'));
    await tester.pump();
    expect(_slide(tester, editor), greaterThan(0));
    expect(tester.state(editor), same(state));
    expect(_editorController(tester, editor), same(controller));
    expect(Navigator.of(tester.element(editor)), same(navigator));
    await tester.pump(const Duration(milliseconds: 220));
    expect(_slide(tester, editor), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid reversal and project switching preserve each Navigator and state',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      await tester.tap(find.text('Open Alpha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      final alpha = _page(fixture.alpha);
      final alphaState = tester.state(alpha);
      final alphaController = _editorController(tester, alpha);
      final alphaNavigator = Navigator.of(tester.element(alpha));
      await tester.tap(find.byTooltip('暂时收起编辑器'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      final outgoingSlide = _slide(tester, alpha);
      expect(outgoingSlide, greaterThan(0));
      // Home is usable during exit. Reopening reverses the same motion in place.
      await tester.tap(find.text('Open Alpha'));
      await tester.pump();
      expect(_slide(tester, alpha), outgoingSlide);
      expect(tester.state(alpha), same(alphaState));
      await tester.pump(const Duration(milliseconds: 35));
      expect(_slide(tester, alpha), lessThan(outgoingSlide));
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.byType(EditorPage, skipOffstage: false), findsOneWidget);

      await tester.tap(find.byTooltip('暂时收起编辑器'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Open Beta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      final beta = _page(fixture.beta);
      final betaState = tester.state(beta);
      final betaNavigator = Navigator.of(tester.element(beta));
      fixture.host.resume(fixture.alpha);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_offstage(tester, alpha), isFalse);
      expect(_offstage(tester, beta), isFalse);
      expect(
        tester
            .widgetList<EditorPage>(
              find.byType(EditorPage, skipOffstage: false),
            )
            .map((page) => page.project.path),
        [fixture.beta.path, fixture.alpha.path],
      );
      expect(tester.state(alpha), same(alphaState));
      expect(tester.state(beta), same(betaState));
      expect(_editorController(tester, alpha), same(alphaController));
      expect(Navigator.of(tester.element(alpha)), same(alphaNavigator));
      expect(Navigator.of(tester.element(beta)), same(betaNavigator));
      expect(TickerMode.valuesOf(tester.element(beta)).enabled, isFalse);
      await tester.pump(const Duration(milliseconds: 220));
      expect(_offstage(tester, beta), isTrue);
      expect(_offstage(tester, alpha), isFalse);
      expect(betaState.mounted, isTrue);
      expect(find.byType(EditorPage, skipOffstage: false), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion opens, minimizes and resumes without a transition',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester, reduceMotion: true);
      await tester.tap(find.text('Open Alpha'));
      await tester.pump();
      final editor = _page(fixture.alpha);
      final state = tester.state(editor);
      expect(_slide(tester, editor), 0);
      expect(_opacity(tester, editor), 1);
      await tester.tap(find.byTooltip('暂时收起编辑器'));
      await tester.pump();
      expect(_offstage(tester, editor), isTrue);
      expect(find.textContaining('返回编辑器 ·'), findsOneWidget);
      await tester.tap(find.textContaining('返回编辑器 ·'));
      await tester.pump();
      expect(tester.state(editor), same(state));
      expect(_slide(tester, editor), 0);
      expect(_opacity(tester, editor), 1);
      expect(_offstage(tester, editor), isFalse);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _page(Project project) => find.byWidgetPredicate(
  (widget) => widget is EditorPage && widget.project.path == project.path,
  skipOffstage: false,
);

double _slide(WidgetTester tester, Finder page) => tester
    .widget<SlideTransition>(
      find
          .ancestor(
            of: page,
            matching: find.byType(SlideTransition, skipOffstage: false),
          )
          .last,
    )
    .position
    .value
    .dy;

double _opacity(WidgetTester tester, Finder page) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: page,
            matching: find.byType(FadeTransition, skipOffstage: false),
          )
          .last,
    )
    .opacity
    .value;

bool _offstage(WidgetTester tester, Finder child) => tester
    .widget<Offstage>(
      find
          .ancestor(
            of: child,
            matching: find.byType(Offstage, skipOffstage: false),
          )
          .last,
    )
    .offstage;

EditorController _editorController(WidgetTester tester, Finder page) =>
    tester
            .widget<SelectionToolbarScope>(
              find.descendant(
                of: page,
                matching: find.byType(
                  SelectionToolbarScope,
                  skipOffstage: false,
                ),
              ),
            )
            .editor
        as EditorController;

class _Fixture {
  _Fixture() {
    alpha = _project('Alpha');
    beta = _project('Beta');
  }

  final directory = Directory.systemTemp.createTempSync('qfli_editor_motion_');
  final host = RetainedEditorController();
  final auth = AuthStore();
  final settings = SettingsStore();
  final store = ProjectStore();
  late final Project alpha;
  late final Project beta;
  int homeActions = 0;

  Project _project(String name) => Project.create(
    name: name,
    path: (Directory(p.join(directory.path, name))..createSync()).path,
  );

  Future<void> mount(WidgetTester tester, {bool reduceMotion = false}) async {
    final previousProfile = StudioProfile.current;
    StudioProfile.current = const StudioProfile(
      id: 'test',
      appTitle: 'Editor motion',
      templates: [],
      isOffline: true,
    );
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      host.dispose();
      auth.dispose();
      settings.dispose();
      store.dispose();
      StudioProfile.current = previousProfile;
      // The real editor schedules history.json writes on dispose. Drain both
      // clocks before deleting our tree, following the retained-editor suite.
      for (var round = 0; round < 4; round++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      FileSystemException? lastError;
      for (var round = 0; round < 50; round++) {
        final error = await tester.runAsync<FileSystemException?>(() async {
          try {
            if (directory.existsSync()) await directory.delete(recursive: true);
            return null;
          } on FileSystemException catch (error) {
            return error;
          }
        });
        if (error == null) return;
        lastError = error;
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      throw lastError!;
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [host.navigatorObserver],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: RetainedEditorHost(controller: host, child: child!),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                for (final project in [alpha, beta])
                  TextButton(
                    onPressed: () => openEditorPage(
                      context,
                      project: project,
                      auth: auth,
                      store: store,
                      settings: settings,
                    ),
                    child: Text('Open ${project.name}'),
                  ),
                TextButton(
                  key: const ValueKey('home-action'),
                  onPressed: () => homeActions++,
                  child: const Text('Home action'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}
