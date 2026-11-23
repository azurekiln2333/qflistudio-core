// R1: one process-wide GitHub auth controller, handed to every surface that
// needs it (Profile connection panel, Home GitHub tab, standalone picker).
//
// The host owns the controller: it restores it once and disposes it with the
// scope. Widgets read it through [GitHubScope.maybeOf]; nothing here starts
// I/O on its own, so a screen that never shows GitHub costs nothing.
import 'package:flutter/widgets.dart';

import 'github_auth_controller.dart';

/// Exposes the single [GitHubAuthController] to the widget tree.
///
/// An [InheritedNotifier] rebuilds dependents when the controller notifies,
/// so a connection made in Profile immediately reaches the Home GitHub tab
/// without extra plumbing.
class GitHubScope extends InheritedNotifier<GitHubAuthController> {
  const GitHubScope({
    super.key,
    required GitHubAuthController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The shared controller, or null when no scope is mounted.
  ///
  /// Callers fall back to a locally owned controller (the legacy picker does
  /// this) so a widget test or an isolated route still works.
  static GitHubAuthController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GitHubScope>()
      ?.notifier;

  /// The shared controller, or a fresh local one the caller must dispose.
  ///
  /// Kept out of [maybeOf] so callers cannot accidentally leak the local one.
  static bool hasScope(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GitHubScope>() != null;
}
