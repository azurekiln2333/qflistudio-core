import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/harness/harness_host.dart';
import 'package:qfli_studio_core/harness/hub/agents_index.dart';
import 'package:qfli_studio_core/harness/hub/harness_hub.dart';
import 'package:qfli_studio_core/services/app_paths.dart';
import 'package:qfli_studio_core/shell/workbench_session_view.dart';

import 'support/fake_harness_host.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1024.0, 1440.0]) {
      testWidgets(
        'session header uses workbench geometry at $width / $brightness',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final session = fakeSession(
            hostId: 'local',
            id: 'header',
            title:
                'A long session title that must truncate instead of wrapping',
          );
          final handle = FakeSessionHandle(info: session);
          final hub = HarnessHub(
            hosts: [
              FakeHarnessHost(
                id: 'local',
                label: 'Local',
                kind: HarnessHostKind.local,
                openHandler: (_) async => handle,
              ),
            ],
            desktop: AppPaths.isDesktop,
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await hub.shutdown();
          });
          final theme = ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: brightness,
            ),
          );
          var closes = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: WorkbenchSessionView(
                  row: AgentsIndexRow(
                    session: session,
                    hostLabel: 'A very long host name',
                    hostKind: HarnessHostKind.local,
                  ),
                  hub: hub,
                  onClose: () => closes++,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          final header = find.byKey(const ValueKey('workbench-session-header'));
          expect(tester.getSize(header).height, AppPaths.isDesktop ? 40 : 48);
          final material = find
              .ancestor(of: header, matching: find.byType(Material))
              .first;
          expect(
            tester.widget<Material>(material).color,
            theme.colorScheme.surfaceContainerLow,
          );
          final close = find.byKey(const ValueKey('workbench-session-close'));
          expect(tester.getSize(close).height, AppPaths.isDesktop ? 40 : 48);
          final title = tester.widget<Text>(find.text(session.title));
          expect(title.maxLines, 1);
          expect(title.overflow, TextOverflow.ellipsis);
          expect(tester.takeException(), isNull);
          await tester.tap(close);
          await tester.pump();
          expect(closes, 1);
          expect(handle.detachCount, 1);
          expect(handle.stopCount, 0);
        },
      );
    }
  }
}
