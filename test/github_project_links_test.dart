import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/github/github_models.dart';
import 'package:qfli_studio_core/github/github_project_links.dart';
import 'package:qfli_studio_core/models/project.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';

const repository = GitHubRepository(
  id: 42,
  name: 'project',
  fullName: 'owner/project',
  ownerLogin: 'owner',
  isPrivate: true,
  htmlUrl: 'https://github.com/owner/project',
  cloneUrl: 'https://github.com/owner/project.git',
);

void main() {
  test(
    'link survives reload and follows registry identity after path moves',
    () async {
      final backend = LocalMemoryBackend();
      final links = GitHubProjectLinks(backend: backend);
      final project = Project(
        id: 'local-42',
        name: 'project',
        path: '/old/project',
        createdAt: DateTime(2026),
        lastOpenedAt: DateTime(2026),
      );
      await links.link(repository, project);
      expect(jsonDecode(backend.payload!), {
        'version': 1,
        'links': {'github.com:42': 'local-42'},
      });
      project.path = '/new/project';
      final restored = GitHubProjectLinks(backend: backend);
      await restored.load();
      expect(restored.projectFor(repository, [project]), same(project));
      expect(restored.projectFor(repository, []), isNull);
    },
  );

  test('old SSH and HTTPS remotes match without retaining credentials', () {
    for (final remote in [
      'git@github.com:OWNER/project.git',
      'ssh://git@github.com/owner/Project',
      'https://user:secret@github.com/owner/project.git',
    ]) {
      expect(
        GitHubProjectLinks.repositoryIdentity(remote),
        'github.com/owner/project',
      );
    }
    for (final remote in [
      '/owner/project',
      'https://github.com.evil/owner/project',
      'https://example.org/owner/project',
      'https://github.com/owner',
    ]) {
      expect(GitHubProjectLinks.repositoryIdentity(remote), isNull);
    }
  });

  test(
    'corrupt optional metadata leaves all projects available for lookup',
    () async {
      final links = GitHubProjectLinks(backend: LocalMemoryBackend('{broken'));
      await links.load();
      expect(links.projectFor(repository, []), isNull);
    },
  );
}
