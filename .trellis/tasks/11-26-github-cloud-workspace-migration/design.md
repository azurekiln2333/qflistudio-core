# Migration design

## Ownership and state

The parent coordinates three children. Source is D:/MyNewProjects/qfli_studio_core; target is E:/MyNewProjects/QFLIProjects/qflistudio-core. GitHub azurekiln2333/qflistudio-core main is the publication authority. Existing non-GitHub remotes are evidence sources, not additional target remotes.

Herdr is the communication transport. Source coordinator is observed w63:p1; four Pi w63:p2-p5 own separate research/implementation reviews. Target coordinator is observed w6A:p1. Resolve live IDs before later actions. Claude w5H:p1 handed core main writes to this coordinator at 476a30a, but retains wsui/* for the active 5.0.15 polish follow-up; its rewritten integration branch is not yet accepted. Rust w61:p1 owns Rust migration and waits on the final core SHA. Never infer branch/worktree release from a main writer handoff or a clean status snapshot.

The historical w5H pane is no longer live; re-establish any continuing owner before changing its protected work. App migration lead w65:p1 owns app six-platform packaging. SQL w62:p1 exclusively owns the shared parent AGENTS.md convenience policy; core owns its repository-local versioned instructions. Do not edit another owner's files or substitute the unversioned parent rule for cloneable instructions.

## Preservation and reconciliation

Inventory refs, live remote heads/tags, registered worktrees, dirty files and ignored durable context separately. Record paths, baseline commits, content identities, classification and ownership. Refresh moving refs after writer handoff. Review each worktree's Trellis context, not only the primary worktree or git status.

Preserve source snapshots before rebasing, resetting or resolving a conflict. Small explicit preservation commits/refs may be used when their staged content is reviewed and excludes generated output and secrets. Do not stash and forget unique work. Integrate reviewed branches with ancestry/content evidence; when old work was superseded, retain original history and document the exact equivalent/superseding change. Do not replay obsolete UI over current UI merely to make a branch look merged. No blanket ours strategy, forced push, automatic branch deletion or forced worktree removal.

Once the source tree is reviewed and preserved, integrate the final active-owner main and remaining valid changes. Maintain a single Git writer and explicit file ownership for parallel edits. Other agents may review independent paths; they must not touch the shared index. Remote main movement triggers a refresh and another candidate, not overwrite.

## Durable context versus generated state

Version workflow, project configuration, scripts, agents/skills/hooks, specs, current/archived tasks, research conclusions and journals needed to resume on another PC. Remove broad ignore rules which hide these. Retain narrow ignores for identity, runtime/session pointers, credentials, caches, SDKs, builds, test output, raw reproducible captures and template hashes. Review Pi portable integration separately rather than exposing its entire runtime directory.

Repair archived manifest references and prove every context manifest target exists in the final tracked tree. Keep original historical capture blobs in Git history; replace current-tree raw captures only with durable summaries preserving provenance and original commit/blob IDs. Fonts, test fixtures and vendored source are not automatically build artifacts.

## Cloud verification and path contract

The target folder is qflistudio-core, while the Dart package name remains qfli_studio_core. Existing GitHub runners intentionally check out core as qfli_studio_core and related repos as qflistudio/qfli_java. Preserve these aliases unless each consuming workflow, relative dependency, vendor override and patch script changes together. Under the 2026-11-27 Note compile ruling, core now provides the narrow explicit `tool/ci/prepare_flutter_core.py` runner entry point derived from the immutable app-owned shim. It validates exact SDK flavor/revision and reviewed source before replacing only the Huawei view for official Flutter; OHOS keeps the native implementation. Consumers must invoke it explicitly during the coordinated pin wave. See backend/core-consumers.md for the executable contract and hosted-evidence limits.

Record the no-local-build/test/install/SDK/artifact-download policy in the unmanaged portion of AGENTS.md, versioned Trellis workflow/specs and handoff docs. Use Git and read-only source inspections locally; execute formatting verification, analysis, tests, native compilation and packaging on cloud runners. Do not silently substitute a local self-hosted runner. Source policies guide all agents; they are not a claim that arbitrary shell commands are technically sandboxed.

Core CI must validate the final candidate. A platform coverage matrix maps Windows, Linux, macOS, iOS, Android and OHOS to owning repo, workflow, immutable source inputs, native/Flutter stages, intermediate storage, installable output, signing requirements and run/artifact evidence. Coordinate missing app/native workflows with the owning workspaces. Distinguish unsigned outputs from installable signed distribution packages. Store intermediates and packages in cloud caches/artifacts/releases with deliberate retention, not Git or the editing clone.

The published `test/interop_arkts_contract_test.dart` at baseline `476a30a` resolves its own source through a hardcoded `qfli_studio_core` sibling path and reads required app/Java source fixtures from the parent directory. At canonical checkout `qflistudio-core`, this breaks test-suite loading before assertions. The permanent design resolves the core transport source by Dart package identity `qfli_studio_core`; app and Java roots are explicit, validated fixture-root inputs, with legacy `qflistudio` and `qfli_java` sibling defaults documented for existing jobs. Missing fixtures must fail with the missing path and expected configuration key. Keep all existing contract assertions active. A GitHub-hosted matrix must exercise canonical core checkout, legacy core alias, relocated explicit app/Java roots, and negative absent/invalid-root cases with identical immutable core/app/Java revisions. A runner symlink is migration evidence only and cannot replace the source fix.

## Equality, handoff and cleanup

After a candidate is published and validated, update target main by safe fast-forward pull from its sole GitHub remote after rechecking it is clean. Compare source/main, remote/main and target/main full commit and tree IDs. Audit final tracked durable files, manifests, untracked status and ignored generated paths independently. Git status alone does not prove progress completeness or disk cleanliness.

Send a concrete handoff package through Herdr to the target Codex; it identifies evidence, remaining obligations, final SHA, active progress and cleanup steps. Obtain acknowledgement. Any target follow-up commit needs another source/remote/target alignment; avoid an endless self-referential commit hash inside the same commit by recording evidence against the completed candidate and communicating the final documentation commit separately.

Cleanup follows verified preservation. The old root contains the common Git directory for 70 worktrees at the latest snapshot, so deleting it first would break them. Refresh that inventory before execution. Classify each exact path and owner before removing eligible worktrees, then generated directories. WSL distributions under other product directories are a separate cross-owner operation. Provide commands only for identified, ready targets; never run blanket git clean -fdx or recursive parent deletion.
