# Core retirement inventory and future sequence

Execution inventory, 2026-11-27. This is not deletion acceptance. The unified directive permits inventory only; no deletion, WSL launch, export, or unregister operation is part of this migration run.

## Current eligibility

No old core root, linked worktree, shared WSL storage, or Java core-work snapshot is certified removable. The last reported inventory has 70 registered core worktrees (primary plus 69 linked), six with ordinary changes; ignored durable data and owner clearance are not yet complete. The primary `D:/MyNewProjects/qfli_studio_core/.git` is their shared Git administration. Removing it first breaks linked worktrees.

| Path or group | Current disposition | Release evidence needed |
| --- | --- | --- |
| `D:/MyNewProjects/qfli_studio_core` | Retain primary repository; original WIP preserved externally and main fast-forwarded to public baseline; migration edits in progress | All source/progress preserved, final GitHub and E-drive equality, target acknowledgement, all linked worktrees intentionally retired or independently migrated |
| `D:/MyNewProjects/_wt/wsui/*/qfli_studio_core` | Retain; historical owner handoff did not release these worktrees | Current ownership, reviewed branch/snapshot disposition, ignored-data preservation, later explicit retirement authorization |
| `D:/MyNewProjects/_wt/check-d/qfli_studio_core` | Retain; three untracked authored tests reported | Owner review and independent source preservation |
| `D:/MyNewProjects/_wt/cloudterminal-import/work/qfli_studio_core` | Retain; three untracked workflow/scripts reported | Owner review and independent source preservation |
| `D:/MyNewProjects/_wt/remote-account-binding/core` | Retain; account/desktop changes reported | Owner review, API intent and preservation; no inference that app APIs are complete |
| `D:/MyNewProjects/_wt/studio-git-integration/qfli_studio_core` | Retain; three modified files and one untracked service reported | Owner review and independent source preservation |
| `D:/MyNewProjects/_wt/ui-c/qfli_studio_core` | Retain; untracked probe test reported | Owner classification and preservation |
| `D:/MyNewProjects/_scratch/ci-sim/qfli_studio_core` and `D:/MyNewProjects/_scratch/core-sync-wt` | Retain registered worktrees; not loose scratch directories | Worktree/owner/ignored-data audit and intentional retirement |
| Root `.dart_tool/`, `build/`, Flutter/JVM logs, and agent runtime state | Generated/runtime candidates only; no blanket move or delete | Exact resolved path, reparse/owner checks, authored-file classification, backup receipt, no live writer |
| `D:/MyNewProjects/qfli_java/build/core-work` | Java-owned mixed source/private-evidence tree; retain or preserve under Java owner | Core semantic/history ledger for 21 Dart snapshots and helpers; Java backup receipt. Core does not mutate this tree |

The table identifies known holds; it is not a complete per-worktree inventory or permission to discard unlisted paths. Counts and dirty-file descriptions come from the earlier bounded audit and must be refreshed before any future retirement.

## Execution preservation update

The source coordinator preserved 70 registered worktrees' dirty/durable context in `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/snapshot-20261127T062635Z/` and verified a complete refs/reflogs bundle. Root WIP was moved to `relocated-root-wip/` only after per-file hash checks; all 56 original product files have published-history counterparts. This does not release any linked worktree or certify complete ignored-data preservation.

A separate `ignored-source/` backup holds 3,185 authored-source/configuration candidates totaling 40,675,200 bytes from root `build/` snapshots and alternative agent integrations. 2,929 normalized blobs exist in the source Git database; this alone is not proof of public reachability. All checkpoint Trellis candidates matched existing Git objects. Remaining build candidates include old publication/helper scripts, a pre-integration editor snapshot, a review diff and historical JSON fixture copies. They remain protected, not runnable current tooling or automatically safe to delete. JSON coordinator w5X:p1 was notified of its fixture copies. Generated binaries/logs outside this authored-source copy remain in place and are outside the backup claim.

## Shared WSL inventory

Only prior Windows registry evidence is used below; no guest filesystem was opened. Registry State=1 and Version=2 do not prove running/stopped status.

| Distribution | Registered storage root | Owner boundary |
| --- | --- | --- |
| Ubuntu (default) | `D:/WindowsExt/Subsystem/Ubuntu/Ubuntu_2204.1.7.0_x64` | Shared/default environment; not owned by core |
| qfli-terminal-test | `D:/MyNewProjects/qflistudio/.artifacts/terminal-runtime-test/ubuntu` | App terminal owner |
| qfli-terminal-al3-clean | `D:/MyNewProjects/qflistudio/.artifacts/terminal-runtime-test/al3-clean` | App terminal owner |
| qfli-terminal-al3-test | `D:/MyNewProjects/qflistudio/.artifacts/terminal-runtime-test/al3` | App terminal owner |
| qfli-java-build | `D:/MyNewProjects/qfli_java/build/wsl/qfli-java-build` | Java owner |

The four non-default registrations name `ext4.vhdx`. Existence and guest-only contents remain unverified here. Deleting app `.artifacts` or Java `build/wsl` as ordinary build output would conflict with these registrations. Keep these roots out of any generic build cleanup.

## Future order after migration acceptance

1. Refresh live owners, all refs/worktrees and dirty/untracked/ignored authored content. Check Java's additional authored core snapshots and source helpers against the final core disposition ledger.
2. Preserve reviewed source/Trellis in GitHub main; retain private/generated/historical variants under verified owner-controlled backup paths. Record byte identities and restoration locations without publishing private data.
3. Complete exact-candidate cloud checks and core path compatibility coverage. Verify source/GitHub/target HEAD and tree equality, ordinary clean status, cloneable progress and GitHub-only target remotes. Obtain final target acknowledgement through Herdr.
4. In a separately authorized retirement phase, inspect each exact worktree root and use Git worktree management for eligible registrations. Do not raw-delete parent `_wt`/`_scratch` trees, force-remove, or prune as a shortcut. Retain common Git metadata until no live registration depends on it.
5. WSL retirement remains a separate cross-owner operation with verified recoverability for guest-only data. Registered storage can only be considered after its owner intentionally retires the distribution; never remove its parent as a build-cache shortcut.
6. Inspect exact generated/cache paths for authored data and active writers. The current directive requires preservation rather than deletion; future disposal requires its own approved path list. Remove the old primary repository last, only after all dependencies above are closed.

No destructive command is supplied for an unverified path. Cloud CI outputs stay in cloud storage and are not downloaded into the new editing workspace.
