# GitHub consolidation and cloud-only workspace migration

## Goal

Make GitHub main the complete source of this repository, including durable Trellis progress. Move editing to the E drive clone, execute builds and tests in GitHub CI, and hand off through Herdr.

## Confirmed background

- User approved the migration plans on 2026-11-27, recorded in the unified directive's 09:35 approval section and reiterated directly in this session. User approval is complete; do not request it again. The task is now in_progress and task.py start succeeded in the current Codex session. Historical planning-state blockers are superseded. Per-request publication through the shared push gate is available again; never push directly.
- Source: D:/MyNewProjects/qfli_studio_core; target: E:/MyNewProjects/QFLIProjects/qflistudio-core. The singular QFLIProject parent does not exist.
- Initial source main: 573d1b6eecf1c2b392ad753264a5a09f62f8335e, with 46 status records before planning artifacts (20 modified tracked files plus untracked paths).
- Initial GitHub main was ee83f1c0d72708547d0692e6cd05498d3539ce02; initial source was 279 commits behind and target was clean at that commit. After the UI handoff, GitHub and CNB main both resolved to 476a30acee21dc486ee2849dd8064a7be665e4d5. During authorized execution, source main safely fast-forwarded to that baseline after independent snapshot/bundle preservation. The original 56 root product files all have published-history provenance. The target has not yet been pulled by this session.
- Source remotes: github, cnb, gitcode, gitee. Target has only origin on GitHub (azurekiln2333/qflistudio-core).
- Source ignore rules exclude important Trellis scripts, specs, workflow, journals, bootstrap task and agent setup. Full durable progress is not currently cloneable.
- Original source main at 573d1b6 had no .github directory. The aligned 476a30a baseline has core-check; the migration adds permanent fixture portability coverage. Complete six-platform product packaging cannot be inferred from core-check.
- Herdr observed source workspace w63 (Codex p1, four Pi p2-p5), and target workspace w6A (Codex p1, four Pi). Rediscover IDs if sessions change.
- This is a shared Flutter core package. Product apps/native repositories have separate workspace owners.
- Herdr owner w5H:p1 explicitly handed core main Git writes to this coordinator on 2026-11-26 at 476a30acee21dc486ee2849dd8064a7be665e4d5. Direct GitHub API verification confirms run 45656065902 passed check and screenshots for that exact SHA. The owner retains wsui/* for a 5.0.15 polish follow-up and will coordinate before another main push. Rewritten wsui/integration is 0defbf39d1ef35e4eae43717e1a910da0f9cfbe5, with failing CI reported by the owner; do not blindly merge it or remove its worktrees.
- Initial read-only audits found 65 local branches, 66 registered worktrees and six dirty worktrees. The latest source/target snapshot found 70 registered worktrees, 20 modified tracked files and 60 visible untracked source files; target remained clean at ee83f1c. Counts are snapshots, not final preservation evidence. Ignored durable documents require a separate worktree inventory. Root ignored context includes 112 durable candidates (875841 bytes), and 15 small historical raw test captures are already tracked. See research/audit-baseline.md for bounded evidence.
- App migration lead w65:p1 owns qflistudio-next source/target and six-platform installer workflows. Historical UI pane w5H:p1 is now absent from live Herdr inventory; that does not release its wsui work. SQL w62:p1 accepted exclusive ownership of E:/MyNewProjects/QFLIProjects/AGENTS.md and created its cloud-only convenience rules. Every repository still needs committed portable rules.
- Existing core main and app v5.0.13 have successful cloud runs, but the app's iOS/OHOS outputs are unsigned and macOS is not notarized. Existing runs do not certify the future integrated SHA or every product. See research/ci-baseline.md.
- App run 45912697544 completed successfully at documentation commit b052d77aa64d11c2baab686ffefadbe9f3a33156; the earlier 18-job success at da74782 is a different SHA. Neither result validates a new core migration commit or publishes a release.

## Requirements

Publication sequencing update, 2026-11-27 23:35: `core-release.md` explicitly releases Core after all other 13 repositories have migrated or completed receipts. This supersedes the earlier all-done hold. Finish only the in-progress filter overflow and Note compile fixes, statically review and commit them, then submit the exact main SHA through `push/qflistudio-core.json` with `allow: []`. After gate PASS, obtain target parity/ACK and hosted evidence. The brain owns the consumer pin-bump wave; a gate PASS is not a claim of CI success.

- R1: Inventory all remote/local branches, tags, registered worktrees, uncommitted source and ignored durable project files. Preserve legitimate work before changing branches or cleanup.
- R2: Reconcile all reviewed valid branch changes into main without reverting newer work or publishing generated outputs. Record per-branch inclusion evidence. Audit all existing remotes for unique work; GitHub is the destination of record.
- R3: Commit durable Trellis tasks/status, specs, workflow, scripts, instructions, journals and necessary agent setup. Exclude machine-specific runtime state, secrets, caches and generated build/test output; retain research decisions/provenance.
- R4: Version a cloud-only rule for every agent: no local dependency installation, build, test, native compilation, SDK bootstrap, emulator runs or artifact-generating verification. Allow source editing, lightweight read-only inventory, Git and remote CI inspection. Apply to both directories immediately.
- R5: Audit cloud native/Flutter intermediates and Windows, Linux, macOS, iOS, Android and OHOS installable package workflows. Coordinate app-specific work through Herdr with the owning agents. Verify pinned inputs, payloads, packaging, artifact retention and actual runs; disclose signing/runner/access blockers. Make the core ArkTS contract test checkout-folder-independent: resolve core-owned source by Dart package identity, and load required app/Java fixtures from explicit validated roots with documented legacy sibling aliases only as defaults. Retain all assertions and report exact missing paths/configuration keys; never mask missing fixtures with a compatibility symlink or skipped coverage.
- R6: After verified GitHub publication, update the target through Git. Prove source/GitHub/target main commit/tree equality, complete durable progress and clean source/target status. Keep only GitHub remote(s) in target.
- R7: Prepare scoped old-directory/build/WSL cleanup only after preservation. Identify exact paths and ownership; do not destroy shared WSL or unrelated product work before all affected owners are ready.
- R8: Use Herdr only for inter-agent communication. Prefer the existing four Pi with gpt-6.1-sol; retry concurrency errors, compact/renew for turn limits, and fall back to deepseek-v4.1-flash only after preferred recovery fails. Give workers explicit ownership and prohibit reverting others.
- R9: Handoff through Herdr to target Codex with final commits, branch ledger, preservation audit, CI run/artifact references, cloud-only rules, blockers and cleanup procedure. Record acknowledgement.
- R10: Keep the Dart package/import name qfli_studio_core. The target editing folder is qflistudio-core. Coordinate app-owned relative dependencies, vendor overrides and CI checkout/patch paths as a unit; retain existing CI aliases until their owning workflows migrate coherently. Publish final immutable core SHA only after active UI work and cloud validation.

## Acceptance criteria

- [ ] A1 (R1-R3): Every inventoried branch/worktree/change has an explicit disposition; no legitimate source or durable progress is lost.
- [ ] A2 (R2-R3,R6): Source main, GitHub main and target main have identical verified commit/tree IDs; both workspaces are clean after final documentation commits. Fresh clone includes complete durable Trellis context.
- [ ] A3 (R3-R4): No accidental build outputs, caches, SDKs, test captures or secrets are tracked; agents can discover the cloud-only rule from AGENTS.md and Trellis guidance.
- [ ] A4 (R5): Six-platform coverage records owning repo, workflow, immutable inputs, native/Flutter intermediates, package and successful cloud run/artifact evidence. Missing evidence remains incomplete.
- [ ] A5 (R7): Cleanup instructions list exact workspace/worktree/cache/WSL targets, preservation evidence and operation order. Shared WSL removal requires cross-owner readiness.
- [ ] A6 (R8-R9): Herdr target Codex acknowledges the handoff and can continue from committed progress.
- [ ] A7 (R10): Dependent workspace owners acknowledge the final core SHA and directory/CI compatibility contract; no accidental package rename or unresolved local path assumption is introduced.
- [ ] A8 (R5): GitHub-hosted path coverage passes for canonical `qflistudio-core`, legacy `qfli_studio_core`, and relocated app/Java fixtures supplied through explicit roots, using the same immutable core/app/Java inputs. Negative resolver cases for absent or invalid fixture roots fail with actionable path/configuration errors; the full contract assertions remain enabled.

## Scope boundaries

- Direct ownership is core and its migration. Coordinate product app/native repositories and machine-wide WSL with their owners instead of taking over.
- Source equality excludes intentionally ignored generated outputs and machine-local runtime metadata. CI intermediates/packages remain in cloud storage, not source commits or target downloads.
- Branch integration does not authorize forced pushes, history rewriting or premature deletion of worktrees/branches.
- No local builds or tests, including temporary diagnostic runs in the old directory.

## Deliverable map and dependencies

- 11-26-core-github-preservation owns R1-R3 and source integration evidence. The core main writer handoff and user approval are received; implementation is active. Refresh all worktree and ignored-document inventories, while respecting continuing ownership of wsui polish branches. Include the 21 authored core-work Dart snapshots and source helpers reported by Java; differing contents require semantic/history review, not automatic overwrite or discard.
- 11-26-core-cloud-ci-policy owns R4-R5 and R10. CI audit can proceed read-only during planning; final runs/pins depend on the integrated candidate from preservation. App-specific changes belong to their respective owners.
- 11-26-core-target-handoff owns R6-R9. Final pull/comparison depends on preserved source publication and cloud-policy/CI evidence. Destructive cleanup additionally depends on every affected active owner being ready.
- The parent owns cross-child acceptance and final integration review. No child is activated merely because its files exist.

## Deferred execution dependencies

- Core main handoff is available at 476a30a. The final migration SHA remains pending source/progress preservation, other branch dispositions and fresh cloud validation. The failing rewritten wsui polish series stays an explicit outstanding branch item.
- Signed iOS/OHOS distribution and macOS notarization remain credential/workflow dependencies; exact access and runner gaps must be resolved by their owners and actual runs. A workflow file alone never satisfies A4.
- Shared WSL resources require their own project owners' preservation/readiness evidence. These are execution gates, not reasons to guess a final migration result.
- As of the 2026-11-27 planning continuation, published main remains 476a30a and no final migration SHA exists. Its checked SDK is Flutter-OHOS 3.41.10-ohos-1.0.1 at adaf911c35c9136a7d18fc424d714c9ec7724e60. The R5 checkout-portability fix and hosted matrix remain pending. Rust's proposed flutter-oh-3.41.9+ohos-1.0.2 and official Flutter 3.50 consumer adaptations require separate exact-input cloud evidence. Reported Web runtime test failures are unresolved; do not promise that a future core SHA fixes them. Details are in research/ci-baseline.md.

