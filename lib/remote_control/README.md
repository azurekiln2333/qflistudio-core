# remote_control — 远程电脑

Migrated from CloudTerminal (source HEAD `49b2aac781858929a19307faeb808b83f8154410`).
This module drives **one paired desktop computer** over the public relay. It is
not a second application shell and does not replace the host's editor terminals.

## Layout

| Path | Responsibility |
| --- | --- |
| `models/protocol.dart` | Wire mirror of the agent protocol: sessions, session events, Codex catalog/transcript types |
| `models/herdr.dart` | Herdr wire types, `herdr_act` payload builders, pane-snapshot replay maths |
| `models/pairing_uri.dart` | `cloudterminal://pair?relay=&code=&v=` parsing |
| `transport/relay_socket.dart` | `RelaySocket`/`RelayConnector` surface + relay URL normalisation (no `dart:io`) |
| `transport/relay_connector.dart` | Conditional export selecting the native or unsupported socket |
| `state/remote_store.dart` | `qfli_remote_control.json` private store + `Pairing` |
| `state/remote_controller.dart` | Connection loop, pairing, request ids/timeouts, replay routing, Herdr push sink |
| `state/session_view.dart` | Ordered events, `seq` dedupe, streaming text, permissions, xterm emulator |
| `state/herdr_controller.dart` | Herdr caches, push deltas, watchdog, in-flight action guard |
| `state/codex_catalog.dart` | Codex project/thread paging |
| `state/codex_thread_view.dart` | One Codex transcript, notices, pending approvals |
| `remote_computer_page.dart` | Module entry: boot, pairing ⇄ dashboard, resume/reconnect, disposal, browser gate |
| `pages/pair_screen.dart` | Pairing: QR / short code / manual relay + secret |
| `pages/home_screen.dart` | Dashboard: sidebar, session list, history, Herdr/Codex destinations |
| `pages/session_screen.dart` | One session transcript, permission dock, composer, Herdr pane rows |
| `pages/herdr_screen.dart` | Herdr workspaces / tabs / panes |
| `pages/herdr_terminal_screen.dart` | Full-screen Herdr pane |
| `pages/codex_screen.dart` | Codex thread transcript and approvals |
| `widgets/remote_terminal_pane.dart` | Interactive remote PTY viewport (renamed from source `TerminalPane`) |
| `widgets/*.dart` | Cards, sheets and tiles shared by the pages above |
| `theme/remote_theme.dart` | Host-theme adapter: monospace style + status colour |
| `util/format.dart` | Display helpers (cost, duration, relative time, path ellipsis) |

## Mounting

The module exposes exactly one entry. It is a route body, not an app:

```dart
if (RemoteComputerPage.isSupported) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const RemoteComputerPage()),
  );
}
// or
await RemoteComputerPage.open(context);
```

`RemoteComputerPage.isSupported` is the same predicate the page uses for its
unsupported gate. Host navigation should use it to hide the entry in builds
without `dart:io`. Opening the page anyway is still safe: it shows the
explanatory gate instead of a failing connection.

`RemoteComputerPage` inherits the host `MaterialApp` (theme, localisations,
`ScaffoldMessenger`). It must never be wrapped in a second `MaterialApp`: that
would replace the host navigator and detach snackbars and dialogs. Appearance
(theme mode / seed colour) stays a host concern — the module has no `Appearance`
controller and no appearance sheet.

Ownership rules:

- With no arguments the page opens `RemoteStore` once and owns the
  `RemoteController`, disposing it exactly once when the route is popped.
- With `controller:` supplied the caller owns the lifetime and the page will not
  dispose it (tests use this with `RemoteStore.memory()`).
- Popping the page closes the client socket only. It never sends `session_close`,
  so agents keep running on the desktop and reappear on reconnect.

## Contract notes

- **Wire compatibility is a hard requirement.** Frame kinds (`hello`,
  `hello_ok`, `presence`, `msg`, `error`), request ids (`r<n>`), the 20 s default
  request timeout, and `seq`-based dedupe/replay are copied unchanged so the
  existing desktop agent and relay keep working. Do not rename wire fields.
- **Relay reachability ≠ agent availability.** `ConnectionPhase` distinguishes
  `connecting`, `online`, `agentOffline`, `authFailed`, `disconnected` and
  `unpaired`. A disconnect settles every pending request.
- **Raw terminal input.** `terminal_input` carries exact bytes. It is never
  trimmed, never gets an appended newline, and is never reinterpreted as a
  prompt.
- **Herdr pushes are screen snapshots, not PTY streams.** `prefix`/`chunk` are
  reconciled against the cached text, and a mismatched prefix falls back to a
  full replace. Responses must be guarded by the selected pane id so a late read
  cannot update a newly selected pane.
- **Approvals are explicit.** Claude permission replies, Codex approvals and
  destructive remote actions only ever follow a user action. Reconnect never
  auto-grants a permission and never replays uncertain keyboard input.

## Persistence

`RemoteStore` writes `qfli_remote_control.json` in the host app's private support
directory (atomic temp-file + rename, writes serialised). It never reads a
CloudTerminal installation's `cloudterminal.json` and never reuses Studio login
tokens. The pairing secret is app-private **plaintext**, not encrypted. It must
not be logged, exported, or copied into fixtures.

## Platform boundary

`dart:io` appears only in `transport/relay_socket_io.dart` and
`state/remote_store_backend_io.dart`. Web targets resolve the `*_stub.dart`
counterparts: connecting reports the feature as unsupported and persistence
degrades to memory. Remote control is a native-only feature and is not advertised
in the browser build.

`RemoteComputerPage` checks `kIsWeb` before any async work and renders an
explicit "当前平台不支持远程电脑" page. That is a real capability statement, not a
network error: no socket is dialed and no storage is opened, so the user never
sees a retry loop against a backend that cannot exist.

## Terminal renderer

The PTY viewport uses the vendored, patched `xterm` fork at
`qfli_studio_core/vendor/xterm` (see `vendor/xterm/PROVENANCE.md`). Do not swap it
for an unrelated pub.dev version.

The renderer font comes from `RemoteTheme.terminalStyle`, which uses the bundled
`EditorFonts` monospace family plus CJK fallbacks so Chinese PTY output does not
render as tofu. The PTY viewport is `widgets/remote_terminal_pane.dart` and is
kept separate from the host's `TerminalPane`
(`lib/editor/terminal_pane.dart`), which owns local/cloud **line-oriented**
execution: remote PTY bytes never pass through `ShellBackend.execute`/`sendLine`.
