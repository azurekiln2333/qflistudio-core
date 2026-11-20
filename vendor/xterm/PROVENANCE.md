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
would drop that patch and break the OpenHarmony build, so the package is copied
into the shared core and pinned by path:

```yaml
# pubspec.yaml
dependencies:
  xterm: ^4.0.0
dependency_overrides:
  xterm:
    path: vendor/xterm
```

The override resolves inside this package, so an app that depends on
`qfli_studio_core` never needs the `cloudterminal` source checkout.

## The one source patch

`lib/src/ui/shortcut/shortcuts.dart`: Apple platforms keep their own shortcuts.
Every other platform (including custom ones such as OpenHarmony) uses the
default shortcuts. This keeps the extra `TargetPlatform` value from making the
exhaustive switch non-exhaustive.

## Maintenance rules

- Do not upgrade in place without re-applying the patch above.
- Do not edit the global pub cache. Edit this copy instead.
- `vendor/**` is excluded from the host `analysis_options.yaml`, so application
  lints and formatting rules are not applied to upstream source.
- Keep `LICENSE` and this note when the copy is refreshed.
