// R1 picker regressions for cloud CI. Not executed locally.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/github/github_auth_controller.dart';
import 'package:qfli_studio_core/github/github_models.dart';
import 'package:qfli_studio_core/pages/git/github_repository_picker.dart';
import 'package:qfli_studio_core/services/git_clone_service.dart';

void main() {
  testWidgets('OAuth is default and PAT input remains obscured', (
    tester,
  ) async {
    final auth = _PickerAuth(signedIn: false);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(home: GitHubRepositoryPicker(controller: auth)),
    );
    expect(find.byKey(const ValueKey('github-oauth-connect')), findsOneWidget);
    expect(find.byKey(const ValueKey('github-pat')), findsNothing);
    await tester.tap(find.text('个人访问令牌'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('github-pat')),
    );
    expect(field.obscureText, isTrue);
    expect(field.enableSuggestions, isFalse);
    expect(field.autocorrect, isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('github-pat')),
      'ci-only-token',
    );
    // The connect button is disabled while the field is empty, and enterText
    // does not pump a frame after it types. Without this pump the tap lands on
    // the stale disabled button and the token never reaches the controller.
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('github-pat-connect')));
    await tester.pump();
    expect(auth.patReceived, 'ci-only-token');
    expect(find.text('ci-only-token'), findsNothing);
  });

  testWidgets(
    'loads another page and returns independent selected clone requests',
    (tester) async {
      final auth = _PickerAuth();
      addTearDown(auth.dispose);
      List<GitCloneRequest>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showGitHubRepositoryPicker(
                    context,
                    controller: auth,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('github-repository-1')));
      await tester.tap(find.byKey(const ValueKey('github-load-more')));
      await tester.pumpAndSettle();
      expect(auth.nextPages, 1);
      await tester.ensureVisible(
        find.byKey(const ValueKey('github-repository-2')),
      );
      await tester.tap(find.byKey(const ValueKey('github-repository-2')));
      await tester.tap(find.byKey(const ValueKey('github-clone-selected')));
      await tester.pumpAndSettle();
      expect(result, hasLength(2));
      expect(result!.map((r) => r.url), [
        'https://github.com/one/repo.git',
        'https://github.com/two/repo.git',
      ]);
      expect(result!.map((r) => r.token).toSet(), {'ci-only-token'});
      expect(result!.every((r) => !r.url.contains('ci-only-token')), isTrue);
      expect(
        result!.every((r) => !r.toString().contains('ci-only-token')),
        isTrue,
      );
      expect(auth.selectedRepositoryIds, isEmpty);
    },
  );

  testWidgets('disconnect clears selected rows and removes clone handoff', (
    tester,
  ) async {
    final auth = _PickerAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(home: GitHubRepositoryPicker(controller: auth)),
    );
    await tester.tap(find.byKey(const ValueKey('github-repository-1')));
    await tester.pump();
    expect(auth.selectedRepositoryIds, {1});
    await tester.tap(find.byKey(const ValueKey('github-disconnect')));
    await tester.pumpAndSettle();
    expect(auth.selectedRepositoryIds, isEmpty);
    expect(find.byKey(const ValueKey('github-clone-selected')), findsNothing);
    expect(find.byKey(const ValueKey('github-repository-1')), findsNothing);
  });

  testWidgets('picker scrolls on narrow large-text layout without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _PickerAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: GitHubRepositoryPicker(controller: auth),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('github-repositories')), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

/// Presentation fake. Service-level auth/generation/pagination regressions are
/// A-owned. This fake changes only what this screen should render or return.
class _PickerAuth extends GitHubAuthController {
  _PickerAuth({bool signedIn = true}) : _signedIn = signedIn;
  bool _signedIn;
  int nextPages = 0;
  String? patReceived;
  final Set<int> _selected = {};
  final List<GitHubRepository> _rows = [_repository(1, 'one')];

  static GitHubRepository _repository(int id, String owner) => GitHubRepository(
    id: id,
    name: 'repo',
    fullName: '$owner/repo',
    ownerLogin: owner,
    isPrivate: id == 2,
    htmlUrl: 'https://github.com/$owner/repo',
    cloneUrl: 'https://github.com/$owner/repo.git',
    description: 'Repository $id',
    defaultBranch: 'main',
    archived: false,
  );

  @override
  GitHubAuthStatus get status =>
      _signedIn ? GitHubAuthStatus.authenticated : GitHubAuthStatus.signedOut;
  @override
  GitHubAccount? get account => null;
  @override
  GitHubDeviceAuthorization? get deviceAuthorization => null;
  @override
  String? get errorMessage => null;
  @override
  bool get isBusy => false;
  @override
  bool get isLoadingRepositories => false;
  @override
  bool get hasMoreRepositories => nextPages == 0;
  @override
  List<GitHubRepository> get repositories =>
      _signedIn ? List.unmodifiable(_rows) : [];
  @override
  Set<int> get selectedRepositoryIds => Set.unmodifiable(_selected);
  @override
  List<GitHubRepository> get selectedRepositories =>
      repositories.where((row) => _selected.contains(row.id)).toList();
  @override
  Future<void> cancelDeviceOAuth() async {}
  @override
  Future<void> signInWithPat(String pat) async {
    patReceived = pat;
  }

  @override
  Future<void> disconnect() async {
    _signedIn = false;
    _selected.clear();
    _rows.clear();
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
  Future<void> loadNextRepositoryPage() async {
    nextPages++;
    _rows.add(_repository(2, 'two'));
    notifyListeners();
  }

  @override
  void clearSelection() {
    _selected.clear();
    notifyListeners();
  }

  @override
  void selectVisibleRepositories() {
    _selected.addAll(_rows.map((row) => row.id));
    notifyListeners();
  }

  @override
  GitCloneRequest? buildCloneRequest(GitHubRepository repository) =>
      !_signedIn || !_selected.contains(repository.id)
      ? null
      : GitCloneRequest(
          url: repository.cloneUrl,
          name: repository.fullName,
          username: 'ci-user',
          token: 'ci-only-token',
        );
}
