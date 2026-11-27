# Preservation design

Use parent design.md and research/audit-baseline.md as the contract. Treat source root plus every registered worktree as the preservation boundary (70 at the latest snapshot; refresh before execution). Inventory ignored Trellis docs separately from git status. Core main writer handoff has arrived, but continuing wsui work remains protected; do not use a stale SHA as final authority.

Preserve reviewed dirty work in explicit commits/refs before branch changes. Reconcile with current main using ancestry and content evidence, retaining superseded intent/provenance without replaying stale code. Review shared index contents before each commit; workers must not stage or commit concurrently.

Narrow .gitignore to runtime/generated exclusions and explicit portable agent setup. Track workflow/scripts/specs/journals/tasks/research decisions; repair archived references. Preserve historical capture blobs then replace raw current captures with durable results when justified. Inspect for secrets without displaying values.

Output is reviewed candidate main plus durable branch/change/context ledgers. Rollback uses retained original refs and snapshots; no destructive reset or force push.

Java's `build/core-work` snapshots are additional preservation inputs, not replacements for current core files. Its owner retains originals/private backup; core assesses semantic and historical inclusion using the fixed published baseline and source evidence. A difference in bytes alone establishes neither unique work nor supersession. Record each authored snapshot and helper as covered, useful pending work, or unresolved, with immutable counterpart/provenance evidence and no deletion authorization. Private coordination, screenshots, and raw logs stay outside the public tree; never publish the mixed directory wholesale.

The unified directive requires GitHub publication through the external push gate only. Coordinator submits the exact reviewed main commit and narrow path allow reasons in `D:/MyNewProjects/_orchestra/push/qflistudio-core.json`; the external gate performs checks and publishes. Source edits, GitHub Actions evidence, and target alignment must refer to the actual accepted SHA, not merely the submitted request. Private/secret-bearing branch contents are retained outside GitHub and receive disposition entries; they are not merged to satisfy branch-count goals.

