@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qfli_studio_core/community/models.dart';
import 'package:qfli_studio_core/i18n/studio_localizations.dart';
import 'package:qfli_studio_core/pages/profile_page.dart';
import 'package:qfli_studio_core/services/api_client.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/services/task_activity_service.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';
import 'package:qfli_studio_core/terminal/shell/sandbox_shell_backend.dart';
import 'package:qfli_studio_core/terminal/shell/shell_backend.dart';
import 'package:qfli_studio_core/terminal/widgets/shortcut_bar.dart';

const _user = CommunityUser(
  id: 'user_11111111111111111111111111111111',
  username: 'restored',
  nickname: 'Restored user',
  bio: '',
  avatarColor: '#2196F3',
  points: 0,
  checkinStreak: 0,
  provider: 'local',
);

void _installProfile({required bool offlineOnly}) {
  StudioProfile.current = StudioProfile(
    id: 'offline-background-test',
    appTitle: 'Test studio',
    templates: const [],
    // Exercise the explicit policy instead of accidentally relying on isOffline.
    isOffline: false,
    offlineOnly: offlineOnly,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StudioProfile? previousProfile;
  setUp(() => previousProfile = StudioProfile.current);
  tearDown(() => StudioProfile.current = previousProfile);

  test(
    'offline restored account keeps local activity without remote events',
    () async {
      _installProfile(offlineOnly: true);
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final requests = <http.Request>[];
      final client = _client(requests);
      addTearDown(client.close);
      final service = fixture.activity(client);
      addTearDown(service.dispose);

      expect(fixture.auth.isLoggedIn, isTrue);
      expect(fixture.auth.token, 'restored-token');
      for (final key in ['create_project', 'open_project', 'save_file']) {
        await service.record(fixture.auth, key);
        expect(service.countToday(fixture.auth, key), 1);
        expect(service.countAllTime(fixture.auth, key), 1);
      }
      await service.syncPending(fixture.auth, force: true);
      await service.refreshIfDue(fixture.auth, force: true);
      expect(requests, isEmpty);
      expect(service.pendingCount(fixture.auth), 0);
      final stored = jsonDecode(await fixture.tasks.readAsString()) as Map;
      expect(stored['pending'], isEmpty);

      final restored = fixture.activity(client);
      addTearDown(restored.dispose);
      await restored.initialize();
      for (final key in ['create_project', 'open_project', 'save_file']) {
        expect(restored.countToday(fixture.auth, key), 1);
        expect(restored.countAllTime(fixture.auth, key), 1);
      }
      expect(restored.pendingCount(fixture.auth), 0);
    },
  );

  test('offline policy holds an old pending event until online sync', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.tasks.writeAsString(
      jsonEncode({
        'pending': [
          {
            'id': 'event_existing',
            'userId': _user.id,
            'day': '2026-10-15',
            'key': 'create_project',
          },
        ],
      }),
    );
    final requests = <http.Request>[];
    final client = _client(requests);
    addTearDown(client.close);
    final service = fixture.activity(client);
    addTearDown(service.dispose);
    _installProfile(offlineOnly: true);
    await service.syncPending(fixture.auth, force: true);
    await service.refreshIfDue(fixture.auth, force: true);
    expect(requests, isEmpty);
    expect(service.pendingCount(fixture.auth), 1);

    _installProfile(offlineOnly: false);
    await service.syncPending(fixture.auth, force: true);
    expect(requests.single.url.path, '/api/users/me/task-events');
    expect(
      (jsonDecode(requests.single.body) as Map)['eventId'],
      'event_existing',
    );
    expect(service.pendingCount(fixture.auth), 0);
    expect(fixture.auth.user?.points, 10);
  });

  test(
    'online activity, task refresh, checkin and calendar remain functional',
    () async {
      _installProfile(offlineOnly: false);
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final requests = <http.Request>[];
      final client = _client(requests);
      addTearDown(client.close);
      final service = fixture.activity(client);
      addTearDown(service.dispose);
      await service.record(fixture.auth, 'save_file');
      await service.syncPending(fixture.auth, force: true);
      expect(service.countToday(fixture.auth, 'save_file'), 1);
      expect(service.pendingCount(fixture.auth), 0);
      await service.refreshIfDue(fixture.auth, force: true);
      expect(service.snapshotFor(fixture.auth)?.points, 10);
      final checkin = await service.checkin(fixture.auth);
      expect(checkin.reward, 10);
      expect(checkin.alreadyChecked, isFalse);
      await service.refreshCalendarIfDue(
        fixture.auth,
        DateTime(2026, 10),
        force: true,
      );
      expect(service.cachedCalendar(fixture.auth, DateTime(2026, 10)), [
        DateTime(2026, 10, 15),
      ]);
      expect(requests.map((request) => request.url.path), [
        '/api/users/me/task-events',
        '/api/users/me/tasks',
        '/api/users/me/checkin',
        '/api/users/me/checkins',
      ]);
    },
  );

  for (final offlineOnly in [true, false]) {
    testWidgets(
      'profile refresh respects offlineOnly=$offlineOnly with restored auth',
      (tester) async {
        _installProfile(offlineOnly: offlineOnly);
        final fixture = (await tester.runAsync(_Fixture.create))!;
        addTearDown(fixture.dispose);
        final settings = SettingsStore();
        final projects = ProjectStore();
        addTearDown(settings.dispose);
        addTearDown(projects.dispose);
        await tester.pumpWidget(
          _app(
            ProfileTab(auth: fixture.auth, settings: settings, store: projects),
          ),
        );
        await tester.pump();
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pump();
        expect(fixture.auth.refreshCalls, offlineOnly ? 0 : 1);
        expect(fixture.auth.isLoggedIn, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('expanded shortcuts respect offlineOnly=$offlineOnly', (
      tester,
    ) async {
      _installProfile(offlineOnly: offlineOnly);
      final inserted = <String>[];
      final keys = <ShortcutKey>[];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: ShortcutBar(
              ctrlActive: false,
              altActive: false,
              expanded: true,
              busy: false,
              attached: false,
              onCtrlChanged: (_) {},
              onAltChanged: (_) {},
              onExpandedChanged: (_) {},
              onText: inserted.add,
              onKey: keys.add,
              onCtrlLetter: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('网络工具'), offlineOnly ? findsNothing : findsOneWidget);
      for (final command in [
        'curl',
        'wget',
        'dig',
        'nslookup',
        'ping',
        'traceroute',
        'nc -z',
        'telnet',
        'ssh',
        'sftp',
        'scp',
        'git status',
      ]) {
        expect(find.text(command), offlineOnly ? findsNothing : findsOneWidget);
      }
      expect(find.text('符号'), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);
      expect(find.text('Tab'), findsOneWidget);
      final pwd = find.text('pwd');
      await tester.ensureVisible(pwd);
      await tester.tap(pwd);
      expect(inserted, ['pwd']);
      await tester.tap(find.text('Tab'));
      expect(keys, [ShortcutKey.tab]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
    'sandbox describes the host toolchain without naming a language',
    () async {
      final root = await Directory.systemTemp.createTemp('qfli_generic_shell_');
      addTearDown(() => root.delete(recursive: true));
      final backend = SandboxShellBackend(
        sandboxRoot: root.path,
        delegate: (_, _) async => false,
      );
      addTearDown(backend.shutdown);
      expect(backend.helpText, contains('语言工具链命令由宿主应用提供'));
      expect(backend.helpText, isNot(contains('Java')));
      final diagnostic = backend.output.firstWhere(
        (chunk) => chunk.kind == OutputKind.stderr,
      );
      await backend.execute('missing-tool');
      final message = (await diagnostic).text;
      expect(message, contains('missing-tool'));
      expect(message, contains('宿主应用支持的工具链命令'));
      expect(message, isNot(contains('Java')));
    },
  );
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: StudioLocalizations.supportedLocales,
  localizationsDelegates: const [
    StudioLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: home,
);

ApiClient _client(List<http.Request> requests) => ApiClient(
  transport: MockClient((request) async {
    requests.add(request);
    final body = request.url.path.endsWith('/checkins')
        ? {
            'days': [
              {'date': '2026-10-15'},
            ],
          }
        : {
            'day': '2026-10-15',
            'points': 10,
            'streak': 0,
            'checkedToday': false,
            'growth': {'experience': 10},
            'reward': 10,
            'duplicate': false,
            'alreadyChecked': false,
            'tasks': <Object>[],
          };
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

class _RefreshSpyAuth extends AuthStore {
  _RefreshSpyAuth({required super.storageFile});
  int refreshCalls = 0;

  @override
  Future<void> refreshMe() async => refreshCalls++;
}

class _Fixture {
  _Fixture(this.root, this.auth);
  final Directory root;
  final _RefreshSpyAuth auth;
  File get tasks => File('${root.path}/tasks.json');

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'qfli_offline_background_',
    );
    final file = File('${root.path}/auth.json');
    final original = AuthStore(storageFile: file);
    await original.load();
    await original.signIn('restored-token', _user);
    original.dispose();
    final restored = _RefreshSpyAuth(storageFile: file);
    await restored.load();
    return _Fixture(root, restored);
  }

  TaskActivityService activity(ApiClient client) => TaskActivityService(
    storageFile: tasks,
    client: client,
    clock: () => DateTime(2026, 10, 15),
  );

  Future<void> dispose() async {
    auth.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
