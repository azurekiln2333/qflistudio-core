import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/local_store_backend.dart';
import '../services/studio_profile.dart';

/// The project scopes Home can list.
///
/// [name] is the stable identifier persisted in `home_project_tabs.json`. Never
/// rename a value: saved orders are read back by identifier and an unknown one
/// is dropped.
enum ProjectScope { all, history, favorite, workspace, cloud }

/// The scopes a product offers, in the order Home sorts them by default.
///
/// The cloud scope is a server feature, so it follows the same switch that
/// hides the server surfaces in general; workspaces are purely local and follow
/// their own opt-out.
List<ProjectScope> defaultProjectScopes(StudioProfile? profile) => [
  ProjectScope.all,
  ProjectScope.history,
  ProjectScope.favorite,
  if (profile?.supportsSavedWorkspaces ?? true) ProjectScope.workspace,
  // The scope only appears for networked products, matching the old rule that
  // kept it out of offline-only builds.
  if (profile?.offlineOnly != true) ProjectScope.cloud,
];

/// Folds a saved order and the scopes a product currently offers into the order
/// Home renders.
///
/// Saved identifiers that are unknown, duplicated or unavailable are dropped;
/// every available scope the saved order does not name is appended in default
/// order. An empty (or missing) saved order therefore yields
/// [defaultProjectScopes], and a product that gains or loses a scope never shows
/// a broken bar.
List<ProjectScope> resolveProjectScopes(
  Iterable<ProjectScope> savedOrder,
  List<ProjectScope> available,
) {
  final ordered = <ProjectScope>[];
  for (final scope in savedOrder) {
    if (!available.contains(scope) || ordered.contains(scope)) continue;
    ordered.add(scope);
  }
  for (final scope in available) {
    if (!ordered.contains(scope)) ordered.add(scope);
  }
  return ordered;
}

/// The order to persist after a drag that happened before the saved order was
/// read, folding the drag into it.
///
/// [applied] is the saved order (empty when there is none), [previous] the order
/// that was on screen before the drag, [next] the order the user dragged to and
/// [moved] the scope the user dragged. Every other scope keeps the position it
/// has in [applied] and only [moved] moves, so dragging one tab does not snap
/// the untouched tabs back to the default order on the next start. When the two
/// lists do not differ by exactly that drag, [next] is returned unchanged.
List<ProjectScope> mergeProjectScopeOrder({
  required List<ProjectScope> previous,
  required List<ProjectScope> applied,
  required List<ProjectScope> next,
  required List<ProjectScope> available,
  required ProjectScope moved,
}) {
  if (applied.isEmpty) return next;
  List<ProjectScope> without(List<ProjectScope> scopes) => [
    for (final scope in scopes)
      if (scope != moved) scope,
  ];
  if (!previous.contains(moved) || !next.contains(moved)) return next;
  if (!listEquals(without(previous), without(next))) return next;
  final ordered = without(resolveProjectScopes(applied, available));
  final target = next.indexOf(moved);
  if (target <= 0) {
    ordered.insert(0, moved);
  } else {
    // Keep [moved] right after the neighbour it now follows.
    final after = ordered.indexOf(next[target - 1]);
    ordered.insert(after < 0 ? ordered.length : after + 1, moved);
  }
  return resolveProjectScopes(ordered, available);
}

/// Persists the user's Home tab order.
///
/// One small JSON file behind [LocalStoreBackend], keeping the same layout the
/// other local stores use. The payload is `{"version": 1, "order": [...]}`; a
/// corrupt or older payload is treated as "no saved order" rather than an error,
/// because losing a cosmetic preference must never block Home.
///
/// Home reads the order as soon as [canReadNow] allows it and otherwise on the
/// first drag, so a start whose storage location is already resolved shows the
/// saved order, and a start that is still probing does not wait on it.
class HomeTabOrderStore {
  HomeTabOrderStore({LocalStoreBackend? backend})
    : _backend = backend ?? const LocalFileBackend('home_project_tabs.json');

  static const int schemaVersion = 1;

  final LocalStoreBackend _backend;

  List<ProjectScope> _order = const [];
  Future<void>? _loading;
  Future<void>? _writes;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Whether [load] can read right now instead of starting a storage probe.
  bool get canReadNow => _backend.isReady;

  /// The saved order as far as it could be read; empty before [load] runs.
  List<ProjectScope> get order => List.unmodifiable(_order);

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final payload = await _backend.read();
      if (payload != null) _order = _decode(payload);
    } catch (_) {
      // A corrupt file only costs the saved order, never the app.
      _order = const [];
    }
    _loaded = true;
  }

  static List<ProjectScope> _decode(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return const [];
    final raw = decoded['order'];
    if (raw is! List) return const [];
    final byName = {for (final scope in ProjectScope.values) scope.name: scope};
    final order = <ProjectScope>[];
    for (final entry in raw) {
      if (entry is! String) continue;
      final scope = byName[entry];
      if (scope == null || order.contains(scope)) continue;
      order.add(scope);
    }
    return order;
  }

  /// Replaces the saved order. Later calls win; the intermediate order of a
  /// drag that fires several updates never reaches the disk twice.
  Future<void> save(List<ProjectScope> order) {
    _order = List.unmodifiable(order);
    _loaded = true;
    final encoded = jsonEncode({
      'version': schemaVersion,
      'order': [for (final scope in order) scope.name],
    });
    final previous = _writes;
    final write = previous == null
        ? _backend.write(encoded)
        : previous
              .catchError((Object _) {})
              .then((_) => _backend.write(encoded));
    return _writes = write;
  }
}
