// Cloud CI regressions. Do not execute product tests locally.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/github/github_auth_controller.dart';
import 'package:qfli_studio_core/github/github_models.dart';
import 'package:qfli_studio_core/github/github_scope.dart';
import 'package:qfli_studio_core/pages/git/github_connection_panel.dart';
import 'package:qfli_studio_core/pages/git/github_repository_list.dart';
import 'package:qfli_studio_core/pages/git/github_repository_picker.dart';
import 'package:qfli_studio_core/pages/profile_page.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';
import 'package:qfli_studio_core/store/auth_store.dart';
import 'package:qfli_studio_core/store/project_store.dart';
import 'package:qfli_studio_core/store/settings_store.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Widget _panel(_WidgetAuth auth, {bool active = true, bool ticking = true}) =>
    MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: ticking,
          child: Offstage(
            offstage: !ticking,
            child: SingleChildScrollView(
              child: GitHubConnectionPanel(controller: auth, isActive: active),
            ),
          ),
        ),
      ),
    );

void main() {
  late StudioProfile? previousProfile;

  setUp(() {
    previousProfile = StudioProfile.current;
    StudioProfile.current = null;
  });

  tearDown(() => StudioProfile.current = previousProfile);

  testWidgets('Profile connects GitHub while Studio remains signed out', (
    tester,
  ) async {
    final github = _WidgetAuth();
    final studio = AuthStore();
    final settings = SettingsStore();
    final projects = ProjectStore();
    addTearDown(github.dispose);
    addTearDown(studio.dispose);
    addTearDown(settings.dispose);
    addTearDown(projects.dispose);
    await tester.pumpWidget(
      GitHubScope(
        controller: github,
        child: MaterialApp(
          home: ProfileTab(auth: studio, settings: settings, store: projects),
        ),
      ),
    );
    expect(studio.isLoggedIn, isFalse);
    expect(find.text('未登录'), findsOneWidget);
    expect(_key('github-oauth-connect'), findsOneWidget);
    await tester.tap(find.text('个人访问令牌'));
    await tester.pump();
    final field = tester.widget<TextField>(_key('github-pat'));
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    await tester.enterText(_key('github-pat'), 'ci-token');
    await tester.pump();
    await tester.ensureVisible(_key('github-pat-connect'));
    await tester.tap(_key('github-pat-connect'));
    await tester.pumpAndSettle();
    expect(github.patReceived, 'ci-token');
    expect(github.status, GitHubAuthStatus.authenticated);
    expect(find.text('octocat'), findsOneWidget);
    expect(studio.isLoggedIn, isFalse);
    expect(find.text('ci-token'), findsNothing);
    expect(github.restores, 0);
    await tester.pumpWidget(const SizedBox());
    expect(github.disposals, 0);
  });

  testWidgets(
    'offline Profile omits GitHub even with an app-owned connection',
    (tester) async {
      StudioProfile.current = const StudioProfile(
        id: 'offline',
        appTitle: 'Offline',
        templates: [],
        offlineOnly: true,
      );
      final github = _WidgetAuth(signedIn: true);
      final studio = AuthStore();
      final settings = SettingsStore();
      final projects = ProjectStore();
      addTearDown(github.dispose);
      addTearDown(studio.dispose);
      addTearDown(settings.dispose);
      addTearDown(projects.dispose);
      await tester.pumpWidget(
        GitHubScope(
          controller: github,
          child: MaterialApp(
            home: ProfileTab(auth: studio, settings: settings, store: projects),
          ),
        ),
      );
      expect(
        find.byType(GitHubConnectionPanel, skipOffstage: false),
        findsNothing,
      );
      expect(find.text('本机记录'), findsOneWidget);
      expect(github.restores, 0);
      expect(github.cancels, 0);
      expect(github.hasConnection, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Profile reconnects and disconnects an expired GitHub connection',
    (tester) async {
      final auth = _WidgetAuth()..expireConnection();
      addTearDown(auth.dispose);
      await tester.pumpWidget(_panel(auth));
      expect(_key('github-disconnect'), findsOneWidget);
      await tester.tap(_key('github-reconnect'));
      await tester.pump();
      await tester.tap(find.text('个人访问令牌'));
      await tester.pump();
      await tester.enterText(_key('github-pat'), 'replacement-token');
      await tester.pump();
      await tester.ensureVisible(_key('github-pat-connect'));
      await tester.tap(_key('github-pat-connect'));
      await tester.pumpAndSettle();
      expect(find.text('octocat'), findsOneWidget);
      expect(_key('github-pat'), findsNothing);
      await tester.tap(_key('github-disconnect'));
      await tester.pumpAndSettle();
      expect(auth.hasConnection, isFalse);
      expect(auth.disconnects, 1);
      expect(find.text('octocat'), findsNothing);
    },
  );

  for (final awaitingCode in [false, true]) {
    testWidgets(
      'hidden retained panel cancels owned OAuth (code ready: $awaitingCode)',
      (tester) async {
        final auth = _WidgetAuth();
        addTearDown(auth.dispose);
        await tester.pumpWidget(_panel(auth));
        final state = tester.state(find.byType(GitHubConnectionPanel));
        await tester.tap(_key('github-oauth-connect'));
        await tester.pump();
        if (awaitingCode) {
          auth.showDeviceCode();
          await tester.pump();
          expect(find.text('ABCD-EFGH'), findsOneWidget);
        }
        await tester.pumpWidget(_panel(auth, ticking: false));
        await tester.pump();
        expect(
          tester.state(find.byType(GitHubConnectionPanel, skipOffstage: false)),
          same(state),
        );
        expect(auth.cancels, 1);
        expect(auth.status, GitHubAuthStatus.signedOut);
        expect(auth.disposals, 0);
        await tester.pumpWidget(_panel(auth));
        expect(_key('github-oauth-connect'), findsOneWidget);
        expect(auth.starts, 1);
        await tester.pumpWidget(const SizedBox());
        expect(auth.cancels, 1);
      },
    );
  }

  testWidgets(
    'explicit inactivity and route disposal cancel only the owned flow',
    (tester) async {
      final auth = _WidgetAuth();
      addTearDown(auth.dispose);
      await tester.pumpWidget(_panel(auth));
      await tester.tap(_key('github-oauth-connect'));
      await tester.pump();
      await tester.pumpWidget(_panel(auth, active: false));
      await tester.pump();
      expect(auth.cancels, 1);
      await tester.pumpWidget(_panel(auth));
      await tester.tap(_key('github-oauth-connect'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(auth.cancels, 2);
      expect(auth.disposals, 0);
    },
  );

  testWidgets('covering Profile with another route cancels its device flow', (
    tester,
  ) async {
    final auth = _WidgetAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(_panel(auth));
    await tester.tap(_key('github-oauth-connect'));
    await tester.pump();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(auth.cancels, 1);
    expect(find.text('Another page'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(_key('github-oauth-connect'), findsOneWidget);
  });

  testWidgets(
    'panel leaves foreign auth and shared repository requests alive',
    (tester) async {
      final auth = _WidgetAuth()..showExternalLoading();
      addTearDown(auth.dispose);
      await tester.pumpWidget(_panel(auth));
      await tester.pumpWidget(_panel(auth, ticking: false));
      await tester.pumpWidget(const SizedBox());
      expect(auth.cancels, 0);
      expect(auth.status, GitHubAuthStatus.loading);
      auth.authenticate();
      auth.loadingRepositories = true;
      await tester.pumpWidget(_panel(auth));
      await tester.pumpWidget(const SizedBox());
      expect(auth.cancels, 0);
      expect(auth.loadingRepositories, isTrue);
      expect(auth.disposals, 0);
    },
  );

  testWidgets('hiding a panel clears an unsubmitted PAT', (tester) async {
    final auth = _WidgetAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(_panel(auth));
    await tester.tap(find.text('个人访问令牌'));
    await tester.pump();
    await tester.enterText(_key('github-pat'), 'unsubmitted-secret');
    await tester.pumpWidget(_panel(auth, ticking: false));
    await tester.pumpWidget(_panel(auth));
    expect(
      tester.widget<TextField>(_key('github-pat')).controller!.text,
      isEmpty,
    );
    expect(auth.patReceived, isNull);
    expect(auth.cancels, 0);
  });

  testWidgets('old OAuth polling cannot cancel a newer shared auth request', (
    tester,
  ) async {
    final auth = _WidgetAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(_panel(auth));
    await tester.tap(_key('github-oauth-connect'));
    await tester.pump();
    // Disconnect invalidates the old request, but its polling sleep has not
    // completed. A different consumer starts another auth operation meanwhile.
    await auth.disconnect();
    auth.showExternalLoading();
    await tester.pumpWidget(_panel(auth, ticking: false));
    await tester.pump();
    expect(auth.cancels, 0);
    expect(auth.status, GitHubAuthStatus.loading);
    auth.finishDeviceRequest();
    await tester.pumpWidget(const SizedBox());
    expect(auth.cancels, 0);
  });

  testWidgets('controller replacement cancels the old panel flow only', (
    tester,
  ) async {
    final oldAuth = _WidgetAuth();
    final newAuth = _WidgetAuth()..showExternalLoading();
    addTearDown(oldAuth.dispose);
    addTearDown(newAuth.dispose);
    await tester.pumpWidget(_panel(oldAuth));
    await tester.tap(_key('github-oauth-connect'));
    await tester.pump();
    await tester.pumpWidget(_panel(newAuth));
    await tester.pump();
    expect(oldAuth.cancels, 1);
    expect(newAuth.cancels, 0);
    expect(newAuth.status, GitHubAuthStatus.loading);
    await tester.pumpWidget(const SizedBox());
    expect(oldAuth.disposals, 0);
    expect(newAuth.disposals, 0);
  });

  testWidgets('completed OAuth retains the connection when Profile is hidden', (
    tester,
  ) async {
    final auth = _WidgetAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(_panel(auth));
    await tester.tap(_key('github-oauth-connect'));
    auth.showDeviceCode();
    await tester.pump();
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    auth.authenticate();
    auth.finishDeviceRequest();
    await tester.pumpAndSettle();
    expect(find.text('octocat'), findsOneWidget);
    await tester.pumpWidget(_panel(auth, ticking: false));
    await tester.pumpWidget(const SizedBox());
    expect(auth.hasConnection, isTrue);
    expect(auth.cancels, 0);
    expect(auth.disposals, 0);
  });

  testWidgets('list filters pages and preserves the query through refresh', (
    tester,
  ) async {
    final auth = _WidgetAuth(signedIn: true);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GitHubRepositoryList(
            controller: auth,
            onOpenRepository: (_) async {},
            onConnect: () {},
          ),
        ),
      ),
    );
    await tester.enterText(_key('github-search'), 'SECOND');
    await tester.pump();
    expect(find.text('one/repo'), findsNothing);
    await tester.tap(_key('github-load-more'));
    await tester.pumpAndSettle();
    expect(auth.nextPages, 1);
    expect(find.text('two/repo'), findsOneWidget);
    expect(find.text('one/repo'), findsNothing);
    await tester.tap(_key('github-refresh'));
    await tester.pumpAndSettle();
    expect(auth.refreshes, 1);
    expect(
      tester.widget<TextField>(_key('github-search')).controller!.text,
      'SECOND',
    );
    expect(find.text('two/repo'), findsNothing);
    expect(_key('github-load-more'), findsOneWidget);
    await tester.tap(_key('github-load-more'));
    await tester.pumpAndSettle();
    expect(find.text('two/repo'), findsOneWidget);
  });

  testWidgets(
    'clone failure retries inline and a mapped repository opens locally',
    (tester) async {
      final auth = _WidgetAuth(signedIn: true);
      final observer = _NavigationObserver();
      final clone = Completer<void>();
      var attempts = 0;
      var mapped = false;
      final opened = <int>[];
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: StatefulBuilder(
            builder: (context, updateHost) => Scaffold(
              body: GitHubRepositoryList(
                controller: auth,
                onConnect: () {},
                actionLabel: (_) => mapped ? 'Open local project' : null,
                progress: const Text('Host clone progress'),
                onOpenRepository: (repository) async {
                  attempts++;
                  if (mapped) {
                    opened.add(repository.id);
                  } else if (attempts == 1) {
                    await clone.future;
                  } else {
                    updateHost(() => mapped = true);
                  }
                },
              ),
            ),
          ),
        ),
      );
      await tester.enterText(_key('github-search'), 'one');
      await tester.pump();
      await tester.tap(_key('github-open-1'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(_key('github-open-1')).onPressed,
        isNull,
      );
      expect(find.text('Host clone progress'), findsOneWidget);
      clone.completeError(StateError('transport reflected ci-private-token'));
      await tester.pumpAndSettle();
      expect(find.text('GitHub 请求失败，请重试'), findsOneWidget);
      expect(find.textContaining('ci-private-token'), findsNothing);
      expect(
        tester.widget<TextField>(_key('github-search')).controller!.text,
        'one',
      );
      await tester.tap(_key('github-open-1'));
      await tester.pumpAndSettle();
      expect(find.text('Open local project'), findsOneWidget);
      expect(_key('github-error'), findsNothing);
      await tester.tap(_key('github-open-1'));
      await tester.pumpAndSettle();
      expect(opened, [1]);
      expect(observer.pushes, 1);
      expect(observer.pops, 0);
      expect(find.byType(GitHubRepositoryPicker), findsNothing);
    },
  );

  testWidgets(
    'expired list delegates reconnect and never cancels shared work',
    (tester) async {
      final auth = _WidgetAuth()..expireConnection();
      var connections = 0;
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GitHubRepositoryList(
              controller: auth,
              onOpenRepository: (_) async =>
                  fail('Expired repositories must not open'),
              onConnect: () => connections++,
            ),
          ),
        ),
      );
      await tester.tap(_key('github-connect'));
      expect(connections, 1);
      expect(_key('github-open-1'), findsNothing);
      auth.authenticate();
      auth.loadingRepositories = true;
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(auth.cancels, 0);
      expect(auth.loadingRepositories, isTrue);
      expect(auth.disposals, 0);
    },
  );

  testWidgets(
    'standalone picker consumes scope without owning shared controller',
    (tester) async {
      final auth = _WidgetAuth(signedIn: true);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        GitHubScope(
          controller: auth,
          child: const MaterialApp(home: GitHubRepositoryPicker()),
        ),
      );
      await tester.tap(_key('github-repository-1'));
      await tester.pump();
      expect(auth.selectedRepositoryIds, {1});
      await tester.pumpWidget(const SizedBox());
      expect(auth.cancels, 0);
      expect(auth.disposals, 0);
      expect(auth.restores, 0);
    },
  );

  testWidgets(
    'inline controls remain scrollable at sidebar width with a keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(300, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = _WidgetAuth(signedIn: true);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: GitHubRepositoryList(
              controller: auth,
              onOpenRepository: (_) async {},
              onConnect: () {},
            ),
          ),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_key('github-open-1'));
      await tester.tap(_key('github-open-1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await auth.disconnect();
      await tester.pumpWidget(_panel(auth));
      await tester.tap(find.text('个人访问令牌'));
      await tester.pump();
      await tester.ensureVisible(_key('github-pat'));
      expect(tester.takeException(), isNull);
    },
  );
}

class _NavigationObserver extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

/// UI fake: no secure storage, browser, network, filesystem or native clone.
class _WidgetAuth extends GitHubAuthController {
  _WidgetAuth({bool signedIn = false})
    : _status = signedIn
          ? GitHubAuthStatus.authenticated
          : GitHubAuthStatus.signedOut,
      _hasConnection = signedIn;

  GitHubAuthStatus _status;
  bool _hasConnection;
  Completer<void>? _deviceFlow;
  GitHubDeviceAuthorization? _device;
  String? patReceived;
  int starts = 0;
  int cancels = 0;
  int disposals = 0;
  int disconnects = 0;
  int restores = 0;
  int refreshes = 0;
  int nextPages = 0;
  bool loadingRepositories = false;
  bool _more = true;
  final _selected = <int>{};
  final _rows = <GitHubRepository>[_repository(1, 'one', 'First project')];

  @override
  GitHubAuthStatus get status => _status;
  @override
  bool get hasConnection => _hasConnection;
  @override
  bool get isBusy =>
      _status == GitHubAuthStatus.loading ||
      _status == GitHubAuthStatus.awaitingDeviceAuthorization;
  @override
  GitHubAccount? get account => _status == GitHubAuthStatus.authenticated
      ? const GitHubAccount(id: 1, login: 'octocat')
      : null;
  @override
  GitHubDeviceAuthorization? get deviceAuthorization => _device;
  @override
  String? get errorMessage =>
      _status == GitHubAuthStatus.error ? 'Connection expired' : null;
  @override
  List<GitHubRepository> get repositories => List.unmodifiable(_rows);
  @override
  bool get isLoadingRepositories => loadingRepositories;
  @override
  bool get hasMoreRepositories => _more;
  @override
  Set<int> get selectedRepositoryIds => Set.unmodifiable(_selected);

  void authenticate() {
    _status = GitHubAuthStatus.authenticated;
    _hasConnection = true;
    notifyListeners();
  }

  void expireConnection() {
    _status = GitHubAuthStatus.error;
    _hasConnection = true;
    notifyListeners();
  }

  void showExternalLoading() {
    _status = GitHubAuthStatus.loading;
    notifyListeners();
  }

  void showDeviceCode() {
    _status = GitHubAuthStatus.awaitingDeviceAuthorization;
    _device = GitHubDeviceAuthorization(
      userCode: 'ABCD-EFGH',
      verificationUri: Uri.parse('https://github.com/login/device'),
      expiresAt: DateTime.utc(2030),
      pollingInterval: const Duration(seconds: 5),
    );
    notifyListeners();
  }

  void finishDeviceRequest() {
    _deviceFlow?.complete();
    _deviceFlow = null;
  }

  @override
  Future<void> restore() async => restores++;

  @override
  Future<void> beginDeviceOAuth() {
    starts++;
    _status = GitHubAuthStatus.loading;
    _deviceFlow = Completer<void>();
    notifyListeners();
    return _deviceFlow!.future;
  }

  @override
  Future<void> cancelDeviceOAuth() async {
    cancels++;
    _status = GitHubAuthStatus.signedOut;
    _device = null;
    finishDeviceRequest();
    notifyListeners();
  }

  @override
  Future<void> signInWithPat(String pat) async {
    patReceived = pat;
    authenticate();
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    _hasConnection = false;
    _status = GitHubAuthStatus.signedOut;
    _device = null;
    _selected.clear();
    notifyListeners();
  }

  @override
  Future<void> refreshRepositories() async {
    refreshes++;
    _rows.removeWhere((row) => row.id != 1);
    _more = true;
    notifyListeners();
  }

  @override
  Future<void> loadNextRepositoryPage() async {
    nextPages++;
    _rows.add(_repository(2, 'two', 'Second project'));
    _more = false;
    notifyListeners();
  }

  @override
  void setRepositorySelected(int repositoryId, bool selected) {
    if (selected) {
      _selected.add(repositoryId);
    } else {
      _selected.remove(repositoryId);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

GitHubRepository _repository(int id, String owner, String description) =>
    GitHubRepository(
      id: id,
      name: 'repo',
      fullName: '$owner/repo',
      ownerLogin: owner,
      isPrivate: id == 2,
      htmlUrl: 'https://github.com/$owner/repo',
      cloneUrl: 'https://github.com/$owner/repo.git',
      description: description,
    );
