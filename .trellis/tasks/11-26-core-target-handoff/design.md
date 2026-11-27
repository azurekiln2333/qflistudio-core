# Target verification design

Re-read live target path/status/remotes before mutation. Existing target is already a clone; do not reinitialize or overwrite it. Use safe fast-forward Git update after source publication, reconciling any intervening edits first. GitHub-only target must not inherit source mirror remotes.

Compare source/GitHub/target commit and tree IDs, tracked durable inventories and manifest resolution. Inspect ignored generated files separately. Do not require machine-local metadata or caches to match, and do not claim freshness from cached remote refs alone.

Send Herdr target Codex a package of final source commits, branch/change ledgers, CI/artifact references, task status, cloud-only policy, directory contract, blockers and cleanup commands. Require acknowledgement. The old coordinator remains responsible until actual acceptance; target post-handoff work may create new commits requiring another synchronization check.

Cleanup order is work preservation, active-owner readiness, eligible registered-worktree removal, scoped generated-file cleanup, then old root and separately WSL if all dependencies are released. Resolve absolute paths and check containment before any recursive operation. User requested the cleanup procedure; do not convert an ambiguous global WSL request into deletion of an unidentified image.

