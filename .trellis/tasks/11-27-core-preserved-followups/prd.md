# Review preserved core feature and diagnostic variants

## Goal

Plan future review of safe historical account-binding, project-config protection, harness/UI and diagnostic variants preserved during migration; do not activate these features as migration work.

## Requirements

- Preserve the reviewed authored differences from historical core branches and dirty linked worktrees as recoverable, non-executing research, with exact base commits, paths and content identities.
- Review account-binding and desktop-companion work as one feature contract; do not assume the missing App consumer APIs exist or enable incomplete imports.
- Review ProjectConfigGuard and explorer/cloud deletion integration separately from obsolete Trellis injection code already covered by current rules.
- Review harness/UI polish variants against the current accepted baseline, retaining original branch identities and failing-cloud evidence. Do not replace newer behavior merely because a historical branch is not an ancestor.
- Treat old branch-pinned CI, device probes and diagnostic tests as historical research. Any adopted behavior needs a new scoped implementation plan and hosted validation.
- Keep private captures, credentials and generated outputs exclusively in the external preservation copy. Never replay old staging/publication scripts.
- This task stays in planning. Migration authorizes source preservation and this plan, not implementation of these features. It is a follow-up to `11-26-github-cloud-workspace-migration`, not a prerequisite for closing the migration once safe preservation is complete.

## Acceptance Criteria

- [ ] Per-feature requirements and intended behavior are reviewed against current core/App contracts.
- [ ] Each selected historical change has a provenance/disposition row and a reviewed minimal patch or published-ref recovery path.
- [ ] Private/generated exclusions and any unrecoverable public-clone differences are stated explicitly; originals remain externally preserved.
- [ ] Separate implementation/check contexts and design are prepared before future activation.
- [ ] Future implementation uses GitHub-hosted analysis/tests/builds only and coordinates with affected App/native owners through Herdr.

## Notes

- Migration provenance: `../11-26-core-github-preservation/research/branch-dispositions.md` and `../11-26-core-github-preservation/research/root-wip-disposition.md`.
- Private recovery root: `D:/MyNewProjects/_migration-backup/qflistudio-core-20261127/`; original linked worktrees remain unchanged.
- The complete Git bundle preserves original history; safe source-only research patches, where supplied, are for future review and must not be applied automatically to main.
