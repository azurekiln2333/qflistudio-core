// HerdrHost: every Herdr agent pane on this computer, as a HarnessHub host.
//
// Herdr is a separate local host rather than part of StudioMux because its
// panes outlive Studio: the user's terminals, their scrollback and their agents
// all live in Herdr's server. Studio therefore never owns these sessions — it
// lists them, attaches a view, and can close a pane only after explicit user
// confirmation.
//
// Status refresh is wait-driven, not a tight poll: while any agent is working the
// loop blocks in `herdr agent wait` (which returns when that agent leaves the
// working state), and an idle environment only needs a slow safety refresh.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../harness_host.dart';
import '../pty/harness_pty.dart';
import 'herdr_cli.dart';
import 'herdr_models.dart';
import 'herdr_platform.dart';
import 'herdr_session.dart';
import 'herdr_terminal.dart';

/// What the Agents UI shows when Herdr is not installed.
@immutable
class HerdrInstallHint {
  const HerdrInstallHint({
    required this.title,
    required this.message,
    this.url = 'https://herdr.dev',
    this.resolvedPath,
  });

  final String title;
  final String message;
  final String url;

  /// Path Studio did find, when the executable exists but cannot run.
  final String? resolvedPath;
}

class HerdrHost implements HarnessHost {
  HerdrHost({
    String? executablePath,
    HerdrCli? cli,
    HerdrCliRunner? runner,
    HarnessPtyFactory? ptyFactory,
    this.disposePtyFactory,
    HerdrExecutableLocator? locator,
    this.idleRefresh = const Duration(seconds: 30),
    this.waitBudget = const Duration(seconds: 20),
    this.waitFloor = const Duration(milliseconds: 250),
    this.attachTakeover = false,
  }) : _executablePath = executablePath,
       _cli = cli,
       _runner = cli == null ? (runner ?? HerdrCliRunner()) : null,
       _ownsRunner = cli == null && runner == null,
       _ptyFactory = ptyFactory,
       _locator = locator ?? locateHerdrExecutable;

  /// Safety refresh while nothing is working. Long on purpose; a change in an
  /// agent's state wakes the loop far sooner through `agent wait`.
  final Duration idleRefresh;

  /// How long one `agent wait` blocks before the loop re-reads the list.
  final Duration waitBudget;

  /// Floor between two `agent wait` attempts.
  ///
  /// `agent wait` can return at once: the budget expired, the pane went away, or
  /// the server answered with an error. Without a floor the loop would re-read
  /// the list and wait again with no pause, which pegs a core and spawns one
  /// CLI process per turn. The budget bounds staleness, this bounds the rate.
  final Duration waitFloor;

  /// Pass `--takeover` to `agent attach`. Off by default: Studio must not steal
  /// the pane from the user's own Herdr client.
  final bool attachTakeover;

  /// Releases [ptyFactory] when this host is disposed.
  ///
  /// The factory owns the launcher and its process supervisor, so whoever
  /// created it has to be able to drop it; [HerdrHost] cannot call `dispose`
  /// itself because `HarnessPtyFactory` only promises `start`. Pass the
  /// factory's own `dispose` when the host is the only owner.
  final Future<void> Function()? disposePtyFactory;

  final String? _executablePath;
  HerdrCli? _cli;
  final HerdrCliRunner? _runner;
  final bool _ownsRunner;
  final HarnessPtyFactory? _ptyFactory;
  final HerdrExecutableLocator _locator;

  final ValueNotifier<HarnessHostState> _state =
      ValueNotifier<HarnessHostState>(HarnessHostState.offline);
  final StreamController<List<HarnessSessionInfo>> _sessions =
      StreamController<List<HarnessSessionInfo>>.broadcast();
  final Map<String, HerdrAgentInfo> _agents = <String, HerdrAgentInfo>{};
  final Map<String, HerdrSessionHandle> _handles =
      <String, HerdrSessionHandle>{};
  List<HarnessSessionInfo> _latest = const <HarnessSessionInfo>[];
  List<HarnessProviderInfo>? _providers;

  Future<HerdrCli?>? _initializing;
  Future<void>? _loop;
  Future<void>? _refreshing;
  Completer<void>? _wake;
  bool _disposed = false;
  String? _lastError;
  String? _version;
  HerdrServerStatus? _serverStatus;
  HerdrInstallHint? _installHint;
  final Map<String, String> _workspaceLabels = <String, String>{};

  @override
  String get id => 'herdr';

  @override
  String get label => 'Herdr';

  @override
  HarnessHostKind get kind => HarnessHostKind.local;

  @override
  ValueListenable<HarnessHostState> get state => _state;

  /// Install guidance for the UI; null once Herdr works.
  HerdrInstallHint? get installHint => _installHint;

  /// Last failure, already user-facing.
  String? get lastError => _lastError;

  /// Herdr version found during detection.
  String? get version => _version;

  /// `herdr status` snapshot from detection.
  HerdrServerStatus? get serverStatus => _serverStatus;

  /// Current session list, for a UI that mounts after the first refresh.
  List<HarnessSessionInfo> get currentSessions => _latest;

  // -------------------------------------------------------------------------
  // HarnessHost
  // -------------------------------------------------------------------------

  @override
  Stream<List<HarnessSessionInfo>> watchSessions() {
    unawaited(_ensureLoop());
    return Stream.multi((controller) {
      controller.add(_latest);
      final subscription = _sessions.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<HarnessProviderInfo>> providers() async {
    final cli = await _ensureInitialized();
    if (cli == null) return const <HarnessProviderInfo>[];
    final cached = _providers;
    if (cached != null) return cached;
    // Only agent kinds: HerdrHost lists the panes Herdr reports as agents, so a
    // bare shell pane would be invisible in the list and a "new terminal" entry
    // would create a session nobody can see. `shell` is therefore not offered.
    final list = <HarnessProviderInfo>[
      for (final kind in HerdrCli.agentKinds)
        () {
          final spec = HerdrProviderSpec.forKind(kind);
          return HarnessProviderInfo(
            id: spec.id,
            label: spec.label,
            // Herdr resolves `agent start --kind`, so a missing binary here only
            // means "this PATH has not got it"; for a kind Herdr knows but we do
            // not, the executable name is a guess and must not hide the entry.
            available: spec.verified ? executableOnPath(spec.executable) : true,
            executable: spec.executable,
            builtIn: true,
          );
        }(),
    ];
    _providers = List<HarnessProviderInfo>.unmodifiable(list);
    return _providers!;
  }

  /// Drops the cached provider list so a newly installed agent appears without
  /// restarting Studio.
  void refreshProviders() => _providers = null;

  @override
  Future<HarnessSessionHandle> open(String sessionId) async {
    final cli = await _ensureInitialized();
    if (cli == null) {
      throw const HerdrException(
        HerdrFailure.unavailable,
        '这台电脑没有安装 Herdr，无法打开该会话。',
      );
    }
    final cached = _handles[sessionId];
    if (cached != null) {
      // A stopped or detached handle still exists in the map until its owner
      // releases it; returning it would show a closed terminal that swallows
      // every keystroke.
      if (!cached.isEnded) return cached;
      _handles.remove(sessionId);
    }

    var agent = _agents[sessionId];
    if (agent == null) {
      // The list may be stale (a pane opened after the last refresh).
      await refreshNow();
      agent = _agents[sessionId];
    }
    if (agent == null) {
      throw const HerdrException(HerdrFailure.notFound, '找不到该 Herdr 面板，可能已关闭。');
    }
    final terminal = await _createTerminal(agent);
    final handle = HerdrSessionHandle(
      cli: cli,
      agent: agent,
      terminal: terminal,
      hostId: id,
      onChanged: refreshNow,
      onDetached: (detached) async {
        if (identical(_handles[sessionId], detached)) {
          _handles.remove(sessionId);
          detached.dispose();
        }
      },
    );
    _handles[sessionId] = handle;
    return handle;
  }

  @override
  Future<HarnessSessionHandle> launch(HarnessLaunchRequest request) async {
    final cli = await _ensureInitialized();
    if (cli == null) {
      throw const HerdrException(
        HerdrFailure.unavailable,
        '这台电脑没有安装 Herdr，无法新建会话。',
      );
    }
    if (request.providerId == 'shell') {
      // HerdrHost lists agents, and `agent list` never shows a bare shell pane:
      // a workspace created here would silently vanish from the list. Say so
      // instead of returning a session that disappears on the next refresh.
      throw const HerdrException(
        HerdrFailure.invalidArgument,
        'Herdr 只管理 agent 面板，普通终端请在“本机”主机里新建。',
      );
    }
    final title = request.title?.trim();
    final label = (title == null || title.isEmpty) ? null : title;
    // A Herdr session needs a workspace to live in; `--no-focus` keeps the
    // user's current pane focused while Studio prepares the new one.
    final paneId = await cli.createWorkspace(
      cwd: request.cwd,
      label: label,
      focus: false,
    );
    final started = await cli.startAgent(
      name: _agentNameFor(request.providerId, label),
      kind: request.providerId,
      paneId: paneId,
      args: request.args,
    );
    // Refresh first so the host cache is current, then keep the freshly started
    // agent even if the list push has not arrived yet.
    await refreshNow();
    _agents[started.paneId] = started;
    _emit();
    return open(started.paneId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
    final handles = _handles.values.toList();
    _handles.clear();
    for (final handle in handles) {
      // 等 attach 客户端真的被 kill：主机释放完应用马上退，不 wait 就会
      // 留下孤儿进程占着窗格。
      await handle.dispose();
    }
    await _sessions.close();
    _state.dispose();
    if (_ownsRunner) await _runner?.dispose();
    // 工厂握着 PTY 启动器与它的进程订阅：不释放就等于每关一个编辑页漏一套。
    try {
      await disposePtyFactory?.call();
    } on Object {
      // 释放失败不该挡住主机自己的收尾。
    }
  }

  // -------------------------------------------------------------------------
  // Detection
  // -------------------------------------------------------------------------

  Future<HerdrCli?> _ensureInitialized() {
    final cli = _cli;
    if (cli != null) return Future<HerdrCli?>.value(cli);
    return _initializing ??= _initialize();
  }

  Future<HerdrCli?> _initialize() async {
    final executable = await _locator(explicitPath: _executablePath);
    if (executable == null) {
      final explicit = _executablePath?.trim() ?? '';
      if (explicit.isNotEmpty) {
        // The user pointed at a path: saying "not installed" would send them
        // looking for a problem they have already solved once.
        _installHint = HerdrInstallHint(
          title: 'Herdr 路径无效',
          message: '设置里指定的路径不能执行：$explicit。改回自动查找或换一个路径。',
          resolvedPath: explicit,
        );
        _state.value = HarnessHostState.unsupported;
        return null;
      }
      _installHint = HerdrInstallHint(
        title: kIsWeb ? '此平台不支持 Herdr' : '未安装 Herdr',
        message: kIsWeb
            ? '网页版拿不到本机的 Herdr 进程，请用桌面版客户端。'
            : '没有找到 herdr。安装后重启 Studio 即可在这里管理 Herdr 工作区、面板和 agent；'
                  '不安装也能用 Studio 自带的会话管理。',
      );
      _state.value = HarnessHostState.unsupported;
      return null;
    }
    final runner = _runner;
    final cli = _cli = HerdrCli(executable: executable, runner: runner!.call);
    try {
      _version = await cli.version();
      final status = await cli.serverStatus();
      _serverStatus = status;
      if (!status.serverRunning) {
        _lastError = 'Herdr 服务未运行。请在电脑上打开一次 Herdr，或在终端运行 herdr server。';
        _state.value = HarnessHostState.offline;
        _installHint = HerdrInstallHint(
          title: 'Herdr 服务未运行',
          message: _lastError!,
          resolvedPath: executable,
        );
        return cli;
      }
      _installHint = null;
      _state.value = HarnessHostState.online;
      return cli;
    } on HerdrException catch (error) {
      _lastError = error.message;
      _installHint = HerdrInstallHint(
        title: 'Herdr 无法使用',
        message: error.message,
        resolvedPath: executable,
      );
      _state.value = error.failure == HerdrFailure.unavailable
          ? HarnessHostState.unsupported
          : HarnessHostState.offline;
      return cli;
    }
  }

  // -------------------------------------------------------------------------
  // Refresh loop
  // -------------------------------------------------------------------------

  Future<void> _ensureLoop() {
    return _loop ??= _runLoop();
  }

  /// Wakes the loop immediately (pull-to-refresh, after an action).
  Future<void> refreshNow() async {
    if (_disposed) return;
    await _ensureInitialized();
    final wake = _wake;
    if (wake != null && !wake.isCompleted) {
      wake.complete();
    }
    await _refresh();
  }

  Future<void> _runLoop() async {
    while (!_disposed) {
      // The loop owns the host's liveness: one unexpected error must never stop
      // it while the host still claims to be online.
      try {
        await _refresh();
      } catch (error) {
        _lastError = '$error';
      }
      if (_disposed) return;
      final busy = <HerdrAgentInfo>[
        for (final agent in _agents.values)
          if (agent.status == HerdrAgentStatus.working) agent,
      ];
      if (busy.isEmpty) {
        await _sleep(idleRefresh);
      } else {
        await _waitForBusy(busy);
      }
    }
  }

  /// Blocks until one busy agent leaves `working` (or the budget expires).
  ///
  /// Exactly one `agent wait` runs at a time: the CLI has no cancel verb, so
  /// racing N waits leaves N-1 orphan processes alive until their budget runs
  /// out, and each loop iteration would add another batch. One waiter plus the
  /// budget bounds staleness at [waitBudget].
  Future<void> _waitForBusy(List<HerdrAgentInfo> busy) async {
    final cli = _cli;
    if (cli == null) {
      await _sleep(idleRefresh);
      return;
    }
    if (busy.isEmpty) return;
    await _waitQuietly(cli, busy.first);
  }

  /// One long wait that must never break the loop: a timeout, a closed pane or a
  /// transient CLI failure all mean "refresh and try again".
  Future<void> _waitQuietly(HerdrCli cli, HerdrAgentInfo agent) async {
    final started = Stopwatch()..start();
    try {
      await cli.wait(
        agent.target,
        until: const <HerdrAgentStatus>[
          HerdrAgentStatus.idle,
          HerdrAgentStatus.done,
          HerdrAgentStatus.blocked,
          HerdrAgentStatus.unknown,
        ],
        budget: waitBudget,
      );
    } on HerdrException {
      // Expected: the budget expired, or the pane went away.
    }
    // A wait that came back immediately must not turn the loop into a busy
    // spin: sleep the rest of the floor before the next attempt.
    final elapsed = started.elapsed;
    if (elapsed < waitFloor) await _sleep(waitFloor - elapsed);
  }

  Future<void> _sleep(Duration duration) async {
    if (_disposed) return;
    final wake = _wake = Completer<void>();
    // A plain `Future.delayed` cannot be cancelled: after dispose it would sit
    // in the timer queue for up to [idleRefresh] and keep the isolate alive.
    // Own the timer so disposing frees it right away.
    final tick = Completer<void>();
    final timer = Timer(duration, () {
      if (!tick.isCompleted) tick.complete();
    });
    await Future.any<void>(<Future<void>>[tick.future, wake.future]);
    timer.cancel();
    if (identical(_wake, wake)) _wake = null;
  }

  Future<void> _refresh() {
    // A user-triggered refresh can land while the loop is already reading; share
    // the in-flight read instead of spawning a second `agent list`.
    return _refreshing ??= _refreshOnce().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<void> _refreshOnce() async {
    final cli = await _ensureInitialized();
    if (cli == null || _disposed) return;
    try {
      final agents = await cli.agents();
      final workspaces = await _safeWorkspaces(cli);
      if (_disposed) return;
      _agents
        ..clear()
        ..addEntries(
          agents.map(
            (agent) => MapEntry<String, HerdrAgentInfo>(agent.paneId, agent),
          ),
        );
      _workspaceLabels
        ..clear()
        ..addEntries(
          workspaces.map(
            (workspace) => MapEntry<String, String>(
              workspace.workspaceId,
              workspace.label,
            ),
          ),
        );
      _lastError = null;
      if (_state.value != HarnessHostState.online) {
        _state.value = HarnessHostState.online;
        _installHint = null;
      }
      _emit();
    } on HerdrException catch (error) {
      if (_disposed) return;
      _lastError = error.message;
      if (error.failure == HerdrFailure.unavailable) {
        _state.value = HarnessHostState.unsupported;
      } else if (error.failure == HerdrFailure.serverDown) {
        _state.value = HarnessHostState.offline;
      } else {
        _state.value = HarnessHostState.offline;
      }
    } catch (error) {
      // A parse surprise is not a reason to kill the refresh loop: report it and
      // keep the last known list.
      if (_disposed) return;
      _lastError = '$error';
    }
  }

  /// Workspace labels are decoration: a failure must not hide the agents.
  Future<List<HerdrWorkspaceInfo>> _safeWorkspaces(HerdrCli cli) async {
    try {
      return await cli.workspaces();
    } on HerdrException {
      return const <HerdrWorkspaceInfo>[];
    }
  }

  void _emit() {
    if (_disposed) return;
    final infos = <HarnessSessionInfo>[
      for (final agent in _agents.values) agent.toSessionInfo(hostId: id),
    ];
    infos.sort(_compareSessions);
    _latest = List<HarnessSessionInfo>.unmodifiable(infos);
    for (final entry in _handles.entries.toList()) {
      final agent = _agents[entry.key];
      if (agent == null) {
        entry.value.markExited();
      } else {
        entry.value.update(agent);
      }
    }
    if (!_sessions.isClosed) _sessions.add(_latest);
  }

  /// Attention first, then most recently completed: `blocked`/`done` are the
  /// two states that need the user; `working` needs nothing.
  static int _compareSessions(HarnessSessionInfo a, HarnessSessionInfo b) {
    int rank(HarnessSessionStatus status) {
      switch (status) {
        case HarnessSessionStatus.blocked:
          return 0;
        case HarnessSessionStatus.done:
          return 1;
        case HarnessSessionStatus.working:
          return 2;
        case HarnessSessionStatus.idle:
          return 3;
        case HarnessSessionStatus.unknown:
          return 4;
        case HarnessSessionStatus.exited:
          return 5;
      }
    }

    final byRank = rank(a.status).compareTo(rank(b.status));
    if (byRank != 0) return byRank;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  // -------------------------------------------------------------------------
  // Terminal creation
  // -------------------------------------------------------------------------

  Future<HerdrTerminal> _createTerminal(HerdrAgentInfo agent) async {
    final cli = _cli!;
    final factory = _ptyFactory;
    if (factory != null) {
      try {
        return await HerdrPtyTerminal.start(
          factory: factory,
          argv: <String>[
            cli.executable,
            'agent',
            'attach',
            agent.target,
            if (attachTakeover) '--takeover',
          ],
          workingDirectory: agent.cwd,
        );
      } on HarnessPtyException catch (error) {
        // A PTY failure must not make the session unopenable: the snapshot
        // fallback still shows the pane and can type into it.
        _lastError = error.message;
      }
    }
    return HerdrSnapshotTerminal(
      readPane: () => cli.readPane(agent.paneId),
      sendText: (text) => cli.sendText(agent.paneId, text),
      sendKeys: (keys) => cli.sendKeys(agent.target, keys),
      onError: (error) {
        _lastError = error is HerdrException ? error.message : '$error';
      },
    )..start();
  }

  /// A short, Herdr-legal agent name. Herdr labels are single-line and are also
  /// used as prompt targets, so control characters and dashes-out-front go away.
  static String _agentNameFor(String providerId, String? label) {
    final base = (label == null || label.trim().isEmpty)
        ? providerId
        : label.trim();
    final cleaned = base
        .replaceAll(RegExp(r'[\u0000-\u001f]'), ' ')
        .replaceAll(RegExp(r'[^A-Za-z0-9._\u4e00-\u9fff-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final name = cleaned.isEmpty ? providerId : cleaned;
    return name.length <= 40 ? name : name.substring(0, 40);
  }
}
