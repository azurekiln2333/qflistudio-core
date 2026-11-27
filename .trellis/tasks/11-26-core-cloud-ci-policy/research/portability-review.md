# Portability review — bounded source sign-off

Date: 2026-11-27. Reviewer: Herdr w63:p5; implementation owner: w63:p4; coordinator: w63:p1. Baseline HEAD: `476a30acee21dc486ee2849dd8064a7be665e4d5`. Candidate is uncommitted.

**Disposition: ready for coordinator staging as an unvalidated cloud candidate.** No remaining substantive static blocker was identified in the four-file scope after the resolutions below. This is not formatter, analyzer, test, workflow-execution or migration acceptance. Exact formatting belongs to the first hosted candidate run; stop further speculative formatting cycles.

## Scope and package/spec check

Read the parent `check.jsonl` and every referenced document, then parent PRD/design/implementation plan; also reviewed the cloud-policy child artifacts, backend index/quality guidance, `interop-fixtures.md`, cloud-only guidance, package `pubspec.yaml` and analyzer configuration. Inspected the complete contents of all four affected files and the tracked diff against the baseline:

- `.github/workflows/core-check.yml`
- `test/interop_arkts_contract_test.dart`
- `test/interop_fixture_roots_test.dart`
- `test/support/interop_fixture_roots.dart`

The sole affected Dart package remains `qfli_studio_core` (SDK constraint `^3.11.5`). Imports resolve structurally to existing dependencies and the new relative support file; no new dependency or production API change is introduced. Read-only SDK source inspection confirms `Isolate.resolvePackageUriSync` is available since Dart 3.2 and `StateError.message` is a string. Runtime package resolution still requires hosted execution. The implementation matches the interop fixture spec's explicit/default roots and error contracts; no additional spec change was identified within this bounded scope.

## Findings and resolutions

1. **Negative coverage was conditionally omitted. Resolved by p4 following coordinator direction:** removed `runNegativeCases` and its environment gate. All six App/Java cases—absent directory, missing required file and empty value for each key—now register in every complete suite, including consumer runs. Each uses an injected environment map and requires `StateError` plus the appropriate configuration key and, where applicable, exact path.
2. **Portability evidence was runner-console/temp only. Resolved by p4:** retained layout identities, positive analyze/full-suite logs, focused resolver logs and negative contract logs. Upload uses `interop-path-${{ matrix.mode }}-${{ github.sha }}-${{ github.run_attempt }}`, with mode-specific file prefixes, `if: always()` and 14-day retention. Names do not collide with existing verification/screenshots artifacts. Pipelines retain failure status with `pipefail`.
3. **Redundant positive focused contract runs. Resolved by p4:** both duplicate steps were removed; canonical, legacy and relocated modes each retain complete analysis and the complete suite, including the original ArkTS contract tests.
4. **Formatting exposure and transient timeout loss. Addressed:** p4 repaired the definite stray-space defect and manually adjusted source layout; the matrix has a bounded 45-minute timeout again. Exact formatter cleanliness is deliberately unconfirmed. The format step always includes all three migration Dart files, independently of the latest commit's changed-file list, so a later documentation-only commit cannot remove this coverage.

## Retained contracts and safety

- Baseline diff retains every original contract assertion and test group: protocol/allowlist/caller, caps/path grammar, channel keys/probe behavior/errors/permissions, Dart response keys, Java language/refusal/output and ability/module contracts. Changes concern fixture roots and formatting, not weakened expectations, skips or replacement fixtures.
- Core resolution uses the exact `package:qfli_studio_core/interop/interop_protocol.dart` identity, derives its package root and checks source/pubspec presence; it no longer derives core from the current directory or checkout basename. App/Java keys normalize explicit roots, reject empty values, validate all five real fixture paths and preserve documented sibling defaults.
- All five matrix modes share core `${{ github.sha }}`, App `69656b4ab14e706e85907ef4c4205d8cd35a1338`, Java `60d97c783f29da767fafe503980812101f6aa61f`, and Flutter-OHOS `3.41.10-ohos-1.0.1` / `adaf911c35c9136a7d18fc424d714c9ec7724e60`. Layout guard checks checkout HEADs. Canonical and legacy exercise defaults; relocated supplies both absolute roots.
- Negative workflow modes require a nonzero contract command plus the corresponding key and exact missing path; focused resolver tests independently cover both roots' three failure classes. Unrelated setup/compile failure alone cannot satisfy the expected-error checks.
- Jobs use `ubuntu-24.04`; the matrix explicitly requires GitHub Actions and `RUNNER_ENVIRONMENT=github-hosted` before SDK setup. No symlink adaptation is added. Existing check/screenshots jobs and reports remain. Actions stay immutable-pinned, permissions remain read-only and checkouts disable credential persistence. SDK/pub caches and generated evidence remain hosted.

## Reviewed byte identities (SHA-256)

| File | SHA-256 |
| --- | --- |
| `.github/workflows/core-check.yml` | `F4083E1EA4439128D9862D13837B37914CB51098786E4844369BEB24966AF4DC` |
| `test/interop_arkts_contract_test.dart` | `25AA782855D2B73E627EFA28C6F04EA1678B81364A4152DCF7FAF7F78BAEA63E` |
| `test/interop_fixture_roots_test.dart` | `FCECB55CF27D32D9DF6E2A49039FDEFFBC3ECBC2F567B4D3347991E325E18295` |
| `test/support/interop_fixture_roots.dart` | `73E170704AF971B311B8469BDB537F4E41CC74E8C04053107DF951726E785B6E` |

Findings/resolutions and source freeze were coordinated through Herdr with p4/p1. Reviewer wrote only this report, did not spawn workers or mutate Git, and performed no local build/test/format/analyze/install/download/WSL operation. No candidate execution success is claimed. Publication remains coordinator-owned with the scheduler paused. Before acceptance, the exact staged candidate needs successful hosted formatting, analysis, complete suites for all three positive layouts, both negative modes and screenshots, with immutable run/job/artifact evidence. Any later source change falls outside these byte identities and requires targeted re-review. Preservation, export/patch ledgers, six-platform acceptance and target handoff are outside this review.
