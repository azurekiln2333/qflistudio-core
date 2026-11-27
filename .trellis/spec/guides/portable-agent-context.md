# Portable agent context

## Scope

Use when preserving Trellis or AI-agent setup across clones and machines. Version shared project behavior, not a user's complete local agent installation.

## Durable versus local state

Version project-wide `AGENTS.md`, `.trellis/workflow.md`, `.trellis/config.yaml` when project-specific, `.trellis/scripts/`, `.trellis/spec/`, task artifacts and research, workspace journals, and the reviewed portable agent adapter paths selected by this repository. Keep `.trellis/.developer`, `.trellis/.runtime/`, task/session pointers, `.trellis/.template-hashes.json`, credentials, machine trust files, caches and generated output local.

Agent roots commonly mix shareable instructions with machine-specific trust, logs, hooks, session state, user preferences and platform metadata. Apply explicit allowlists and inspect paths and content for absolute paths, secrets, authentication and private state. Do not stage a whole hidden directory just because some descendants are useful.

## Cross-platform duplicates

When a shared skill or command is rendered into multiple agent platforms, identify the canonical project copy and compare complete relative paths and content before deciding what to commit. Exact copies are generated platform variants, not independent source. Keep platform-specific differences only when that platform is deliberately supported and the files have been reviewed for portability. Preserve unreviewed or divergent variants in an external backup and document the limitation; do not resolve them by bulk copying.

## Validation

Check the candidate path allowlist and Git ignore behavior with read-only metadata. Confirm durable manifest links resolve in the clone. Do not run local builds or tests to validate agent setup; use hosted workflow evidence or static file comparison within the permitted cloud-only policy.

## Good / Base / Bad

- Good: share platform-neutral skills and reviewed adapter definitions under explicit paths while leaving local identity/trust state ignored.
- Base: keep an unreviewed platform-specific integration in its external preservation copy until an owner verifies it.
- Bad: recursively add every `.agent`, `.claude`, `.cursor`, `.codex`, or `.pi` file from a workstation.

## Wrong vs correct

Wrong: treat ignored status as proof that a file is disposable or, conversely, add every ignored file for completeness.

Correct: preserve first, classify by role and provenance, then version only the reviewed portable candidate set.
