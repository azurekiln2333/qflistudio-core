# Vendored xterm.dart 4.0.0 (CloudTerminal fork)

Provenance note for `qfli_studio_core/vendor/xterm`.

| Field | Value |
| --- | --- |
| Package | `xterm` 4.0.0 |
| Origin | https://pub.dev/packages/xterm/versions/4.0.0 |
| Upstream | https://github.com/TerminalStudio/xterm.dart |
| License | MIT — retained verbatim in `LICENSE` (Copyright (c) 2020 xuty) |
| Migrated from | `cloudterminal/third_party/xterm` at source HEAD `49b2aac781858929a19307faeb808b83f8154410` |
| Vendored on | 2026-11-20, as part of the CloudTerminal → QFLIStudio migration |

## Why it is vendored

The CloudTerminal build patches upstream xterm for this project's Flutter SDK
(an extra `TargetPlatform.ohos` enum member, plus newer `KeyEvent` APIs that
release 3.5.0 fails on). Replacing this fork with an unrelated pub.dev version
would drop the retained compatibility changes and break the OpenHarmony build,
so the package is copied into the shared core and pinned by path:

```yaml
# pubspec.yaml
dependencies:
  xterm:
    path: vendor/xterm
dependency_overrides:
  xterm:
    path: vendor/xterm
```

The direct path dependency resolves relative to this core checkout when an app
depends on `qfli_studio_core` by path. Dependency overrides in dependencies do
not propagate to the consuming app, so the direct declaration is required; a
core-only override would otherwise leave consumers using hosted xterm 4.0.0.
The retained root override preserves the existing core setup and lockfile
classification. Neither arrangement requires a `cloudterminal` source checkout.

A consuming app's own root overrides take precedence. If it overrides `xterm`,
that override must select this same checkout's `vendor/xterm`, never the hosted
package or a different core checkout. The existing explicit consumer override
for `re_editor` must still select this checkout's `vendor/re_editor`.

Hosted consumer validation must inspect the resolved `package_config.json`:
`qfli_studio_core` must resolve to the selected core checkout, `xterm` to its
`vendor/xterm`, and `re_editor` to its `vendor/re_editor`. Hosted validation of
this direct dependency change remains pending.

## Retained source contracts

`lib/src/ui/shortcut/shortcuts.dart`: Apple platforms keep their own shortcuts.
Every other platform (including custom ones such as OpenHarmony) uses the
default shortcuts. This keeps the extra `TargetPlatform` value from making the
exhaustive switch non-exhaustive.

`lib/utils.dart` publicly exports `src/utils/unicode_v11.dart`, including
`UnicodeV11` and its integer-returning `wcwidth(int codePoint)`. Shared-core
terminal width and replay code use this API to stay aligned with the vendored
terminal buffer and renderer. Hosted xterm 4.0.0 is not an interchangeable
replacement for this public width contract.

## Maintenance rules

- Do not upgrade in place without preserving both contracts above.
- Do not edit the global pub cache. Edit this copy instead.
- `vendor/**` is excluded from the host `analysis_options.yaml`, so application
  lints and formatting rules are not applied to upstream source.
- Keep `LICENSE` and this note when the copy is refreshed.
