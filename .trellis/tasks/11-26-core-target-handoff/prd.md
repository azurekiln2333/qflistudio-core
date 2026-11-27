# Verify E drive core migration and hand off cleanup

## Goal
Make the target GitHub-only clone a complete, clean continuation point and hand it to its Codex with verifiable evidence and safe cleanup instructions.

## Requirements
Own parent R6-R9. Recheck E:/MyNewProjects/QFLIProjects/qflistudio-core and sole GitHub origin, pull only after source publication, compare full commits/trees and durable progress, audit untracked/ignored generated paths. Hand off through Herdr with evidence. Provide precise old-directory/worktree/cache/WSL cleanup phases.

## Dependencies
Preservation must publish reviewed source/progress and cloud-policy must supply required CI/policy evidence. Core main writer handoff has arrived at 476a30a, but active wsui polish branches/worktrees remain protected until their owner releases them. Target Codex is reserved read-only until the final handoff. Shared WSL cleanup requires each owning project's preservation readiness. Current target pre-handoff acknowledgement is not final completion.

## Acceptance
- Source main, live GitHub main and target main match by full commit/tree and both workspaces are clean.
- Target contains complete durable task/spec/workflow/agent context and only GitHub remote.
- Target Codex acknowledges exact handoff SHA, cloud-only rule, remaining work and cleanup boundaries.
- Cleanup runbook names exact resolved paths/ownership/preservation status, protects shared Git metadata and WSL data.
- Any follow-up documentation commit is propagated and reverified before final clean-state claim.

## Out of scope
Blind pull/reset over new changes, blanket git clean, deleting the old common Git directory first or removing unrelated WSL/product data.

