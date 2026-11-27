# Vendored xterm.dart 4.0.0

Source: https://pub.dev/packages/xterm/versions/4.0.0
Upstream: https://github.com/TerminalStudio/xterm.dart
License: MIT, retained in LICENSE.

The vendored payload includes lib/, pubspec.yaml, LICENSE and CHANGELOG.md.
Retained compatibility contracts include:

- `lib/src/ui/shortcut/shortcuts.dart`: Apple platforms keep their shortcuts;
  all other platforms use the default shortcuts. This handles the extra
  `TargetPlatform.ohos` enum in this project's Flutter SDK while retaining
  support for upstream Flutter. Release 3.5.0 also fails on newer `KeyEvent` APIs.
- `lib/utils.dart`: the public export of `UnicodeV11` and its integer-returning
  `wcwidth(int codePoint)` keeps shared-core width and replay code aligned with
  the vendored terminal buffer and renderer.

Core declares `xterm` as a direct `path: vendor/xterm` dependency so apps that
depend on core by path also resolve this copy. A dependency's overrides do not
propagate to its consumers. The root xterm override remains to preserve core's
existing setup and lockfile classification. Consumer root overrides take
precedence; any xterm override must point to this same core checkout's
`vendor/xterm`, not hosted xterm. The explicit consumer `re_editor` override
still needs to point to this checkout's `vendor/re_editor`.

Hosted consumer checks must verify `package_config.json` resolves core to the
selected checkout and xterm/re_editor to its respective vendor directories.
Validation of the direct dependency change remains hosted-pending. See
`PROVENANCE.md` for the dependency declaration and source identity.

App tests exercise terminal parsing, replay, input, widgets and the real Node
PTY. Vendor lint exclusion avoids applying application formatting rules to
upstream source. Preserve these contracts when upgrading xterm; do not edit the
global Pub cache.
