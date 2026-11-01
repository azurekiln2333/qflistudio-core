# qfli_studio_core

Shared Flutter IDE package for QFLIStudio and the language apps. This Git repository also contains the patched `re_editor` package in `vendor/re_editor`.

Check out this repository alongside `qflistudio` and the language app repositories. Each app references it through a sibling path dependency and resolves its own lockfile.

## Vibe Coding acceptance driver

`tool/vibe_e2e.dart` drives `VibeCodingController` headless against the debug
upstream and writes a JSON report.

```bash
# Offline self-check of the report model and the scenarios.
flutter test --no-pub test/vibe_e2e_harness_test.dart test/vibe_e2e_runner_test.dart

# Live scenarios against the debug upstream. The whole file skips when any of
# the three variables is missing; the driver never opens a credential file.
flutter test --no-pub test/vibe_live_e2e_test.dart
```

The report stores the upstream host, the model name, whether a key was present
and its length. It never stores the key. Reports default to
`<scratch>/.artifacts/vibe-e2e/` so prompts and source snippets stay out of every
Git root.

`qflistudio/tool/verify_vibe_e2e.dart` is the operator entry: it checks the
environment, runs the live host above and prints a table. See
`qflistudio/docs/vibe-acceptance.md` and
`qflistudio/.trellis/spec/frontend/vibe-e2e.md`.

`dart run` alone cannot load this package, because it imports Flutter. That is
why the live host is a `flutter test` file; `tool/vibe_e2e.dart` stays as the CLI
for an SDK-side adapter and shares `tool/vibe_e2e_runner.dart` with the test.

## Tests

```bash
flutter analyze --no-pub
flutter test --no-pub
```
