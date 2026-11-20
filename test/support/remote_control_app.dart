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

import 'package:flutter/material.dart';
import 'package:qfli_studio_core/remote_control/remote_computer_page.dart';
import 'package:qfli_studio_core/remote_control/state/remote_controller.dart';
import 'package:qfli_studio_core/remote_control/state/remote_store.dart';

/// Seeded light theme used where the source tests used `AppTheme.light`.
ThemeData remoteTestTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC15F3C)),
  useMaterial3: true,
);

/// One `MaterialApp` plus the module's page: the shell the host provides.
///
/// The page does not dispose a caller-supplied [controller], matching the
/// source app root, so tests keep their own `addTearDown`.
class TestRemoteApp extends StatelessWidget {
  const TestRemoteApp({
    super.key,
    required this.store,
    required this.controller,
  });

  final RemoteStore store;
  final RemoteController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: remoteTestTheme(),
    home: RemoteComputerPage(store: store, controller: controller),
  );
}
