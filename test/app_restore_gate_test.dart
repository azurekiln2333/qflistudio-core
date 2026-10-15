import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/app.dart';
import 'package:qfli_studio_core/pages/home_page.dart';
import 'package:qfli_studio_core/pages/restore_complete_page.dart';
import 'package:qfli_studio_core/services/app_restore_gate.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

void main() {
  tearDown(() => AppRestoreGate.status.value = null);

  for (final status in AppRestoreStatus.values) {
    testWidgets('cold restore $status prevents entering Home', (tester) async {
      final ready = ValueNotifier(false);
      final store = ProjectStore();
      final auth = AuthStore();
      final settings = SettingsStore();
      addTearDown(ready.dispose);
      addTearDown(store.dispose);
      addTearDown(auth.dispose);
      addTearDown(settings.dispose);

      await tester.pumpWidget(
        QfliApp(store: store, auth: auth, settings: settings, ready: ready),
      );
      if (status == AppRestoreStatus.completed) {
        AppRestoreGate.requireRestart();
      } else {
        AppRestoreGate.requireRecovery();
      }
      ready.value = true;
      await tester.pumpAndSettle();

      expect(find.byType(RestoreCompletePage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      expect(find.textContaining('完全关闭应用'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isFalse);
      await tester.pump();
      expect(find.byType(RestoreCompletePage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('initial $status gate fits narrow screens and large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(240, 320);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = ProjectStore();
      final auth = AuthStore();
      final settings = SettingsStore();
      addTearDown(store.dispose);
      addTearDown(auth.dispose);
      addTearDown(settings.dispose);
      AppRestoreGate.status.value = status;

      await tester.pumpWidget(
        QfliApp(store: store, auth: auth, settings: settings),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RestoreCompletePage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      final context = tester.element(find.byType(RestoreCompletePage));
      expect(MediaQuery.textScalerOf(context).scale(10), 30);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
      expect(scrollable.position.extentAfter, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
