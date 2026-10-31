# qfli_studio_core

Shared Flutter IDE package for QFLIStudio and the language apps. This Git repository also contains the patched `re_editor` package in `vendor/re_editor`.

Check out this repository alongside `qflistudio` and the language app repositories. Each app references it through a sibling path dependency and resolves its own lockfile.

## Vibe Coding acceptance driver

`tool/vibe_e2e.dart` drives `VibeCodingController` headless against the debug
upstream and writes a JSON report.

```bash
# Offline self-check of the report model and the scenarios.
flutter test --no-pub test/vibe_e2e_harness_test.dart

# One scenario against the debug upstream. The three variables come from the
# process environment; the driver never opens a credential file.
dart run tool/vibe_e2e.dart --scenario python_fix_loop
```

The report stores the upstream host, the model name, whether a key was present
and its length. It never stores the key. Reports default to
`<scratch>/.artifacts/vibe-e2e/` so prompts and source snippets stay out of every
Git root.

`qflistudio/tool/verify_vibe_e2e.dart` is the operator entry: it checks the
environment, runs this driver and prints a table. See
`qflistudio/docs/vibe-acceptance.md` and
`qflistudio/.trellis/spec/frontend/vibe-e2e.md`.

`dart run` alone cannot load this package, because it imports Flutter. A live
scenario run needs the Flutter test runner or an SDK-side adapter.

## Tests

```bash
flutter analyze --no-pub
flutter test --no-pub
```
