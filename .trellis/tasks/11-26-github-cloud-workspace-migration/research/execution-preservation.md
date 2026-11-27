# Migration execution preservation

Recorded 2026-11-27. This is preservation evidence, not final migration acceptance.

## Independent recovery copy

The coordinator created `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/` before source realignment. `all-refs-and-reflogs.bundle` contains all refs and reflog-reachable history, including linked-worktree HEADs. `git bundle verify` reported a complete history and a valid bundle. Its SHA-256 is `104A7192E63C19DE09486DEC5ACBF2AAA77C44600FF788BCF343828A08A5C69A`.

`snapshot-20261127T062635Z/manifest.json` records the original 70 registered worktrees, their HEAD/ref metadata, changed/untracked product files and portable/runtime context snapshots. The snapshot holds 5,051 files totaling 15,409,564 bytes. Each copied file was hashed before copying, after copying, and again at its source; unequal hashes aborted preservation. Private/runtime context remains outside Git. Per-worktree `tracked.patch`, `index.patch`, and `status.z` preserve the initial source-control state.

The root's 20 changed tracked and 36 untracked product files were separately moved to `relocated-root-wip/` only after source and snapshot SHA-256 values matched the manifest. Every resolved move target was checked to remain under the named source/preservation roots. No linked worktree, ignored build tree or WSL storage was moved or deleted.

## Source realignment

GitHub fetch still advertised main `476a30acee21dc486ee2849dd8064a7be665e4d5`. Source main `573d1b6eecf1c2b392ad753264a5a09f62f8335e` was verified to be its ancestor. After external WIP relocation, only the explicitly preserved tracked product paths were restored from the old HEAD. Three files required index-stat/newline normalization; their filtered working blobs were checked equal to index blobs and the staged diff was empty. Main then fast-forwarded to the public baseline. No reset, force push or history rewrite occurred.

Pi w63:p5 established same-path published-history provenance for all 56 original product files. See `../../11-26-core-github-preservation/research/root-wip-disposition.md` for the final per-file ledger. Obsolete source must not overwrite later published refactors. Independent backup retention continues until all preservation, publication, cloud validation and handoff gates pass.

## Work ownership

The coordinator alone owns Git index/ref changes. Pi w63:p2 owns branch/context history disposition; p3 owns durable context and cloud policy; p4 owns the permanent interop fixture resolver and hosted portability coverage; p5 owns source-WIP provenance and independent review. All four model displays confirmed `gpt-6.1-sol` after fresh sessions. Communication uses Herdr. Product builds, tests, analysis, formatting and dependency installation remain cloud-only.

The earlier scheduler pause was superseded by the user's per-request gate availability update. A candidate may only be published by the shared push gate after content review, a clean main tree and fast-forward proof. No final core SHA, target parity, deletion clearance or accepted target handoff is asserted here.

The subsequent user-directed core-last ruling at 17:00 on 2026-11-27 adds a publication hold: no core push request until the brain explicitly confirms all other repositories have done.json. Local preparation/review continues; published main remains the tested provisional baseline. The later pin-bump wave belongs to the brain and consuming owners.
