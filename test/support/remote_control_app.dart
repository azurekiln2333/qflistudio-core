// Test shell for the migrated remote-control module.
//
// Provenance: the source package's widget tests mounted `CloudTerminalApp`
// (`lib/main.dart`), an app root that owned a `MaterialApp`, a global
// `Appearance` controller and `_Root`, the pairing/dashboard switcher.
//
// The core module deliberately does not create a `MaterialApp`: it is a route
// body that inherits the host app's navigator, theme and localisations (see
// `lib/remote_control/remote_computer_page.dart`). The appearance controller was
// not ported either. Tests therefore supply the host shell here, and mount the
// real page inside it, instead of copying the source app root.
//
// `remoteTestTheme()` stands in for `AppTheme.light(AppTheme.seeds.first.color)`.
// The ported assertions never read a colour: they look for widgets, Chinese
// labels and wire frames, so a seeded Material 3 palette is enough.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/remote_control/remote_computer_page.dart';
import 'package:qfli_studio_core/remote_control/state/remote_controller.dart';
import 'package:qfli_studio_core/remote_control/state/remote_store.dart';

/// Seeded light theme used where the source tests used `AppTheme.light`.
ThemeData remoteTestTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC15F3C)),
  useMaterial3: true,
);

/// Wait for a specific observable result while live sessions keep animating.
/// `pumpAndSettle` cannot finish while a running-session spinner is mounted.
Future<void> pumpRemoteUntil(
  WidgetTester tester,
  bool Function() ready, {
  required String reason,
}) async {
  for (var frame = 0; frame < 100; frame += 1) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
  }
  expect(ready(), isTrue, reason: reason);
}

/// Preserve real route transitions without waiting for unrelated busy spinners.
Future<void> pumpRemoteRoute(
  WidgetTester tester,
  Finder page, {
  bool Function()? ready,
}) => pumpRemoteUntil(tester, () {
  final elements = page.evaluate().toList();
  if (elements.length != 1) return false;
  final route = ModalRoute.of(elements.single);
  if (route == null) return false;
  final routes = <ModalRoute<dynamic>>{route};
  // The dashboard has an inner Navigator. Its first route can be ready while
  // the host is still animating the module into view.
  elements.single.visitAncestorElements((element) {
    final ancestor = ModalRoute.of(element);
    if (ancestor != null) routes.add(ancestor);
    return true;
  });
  return routes.every(
        (route) =>
            route.isCurrent &&
            route.animation?.status == AnimationStatus.completed &&
            (route.secondaryAnimation == null ||
                route.secondaryAnimation!.status == AnimationStatus.dismissed),
      ) &&
      (ready?.call() ?? true);
}, reason: 'Expected one ready, fully transitioned route for $page');

/// One `MaterialApp` plus the module's page: the shell the host provides.
///
/// **Ownership.** The migrated page does *not* dispose a caller-supplied
/// [controller] (`RemoteComputerPage.controller`), because the host may keep it
/// across module visits. That differs from the source app root, which disposed
/// `widget.controller` when `CloudTerminalApp` was removed (`lib/main.dart:52-55`
/// at source HEAD). This shell is therefore **not** a faithful stand-in for
/// source ownership: every test that passes a controller here must keep and
/// dispose it itself — see [TestControllerOwner].
class TestRemoteApp extends StatelessWidget {
  const TestRemoteApp({
    super.key,
    required this.store,
    required this.controller,
    this.onExit,
  });

  final RemoteStore store;
  final RemoteController controller;

  /// Forwarded to the page so a test can assert the injected-exit path.
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: remoteTestTheme(),
    home: RemoteComputerPage(
      store: store,
      controller: controller,
      onExit: onExit,
    ),
  );
}

/// A Studio-like host home that pushes the module as a **second** route.
///
/// The source tests could not see the module-exit problem because they mounted
/// the page as `MaterialApp.home`, where there is no host route to return to.
/// This shell reproduces the real host: one route below, the module above it, so
/// the module's visible "返回 Studio" control has something to pop.
class TestRemoteHost extends StatefulWidget {
  const TestRemoteHost({
    super.key,
    required this.store,
    this.controller,
    this.onExit,
    this.hostLabel = 'Studio 主页',
  });

  final RemoteStore store;

  /// Injected controller. The host owns it: closing the module must leave it
  /// usable, so its socket stays open until the test disposes it.
  ///
  /// Null models the app path, where the page opens the store and takes
  /// ownership of the controller it builds (and releases it on exit). The shell
  /// then has no controller to inspect — that is the point of the owned case.
  final RemoteController? controller;

  /// Overrides the module's exit callback. Null uses the page default, which pops
  /// the route this shell pushed.
  final VoidCallback? onExit;

  /// Text painted by the host home, used to assert the return.
  final String hostLabel;

  @override
  State<TestRemoteHost> createState() => _TestRemoteHostState();
}

class _TestRemoteHostState extends State<TestRemoteHost> {
  final _navigator = GlobalKey<NavigatorState>();

  /// Pushes the module as a second route, the way Studio's navigation entry does.
  Future<void> openModule() async {
    await _navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteComputerPage(
          store: widget.store,
          controller: widget.controller,
          onExit: widget.onExit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    debugShowCheckedModeBanner: false,
    theme: remoteTestTheme(),
    home: Scaffold(
      appBar: AppBar(title: const Text('Studio')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(widget.hostLabel),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => unawaited(openModule()),
              icon: const Icon(Icons.desktop_windows_outlined),
              label: const Text('远程电脑'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Owns a test-created [RemoteController] exactly once.
///
/// Two things are needed at the same time: an explicit disposal inside the test
/// body (so the test can assert what the wire saw when the socket closed) and a
/// tear-down fallback for the failure path. `ChangeNotifier.dispose` throws when
/// it runs twice, so the disposal is funnelled through one idempotent owner.
class TestControllerOwner {
  TestControllerOwner(this.controller);

  final RemoteController controller;
  bool _disposed = false;

  bool get disposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
  }
}
