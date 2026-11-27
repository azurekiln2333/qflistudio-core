# Cloud-only verification and durable evidence

## Scope

Applies to every code, test, documentation, CI, and platform-integration change in this repository. Local environments are for source editing and lightweight read-only inspection only; verification and generated outputs belong on GitHub-hosted Actions.

## Allowed local activity

- Read, search, compare, and edit source, documentation, tests, and configuration.
- Inspect Git status, refs, trees, ignore decisions, and remote workflow/run metadata without changing shared repository state.
- Use read-only GitHub API/CLI metadata and logs to inspect cloud runs; keep large artifacts in cloud storage.

## Prohibited local activity

Do not run builds, tests, benchmarks, emulators, native compilation, formatters, analyzers, code generators, package-manager operations that generate outputs, dependency installation/restoration, SDK bootstrap, or artifact/cache downloads into a workspace. Do not run Flutter, Dart, Gradle, CMake, Ninja, Xcode, Hvigor, or package-manager commands when they generate output. This applies equally to temporary diagnostic scripts that invoke product/build/test code.

Run these checks through the repository's GitHub-hosted workflows. Record repository, immutable source SHA, workflow/run ID, relevant job conclusions, artifact references/retention, and signing or platform limitations before reporting validation. A workflow file, skipped job, adapted runner, or unsigned package is not proof of completed platform acceptance.

## Durable context and privacy

Version durable project instructions, Trellis workflow/scripts/specs/tasks/research and developer journals. Keep secrets, user-level trust/authentication, session pointers, runtime state, caches, SDKs, generated build/test output, and raw reproducible captures out of Git. Replace useful raw-run material with concise summaries carrying evidence provenance; preserve original captures only in a reviewed external backup or historical Git object database.

Allowlist portable agent integration by reviewed paths and formats. Do not commit complete agent-platform directories or runtime settings merely because they contain workflow text. Preserve unclear variants externally and record the disposition instead of guessing which copy is canonical.

## Good / Base / Bad

- Good: edit source locally, dispatch the exact candidate to GitHub-hosted validation, and report the immutable SHA and run evidence.
- Base: inspect cloud metadata without downloading generated artifacts.
- Bad: run a local analyzer/test or restore packages and then describe the result as cloud validation.

## Tests and evidence

There are no local verification commands under this policy. Use the owner repository's existing hosted workflow; if it does not cover a required check, keep the acceptance item explicitly incomplete and coordinate workflow ownership before adding CI.

## Wrong vs correct

Wrong: infer platform success from workflow YAML or from a green run on another SHA.

Correct: link the exact candidate SHA to terminal hosted jobs and artifact/signing evidence, and state all missing coverage.
