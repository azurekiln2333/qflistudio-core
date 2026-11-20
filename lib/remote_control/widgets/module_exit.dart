// Visible return-to-host controls for the remote-computer module.
//
// The module is a route body inside the host app (see
// `remote_computer_page.dart`), so leaving it is the host's decision: the page
// injects one `onExit` callback and every state of the module renders the same
// control from it. Keeping the tooltip/message in one place is what makes
// "返回 Studio" consistent in the paired dashboard, the pairing screen and the
// boot/unsupported states.

import 'package:flutter/material.dart';

/// Tooltip and label shared by every exit affordance in the module.
const String moduleExitLabel = '返回 Studio';

/// App-bar action used by the module's scaffolds.
class ModuleExitButton extends StatelessWidget {
  const ModuleExitButton({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: moduleExitLabel,
      onPressed: onExit,
      icon: const Icon(Icons.exit_to_app_rounded),
    );
  }
}

/// Labelled variant for screens without an app bar (the pairing form).
///
/// Wrapped in a tooltip on purpose: it is the same control as
/// [ModuleExitButton], so one finder works in every module state.
class ModuleExitTextButton extends StatelessWidget {
  const ModuleExitTextButton({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: moduleExitLabel,
      child: TextButton.icon(
        onPressed: onExit,
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: const Text(moduleExitLabel),
      ),
    );
  }
}
