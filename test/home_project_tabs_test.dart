import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/pages/home_project_tabs.dart';
import 'package:qfli_studio_core/services/local_store_backend.dart';
import 'package:qfli_studio_core/services/project_templates.dart';
import 'package:qfli_studio_core/services/studio_profile.dart';

/// Contract for the Home project tab order (R3, R4).
///
/// Three behaviours are pinned here: the default order, the tolerance of a saved
/// order (unknown identifiers dropped, missing scopes appended), and the
/// round trip through the store the app actually uses.
void main() {
  StudioProfile profile({
    bool offlineOnly = false,
    bool supportsSavedWorkspaces = true,
  }) => StudioProfile(
    id: 'java',
    appTitle: 'QFLIJVMX',
    templates: const [ProjectTemplate.java],
    isOffline: true,
    offlineOnly: offlineOnly,
    supportsSavedWorkspaces: supportsSavedWorkspaces,
    productKey: StudioProductCatalog.jvmxKey,
  );

  // The user's order: history, workspace, all, favorite, cloud.
  const localOrder = [
    ProjectScope.history,
    ProjectScope.workspace,
    ProjectScope.all,
    ProjectScope.favorite,
    ProjectScope.cloud,
  ];

  group('default order', () {
    test('a networked product keeps project order and appends Agents', () {
      expect(defaultProjectScopes(profile()), [
        ...localOrder,
        ProjectScope.agents,
      ]);
    });

    test('history is the first tab, so it is the page shown at launch', () {
      expect(defaultProjectScopes(profile()).first, ProjectScope.history);
      expect(
        defaultProjectScopes(profile(offlineOnly: true)).first,
        ProjectScope.history,
      );
      expect(
        defaultProjectScopes(profile(supportsSavedWorkspaces: false)).first,
        ProjectScope.history,
      );
    });

    test('no saved order resolves to the default order', () {
      expect(resolveProjectScopes(const [], localOrder), localOrder);
    });

    test('an offline-only product drops the cloud scope', () {
      expect(defaultProjectScopes(profile(offlineOnly: true)), [
        ProjectScope.history,
        ProjectScope.workspace,
        ProjectScope.all,
        ProjectScope.favorite,
        ProjectScope.agents,
      ]);
    });

    test('a product without saved workspaces drops the workspace scope', () {
      expect(defaultProjectScopes(profile(supportsSavedWorkspaces: false)), [
        ProjectScope.history,
        ProjectScope.all,
        ProjectScope.favorite,
        ProjectScope.cloud,
        ProjectScope.agents,
      ]);
    });
  });

  group('saved order', () {
    test('an older saved order retains its order and gains Agents once', () {
      expect(
        resolveProjectScopes([
          ProjectScope.favorite,
          ...localOrder,
        ], defaultProjectScopes(profile())),
        const [
          ProjectScope.favorite,
          ProjectScope.history,
          ProjectScope.workspace,
          ProjectScope.all,
          ProjectScope.cloud,
          ProjectScope.agents,
        ],
      );
    });

    test('is honoured when it names every available scope', () {
      const saved = [
        ProjectScope.cloud,
        ProjectScope.workspace,
        ProjectScope.favorite,
        ProjectScope.history,
        ProjectScope.all,
      ];
      expect(resolveProjectScopes(saved, localOrder), saved);
    });

    test('drops identifiers that are no longer available', () {
      const saved = [
        ProjectScope.cloud,
        ProjectScope.workspace,
        ProjectScope.favorite,
        ProjectScope.history,
        ProjectScope.all,
      ];
      expect(
        resolveProjectScopes(saved, const [
          ProjectScope.all,
          ProjectScope.history,
          ProjectScope.favorite,
        ]),
        const [ProjectScope.favorite, ProjectScope.history, ProjectScope.all],
      );
    });

    test('appends missing scopes in default order', () {
      expect(
        resolveProjectScopes(const [ProjectScope.favorite], localOrder),
        const [
          ProjectScope.favorite,
          ProjectScope.history,
          ProjectScope.workspace,
          ProjectScope.all,
          ProjectScope.cloud,
        ],
      );
    });

    test('ignores duplicates', () {
      expect(
        resolveProjectScopes(const [
          ProjectScope.history,
          ProjectScope.history,
          ProjectScope.all,
        ], localOrder),
        const [
          ProjectScope.history,
          ProjectScope.all,
          ProjectScope.workspace,
          ProjectScope.favorite,
          ProjectScope.cloud,
        ],
      );
    });

    test('always returns every available scope exactly once', () {
      final resolved = resolveProjectScopes(const [
        ProjectScope.cloud,
        ProjectScope.all,
        ProjectScope.cloud,
      ], localOrder);
      expect(resolved.toSet(), localOrder.toSet());
      expect(resolved, hasLength(localOrder.length));
    });
  });

  group('merging a drag into a saved order', () {
    // Saved order that has not been shown yet: cloud first.
    const applied = [
      ProjectScope.cloud,
      ProjectScope.favorite,
      ProjectScope.history,
      ProjectScope.workspace,
      ProjectScope.all,
    ];
    // What the default order looked like, and the same list after dragging
    // 全部项目 from its slot onto 收藏项目.
    const draggedAll = [
      ProjectScope.history,
      ProjectScope.workspace,
      ProjectScope.favorite,
      ProjectScope.all,
      ProjectScope.cloud,
    ];

    test('keeps the saved positions and moves only the dragged scope', () {
      expect(
        mergeProjectScopeOrder(
          previous: localOrder,
          applied: applied,
          next: draggedAll,
          available: localOrder,
          moved: ProjectScope.all,
        ),
        const [
          ProjectScope.cloud,
          ProjectScope.favorite,
          ProjectScope.all,
          ProjectScope.history,
          ProjectScope.workspace,
        ],
      );
    });

    test('a scope dragged to the front goes in front of the saved order', () {
      const next = [
        ProjectScope.cloud,
        ProjectScope.history,
        ProjectScope.workspace,
        ProjectScope.all,
        ProjectScope.favorite,
      ];
      expect(
        mergeProjectScopeOrder(
          previous: localOrder,
          applied: applied,
          next: next,
          available: localOrder,
          moved: ProjectScope.cloud,
        ),
        const [
          ProjectScope.cloud,
          ProjectScope.favorite,
          ProjectScope.history,
          ProjectScope.workspace,
          ProjectScope.all,
        ],
      );
    });

    test('without a saved order the dragged order is stored as is', () {
      expect(
        mergeProjectScopeOrder(
          previous: localOrder,
          applied: const [],
          next: draggedAll,
          available: localOrder,
          moved: ProjectScope.all,
        ),
        draggedAll,
      );
    });

    test('a change that is not that drag is stored as shown', () {
      // The two lists differ by more than moving 全部项目; keeping the drag is
      // safer than inventing a merge.
      const next = [
        ProjectScope.cloud,
        ProjectScope.workspace,
        ProjectScope.favorite,
        ProjectScope.history,
        ProjectScope.all,
      ];
      expect(
        mergeProjectScopeOrder(
          previous: localOrder,
          applied: applied,
          next: next,
          available: localOrder,
          moved: ProjectScope.all,
        ),
        next,
      );
    });

    test('a scope that is not on screen cannot be merged', () {
      expect(
        mergeProjectScopeOrder(
          previous: const [ProjectScope.all, ProjectScope.history],
          applied: applied,
          next: const [ProjectScope.cloud, ProjectScope.all],
          available: localOrder,
          moved: ProjectScope.workspace,
        ),
        const [ProjectScope.cloud, ProjectScope.all],
      );
    });

    test('the merged order still covers every available scope once', () {
      final merged = mergeProjectScopeOrder(
        previous: localOrder,
        applied: applied,
        next: draggedAll,
        available: const [
          ProjectScope.all,
          ProjectScope.history,
          ProjectScope.favorite,
        ],
        moved: ProjectScope.all,
      );
      expect(merged, const [
        ProjectScope.favorite,
        ProjectScope.all,
        ProjectScope.history,
      ]);
    });
  });

  group('HomeTabOrderStore', () {
    test('Agents order uses its stable identifier across restarts', () async {
      final backend = LocalMemoryBackend();
      final first = HomeTabOrderStore(backend: backend);
      await first.save(const [ProjectScope.agents, ...localOrder]);
      final payload = jsonDecode(backend.payload!) as Map<String, dynamic>;
      expect((payload['order'] as List).first, 'agents');

      final second = HomeTabOrderStore(backend: backend);
      await second.load();
      expect(second.order, const [ProjectScope.agents, ...localOrder]);
    });

    test('starts empty and reports no saved order', () async {
      final store = HomeTabOrderStore(backend: LocalMemoryBackend());
      await store.load();
      expect(store.isLoaded, isTrue);
      expect(store.order, isEmpty);
      expect(resolveProjectScopes(store.order, localOrder), localOrder);
    });

    test('persists the order and reads it back in a new store', () async {
      final backend = LocalMemoryBackend();
      final first = HomeTabOrderStore(backend: backend);
      await first.load();
      await first.save(const [
        ProjectScope.favorite,
        ProjectScope.all,
        ProjectScope.history,
        ProjectScope.workspace,
        ProjectScope.cloud,
      ]);

      final second = HomeTabOrderStore(backend: backend);
      await second.load();
      expect(second.order, const [
        ProjectScope.favorite,
        ProjectScope.all,
        ProjectScope.history,
        ProjectScope.workspace,
        ProjectScope.cloud,
      ]);
    });

    test('stores stable identifiers rather than indices', () async {
      final backend = LocalMemoryBackend();
      final store = HomeTabOrderStore(backend: backend);
      await store.load();
      await store.save(const [ProjectScope.cloud, ProjectScope.all]);
      final payload = jsonDecode(backend.payload!) as Map<String, dynamic>;
      expect(payload['version'], HomeTabOrderStore.schemaVersion);
      expect(payload['order'], ['cloud', 'all']);
    });

    test('keeps the last of several quick saves', () async {
      final backend = LocalMemoryBackend();
      final store = HomeTabOrderStore(backend: backend);
      await store.load();
      await store.save(const [ProjectScope.history, ProjectScope.all]);
      await store.save(const [ProjectScope.cloud, ProjectScope.all]);
      expect(store.order, const [ProjectScope.cloud, ProjectScope.all]);
      final reread = HomeTabOrderStore(backend: backend);
      await reread.load();
      expect(reread.order, const [ProjectScope.cloud, ProjectScope.all]);
    });

    test('a corrupt payload falls back to no saved order', () async {
      final backend = LocalMemoryBackend('{not json');
      final store = HomeTabOrderStore(backend: backend);
      await store.load();
      expect(store.isLoaded, isTrue);
      expect(store.order, isEmpty);
    });

    test('unknown identifiers in a payload are dropped, not fatal', () async {
      final backend = LocalMemoryBackend(
        jsonEncode({
          'version': 1,
          'order': ['cloud', 'gone', 'all'],
        }),
      );
      final store = HomeTabOrderStore(backend: backend);
      await store.load();
      expect(store.order, const [ProjectScope.cloud, ProjectScope.all]);
    });
  });
}
