// Provenance: replaces CloudTerminal `lib/main.dart` (source HEAD
// 49b2aac781858929a19307faeb808b83f8154410).
//
// The source app wrapped the whole product in its own `MaterialApp`, its own
// `Appearance` controller and its own lifecycle observer. None of that belongs
// in a shared core: the host app already owns theming, localisation and the
// widget tree. What is genuinely module behaviour is kept here:
//
//   * pairing ⇄ dashboard transition driven by `RemoteController.pairing`
//   * app resume → `reconnectNow()` (phones drop sockets in the background)
//   * exactly-once disposal of the store/controller this page created
//   * a truthful gate for platforms without a socket/persistence backend
//
// Closing this page never closes desktop sessions. `RemoteController.dispose()`
// only cancels the frame subscription and closes the client socket; it sends no
// `session_close`, so agents keep running on the PC and reappear on reconnect.
//
// ## Ownership
//
// * No injected controller: this page opens the store, builds the controller and
//   disposes it when the route goes away.
// * `store`/`controller` injected: the **caller** owns them. The page never
//   disposes them, and the caller keeps whatever it wants across module visits.
//
// Returning to Studio uses the host route that mounted this page, captured
// outside the module's own inner `Navigator` (see [RemoteComputerPage.onExit]),
// so a nested remote page never swallows the exit.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'pages/home_screen.dart';
import 'pages/pair_screen.dart';
import 'state/remote_controller.dart';
import 'state/remote_store.dart';
import 'widgets/module_exit.dart';

/// Single entry point for the remote-computer module.
///
/// Mount it as a route from the host app:
///
/// ```dart
/// Navigator.of(context).push(
///   MaterialPageRoute<void>(builder: (_) => const RemoteComputerPage()),
/// );
/// ```
///
/// The page does **not** create a `MaterialApp`, so it inherits the host theme,
/// text direction, localisations and `ScaffoldMessenger`. Do not wrap it in a
/// second `MaterialApp`: that would silently drop the host's navigator and
/// snackbars.
class RemoteComputerPage extends StatefulWidget {
  const RemoteComputerPage({
    super.key,
    this.store,
    this.controller,
    this.onExit,
  });

  /// Pre-opened store. Tests pass one to avoid the private directory; the app
  /// leaves it null and the page opens it once.
  final RemoteStore? store;

  /// Pre-built controller. When given, this page does **not** dispose it — the
  /// caller owns its lifetime, and that stays true after the module is closed.
  final RemoteController? controller;

  /// Leaves the module from the visible "返回 Studio" control.
  ///
  /// Defaults to popping the route that mounted this page. Inject it when the
  /// host embeds the module somewhere a `pop` is not the right exit (a tab, a
  /// dialog, a desktop shell).
  ///
  /// The callback is captured at the page level, deliberately *outside* the
  /// dashboard's inner `Navigator`: the control therefore returns to the host
  /// even while a nested remote page (a pane, a Codex thread) is on top of the
  /// inner stack, and internal back navigation keeps working for those pages.
  final VoidCallback? onExit;

  /// Whether this build can drive a paired computer at all.
  ///
  /// True exactly when the conditional exports resolved the native transport
  /// and store (`dart:io` available). Host navigation should hide the entry
  /// when this is false instead of pushing a page that can only apologise.
  /// The page still renders [_UnsupportedPlatform] if it is opened anyway, so a
  /// deep link or a stale menu cannot produce a retry loop either.
  static bool get isSupported => !kIsWeb;

  /// Convenience route so a host menu entry stays a one-liner.
  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RemoteComputerPage()));
  }

  @override
  State<RemoteComputerPage> createState() => _RemoteComputerPageState();
}

/// Boot result: the store the page opened (if any) and the controller it owns.
class _Boot {
  const _Boot({
    required this.controller,
    required this.store,
    required this.ownsController,
  });

  final RemoteController controller;

  /// Store backing [controller], when the caller supplied it.
  ///
  /// Only used for the pair screen's remembered relay address; the controller
  /// owns everything else.
  final RemoteStore? store;

  /// True when this page created the controller and must dispose it.
  final bool ownsController;
}

class _RemoteComputerPageState extends State<RemoteComputerPage>
    with WidgetsBindingObserver {
  /// Non-null once the async boot finished. Null while the store is opening.
  _Boot? _boot;

  /// Set when booting failed. Kept separate from [_boot] so the error state is
  /// not mistaken for "still loading" and the page cannot spin forever.
  Object? _bootError;

  /// A browser build has no socket or private-storage backend for this module,
  /// so the gate is decided before any async work starts.
  bool get _unsupported => !RemoteComputerPage.isSupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_unsupported) return;
    unawaited(_bootModule());
  }

  Future<void> _bootModule() async {
    try {
      final RemoteController controller;
      RemoteStore? store = widget.store;
      final bool ownsController;
      final provided = widget.controller;
      if (provided != null) {
        controller = provided;
        ownsController = false;
      } else {
        final opened = store ?? await RemoteStore.open();
        store = opened;
        controller = RemoteController(store: opened);
        ownsController = true;
      }
      if (!mounted) {
        // The route was popped while the store was opening. Nothing else holds
        // the controller, so release it here instead of leaking a socket loop.
        if (ownsController) controller.dispose();
        return;
      }
      controller.connect();
      setState(
        () => _boot = _Boot(
          controller: controller,
          store: store,
          ownsController: ownsController,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _bootError = e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Phones kill sockets while backgrounded. Reconnecting on resume skips the
    // remaining backoff instead of making the user wait it out.
    //
    // This is a reconnect only: it never replays uncertain keyboard input and
    // never auto-grants a permission that was pending when the link dropped.
    if (state == AppLifecycleState.resumed) {
      _boot?.controller.reconnectNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Disposing the client view must not touch the desktop: this only closes the
    // local socket and settles local pending requests.
    final boot = _boot;
    if (boot != null && boot.ownsController) boot.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupported) return _UnsupportedPlatform(onExit: _exit);
    final error = _bootError;
    if (error != null) return _BootFailure(error: error, onExit: _exit);
    final boot = _boot;
    if (boot == null) return const _Booting();
    return _RemoteRoot(
      controller: boot.controller,
      store: boot.store,
      onExit: _exit,
    );
  }

  /// Leaves the module, releasing whatever this page owns.
  ///
  /// Ownership is decided by [RemoteController.dispose] alone: an owned
  /// controller is disposed by `dispose()` when the route is removed, an injected
  /// one is left to its caller. Either way no `session_close` is sent, so desktop
  /// sessions keep running.
  void _exit() {
    final injected = widget.onExit;
    if (injected != null) {
      injected();
      return;
    }
    // Resolved from this page's own context, which sits above the dashboard's
    // inner Navigator, so this pops the host route rather than an inner page.
    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) navigator.pop();
  }
}

/// Swaps between pairing and the dashboard when the pairing changes.
///
/// Split out so the transition rebuilds only on controller notifications and
/// never re-runs the page's boot or lifecycle logic.
class _RemoteRoot extends StatelessWidget {
  const _RemoteRoot({required this.controller, this.store, this.onExit});

  final RemoteController controller;
  final RemoteStore? store;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pairing = controller.pairing;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: pairing == null
              ? PairScreen(
                  key: const ValueKey<String>('remote-pair'),
                  controller: controller,
                  onExit: onExit,
                  // Remembering the last relay saves retyping the address after
                  // an unpair; the secret is gone with the pairing.
                  initialRelay: store?.lastRelayUrl,
                )
              : HomeScreen(
                  key: ValueKey<String>('remote-home-${pairing.agentId}'),
                  controller: controller,
                  onExit: onExit,
                ),
        );
      },
    );
  }
}

class _Booting extends StatelessWidget {
  const _Booting();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在读取配对信息…', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// Shown when the module could not open its own state.
///
/// The only realistic causes are a broken storage plugin or a filesystem
/// permission problem, so the text says that instead of "something went wrong".
class _BootFailure extends StatelessWidget {
  const _BootFailure({required this.error, this.onExit});

  final Object error;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程电脑'),
        actions: <Widget>[
          if (onExit != null) ModuleExitButton(onExit: onExit!),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.sd_card_alert_outlined, color: scheme.error, size: 40),
              const SizedBox(height: 12),
              Text(
                '无法打开远程电脑的本地存储',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '配对信息保存在本应用的私有目录。请检查存储权限后重试。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SelectableText(
                '$error',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Truthful gate for platforms the module cannot run on.
///
/// This is a browser build, not a network failure: `transport/relay_socket_io.dart`
/// and `state/remote_store_backend_io.dart` are selected by a conditional export
/// and resolve to stubs without `dart:io`. Saying so avoids the "连接失败" loop a
/// user would otherwise see from repeated socket attempts.
class _UnsupportedPlatform extends StatelessWidget {
  const _UnsupportedPlatform({this.onExit});

  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程电脑'),
        actions: <Widget>[
          if (onExit != null) ModuleExitButton(onExit: onExit!),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.devices_other_rounded,
                color: scheme.outline,
                size: 44,
              ),
              const SizedBox(height: 14),
              Text(
                '当前平台不支持远程电脑',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '远程电脑需要原生应用提供的 WebSocket 连接与本地私有存储，浏览器版两者都没有实现。'
                '请在 Windows、macOS、Linux、Android 或 OpenHarmony 应用中使用。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
