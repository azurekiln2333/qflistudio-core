import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../config/api_config.dart';
import '../models/cloud_project.dart';
import '../models/project.dart';
import '../store/auth_store.dart';
import '../store/project_store.dart';
import 'api_client.dart';
import 'cloud_cache_service.dart';
import 'cloud_sync_service.dart';

export '../models/cloud_project.dart';

/// Account-scoped Home facade. All list merges use a store-issued ticket, so a
/// delayed refresh cannot reinsert a remotely deleted project or another login.
class CloudProjectActions extends ChangeNotifier {
  CloudProjectActions({
    required this.auth,
    required this.store,
    ApiClient? api,
    CloudCacheService? cache,
  }) : api = api ?? ApiClient.instance,
       cache = cache ?? CloudCacheService.instance {
    auth.addListener(_authChanged);
    _authChanged();
  }
  final AuthStore auth;
  final ProjectStore store;
  final ApiClient api;
  final CloudCacheService cache;
  String? _token;
  CloudProjectScope? _scope;
  CloudSession? _session;
  static final _bindings = Expando<_CloudAuthBinding>();
  _CloudAuthBinding get _binding => _bindings[auth] ??= _CloudAuthBinding(auth);
  bool _disposed = false;

  bool get available {
    if (_disposed || _session == null) return false;
    try {
      _session!.ensureCurrent();
      return true;
    } on CloudOperationException {
      return false;
    }
  }

  CloudProjectScope? get scope => _scope;
  List<Project> get projects =>
      !available ? [] : store.cloudProjectsFor(_scope!);

  void _authChanged() {
    if (_disposed) return;
    final session = _binding.capture();
    final token = auth.token;
    final scope = session?.scope;
    if (token == _token && scope == _scope && identical(session, _session)) {
      return;
    }
    _token = token;
    _scope = scope;
    _session = session;
    CloudSyncService.activeSession = session;
    store.bindCloudScope(scope);
    notifyListeners();
  }

  CloudSession _capture() {
    // AuthStore mutates before awaiting persistence and notifying. Capture and
    // fences therefore check live getters, not only ChangeNotifier emissions.
    _authChanged();
    final session = _session;
    if (session == null) {
      throw const CloudOperationException('signedOut', '请先登录云端账号');
    }
    session.ensureCurrent();
    return session;
  }

  Future<void> refresh() async {
    final session = _capture();
    final generation = store.invalidateCloudRefresh(session.scope);
    final remote = await api.scopedCloud(session).projects();
    final rows = <Project>[];
    for (final item in remote) {
      session.ensureCurrent();
      if (!store.cloudRefreshIsCurrent(session.scope, generation)) return;
      final id = item['id'];
      final name = item['name'];
      if (id is! String || name is! String) {
        throw const CloudOperationException('response', '云端项目列表无效');
      }
      CloudProjectScope.validateCloudId(id);
      final root = await cache.projectRoot(session.scope, id);
      session.ensureCurrent();
      rows.add(
        Project.create(
          name: name,
          path: p.join(root, 'workspace'),
          cloudId: id,
          cloudOrigin: session.scope.origin,
          cloudAccountId: session.scope.accountId,
        ),
      );
    }
    session.ensureCurrent();
    if (!store.cloudRefreshIsCurrent(session.scope, generation)) return;
    await store.mergeCloudProjects(
      rows,
      scope: session.scope,
      generation: generation,
      session: session,
    );
    session.ensureCurrent();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    auth.removeListener(_authChanged);
    super.dispose();
  }
}

/// One binding per AuthStore, not per widget. Closing an export facade must not
/// invalidate the editor session. Login generation changes still invalidate it.
class _CloudAuthBinding {
  _CloudAuthBinding(this.auth) {
    auth.addListener(_changed);
  }
  final AuthStore auth;
  String? _token;
  String? _account;
  int _generation = 0;
  CloudSession? _session;
  int? _authGeneration;
  void _changed() {
    capture();
  }

  CloudSession? capture() {
    final token = auth.token;
    final account = auth.user?.id;
    final authGeneration = auth.sessionGeneration;
    if (_token == token &&
        _account == account &&
        _authGeneration == authGeneration) {
      return _session;
    }
    _token = token;
    _account = account;
    _authGeneration = authGeneration;
    final generation = ++_generation;
    _session = token == null || account == null
        ? null
        : CloudSession(
            scope: CloudProjectScope(
              origin: ApiConfig.origin,
              accountId: account,
            ),
            token: token,
            isCurrent: () =>
                _generation == generation &&
                auth.token == token &&
                auth.sessionGeneration == authGeneration &&
                auth.user?.id == account,
          );
    return _session;
  }
}
