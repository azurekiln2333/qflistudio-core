# Preserved source and branch variants for follow-up review

This directory preserves authored changes discovered during the migration. Everything here is inert research, not enabled product functionality, an approved merge, or evidence that a deferred feature should be activated. The follow-up task remains in planning; any adoption requires a reviewed plan and cloud verification.

## Dirty linked-worktree changes

`wip-patch-manifest.json` maps seven original-parent-relative patches to snapshot IDs, source paths, original SHA-256 hashes, derivative hashes and patch hashes. Together they account for 41 authored files from five dirty linked worktrees. They are not diffs from current main back to an older tree.

| Patch | Files | Purpose and follow-up gate |
|---|---:|---|
| `remote-account-binding.patch` | 14 | Account/relay API, controller, screen integration and tests. Review owner boundaries, grants, credential handling and races. |
| `desktop-companion.patch` | 16 | Companion connection/session/UI source and tests. Review independent service ownership, platform support and lifecycle. |
| `project-config-guard.patch` | 3 | Proposed protected-path checks for local/cloud deletion; requires a separate design and hosted safety regressions. |
| `trellis-rule-bootstrap-covered.patch` | 1 | Historical rule delta already covered by published/shared Trellis resolution; preserve provenance, do not replay. |
| `remote-control-ci-historical.patch` | 3 | Older paired-revision workflow/helper assumptions; not current CI policy. |
| `agent-ui-diagnostics.patch` | 3 | Diagnostic source only; screenshots/captured outputs omitted. |
| `tools-scrollable-probe.patch` | 1 | Print-oriented probe, not accepted behavioral coverage. |

These are source-recovery artifacts only. No local product tests, formatters, analyzers, SDK setup or builds were run. The recorded sanitization is limited to the exact transformations listed in the WIP manifest; do not infer that every other historical-looking string is synthetic or scrubbed. Real auth stores, attachment/session transcripts, device captures, SDKs, screenshots and build outputs are excluded.

## Branch-history derivatives

The branch recovery collection is `branches/branch-patch-manifest.json` plus its `branch-*.patch` files. It maps 30 noncontained local/advertised refs and 83 unique commits to 52 distinct, deduplicated text-patch artifacts. Each exported derivative is based on that commit's original first parent; original commit order and parent IDs are in the manifest. The original full histories are retained only in the external refs/reflogs bundle; these derivatives preserve selected text deltas, not original branch commit objects or a claim of semantic uniqueness.

Patch-ID matches record normalized textual equivalence only. Published `main` has later harness, remote, hub and Trellis implementations in these domains; semantic supersession/adoption review is deferred and is **not a migration acceptance blocker**, because none of these features is being activated by this task. Do not infer that branch functionality is absent solely because a historical tip is not an ancestor of current main.

The `ci/mobile-diag` test change is content-equivalent to published `github/ci/mobile-files` (`d3d899571382121d3b5d69dd36b60222e5fa0b37`); no duplicate patch is needed. The branch's workflow narrowing is excluded.

For the `harness/pi-b` original commit `c1625ad65f78bf1d35b0ec9547c3da01c4d8f3e9`, derivative `branch-039-e7f31261900e.patch` excludes the entire `test/harness_herdr_models_test.dart` section because its comment attributes fields to real command output and exact IDs, paths, titles and session values have unverified provenance. Companion `test/harness_herdr_platform_test.dart` is also excluded for machine-specific paths. Field names may be schema-derived; exact sample values are not established as synthetic. Do not call them synthetic or enable the test without owner-confirmed provenance or a separately reviewed synthetic replacement. The current derivative has patch ID `581df5505cbdc5c1276e788ec6a98f37252f0dbb`, SHA-256 `724ebf9523bfcde50890fe3149ca7232c10d3a53a8b83fa458011c2c001eae3e`, and size 190767 bytes. Pre-exclusion patch ID `29a0f00a7bbc903ecffa8d0a2cdc55a3b1387a64` is retained in the manifest as provenance.

These files are inert preservation research. They are not a migration feature list, merge recommendation, or claim of approved behavior. Semantic/adoption review may be deferred to the planning follow-up without blocking migration closure.

## Root work

Root pre-fast-forward work and portable-context import are tracked separately in the preservation ledger and root-owned snapshots; do not duplicate that inventory here.

## Recovery boundary

Original refs/reflogs and original snapshot bytes remain at `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/`, including the verified bundle and `snapshot-20261127T062635Z`. These local backups preserve original commit identities and excluded material. The portable research derivatives do not authorize deleting the backup or linked worktrees. Before adopting a patch, compare its exact parent/paths with current source, obtain the follow-up task's implementation approval, and verify through GitHub CI. Never replay historical publication scripts.
